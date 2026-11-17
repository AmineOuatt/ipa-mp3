import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '../models/models.dart';
import 'notification_service.dart';

class DownloadService {
  static final DownloadService _instance = DownloadService._internal();
  static DownloadService get instance => _instance;

  DownloadService._internal();

  final YoutubeExplode _yt = YoutubeExplode();
  final List<DownloadTask> _tasks = [];
  final StreamController<List<DownloadTask>> _tasksController =
      StreamController<List<DownloadTask>>.broadcast();

  final int _maxConcurrentDownloads = 2;
  int _activeCount = 0;

  void Function(SavedAudioEntry entry)? onAudioDownloaded;
  void Function(AudioGroup group)? onGroupCreated;

  Stream<List<DownloadTask>> get tasksStream => _tasksController.stream;
  List<DownloadTask> get tasks => List.unmodifiable(_tasks);

  void _notify() {
    _tasksController.add(List.unmodifiable(_tasks));
    _updateProgressNotification();
  }

  void _updateProgressNotification() {
    final active = _tasks.where((t) => t.isActive).toList();
    if (active.isEmpty) {
      NotificationService().cancelDownloadNotification();
      return;
    }

    final totalActive = active.length;
    final completedCount = _tasks.where((t) => t.isCompleted).length;
    final totalCount = _tasks.length;

    double avgProgress = 0.0;
    if (totalActive > 0) {
      avgProgress =
          active.map((t) => t.progress).reduce((a, b) => a + b) / totalActive;
    }

    final percent = (avgProgress * 100).toInt();

    NotificationService().showDownloadNotification(
      title: 'Downloading audio ($completedCount/$totalCount)',
      subtitle: '$percent% - ${active.first.title}',
      progress: percent,
      maxProgress: 100,
    );
  }

  Future<Video> fetchVideoMetadata(String url) async {
    final videoId = VideoId(url.trim());
    return await _yt.videos.get(videoId);
  }

  Future<Playlist> fetchPlaylistMetadata(String url) async {
    final playlistId = PlaylistId(url.trim());
    return await _yt.playlists.get(playlistId);
  }

  Future<List<Video>> fetchPlaylistVideos(String url) async {
    final playlistId = PlaylistId(url.trim());
    final videos = <Video>[];
    await for (final video in _yt.playlists.getVideos(playlistId)) {
      videos.add(video);
    }
    return videos;
  }

  String sanitizeFilename(String name) {
    return name
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  Future<void> enqueueSingleDownload({
    required Video video,
    String? targetGroupId,
    String? groupName,
  }) async {
    final existing = _tasks.indexWhere((t) => t.id == video.id.value);
    if (existing != -1 && _tasks[existing].isActive) {
      return;
    }

    final task = DownloadTask(
      id: video.id.value,
      url: video.url,
      title: video.title,
      author: video.author,
      thumbnailUrl: video.thumbnails.mediumResUrl,
      duration: video.duration,
      targetGroupId: targetGroupId,
      groupName: groupName,
    );

    _tasks.add(task);
    _notify();
    _processQueue();
  }

  Future<void> enqueuePlaylistDownload({
    required Playlist playlist,
    required List<Video> videos,
    required String customFolderName,
  }) async {
    final groupId = DateTime.now().millisecondsSinceEpoch.toString();
    final group = AudioGroup(id: groupId, name: customFolderName);
    onGroupCreated?.call(group);

    for (final video in videos) {
      final task = DownloadTask(
        id: video.id.value,
        url: video.url,
        title: video.title,
        author: video.author,
        thumbnailUrl: video.thumbnails.mediumResUrl,
        duration: video.duration,
        targetGroupId: groupId,
        groupName: customFolderName,
      );
      _tasks.add(task);
    }

    _notify();
    _processQueue();
  }

  Future<void> enqueueQuranReciterDownload({
    required String reciterName,
    required String serverUrl,
    required List<dynamic> suwarToDownload,
    String? customFolderName,
  }) async {
    final folder = customFolderName ?? reciterName;
    final groupId = DateTime.now().millisecondsSinceEpoch.toString();
    final group = AudioGroup(id: groupId, name: folder);
    onGroupCreated?.call(group);

    for (final s in suwarToDownload) {
      final surahIdStr = s['id'].toString().padLeft(3, '0');
      final url = "$serverUrl$surahIdStr.mp3";
      final title = "$reciterName - ${s['name']}";
      final taskId = "quran_${reciterName}_${s['id']}";

      // Avoid adding if already completed or active
      final existing = _tasks.indexWhere((t) => t.id == taskId);
      if (existing != -1 &&
          (_tasks[existing].isActive || _tasks[existing].isCompleted)) {
        continue;
      }

      final task = DownloadTask(
        id: taskId,
        url: url,
        title: title,
        author: reciterName,
        targetGroupId: groupId,
        groupName: folder,
      );
      _tasks.add(task);
    }

    _notify();
    _processQueue();
  }

  void _processQueue() {
    if (_activeCount >= _maxConcurrentDownloads) return;

    final pending = _tasks.where((t) => t.status == DownloadStatus.pending);
    for (final task in pending) {
      if (_activeCount >= _maxConcurrentDownloads) break;
      _startDownload(task);
    }
  }

  Future<void> _startDownload(DownloadTask task) async {
    task.status = DownloadStatus.downloading;
    _activeCount++;
    _notify();

    IOSink? outputSink;
    File? targetFile;

    try {
      final docDir = await getApplicationDocumentsDirectory();

      Directory saveDir;
      if (task.groupName != null && task.groupName!.isNotEmpty) {
        final sanitizedFolder = sanitizeFilename(task.groupName!);
        saveDir = Directory('${docDir.path}/audios/$sanitizedFolder');
      } else {
        saveDir = Directory('${docDir.path}/audios');
      }

      if (!await saveDir.exists()) {
        await saveDir.create(recursive: true);
      }

      final isDirectHttp =
          task.url.startsWith('http') &&
          (!task.url.contains('youtube.com') && !task.url.contains('youtu.be'));

      final safeTitle = sanitizeFilename(task.title);

      if (isDirectHttp) {
        final filePath = '${saveDir.path}/$safeTitle.mp3';
        targetFile = File(filePath);

        if (await targetFile.exists() && await targetFile.length() > 50000) {
          task.savedFilePath = filePath;
          task.progress = 1.0;
          task.status = DownloadStatus.completed;
          _activeCount--;
          _createAudioEntry(task, filePath);
          _notify();
          _processQueue();
          return;
        }

        outputSink = targetFile.openWrite();
        final request = http.Request('GET', Uri.parse(task.url));
        final response = await http.Client().send(request);
        final total = response.contentLength ?? 0;
        task.totalBytes = total;
        int count = 0;

        await for (final data in response.stream) {
          if (task.status == DownloadStatus.cancelled) {
            await outputSink.flush();
            await outputSink.close();
            if (await targetFile.exists()) {
              await targetFile.delete();
            }
            _activeCount--;
            _notify();
            _processQueue();
            return;
          }

          count += data.length;
          task.downloadedBytes = count;
          task.progress = total > 0 ? (count / total).clamp(0.0, 1.0) : 0.0;
          outputSink.add(data);
          _notify();
        }

        await outputSink.flush();
        await outputSink.close();

        task.savedFilePath = filePath;
        task.progress = 1.0;
        task.status = DownloadStatus.completed;

        _createAudioEntry(task, filePath);
      } else {
        // YouTube stream download
        final manifest = await _yt.videos.streamsClient.getManifest(
          VideoId(task.id),
        );
        final audioStreams = manifest.audioOnly.sortByBitrate();
        if (audioStreams.isEmpty) {
          throw Exception('No audio stream available for this video');
        }

        final streamInfo = audioStreams.last; // Highest bitrate audio
        final ext = streamInfo.container.name;
        final filePath = '${saveDir.path}/$safeTitle.$ext';
        targetFile = File(filePath);

        // Skip download if already exists with full size
        if (await targetFile.exists() &&
            await targetFile.length() >= streamInfo.size.totalBytes) {
          task.savedFilePath = filePath;
          task.progress = 1.0;
          task.status = DownloadStatus.completed;
          _activeCount--;

          _createAudioEntry(task, filePath);
          _notify();
          _processQueue();
          return;
        }

        outputSink = targetFile.openWrite();
        final stream = _yt.videos.streamsClient.get(streamInfo);
        final total = streamInfo.size.totalBytes;
        task.totalBytes = total;
        int count = 0;

        await for (final data in stream) {
          if (task.status == DownloadStatus.cancelled) {
            await outputSink.flush();
            await outputSink.close();
            if (await targetFile.exists()) {
              await targetFile.delete();
            }
            _activeCount--;
            _notify();
            _processQueue();
            return;
          }

          count += data.length;
          task.downloadedBytes = count;
          task.progress = total > 0 ? (count / total).clamp(0.0, 1.0) : 0.0;
          outputSink.add(data);
          _notify();
        }

        await outputSink.flush();
        await outputSink.close();

        task.savedFilePath = filePath;
        task.progress = 1.0;
        task.status = DownloadStatus.completed;

        _createAudioEntry(task, filePath);
      }
    } catch (e) {
      debugPrint('Download error for ${task.title}: $e');
      task.status = DownloadStatus.failed;
      task.error = e.toString();
      try {
        if (outputSink != null) await outputSink.close();
        if (targetFile != null && await targetFile.exists()) {
          await targetFile.delete();
        }
      } catch (_) {}
    } finally {
      _activeCount--;
      _notify();
      _processQueue();
    }
  }

  void _createAudioEntry(DownloadTask task, String filePath) {
    final entry = SavedAudioEntry(
      path: filePath,
      name: task.title,
      segments: [],
      groupId: task.targetGroupId,
      sourceReciterName: task.author,
    );
    onAudioDownloaded?.call(entry);
  }

  void cancelTask(String taskId) {
    final idx = _tasks.indexWhere((t) => t.id == taskId);
    if (idx != -1) {
      final task = _tasks[idx];
      if (task.isActive) {
        task.status = DownloadStatus.cancelled;
        _notify();
      } else {
        _tasks.removeAt(idx);
        _notify();
      }
    }
  }

  void cancelAll() {
    for (final task in _tasks) {
      if (task.isActive) {
        task.status = DownloadStatus.cancelled;
      }
    }
    _notify();
  }

  void retryTask(String taskId) {
    final idx = _tasks.indexWhere((t) => t.id == taskId);
    if (idx != -1) {
      final task = _tasks[idx];
      task.status = DownloadStatus.pending;
      task.error = null;
      task.progress = 0.0;
      _notify();
      _processQueue();
    }
  }

  void clearCompleted() {
    _tasks.removeWhere(
      (t) => t.isCompleted || t.status == DownloadStatus.cancelled,
    );
    _notify();
  }
}

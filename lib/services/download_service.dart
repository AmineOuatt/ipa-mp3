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

  void Function(SavedAudioEntry entry)? onAudioDownloaded;
  void Function(AudioGroup group)? onGroupCreated;

  Stream<List<DownloadTask>> get tasksStream => _tasksController.stream;
  List<DownloadTask> get tasks => List.unmodifiable(_tasks);

  int get activeCount =>
      _tasks.where((t) => t.status == DownloadStatus.downloading).length;

  void _notify() {
    _tasksController.add(List.unmodifiable(_tasks));
    _updateProgressNotification();
  }

  void _updateProgressNotification() {
    try {
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
    } catch (e) {
      debugPrint('Error updating download notification: $e');
    }
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
    final existingIndex = _tasks.indexWhere((t) => t.id == video.id.value);
    if (existingIndex != -1) {
      final existing = _tasks[existingIndex];
      if (existing.isActive) return;
      existing.status = DownloadStatus.pending;
      existing.progress = 0.0;
      existing.error = null;
      _notify();
      _processQueue();
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

  Future<void> enqueueSingleSurahDownload({
    required String reciterName,
    required dynamic surah,
    required String audioUrl,
    String? customFolderName,
  }) async {
    final surahId = surah['id'].toString();
    final surahName = surah['name'].toString();
    final taskId = "quran_${reciterName}_$surahId";
    final title = "$reciterName - $surahName";
    final folder = customFolderName ?? reciterName;

    final existingIndex = _tasks.indexWhere((t) => t.id == taskId);
    if (existingIndex != -1) {
      final existing = _tasks[existingIndex];
      if (existing.isActive) return;
      existing.status = DownloadStatus.pending;
      existing.progress = 0.0;
      existing.error = null;
      _notify();
      _processQueue();
      return;
    }

    final task = DownloadTask(
      id: taskId,
      url: audioUrl,
      title: title,
      author: reciterName,
      targetGroupId: null,
      groupName: folder,
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
      final existingIndex = _tasks.indexWhere((t) => t.id == video.id.value);
      if (existingIndex != -1) {
        final existing = _tasks[existingIndex];
        if (existing.isActive || existing.isCompleted) continue;
        existing.status = DownloadStatus.pending;
        existing.progress = 0.0;
        existing.error = null;
        continue;
      }

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

      // Avoid adding if already active or completed
      final existingIndex = _tasks.indexWhere((t) => t.id == taskId);
      if (existingIndex != -1) {
        final existing = _tasks[existingIndex];
        if (existing.isActive || existing.isCompleted) continue;
        existing.status = DownloadStatus.pending;
        existing.progress = 0.0;
        existing.error = null;
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
    final downloadingCount = activeCount;
    if (downloadingCount >= _maxConcurrentDownloads) return;

    final pending = _tasks
        .where((t) => t.status == DownloadStatus.pending)
        .toList();
    int slotsAvailable = _maxConcurrentDownloads - downloadingCount;

    for (final task in pending) {
      if (slotsAvailable <= 0) break;
      slotsAvailable--;
      _startDownload(task);
    }
  }

  Future<void> _startDownload(DownloadTask task) async {
    task.status = DownloadStatus.downloading;
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
          _createAudioEntry(task, filePath);
          return;
        }

        outputSink = targetFile.openWrite();
        final request = http.Request('GET', Uri.parse(task.url));
        final response = await http.Client().send(request);
        if (response.statusCode >= 400) {
          throw Exception('HTTP error ${response.statusCode}');
        }
        final total = response.contentLength ?? 0;
        task.totalBytes = total;
        int count = 0;
        int lastNotifiedMs = 0;
        double lastNotifiedProgress = 0.0;

        await for (final data in response.stream) {
          if (task.status == DownloadStatus.cancelled) {
            await outputSink.flush();
            await outputSink.close();
            if (await targetFile.exists()) {
              await targetFile.delete();
            }
            return;
          }

          count += data.length;
          task.downloadedBytes = count;
          task.progress = total > 0 ? (count / total).clamp(0.0, 1.0) : 0.0;
          outputSink.add(data);

          final nowMs = DateTime.now().millisecondsSinceEpoch;
          if ((task.progress - lastNotifiedProgress).abs() >= 0.02 ||
              (nowMs - lastNotifiedMs) >= 400) {
            lastNotifiedProgress = task.progress;
            lastNotifiedMs = nowMs;
            _notify();
          }
        }

        await outputSink.flush();
        await outputSink.close();

        task.savedFilePath = filePath;
        task.progress = 1.0;
        task.status = DownloadStatus.completed;

        _createAudioEntry(task, filePath);
      } else {
        // YouTube stream download
        VideoId videoId;
        try {
          videoId = VideoId(task.id);
        } catch (_) {
          videoId = VideoId(task.url);
        }

        final manifest = await _yt.videos.streamsClient.getManifest(videoId);

        // Find best audio stream (prefer mp4/m4a for iOS & Android universal support)
        final mp4Audios = manifest.audioOnly
            .where((s) => s.container.name.toLowerCase() == 'mp4')
            .sortByBitrate()
            .toList();

        StreamInfo? selectedStream;
        String ext = 'm4a';

        if (mp4Audios.isNotEmpty) {
          selectedStream = mp4Audios.first;
          ext = 'm4a';
        } else {
          final allAudios = manifest.audioOnly.sortByBitrate().toList();
          if (allAudios.isNotEmpty) {
            selectedStream = allAudios.first;
            ext = selectedStream.container.name.toLowerCase() == 'mp4'
                ? 'm4a'
                : selectedStream.container.name;
          } else if (manifest.muxed.isNotEmpty) {
            selectedStream = manifest.muxed.sortByBitrate().first;
            ext = 'mp4';
          }
        }

        if (selectedStream == null) {
          throw Exception('No playable audio stream available for this video');
        }

        final filePath = '${saveDir.path}/$safeTitle.$ext';
        targetFile = File(filePath);

        // Skip download if already exists with full size
        if (await targetFile.exists() &&
            await targetFile.length() >= selectedStream.size.totalBytes) {
          task.savedFilePath = filePath;
          task.progress = 1.0;
          task.status = DownloadStatus.completed;

          _createAudioEntry(task, filePath);
          return;
        }

        outputSink = targetFile.openWrite();
        final stream = _yt.videos.streamsClient.get(selectedStream);
        final total = selectedStream.size.totalBytes;
        task.totalBytes = total;
        int count = 0;
        int lastNotifiedMs = 0;
        double lastNotifiedProgress = 0.0;

        await for (final data in stream) {
          if (task.status == DownloadStatus.cancelled) {
            await outputSink.flush();
            await outputSink.close();
            if (await targetFile.exists()) {
              await targetFile.delete();
            }
            return;
          }

          count += data.length;
          task.downloadedBytes = count;
          task.progress = total > 0 ? (count / total).clamp(0.0, 1.0) : 0.0;
          outputSink.add(data);

          final nowMs = DateTime.now().millisecondsSinceEpoch;
          if ((task.progress - lastNotifiedProgress).abs() >= 0.02 ||
              (nowMs - lastNotifiedMs) >= 400) {
            lastNotifiedProgress = task.progress;
            lastNotifiedMs = nowMs;
            _notify();
          }
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

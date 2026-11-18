import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

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

  Future<Directory?> findFolderByPlaylistId(String playlistId) async {
    try {
      final docDir = await getApplicationDocumentsDirectory();
      final audiosDir = Directory('${docDir.path}/audios');
      if (!await audiosDir.exists()) return null;

      final entities = await audiosDir.list().toList();
      for (final entity in entities) {
        if (entity is Directory) {
          final metaFile = File('${entity.path}/.playlist.json');
          if (await metaFile.exists()) {
            try {
              final content = await metaFile.readAsString();
              final json = jsonDecode(content) as Map<String, dynamic>;
              if (json['playlistId'] == playlistId) {
                return entity;
              }
            } catch (_) {}
          }
        }
      }
    } catch (e) {
      debugPrint('Error searching for playlist folder: $e');
    }
    return null;
  }

  Future<void> _writePlaylistMetadataFile({
    required Directory saveDir,
    required String playlistId,
    required String playlistTitle,
    required List<Map<String, dynamic>> items,
  }) async {
    try {
      if (!await saveDir.exists()) {
        await saveDir.create(recursive: true);
      }
      final file = File('${saveDir.path}/.playlist.json');
      final data = {
        'playlistId': playlistId,
        'playlistTitle': playlistTitle,
        'totalItems': items.length,
        'updatedAt': DateTime.now().toIso8601String(),
        'items': items,
      };
      await file.writeAsString(jsonEncode(data), flush: true);
    } catch (e) {
      debugPrint('Error writing .playlist.json: $e');
    }
  }

  Future<void> _updateTaskInMetadata(DownloadTask task) async {
    if (task.groupName == null) return;
    try {
      final docDir = await getApplicationDocumentsDirectory();
      final sanitizedFolder = sanitizeFilename(task.groupName!);
      final metaFile = File('${docDir.path}/audios/$sanitizedFolder/.playlist.json');
      if (!await metaFile.exists()) return;

      final content = await metaFile.readAsString();
      final data = jsonDecode(content) as Map<String, dynamic>;
      final items = (data['items'] as List?)?.cast<Map<String, dynamic>>() ?? [];

      String statusStr;
      switch (task.status) {
        case DownloadStatus.completed:
          statusStr = 'done';
          break;
        case DownloadStatus.downloading:
          statusStr = 'downloading';
          break;
        case DownloadStatus.stopped:
        case DownloadStatus.paused:
          statusStr = 'stopped';
          break;
        case DownloadStatus.failed:
          statusStr = 'failed';
          break;
        case DownloadStatus.pending:
        case DownloadStatus.cancelled:
          statusStr = 'pending';
          break;
      }

      final idx = items.indexWhere(
        (it) => it['videoId'] == task.id || (task.playlistIndex != null && it['index'] == task.playlistIndex),
      );

      final filename = task.savedFilePath?.split(RegExp(r'[\\/]')).last ??
          (task.customFilename != null ? '${task.customFilename}.m4a' : '${task.title}.m4a');

      if (idx != -1) {
        items[idx]['status'] = statusStr;
        items[idx]['filename'] = filename;
      } else {
        items.add({
          'index': task.playlistIndex ?? (items.length + 1),
          'videoId': task.id,
          'title': task.title,
          'filename': filename,
          'status': statusStr,
        });
      }

      data['items'] = items;
      data['updatedAt'] = DateTime.now().toIso8601String();
      await metaFile.writeAsString(jsonEncode(data), flush: true);
    } catch (e) {
      debugPrint('Error updating .playlist.json for task ${task.id}: $e');
    }
  }

  void _setTaskStatus(DownloadTask task, DownloadStatus status) {
    task.status = status;
    _updateTaskInMetadata(task);
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

  Future<Map<String, int>> enqueuePlaylistDownload({
    required Playlist playlist,
    required List<Video> videos,
    required String customFolderName,
  }) async {
    final existingDir = await findFolderByPlaylistId(playlist.id.value);
    String folderName = customFolderName;
    Map<String, dynamic>? existingMeta;

    if (existingDir != null) {
      folderName = existingDir.path.split(RegExp(r'[\\/]')).last;
      try {
        final content = await File('${existingDir.path}/.playlist.json').readAsString();
        existingMeta = jsonDecode(content) as Map<String, dynamic>;
      } catch (_) {}
    }

    final totalCount = videos.length;
    final padLength = max(3, totalCount.toString().length);

    int skippedDone = 0;
    int remainingToDownload = 0;

    final docDir = await getApplicationDocumentsDirectory();
    final saveDir = Directory('${docDir.path}/audios/${sanitizeFilename(folderName)}');
    if (!await saveDir.exists()) {
      await saveDir.create(recursive: true);
    }

    final Map<String, Map<String, dynamic>> existingItemsByVideoId = {};
    if (existingMeta != null && existingMeta['items'] is List) {
      for (final item in (existingMeta['items'] as List)) {
        if (item is Map && item['videoId'] != null) {
          existingItemsByVideoId[item['videoId'].toString()] = Map<String, dynamic>.from(item);
        }
      }
    }

    final List<Map<String, dynamic>> metaItems = [];
    final List<DownloadTask> tasksToAdd = [];

    final groupId = playlist.id.value;
    final group = AudioGroup(id: groupId, name: folderName);
    onGroupCreated?.call(group);

    for (int i = 0; i < videos.length; i++) {
      final video = videos[i];
      final index = i + 1;
      final prefix = index.toString().padLeft(padLength, '0');
      final safeTitle = sanitizeFilename(video.title);
      final filenamePrefix = "$prefix - $safeTitle";

      final existingItemMeta = existingItemsByVideoId[video.id.value];
      bool isAlreadyDone = false;
      String? actualFilename = existingItemMeta?['filename']?.toString();

      if (existingItemMeta != null && existingItemMeta['status'] == 'done' && actualFilename != null) {
        final existingFile = File('${saveDir.path}/$actualFilename');
        if (await existingFile.exists() && await existingFile.length() > 1000) {
          isAlreadyDone = true;
          skippedDone++;
        }
      } else {
        if (await saveDir.exists()) {
          final matchingFiles = saveDir.listSync().whereType<File>().where((f) {
            final base = f.path.split(RegExp(r'[\\/]')).last;
            return base.startsWith('$prefix - ') && !base.endsWith('.part');
          }).toList();
          if (matchingFiles.isNotEmpty && matchingFiles.first.lengthSync() > 1000) {
            isAlreadyDone = true;
            actualFilename = matchingFiles.first.path.split(RegExp(r'[\\/]')).last;
            skippedDone++;
          }
        }
      }

      metaItems.add({
        'index': index,
        'videoId': video.id.value,
        'title': video.title,
        'filename': actualFilename ?? '$filenamePrefix.m4a',
        'status': isAlreadyDone ? 'done' : 'pending',
      });

      if (isAlreadyDone) {
        _createAudioEntry(
          DownloadTask(
            id: video.id.value,
            url: video.url,
            title: video.title,
            author: video.author,
            targetGroupId: groupId,
            groupName: folderName,
            playlistIndex: index,
            playlistTotal: totalCount,
            playlistId: playlist.id.value,
            playlistTitle: playlist.title,
            customFilename: filenamePrefix,
          ),
          '${saveDir.path}/$actualFilename',
        );
        continue;
      }

      remainingToDownload++;

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
        groupName: folderName,
        playlistIndex: index,
        playlistTotal: totalCount,
        playlistId: playlist.id.value,
        playlistTitle: playlist.title,
        customFilename: filenamePrefix,
      );
      tasksToAdd.add(task);
    }

    _tasks.addAll(tasksToAdd);

    await _writePlaylistMetadataFile(
      saveDir: saveDir,
      playlistId: playlist.id.value,
      playlistTitle: playlist.title,
      items: metaItems,
    );

    _notify();
    _processQueue();

    return {
      'skipped': skippedDone,
      'remaining': remainingToDownload,
    };
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

    final totalCount = suwarToDownload.length;
    final docDir = await getApplicationDocumentsDirectory();
    final saveDir = Directory('${docDir.path}/audios/${sanitizeFilename(folder)}');
    final List<Map<String, dynamic>> metaItems = [];

    for (int i = 0; i < suwarToDownload.length; i++) {
      final s = suwarToDownload[i];
      final surahNum = int.tryParse(s['id'].toString()) ?? (i + 1);
      final surahIdStr = s['id'].toString().padLeft(3, '0');
      final prefix = surahNum.toString().padLeft(3, '0');
      final url = "$serverUrl$surahIdStr.mp3";
      final safeTitle = sanitizeFilename(s['name']);
      final filenamePrefix = "$prefix - $safeTitle";
      final taskId = "quran_${reciterName}_${s['id']}";

      metaItems.add({
        'index': surahNum,
        'videoId': taskId,
        'title': "$reciterName - ${s['name']}",
        'filename': '$filenamePrefix.mp3',
        'status': 'pending',
      });

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
        title: "$reciterName - ${s['name']}",
        author: reciterName,
        targetGroupId: groupId,
        groupName: folder,
        playlistIndex: surahNum,
        playlistTotal: totalCount,
        playlistId: 'quran_$reciterName',
        playlistTitle: reciterName,
        customFilename: filenamePrefix,
      );
      _tasks.add(task);
    }

    await _writePlaylistMetadataFile(
      saveDir: saveDir,
      playlistId: 'quran_$reciterName',
      playlistTitle: reciterName,
      items: metaItems,
    );

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
    _setTaskStatus(task, DownloadStatus.downloading);
    _notify();

    IOSink? outputSink;
    File? partFile;
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
      final filenameBase = task.customFilename ?? safeTitle;

      if (isDirectHttp) {
        final filePath = '${saveDir.path}/$filenameBase.mp3';
        targetFile = File(filePath);
        partFile = File('$filePath.part');

        if (await targetFile.exists() && await targetFile.length() > 50000) {
          task.savedFilePath = filePath;
          task.progress = 1.0;
          _setTaskStatus(task, DownloadStatus.completed);
          _createAudioEntry(task, filePath);
          return;
        }

        if (await partFile.exists()) {
          await partFile.delete();
        }

        outputSink = partFile.openWrite();
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
            if (await partFile.exists()) {
              await partFile.delete();
            }
            return;
          }

          count += data.length;
          task.downloadedBytes = count;
          task.progress = total > 0 ? (count / total).clamp(0.0, 1.0) : 0.0;
          outputSink.add(data);

          final nowMs = DateTime.now().millisecondsSinceEpoch;
          if ((task.progress - lastNotifiedProgress).abs() >= 0.01 ||
              (nowMs - lastNotifiedMs) >= 100) {
            lastNotifiedProgress = task.progress;
            lastNotifiedMs = nowMs;
            _notify();
          }
        }

        await outputSink.flush();
        await outputSink.close();

        if (await partFile.exists()) {
          if (await targetFile.exists()) await targetFile.delete();
          await partFile.rename(targetFile.path);
        }

        task.savedFilePath = targetFile.path;
        task.progress = 1.0;
        _setTaskStatus(task, DownloadStatus.completed);

        _createAudioEntry(task, targetFile.path);
      } else {
        // YouTube stream download with fallback clients, candidates, and 15s timeout
        VideoId videoId;
        try {
          videoId = VideoId(task.id);
        } catch (_) {
          videoId = VideoId(task.url);
        }

        // 1. Fetch stream manifest with fallback clients and bypass watch page rate limiting
        StreamManifest? manifest;
        try {
          manifest = await _yt.videos.streamsClient.getManifest(
            videoId,
            ytClients: [YoutubeApiClient.android, YoutubeApiClient.ios],
            requireWatchPage: false,
          );
        } catch (_) {
          try {
            manifest = await _yt.videos.streamsClient.getManifest(
              videoId,
              ytClients: [YoutubeApiClient.androidSdkless],
              requireWatchPage: false,
            );
          } catch (_) {
            try {
              manifest = await _yt.videos.streamsClient.getManifest(
                videoId,
                requireWatchPage: false,
              );
            } catch (_) {
              manifest = await _yt.videos.streamsClient.getManifest(videoId);
            }
          }
        }

        if (manifest.streams.isEmpty) {
          throw Exception('No playable streams found for this YouTube video.');
        }

        // 2. Prioritize candidate streams:
        // Priority 1: Muxed MP4 (e.g. tag 18 / 360p mp4, unthrottled, instant CDN response, bypasses bot checks)
        // Priority 2: Audio-only MP4/M4A (highest bitrate)
        // Priority 3: Audio-only WebM (highest bitrate)
        // Priority 4: Any other muxed stream
        final candidates = <StreamInfo>[];

        final bestMuxedMp4 = manifest.muxed
            .where((s) => s.container.name.toLowerCase() == 'mp4')
            .sortByBitrate()
            .firstOrNull;
        if (bestMuxedMp4 != null) {
          candidates.add(bestMuxedMp4);
        }

        final bestAudioMp4 = manifest.audioOnly
            .where((s) => s.container.name.toLowerCase() == 'mp4')
            .sortByBitrate()
            .firstOrNull;
        if (bestAudioMp4 != null) {
          candidates.add(bestAudioMp4);
        }

        final bestAudioWebm = manifest.audioOnly
            .where((s) => s.container.name.toLowerCase() != 'mp4')
            .sortByBitrate()
            .firstOrNull;
        if (bestAudioWebm != null) {
          candidates.add(bestAudioWebm);
        }

        final otherMuxed = manifest.muxed
            .where((s) => s != bestMuxedMp4)
            .sortByBitrate()
            .firstOrNull;
        if (otherMuxed != null) {
          candidates.add(otherMuxed);
        }

        if (candidates.isEmpty) {
          throw Exception(
            'No audio or media streams available for this video.',
          );
        }

        bool downloadSuccess = false;
        String? lastStreamError;

        for (int i = 0; i < candidates.length; i++) {
          if (task.status == DownloadStatus.cancelled) return;

          final candidate = candidates[i];
          final isMuxed = candidate is MuxedStreamInfo;
          final isMp4 = candidate.container.name.toLowerCase() == 'mp4';
          final ext = isMuxed
              ? 'mp4'
              : (isMp4 ? 'm4a' : candidate.container.name);
          final filePath = '${saveDir.path}/$filenameBase.$ext';
          targetFile = File(filePath);
          partFile = File('$filePath.part');

          // Skip download if already exists with full size
          if (await targetFile.exists() &&
              await targetFile.length() >= candidate.size.totalBytes) {
            task.savedFilePath = filePath;
            task.progress = 1.0;
            task.downloadedBytes = candidate.size.totalBytes;
            task.totalBytes = candidate.size.totalBytes;
            _setTaskStatus(task, DownloadStatus.completed);
            _createAudioEntry(task, filePath);
            return;
          }

          task.totalBytes = candidate.size.totalBytes;
          task.downloadedBytes = 0;
          task.progress = 0.0;
          _notify();

          StreamSubscription<List<int>>? subscription;
          final firstChunkCompleter = Completer<bool>();
          final doneCompleter = Completer<void>();
          int receivedCount = 0;
          int lastNotifiedMs = 0;
          double lastNotifiedProgress = 0.0;

          try {
            if (await partFile.exists()) await partFile.delete();
            outputSink = partFile.openWrite();

            final stream = _yt.videos.streamsClient.get(candidate);

            subscription = stream.listen(
              (chunk) {
                if (!firstChunkCompleter.isCompleted) {
                  firstChunkCompleter.complete(true);
                }
                if (task.status == DownloadStatus.cancelled) {
                  return;
                }
                receivedCount += chunk.length;
                task.downloadedBytes = receivedCount;
                task.progress = (receivedCount / candidate.size.totalBytes)
                    .clamp(0.0, 1.0);
                outputSink?.add(chunk);

                final nowMs = DateTime.now().millisecondsSinceEpoch;
                if ((task.progress - lastNotifiedProgress).abs() >= 0.01 ||
                    (nowMs - lastNotifiedMs) >= 100) {
                  lastNotifiedProgress = task.progress;
                  lastNotifiedMs = nowMs;
                  _notify();
                }
              },
              onError: (e) {
                if (!firstChunkCompleter.isCompleted) {
                  firstChunkCompleter.complete(false);
                }
                if (!doneCompleter.isCompleted) doneCompleter.completeError(e);
              },
              onDone: () {
                if (!doneCompleter.isCompleted) doneCompleter.complete();
              },
              cancelOnError: true,
            );

            // 3.5-second timeout waiting for first chunk
            final gotFirstChunk = await firstChunkCompleter.future.timeout(
              const Duration(milliseconds: 3500),
              onTimeout: () => false,
            );

            if (!gotFirstChunk) {
              await subscription.cancel();
              await outputSink.flush();
              await outputSink.close();
              outputSink = null;
              if (await partFile.exists()) await partFile.delete();
              lastStreamError =
                  'Stream timed out with 0 bytes received (tag ${candidate.tag}). Trying alternate stream.';
              continue; // Try next candidate stream!
            }

            // Wait for download to finish
            await doneCompleter.future;
            await outputSink.flush();
            await outputSink.close();
            outputSink = null;

            if (task.status == DownloadStatus.cancelled) {
              if (await partFile.exists()) await partFile.delete();
              return;
            }

            if (receivedCount > 0 && await partFile.exists()) {
              if (await targetFile.exists()) await targetFile.delete();
              await partFile.rename(targetFile.path);

              task.savedFilePath = targetFile.path;
              task.progress = 1.0;
              task.downloadedBytes = candidate.size.totalBytes;
              _setTaskStatus(task, DownloadStatus.completed);

              _createAudioEntry(task, targetFile.path);
              downloadSuccess = true;
              break;
            }
          } catch (e) {
            lastStreamError = e.toString();
            try {
              await subscription?.cancel();
              if (outputSink != null) {
                await outputSink.close();
                outputSink = null;
              }
              if (await partFile.exists()) await partFile.delete();
            } catch (_) {}
          }
        }

        if (!downloadSuccess && task.status != DownloadStatus.cancelled) {
          throw Exception(
            lastStreamError ??
                'YouTube audio stream failed or was blocked by CDN. Please tap retry.',
          );
        }
      }
    } catch (e) {
      debugPrint('Download error for ${task.title}: $e');
      _setTaskStatus(task, DownloadStatus.failed);
      task.error = e.toString().replaceFirst('Exception: ', '');
      try {
        if (outputSink != null) await outputSink.close();
        if (partFile != null && await partFile.exists()) {
          await partFile.delete();
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
      playlistIndex: task.playlistIndex,
    );
    onAudioDownloaded?.call(entry);
  }

  void cancelTask(String taskId) {
    final idx = _tasks.indexWhere((t) => t.id == taskId);
    if (idx != -1) {
      final task = _tasks[idx];
      if (task.isActive) {
        _setTaskStatus(task, DownloadStatus.cancelled);
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
        _setTaskStatus(task, DownloadStatus.cancelled);
      }
    }
    _notify();
  }

  void retryTask(String taskId) {
    final idx = _tasks.indexWhere((t) => t.id == taskId);
    if (idx != -1) {
      final task = _tasks[idx];
      _setTaskStatus(task, DownloadStatus.pending);
      task.error = null;
      task.progress = 0.0;
      task.downloadedBytes = 0;
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

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart' as yt;

import '../../../../core/constants/app_colors.dart';
import '../../../../core/utils/duration_formatter.dart';
import '../../../../core/utils/file_size_formatter.dart';
import '../../../../models/models.dart';
import '../../../../services/download_service.dart';
import '../../../../shared/widgets/custom_audio_notification_bar.dart';
import '../widgets/download_queue_sheet.dart';

class YoutubeDownloadScreen extends StatefulWidget {
  const YoutubeDownloadScreen({super.key});

  @override
  State<YoutubeDownloadScreen> createState() => _YoutubeDownloadScreenState();
}

class _YoutubeDownloadScreenState extends State<YoutubeDownloadScreen> {
  final TextEditingController _urlController = TextEditingController();
  final DownloadService _downloadService = DownloadService.instance;

  bool _isLoading = false;
  String? _errorMessage;

  yt.Video? _previewVideo;
  yt.Playlist? _previewPlaylist;
  List<yt.Video>? _playlistVideos;

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null && data!.text!.trim().isNotEmpty) {
      _urlController.text = data.text!.trim();
      _analyzeUrl();
    }
  }

  bool _isPlaylistUrl(String url) {
    return url.contains('list=') || url.contains('playlist');
  }

  Future<void> _analyzeUrl() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _previewVideo = null;
      _previewPlaylist = null;
      _playlistVideos = null;
    });

    try {
      if (_isPlaylistUrl(url)) {
        final playlist = await _downloadService.fetchPlaylistMetadata(url);
        final videos = await _downloadService.fetchPlaylistVideos(url);
        if (mounted) {
          setState(() {
            _previewPlaylist = playlist;
            _playlistVideos = videos;
            _isLoading = false;
          });
        }
      } else {
        final video = await _downloadService.fetchVideoMetadata(url);
        if (mounted) {
          setState(() {
            _previewVideo = video;
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage =
              'Could not load YouTube URL. Please verify the link and internet connection.';
          _isLoading = false;
        });
      }
    }
  }

  void _downloadSingleVideo() {
    if (_previewVideo == null) return;
    _downloadService.enqueueSingleDownload(video: _previewVideo!);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Downloading: ${_previewVideo!.title}'),
        backgroundColor: AppColors.primaryGreen,
      ),
    );
    setState(() {
      _previewVideo = null;
      _urlController.clear();
    });
  }

  void _showPlaylistDownloadDialog() {
    if (_previewPlaylist == null || _playlistVideos == null) return;

    final folderController = TextEditingController(
      text: _downloadService.sanitizeFilename(_previewPlaylist!.title),
    );

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.cardBackground,
        title: const Text(
          'Download Playlist as Folder',
          style: TextStyle(color: Colors.white),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${_playlistVideos!.length} audio tracks will be downloaded.',
              style: const TextStyle(color: Colors.grey, fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: folderController,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Folder Name / Reciter',
                labelStyle: TextStyle(color: Colors.grey),
                enabledBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: Colors.grey),
                ),
                focusedBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: AppColors.primaryGreen),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            child: const Text('CANCEL', style: TextStyle(color: Colors.grey)),
            onPressed: () => Navigator.pop(context),
          ),
          TextButton(
            child: const Text(
              'START DOWNLOAD',
              style: TextStyle(color: AppColors.primaryGreen),
            ),
            onPressed: () async {
              final folder = folderController.text.trim();
              if (folder.isNotEmpty) {
                final scaffoldMessenger = ScaffoldMessenger.of(context);
                final playlist = _previewPlaylist!;
                final videos = _playlistVideos!;
                Navigator.pop(context);

                final result = await _downloadService.enqueuePlaylistDownload(
                  playlist: playlist,
                  videos: videos,
                  customFolderName: folder,
                );
                final skipped = result['skipped'] ?? 0;
                final remaining = result['remaining'] ?? 0;
                final msg = (skipped > 0)
                    ? '$skipped already downloaded, $remaining remaining'
                    : 'Queued $remaining tracks in folder "$folder"';

                scaffoldMessenger.showSnackBar(
                  SnackBar(
                    content: Text(msg),
                    backgroundColor: AppColors.primaryGreen,
                    action: SnackBarAction(
                      label: 'VIEW QUEUE',
                      textColor: Colors.black,
                      onPressed: () {
                        if (mounted) {
                          showDownloadQueue(context);
                        }
                      },
                    ),
                  ),
                );
                if (mounted) {
                  setState(() {
                    _previewPlaylist = null;
                    _playlistVideos = null;
                    _urlController.clear();
                  });
                }
              }
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      bottomNavigationBar: const CustomAudioNotificationBar(),
      appBar: AppBar(
        title: const Text('YouTube Audio Downloader'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: 'Clear completed',
            icon: const Icon(Icons.cleaning_services_outlined),
            onPressed: () => _downloadService.clearCompleted(),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _urlController,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          hintText: 'Paste YouTube video or playlist link...',
                          hintStyle: const TextStyle(color: Colors.grey),
                          filled: true,
                          fillColor: AppColors.cardBackground,
                          prefixIcon: const Icon(
                            Icons.link,
                            color: Colors.grey,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                        ),
                        onSubmitted: (_) => _analyzeUrl(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(
                        Icons.paste_rounded,
                        color: AppColors.primaryGreen,
                      ),
                      tooltip: 'Paste from clipboard',
                      onPressed: _pasteFromClipboard,
                    ),
                    IconButton(
                      icon: const Icon(Icons.search, color: Colors.white),
                      tooltip: 'Analyze URL',
                      onPressed: _analyzeUrl,
                    ),
                  ],
                ),
                if (_isLoading) ...[
                  const SizedBox(height: 16),
                  const LinearProgressIndicator(color: AppColors.primaryGreen),
                ],
                if (_errorMessage != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.withAlpha(40),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.redAccent.withAlpha(80)),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.error_outline,
                          color: Colors.redAccent,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                if (_previewVideo != null) ...[
                  const SizedBox(height: 12),
                  _buildVideoPreviewCard(_previewVideo!),
                ],
                if (_previewPlaylist != null && _playlistVideos != null) ...[
                  const SizedBox(height: 12),
                  _buildPlaylistPreviewCard(
                    _previewPlaylist!,
                    _playlistVideos!,
                  ),
                ],
              ],
            ),
          ),
          const Divider(color: Colors.white12, height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                const Text(
                  'Download Queue',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                StreamBuilder<List<DownloadTask>>(
                  stream: _downloadService.tasksStream,
                  initialData: _downloadService.tasks,
                  builder: (context, snapshot) {
                    final tasks = snapshot.data ?? [];
                    final hasActive = tasks.any((t) => t.isActive);
                    final hasStopped =
                        tasks.any((t) => t.isStopped || t.isFailed);
                    final hasCompleted = tasks.any((t) => t.isCompleted);

                    return Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (hasActive)
                          TextButton(
                            onPressed: () => _downloadService.stopAll(),
                            child: const Text(
                              'Stop All',
                              style: TextStyle(
                                color: Colors.orangeAccent,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        if (hasStopped)
                          TextButton(
                            onPressed: () => _downloadService.resumeAll(),
                            child: const Text(
                              'Resume All',
                              style: TextStyle(
                                color: AppColors.primaryGreen,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        if (hasCompleted)
                          TextButton(
                            onPressed: () => _downloadService.clearCompleted(),
                            child: const Text(
                              'Clear',
                              style:
                                  TextStyle(color: Colors.grey, fontSize: 12),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
          Expanded(
            child: StreamBuilder<List<DownloadTask>>(
              stream: _downloadService.tasksStream,
              initialData: _downloadService.tasks,
              builder: (context, snapshot) {
                final tasks = snapshot.data ?? [];
                if (tasks.isEmpty) {
                  return const Center(
                    child: Text(
                      'No downloads in queue.\nPaste a YouTube URL above to begin.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey, fontSize: 14),
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  itemCount: tasks.length,
                  itemBuilder: (context, index) {
                    final task = tasks[index];
                    return _buildTaskTile(task);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVideoPreviewCard(yt.Video video) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primaryGreen.withAlpha(60)),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.network(
              video.thumbnails.mediumResUrl,
              width: 80,
              height: 60,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                width: 80,
                height: 60,
                color: Colors.grey[800],
                child: const Icon(Icons.music_note, color: Colors.white),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  video.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  '${video.author} • ${formatDuration(video.duration ?? Duration.zero)}',
                  style: const TextStyle(color: Colors.grey, fontSize: 11),
                ),
              ],
            ),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryGreen,
              foregroundColor: Colors.black,
            ),
            onPressed: _downloadSingleVideo,
            icon: const Icon(Icons.download, size: 16),
            label: const Text('Download'),
          ),
        ],
      ),
    );
  }

  Widget _buildPlaylistPreviewCard(
    yt.Playlist playlist,
    List<yt.Video> videos,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primaryGreen.withAlpha(60)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: AppColors.primaryGreen.withAlpha(30),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.playlist_play,
                  color: AppColors.primaryGreen,
                  size: 36,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      playlist.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${playlist.author} • ${videos.length} videos',
                      style: const TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryGreen,
                foregroundColor: Colors.black,
              ),
              onPressed: _showPlaylistDownloadDialog,
              icon: const Icon(Icons.folder_zip_rounded),
              label: Text('Download Entire Playlist (${videos.length} tracks)'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTaskTile(DownloadTask task) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _buildStatusIcon(task.status),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      task.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (task.groupName != null)
                      Text(
                        'Folder: ${task.groupName}',
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 11,
                        ),
                      ),
                  ],
                ),
              ),
              if (task.isActive)
                IconButton(
                  icon: const Icon(
                    Icons.stop_circle_outlined,
                    color: Colors.orangeAccent,
                    size: 20,
                  ),
                  tooltip: 'Stop',
                  onPressed: () => _downloadService.stopTask(task.id),
                )
              else if (task.isStopped) ...[
                IconButton(
                  icon: const Icon(
                    Icons.play_circle_outline,
                    color: AppColors.primaryGreen,
                    size: 20,
                  ),
                  tooltip: 'Resume',
                  onPressed: () => _downloadService.resumeTask(task.id),
                ),
                IconButton(
                  icon: const Icon(
                    Icons.delete_outline,
                    color: Colors.redAccent,
                    size: 20,
                  ),
                  tooltip: 'Remove',
                  onPressed: () => _downloadService.removeTask(task.id),
                ),
              ] else if (task.isFailed) ...[
                IconButton(
                  icon: const Icon(
                    Icons.refresh,
                    color: Colors.orangeAccent,
                    size: 20,
                  ),
                  tooltip: 'Retry',
                  onPressed: () => _downloadService.resumeTask(task.id),
                ),
                IconButton(
                  icon: const Icon(
                    Icons.delete_outline,
                    color: Colors.redAccent,
                    size: 20,
                  ),
                  tooltip: 'Remove',
                  onPressed: () => _downloadService.removeTask(task.id),
                ),
              ] else if (task.isCompleted)
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.grey, size: 18),
                  tooltip: 'Remove',
                  onPressed: () => _downloadService.removeTask(task.id),
                ),
            ],
          ),
          if (task.status == DownloadStatus.downloading ||
              (task.isStopped && task.downloadedBytes > 0)) ...[
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: task.progress > 0 ? task.progress : null,
              backgroundColor: Colors.white12,
              color: task.isStopped
                  ? Colors.orangeAccent
                  : AppColors.primaryGreen,
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  task.isStopped
                      ? 'Stopped (${(task.progress * 100).toStringAsFixed(1)}%)'
                      : '${(task.progress * 100).toStringAsFixed(1)}%',
                  style: TextStyle(
                    color: task.isStopped ? Colors.orangeAccent : Colors.grey,
                    fontSize: 11,
                  ),
                ),
                Text(
                  '${formatFileSize(task.downloadedBytes)} / ${formatFileSize(task.totalBytes)}',
                  style: const TextStyle(color: Colors.grey, fontSize: 11),
                ),
              ],
            ),
          ] else if (task.isFailed) ...[
            const SizedBox(height: 4),
            Text(
              task.error ?? 'Download failed',
              style: const TextStyle(color: Colors.redAccent, fontSize: 11),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatusIcon(DownloadStatus status) {
    switch (status) {
      case DownloadStatus.pending:
        return const Icon(Icons.hourglass_empty, color: Colors.grey, size: 20);
      case DownloadStatus.downloading:
        return const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: AppColors.primaryGreen,
          ),
        );
      case DownloadStatus.completed:
        return const Icon(
          Icons.check_circle,
          color: AppColors.primaryGreen,
          size: 20,
        );
      case DownloadStatus.failed:
        return const Icon(Icons.error, color: Colors.redAccent, size: 20);
      case DownloadStatus.paused:
      case DownloadStatus.stopped:
        return const Icon(
          Icons.pause_circle,
          color: Colors.orangeAccent,
          size: 20,
        );
      case DownloadStatus.cancelled:
        return const Icon(Icons.cancel, color: Colors.grey, size: 20);
    }
  }
}

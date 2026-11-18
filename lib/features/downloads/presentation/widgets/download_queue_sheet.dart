import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../models/download_task.dart';
import '../../../../services/download_service.dart';

void showDownloadQueue(BuildContext context) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => const DownloadQueueSheet(),
  );
}

class DownloadQueueSheet extends StatelessWidget {
  const DownloadQueueSheet({super.key});

  String _formatFileSize(int bytes) {
    if (bytes <= 0) return '0 B';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
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

  @override
  Widget build(BuildContext context) {
    final downloadService = DownloadService.instance;

    return FractionallySizedBox(
      heightFactor: 0.75,
      child: Container(
        decoration: const BoxDecoration(
          color: Color(0xFF141414),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            // Handle bar
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 44,
              height: 5,
              decoration: BoxDecoration(
                color: Colors.grey[700],
                borderRadius: BorderRadius.circular(2.5),
              ),
            ),
            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  const Icon(
                    Icons.download_rounded,
                    color: AppColors.primaryGreen,
                    size: 24,
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Download Queue',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white70),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            // Global controls bar
            StreamBuilder<List<DownloadTask>>(
              stream: downloadService.tasksStream,
              initialData: downloadService.tasks,
              builder: (context, snapshot) {
                final tasks = snapshot.data ?? [];
                final hasActive = tasks.any((t) => t.isActive);
                final hasStopped = tasks.any((t) => t.isStopped || t.isFailed);
                final hasCompleted = tasks.any((t) => t.isCompleted);

                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (hasActive)
                        TextButton.icon(
                          onPressed: () => downloadService.stopAll(),
                          icon: const Icon(
                            Icons.stop_circle_outlined,
                            size: 16,
                            color: Colors.orangeAccent,
                          ),
                          label: const Text(
                            'Stop All',
                            style: TextStyle(
                              color: Colors.orangeAccent,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      if (hasStopped)
                        TextButton.icon(
                          onPressed: () => downloadService.resumeAll(),
                          icon: const Icon(
                            Icons.play_circle_outline,
                            size: 16,
                            color: AppColors.primaryGreen,
                          ),
                          label: const Text(
                            'Resume All',
                            style: TextStyle(
                              color: AppColors.primaryGreen,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      if (hasCompleted)
                        TextButton.icon(
                          onPressed: () => downloadService.clearCompleted(),
                          icon: const Icon(
                            Icons.clear_all,
                            size: 16,
                            color: Colors.grey,
                          ),
                          label: const Text(
                            'Clear Done',
                            style: TextStyle(color: Colors.grey, fontSize: 12),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
            const Divider(color: Colors.white12, height: 1),
            // Queue items
            Expanded(
              child: StreamBuilder<List<DownloadTask>>(
                stream: downloadService.tasksStream,
                initialData: downloadService.tasks,
                builder: (context, snapshot) {
                  final tasks = snapshot.data ?? [];
                  if (tasks.isEmpty) {
                    return const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.cloud_download_outlined,
                            size: 48,
                            color: Colors.grey,
                          ),
                          SizedBox(height: 12),
                          Text(
                            'No downloads in queue',
                            style: TextStyle(color: Colors.grey, fontSize: 14),
                          ),
                        ],
                      ),
                    );
                  }

                  return ListView.separated(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    itemCount: tasks.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final task = tasks[index];
                      return Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E1E1E),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: task.isActive
                                ? AppColors.primaryGreen.withAlpha(80)
                                : Colors.white10,
                          ),
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
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
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
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                    ],
                                  ),
                                ),
                                // Per-item controls
                                if (task.isActive) ...[
                                  IconButton(
                                    icon: const Icon(
                                      Icons.stop_circle_outlined,
                                      color: Colors.orangeAccent,
                                      size: 20,
                                    ),
                                    tooltip: 'Stop',
                                    onPressed: () =>
                                        downloadService.stopTask(task.id),
                                  ),
                                ] else if (task.isStopped) ...[
                                  IconButton(
                                    icon: const Icon(
                                      Icons.play_circle_outline,
                                      color: AppColors.primaryGreen,
                                      size: 20,
                                    ),
                                    tooltip: 'Resume',
                                    onPressed: () =>
                                        downloadService.resumeTask(task.id),
                                  ),
                                  IconButton(
                                    icon: const Icon(
                                      Icons.delete_outline,
                                      color: Colors.redAccent,
                                      size: 20,
                                    ),
                                    tooltip: 'Remove',
                                    onPressed: () =>
                                        downloadService.removeTask(task.id),
                                  ),
                                ] else if (task.isFailed) ...[
                                  IconButton(
                                    icon: const Icon(
                                      Icons.refresh,
                                      color: Colors.orangeAccent,
                                      size: 20,
                                    ),
                                    tooltip: 'Retry',
                                    onPressed: () =>
                                        downloadService.resumeTask(task.id),
                                  ),
                                  IconButton(
                                    icon: const Icon(
                                      Icons.delete_outline,
                                      color: Colors.redAccent,
                                      size: 20,
                                    ),
                                    tooltip: 'Remove',
                                    onPressed: () =>
                                        downloadService.removeTask(task.id),
                                  ),
                                ] else if (task.isCompleted) ...[
                                  IconButton(
                                    icon: const Icon(
                                      Icons.close,
                                      color: Colors.grey,
                                      size: 18,
                                    ),
                                    tooltip: 'Remove',
                                    onPressed: () =>
                                        downloadService.removeTask(task.id),
                                  ),
                                ],
                              ],
                            ),
                            if (task.status == DownloadStatus.downloading ||
                                (task.isStopped &&
                                    task.downloadedBytes > 0)) ...[
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
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    task.isStopped
                                        ? 'Stopped (${(task.progress * 100).toStringAsFixed(1)}%)'
                                        : '${(task.progress * 100).toStringAsFixed(1)}%',
                                    style: TextStyle(
                                      color: task.isStopped
                                          ? Colors.orangeAccent
                                          : Colors.grey,
                                      fontSize: 11,
                                    ),
                                  ),
                                  Text(
                                    '${_formatFileSize(task.downloadedBytes)} / ${_formatFileSize(task.totalBytes)}',
                                    style: const TextStyle(
                                      color: Colors.grey,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ] else if (task.isFailed) ...[
                              const SizedBox(height: 4),
                              Text(
                                task.error ?? 'Download failed',
                                style: const TextStyle(
                                  color: Colors.redAccent,
                                  fontSize: 11,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

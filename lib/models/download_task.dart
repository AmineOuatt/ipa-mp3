enum DownloadStatus {
  pending,
  downloading,
  completed,
  failed,
  paused,
  cancelled,
}

class DownloadTask {
  final String id;
  final String url;
  final String title;
  final String author;
  final String? thumbnailUrl;
  final Duration? duration;
  final String? targetGroupId;
  final String? groupName;

  DownloadStatus status;
  double progress; // 0.0 to 1.0
  int downloadedBytes;
  int totalBytes;
  String? savedFilePath;
  String? error;

  DownloadTask({
    required this.id,
    required this.url,
    required this.title,
    required this.author,
    this.thumbnailUrl,
    this.duration,
    this.targetGroupId,
    this.groupName,
    this.status = DownloadStatus.pending,
    this.progress = 0.0,
    this.downloadedBytes = 0,
    this.totalBytes = 0,
    this.savedFilePath,
    this.error,
  });

  bool get isActive =>
      status == DownloadStatus.pending || status == DownloadStatus.downloading;
  bool get isCompleted => status == DownloadStatus.completed;
  bool get isFailed => status == DownloadStatus.failed;
}

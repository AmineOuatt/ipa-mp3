import 'loop_bookmark.dart';

class SavedAudioEntry {
  final String path;
  String name;
  List<LoopBookmark> segments;
  String? groupId;
  String? sourceReciterName;
  String? sourceSurahName;
  String? sourceSurahId;
  int? playlistIndex;

  SavedAudioEntry({
    required this.path,
    required this.name,
    List<LoopBookmark>? segments,
    this.groupId,
    this.sourceReciterName,
    this.sourceSurahName,
    this.sourceSurahId,
    this.playlistIndex,
  }) : segments = segments ?? [];

  int get sortIndex {
    if (playlistIndex != null) return playlistIndex!;
    final base = path.split(RegExp(r'[\\/]')).last;
    final match = RegExp(r'^(\d+)').firstMatch(base);
    if (match != null) {
      return int.tryParse(match.group(1)!) ?? 999999;
    }
    return 999999;
  }

  Map<String, dynamic> toJson() => {
    'path': path,
    'name': name,
    'segments': segments.map((s) => s.toJson()).toList(),
    'groupId': groupId,
    'sourceReciterName': sourceReciterName,
    'sourceSurahName': sourceSurahName,
    'sourceSurahId': sourceSurahId,
    'playlistIndex': playlistIndex,
  };

  factory SavedAudioEntry.fromJson(Map<String, dynamic> json) =>
      SavedAudioEntry(
        path: json['path'],
        name: json['name'],
        segments: (json['segments'] as List)
            .map((s) => LoopBookmark.fromJson(s as Map<String, dynamic>))
            .toList(),
        groupId: json['groupId'],
        sourceReciterName: json['sourceReciterName'],
        sourceSurahName: json['sourceSurahName'],
        sourceSurahId: json['sourceSurahId'],
        playlistIndex: json['playlistIndex'] is int ? json['playlistIndex'] : null,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SavedAudioEntry &&
          runtimeType == other.runtimeType &&
          path == other.path;

  @override
  int get hashCode => path.hashCode;
}

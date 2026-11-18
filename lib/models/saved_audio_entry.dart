import 'loop_bookmark.dart';

class SavedAudioEntry {
  final String path;
  String name;
  List<LoopBookmark> segments;
  String? groupId;
  String? sourceReciterName;
  String? sourceSurahName;
  String? sourceSurahId;

  SavedAudioEntry({
    required this.path,
    required this.name,
    List<LoopBookmark>? segments,
    this.groupId,
    this.sourceReciterName,
    this.sourceSurahName,
    this.sourceSurahId,
  }) : segments = segments ?? [];

  Map<String, dynamic> toJson() => {
    'path': path,
    'name': name,
    'segments': segments.map((s) => s.toJson()).toList(),
    'groupId': groupId,
    'sourceReciterName': sourceReciterName,
    'sourceSurahName': sourceSurahName,
    'sourceSurahId': sourceSurahId,
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

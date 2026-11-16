class LoopBookmark {
  final String id;
  String name;
  Duration start;
  Duration end;

  LoopBookmark({
    required this.id,
    required this.name,
    required this.start,
    required this.end,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'start': start.inMilliseconds,
    'end': end.inMilliseconds,
  };

  factory LoopBookmark.fromJson(Map<String, dynamic> json) => LoopBookmark(
    id: json['id'],
    name: json['name'],
    start: Duration(milliseconds: json['start']),
    end: Duration(milliseconds: json['end']),
  );
}


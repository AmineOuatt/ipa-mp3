class AudioGroup {
  final String id;
  String name;
  bool isExpanded;

  AudioGroup({required this.id, required this.name, this.isExpanded = true});

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'isExpanded': isExpanded,
  };

  factory AudioGroup.fromJson(Map<String, dynamic> json) => AudioGroup(
    id: json['id'],
    name: json['name'],
    isExpanded: json['isExpanded'] ?? true,
  );
}


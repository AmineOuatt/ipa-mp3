import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';

import '../../../../core/constants/app_colors.dart';

class SurahSelectionScreen extends StatefulWidget {
  final String reciterName;
  final dynamic moshaf;
  final List<dynamic> suwarList;
  final String? initialSurahName;
  final String? initialSurahId;

  const SurahSelectionScreen({
    super.key,
    required this.reciterName,
    required this.moshaf,
    required this.suwarList,
    this.initialSurahName,
    this.initialSurahId,
  });

  @override
  State<SurahSelectionScreen> createState() => _SurahSelectionScreenState();
}

class _SurahSelectionScreenState extends State<SurahSelectionScreen> {
  String _searchQuery = "";
  bool _isDownloading = false;
  double _downloadProgress = 0.0;
  String? _downloadingSurahId;
  String? _expandedSurahId;
  String? _localDirPath;

  final AudioPlayer _player = AudioPlayer();
  bool _isPlayingPreview = false;
  StreamSubscription? _playerStateSubscription;
  StreamSubscription<List<int>>? _downloadSubscription;

  @override
  void initState() {
    super.initState();
    _initDir();
    final initialName = widget.initialSurahName;
    if (initialName != null && initialName.trim().isNotEmpty) {
      _searchQuery = initialName.trim();
    }
    final initialId = widget.initialSurahId;
    if (initialId != null && initialId.trim().isNotEmpty) {
      _expandedSurahId = initialId.trim();
    }
    _playerStateSubscription = _player.playerStateStream.listen((state) {
      if (mounted) {
        setState(() {
          _isPlayingPreview =
              state.playing &&
              state.processingState != ProcessingState.completed;
        });
      }
    });
  }

  Future<void> _initDir() async {
    final dir = await getApplicationDocumentsDirectory();
    if (mounted) {
      setState(() {
        _localDirPath = dir.path;
      });
    }
  }

  @override
  void dispose() {
    _playerStateSubscription?.cancel();
    _downloadSubscription?.cancel();
    _player.dispose();
    super.dispose();
  }

  Future<void> _previewAudio(String pathOrUrl) async {
    try {
      if (_player.playing) {
        await _player.pause();
      } else {
        if (pathOrUrl.startsWith('http')) {
          await _player.setUrl(pathOrUrl);
        } else {
          await _player.setFilePath(pathOrUrl);
        }
        await _player.play();
      }
    } catch (e) {
      if (mounted) setState(() => _isPlayingPreview = false);
    }
  }

  void _useAudioDirectly(dynamic surah, String audioPath) {
    String name = "${widget.reciterName} - ${surah['name']}";
    Navigator.pop(context, {
      'path': audioPath,
      'name': name,
      'sourceReciterName': widget.reciterName,
      'sourceSurahName': surah['name']?.toString(),
      'sourceSurahId': surah['id']?.toString(),
    });
  }

  Future<void> _deleteSurah(dynamic surah) async {
    if (_localDirPath == null) return;
    final filename = "${widget.reciterName}_${surah['name']}.mp3".replaceAll(
      RegExp(r'[\\/:*?"<>|]'),
      '',
    );
    final file = File('$_localDirPath/$filename');
    if (file.existsSync()) {
      try {
        file.deleteSync();
        if (mounted) setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Deleted Successfully"),
            backgroundColor: Colors.redAccent,
          ),
        );
      } catch (_) {
        // Ignore snackbar errors if widget unmounted
      }
    }
  }

  Future<void> _downloadSurah(dynamic surah, String finalUrl) async {
    setState(() {
      _isDownloading = true;
      _downloadingSurahId = surah['id'].toString();
    });

    try {
      final request = http.Request('GET', Uri.parse(finalUrl));
      final response = await http.Client().send(request);
      final total = response.contentLength ?? 0;

      int downloadedBytes = 0;
      List<int> bytes = [];

      response.stream.listen(
        (chunk) {
          bytes.addAll(chunk);
          downloadedBytes += chunk.length;
          if (total != 0) {
            setState(() {
              _downloadProgress = downloadedBytes / total;
            });
          }
        },
        onDone: () async {
          final dir = await getApplicationDocumentsDirectory();
          final filename = "${widget.reciterName}_${surah['name']}.mp3"
              .replaceAll(RegExp(r'[\\/:*?"<>|]'), '');
          final file = File('${dir.path}/$filename');
          await file.writeAsBytes(bytes);

          final displayName = "${widget.reciterName} - ${surah['name']}";

          if (mounted) {
            setState(() {
              _isDownloading = false;
              _downloadingSurahId = null;
            });
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text("Download Complete"),
                backgroundColor: AppColors.primary,
              ),
            );

            // Auto-switch main window/library entry from stream to offline file.
            Navigator.pop(context, {
              'path': file.path,
              'name': displayName,
              'sourceReciterName': widget.reciterName,
              'sourceSurahName': surah['name']?.toString(),
              'sourceSurahId': surah['id']?.toString(),
              'replaceStreamPath': finalUrl,
            });
          }
        },
        onError: (e) {
          setState(() {
            _isDownloading = false;
            _downloadingSurahId = null;
          });
        },
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _isDownloading = false;
          _downloadingSurahId = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final availableSurahs = widget.moshaf['surah_list'].toString().split(',');
    final filteredSuwar = widget.suwarList.where((s) {
      final name = s['name'].toString().toLowerCase();
      return availableSurahs.contains(s['id'].toString()) &&
          name.contains(_searchQuery.toLowerCase());
    }).toList();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          widget.reciterName,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
      ),
      body: Container(
        color: AppColors.background,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 16.0,
                vertical: 12.0,
              ),
              child: Container(
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: TextField(
                  style: const TextStyle(color: Colors.black, fontSize: 14),
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search, color: Colors.black54),
                    hintText: 'Search surah...',
                    hintStyle: TextStyle(color: Colors.black54),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(vertical: 10),
                  ),
                  onChanged: (val) {
                    setState(() {
                      _searchQuery = val;
                    });
                  },
                ),
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: filteredSuwar.length,
                padding: const EdgeInsets.only(bottom: 20),
                itemBuilder: (context, index) {
                  final s = filteredSuwar[index];
                  final surahIdStr = s['id'].toString().padLeft(3, '0');
                  final url = "${widget.moshaf['server']}$surahIdStr.mp3";

                  final filename = "${widget.reciterName}_${s['name']}.mp3"
                      .replaceAll(RegExp(r'[\\/:*?"<>|]'), '');
                  final bool fileExists =
                      _localDirPath != null &&
                      File('$_localDirPath/$filename').existsSync();

                  final isThisDownloading =
                      _isDownloading &&
                      _downloadingSurahId == s['id'].toString();
                  final isExpanded = _expandedSurahId == s['id'].toString();

                  return Column(
                    children: [
                      ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 4,
                        ),
                        leading: CircleAvatar(
                          backgroundColor: Colors.transparent,
                          child: Text(
                            s['id'].toString(),
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 16,
                            ),
                          ),
                        ),
                        title: Text(
                          s['name'],
                          style: TextStyle(
                            color: isExpanded
                                ? AppColors.primary
                                : Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        trailing: Icon(
                          isExpanded
                              ? Icons.keyboard_arrow_up
                              : Icons.more_horiz,
                          color: Colors.white54,
                        ),
                        onTap: () async {
                          setState(() {
                            if (isExpanded) {
                              _expandedSurahId = null;
                              if (_isPlayingPreview) {
                                _player.pause();
                                _isPlayingPreview = false;
                              }
                            } else {
                              if (_isPlayingPreview) {
                                _player.pause();
                                _isPlayingPreview = false;
                              }
                              _expandedSurahId = s['id'].toString();
                            }
                          });
                        },
                      ),
                      if (isExpanded)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          color: AppColors.background,
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  GestureDetector(
                                    onTap: () => _previewAudio(
                                      fileExists
                                          ? '$_localDirPath/$filename'
                                          : url,
                                    ),
                                    child: Container(
                                      width: 40,
                                      height: 40,
                                      decoration: const BoxDecoration(
                                        color: AppColors.primary,
                                        shape: BoxShape.circle,
                                      ),
                                      child: Icon(
                                        _isPlayingPreview
                                            ? Icons.pause
                                            : Icons.play_arrow,
                                        color: Colors.black,
                                        size: 28,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: StreamBuilder<Duration?>(
                                      stream: _player.positionStream,
                                      builder: (context, posSnap) {
                                        return StreamBuilder<Duration?>(
                                          stream: _player.durationStream,
                                          builder: (context, durSnap) {
                                            final pos =
                                                posSnap.data ?? Duration.zero;
                                            final dur =
                                                durSnap.data ?? Duration.zero;
                                            double max = dur.inMilliseconds
                                                .toDouble();
                                            double val = pos.inMilliseconds
                                                .toDouble();
                                            if (val > max) val = max;
                                            if (max == 0) max = 1;
                                            return SliderTheme(
                                              data: SliderTheme.of(context).copyWith(
                                                trackHeight: 4.0,
                                                thumbShape:
                                                    const RoundSliderThumbShape(
                                                      enabledThumbRadius: 6.0,
                                                    ),
                                                overlayShape:
                                                    const RoundSliderOverlayShape(
                                                      overlayRadius: 12.0,
                                                    ),
                                              ),
                                              child: Slider(
                                                value: val,
                                                max: max,
                                                activeColor: AppColors.primary,
                                                inactiveColor: Colors.white24,
                                                onChanged: (v) {
                                                  _player.seek(
                                                    Duration(
                                                      milliseconds: v.toInt(),
                                                    ),
                                                  );
                                                },
                                              ),
                                            );
                                          },
                                        );
                                      },
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Expanded(
                                    child: ElevatedButton(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.transparent,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            20,
                                          ),
                                          side: const BorderSide(
                                            color: AppColors.primary,
                                          ),
                                        ),
                                        foregroundColor: AppColors.primary,
                                      ),
                                      onPressed: () => _useAudioDirectly(
                                        s,
                                        fileExists
                                            ? '$_localDirPath/$filename'
                                            : url,
                                      ),
                                      child: Text(
                                        fileExists
                                            ? "Use Audio (Offline)"
                                            : "Use Audio (Stream)",
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  if (isThisDownloading)
                                    Padding(
                                      padding: const EdgeInsets.all(8.0),
                                      child: SizedBox(
                                        width: 24,
                                        height: 24,
                                        child: CircularProgressIndicator(
                                          value: _downloadProgress,
                                          color: AppColors.primary,
                                          strokeWidth: 3,
                                        ),
                                      ),
                                    )
                                  else if (fileExists)
                                    IconButton(
                                      icon: const Icon(
                                        Icons.delete_outline,
                                        color: Colors.redAccent,
                                      ),
                                      tooltip: "Delete",
                                      onPressed: () => _deleteSurah(s),
                                    )
                                  else
                                    IconButton(
                                      icon: const Icon(
                                        Icons.download_for_offline,
                                        color: Colors.white70,
                                      ),
                                      onPressed: () => _downloadSurah(s, url),
                                      tooltip: "Download",
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                    ],
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

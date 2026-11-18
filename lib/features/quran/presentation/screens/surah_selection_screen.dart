import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../services/audio_handler.dart';
import '../../../../services/download_service.dart';
import '../../../../shared/widgets/custom_audio_notification_bar.dart';
import '../../../downloads/presentation/screens/youtube_download_screen.dart';
import '../../../downloads/presentation/widgets/download_queue_sheet.dart';

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
  String? _expandedSurahId;
  String? _localDirPath;

  AudioPlayer get _player => appPlayer;
  bool _isPlayingPreview = false;
  StreamSubscription? _playerStateSubscription;
  StreamSubscription? _downloadSubscription;

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

    _downloadSubscription = DownloadService.instance.tasksStream.listen((_) {
      if (mounted) {
        setState(() {});
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
    super.dispose();
  }

  File? _getSurahLocalFile(dynamic surah) {
    if (_localDirPath == null) return null;
    final legacyFilename = "${widget.reciterName}_${surah['name']}.mp3"
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '');
    final f1 = File('$_localDirPath/$legacyFilename');
    if (f1.existsSync()) return f1;

    final safeTitle = DownloadService.instance.sanitizeFilename(
      "${widget.reciterName} - ${surah['name']}",
    );
    final safeFolder = DownloadService.instance.sanitizeFilename(
      widget.reciterName,
    );

    final f2 = File('$_localDirPath/audios/$safeFolder/$safeTitle.mp3');
    if (f2.existsSync()) return f2;

    final f3 = File('$_localDirPath/audios/$safeTitle.mp3');
    if (f3.existsSync()) return f3;

    return null;
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
    final file = _getSurahLocalFile(surah);
    if (file != null && file.existsSync()) {
      try {
        file.deleteSync();
        if (mounted) setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Deleted Successfully"),
            backgroundColor: Colors.redAccent,
          ),
        );
      } catch (_) {}
    }
  }

  Future<void> _downloadSurah(dynamic surah, String finalUrl) async {
    await DownloadService.instance.enqueueSingleSurahDownload(
      reciterName: widget.reciterName,
      surah: surah,
      audioUrl: finalUrl,
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Added to download queue: ${surah['name']}"),
          backgroundColor: AppColors.primary,
          duration: const Duration(seconds: 3),
          action: SnackBarAction(
            label: 'VIEW QUEUE',
            textColor: Colors.black,
            onPressed: () {
              showDownloadQueue(context);
            },
          ),
        ),
      );
      setState(() {});
    }
  }

  void _showDownloadAllSuwarDialog(List<dynamic> allAvailableSuwar) {
    final folderController = TextEditingController(text: widget.reciterName);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF181818),
        title: const Text(
          'Download Full Folder of Suwar',
          style: TextStyle(color: Colors.white),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Download all ${allAvailableSuwar.length} suwar of reciter "${widget.reciterName}" as a folder into your library.',
              style: const TextStyle(color: Colors.grey, fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: folderController,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Folder Name',
                labelStyle: TextStyle(color: Colors.grey),
                enabledBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: Colors.grey),
                ),
                focusedBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: AppColors.primary),
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
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.black,
            ),
            onPressed: () async {
              final folder = folderController.text.trim();
              if (folder.isNotEmpty) {
                final scaffoldMessenger = ScaffoldMessenger.of(context);
                final parentContext = context;
                Navigator.pop(context);
                final result =
                    await DownloadService.instance.enqueueQuranReciterDownload(
                  reciterName: widget.reciterName,
                  serverUrl: widget.moshaf['server'],
                  suwarToDownload: allAvailableSuwar,
                  customFolderName: folder,
                );
                final skipped = result['skipped'] ?? 0;
                final remaining = result['remaining'] ?? 0;
                final msg = (skipped > 0)
                    ? '$skipped already downloaded, $remaining remaining'
                    : 'Queued $remaining suwar in folder "$folder"';
                scaffoldMessenger.showSnackBar(
                  SnackBar(
                    content: Text(msg),
                    backgroundColor: AppColors.primary,
                    action: SnackBarAction(
                      label: 'VIEW QUEUE',
                      textColor: Colors.black,
                      onPressed: () {
                        showDownloadQueue(parentContext);
                      },
                    ),
                  ),
                );
              }
            },
            child: const Text('DOWNLOAD ALL'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final String surasListStr = widget.moshaf['surah_list']?.toString() ?? "";
    final List<String> availableSurahs = surasListStr.isNotEmpty
        ? surasListStr.split(',')
        : [];

    final filteredSuwar = widget.suwarList.where((s) {
      final name = s['name'].toString().toLowerCase();
      return availableSurahs.contains(s['id'].toString()) &&
          name.contains(_searchQuery.toLowerCase());
    }).toList();

    final allReciterSuwar = widget.suwarList.where((s) {
      return availableSurahs.contains(s['id'].toString());
    }).toList();

    return Scaffold(
      backgroundColor: AppColors.background,
      bottomNavigationBar: const CustomAudioNotificationBar(),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          widget.reciterName,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.download_rounded, color: Colors.white70),
            tooltip: 'View Download Queue',
            onPressed: () => showDownloadQueue(context),
          ),
          IconButton(
            icon: const Icon(
              Icons.download_for_offline_rounded,
              color: AppColors.primary,
              size: 26,
            ),
            tooltip: 'Download Full Folder of Suwar',
            onPressed: () => _showDownloadAllSuwarDialog(allReciterSuwar),
          ),
        ],
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

                  final localFile = _getSurahLocalFile(s);
                  final bool fileExists = localFile != null;
                  final String resolvedAudioPath = localFile?.path ?? url;

                  final taskId = "quran_${widget.reciterName}_${s['id']}";
                  final taskIndex = DownloadService.instance.tasks.indexWhere(
                    (t) => t.id == taskId,
                  );
                  final downloadTask = taskIndex != -1
                      ? DownloadService.instance.tasks[taskIndex]
                      : null;

                  final isThisDownloading =
                      downloadTask != null && downloadTask.isActive;
                  final double downloadProgress = downloadTask?.progress ?? 0.0;
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
                                    onTap: () =>
                                        _previewAudio(resolvedAudioPath),
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
                                        resolvedAudioPath,
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
                                          value: downloadProgress > 0
                                              ? downloadProgress
                                              : null,
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

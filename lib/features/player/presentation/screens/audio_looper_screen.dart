import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:audio_session/audio_session.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../models/models.dart';
import '../../../../services/audio_handler.dart';
import '../../../../services/download_service.dart';
import '../../../../services/notification_service.dart';
import '../../../../core/l10n/generated/app_localizations.dart';
import '../../../downloads/presentation/screens/youtube_download_screen.dart';
import '../../../library/presentation/widgets/group_dialogs.dart';
import '../../../library/presentation/widgets/library_panel.dart';
import '../../../quran/presentation/screens/quran_browser_screen.dart';
import '../../../settings/presentation/screens/settings_screen.dart';
import '../widgets/waveform_painter.dart';
import 'segment_player_screen.dart';

class AudioLooperScreen extends StatefulWidget {
  const AudioLooperScreen({super.key});

  @override
  State<AudioLooperScreen> createState() => _AudioLooperScreenState();
}

class _AudioLooperScreenState extends State<AudioLooperScreen> {
  late final AudioPlayer _player;
  SharedPreferences? _prefs;

  bool get _supportsLocalPlaybackNotification =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  List<SavedAudioEntry> _library = [];
  List<AudioGroup> _audioGroups = [];
  SavedAudioEntry? _currentEntry;

  bool _isPlaying = false;
  bool _isLooping = true;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  Duration _loopStart = Duration.zero;
  Duration _loopEnd = Duration.zero;
  String? _selectedSegmentId;

  List<double> _waveformSamples = [];
  String _segmentSearchQuery = "";

  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<Duration?>? _durationSubscription;
  StreamSubscription<PlayerState>? _playerStateSubscription;
  StreamSubscription? _noisySubscription;

  @override
  void initState() {
    super.initState();
    _player = appPlayer;
    _isPlaying = _player.playing;
    _position = _player.position;
    _duration = _player.duration ?? Duration.zero;
    _initApp();
  }

  Future<void> _initApp() async {
    _prefs = await SharedPreferences.getInstance();
    _loadLibrary();

    DownloadService.instance.onAudioDownloaded = (entry) {
      if (!mounted) return;
      setState(() {
        final existing = _library.indexWhere((e) => e.path == entry.path);
        if (existing == -1) {
          _library.add(entry);
        }
      });
      _saveLibrary();
    };

    DownloadService.instance.onGroupCreated = (group) {
      if (!mounted) return;
      setState(() {
        final existing = _audioGroups.indexWhere((g) => g.id == group.id);
        if (existing == -1) {
          _audioGroups.add(group);
        }
      });
      _saveLibrary();
    };

    if (_supportsLocalPlaybackNotification) {
      NotificationService().setActionCallback(_handleNotificationAction);
    }

    try {
      if (!kIsWeb &&
          (defaultTargetPlatform == TargetPlatform.android ||
              defaultTargetPlatform == TargetPlatform.iOS)) {
        final session = await AudioSession.instance;
        await session.configure(const AudioSessionConfiguration.music());
        _noisySubscription = session.becomingNoisyEventStream.listen((_) {
          _player.pause();
        });

        if (appAudioHandler != null) {
          appAudioHandler!.onSkipToNext = _skipToNextAudio;
          appAudioHandler!.onSkipToPrevious = _skipToPreviousAudio;
          appAudioHandler!.onStopRequested = _stopPlayback;
        }
      }
    } catch (e) {
      debugPrint('Audio session init skipped: $e');
    }

    try {
      _positionSubscription = _player.positionStream.listen(
        (pos) {
          if (!mounted) return;
          setState(() => _position = pos);

          // Auto-looping logic
          if (_isLooping && _loopEnd > Duration.zero && pos >= _loopEnd) {
            _player.seek(_loopStart);
          }

          // Update notification with current position
          if (_supportsLocalPlaybackNotification &&
              _isPlaying &&
              _currentEntry != null) {
            _showPlaybackNotification();
          }
        },
        onError: (error) {
          debugPrint("Position stream error: $error");
        },
      );

      _durationSubscription = _player.durationStream.listen(
        (dur) {
          if (!mounted) return;
          setState(() {
            _duration = dur ?? Duration.zero;
            if (_loopEnd == Duration.zero || _loopEnd > _duration) {
              _loopEnd = _duration;
            }
          });
        },
        onError: (error) {
          debugPrint("Duration stream error: $error");
        },
      );

      _playerStateSubscription = _player.playerStateStream.listen(
        (state) {
          if (!mounted) return;
          setState(() {
            _isPlaying = state.playing;
          });

          // Show/update notification when playing
          if (_supportsLocalPlaybackNotification &&
              state.playing &&
              _currentEntry != null) {
            _showPlaybackNotification();
          } else if (_supportsLocalPlaybackNotification && !state.playing) {
            // Cancel notification when paused/stopped
            NotificationService().cancelNotification();
          }

          if (state.processingState == ProcessingState.completed) {
            if (_isLooping) {
              _player.seek(_loopStart);
              _player.play();
            } else {
              _player.seek(Duration.zero);
              _player.pause();
            }
          }
        },
        onError: (error) {
          debugPrint("Player state stream error: $error");
        },
      );
    } catch (e) {
      debugPrint("Error initializing audio player: $e");
    }
  }

  bool _replaceStreamEntryWithOffline({
    required String offlinePath,
    required String offlineName,
    String? replaceStreamPath,
    String? sourceReciterName,
    String? sourceSurahId,
    String? sourceSurahName,
  }) {
    int index = -1;

    if (replaceStreamPath != null && replaceStreamPath.isNotEmpty) {
      index = _library.indexWhere((entry) => entry.path == replaceStreamPath);
    }

    if (index == -1 &&
        sourceReciterName != null &&
        sourceReciterName.isNotEmpty &&
        sourceSurahId != null &&
        sourceSurahId.isNotEmpty) {
      index = _library.indexWhere(
        (entry) =>
            (entry.path.startsWith('http://') ||
                entry.path.startsWith('https://')) &&
            (entry.sourceReciterName ?? '').trim() ==
                sourceReciterName.trim() &&
            (entry.sourceSurahId ?? '').trim() == sourceSurahId.trim(),
      );
    }

    if (index == -1) return false;

    final existing = _library[index];
    final updated = SavedAudioEntry(
      path: offlinePath,
      name: offlineName,
      segments: existing.segments,
      groupId: existing.groupId,
      sourceReciterName: sourceReciterName?.isNotEmpty == true
          ? sourceReciterName
          : existing.sourceReciterName,
      sourceSurahName: sourceSurahName?.isNotEmpty == true
          ? sourceSurahName
          : existing.sourceSurahName,
      sourceSurahId: sourceSurahId?.isNotEmpty == true
          ? sourceSurahId
          : existing.sourceSurahId,
    );

    setState(() {
      _library[index] = updated;
      if (_currentEntry?.path == existing.path) {
        _currentEntry = updated;
      }
    });

    return true;
  }

  void _loadLibrary() {
    try {
      final libraryJson = _prefs?.getString('library');
      final groupsJson = _prefs?.getString('audioGroups');

      if (libraryJson != null && libraryJson.isNotEmpty) {
        try {
          final List decoded = jsonDecode(libraryJson);
          setState(() {
            _library = decoded
                .map((e) {
                  try {
                    return SavedAudioEntry.fromJson(e as Map<String, dynamic>);
                  } catch (e) {
                    debugPrint("Error parsing library entry: $e");
                    return null;
                  }
                })
                .whereType<SavedAudioEntry>()
                .toList();
          });
        } catch (e) {
          debugPrint("Error decoding library JSON: $e");
        }
      }

      if (groupsJson != null && groupsJson.isNotEmpty) {
        try {
          final List decoded = jsonDecode(groupsJson);
          setState(() {
            _audioGroups = decoded
                .map((e) {
                  try {
                    return AudioGroup.fromJson(e as Map<String, dynamic>);
                  } catch (e) {
                    debugPrint("Error parsing group entry: $e");
                    return null;
                  }
                })
                .whereType<AudioGroup>()
                .toList();
          });
        } catch (e) {
          debugPrint("Error decoding groups JSON: $e");
        }
      }

      if (_currentEntry == null &&
          appAudioHandler?.mediaItem.value?.id != null) {
        final activeId = appAudioHandler!.mediaItem.value!.id;
        final match = _library.where((e) => e.path == activeId).firstOrNull;
        if (match != null) {
          setState(() {
            _currentEntry = match;
            _loopEnd = _player.duration ?? _duration;
          });
        }
      }
    } catch (e) {
      debugPrint("Error loading library: $e");
    }
  }

  Future<void> _saveLibrary() async {
    final libraryJson = jsonEncode(_library.map((e) => e.toJson()).toList());
    await _prefs?.setString('library', libraryJson);

    final groupsJson = jsonEncode(_audioGroups.map((g) => g.toJson()).toList());
    await _prefs?.setString('audioGroups', groupsJson);
  }

  void _skipToNextAudio() {
    if (_library.isEmpty) return;
    int idx = -1;
    if (_currentEntry != null) {
      idx = _library.indexWhere((e) => e.path == _currentEntry!.path);
    }
    final nextIdx = (idx == -1) ? 0 : (idx + 1) % _library.length;
    final next = _library[nextIdx];
    _loadFile(
      next.path,
      next.name,
      sourceReciterName: next.sourceReciterName,
      sourceSurahName: next.sourceSurahName,
      sourceSurahId: next.sourceSurahId,
    );
  }

  void _skipToPreviousAudio() {
    if (_library.isEmpty) return;
    int idx = -1;
    if (_currentEntry != null) {
      idx = _library.indexWhere((e) => e.path == _currentEntry!.path);
    }
    final prevIdx = (idx <= 0) ? _library.length - 1 : idx - 1;
    final prev = _library[prevIdx];
    _loadFile(
      prev.path,
      prev.name,
      sourceReciterName: prev.sourceReciterName,
      sourceSurahName: prev.sourceSurahName,
      sourceSurahId: prev.sourceSurahId,
    );
  }

  Future<void> _togglePlayPause() async {
    HapticFeedback.mediumImpact();
    if (_player.playing) {
      await _player.pause();
    } else {
      if (_player.processingState == ProcessingState.idle ||
          _player.processingState == ProcessingState.completed) {
        if (_currentEntry != null) {
          final resumePos = _position;
          final sourceUri =
              _currentEntry!.path.startsWith('http://') ||
                  _currentEntry!.path.startsWith('https://')
              ? Uri.parse(_currentEntry!.path)
              : Uri.file(_currentEntry!.path);
          try {
            await _player.setAudioSource(
              AudioSource.uri(sourceUri),
              initialPosition: resumePos,
            );
            await _player.setLoopMode(_isLooping ? LoopMode.one : LoopMode.off);
            await _player.play();
            return;
          } catch (e) {
            debugPrint("Error recovering audio source: $e");
          }
        }
      }
      await _player.play();
    }
  }

  void _stopPlayback() {
    HapticFeedback.mediumImpact();
    _player.stop();
    _player.seek(Duration.zero);
    setState(() {
      _isPlaying = false;
      _position = Duration.zero;
    });
    appAudioHandler?.stop();
  }

  void _consumeQuranBrowserResult(Map result) {
    final path = result['path']?.toString() ?? '';
    final filename = result['name']?.toString() ?? '';
    final sourceReciterName = result['sourceReciterName']?.toString();
    final sourceSurahName = result['sourceSurahName']?.toString();
    final sourceSurahId = result['sourceSurahId']?.toString();
    final replaceStreamPath = result['replaceStreamPath']?.toString();

    if (path.isEmpty || filename.isEmpty) return;

    final didReplaceStreamEntry = _replaceStreamEntryWithOffline(
      offlinePath: path,
      offlineName: filename,
      replaceStreamPath: replaceStreamPath,
      sourceReciterName: sourceReciterName,
      sourceSurahName: sourceSurahName,
      sourceSurahId: sourceSurahId,
    );

    if (didReplaceStreamEntry) {
      _saveLibrary();
      _loadFile(
        path,
        filename,
        sourceReciterName: sourceReciterName,
        sourceSurahName: sourceSurahName,
        sourceSurahId: sourceSurahId,
      );
      return;
    }

    final index = _library.indexWhere((entry) => entry.path == path);
    if (index == -1) {
      setState(() {
        _library.add(
          SavedAudioEntry(
            path: path,
            name: filename,
            segments: [],
            sourceReciterName: sourceReciterName,
            sourceSurahName: sourceSurahName,
            sourceSurahId: sourceSurahId,
          ),
        );
      });
      _saveLibrary();
      _loadFile(
        path,
        filename,
        sourceReciterName: sourceReciterName,
        sourceSurahName: sourceSurahName,
        sourceSurahId: sourceSurahId,
      );
    } else {
      // Audio already exists - show confirmation dialog
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: const Color(0xFF181818),
          title: const Text(
            'Audio Already in Library',
            style: TextStyle(color: Colors.white),
          ),
          content: Text(
            'This voice is already in your library:\n\n"${_library[index].name}"\n\nDo you want to use it again?',
            style: const TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              child: const Text('CANCEL', style: TextStyle(color: Colors.grey)),
              onPressed: () => Navigator.pop(context),
            ),
            TextButton(
              child: const Text(
                'USE ANYWAY',
                style: TextStyle(color: Color(0xFF1DB954)),
              ),
              onPressed: () {
                Navigator.pop(context);
                setState(() {
                  final existing = _library[index];
                  if (sourceReciterName != null &&
                      sourceReciterName.isNotEmpty) {
                    existing.sourceReciterName = sourceReciterName;
                  }
                  if (sourceSurahName != null && sourceSurahName.isNotEmpty) {
                    existing.sourceSurahName = sourceSurahName;
                  }
                  if (sourceSurahId != null && sourceSurahId.isNotEmpty) {
                    existing.sourceSurahId = sourceSurahId;
                  }
                });
                _saveLibrary();
                _loadFile(
                  path,
                  filename,
                  sourceReciterName: sourceReciterName,
                  sourceSurahName: sourceSurahName,
                  sourceSurahId: sourceSurahId,
                );
              },
            ),
          ],
        ),
      );
    }
  }

  void _openOnlineQuranBrowser() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const QuranBrowserMode(),
        fullscreenDialog: true,
      ),
    );

    // If an audio was selected and downloaded or used online
    if (result != null && result is Map) {
      _consumeQuranBrowserResult(result);
    }
  }

  IconData _getAudioStatusIcon(SavedAudioEntry entry) {
    // Streaming from network
    if (entry.path.startsWith('http://') || entry.path.startsWith('https://')) {
      return Icons.cloud_upload;
    }

    // Check if local file exists (downloaded)
    try {
      final file = File(entry.path);
      if (file.existsSync()) {
        return Icons.download_done; // Downloaded icon
      }
    } catch (e) {
      debugPrint("Error checking file: $e");
    }

    // File not found or error
    return Icons.album;
  }

  Color _getAudioStatusIconColor(SavedAudioEntry entry) {
    // Streaming from network
    if (entry.path.startsWith('http://') || entry.path.startsWith('https://')) {
      return const Color(0xFF1DB954); // Green for streaming
    }

    // Check if local file exists (downloaded)
    try {
      final file = File(entry.path);
      if (file.existsSync()) {
        return const Color(0xFF1DB954); // Green for downloaded
      }
    } catch (e) {
      debugPrint("Error checking file color: $e");
    }

    // File not found
    return Colors.grey;
  }

  void _openAudioSource(SavedAudioEntry entry) async {
    String? reciter = entry.sourceReciterName;
    String? surah = entry.sourceSurahName;

    // Fallback for older library items: try parsing "Reciter - Surah".
    if ((reciter == null || reciter.trim().isEmpty) &&
        entry.name.contains(' - ')) {
      final parts = entry.name.split(' - ');
      if (parts.isNotEmpty) {
        reciter = parts.first.trim();
      }
      if ((surah == null || surah.trim().isEmpty) && parts.length > 1) {
        surah = parts.sublist(1).join(' - ').trim();
      }
    }

    if (reciter == null || reciter.trim().isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Source location is not available for this audio.'),
        ),
      );
      return;
    }

    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => QuranBrowserMode(
          initialReciterName: reciter,
          initialSurahName: surah,
          initialSurahId: entry.sourceSurahId,
        ),
        fullscreenDialog: true,
      ),
    );

    if (result != null && result is Map) {
      _consumeQuranBrowserResult(result);
    }
  }

  Future<void> _importAudio() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['mp3', 'wav', 'm4a', 'aac', 'ogg', 'flac'],
    );

    if (result != null && result.files.single.path != null) {
      final path = result.files.single.path!;
      final name = result.files.single.name;

      _loadFile(path, name);
    }
  }

  Future<void> _loadFile(
    String path,
    String name, {
    String? sourceReciterName,
    String? sourceSurahName,
    String? sourceSurahId,
  }) async {
    try {
      // Validate path
      if (path.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Invalid audio path')));
        return;
      }

      // Guard: If the requested audio is already loaded and ready/playing, do not re-set source
      if (_currentEntry?.path == path &&
          _player.audioSource != null &&
          _player.processingState != ProcessingState.idle) {
        if (!_player.playing) {
          await _player.play();
        }
        return;
      }

      final sourceUri =
          path.startsWith('http://') || path.startsWith('https://')
          ? Uri.parse(path)
          : Uri.file(path);

      await _player.setAudioSource(AudioSource.uri(sourceUri));
      await _player.setLoopMode(_isLooping ? LoopMode.one : LoopMode.off);

      // Update library
      int index = _library.indexWhere((e) => e.path == path);
      SavedAudioEntry entry;
      if (index == -1) {
        entry = SavedAudioEntry(
          path: path,
          name: name,
          sourceReciterName: sourceReciterName,
          sourceSurahName: sourceSurahName,
          sourceSurahId: sourceSurahId,
        );
        _library.add(entry);
      } else {
        entry = _library[index];
        if (sourceReciterName?.isNotEmpty == true) {
          entry.sourceReciterName = sourceReciterName;
        }
        if (sourceSurahName?.isNotEmpty == true) {
          entry.sourceSurahName = sourceSurahName;
        }
        if (sourceSurahId?.isNotEmpty == true) {
          entry.sourceSurahId = sourceSurahId;
        }
      }

      setState(() {
        _currentEntry = entry;
        _loopStart = Duration.zero;
        _loopEnd = _player.duration ?? _duration;
        _selectedSegmentId = null;
      });

      await publishNowPlayingMetadata(
        id: path,
        title: name,
        artist: sourceReciterName ?? 'MP360',
        duration: _player.duration ?? _duration,
      );

      _saveLibrary();
      _generateWaveform(path);

      // Delay play to ensure audio is ready
      Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted) {
          _player.play();
        }
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not load audio: $e')));
      debugPrint("Error loading file: $e");
    }
  }

  Future<void> _generateWaveform(String path) async {
    // A VERY simplified mock waveform generation for local files.
    // In a real app with just_audio, you might need a platform channel or a heavier dart package to decode PCM bytes.
    // Here we generate 96 mock values for demonstration purposes, mimicking a downsampled byte array.
    final rand = Random();
    List<double> samples = List.generate(
      96,
      (index) => rand.nextDouble() * 0.8 + 0.2,
    );

    setState(() {
      _waveformSamples = samples;
    });
  }

  void _upsertAudioEntry() {
    if (_currentEntry != null) {
      int index = _library.indexWhere((e) => e.path == _currentEntry!.path);
      if (index != -1) {
        _library[index] = _currentEntry!;
        _saveLibrary();
      }
    }
  }

  void _seekBy(Duration offset) {
    final target = _position + offset;
    final clamped = target < Duration.zero
        ? Duration.zero
        : (target > _duration ? _duration : target);
    _player.seek(clamped);
  }

  void _saveSegment() {
    if (_currentEntry == null) return;

    HapticFeedback.mediumImpact();
    TextEditingController controller = TextEditingController(
      text: "Segment ${_currentEntry!.segments.length + 1}",
    );

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF181818),
        title: const Text(
          'Save Loop Segment',
          style: TextStyle(color: Colors.white),
        ),
        content: TextField(
          controller: controller,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: "Enter segment name",
            hintStyle: TextStyle(color: Colors.grey),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.grey),
            ),
            focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: Color(0xFF1DB954)),
            ),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            child: const Text('CANCEL', style: TextStyle(color: Colors.grey)),
            onPressed: () => Navigator.pop(context),
          ),
          TextButton(
            child: const Text(
              'SAVE',
              style: TextStyle(color: Color(0xFF1DB954)),
            ),
            onPressed: () {
              final newBookmark = LoopBookmark(
                id: DateTime.now().millisecondsSinceEpoch.toString(),
                name: controller.text.trim(),
                start: _loopStart,
                end: _loopEnd,
              );
              setState(() {
                _currentEntry!.segments.add(newBookmark);
              });
              _upsertAudioEntry();
              Navigator.pop(context);
            },
          ),
        ],
      ),
    );
  }

  void _deleteSegment(LoopBookmark segment) {
    setState(() {
      _currentEntry?.segments.removeWhere((s) => s.id == segment.id);
    });
    _upsertAudioEntry();
  }

  void _editSegmentName(LoopBookmark segment) {
    TextEditingController controller = TextEditingController(
      text: segment.name,
    );
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF181818),
        title: const Text(
          'Edit Segment Name',
          style: TextStyle(color: Colors.white),
        ),
        content: TextField(
          controller: controller,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: "Enter new name",
            hintStyle: TextStyle(color: Colors.grey),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.grey),
            ),
            focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: Color(0xFF1DB954)),
            ),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            child: const Text('CANCEL', style: TextStyle(color: Colors.grey)),
            onPressed: () => Navigator.pop(context),
          ),
          TextButton(
            child: const Text(
              'SAVE',
              style: TextStyle(color: Color(0xFF1DB954)),
            ),
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                setState(() {
                  segment.name = controller.text.trim();
                });
                _upsertAudioEntry();
              }
              Navigator.pop(context);
            },
          ),
        ],
      ),
    );
  }

  void _editLibraryAudioName(SavedAudioEntry entry) {
    GroupDialogs.showEditAudioName(
      context,
      currentName: entry.name,
      onSaved: (name) {
        setState(() {
          entry.name = name;
        });
        _saveLibrary();
      },
    );
  }

  void _moveAudioToGroup(SavedAudioEntry entry) {
    GroupDialogs.showMoveAudioToGroup(
      context,
      entry: entry,
      groups: _audioGroups,
      onSelected: (groupId) {
        setState(() {
          entry.groupId = groupId;
        });
        _saveLibrary();
      },
    );
  }

  void _editAudioName() {
    if (_currentEntry == null) return;
    GroupDialogs.showEditAudioName(
      context,
      currentName: _currentEntry!.name,
      onSaved: (name) {
        setState(() {
          _currentEntry!.name = name;
        });
        _upsertAudioEntry();
      },
    );
  }

  void _createNewGroup() {
    GroupDialogs.showCreateGroup(
      context,
      onCreated: (name) {
        setState(() {
          _audioGroups.add(
            AudioGroup(
              id: DateTime.now().millisecondsSinceEpoch.toString(),
              name: name,
            ),
          );
        });
        _saveLibrary();
      },
    );
  }

  void _renameGroup(AudioGroup group) {
    GroupDialogs.showRenameGroup(
      context,
      group: group,
      onRenamed: (name) {
        setState(() {
          group.name = name;
        });
        _saveLibrary();
      },
    );
  }

  void _deleteGroup(AudioGroup group) {
    // Move all items in group to ungrouped
    for (var item in _library) {
      if (item.groupId == group.id) {
        item.groupId = null;
      }
    }
    setState(() {
      _audioGroups.removeWhere((g) => g.id == group.id);
    });
    _saveLibrary();
  }

  void _showAddAudiosToGroup(AudioGroup group) {
    GroupDialogs.showAddAudiosToGroup(
      context,
      group: group,
      library: _library,
      onAdded: (selected) {
        setState(() {
          for (final path in selected) {
            final idx = _library.indexWhere((a) => a.path == path);
            if (idx != -1) {
              _library[idx].groupId = group.id;
            }
          }
        });
        _saveLibrary();
      },
    );
  }

  void _openLibraryPanel() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return LibraryPanel(
              library: _library,
              audioGroups: _audioGroups,
              currentEntry: _currentEntry,
              onSelectAudio: (item) {
                Navigator.pop(context);
                _loadFile(
                  item.path,
                  item.name,
                  sourceReciterName: item.sourceReciterName,
                  sourceSurahName: item.sourceSurahName,
                  sourceSurahId: item.sourceSurahId,
                );
              },
              onCreateGroup: () {
                Navigator.pop(context);
                _createNewGroup();
              },
              onAddAudiosToGroup: (group) => _showAddAudiosToGroup(group),
              onRenameGroup: (group) => _renameGroup(group),
              onDeleteGroup: (group) {
                _deleteGroup(group);
                setModalState(() {});
              },
              onToggleGroupExpanded: (group) {
                setState(() {
                  group.isExpanded = !group.isExpanded;
                });
                setModalState(() {});
              },
              onOpenAudioSource: (item) => _openAudioSource(item),
              onMoveAudioToGroup: (item) => _moveAudioToGroup(item),
              onEditAudioName: (item) => _editLibraryAudioName(item),
              onDeleteAudio: (item) {
                setState(() {
                  _library.remove(item);
                  if (_currentEntry == item) {
                    _currentEntry = null;
                    _player.stop();
                  }
                });
                _saveLibrary();
                setModalState(() {});
              },
              getAudioStatusIcon: _getAudioStatusIcon,
              getAudioStatusIconColor: _getAudioStatusIconColor,
            );
          },
        );
      },
    );
  }

  void _openSegmentPlayer(int initialIndex) {
    if (_currentEntry == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SegmentPlayerScreen(
          player: _player,
          segments: _currentEntry!.segments,
          initialIndex: initialIndex,
          trackName: _currentEntry?.name ?? 'Unknown Track',
          onSegmentsUpdated: _upsertAudioEntry,
        ),
      ),
    );
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes;
    final seconds = d.inSeconds % 60;
    final ms = (d.inMilliseconds % 1000) ~/ 100;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}.$ms';
  }

  void _showPlaybackNotification() {
    if (!_supportsLocalPlaybackNotification) return;
    if (_currentEntry == null) return;

    final currentTime = _formatDuration(_position);
    final totalTime = _formatDuration(_duration);
    final subtitle =
        '${_isPlaying ? "Playing" : "Paused"} â€¢ $currentTime / $totalTime';

    NotificationService().showPlaybackNotification(
      title: _currentEntry!.name,
      subtitle: subtitle,
      isPlaying: _isPlaying,
    );
  }

  void _handleNotificationAction(String action) {
    if (!mounted) return;

    switch (action) {
      case 'play_pause':
        _isPlaying ? _player.pause() : _player.play();
        break;
      case 'prev_segment':
        _seekBy(const Duration(seconds: -5));
        break;
      case 'next_segment':
        _seekBy(const Duration(seconds: 5));
        break;
      case 'stop':
        _player.stop();
        NotificationService().cancelNotification();
        break;
    }
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    _durationSubscription?.cancel();
    _playerStateSubscription?.cancel();
    _noisySubscription?.cancel();
    // Do NOT dispose _player! The single global AudioPlayer lives for the full app lifetime.
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: GestureDetector(
          onTap: _editAudioName,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  _currentEntry?.name ??
                      (AppLocalizations.of(context)?.noAudioLoaded ??
                          "No Audio Loaded"),
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (_currentEntry != null) ...[
                const SizedBox(width: 8),
                const Icon(Icons.edit, size: 16, color: Colors.grey),
              ],
            ],
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.menu),
          onPressed: _openLibraryPanel,
        ),
        actions: [
          IconButton(
            tooltip: "YouTube Downloader",
            icon: const Icon(
              Icons.cloud_download_rounded,
              color: Color(0xFF1DB954),
            ),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const YoutubeDownloadScreen(),
                ),
              );
            },
          ),
          IconButton(
            tooltip: "Browse Quran API",
            icon: const Icon(Icons.cloud_outlined, color: Colors.white),
            onPressed: _openOnlineQuranBrowser,
          ),
          IconButton(
            icon: const Icon(Icons.file_upload, color: Color(0xFF1DB954)),
            onPressed: _importAudio,
          ),
          IconButton(
            tooltip: "Settings",
            icon: const Icon(Icons.settings_outlined, color: Colors.white70),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Upper Workspace: Waveform & Playback Controls
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Waveform Container
                  GestureDetector(
                    onTapDown: (details) {
                      if (_duration == Duration.zero) return;
                      final percent =
                          details.localPosition.dx /
                          MediaQuery.of(context).size.width;
                      final newPos = Duration(
                        milliseconds: (_duration.inMilliseconds * percent)
                            .toInt(),
                      );
                      _player.seek(newPos);
                    },
                    child: Container(
                      height: 72,
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF181818).withAlpha(230),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: CustomPaint(
                        painter: WaveformPainter(
                          samples: _waveformSamples,
                          positionPercent: _duration.inMilliseconds > 0
                              ? _position.inMilliseconds /
                                    _duration.inMilliseconds
                              : 0,
                          loopStartPercent: _duration.inMilliseconds > 0
                              ? _loopStart.inMilliseconds /
                                    _duration.inMilliseconds
                              : 0,
                          loopEndPercent: _duration.inMilliseconds > 0
                              ? _loopEnd.inMilliseconds /
                                    _duration.inMilliseconds
                              : 1.0,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Range Slider
                  SizedBox(
                    height: 88,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        RangeSlider(
                          values: RangeValues(
                            _duration.inMilliseconds > 0
                                ? _loopStart.inMilliseconds /
                                      _duration.inMilliseconds
                                : 0,
                            _duration.inMilliseconds > 0
                                ? _loopEnd.inMilliseconds /
                                      _duration.inMilliseconds
                                : 1.0,
                          ),
                          min: 0.0,
                          max: 1.0,
                          activeColor: const Color(0xFF1DB954),
                          inactiveColor: Colors.grey[800],
                          onChanged: (values) {
                            setState(() {
                              _loopStart = Duration(
                                milliseconds:
                                    (_duration.inMilliseconds * values.start)
                                        .toInt(),
                              );
                              _loopEnd = Duration(
                                milliseconds:
                                    (_duration.inMilliseconds * values.end)
                                        .toInt(),
                              );
                            });
                            if (_position < _loopStart ||
                                _position > _loopEnd) {
                              _player.seek(_loopStart);
                            }
                          },
                        ),

                        // Timestamps
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16.0),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                _formatDuration(_loopStart),
                                style: const TextStyle(color: Colors.grey),
                              ),
                              Text(
                                _formatDuration(_loopEnd),
                                style: const TextStyle(color: Colors.grey),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),

                  // Set Bounds Controls & Secondary Actions
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      IconButton(
                        tooltip: "Loop mode",
                        icon: Icon(
                          _isLooping ? Icons.repeat_on : Icons.repeat,
                          color: _isLooping
                              ? const Color(0xFF1DB954)
                              : Colors.grey,
                          size: 22,
                        ),
                        onPressed: () {
                          HapticFeedback.selectionClick();
                          setState(() => _isLooping = !_isLooping);
                          _player.setLoopMode(
                            _isLooping ? LoopMode.one : LoopMode.off,
                          );
                        },
                      ),
                      _buildControlBtn("Set Start", () {
                        HapticFeedback.mediumImpact();
                        setState(() {
                          _loopStart = _position;
                          if (_loopStart > _loopEnd) _loopEnd = _duration;
                          _selectedSegmentId = null;
                        });
                      }),
                      _buildControlBtn("Reset", () {
                        HapticFeedback.mediumImpact();
                        setState(() {
                          _loopStart = Duration.zero;
                          _loopEnd = _duration;
                          _selectedSegmentId = null;
                        });
                        _player.seek(Duration.zero);
                        _player.setLoopMode(
                          _isLooping ? LoopMode.one : LoopMode.off,
                        );
                      }),
                      _buildControlBtn("Set End", () {
                        HapticFeedback.mediumImpact();
                        setState(() {
                          _loopEnd = _position;
                          if (_loopEnd < _loopStart) {
                            _loopStart = Duration.zero;
                          }
                          _selectedSegmentId = null;
                        });
                        _player.setLoopMode(
                          _isLooping ? LoopMode.one : LoopMode.off,
                        );
                      }),
                      IconButton(
                        tooltip: "Save segment",
                        icon: const Icon(
                          Icons.bookmark_add,
                          color: Colors.white,
                          size: 22,
                        ),
                        onPressed: _currentEntry != null ? _saveSegment : null,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // Main Controls: Previous, -5s, Play/Pause, +5s, Next
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        tooltip: "Previous Audio",
                        iconSize: 28,
                        icon: const Icon(
                          Icons.skip_previous_rounded,
                          color: Colors.white,
                        ),
                        onPressed: _skipToPreviousAudio,
                      ),
                      IconButton(
                        tooltip: "Pass -5s",
                        iconSize: 26,
                        icon: const Icon(
                          Icons.replay_5_rounded,
                          color: Colors.white,
                        ),
                        onPressed: () {
                          HapticFeedback.selectionClick();
                          _seekBy(const Duration(seconds: -5));
                        },
                      ),
                      Container(
                        margin: const EdgeInsets.symmetric(horizontal: 8),
                        decoration: const BoxDecoration(
                          color: Color(0xFF1DB954),
                          shape: BoxShape.circle,
                        ),
                        child: IconButton(
                          iconSize: 40,
                          padding: const EdgeInsets.all(10),
                          icon: Icon(
                            _isPlaying ? Icons.pause : Icons.play_arrow,
                            color: Colors.black,
                          ),
                          onPressed: _togglePlayPause,
                        ),
                      ),
                      IconButton(
                        tooltip: "Pass +5s",
                        iconSize: 26,
                        icon: const Icon(
                          Icons.forward_5_rounded,
                          color: Colors.white,
                        ),
                        onPressed: () {
                          HapticFeedback.selectionClick();
                          _seekBy(const Duration(seconds: 5));
                        },
                      ),
                      IconButton(
                        tooltip: "Next Audio",
                        iconSize: 28,
                        icon: const Icon(
                          Icons.skip_next_rounded,
                          color: Colors.white,
                        ),
                        onPressed: _skipToNextAudio,
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  // Overall Progress Slider (Voice Tracer)
                  SizedBox(
                    height: 18,
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        activeTrackColor: const Color(0xFF1DB954),
                        inactiveTrackColor: Colors.grey[800],
                        thumbColor: Colors.white,
                        trackHeight: 3.0,
                        thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: 5.0,
                        ),
                        overlayShape: const RoundSliderOverlayShape(
                          overlayRadius: 10.0,
                        ),
                      ),
                      child: Slider(
                        value: _duration.inMilliseconds > 0
                            ? _position.inMilliseconds /
                                  _duration.inMilliseconds
                            : 0.0,
                        onChanged: (value) {
                          // Prevent bypassing loop boundaries when in loop mode
                          final newPos = Duration(
                            milliseconds: (_duration.inMilliseconds * value)
                                .toInt(),
                          );

                          // If looping the full audio (not a segment), constrain slider
                          if (_isLooping && _selectedSegmentId == null) {
                            if (newPos < _loopStart) {
                              _player.seek(_loopStart);
                            } else if (newPos > _loopEnd) {
                              _player.seek(_loopEnd);
                            } else {
                              _player.seek(newPos);
                            }
                          } else {
                            // No constraints when not looping
                            _player.seek(newPos);
                          }
                        },
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _formatDuration(_position),
                          style: const TextStyle(
                            color: Colors.grey,
                            fontSize: 10,
                            height: 1.0,
                          ),
                        ),
                        Text(
                          _formatDuration(_duration),
                          style: const TextStyle(
                            color: Colors.grey,
                            fontSize: 10,
                            height: 1.0,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Lower Workspace: Segment List
            Expanded(
              child: Container(
                decoration: const BoxDecoration(color: Color(0xFF121212)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 2, 16, 0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            "Saved Segments",
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (_currentEntry != null &&
                              _currentEntry!.segments.isNotEmpty)
                            SizedBox(
                              width: 140,
                              child: TextField(
                                decoration: InputDecoration(
                                  hintText: "Search...",
                                  hintStyle: const TextStyle(
                                    color: Colors.grey,
                                    fontSize: 13,
                                  ),
                                  isDense: true,
                                  prefixIcon: const Icon(
                                    Icons.search,
                                    size: 16,
                                    color: Colors.grey,
                                  ),
                                  contentPadding: EdgeInsets.zero,
                                  filled: true,
                                  fillColor: const Color(0xFF282828),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(20),
                                    borderSide: BorderSide.none,
                                  ),
                                ),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                ),
                                onChanged: (val) {
                                  setState(() => _segmentSearchQuery = val);
                                },
                              ),
                            ),
                        ],
                      ),
                    ),
                    Expanded(
                      child:
                          _currentEntry == null ||
                              _currentEntry!.segments.isEmpty
                          ? const Center(
                              child: Text(
                                "No segments saved yet.",
                                style: TextStyle(color: Colors.grey),
                              ),
                            )
                          : Builder(
                              builder: (context) {
                                final filteredSegments = _currentEntry!.segments
                                    .where(
                                      (s) => s.name.toLowerCase().contains(
                                        _segmentSearchQuery.toLowerCase(),
                                      ),
                                    )
                                    .toList();

                                if (filteredSegments.isEmpty) {
                                  return const Center(
                                    child: Text(
                                      "No matching segments.",
                                      style: TextStyle(color: Colors.grey),
                                    ),
                                  );
                                }

                                return ReorderableListView.builder(
                                  padding: const EdgeInsets.fromLTRB(
                                    12,
                                    4,
                                    12,
                                    8,
                                  ),
                                  itemCount: filteredSegments.length,
                                  onReorder: (oldIndex, newIndex) {
                                    // Disable reordering when filtering since indices won't match
                                    if (_segmentSearchQuery.isNotEmpty) {
                                      return;
                                    }

                                    setState(() {
                                      if (newIndex > oldIndex) newIndex -= 1;
                                      final item = _currentEntry!.segments
                                          .removeAt(oldIndex);
                                      _currentEntry!.segments.insert(
                                        newIndex,
                                        item,
                                      );
                                    });
                                    _upsertAudioEntry();
                                  },
                                  itemBuilder: (context, index) {
                                    final segment = filteredSegments[index];
                                    final isSelected =
                                        _selectedSegmentId == segment.id;

                                    return Container(
                                      key: ValueKey(segment.id),
                                      margin: const EdgeInsets.symmetric(
                                        vertical: 3,
                                      ),
                                      decoration: BoxDecoration(
                                        color: isSelected
                                            ? const Color(0xFF1E3C2D)
                                            : const Color(0xFF181818),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: isSelected
                                              ? const Color(0xFF2FBF6C)
                                              : const Color(0xFF2A2A2A),
                                          width: 1,
                                        ),
                                      ),
                                      child: ListTile(
                                        dense: true,
                                        minVerticalPadding: 4,
                                        contentPadding: const EdgeInsets.only(
                                          left: 12,
                                          right: 2,
                                        ),
                                        leading: Icon(
                                          Icons.bookmark,
                                          size: 18,
                                          color: isSelected
                                              ? const Color(0xFF45D47F)
                                              : Colors.grey,
                                        ),
                                        onTap: () {
                                          _player.seek(segment.start);
                                          _player.play();
                                          setState(() {
                                            _loopStart = segment.start;
                                            _loopEnd = segment.end;
                                            _selectedSegmentId = segment.id;
                                          });
                                          int originalIndex = _currentEntry!
                                              .segments
                                              .indexOf(segment);
                                          _openSegmentPlayer(originalIndex);
                                        },
                                        title: Text(
                                          segment.name,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color: isSelected
                                                ? const Color(0xFFC9FBDD)
                                                : Colors.white,
                                            fontWeight: FontWeight.w600,
                                            fontSize: 14,
                                          ),
                                        ),
                                        subtitle: Text(
                                          "${_formatDuration(segment.start)} - ${_formatDuration(segment.end)}",
                                          style: TextStyle(
                                            color: isSelected
                                                ? const Color(0xFF9CE7BE)
                                                : Colors.grey,
                                            fontSize: 12,
                                          ),
                                        ),
                                        trailing: Wrap(
                                          spacing: 2,
                                          crossAxisAlignment:
                                              WrapCrossAlignment.center,
                                          children: [
                                            ReorderableDragStartListener(
                                              index: index,
                                              child: const Icon(
                                                Icons.drag_indicator,
                                                color: Colors.grey,
                                                size: 18,
                                              ),
                                            ),
                                            IconButton(
                                              visualDensity:
                                                  VisualDensity.compact,
                                              constraints:
                                                  const BoxConstraints.tightFor(
                                                    width: 28,
                                                    height: 28,
                                                  ),
                                              padding: EdgeInsets.zero,
                                              icon: const Icon(
                                                Icons.edit,
                                                color: Colors.grey,
                                                size: 17,
                                              ),
                                              onPressed: () =>
                                                  _editSegmentName(segment),
                                            ),
                                            IconButton(
                                              visualDensity:
                                                  VisualDensity.compact,
                                              constraints:
                                                  const BoxConstraints.tightFor(
                                                    width: 28,
                                                    height: 28,
                                                  ),
                                              padding: EdgeInsets.zero,
                                              icon: const Icon(
                                                Icons.delete_outline,
                                                color: Colors.redAccent,
                                                size: 18,
                                              ),
                                              onPressed: () =>
                                                  _deleteSegment(segment),
                                            ),
                                          ],
                                        ),
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
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildControlBtn(String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF282828),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

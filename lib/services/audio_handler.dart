import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import 'widget_service.dart';

class AppAudioHandler extends BaseAudioHandler with SeekHandler {
  final AudioPlayer _player;

  String? _mediaId;
  String? _mediaTitle;
  String? _mediaArtist;
  Uri? _mediaArtUri;

  AppAudioHandler(this._player) {
    _player.playerStateStream.listen(_broadcastPlaybackState);
    _player.playbackEventStream.listen((event) {
      _broadcastPlaybackState(_player.playerState);
    });
    _player.durationStream.listen((Duration? duration) {
      if (_mediaId != null) {
        _publishMediaItem(duration: duration);
      }
    });

    _initAudioSession();
  }

  void _initAudioSession() {
    AudioSession.instance
        .then((session) async {
          await session.configure(const AudioSessionConfiguration.music());
          session.becomingNoisyEventStream.listen((_) {
            _player.pause();
          });
          session.interruptionEventStream.listen((event) {
            if (event.begin) {
              switch (event.type) {
                case AudioInterruptionType.duck:
                  _player.setVolume(0.5);
                  break;
                case AudioInterruptionType.pause:
                case AudioInterruptionType.unknown:
                  _player.pause();
                  break;
              }
            } else {
              switch (event.type) {
                case AudioInterruptionType.duck:
                  _player.setVolume(1.0);
                  break;
                case AudioInterruptionType.pause:
                  _player.play();
                  break;
                case AudioInterruptionType.unknown:
                  break;
              }
            }
          });
        })
        .catchError((e) {
          debugPrint('AudioSession error: $e');
        });
  }

  AudioPlayer get player => _player;

  Future<void> publishNowPlaying({
    required String id,
    required String title,
    String? artist,
    Uri? artUri,
    Duration? duration,
  }) async {
    _mediaId = id;
    _mediaTitle = title;
    _mediaArtist = artist;
    _mediaArtUri = artUri;
    _publishMediaItem(duration: duration ?? _player.duration);
  }

  void _publishMediaItem({Duration? duration}) {
    final id = _mediaId;
    final title = _mediaTitle;
    if (id == null || title == null) return;

    mediaItem.add(
      MediaItem(
        id: id,
        title: title,
        artist: _mediaArtist,
        artUri: _mediaArtUri,
        duration: duration,
      ),
    );

    WidgetService.updateWidget(
      title: title,
      artist: _mediaArtist ?? 'MP360',
      isPlaying: _player.playing,
    );
  }

  void _broadcastPlaybackState(PlayerState state) {
    playbackState.add(
      playbackState.value.copyWith(
        controls: [
          MediaControl.skipToPrevious,
          MediaControl.rewind,
          state.playing ? MediaControl.pause : MediaControl.play,
          MediaControl.fastForward,
          MediaControl.skipToNext,
          MediaControl.stop,
        ],
        systemActions: const {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
          MediaAction.setSpeed,
        },
        androidCompactActionIndices: const [0, 2, 4],
        processingState: _mapProcessingState(state.processingState),
        playing: state.playing,
        updatePosition: _player.position,
        bufferedPosition: _player.bufferedPosition,
        speed: _player.speed,
      ),
    );

    WidgetService.updateWidget(
      title: _mediaTitle ?? 'MP360',
      artist: _mediaArtist ?? 'No Audio Playing',
      isPlaying: state.playing,
    );
  }

  AudioProcessingState _mapProcessingState(ProcessingState processingState) {
    switch (processingState) {
      case ProcessingState.idle:
        return AudioProcessingState.idle;
      case ProcessingState.loading:
        return AudioProcessingState.loading;
      case ProcessingState.buffering:
        return AudioProcessingState.buffering;
      case ProcessingState.ready:
        return AudioProcessingState.ready;
      case ProcessingState.completed:
        return AudioProcessingState.completed;
    }
  }

  VoidCallback? onSkipToNext;
  VoidCallback? onSkipToPrevious;
  VoidCallback? onStopRequested;

  @override
  Future<void> play() async {
    if (_player.processingState == ProcessingState.idle ||
        _player.processingState == ProcessingState.completed) {
      if (_mediaId != null && _mediaId!.isNotEmpty) {
        final resumePos = _player.position;
        final sourceUri =
            _mediaId!.startsWith('http://') || _mediaId!.startsWith('https://')
            ? Uri.parse(_mediaId!)
            : Uri.file(_mediaId!);
        try {
          await _player.setAudioSource(
            AudioSource.uri(sourceUri),
            initialPosition: resumePos,
          );
        } catch (e) {
          debugPrint('Error recovering in handler.play: $e');
        }
      }
    }
    return _player.play();
  }

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> stop() async {
    onStopRequested?.call();
    await _player.stop();
    await _player.seek(Duration.zero);
    playbackState.add(
      playbackState.value.copyWith(
        processingState: AudioProcessingState.idle,
        playing: false,
      ),
    );
    await WidgetService.clearWidget();
    return super.stop();
  }

  @override
  Future<void> seek(Duration position) async {
    await _player.seek(position);
    playbackState.add(playbackState.value.copyWith(updatePosition: position));
  }

  @override
  Future<void> skipToNext() async {
    onSkipToNext?.call();
  }

  @override
  Future<void> skipToPrevious() async {
    onSkipToPrevious?.call();
  }

  @override
  Future<void> fastForward() async {
    final current = _player.position;
    final target = current + const Duration(seconds: 5);
    final duration = _player.duration ?? Duration.zero;
    final newPos = target < duration ? target : duration;
    await _player.seek(newPos);
    playbackState.add(playbackState.value.copyWith(updatePosition: newPos));
  }

  @override
  Future<void> rewind() async {
    final current = _player.position;
    final target = current - const Duration(seconds: 5);
    final newPos = target > Duration.zero ? target : Duration.zero;
    await _player.seek(newPos);
    playbackState.add(playbackState.value.copyWith(updatePosition: newPos));
  }
}

AppAudioHandler? appAudioHandler;
AudioPlayer? _appPlayer;
AudioPlayer get appPlayer => _appPlayer ??= AudioPlayer();
set appPlayer(AudioPlayer player) => _appPlayer = player;

bool get useIosMediaControls => !kIsWeb && Platform.isIOS;
bool get isAudioServiceSupported =>
    !kIsWeb && (Platform.isAndroid || Platform.isIOS);

Future<void> publishNowPlayingMetadata({
  required String id,
  required String title,
  String? artist,
  Duration? duration,
}) async {
  final handler = appAudioHandler;
  if (handler == null) return;

  await handler.publishNowPlaying(
    id: id,
    title: title,
    artist: artist,
    duration: duration,
  );
}

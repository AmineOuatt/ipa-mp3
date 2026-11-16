import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';

class AppAudioHandler extends BaseAudioHandler with SeekHandler {
  final AudioPlayer _player;

  String? _mediaId;
  String? _mediaTitle;
  String? _mediaArtist;
  Uri? _mediaArtUri;

  AppAudioHandler(this._player) {
    _player.playerStateStream.listen(_broadcastPlaybackState);
    _player.durationStream.listen((Duration? duration) {
      if (_mediaId != null) {
        _publishMediaItem(duration: duration);
      }
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
        androidCompactActionIndices: const [0, 2, 4],
        processingState: _mapProcessingState(state.processingState),
        playing: state.playing,
        updatePosition: _player.position,
        bufferedPosition: _player.bufferedPosition,
        speed: _player.speed,
      ),
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

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seek(Duration position) => _player.seek(position);
}


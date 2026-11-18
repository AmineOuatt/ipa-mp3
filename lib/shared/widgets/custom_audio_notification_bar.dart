import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';

import '../../core/constants/app_colors.dart';
import '../../core/utils/duration_formatter.dart';
import '../../main.dart';

/// A custom Flutter notification widget bar providing full playback control:
/// - Stop
/// - Pass 5s (Rewind -5s and Fast Forward +5s)
/// - Swap between audios (Skip Next and Skip Previous)
/// - Play / Pause toggle
/// - Tap to jump to full player
class CustomAudioNotificationBar extends StatelessWidget {
  final bool showOpenPlayerButton;

  const CustomAudioNotificationBar({
    super.key,
    this.showOpenPlayerButton = true,
  });

  @override
  Widget build(BuildContext context) {
    final player = appPlayer;

    return StreamBuilder<PlayerState>(
      stream: player.playerStateStream,
      builder: (context, playerSnapshot) {
        final state = playerSnapshot.data;
        final hasSource =
            player.duration != null && player.duration! > Duration.zero;

        // If nothing is loaded, keep invisible
        if (!hasSource &&
            (state == null || state.processingState == ProcessingState.idle)) {
          return const SizedBox.shrink();
        }

        final isPlaying = state?.playing ?? false;

        return StreamBuilder<MediaItem?>(
          stream: appAudioHandler?.mediaItem ?? Stream.value(null),
          builder: (context, mediaSnapshot) {
            final media = mediaSnapshot.data;
            final title = media?.title ?? 'MP360 Audio';
            final artist = media?.artist ?? 'Audio Player';

            return SafeArea(
              top: false,
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E1E),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: AppColors.primaryGreen.withAlpha(70),
                    width: 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withAlpha(160),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Stream Position Progress Indicator
                    StreamBuilder<Duration>(
                      stream: player.positionStream,
                      builder: (context, posSnapshot) {
                        final pos = posSnapshot.data ?? Duration.zero;
                        final total = player.duration ?? Duration.zero;
                        final progress = total.inMilliseconds > 0
                            ? (pos.inMilliseconds / total.inMilliseconds).clamp(
                                0.0,
                                1.0,
                              )
                            : 0.0;

                        return ClipRRect(
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(14),
                          ),
                          child: LinearProgressIndicator(
                            value: progress,
                            minHeight: 2.5,
                            backgroundColor: Colors.white10,
                            color: AppColors.primaryGreen,
                          ),
                        );
                      },
                    ),

                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                      child: Row(
                        children: [
                          // App / Audio Icon with Tap to Open
                          GestureDetector(
                            onTap: () => _openPlayer(context),
                            child: Container(
                              width: 38,
                              height: 38,
                              decoration: BoxDecoration(
                                color: AppColors.primaryGreen.withAlpha(30),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(
                                isPlaying
                                    ? Icons.music_note_rounded
                                    : Icons.pause_rounded,
                                color: AppColors.primaryGreen,
                                size: 22,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),

                          // Title and Reciter info
                          Expanded(
                            child: GestureDetector(
                              onTap: () => _openPlayer(context),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  StreamBuilder<Duration>(
                                    stream: player.positionStream,
                                    builder: (context, posSnapshot) {
                                      final pos =
                                          posSnapshot.data ?? Duration.zero;
                                      final total =
                                          player.duration ?? Duration.zero;
                                      return Text(
                                        '$artist • ${formatDuration(pos)} / ${formatDuration(total)}',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: Colors.grey[400],
                                          fontSize: 11,
                                        ),
                                      );
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ),

                          // Controls: Prev, -5s, Play/Pause, +5s, Next, Stop
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Swap to Previous
                              IconButton(
                                tooltip: 'Previous Audio',
                                iconSize: 22,
                                padding: const EdgeInsets.all(4),
                                constraints: const BoxConstraints(),
                                icon: const Icon(
                                  Icons.skip_previous_rounded,
                                  color: Colors.white,
                                ),
                                onPressed: () {
                                  HapticFeedback.selectionClick();
                                  appAudioHandler?.skipToPrevious();
                                },
                              ),
                              const SizedBox(width: 4),

                              // Pass -5s
                              IconButton(
                                tooltip: 'Pass -5s',
                                iconSize: 20,
                                padding: const EdgeInsets.all(4),
                                constraints: const BoxConstraints(),
                                icon: const Icon(
                                  Icons.replay_5_rounded,
                                  color: Colors.white70,
                                ),
                                onPressed: () {
                                  HapticFeedback.selectionClick();
                                  appAudioHandler?.rewind();
                                },
                              ),
                              const SizedBox(width: 4),

                              // Play / Pause
                              Container(
                                width: 34,
                                height: 34,
                                decoration: const BoxDecoration(
                                  color: AppColors.primaryGreen,
                                  shape: BoxShape.circle,
                                ),
                                child: IconButton(
                                  tooltip: isPlaying ? 'Pause' : 'Play',
                                  iconSize: 20,
                                  padding: EdgeInsets.zero,
                                  icon: Icon(
                                    isPlaying
                                        ? Icons.pause_rounded
                                        : Icons.play_arrow_rounded,
                                    color: Colors.black,
                                  ),
                                  onPressed: () {
                                    HapticFeedback.mediumImpact();
                                    isPlaying ? player.pause() : player.play();
                                  },
                                ),
                              ),
                              const SizedBox(width: 4),

                              // Pass +5s
                              IconButton(
                                tooltip: 'Pass +5s',
                                iconSize: 20,
                                padding: const EdgeInsets.all(4),
                                constraints: const BoxConstraints(),
                                icon: const Icon(
                                  Icons.forward_5_rounded,
                                  color: Colors.white70,
                                ),
                                onPressed: () {
                                  HapticFeedback.selectionClick();
                                  appAudioHandler?.fastForward();
                                },
                              ),
                              const SizedBox(width: 4),

                              // Swap to Next
                              IconButton(
                                tooltip: 'Next Audio',
                                iconSize: 22,
                                padding: const EdgeInsets.all(4),
                                constraints: const BoxConstraints(),
                                icon: const Icon(
                                  Icons.skip_next_rounded,
                                  color: Colors.white,
                                ),
                                onPressed: () {
                                  HapticFeedback.selectionClick();
                                  appAudioHandler?.skipToNext();
                                },
                              ),
                              const SizedBox(width: 4),

                              // Stop
                              IconButton(
                                tooltip: 'Stop',
                                iconSize: 20,
                                padding: const EdgeInsets.all(4),
                                constraints: const BoxConstraints(),
                                icon: const Icon(
                                  Icons.stop_circle_outlined,
                                  color: Colors.redAccent,
                                ),
                                onPressed: () {
                                  HapticFeedback.mediumImpact();
                                  appAudioHandler?.stop();
                                },
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _openPlayer(BuildContext context) {
    if (ModalRoute.of(context)?.isFirst ?? false) {
      return;
    }
    Navigator.of(context).popUntil((route) => route.isFirst);
  }
}

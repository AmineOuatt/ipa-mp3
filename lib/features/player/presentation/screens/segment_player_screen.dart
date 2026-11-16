import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/utils/duration_formatter.dart';
import '../../../../models/models.dart';

class SegmentPlayerScreen extends StatefulWidget {
  final AudioPlayer player;
  final List<LoopBookmark> segments;
  final int initialIndex;
  final String trackName;
  final VoidCallback onSegmentsUpdated;

  const SegmentPlayerScreen({
    super.key,
    required this.player,
    required this.segments,
    required this.initialIndex,
    required this.trackName,
    required this.onSegmentsUpdated,
  });

  @override
  State<SegmentPlayerScreen> createState() => _SegmentPlayerScreenState();
}

class _SegmentPlayerScreenState extends State<SegmentPlayerScreen> {
  bool _isPlaying = true;
  bool _isLooping = true;
  Duration _position = Duration.zero;
  late int _currentIndex;

  // Stream subscriptions to clean up
  late final StreamSubscription<Duration> _positionSubscription;
  late final StreamSubscription<PlayerState> _stateSubscription;

  LoopBookmark get currentSegment => widget.segments[_currentIndex];

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _position = currentSegment.start;

    _positionSubscription = widget.player.positionStream.listen((pos) {
      if (!mounted) return;
      setState(() => _position = pos);

      if (pos >= currentSegment.end) {
        if (_isLooping) {
          widget.player.seek(currentSegment.start);
        } else {
          _goToNextSegmentOrStop();
        }
      }
    });

    _stateSubscription = widget.player.playerStateStream.listen((state) {
      if (!mounted) return;
      setState(() => _isPlaying = state.playing);
    });
  }

  @override
  void dispose() {
    _positionSubscription.cancel();
    _stateSubscription.cancel();
    super.dispose();
  }

  void _goToNextSegmentOrStop() {
    if (_currentIndex < widget.segments.length - 1) {
      setState(() {
        _currentIndex++;
      });
      widget.player.seek(currentSegment.start);
    } else {
      widget.player.pause();
    }
  }

  void _goToPrevSegment() {
    HapticFeedback.mediumImpact();
    // If we've played for more than 3 seconds or it's the first segment, restart current.
    if ((_position - currentSegment.start).inSeconds >= 3 ||
        _currentIndex == 0) {
      widget.player.seek(currentSegment.start);
    } else {
      setState(() {
        _currentIndex--;
      });
      widget.player.seek(currentSegment.start);
    }
  }

  void _goToNextSegment() {
    HapticFeedback.mediumImpact();
    if (_currentIndex < widget.segments.length - 1) {
      setState(() {
        _currentIndex++;
      });
      widget.player.seek(currentSegment.start);
    } else {
      widget.player.seek(currentSegment.end);
    }
  }

  void _seekRelative(Duration offset) {
    HapticFeedback.selectionClick();
    final newPos = _position + offset;
    final maxPos = newPos > currentSegment.end ? currentSegment.end : newPos;
    final minPos = maxPos < currentSegment.start
        ? currentSegment.start
        : maxPos;
    widget.player.seek(minPos);
  }

  String _formatDuration(Duration d) => formatDuration(d);

  @override
  Widget build(BuildContext context) {
    final segmentDuration = currentSegment.end - currentSegment.start;
    final currentSegmentPos = _position - currentSegment.start;

    // Safety clamp
    final clampedPos = currentSegmentPos.isNegative
        ? Duration.zero
        : (currentSegmentPos > segmentDuration
              ? segmentDuration
              : currentSegmentPos);

    return Container(
      color: AppColors.background,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.keyboard_arrow_down),
            onPressed: () => Navigator.pop(context),
          ),
          title: const Text(
            "PLAYING SEGMENT",
            style: TextStyle(
              fontSize: 12,
              letterSpacing: 1.5,
              color: Colors.grey,
            ),
          ),
          centerTitle: true,
        ),
        body: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Album Art Placeholder
              Expanded(
                child: Center(
                  child: Container(
                    width: MediaQuery.of(context).size.width * 0.8,
                    height: MediaQuery.of(context).size.width * 0.8,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [AppColors.surfaceElevated, AppColors.surface],
                      ),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withAlpha(128),
                          blurRadius: 20,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: const Center(
                      child: Icon(
                        Icons.music_note,
                        size: 80,
                        color: Colors.grey,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 40),

              // Track Info
              Text(
                currentSegment.name,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                widget.trackName,
                style: const TextStyle(fontSize: 16, color: Colors.grey),
              ),
              const SizedBox(height: 32),

              // Segment Progress
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  activeTrackColor: AppColors.primary,
                  inactiveTrackColor: Colors.grey[800],
                  thumbColor: Colors.white,
                  trackHeight: 4.0,
                  thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: 6.0,
                  ),
                  overlayShape: const RoundSliderOverlayShape(
                    overlayRadius: 14.0,
                  ),
                ),
                child: Slider(
                  value: segmentDuration.inMilliseconds > 0
                      ? clampedPos.inMilliseconds /
                            segmentDuration.inMilliseconds
                      : 0.0,
                  onChanged: (value) {
                    final newPos =
                        currentSegment.start +
                        Duration(
                          milliseconds: (segmentDuration.inMilliseconds * value)
                              .toInt(),
                        );
                    widget.player.seek(newPos);
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _formatDuration(clampedPos),
                      style: const TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                    Text(
                      _formatDuration(segmentDuration),
                      style: const TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Micro-adjustments
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildMicroBtn(
                    "-5s",
                    () => _seekRelative(const Duration(seconds: -5)),
                  ),
                  _buildMicroBtn(
                    "+5s",
                    () => _seekRelative(const Duration(seconds: 5)),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Controls
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  IconButton(
                    icon: Icon(
                      _isLooping ? Icons.repeat_on : Icons.repeat,
                      color: _isLooping ? AppColors.primary : Colors.grey,
                    ),
                    onPressed: () {
                      HapticFeedback.selectionClick();
                      setState(() => _isLooping = !_isLooping);
                    },
                  ),
                  IconButton(
                    iconSize: 36,
                    icon: const Icon(Icons.skip_previous, color: Colors.white),
                    onPressed: _goToPrevSegment,
                  ),
                  Container(
                    decoration: const BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      iconSize: 48,
                      padding: const EdgeInsets.all(16),
                      icon: Icon(
                        _isPlaying ? Icons.pause : Icons.play_arrow,
                        color: Colors.black,
                      ),
                      onPressed: () {
                        HapticFeedback.mediumImpact();
                        _isPlaying
                            ? widget.player.pause()
                            : widget.player.play();
                      },
                    ),
                  ),
                  IconButton(
                    iconSize: 36,
                    icon: const Icon(Icons.skip_next, color: Colors.white),
                    onPressed: _goToNextSegment,
                  ),
                  IconButton(
                    icon: const Icon(Icons.edit, color: Colors.white),
                    tooltip: "Edit segment bounds",
                    onPressed: _showEditSegmentSheet,
                  ),
                ],
              ),
              const SizedBox(height: 48),
            ],
          ),
        ),
      ),
    );
  }

  void _showEditSegmentSheet() {
    Duration tempStart = currentSegment.start;
    Duration tempEnd = currentSegment.end;
    final Duration totalDuration =
        widget.player.duration ??
        (currentSegment.end > Duration.zero
            ? currentSegment.end
            : const Duration(seconds: 1));
    final int minGapMs = 500;

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        "Edit Segment",
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.grey),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    "Full audio: 00:00 - ${_formatDuration(totalDuration)}",
                    style: const TextStyle(color: Colors.grey),
                  ),
                  const SizedBox(height: 8),
                  RangeSlider(
                    values: RangeValues(
                      tempStart.inMilliseconds
                          .clamp(0, totalDuration.inMilliseconds)
                          .toDouble(),
                      tempEnd.inMilliseconds
                          .clamp(0, totalDuration.inMilliseconds)
                          .toDouble(),
                    ),
                    min: 0,
                    max: totalDuration.inMilliseconds.toDouble(),
                    activeColor: AppColors.primary,
                    inactiveColor: Colors.grey[800],
                    labels: RangeLabels(
                      _formatDuration(tempStart),
                      _formatDuration(tempEnd),
                    ),
                    onChanged: (values) {
                      setModalState(() {
                        int startMs = values.start.round();
                        int endMs = values.end.round();

                        if (endMs - startMs < minGapMs) {
                          if (endMs + minGapMs <=
                              totalDuration.inMilliseconds) {
                            endMs = startMs + minGapMs;
                          } else {
                            startMs = (endMs - minGapMs).clamp(
                              0,
                              totalDuration.inMilliseconds,
                            );
                          }
                        }

                        tempStart = Duration(milliseconds: startMs);
                        tempEnd = Duration(milliseconds: endMs);
                      });
                    },
                  ),
                  const SizedBox(height: 8),
                  Text(
                    "Start: ${_formatDuration(tempStart)}",
                    style: const TextStyle(color: Colors.grey),
                  ),
                  const SizedBox(height: 4),
                  TextButton.icon(
                    icon: const Icon(Icons.flag, color: AppColors.primary),
                    label: const Text(
                      "Set start to current position",
                      style: TextStyle(color: Colors.white),
                    ),
                    onPressed: () {
                      setModalState(() {
                        tempStart = _position;
                        if (tempStart > totalDuration) {
                          tempStart = totalDuration;
                        }
                        if (tempEnd <= tempStart) {
                          final candidate =
                              tempStart + Duration(milliseconds: minGapMs);
                          tempEnd = candidate > totalDuration
                              ? totalDuration
                              : candidate;
                        }
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  Text(
                    "End: ${_formatDuration(tempEnd)}",
                    style: const TextStyle(color: Colors.grey),
                  ),
                  const SizedBox(height: 4),
                  TextButton.icon(
                    icon: const Icon(
                      Icons.flag_circle,
                      color: AppColors.primary,
                    ),
                    label: const Text(
                      "Set end to current position",
                      style: TextStyle(color: Colors.white),
                    ),
                    onPressed: () {
                      setModalState(() {
                        tempEnd = _position;
                        if (tempEnd > totalDuration) {
                          tempEnd = totalDuration;
                        }
                        if (tempEnd <= tempStart) {
                          tempStart =
                              tempEnd - Duration(milliseconds: minGapMs);
                          if (tempStart < Duration.zero) {
                            tempStart = Duration.zero;
                          }
                        }
                      });
                    },
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        child: const Text(
                          "CANCEL",
                          style: TextStyle(color: Colors.grey),
                        ),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.black,
                        ),
                        onPressed: () {
                          setState(() {
                            currentSegment.start = tempStart;
                            currentSegment.end = tempEnd;
                          });
                          widget.player.seek(currentSegment.start);
                          widget.onSegmentsUpdated();
                          Navigator.pop(ctx);
                        },
                        child: const Text("Save"),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildMicroBtn(String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.surfaceElevated,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';

class WaveformPainter extends CustomPainter {
  final List<double> samples;
  final double positionPercent;
  final double loopStartPercent;
  final double loopEndPercent;

  WaveformPainter({
    required this.samples,
    required this.positionPercent,
    required this.loopStartPercent,
    required this.loopEndPercent,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (samples.isEmpty) return;

    final paintNormal = Paint()
      ..color = Colors.grey[800]!
      ..style = PaintingStyle.fill
      ..strokeCap = StrokeCap.round;

    final paintHighlight = Paint()
      ..color = AppColors.primary
      ..style = PaintingStyle.fill
      ..strokeCap = StrokeCap.round;

    final double barWidth = (size.width / samples.length) * 0.7;
    final double spacing = (size.width / samples.length) * 0.3;

    for (int i = 0; i < samples.length; i++) {
      final double percent = i / samples.length;
      final bool inLoop =
          percent >= loopStartPercent && percent <= loopEndPercent;

      final Paint currentPaint = inLoop ? paintHighlight : paintNormal;

      final double barHeight = samples[i] * size.height;
      final double x = i * (barWidth + spacing);
      final double y = (size.height - barHeight) / 2;

      final roundedRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, y, barWidth, barHeight),
        const Radius.circular(4),
      );

      canvas.drawRRect(roundedRect, currentPaint);
    }

    // Draw position line
    final posPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 2;
    final xPos = positionPercent * size.width;
    canvas.drawLine(Offset(xPos, 0), Offset(xPos, size.height), posPaint);
  }

  @override
  bool shouldRepaint(covariant WaveformPainter oldDelegate) {
    return oldDelegate.positionPercent != positionPercent ||
        oldDelegate.loopStartPercent != loopStartPercent ||
        oldDelegate.loopEndPercent != loopEndPercent ||
        oldDelegate.samples != samples;
  }
}

// Alias for backwards compatibility with any private naming
typedef WaveformPainterAlias = WaveformPainter;

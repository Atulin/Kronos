import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../domain/task_analytics.dart';

class DurationBarChart extends StatelessWidget {
  const DurationBarChart({
    super.key,
    required this.buckets,
    required this.bucketSize,
  });

  final List<AnalyticsBucket> buckets;
  final AnalyticsBucketSize bucketSize;

  @override
  Widget build(BuildContext context) {
    final availableWidth = MediaQuery.sizeOf(context).width - 80;
    final chartWidth = math.max(availableWidth, buckets.length * 62.0);
    final colors = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: CustomPaint(
        size: Size(chartWidth, 240),
        painter: _DurationBarPainter(
          buckets: buckets,
          bucketSize: bucketSize,
          barColor: colors.secondary,
          gridColor: colors.outlineVariant,
          labelColor: colors.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _DurationBarPainter extends CustomPainter {
  const _DurationBarPainter({
    required this.buckets,
    required this.bucketSize,
    required this.barColor,
    required this.gridColor,
    required this.labelColor,
  });

  final List<AnalyticsBucket> buckets;
  final AnalyticsBucketSize bucketSize;
  final Color barColor;
  final Color gridColor;
  final Color labelColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (buckets.isEmpty) return;
    const left = 58.0;
    const right = 8.0;
    const top = 12.0;
    const bottom = 36.0;
    final chartWidth = size.width - left - right;
    final chartHeight = size.height - top - bottom;
    final values = buckets.map((bucket) => bucket.average.inMicroseconds);
    final minimum = math.min(0, values.reduce(math.min));
    var maximum = math.max(0, values.reduce(math.max));
    if (minimum == maximum) maximum = minimum + 1;
    final valueRange = (maximum - minimum).toDouble();
    final baseline = top + (maximum / valueRange) * chartHeight;

    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 0.7;
    final axisLabelStyle = TextStyle(color: labelColor, fontSize: 10);
    for (var line = 0; line <= 4; line++) {
      final fraction = line / 4;
      final y = top + chartHeight * fraction;
      canvas.drawLine(
        Offset(left, y),
        Offset(size.width - right, y),
        gridPaint,
      );
      final value = maximum - valueRange * fraction;
      _paintText(
        canvas,
        _formatMicros(value.round()),
        axisLabelStyle,
        Offset(0, y - 7),
        width: left - 8,
        align: TextAlign.right,
      );
    }

    final barPaint = Paint()..color = barColor;
    final slotWidth = chartWidth / buckets.length;
    final barWidth = math.min(30.0, slotWidth * 0.58);
    for (var index = 0; index < buckets.length; index++) {
      final bucket = buckets[index];
      final value = bucket.average.inMicroseconds.toDouble();
      final valueY = top + ((maximum - value) / valueRange) * chartHeight;
      final x = left + slotWidth * index + (slotWidth - barWidth) / 2;
      final rectTop = math.min(baseline, valueY);
      final rectHeight = math.max(2.0, (baseline - valueY).abs());
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, rectTop, barWidth, rectHeight),
          const Radius.circular(5),
        ),
        barPaint,
      );
      _paintText(
        canvas,
        bucket.label(bucketSize),
        axisLabelStyle,
        Offset(left + slotWidth * index, size.height - bottom + 8),
        width: slotWidth,
        align: TextAlign.center,
      );
    }
  }

  void _paintText(
    Canvas canvas,
    String value,
    TextStyle style,
    Offset offset, {
    required double width,
    required TextAlign align,
  }) {
    final painter = TextPainter(
      text: TextSpan(text: value, style: style),
      textDirection: TextDirection.ltr,
      textAlign: align,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: width);
    painter.paint(canvas, offset);
  }

  String _formatMicros(int microseconds) {
    final duration = Duration(microseconds: microseconds);
    final sign = duration.isNegative ? '−' : '';
    final absolute = duration.abs();
    if (absolute.inDays > 0) {
      return '$sign${absolute.inDays}d';
    }
    if (absolute.inHours > 0) {
      return '$sign${absolute.inHours}h';
    }
    if (absolute.inMinutes > 0) {
      return '$sign${absolute.inMinutes}m';
    }
    return '$sign${absolute.inSeconds}s';
  }

  @override
  bool shouldRepaint(covariant _DurationBarPainter oldDelegate) =>
      oldDelegate.buckets != buckets ||
      oldDelegate.bucketSize != bucketSize ||
      oldDelegate.barColor != barColor ||
      oldDelegate.gridColor != gridColor ||
      oldDelegate.labelColor != labelColor;
}

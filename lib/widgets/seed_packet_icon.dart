import 'package:flutter/material.dart';

/// A seed packet with a sprout, readable at toolbar icon sizes.
class SeedPacketIcon extends StatelessWidget {
  const SeedPacketIcon({super.key, this.size = 18});
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: _SeedPacketPainter(
          IconTheme.of(context).color ?? const Color(0xff376b50))));
}

class _SeedPacketPainter extends CustomPainter {
  const _SeedPacketPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 18, size.height / 18);
    final outline = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawRRect(RRect.fromRectAndRadius(
        const Rect.fromLTWH(3, 1, 12, 16), const Radius.circular(2)), outline);
    canvas.drawLine(const Offset(3.5, 4), const Offset(14.5, 4), outline);
    canvas.drawLine(const Offset(9, 13.5), const Offset(9, 9), outline);
    final leaves = Path()
      ..moveTo(9, 11)
      ..quadraticBezierTo(4.8, 11, 5.5, 7)
      ..quadraticBezierTo(9, 7.1, 9, 11)
      ..moveTo(9, 10)
      ..quadraticBezierTo(9, 6.5, 12.8, 6.5)
      ..quadraticBezierTo(13.2, 10, 9, 10);
    canvas.drawPath(leaves, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_SeedPacketPainter oldDelegate) => oldDelegate.color != color;
}

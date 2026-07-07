import 'package:flutter/material.dart';

/// Сплошной вертикальный гексагон для фирменного логомарка.
class AppLogoMark extends StatelessWidget {
  final double size;
  final Color color;

  const AppLogoMark({
    super.key,
    this.size = 18,
    this.color = const Color(0xFF8E5CFF),
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _HexagonPainter(color),
    );
  }
}

class _HexagonPainter extends CustomPainter {
  final Color color;
  const _HexagonPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final path = Path()
      ..moveTo(w * 0.5, 0)
      ..lineTo(w, h * 0.25)
      ..lineTo(w, h * 0.75)
      ..lineTo(w * 0.5, h)
      ..lineTo(0, h * 0.75)
      ..lineTo(0, h * 0.25)
      ..close();

    final paint = Paint()
      ..style = PaintingStyle.fill
      ..color = color;

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _HexagonPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

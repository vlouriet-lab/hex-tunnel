import 'dart:math';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Фоновый виджет с анимированными геометрическими контурами гексагонов.
/// Вдохновлён стилем SOTA Segment и расширения Red Shield VPN.
class HexBackground extends StatefulWidget {
  final Widget child;

  const HexBackground({super.key, this.child = const SizedBox.expand()});

  @override
  State<HexBackground> createState() => _HexBackgroundState();
}

class _HexBackgroundState extends State<HexBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.sizeOf(context).height;
    final topAccentHeight = (screenHeight * 0.36).clamp(220.0, 360.0);

    return Stack(
      children: [
        // Сплошной тёмный фон
        Container(color: AppTheme.background),

        // Анимированная гексагональная сетка — изолирована RepaintBoundary,
        // чтобы 60fps-перерисовка не загрязняла слой контента.
        RepaintBoundary(
          child: AnimatedBuilder(
            animation: _controller,
            builder: (_, __) => CustomPaint(
              painter: _HexGridPainter(_controller.value),
              size: Size.infinite,
              child: const SizedBox.expand(),
            ),
          ),
        ),

        // Радиальный градиент сверху (логотип / акцент)
        Positioned(
          top: -120,
          left: 0,
          right: 0,
          child: Container(
            height: topAccentHeight,
            decoration: const BoxDecoration(
              gradient: RadialGradient(
                center: Alignment.topCenter,
                radius: 0.8,
                colors: [
                  Color(0x257C3AED),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),

        // Контент — изолирован RepaintBoundary, чтобы перерисовки UI
        // не тригерили слой анимации.
        RepaintBoundary(child: widget.child),
      ],
    );
  }
}

/// Описание одной ячейки гексагональной сетки.
/// Геометрия вычисляется один раз при первой отрисовке и кэшируется.
typedef _HexCell = ({double normDist, Path path});

class _HexGridPainter extends CustomPainter {
  final double phase;

  _HexGridPainter(this.phase);

  // Статический кэш геометрии — пересчитывается только при смене размера экрана.
  // Исключает создание сотен Path-объектов каждый кадр (было ~750+ аллокаций/кадр).
  static Size? _cachedSize;
  static List<_HexCell> _cachedCells = [];

  static void _rebuildCache(Size size) {
    const double hexRadius = 40.0;
    final double hexW = sqrt(3) * hexRadius;
    const double hexH = 2 * hexRadius;
    final double colStep = hexW;
    const double rowStep = hexH * 0.75;
    final double maxDist = size.width * 0.9;

    final int cols = (size.width / colStep).ceil() + 2;
    final int rows = (size.height / rowStep).ceil() + 2;

    final cells = <_HexCell>[];
    for (int row = -1; row < rows; row++) {
      for (int col = -1; col < cols; col++) {
        final bool odd = col.isOdd;
        final double cx = col * colStep + (odd ? hexW / 2 : 0);
        final double cy = row * rowStep + (odd ? rowStep / 2 : 0);

        final double dx = cx - size.width * 0.5;
        final double dy = cy - size.height * 0.3;
        final double dist = sqrt(dx * dx + dy * dy);
        final double normDist = (dist / maxDist).clamp(0.0, 1.0);

        final path = Path();
        for (int i = 0; i < 6; i++) {
          final angle = pi / 180 * (60 * i - 30);
          final x = cx + hexRadius * cos(angle);
          final y = cy + hexRadius * sin(angle);
          if (i == 0) {
            path.moveTo(x, y);
          } else {
            path.lineTo(x, y);
          }
        }
        path.close();

        cells.add((normDist: normDist, path: path));
      }
    }
    _cachedCells = cells;
    _cachedSize = size;
  }

  @override
  void paint(Canvas canvas, Size size) {
    // Пересчитываем геометрию только если изменился размер экрана.
    if (_cachedSize != size) {
      _rebuildCache(size);
    }

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;

    // Per-frame работа: только арифметика + один sin на ячейку.
    // Никаких Path-аллокаций и тригонометрии для координат.
    for (final cell in _cachedCells) {
      final double pulse =
          (sin((phase * 2 * pi) - (cell.normDist * 3)) + 1) / 2;
      final double alpha = 0.04 + pulse * 0.07 * (1 - cell.normDist);
      paint.color = Color.fromRGBO(168, 85, 247, alpha);
      canvas.drawPath(cell.path, paint);
    }
  }

  @override
  bool shouldRepaint(_HexGridPainter old) => old.phase != phase;
}

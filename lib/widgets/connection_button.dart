import 'package:flutter/material.dart';
import '../models/tunnel_status.dart';
import '../theme/app_theme.dart';

/// Большая круглая кнопка подключения с анимацией свечения.
class ConnectionButton extends StatefulWidget {
  final TunnelState state;
  final VoidCallback onTap;

  const ConnectionButton({
    super.key,
    required this.state,
    required this.onTap,
  });

  @override
  State<ConnectionButton> createState() => _ConnectionButtonState();
}

class _ConnectionButtonState extends State<ConnectionButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: AppTheme.motionPulse,
    );
    _pulseAnim = Tween<double>(begin: 0.85, end: 1.15).animate(
      CurvedAnimation(
        parent: _pulseController,
        curve: AppTheme.emphasizedCurve,
      ),
    );
    _updateAnimation();
  }

  @override
  void didUpdateWidget(ConnectionButton old) {
    super.didUpdateWidget(old);
    if (old.state != widget.state) _updateAnimation();
  }

  void _updateAnimation() {
    if (widget.state == TunnelState.connecting) {
      _pulseController.repeat(reverse: true);
    } else {
      _pulseController.stop();
      _pulseController.value = 0.5;
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Color get _ringColor {
    switch (widget.state) {
      case TunnelState.connected:
        return AppTheme.connected;
      case TunnelState.connecting:
        return AppTheme.connecting;
      case TunnelState.error:
        return AppTheme.error;
      case TunnelState.stopped:
        return AppTheme.disconnected;
    }
  }

  Color get _glowColor {
    switch (widget.state) {
      case TunnelState.connected:
        return AppTheme.connected.withValues(alpha: 0.28);
      case TunnelState.connecting:
        return AppTheme.connecting.withValues(alpha: 0.22);
      case TunnelState.error:
        return AppTheme.error.withValues(alpha: 0.20);
      case TunnelState.stopped:
        return Colors.transparent;
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final baseSize = (screenWidth * 0.5).clamp(136.0, 176.0);
    final outerPulseSize = baseSize - 4;
    final ringSize = baseSize - 24;
    final innerSize = baseSize - 40;
    final iconSize = (innerSize * 0.38).clamp(40.0, 52.0);

    return GestureDetector(
      onTap: widget.onTap,
      child: AnimatedBuilder(
        animation: _pulseAnim,
        builder: (context, child) {
          return SizedBox(
            width: baseSize,
            height: baseSize,
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                // Внешний пульсирующий ореол
                if (widget.state != TunnelState.stopped)
                  Transform.scale(
                    scale: _pulseAnim.value,
                    child: Container(
                      width: outerPulseSize,
                      height: outerPulseSize,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _glowColor,
                      ),
                    ),
                  ),

                // Средний обводной круг
                Container(
                  width: ringSize,
                  height: ringSize,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: _ringColor, width: 2),
                    color: Colors.transparent,
                  ),
                ),

                // Основной круг кнопки
                Container(
                  width: innerSize,
                  height: innerSize,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: widget.state == TunnelState.connected
                          ? [
                              const Color(0xFF1A3A2E),
                              const Color(0xFF0F2620),
                            ]
                          : [
                              AppTheme.surfaceVariant,
                              AppTheme.surface,
                            ],
                    ),
                    boxShadow: widget.state == TunnelState.connected
                        ? [
                            BoxShadow(
                              color: AppTheme.connected.withValues(alpha: 0.25),
                              blurRadius: 24,
                              spreadRadius: 4,
                            ),
                          ]
                        : null,
                  ),
                  child: Center(child: _buildIcon(iconSize)),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildIcon(double iconSize) {
    if (widget.state == TunnelState.connecting) {
      final loaderSize = (iconSize * 0.85).clamp(34.0, 44.0);
      return SizedBox(
        width: loaderSize,
        height: loaderSize,
        child: CircularProgressIndicator(
          color: AppTheme.connecting,
          strokeWidth: 2.5,
        ),
      );
    }

    IconData icon;
    Color color;

    switch (widget.state) {
      case TunnelState.connected:
        icon = Icons.power_settings_new_rounded;
        color = AppTheme.connected;
        break;
      case TunnelState.error:
        icon = Icons.warning_amber_rounded;
        color = AppTheme.error;
        break;
      default:
        icon = Icons.power_settings_new_rounded;
        color = AppTheme.textDisabled;
    }

    return Icon(icon, size: iconSize, color: color);
  }
}

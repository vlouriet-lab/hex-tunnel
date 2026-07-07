import 'package:flutter/material.dart';
import '../l10n/app_strings.dart';
import '../models/deblocker_runtime_bundle.dart';
import '../models/offline_deblock_profile.dart';
import '../models/proxy_profile.dart';
import '../models/routing_mode.dart';
import '../models/tunnel_status.dart';
import '../theme/app_theme.dart';

String _t(BuildContext context, String ru, String en) {
  return context.l10n.isRussian ? ru : en;
}

/// Карточка статуса соединения и информации о сервере.
class StatusCard extends StatelessWidget {
  final TunnelStatus status;
  final ProxyProfile? activeProfile;
  final String? activeCountryName;
  final String? activeFlagEmoji;
  final OfflineDeblockProfile? offlineDeblockProfile;
  final DeblockerRuntimeBundle? deblockerRuntimeBundle;
  final bool strictAllowlistModeEnabled;

  const StatusCard({
    super.key,
    required this.status,
    this.activeProfile,
    this.activeCountryName,
    this.activeFlagEmoji,
    this.offlineDeblockProfile,
    this.deblockerRuntimeBundle,
    this.strictAllowlistModeEnabled = false,
  });

  @override
  Widget build(BuildContext context) {
    String routingName(RoutingMode mode) {
      switch (mode) {
        case RoutingMode.global:
          return _t(context, 'Глобальный', 'Global');
        case RoutingMode.ruleBased:
          return _t(context, 'Обход блокировок', 'Bypass blocks');
        case RoutingMode.smart:
          return _t(context, 'Умная маршрутизация', 'Smart Routing');
        case RoutingMode.bypassLan:
          return _t(context, 'Весь трафик + LAN', 'All traffic + LAN');
        case RoutingMode.ruleBasedRu:
          return _t(context, 'Только RU через прокси', 'Only RU via proxy');
      }
    }

    String profileName(OfflineDeblockProfile profile) {
      switch (profile) {
        case OfflineDeblockProfile.soft:
          return _t(context, 'Мягкий', 'Soft');
        case OfflineDeblockProfile.balanced:
          return _t(context, 'Стандартный', 'Balanced');
        case OfflineDeblockProfile.hybrid:
          return _t(context, 'Гибридный Legacy', 'Hybrid Legacy');
        case OfflineDeblockProfile.aggressive:
          return _t(context, 'Агрессивный', 'Aggressive');
        case OfflineDeblockProfile.ultra:
          return _t(context, 'Ультра', 'Ultra');
        case OfflineDeblockProfile.custom:
          return _t(context, 'Кастом', 'Custom');
      }
    }

    String runtimeStatus(OfflineDeblockProfile profile) {
      switch (profile) {
        case OfflineDeblockProfile.soft:
          return _t(context, 'DNS усилен', 'DNS hardened');
        case OfflineDeblockProfile.balanced:
          return _t(context, 'DNS усилен, QUIC ограничен',
              'DNS hardened, QUIC limited');
        case OfflineDeblockProfile.hybrid:
          return _t(context, 'Legacy WARP fallback для мягкой фильтрации',
              'Legacy WARP fallback for mild filtering');
        case OfflineDeblockProfile.aggressive:
          return _t(context, 'DNS усилен, UDP и IPv6 ограничены',
              'DNS hardened, UDP and IPv6 limited');
        case OfflineDeblockProfile.ultra:
          return _t(context, 'DNS усилен, транспорт жёстко ограничен',
              'DNS hardened, transport strictly limited');
        case OfflineDeblockProfile.custom:
          return _t(context, 'DNS/транспорт настроены вручную',
              'DNS/transport configured manually');
      }
    }

    final fallbackState = switch (status.state) {
      TunnelState.stopped => _t(context, 'Отключено', 'Disconnected'),
      TunnelState.connecting => _t(context, 'Подключение…', 'Connecting...'),
      TunnelState.connected => _t(context, 'Подключено', 'Connected'),
      TunnelState.error => _t(context, 'Ошибка', 'Error'),
    };

    String deliveryModeLabel(DeblockerDeliveryMode mode) {
      switch (mode) {
        case DeblockerDeliveryMode.allowlistedIngress:
          return _t(context, 'Выделенный канал', 'Dedicated channel');
        case DeblockerDeliveryMode.warpHybridLegacy:
          return _t(context, 'Cloudflare (резерв)', 'Cloudflare (fallback)');
        case DeblockerDeliveryMode.directOnly:
          return _t(context, 'Без проксирования', 'No proxying');
      }
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Статус строка
          Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 4,
            children: [
              AnimatedContainer(
                duration: AppTheme.motionMedium,
                curve: AppTheme.emphasizedCurve,
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _dotColor,
                  boxShadow: status.state == TunnelState.connected
                      ? [
                          BoxShadow(
                            color: AppTheme.connected.withValues(alpha: 0.5),
                            blurRadius: 6,
                          ),
                        ]
                      : null,
                ),
              ),
              Text(
                status.statusText.isNotEmpty
                    ? status.statusText
                    : fallbackState,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: _dotColor,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ],
          ),

          if (status.state == TunnelState.connected &&
              activeProfile != null) ...[
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 12),

            if (activeCountryName != null &&
                activeCountryName!.trim().isNotEmpty) ...[
              _InfoRow(
                icon: Icons.flag_rounded,
                label: _t(context, 'Страна', 'Country'),
                value:
                    '${activeFlagEmoji != null && activeFlagEmoji!.isNotEmpty ? '${activeFlagEmoji!} ' : ''}${activeCountryName!}',
              ),
              const SizedBox(height: 8),
            ],

            // Сервер
            _InfoRow(
              icon: Icons.dns_rounded,
              label: _t(context, 'Сервер', 'Server'),
              value: activeProfile!.server,
            ),
            const SizedBox(height: 8),

            // Протокол
            _InfoRow(
              icon: Icons.security_rounded,
              label: _t(context, 'Протокол', 'Protocol'),
              value: activeProfile!.protocolLabel,
            ),

            // Задержка
            if (status.latencyMs >= 0) ...[
              const SizedBox(height: 8),
              _InfoRow(
                icon: Icons.speed_rounded,
                label: _t(context, 'Задержка', 'Latency'),
                value: '${status.latencyMs} ${_t(context, 'мс', 'ms')}',
                valueColor: _latencyColor(status.latencyMs),
              ),
            ],

            // Режим маршрутизации
            const SizedBox(height: 8),
            _InfoRow(
              icon: Icons.route_rounded,
              label: _t(context, 'Маршрут', 'Route'),
              value: routingName(status.routingMode),
            ),
          ],

          if (status.state == TunnelState.connected &&
              offlineDeblockProfile != null) ...[
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 12),
            _InfoRow(
              icon: Icons.tune_rounded,
              label: _t(context, 'Профиль', 'Profile'),
              value: profileName(offlineDeblockProfile!),
            ),
            const SizedBox(height: 8),
            _InfoRow(
              icon: Icons.shield_rounded,
              label: _t(context, 'Режим', 'Mode'),
              value: runtimeStatus(offlineDeblockProfile!),
            ),
            if (deblockerRuntimeBundle != null) ...[
              const SizedBox(height: 8),
              _InfoRow(
                icon: Icons.alt_route_rounded,
                label: _t(context, 'Канал', 'Channel'),
                value:
                    '${deliveryModeLabel(deblockerRuntimeBundle!.deliveryMode)}${strictAllowlistModeEnabled ? ' • надёжный' : ''}',
              ),
            ],
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                offlineDeblockProfile!.highlights.take(2).join(' • '),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppTheme.textSecondary,
                      height: 1.35,
                    ),
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                offlineDeblockProfile!.limitationText,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppTheme.textDisabled,
                      height: 1.35,
                    ),
              ),
            ),
          ],

          if (status.state == TunnelState.error &&
              status.errorMessage.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              status.errorMessage,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppTheme.error,
                  ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }

  Color get _dotColor {
    switch (status.state) {
      case TunnelState.connected:
        return AppTheme.connected;
      case TunnelState.connecting:
        return AppTheme.connecting;
      case TunnelState.error:
        return AppTheme.error;
      case TunnelState.stopped:
        return AppTheme.textDisabled;
    }
  }

  Color _latencyColor(int ms) {
    if (ms < 150) return AppTheme.connected;
    if (ms < 400) return AppTheme.connecting;
    return AppTheme.error;
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: AppTheme.textSecondary),
        const SizedBox(width: 8),
        Expanded(
          flex: 4,
          child: Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 6,
          child: Text(
            value,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.end,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: valueColor ?? AppTheme.textPrimary,
                  fontWeight: FontWeight.w500,
                ),
          ),
        ),
      ],
    );
  }
}

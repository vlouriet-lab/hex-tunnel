import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'package:provider/provider.dart';
import '../l10n/app_strings.dart';
import '../models/app_connection_mode.dart';
import '../models/installed_app.dart';
import '../models/offline_deblock_profile.dart';
import '../models/proxy_profile.dart';
import '../models/routing_mode.dart';
import '../models/split_tunneling.dart';
import '../models/tunnel_status.dart';
import '../services/key_loader_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_logo_mark.dart';
import '../widgets/connection_button.dart';
import '../widgets/status_card.dart';
import '../providers/tunnel_provider.dart';

String _t(BuildContext context, String ru, String en) {
  return context.l10n.isRussian ? ru : en;
}

String _connectionModeDisplay(BuildContext context, AppConnectionMode mode) {
  switch (mode) {
    case AppConnectionMode.tunnel:
      return _t(context, 'Туннель', 'Tunnel');
    case AppConnectionMode.offlineDeblock:
      return _t(context, 'Деблокер', 'Deblocker');
  }
}

String _connectionModeIdleText(BuildContext context, AppConnectionMode mode) {
  switch (mode) {
    case AppConnectionMode.tunnel:
      return _t(context, 'Нажмите для подключения', 'Tap to connect');
    case AppConnectionMode.offlineDeblock:
      return _t(
        context,
        'Нажмите для запуска деблокера',
        'Tap to start Deblocker',
      );
  }
}

String _routingModeDisplay(BuildContext context, RoutingMode mode) {
  switch (mode) {
    case RoutingMode.global:
      return _t(context, 'Глобальный', 'Global');
    case RoutingMode.ruleBased:
      return _t(context, 'Обход блокировок', 'Bypass blocks');
    case RoutingMode.smart:
      return _t(context, 'Умная маршрутизация', 'Smart Routing');
    case RoutingMode.bypassLan:
      return _t(context, 'Все сайты + домашняя сеть', 'All sites + LAN');
    case RoutingMode.ruleBasedRu:
      return _t(context, 'Только российские сайты через VPN',
          'Only RU sites via VPN');
  }
}

String _routingModeDescription(BuildContext context, RoutingMode mode) {
  switch (mode) {
    case RoutingMode.global:
      return _t(context, 'Весь трафик через VPN', 'All traffic via VPN');
    case RoutingMode.ruleBased:
      return _t(
        context,
        'Зарубежные сайты — через VPN, российские — напрямую',
        'Foreign sites via VPN, RU direct',
      );
    case RoutingMode.smart:
      return _t(
        context,
        'Только заблокированные сайты через VPN. Экономит трафик.',
        'Only blocked sites via VPN. Saves bandwidth.',
      );
    case RoutingMode.bypassLan:
      return _t(
        context,
        'Весь трафик через VPN, домашняя сеть напрямую',
        'All traffic via VPN, local network direct',
      );
    case RoutingMode.ruleBasedRu:
      return _t(
        context,
        'Российские сайты через VPN, остальное — напрямую',
        'RU sites via VPN, the rest direct',
      );
  }
}

String _offlineProfileDisplay(BuildContext context, OfflineDeblockProfile p) {
  switch (p) {
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

String _countryName(
  BuildContext context,
  String code,
  String name,
) {
  return KeyLoaderService.toLocalizedCountryName(
    code,
    name,
    useRussian: context.l10n.isRussian,
  );
}

String _tunnelStateLabel(BuildContext context, TunnelState state) {
  switch (state) {
    case TunnelState.stopped:
      return _t(context, 'Отключено', 'Disconnected');
    case TunnelState.connecting:
      return _t(context, 'Подключение…', 'Connecting...');
    case TunnelState.connected:
      return _t(context, 'Подключено', 'Connected');
    case TunnelState.error:
      return _t(context, 'Ошибка', 'Error');
  }
}

/// Главный экран — подключение, статус, выбор сервера.
class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  @override
  Widget build(BuildContext context) {
    final tunnel = context.watch<TunnelProvider>();
    final status = tunnel.effectiveStatus;
    final activeAutoProfile = tunnel.activeAutoProfile;

    return SafeArea(
      child: Column(
        children: [
          _buildAppBar(context),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                children: [
                  const SizedBox(height: 24),

                  _ModeSwitcher(provider: tunnel),

                  const SizedBox(height: 20),

                  // ── Кнопка подключения ───────────────────────────────────
                  ConnectionButton(
                    state: status.state,
                    onTap: () => tunnel.toggleConnection(context),
                  ),

                  const SizedBox(height: 10),
                  Text(
                    status.state == TunnelState.stopped
                        ? (tunnel.isTemporarilyPaused
                            ? tunnel.temporaryPauseStatusText
                            : _connectionModeIdleText(
                                context, tunnel.connectionMode))
                        : (status.statusText.isNotEmpty
                            ? status.statusText
                            : _tunnelStateLabel(context, status.state)),
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),

                  const SizedBox(height: 28),

                  // ── Карточка статуса ─────────────────────────────────────
                  StatusCard(
                    status: status,
                    activeProfile:
                        tunnel.isTunnelMode ? tunnel.activeProfile : null,
                    offlineDeblockProfile: tunnel.isOfflineDeblockMode
                        ? tunnel.offlineDeblockProfile
                        : null,
                    deblockerRuntimeBundle: tunnel.isOfflineDeblockMode
                        ? (tunnel.deblockerRuntimeBundle ??
                            (tunnel.strictAllowlistModeEnabled
                                ? tunnel.cachedIngressRuntimeBundle
                                : null))
                        : null,
                    strictAllowlistModeEnabled:
                        tunnel.strictAllowlistModeEnabled,
                    activeCountryName:
                        !tunnel.isTunnelMode || activeAutoProfile == null
                            ? null
                            : _countryName(
                                context,
                                activeAutoProfile.countryCode,
                                activeAutoProfile.countryName,
                              ),
                    activeFlagEmoji: activeAutoProfile?.flagEmoji,
                  ),

                  const SizedBox(height: 20),

                  if (tunnel.isTunnelMode)
                    _ServerSelector(
                      provider: tunnel,
                      isLoading: tunnel.isLoadingKeys,
                      onRefresh: () => tunnel.refreshKeys(context),
                    )
                  else
                    _OfflineDeblockCard(profile: tunnel.offlineDeblockProfile),



                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAppBar(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final chipMaxWidth = math.max(112.0, screenWidth * 0.42);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          // Логотип / заголовок
          Expanded(
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: AppTheme.primary.withValues(alpha: 0.4),
                    ),
                  ),
                  child: const Center(
                    child: AppLogoMark(
                      size: 16,
                      color: AppTheme.primary,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Hex Tunnel',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          // Режим маршрутизации / профиль деблока
          Consumer<TunnelProvider>(
            builder: (_, tunnel, __) => GestureDetector(
              onTap: () {
                if (tunnel.isTunnelMode) {
                  _showRoutingMenu(context, tunnel);
                } else {
                  _showDeblockProfileMenu(context, tunnel);
                }
              },
              child: Container(
                constraints: BoxConstraints(maxWidth: chipMaxWidth),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceVariant,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppTheme.border),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      tunnel.isTunnelMode
                          ? Icons.route_rounded
                          : Icons.offline_bolt_rounded,
                      size: 14,
                      color: AppTheme.primary,
                    ),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        tunnel.isTunnelMode
                            ? _routingModeDisplay(context, tunnel.routingMode)
                            : _offlineProfileDisplay(
                                context,
                                tunnel.offlineDeblockProfile,
                              ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppTheme.textSecondary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showRoutingMenu(BuildContext context, TunnelProvider tunnel) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SingleChildScrollView(child: _RoutingSheet(tunnel: tunnel)),
    );
  }

  void _showDeblockProfileMenu(BuildContext context, TunnelProvider tunnel) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _DeblockProfileSheet(tunnel: tunnel),
    );
  }


}

class _ModeSwitcher extends StatelessWidget {
  final TunnelProvider provider;

  const _ModeSwitcher({required this.provider});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: AppConnectionMode.values.map((mode) {
          final selected = provider.connectionMode == mode;
          return Expanded(
            child: GestureDetector(
              onTap: () async {
                await provider.setConnectionMode(mode);
              },
              child: AnimatedContainer(
                duration: AppTheme.motionFast,
                curve: AppTheme.emphasizedCurve,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                decoration: BoxDecoration(
                  color: selected
                      ? AppTheme.primary.withValues(alpha: 0.14)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: selected ? AppTheme.primary : Colors.transparent,
                  ),
                ),
                child: Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      _connectionModeDisplay(context, mode),
                      maxLines: 1,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            color: selected
                                ? AppTheme.primaryLight
                                : AppTheme.textPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ),
                ),
              ),
            ),
          );
        }).toList(growable: false),
      ),
    );
  }
}

class _OfflineDeblockCard extends StatelessWidget {
  final OfflineDeblockProfile profile;

  const _OfflineDeblockCard({required this.profile});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.offline_bolt_rounded,
                color: AppTheme.primary,
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                _t(context, 'Деблокер', 'Deblocker'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            _offlineProfileDisplay(context, profile),
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: AppTheme.primaryLight,
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 6),
          Text(
            profile.description,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          ...profile.highlights.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 3),
                    child: Icon(
                      Icons.check_circle_outline_rounded,
                      size: 14,
                      color: AppTheme.primary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      item,
                      style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            profile.limitationText,
            style: const TextStyle(
              color: AppTheme.textDisabled,
              fontSize: 12,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Виджет выбора сервера ─────────────────────────────────────────────────────

class _ServerSelector extends StatelessWidget {
  final TunnelProvider provider;
  final bool isLoading;
  final VoidCallback onRefresh;

  const _ServerSelector({
    required this.provider,
    required this.isLoading,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final manualProfiles = provider.manualProfiles;
    final customSourceGroups = provider.customSourceProfileGroups;
    final hasCustomProfiles = manualProfiles.isNotEmpty ||
        customSourceGroups.isNotEmpty ||
        provider.enabledCustomKeySources.isNotEmpty;
    final allCountries = _groupCountries(
      context,
      provider.allAutoProfiles.where(
        (profile) => profile.countryCode.trim().toUpperCase() != 'RU',
      ),
    );
    final whiteListCountries = _groupCountries(
      context,
      provider.allAutoProfiles.where(
        (profile) =>
            profile.listType == KeyListType.whiteList &&
            profile.countryCode.trim().toUpperCase() != 'RU',
      ),
    );
    final russianProfiles = provider.allAutoProfiles
        .where((profile) => profile.countryCode.trim().toUpperCase() == 'RU')
        .toList(growable: false);
    final autoTotal = allCountries.length +
        whiteListCountries.length +
        russianProfiles.length;
    final hasAnySections = autoTotal > 0 || hasCustomProfiles;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              l10n.serversTitle,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const Spacer(),
            if (isLoading)
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppTheme.primary,
                ),
              )
            else
              GestureDetector(
                onTap: onRefresh,
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceVariant,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.refresh_rounded,
                    size: 16,
                    color: AppTheme.primary,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (!hasAnySections && !isLoading)
          _EmptyServersHint(onRefresh: onRefresh)
        else ...[
          if (provider.selectionNotice.isNotEmpty) ...[
            _SelectionNoticeCard(
              message: provider.selectionNotice,
              onClose: provider.clearSelectionNotice,
            ),
            const SizedBox(height: 10),
          ],
          if (autoTotal > 0) ...[
            _CountrySection(
              title: l10n.allLabel,
              scope: AutoSelectionScope.allCountries,
              countries: allCountries,
              selectedCountryCode: provider.selectedAllCountryCode,
              selectedScope: provider.homeSelectionScope,
              onSelectCountry: provider.selectCountryForHome,
            ),
            const SizedBox(height: 10),
            _CountrySection(
              title: l10n.whiteListLabel,
              scope: AutoSelectionScope.whiteList,
              countries: whiteListCountries,
              selectedCountryCode: provider.selectedWhiteListCountryCode,
              selectedScope: provider.homeSelectionScope,
              onSelectCountry: provider.selectCountryForHome,
            ),
            const SizedBox(height: 10),
            _RussiaSection(
              provider: provider,
              profiles: russianProfiles,
              isSelected:
                  provider.homeSelectionScope == AutoSelectionScope.russia,
              activeCountryName: _activeCountryName(context, provider),
            ),
          ],
          if (hasCustomProfiles) ...[
            if (autoTotal > 0) const SizedBox(height: 10),
            _CustomProfilesSection(
              provider: provider,
              manualProfiles: manualProfiles,
              sourceGroups: customSourceGroups,
            ),
          ],
        ],
      ],
    );
  }

  String? _activeCountryName(BuildContext context, TunnelProvider provider) {
    final active = provider.activeAutoProfile;
    if (active == null) {
      return null;
    }
    return KeyLoaderService.toLocalizedCountryName(
      active.countryCode,
      active.countryName,
      useRussian: context.l10n.isRussian,
    );
  }

  List<_CountryOption> _groupCountries(
    BuildContext context,
    Iterable<AutoProfile> profiles,
  ) {
    final grouped = <String, List<AutoProfile>>{};
    for (final profile in profiles) {
      final code = profile.countryCode.trim().toUpperCase();
      if (code.isEmpty) {
        continue;
      }
      grouped.putIfAbsent(code, () => <AutoProfile>[]).add(profile);
    }

    final options = grouped.entries.map((entry) {
      entry.value.sort((a, b) {
        final aLatency = a.latencyMs >= 0 ? a.latencyMs : 100000;
        final bLatency = b.latencyMs >= 0 ? b.latencyMs : 100000;
        final byLatency = aLatency.compareTo(bLatency);
        if (byLatency != 0) {
          return byLatency;
        }
        return a.profile.server.compareTo(b.profile.server);
      });
      final representative = entry.value.first;
      return _CountryOption(
        code: entry.key,
        name: _countryName(
          context,
          representative.countryCode,
          representative.countryName,
        ),
        flagEmoji: representative.flagEmoji,
        profilesCount: entry.value.length,
        bestLatencyMs: representative.latencyMs,
      );
    }).toList(growable: false);

    options.sort((a, b) {
      final aLatency = a.bestLatencyMs >= 0 ? a.bestLatencyMs : 100000;
      final bLatency = b.bestLatencyMs >= 0 ? b.bestLatencyMs : 100000;
      final byLatency = aLatency.compareTo(bLatency);
      if (byLatency != 0) {
        return byLatency;
      }
      return a.name.compareTo(b.name);
    });
    return options;
  }
}

class _SelectionNoticeCard extends StatelessWidget {
  final String message;
  final VoidCallback onClose;

  const _SelectionNoticeCard({
    required this.message,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.connecting.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppTheme.connecting.withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: Icon(
              Icons.info_outline_rounded,
              size: 18,
              color: AppTheme.connecting,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 13,
                height: 1.35,
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: onClose,
            child: const Icon(
              Icons.close_rounded,
              size: 18,
              color: AppTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _RussiaSection extends StatelessWidget {
  final TunnelProvider provider;
  final List<AutoProfile> profiles;
  final bool isSelected;
  final String? activeCountryName;

  const _RussiaSection({
    required this.provider,
    required this.profiles,
    required this.isSelected,
    required this.activeCountryName,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final count = profiles.length;
    final allCount = count;
    final whiteListCount =
        profiles.where((p) => p.listType == KeyListType.whiteList).length;

    final selectedListType = provider.selectedRussiaListType;
    final isAllSelected = selectedListType == KeyListType.blackList;
    final isWhiteListSelected = selectedListType == KeyListType.whiteList;

    return _SectionCard(
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
          title: Row(
            children: [
              Expanded(
                child: Text(
                  l10n.russiaLabel,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
            ],
          ),
          subtitle: Text(
            count > 0 ? l10n.keysCount(count) : l10n.russianKeysNotLoaded,
            style: const TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 12,
            ),
          ),
          iconColor: AppTheme.primary,
          collapsedIconColor: AppTheme.textSecondary,
          children: [
            if (count == 0)
              Padding(
                padding: EdgeInsets.only(top: 4),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    l10n.noKeys,
                    style: TextStyle(
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ),
              )
            else ...[
              _RussiaTile(
                flagEmoji: '🇷🇺',
                label: l10n.allLabel,
                count: allCount,
                isSelected: isSelected && isAllSelected,
                onTap: count > 0
                    ? () => provider.selectRussiaListType(KeyListType.blackList)
                    : null,
              ),
              const SizedBox(height: 8),
              _RussiaTile(
                flagEmoji: '🇷🇺',
                label: l10n.whiteListLabel,
                count: whiteListCount,
                isSelected: isSelected && isWhiteListSelected,
                onTap: count > 0
                    ? () => provider.selectRussiaListType(KeyListType.whiteList)
                    : null,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _RussiaTile extends StatelessWidget {
  final String flagEmoji;
  final String label;
  final int count;
  final bool isSelected;
  final VoidCallback? onTap;

  const _RussiaTile({
    required this.flagEmoji,
    required this.label,
    required this.count,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: AppTheme.motionFast,
        curve: AppTheme.emphasizedCurve,
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: isSelected
              ? AppTheme.primary.withValues(alpha: 0.12)
              : AppTheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? AppTheme.primary : AppTheme.border,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Text(
              flagEmoji,
              style: const TextStyle(fontSize: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w500,
                          color: isSelected
                              ? AppTheme.primaryLight
                              : AppTheme.textPrimary,
                        ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    context.l10n.keysCount(count),
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
            if (isSelected) ...[
              const SizedBox(width: 8),
              const Icon(
                Icons.check_circle_rounded,
                size: 18,
                color: AppTheme.primary,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CountrySection extends StatelessWidget {
  final String title;
  final AutoSelectionScope scope;
  final List<_CountryOption> countries;
  final String? selectedCountryCode;
  final AutoSelectionScope selectedScope;
  final void Function(AutoSelectionScope scope, String countryCode)
      onSelectCountry;

  const _CountrySection({
    required this.title,
    required this.scope,
    required this.countries,
    required this.selectedCountryCode,
    required this.selectedScope,
    required this.onSelectCountry,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final selectedOption = countries.cast<_CountryOption?>().firstWhere(
          (country) => country?.code == selectedCountryCode,
          orElse: () => null,
        );

    return _SectionCard(
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
          title: Text(
            title,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
          subtitle: Text(
            selectedOption == null
                ? l10n.countriesCount(countries.length)
                : l10n.selectedCountry(
                    selectedOption.flagEmoji,
                    selectedOption.name,
                  ),
            style: const TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 12,
            ),
          ),
          iconColor: AppTheme.primary,
          collapsedIconColor: AppTheme.textSecondary,
          children: [
            if (countries.isEmpty)
              Padding(
                padding: EdgeInsets.only(top: 4),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    l10n.noCountries,
                    style: TextStyle(
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ),
              )
            else
              ...countries.map((country) {
                final selected = selectedScope == scope &&
                    selectedCountryCode == country.code;
                return _CountryTile(
                  country: country,
                  isSelected: selected,
                  onTap: () => onSelectCountry(scope, country.code),
                );
              }),
          ],
        ),
      ),
    );
  }
}

class _CountryTile extends StatelessWidget {
  final _CountryOption country;
  final bool isSelected;
  final VoidCallback onTap;

  const _CountryTile({
    required this.country,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: AppTheme.motionFast,
        curve: AppTheme.emphasizedCurve,
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: isSelected
              ? AppTheme.primary.withValues(alpha: 0.12)
              : AppTheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? AppTheme.primary : AppTheme.border,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Text(
              country.flagEmoji,
              style: const TextStyle(fontSize: 22),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    country.name,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w500,
                          color: isSelected
                              ? AppTheme.primaryLight
                              : AppTheme.textPrimary,
                        ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    context.l10n.keysCount(country.profilesCount),
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
            if (country.bestLatencyMs >= 0) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _latencyColor(country.bestLatencyMs)
                      .withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${country.bestLatencyMs}ms',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: _latencyColor(country.bestLatencyMs),
                  ),
                ),
              ),
            ],
            if (isSelected) ...[
              const SizedBox(width: 8),
              const Icon(
                Icons.check_circle_rounded,
                size: 18,
                color: AppTheme.primary,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Color _latencyColor(int ms) {
    if (ms < 150) return AppTheme.connected;
    if (ms < 400) return AppTheme.connecting;
    return AppTheme.error;
  }
}

class _CustomProfilesSection extends StatelessWidget {
  final TunnelProvider provider;
  final List<ProxyProfile> manualProfiles;
  final List<CustomSourceProfilesGroup> sourceGroups;

  const _CustomProfilesSection({
    required this.provider,
    required this.manualProfiles,
    required this.sourceGroups,
  });

  @override
  Widget build(BuildContext context) {
    final activeManualProfile =
        provider.activeAutoProfile == null ? provider.activeProfile : null;
    final totalCount = manualProfiles.length +
        sourceGroups.fold<int>(0, (sum, group) => sum + group.profiles.length);
    final subtitle = activeManualProfile != null
        ? _displayProfileName(activeManualProfile)
        : totalCount > 0
            ? _t(context, 'Ключей: $totalCount', 'Keys: $totalCount')
            : _t(
                context,
                'Источники добавлены, но профили ещё не загружены',
                'Sources added, but profiles are not loaded yet',
              );

    return _SectionCard(
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
          title: Text(
            _t(context, 'Пользовательские', 'Custom'),
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
          subtitle: Text(
            subtitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 12,
            ),
          ),
          iconColor: AppTheme.primary,
          collapsedIconColor: AppTheme.textSecondary,
          children: [
            if (manualProfiles.isEmpty && sourceGroups.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _t(
                      context,
                      'Пользовательские источники добавлены, но активных профилей пока нет.',
                      'Custom sources were added, but there are no active profiles yet.',
                    ),
                    style: const TextStyle(
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ),
              )
            else ...[
              if (manualProfiles.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      _t(context, 'Ручные ключи', 'Manual keys'),
                      style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                ...manualProfiles.map(
                  (profile) => _CustomProfileTile(
                    profile: profile,
                    isSelected: activeManualProfile?.rawUri == profile.rawUri,
                    onTap: () => provider.selectManualProfile(profile),
                  ),
                ),
                if (sourceGroups.isNotEmpty) const SizedBox(height: 4),
              ],
              ...sourceGroups.map(
                (group) => _CustomSourceGroupCard(
                  group: group,
                  activeRawUri: activeManualProfile?.rawUri,
                  onSelect: provider.selectManualProfile,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CustomSourceGroupCard extends StatefulWidget {
  final CustomSourceProfilesGroup group;
  final String? activeRawUri;
  final ValueChanged<ProxyProfile> onSelect;

  const _CustomSourceGroupCard({
    required this.group,
    required this.activeRawUri,
    required this.onSelect,
  });

  @override
  State<_CustomSourceGroupCard> createState() => _CustomSourceGroupCardState();
}

class _CustomSourceGroupCardState extends State<_CustomSourceGroupCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final selectedProfile =
        widget.group.profiles.cast<ProxyProfile?>().firstWhere(
              (profile) => profile?.rawUri == widget.activeRawUri,
              orElse: () => null,
            );
    final hasError = widget.group.errorMessage?.trim().isNotEmpty == true;
    final subtitle = hasError
        ? widget.group.errorMessage!
        : selectedProfile != null
            ? _t(
                context,
                'Активен: ${_displayProfileName(selectedProfile)}',
                'Active: ${_displayProfileName(selectedProfile)}',
              )
            : widget.group.profiles.isNotEmpty
                ? _t(
                    context,
                    'Ключей: ${widget.group.profiles.length}',
                    'Keys: ${widget.group.profiles.length}',
                  )
                : _t(
                    context,
                    'Профили не найдены',
                    'No profiles found',
                  );

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppTheme.background.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: selectedProfile != null
              ? AppTheme.primary.withValues(alpha: 0.45)
              : hasError
                  ? AppTheme.error.withValues(alpha: 0.45)
                  : AppTheme.border,
        ),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.link_rounded,
                      color: AppTheme.primary,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.group.source.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              Theme.of(context).textTheme.bodyLarge?.copyWith(
                                    fontWeight: FontWeight.w500,
                                  ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: hasError
                                ? AppTheme.error
                                : AppTheme.textSecondary,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    color: AppTheme.textSecondary,
                    size: 18,
                  ),
                ],
              ),
            ),
          ),
          if (_expanded && widget.group.profiles.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
              child: Column(
                children: widget.group.profiles
                    .map(
                      (profile) => _CustomProfileTile(
                        profile: profile,
                        isSelected: widget.activeRawUri == profile.rawUri,
                        onTap: () => widget.onSelect(profile),
                        subtitle: _t(
                          context,
                          'Источник: ${widget.group.source.name}',
                          'Source: ${widget.group.source.name}',
                        ),
                      ),
                    )
                    .toList(growable: false),
              ),
            ),
        ],
      ),
    );
  }
}

class _CustomProfileTile extends StatelessWidget {
  final ProxyProfile profile;
  final bool isSelected;
  final VoidCallback onTap;
  final String? subtitle;

  const _CustomProfileTile({
    required this.profile,
    required this.isSelected,
    required this.onTap,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final secondaryText = subtitle?.trim().isNotEmpty == true
        ? subtitle!
        : '${profile.server}:${profile.port}';

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: AppTheme.motionFast,
        curve: AppTheme.emphasizedCurve,
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected
              ? AppTheme.primary.withValues(alpha: 0.12)
              : AppTheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? AppTheme.primary : AppTheme.border,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            _ProfileProtocolBadge(protocol: profile.protocol),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _displayProfileName(profile),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w500,
                          color: isSelected
                              ? AppTheme.primaryLight
                              : AppTheme.textPrimary,
                        ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    secondaryText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
            if (isSelected) ...[
              const SizedBox(width: 8),
              const Icon(
                Icons.check_circle_rounded,
                size: 18,
                color: AppTheme.primary,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ProfileProtocolBadge extends StatelessWidget {
  final String protocol;

  const _ProfileProtocolBadge({required this.protocol});

  @override
  Widget build(BuildContext context) {
    final color = switch (protocol.toLowerCase()) {
      'vless' => const Color(0xFF7C3AED),
      'ss' || 'shadowsocks' => const Color(0xFF0EA5E9),
      'trojan' => const Color(0xFF10B981),
      'tuic' => const Color(0xFFF59E0B),
      _ => AppTheme.textSecondary,
    };
    final label = protocol.length > 4
        ? protocol.substring(0, 4).toUpperCase()
        : protocol.toUpperCase();

    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Center(
        child: Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 9,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

String _displayProfileName(ProxyProfile profile) {
  final name = profile.name.trim();
  if (name.isNotEmpty) {
    return name;
  }
  return '${profile.server}:${profile.port}';
}

class _SectionCard extends StatelessWidget {
  final Widget child;

  const _SectionCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
      ),
      child: child,
    );
  }
}

class _CountryOption {
  final String code;
  final String name;
  final String flagEmoji;
  final int profilesCount;
  final int bestLatencyMs;

  const _CountryOption({
    required this.code,
    required this.name,
    required this.flagEmoji,
    required this.profilesCount,
    required this.bestLatencyMs,
  });
}

class _EmptyServersHint extends StatelessWidget {
  final VoidCallback onRefresh;
  const _EmptyServersHint({required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        children: [
          const Icon(
            Icons.cloud_download_outlined,
            size: 40,
            color: AppTheme.textDisabled,
          ),
          const SizedBox(height: 12),
          Text(
            l10n.serversNotLoaded,
            style: TextStyle(
              color: AppTheme.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            l10n.tapToRefreshServers,
            style: TextStyle(
              fontSize: 12,
              color: AppTheme.textDisabled,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onRefresh,
              icon: const Icon(Icons.download_rounded, size: 16),
              label: Text(l10n.downloadServers),
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.primary,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Выбор режима маршрутизации ────────────────────────────────────────────────

class _RoutingSheet extends StatelessWidget {
  final TunnelProvider tunnel;
  const _RoutingSheet({required this.tunnel});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: AppTheme.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            l10n.routingModeTitle,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 4),
          Text(
            l10n.routingModeSubtitle,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          ...RoutingMode.values.map((mode) {
            final selected = tunnel.routingMode == mode;
            return ListTile(
              onTap: () {
                tunnel.setRoutingMode(mode);
                Navigator.pop(context);
              },
              tileColor: selected
                  ? AppTheme.primary.withValues(alpha: 0.1)
                  : Colors.transparent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(
                  color: selected ? AppTheme.primary : Colors.transparent,
                ),
              ),
              leading: Icon(
                _routingIcon(mode),
                color: selected ? AppTheme.primary : AppTheme.textSecondary,
              ),
              title: Text(
                _routingModeDisplay(context, mode),
                style: TextStyle(
                  color:
                      selected ? AppTheme.primaryLight : AppTheme.textPrimary,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
              subtitle: Text(
                _routingModeDescription(context, mode),
                style: const TextStyle(
                  fontSize: 12,
                  color: AppTheme.textDisabled,
                ),
              ),
              trailing: selected
                  ? const Icon(Icons.check_rounded, color: AppTheme.primary)
                  : null,
            );
          }),
        ],
      ),
    );
  }

  IconData _routingIcon(RoutingMode mode) {
    switch (mode) {
      case RoutingMode.global:
        return Icons.public_rounded;
      case RoutingMode.ruleBased:
        return Icons.filter_alt_rounded;
      case RoutingMode.smart:
        return Icons.auto_awesome_rounded;
      case RoutingMode.bypassLan:
        return Icons.wifi_rounded;
      case RoutingMode.ruleBasedRu:
        return Icons.flag_rounded;
    }
  }
}

class _DeblockProfileSheet extends StatelessWidget {
  final TunnelProvider tunnel;

  const _DeblockProfileSheet({required this.tunnel});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: AppTheme.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            _t(context, 'Профиль деблокера', 'Deblocker profile'),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 4),
          Text(
            _t(context, 'Выберите режим работы деблокера',
                'Select deblocker mode'),
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          ...OfflineDeblockProfile.values.map((profile) {
            final selected = tunnel.offlineDeblockProfile == profile;
            return ListTile(
              onTap: () {
                tunnel.setOfflineDeblockProfile(profile);
                Navigator.pop(context);
              },
              tileColor: selected
                  ? AppTheme.primary.withValues(alpha: 0.1)
                  : Colors.transparent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(
                  color: selected ? AppTheme.primary : Colors.transparent,
                ),
              ),
              leading: Icon(
                Icons.offline_bolt_rounded,
                color: selected ? AppTheme.primary : AppTheme.textSecondary,
              ),
              title: Text(
                _offlineProfileDisplay(context, profile),
                style: TextStyle(
                  color:
                      selected ? AppTheme.primaryLight : AppTheme.textPrimary,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
              trailing: selected
                  ? const Icon(Icons.check_rounded, color: AppTheme.primary)
                  : null,
            );
          }),
        ],
      ),
    );
  }
}


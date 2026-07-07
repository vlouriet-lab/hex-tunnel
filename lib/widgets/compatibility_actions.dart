import '../l10n/app_strings.dart';
import '../models/installed_app.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/tunnel_provider.dart';
import '../theme/app_theme.dart';
import '../models/split_tunneling.dart';

class CompatibilityActionsCard extends StatelessWidget {
  final TunnelProvider provider;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onManageApps;

  const CompatibilityActionsCard({
    super.key,
    required this.provider,
    required this.onPause,
    required this.onResume,
    required this.onManageApps,
  });

  @override
  Widget build(BuildContext context) {
    final message = provider.isTemporarilyPaused
        ? _t(
            context,
            'Туннель временно остановлен. Если нужно, можно возобновить раньше.',
            'The tunnel is temporarily paused. You can resume it earlier if needed.',
          )
        : provider.hasVpnCompatibilityBypass
            ? _t(
                context,
                'Приложений вне VPN: ${provider.vpnCompatibilityBypassCount}. Они будут работать напрямую и не увидят активный VPN.',
                'Apps outside VPN: ${provider.vpnCompatibilityBypassCount}. They will work directly and will not see an active VPN.',
              )
            : _t(
                context,
                'Если приложение отказывается работать с VPN, добавьте его в исключения. Оно пойдёт напрямую, остальной трафик останется в туннеле.',
                'If an app refuses to work with VPN, add it to exclusions. It will go directly while the rest stays in the tunnel.',
              );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
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
                Icons.apps_rounded,
                size: 18,
                color: AppTheme.primary,
              ),
              const SizedBox(width: 8),
              Text(
                _t(context, 'Совместимость приложений', 'App compatibility'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            message,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppTheme.textSecondary,
                  height: 1.35,
                ),
          ),
          if (provider.hasAdaptiveMitigations) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppTheme.primary.withValues(alpha: 0.18),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 1),
                    child: Icon(
                      Icons.auto_awesome_rounded,
                      size: 16,
                      color: AppTheme.primary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _t(
                        context,
                        'Автоадаптация: ${provider.adaptiveMitigationSummary}',
                        'Auto-adaptation: ${provider.adaptiveMitigationSummary}',
                      ),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppTheme.primaryLight,
                            height: 1.35,
                          ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: onManageApps,
                  icon: const Icon(Icons.rule_folder_outlined, size: 18),
                  label: Text(
                    provider.hasVpnCompatibilityBypass
                        ? _t(context, 'Изменить исключения', 'Edit exclusions')
                        : _t(context, 'Исключить приложения', 'Exclude apps'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: provider.isTemporarilyPaused ? onResume : onPause,
                  icon: Icon(
                    provider.isTemporarilyPaused
                        ? Icons.play_arrow_rounded
                        : Icons.pause_circle_outline_rounded,
                    size: 18,
                  ),
                  label: Text(
                    provider.isTemporarilyPaused
                        ? _t(context, 'Возобновить', 'Resume')
                        : _t(context, 'Пауза 5 мин', 'Pause 5 min'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class CompatibilityAppsSheet extends StatefulWidget {
  const CompatibilityAppsSheet({super.key});

  @override
  State<CompatibilityAppsSheet> createState() =>
      CompatibilityAppsSheetState();
}

class CompatibilityAppsSheetState extends State<CompatibilityAppsSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<TunnelProvider>();
    final query = _query.trim().toLowerCase();
    final selectedPackages =
        provider.splitTunnelingMode == SplitTunnelingMode.exceptSelected
            ? provider.splitTunnelPackages.toSet()
            : const <String>{};
    final apps =
        provider.installedApps.where((app) => !app.systemApp).where((app) {
      if (query.isEmpty) {
        return true;
      }
      return app.label.toLowerCase().contains(query) ||
          app.packageName.toLowerCase().contains(query);
    }).toList(growable: false)
          ..sort((a, b) {
            final aSelected = selectedPackages.contains(a.packageName);
            final bSelected = selectedPackages.contains(b.packageName);
            if (aSelected != bSelected) {
              return aSelected ? -1 : 1;
            }
            return a.label.toLowerCase().compareTo(b.label.toLowerCase());
          });

    return SafeArea(
      top: false,
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.82,
        child: Column(
          children: [
            Container(
              width: 42,
              height: 4,
              margin: const EdgeInsets.only(top: 12, bottom: 16),
              decoration: BoxDecoration(
                color: AppTheme.border,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _t(context, 'Исключения из VPN', 'VPN exclusions'),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _t(
                      context,
                      'Отмеченные приложения будут работать напрямую и не увидят активный VPN. Для них автоматически включается режим «Кроме этих приложений».',
                      'Selected apps will work directly and will not see an active VPN. This automatically enables the “Except these apps” mode.',
                    ),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppTheme.textSecondary,
                          height: 1.35,
                        ),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      color: AppTheme.background.withValues(alpha: 0.45),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppTheme.border),
                    ),
                    child: TextField(
                      onChanged: (value) => setState(() => _query = value),
                      style: const TextStyle(color: AppTheme.textPrimary),
                      decoration: InputDecoration(
                        border: InputBorder.none,
                        icon: const Icon(
                          Icons.search_rounded,
                          color: AppTheme.textSecondary,
                        ),
                        hintText: _t(
                          context,
                          'Название или пакет приложения',
                          'App name or package',
                        ),
                        hintStyle: const TextStyle(
                          color: AppTheme.textDisabled,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    provider.hasVpnCompatibilityBypass
                        ? _t(
                            context,
                            'Сейчас вне VPN: ${provider.vpnCompatibilityBypassCount}',
                            'Currently outside VPN: ${provider.vpnCompatibilityBypassCount}',
                          )
                        : _t(
                            context,
                            'Пока исключений нет',
                            'No exclusions yet',
                          ),
                    style: const TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: provider.isLoadingInstalledApps
                  ? const Center(
                      child: CircularProgressIndicator(color: AppTheme.primary),
                    )
                  : apps.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 24),
                            child: Text(
                              _t(
                                context,
                                'Подходящие приложения не найдены.',
                                'No matching apps were found.',
                              ),
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: AppTheme.textSecondary,
                              ),
                            ),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                          itemBuilder: (context, index) {
                            final app = apps[index];
                            return CompatibilityAppTile(app: app);
                          },
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 8),
                          itemCount: apps.length,
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

class CompatibilityAppTile extends StatelessWidget {
  final InstalledApp app;

  const CompatibilityAppTile({super.key, required this.app});

  @override
  Widget build(BuildContext context) {
    return Selector<TunnelProvider, bool>(
      selector: (_, provider) =>
          provider.splitTunnelingMode == SplitTunnelingMode.exceptSelected &&
          provider.isSplitTunnelPackageSelected(app.packageName),
      builder: (context, selected, _) {
        final provider = context.read<TunnelProvider>();
        return InkWell(
          onTap: () =>
              provider.setVpnBypassForPackage(app.packageName, !selected),
          borderRadius: BorderRadius.circular(14),
          child: AnimatedContainer(
            duration: AppTheme.motionFast,
            curve: AppTheme.emphasizedCurve,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: selected
                  ? AppTheme.primary.withValues(alpha: 0.12)
                  : AppTheme.background.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: selected ? AppTheme.primary : AppTheme.border,
                width: selected ? 1.4 : 1,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceVariant,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    selected
                        ? Icons.open_in_browser_rounded
                        : Icons.apps_rounded,
                    color: selected ? AppTheme.primary : AppTheme.textSecondary,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        app.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        app.packageName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Switch.adaptive(
                  value: selected,
                  onChanged: (value) =>
                      provider.setVpnBypassForPackage(app.packageName, value),
                  activeThumbColor: AppTheme.primary,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}


String _t(BuildContext context, String ru, String en) {
  return context.l10n.isRussian ? ru : en;
}




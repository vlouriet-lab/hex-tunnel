import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import '../l10n/app_strings.dart';
import '../models/app_connection_mode.dart';
import '../models/custom_key_source.dart';
import '../models/deblocker_runtime_bundle.dart';
import '../models/installed_app.dart';
import '../models/offline_deblock_profile.dart';
import '../models/routing_mode.dart';
import '../models/split_tunneling.dart';
import '../providers/tunnel_provider.dart';
import '../services/key_analysis_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_logo_mark.dart';
import '../widgets/compatibility_actions.dart';

String _t(BuildContext context, String ru, String en) {
  return context.l10n.isRussian ? ru : en;
}

String _modeDisplay(BuildContext context, AppConnectionMode mode) {
  switch (mode) {
    case AppConnectionMode.tunnel:
      return _t(context, 'Туннель', 'Tunnel');
    case AppConnectionMode.offlineDeblock:
      return _t(context, 'Деблокер', 'Deblocker');
  }
}

String _modeDescription(BuildContext context, AppConnectionMode mode) {
  switch (mode) {
    case AppConnectionMode.tunnel:
      return _t(
        context,
        'Удалённый ключ, смена IP и полный туннель',
        'Remote key, IP change, and full tunnel',
      );
    case AppConnectionMode.offlineDeblock:
      return _t(
        context,
        'Локальный деблок без удалённого прокси',
        'Local deblocking without a remote proxy',
      );
  }
}

String _routingTitle(BuildContext context, RoutingMode mode) {
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

String _routingDescription(BuildContext context, RoutingMode mode) {
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

String _keyListTypeTitle(BuildContext context, KeyListType type) {
  switch (type) {
    case KeyListType.blackList:
      return _t(context, 'Туннель', 'Tunnel');
    case KeyListType.whiteList:
      return _t(context, 'Белый список', 'Whitelist');
  }
}

String _splitModeTitle(BuildContext context, SplitTunnelingMode mode) {
  switch (mode) {
    case SplitTunnelingMode.off:
      return _t(context, 'Выключено', 'Off');
    case SplitTunnelingMode.onlySelected:
      return _t(context, 'Только эти приложения', 'Only selected apps');
    case SplitTunnelingMode.exceptSelected:
      return _t(context, 'Кроме этих приложений', 'Except selected apps');
  }
}

String _splitModeDescription(BuildContext context, SplitTunnelingMode mode) {
  switch (mode) {
    case SplitTunnelingMode.off:
      return _t(
        context,
        'Весь трафик приложений обрабатывается одинаково',
        'All app traffic is handled the same way',
      );
    case SplitTunnelingMode.onlySelected:
      return _t(
        context,
        'Через туннель пойдут только выбранные приложения',
        'Only selected apps will use the tunnel',
      );
    case SplitTunnelingMode.exceptSelected:
      return _t(
        context,
        'Через туннель пойдут все приложения, кроме выбранных',
        'All apps except selected ones will use the tunnel',
      );
  }
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text(l10n.appSettings),
        backgroundColor: AppTheme.surface,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Consumer<TunnelProvider>(
        builder: (context, provider, _) {
          return ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              _SettingsNavTile(
                icon: Icons.route_rounded,
                title: _t(context, 'Подключение', 'Connection'),
                subtitle: _t(context, 'Режим, маршрутизация, туннель',
                    'Mode, routing, tunnel'),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ChangeNotifierProvider.value(
                      value: provider,
                      child: const _ConnectionSubScreen(),
                    ),
                  ),
                ),
              ),
              _SettingsNavTile(
                icon: Icons.offline_bolt_rounded,
                title: _t(context, 'Деблокер', 'Deblocker'),
                subtitle: _t(context, 'Профиль, правила, пакет обновлений',
                    'Profile, rules, update bundle'),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ChangeNotifierProvider.value(
                      value: provider,
                      child: const _DeblockSubScreen(),
                    ),
                  ),
                ),
              ),
              _SettingsNavTile(
                icon: Icons.vpn_key_rounded,
                title: _t(context, 'Ключи', 'Keys'),
                subtitle: _t(context, 'Тип, источники, автообновление',
                    'Type, sources, auto-update'),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ChangeNotifierProvider.value(
                      value: provider,
                      child: const _KeysSubScreen(),
                    ),
                  ),
                ),
              ),
              _SettingsNavTile(
                icon: Icons.call_split_rounded,
                title: _t(
                    context, 'Разделённое туннелирование', 'Split tunneling'),
                subtitle: _t(
                    context, 'Выбор приложений для VPN', 'Choose apps for VPN'),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ChangeNotifierProvider.value(
                      value: provider,
                      child: const _SplitTunnelingSubScreen(),
                    ),
                  ),
                ),
              ),
              _SettingsNavTile(
                icon: Icons.science_rounded,
                title: _t(context, 'Инструменты', 'Tools'),
                subtitle: _t(context, 'Анализ ключей', 'Key analysis'),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const _ToolsSubScreen(),
                  ),
                ),
              ),
              _SettingsNavTile(
                icon: Icons.info_outline_rounded,
                title: _t(context, 'Приложение', 'App'),
                subtitle: _t(
                    context, 'Язык, версия, сброс', 'Language, version, reset'),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ChangeNotifierProvider.value(
                      value: provider,
                      child: const _AppSubScreen(),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SettingsNavTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _SettingsNavTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: AppTheme.primary.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: AppTheme.primary, size: 20),
      ),
      title: Text(
        title,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w500,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(
          color: AppTheme.textSecondary,
          fontSize: 12,
        ),
      ),
      trailing: const Icon(
        Icons.chevron_right_rounded,
        color: AppTheme.textSecondary,
      ),
      onTap: onTap,
      enableFeedback: false,
    );
  }
}

class _ConnectionSubScreen extends StatelessWidget {
  const _ConnectionSubScreen();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text(_t(context, 'Подключение', 'Connection')),
        backgroundColor: AppTheme.surface,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Consumer<TunnelProvider>(
        builder: (context, provider, _) {
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _SectionHeader(title: l10n.sectionWorkMode),
              _ConnectionModeCard(provider: provider),
              const SizedBox(height: 24),
              _SectionHeader(title: l10n.sectionRoutingMode),
              _RoutingModeCard(
                current: provider.routingMode,
                onChanged: provider.setRoutingMode,
              ),

              const SizedBox(height: 24),
              _SectionHeader(title: l10n.sectionTunneling),
              _TunnelOptionsCard(provider: provider),
              
              if (provider.isTunnelMode) ...[
                const SizedBox(height: 24),
                _SectionHeader(title: _t(context, 'Совместимость', 'Compatibility')),
                CompatibilityActionsCard(
                  provider: provider,
                  onPause: () => provider.pauseConnectionTemporarily(
                    const Duration(minutes: 5),
                    context: context,
                  ),
                  onResume: () => provider.resumeConnectionAfterPause(context),
                  onManageApps: () {
                    showModalBottomSheet<void>(
                      context: context,
                      isScrollControlled: true,
                      backgroundColor: AppTheme.surface,
                      shape: const RoundedRectangleBorder(
                        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                      ),
                      builder: (_) => const CompatibilityAppsSheet(),
                    );
                  },
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _DeblockSubScreen extends StatelessWidget {
  const _DeblockSubScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text(_t(context, 'Деблокер', 'Deblocker')),
        backgroundColor: AppTheme.surface,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Consumer<TunnelProvider>(
        builder: (context, provider, _) {
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _OfflineDeblockProfileCard(
                provider: provider,
                current: provider.offlineDeblockProfile,
                onChanged: provider.setOfflineDeblockProfile,
              ),
              if (provider.cachedIngressRuntimeBundle != null ||
                  provider.allowlistedIngressFeatureEnabled) ...[
                const SizedBox(height: 8),
                _StrictAllowlistCard(provider: provider),
                const SizedBox(height: 8),
                _IngressBundleStatusCard(provider: provider),
              ],
              if (provider.offlineDeblockProfile ==
                  OfflineDeblockProfile.custom) ...[
                const SizedBox(height: 8),
                _OfflineDeblockCustomCard(
                  settings: provider.offlineDeblockCustomSettings,
                  onChanged: provider.setOfflineDeblockCustomSettings,
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _KeysSubScreen extends StatefulWidget {
  const _KeysSubScreen();

  @override
  State<_KeysSubScreen> createState() => _KeysSubScreenState();
}

class _KeysSubScreenState extends State<_KeysSubScreen> {
  Future<bool> _confirmAction({
    required String title,
    required String message,
    required String confirmLabel,
  }) async {
    final l10n = context.l10n;
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
            ),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _refreshKeys(TunnelProvider provider) async {
    await provider.refreshKeys(
      context,
      allowReserveSources: true,
    );
  }

  Future<void> _deleteAllKeys(TunnelProvider provider) async {
    final l10n = context.l10n;
    final confirmed = await _confirmAction(
      title: l10n.deleteAllKeysTitle,
      message: l10n.deleteAllKeysMessage,
      confirmLabel: l10n.delete,
    );
    if (!confirmed) return;
    await provider.deleteAllKeys();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.deleteKeysDone)),
    );
  }

  Future<void> _resetSettings(TunnelProvider provider) async {
    final l10n = context.l10n;
    final confirmed = await _confirmAction(
      title: l10n.resetSettingsTitle,
      message: l10n.resetSettingsMessage,
      confirmLabel: l10n.reset,
    );
    if (!confirmed) return;
    await provider.resetSettings();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.settingsResetDone)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text(_t(context, 'Ключи', 'Keys')),
        backgroundColor: AppTheme.surface,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Consumer<TunnelProvider>(
        builder: (context, provider, _) {
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _SectionHeader(title: l10n.sectionKeyListType),
              _KeyListTypeCard(
                current: provider.keyListType,
                onChanged: provider.setKeyListType,
              ),
              const SizedBox(height: 24),
              _SectionHeader(title: l10n.sectionAutoKeys),
              _AutoKeysCard(
                isLoading: provider.isLoadingKeys,
                message: provider.loadingMessage,
                count: provider.autoProfiles.length,
                onRefresh: () => _refreshKeys(provider),
                onDeleteAllKeys: () => _deleteAllKeys(provider),
                onResetSettings: () => _resetSettings(provider),
              ),
              const SizedBox(height: 24),
              _SectionHeader(title: l10n.sectionCustomSources),
              _CustomSourcesCard(provider: provider),
            ],
          );
        },
      ),
    );
  }
}

class _SplitTunnelingSubScreen extends StatefulWidget {
  const _SplitTunnelingSubScreen();

  @override
  State<_SplitTunnelingSubScreen> createState() =>
      _SplitTunnelingSubScreenState();
}

class _SplitTunnelingSubScreenState extends State<_SplitTunnelingSubScreen> {
  List<String> _selectedLabels(TunnelProvider provider) {
    if (provider.splitTunnelPackages.isEmpty) {
      return const <String>[];
    }
    final labelsByPackage = <String, String>{
      for (final app in provider.installedApps) app.packageName: app.label,
    };
    return provider.splitTunnelPackages
        .take(3)
        .map((packageName) => labelsByPackage[packageName] ?? packageName)
        .toList(growable: false);
  }

  Future<void> _openSplitTunnelApps(TunnelProvider provider) async {
    try {
      await provider.loadInstalledApps();
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (context) => ChangeNotifierProvider.value(
          value: provider,
          child: const _SplitTunnelAppsSheet(),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      final l10n = context.l10n;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.appLoadFailed(e.toString()))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title:
            Text(_t(context, 'Разделённое туннелирование', 'Split tunneling')),
        backgroundColor: AppTheme.surface,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Consumer<TunnelProvider>(
        builder: (context, provider, _) {
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _SectionHeader(title: l10n.sectionSplitTunneling),
              _SplitTunnelingCard(
                current: provider.splitTunnelingMode,
                isLoadingApps: provider.isLoadingInstalledApps,
                selectedCount: provider.splitTunnelPackages.length,
                selectedLabels: _selectedLabels(provider),
                onChanged: provider.setSplitTunnelingMode,
                onChooseApps: () => _openSplitTunnelApps(provider),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ToolsSubScreen extends StatefulWidget {
  const _ToolsSubScreen();

  @override
  State<_ToolsSubScreen> createState() => _ToolsSubScreenState();
}

class _ToolsSubScreenState extends State<_ToolsSubScreen> {
  final _analysisController = TextEditingController();
  bool _analysisWithNetworkChecks = true;
  bool _analysisInProgress = false;
  String _analysisErrorText = '';
  KeyAnalysisResult? _analysisResult;

  @override
  void dispose() {
    _analysisController.dispose();
    super.dispose();
  }

  Future<void> _analyzeKey() async {
    final l10n = context.l10n;
    final key = _analysisController.text.trim();
    if (key.isEmpty) {
      setState(() {
        _analysisErrorText = l10n.isRussian
            ? 'Вставьте ключ для анализа'
            : 'Paste a key for analysis';
        _analysisResult = null;
      });
      return;
    }

    setState(() {
      _analysisInProgress = true;
      _analysisErrorText = '';
    });

    try {
      final result = await KeyAnalysisService.analyzeUri(
        key,
        withNetworkChecks: _analysisWithNetworkChecks,
      );
      if (!mounted) return;
      setState(() {
        _analysisResult = result;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _analysisErrorText =
            l10n.isRussian ? 'Ошибка анализа: $e' : 'Analysis error: $e';
        _analysisResult = null;
      });
    } finally {
      if (mounted) {
        setState(() {
          _analysisInProgress = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text(_t(context, 'Инструменты', 'Tools')),
        backgroundColor: AppTheme.surface,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _SectionHeader(title: l10n.sectionKeyAnalysis),
          _KeyAnalysisCard(
            controller: _analysisController,
            withNetworkChecks: _analysisWithNetworkChecks,
            inProgress: _analysisInProgress,
            errorText: _analysisErrorText,
            result: _analysisResult,
            onChanged: (_) {
              if (_analysisErrorText.isNotEmpty) {
                setState(() => _analysisErrorText = '');
              }
            },
            onToggleNetworkChecks: (value) {
              setState(() {
                _analysisWithNetworkChecks = value;
              });
            },
            onAnalyze: _analyzeKey,
          ),
        ],
      ),
    );
  }
}

class _AppSubScreen extends StatefulWidget {
  const _AppSubScreen();

  @override
  State<_AppSubScreen> createState() => _AppSubScreenState();
}

class _AppSubScreenState extends State<_AppSubScreen> {
  String _appVersionLabel = 'v-';

  @override
  void initState() {
    super.initState();
    _loadAppVersionLabel();
  }

  Future<void> _loadAppVersionLabel() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final label = 'v${info.version}';
      if (!mounted) return;
      setState(() {
        _appVersionLabel = label;
      });
    } catch (_) {
      // Keep fallback label when package info is unavailable.
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text(_t(context, 'Приложение', 'App')),
        backgroundColor: AppTheme.surface,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Consumer<TunnelProvider>(
        builder: (context, provider, _) {
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _SectionHeader(title: l10n.sectionLanguage),
              _LanguageCard(provider: provider),
              const SizedBox(height: 32),
              _AppInfoTile(versionLabel: _appVersionLabel),
            ],
          );
        },
      ),
    );
  }
}

class _LanguageCard extends StatelessWidget {
  final TunnelProvider provider;

  const _LanguageCard({required this.provider});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.25)),
      ),
      child: Column(
        children: [
          ListTile(
            dense: true,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            title: Text(l10n.languageTitle),
            subtitle: Text(
              l10n.languageSubtitle,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          const SizedBox(height: 8),
          _LanguageOptionTile(
            label: l10n.languageRu,
            code: 'ru',
            selected: provider.languageCode == 'ru',
            onTap: () => provider.setLanguageCode('ru'),
          ),
          const SizedBox(height: 8),
          _LanguageOptionTile(
            label: l10n.languageEn,
            code: 'en',
            selected: provider.languageCode == 'en',
            onTap: () => provider.setLanguageCode('en'),
          ),
        ],
      ),
    );
  }
}

class _LanguageOptionTile extends StatelessWidget {
  final String label;
  final String code;
  final bool selected;
  final VoidCallback onTap;

  const _LanguageOptionTile({
    required this.label,
    required this.code,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? AppTheme.primary.withValues(alpha: 0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? AppTheme.primary : AppTheme.border,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                '$label (${code.toUpperCase()})',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: selected
                          ? AppTheme.primaryLight
                          : AppTheme.textPrimary,
                    ),
              ),
            ),
            if (selected)
              const Icon(
                Icons.check_circle_rounded,
                size: 18,
                color: AppTheme.primary,
              ),
          ],
        ),
      ),
    );
  }
}

class _ConnectionModeCard extends StatelessWidget {
  final TunnelProvider provider;

  const _ConnectionModeCard({required this.provider});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.25)),
      ),
      child: Column(
        children: AppConnectionMode.values.map((mode) {
          final selected = provider.connectionMode == mode;
          return InkWell(
            onTap: () async {
              await provider.setConnectionMode(mode);
            },
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: selected
                    ? AppTheme.primary.withValues(alpha: 0.12)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: selected ? AppTheme.primary : Colors.transparent,
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    mode == AppConnectionMode.tunnel
                        ? Icons.shield_rounded
                        : Icons.offline_bolt_rounded,
                    color: selected ? AppTheme.primary : AppTheme.textSecondary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _modeDisplay(context, mode),
                          style:
                              Theme.of(context).textTheme.bodyLarge?.copyWith(
                                    fontWeight: FontWeight.w600,
                                    color: selected
                                        ? AppTheme.primaryLight
                                        : AppTheme.textPrimary,
                                  ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _modeDescription(context, mode),
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(growable: false),
      ),
    );
  }
}

class _OfflineDeblockProfileCard extends StatelessWidget {
  final TunnelProvider provider;
  final OfflineDeblockProfile current;
  final ValueChanged<OfflineDeblockProfile> onChanged;

  const _OfflineDeblockProfileCard({
    required this.provider,
    required this.current,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
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

    String profileDescription(OfflineDeblockProfile profile) {
      switch (profile) {
        case OfflineDeblockProfile.soft:
          return _t(
            context,
            'Защищённый DNS и мягкая стабилизация без жёстких транспортных ограничений',
            'Protected DNS with soft stabilization and no strict transport limits',
          );
        case OfflineDeblockProfile.balanced:
          return _t(
            context,
            'Защищённый DNS, подавление QUIC и защита от современных DNS-ответов DPI',
            'Protected DNS, QUIC suppression, and modern DNS anti-DPI hardening',
          );
        case OfflineDeblockProfile.hybrid:
          return _t(
            context,
            'Legacy fallback для мягкой фильтрации: выборочный Cloudflare WARP для web-трафика; strict allowlist использует отдельный ingress toggle ниже',
            'Legacy fallback for mild filtering: selective Cloudflare WARP for web traffic; strict allowlist uses the separate ingress toggle below',
          );
        case OfflineDeblockProfile.aggressive:
          return _t(
            context,
            'Максимально жёсткий режим: режет UDP и IPv6 ради устойчивости в сложных DPI-сценариях',
            'Aggressive mode blocks UDP and IPv6 for stability in heavy DPI scenarios',
          );
        case OfflineDeblockProfile.ultra:
          return _t(
            context,
            'Максимально строгий профиль: усиленные DNS-ограничения и жёсткая транспортная фильтрация',
            'Ultra-strict profile with reinforced DNS limits and strict transport filtering',
          );
        case OfflineDeblockProfile.custom:
          return _t(
            context,
            'Пользовательский профиль: вручную настраиваемые ограничения DNS и транспорта',
            'Custom profile with manually configurable DNS and transport restrictions',
          );
      }
    }

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.25)),
      ),
      child: Column(
        children: OfflineDeblockProfile.values.map((profile) {
          final selected = current == profile;
          final profileSettings = switch (profile) {
            OfflineDeblockProfile.custom =>
              provider.offlineDeblockCustomSettings,
            OfflineDeblockProfile.hybrid =>
              provider.offlineDeblockHybridSettings,
            _ => OfflineDeblockSettings.forProfile(profile),
          };
          final tlsBadge = profileSettings.tlsFragmentEnabled ||
                  profileSettings.tlsPaddingEnabled ||
                  profileSettings.tlsMixedSniCase
              ? ' • TLS-маскировка'
              : '';
          final warpBadge =
              profileSettings.warpEnabled ? ' • Cloudflare WARP' : '';
          final summary =
              'Трафик: ${profileSettings.blockAllUdp ? 'TCP' : profileSettings.blockUdp443 ? 'TCP+UDP' : 'Не ограничен'} • IPv6: ${profileSettings.blockIpv6 ? 'выкл' : 'вкл'}$warpBadge$tlsBadge';
          return InkWell(
            onTap: () => onChanged(profile),
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: selected
                    ? AppTheme.primary.withValues(alpha: 0.12)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: selected ? AppTheme.primary : Colors.transparent,
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          profileName(profile),
                          style:
                              Theme.of(context).textTheme.bodyLarge?.copyWith(
                                    fontWeight: FontWeight.w600,
                                    color: selected
                                        ? AppTheme.primaryLight
                                        : AppTheme.textPrimary,
                                  ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          profileDescription(profile),
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 3),
                        Text(
                          summary,
                          style: const TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (selected)
                    const Icon(
                      Icons.check_circle_rounded,
                      color: AppTheme.primary,
                    ),
                ],
              ),
            ),
          );
        }).toList(growable: false),
      ),
    );
  }
}

class _OfflineDeblockCustomCard extends StatelessWidget {
  final OfflineDeblockSettings settings;
  final ValueChanged<OfflineDeblockSettings> onChanged;

  const _OfflineDeblockCustomCard({
    required this.settings,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _t(context, 'Параметры', 'Custom restrictions'),
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          _CustomSwitchTile(
            title: _t(
                context,
                'Отключить QUIC-протокол (помогает при блокировках)',
                'Block UDP:443 (anti-QUIC)'),
            value: settings.blockUdp443,
            onChanged: (value) =>
                onChanged(settings.copyWith(blockUdp443: value)),
          ),
          _CustomSwitchTile(
            title: _t(context, 'Отключить все UDP-соединения', 'Block all UDP'),
            value: settings.blockAllUdp,
            onChanged: (value) =>
                onChanged(settings.copyWith(blockAllUdp: value)),
          ),
          _CustomSwitchTile(
            title: _t(context, 'Отключить IPv6', 'Block IPv6'),
            value: settings.blockIpv6,
            onChanged: (value) =>
                onChanged(settings.copyWith(blockIpv6: value)),
          ),
          _CustomSwitchTile(
            title: _t(
                context, 'Фильтровать DNS через HTTPS', 'Block DNS HTTPS/SVCB'),
            value: settings.blockDnsHttpsSvcb,
            onChanged: (value) =>
                onChanged(settings.copyWith(blockDnsHttpsSvcb: value)),
          ),
          _CustomSwitchTile(
            title: _t(context, 'Отключить IPv6-адреса в DNS',
                'Block DNS AAAA (IPv6)'),
            value: settings.blockDnsAaaa,
            onChanged: (value) =>
                onChanged(settings.copyWith(blockDnsAaaa: value)),
          ),
          _CustomSwitchTile(
            title: _t(context, 'Точно определять адрес назначения',
                'Sniff override destination'),
            value: settings.sniffOverrideDestination,
            onChanged: (value) =>
                onChanged(settings.copyWith(sniffOverrideDestination: value)),
          ),
          const SizedBox(height: 8),
          Text(
            _t(context, 'TLS-маскировка (экспериментально)',
                'TLS tricks (experimental)'),
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          _CustomSwitchTile(
            title: _t(context, 'Фрагментация TLS', 'Enable TLS Fragment'),
            value: settings.tlsFragmentEnabled,
            onChanged: (value) =>
                onChanged(settings.copyWith(tlsFragmentEnabled: value)),
          ),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Размер фрагмента',
                  style: TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ),
              DropdownButton<int>(
                value: settings.tlsFragmentSize,
                dropdownColor: AppTheme.surface,
                style: const TextStyle(color: AppTheme.textPrimary),
                underline: const SizedBox.shrink(),
                items: List<int>.generate(21, (i) => i + 10)
                    .map(
                      (value) => DropdownMenuItem<int>(
                        value: value,
                        child: Text('$value'),
                      ),
                    )
                    .toList(growable: false),
                onChanged: (value) {
                  if (value == null) return;
                  onChanged(settings.copyWith(tlsFragmentSize: value));
                },
              ),
            ],
          ),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Задержка (мс)',
                  style: TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ),
              DropdownButton<int>(
                value: settings.tlsFragmentSleepMs,
                dropdownColor: AppTheme.surface,
                style: const TextStyle(color: AppTheme.textPrimary),
                underline: const SizedBox.shrink(),
                items: List<int>.generate(7, (i) => i + 2)
                    .map(
                      (value) => DropdownMenuItem<int>(
                        value: value,
                        child: Text('$value'),
                      ),
                    )
                    .toList(growable: false),
                onChanged: (value) {
                  if (value == null) return;
                  onChanged(settings.copyWith(tlsFragmentSleepMs: value));
                },
              ),
            ],
          ),
          _CustomSwitchTile(
            title: _t(
                context, 'Смешанный регистр SNI', 'Enable TLS Mixed SNI Case'),
            value: settings.tlsMixedSniCase,
            onChanged: (value) =>
                onChanged(settings.copyWith(tlsMixedSniCase: value)),
          ),
          _CustomSwitchTile(
            title:
                _t(context, 'Случайное дополнение TLS', 'Enable TLS Padding'),
            value: settings.tlsPaddingEnabled,
            onChanged: (value) =>
                onChanged(settings.copyWith(tlsPaddingEnabled: value)),
          ),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Размер дополнения',
                  style: TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ),
              DropdownButton<int>(
                value: settings.tlsPaddingSize,
                dropdownColor: AppTheme.surface,
                style: const TextStyle(color: AppTheme.textPrimary),
                underline: const SizedBox.shrink(),
                items: const [64, 128, 256, 512, 768, 1024, 1500]
                    .map(
                      (value) => DropdownMenuItem<int>(
                        value: value,
                        child: Text('$value'),
                      ),
                    )
                    .toList(growable: false),
                onChanged: (value) {
                  if (value == null) return;
                  onChanged(settings.copyWith(tlsPaddingSize: value));
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Размер пакета (MTU)',
                  style: TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ),
              DropdownButton<int>(
                value: settings.mtu,
                dropdownColor: AppTheme.surface,
                style: const TextStyle(color: AppTheme.textPrimary),
                underline: const SizedBox.shrink(),
                items: const [1200, 1280, 1360, 1400, 1500]
                    .map(
                      (value) => DropdownMenuItem<int>(
                        value: value,
                        child: Text('$value'),
                      ),
                    )
                    .toList(growable: false),
                onChanged: (value) {
                  if (value == null) return;
                  onChanged(settings.copyWith(mtu: value));
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StrictAllowlistCard extends StatelessWidget {
  final TunnelProvider provider;

  const _StrictAllowlistCard({required this.provider});

  @override
  Widget build(BuildContext context) {
    final bundle = provider.cachedIngressRuntimeBundle;
    final rolloutReady = provider.hasValidCachedIngressBundle;
    final controlPlaneConfigured = provider.hasConfiguredIngressControlPlane;
    final deliveryMode = provider.selectedOfflineDeblockDeliveryMode;
    final modeLabel = switch (deliveryMode) {
      DeblockerDeliveryMode.allowlistedIngress =>
        _t(context, 'Выделенный канал', 'Dedicated channel'),
      DeblockerDeliveryMode.warpHybridLegacy =>
        _t(context, 'Cloudflare (резерв)', 'Cloudflare (fallback)'),
      DeblockerDeliveryMode.directOnly =>
        _t(context, 'Без проксирования', 'No proxying'),
    };

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _t(
                        context,
                        'Надёжный канал деблокировки',
                        'Dedicated deblocking channel',
                      ),
                      style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _t(
                        context,
                        'Приоритетный режим: деблокировка запускается только после получения актуальной конфигурации с сервера. Встроенная конфигурация используется только как запасной вариант.',
                        'Priority mode: deblocking starts only after receiving the latest config from the server. The bundled config is used only as a fallback.',
                      ),
                      style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              Switch.adaptive(
                value: provider.strictAllowlistModeEnabled,
                onChanged: provider.allowlistedIngressFeatureEnabled
                    ? provider.setStrictAllowlistModeEnabled
                    : null,
                activeThumbColor: AppTheme.primary,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${_t(context, 'Тип канала', 'Channel type')}: $modeLabel',
            style: const TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            rolloutReady
                ? _t(
                    context,
                    'Конфигурация канала получена и готова к работе.',
                    'Channel config received and ready.',
                  )
                : !controlPlaneConfigured
                    ? _t(
                        context,
                        'Сервер управления не настроен — деблокировка будет работать в резервном режиме.',
                        'Management server is not configured — deblocking will work in fallback mode.',
                      )
                    : provider.cachedIngressBundleIsSeed
                        ? _t(
                            context,
                            'Доступна только встроенная конфигурация. Обновите канал для активации надёжного режима.',
                            'Only the built-in config is available. Refresh the channel to activate priority mode.',
                          )
                        : provider.isRefreshingIngressBundle
                            ? _t(
                                context,
                                'Получаем конфигурацию…',
                                'Fetching channel configuration…',
                              )
                            : _t(
                                context,
                                'Конфигурация ещё не получена. При запуске сработает резервный режим.',
                                'Configuration not yet received. Startup will use fallback mode.',
                              ),
            style: TextStyle(
              color:
                  rolloutReady ? AppTheme.primaryLight : AppTheme.textSecondary,
              fontSize: 11,
              height: 1.35,
            ),
          ),
          if (bundle != null) ...[
            const SizedBox(height: 4),
            Text(
              '${_t(context, 'Edge', 'Edge')}: ${bundle.ingressConfig?.edgeHost ?? '—'} • ${bundle.ingressConfig?.transport ?? '—'} • ${bundle.ingressConfig?.outboundType ?? '—'}',
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 11,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _IngressBundleStatusCard extends StatelessWidget {
  final TunnelProvider provider;

  const _IngressBundleStatusCard({required this.provider});

  @override
  Widget build(BuildContext context) {
    final bundle = provider.cachedIngressRuntimeBundle;
    final controlPlaneConfigured = provider.hasConfiguredIngressControlPlane;
    if (bundle == null && !provider.allowlistedIngressFeatureEnabled) {
      return const SizedBox.shrink();
    }

    String freshnessLabel(DeblockerBundleFreshness freshness) {
      switch (freshness) {
        case DeblockerBundleFreshness.fresh:
          return _t(context, 'свежий', 'fresh');
        case DeblockerBundleFreshness.stale:
          return _t(context, 'устаревает', 'aging');
        case DeblockerBundleFreshness.expired:
          return _t(context, 'истёк', 'expired');
      }
    }

    String sourceLabel(String? source) {
      if (source != null && source.startsWith('remote_control_plane')) {
        return _t(context, 'remote control plane', 'remote control plane');
      }
      switch (source) {
        case 'bundled_seed':
          return _t(context, 'вшитый seed', 'bundled seed');
        case 'cached':
          return _t(context, 'локальный кэш', 'local cache');
        case 'generated_legacy':
          return _t(context, 'legacy runtime', 'legacy runtime');
        default:
          return _t(context, 'неизвестно', 'unknown');
      }
    }

    String ttlLabel(int? seconds) {
      if (seconds == null) {
        return '—';
      }
      if (seconds <= 0) {
        return _t(context, 'истёк', 'expired');
      }
      if (seconds >= 86400) {
        return '${seconds ~/ 86400} ${_t(context, 'д', 'd')}';
      }
      return '${(seconds / 3600).ceil()} ${_t(context, 'ч', 'h')}';
    }

    final summary = bundle == null
        ? controlPlaneConfigured
            ? _t(
                context,
                'Bootstrap bundle ещё не подготовлен',
                'Bootstrap bundle is not prepared yet',
              )
            : _t(
                context,
                'Control plane URL не задан в сборке',
                'No control plane URL is configured in this build',
              )
        : 'v${bundle.bundleVersion} • ${sourceLabel(bundle.bootstrapSource)} • ${freshnessLabel(bundle.freshness)}';
    final integrityText = bundle == null
        ? _t(context, 'нет данных', 'no data')
        : bundle.isBootstrapSeedBundle
            ? _t(context, 'bootstrap only', 'bootstrap only')
            : provider.hasValidCachedIngressBundle
                ? 'SHA-256 ok'
                : _t(context, 'требует обновления', 'needs refresh');

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _t(
              context,
              'Состояние канала',
              'Channel status',
            ),
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            summary,
            style: const TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 12,
              height: 1.35,
            ),
          ),
          if (bundle != null) ...[
            const SizedBox(height: 8),
            Text(
              'Edge ${bundle.ingressConfig?.edgeHost ?? '—'} • ${bundle.ingressConfig?.transport ?? '—'}',
              style: const TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${_t(context, 'Целостность', 'Integrity')}: $integrityText • TTL ${ttlLabel(bundle.remainingTtlSeconds)}',
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 11,
              ),
            ),
          ],
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed:
                  !controlPlaneConfigured || provider.isRefreshingIngressBundle
                      ? null
                      : () => provider.refreshIngressBundle(context),
              icon: provider.isRefreshingIngressBundle
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppTheme.primary,
                      ),
                    )
                  : const Icon(Icons.sync_rounded, size: 16),
              label: Text(
                provider.isRefreshingIngressBundle
                    ? _t(context, 'Обновляем…', 'Refreshing…')
                    : _t(
                        context,
                        'Обновить конфигурацию',
                        'Refresh config',
                      ),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.primary,
                side: const BorderSide(color: AppTheme.primary),
                enableFeedback: false,
                padding: const EdgeInsets.symmetric(vertical: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
          if (!controlPlaneConfigured) ...[
            const SizedBox(height: 8),
            Text(
              _t(
                context,
                'Для обновления конфигурации в сборке не задан адрес сервера управления.',
                'The management server URL is not configured in this build.',
              ),
              style: const TextStyle(
                color: AppTheme.textDisabled,
                fontSize: 11,
                height: 1.35,
              ),
            ),
          ] else if (provider.ingressBundleRefreshError != null) ...[
            const SizedBox(height: 8),
            Text(
              '${_t(context, 'Ошибка обновления', 'Refresh error')}: ${provider.ingressBundleRefreshError}',
              style: const TextStyle(
                color: Colors.orangeAccent,
                fontSize: 11,
                height: 1.35,
              ),
            ),
          ],
          if (!provider.allowlistedIngressFeatureEnabled) ...[
            const SizedBox(height: 8),
            Text(
              _t(
                context,
                'Конфигурация канала загружается заранее; активация канала будет доступна позже.',
                'Channel config is loaded in advance; channel activation will be available later.',
              ),
              style: const TextStyle(
                color: AppTheme.textDisabled,
                fontSize: 11,
                height: 1.35,
              ),
            ),
          ] else if (provider.strictAllowlistModeEnabled) ...[
            const SizedBox(height: 8),
            Text(
              _t(
                context,
                'Надёжный канал включён: встроенная конфигурация не считается актуальной, поэтому при включенном режиме нужна актуальная конфигурация от сервера.',
                'Priority channel enabled: the built-in config is not used as current, so startup requires a fresh config from the server.',
              ),
              style: const TextStyle(
                color: AppTheme.textDisabled,
                fontSize: 11,
                height: 1.35,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CustomSwitchTile extends StatelessWidget {
  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _CustomSwitchTile({
    required this.title,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 12,
              ),
            ),
          ),
          Switch.adaptive(
            value: value,
            onChanged: onChanged,
            activeThumbColor: AppTheme.primary,
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;

  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.2,
          color: AppTheme.primary,
        ),
      ),
    );
  }
}

class _TunnelOptionsCard extends StatelessWidget {
  final TunnelProvider provider;

  const _TunnelOptionsCard({required this.provider});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.25)),
      ),
      child: Column(
        children: [
          _CustomSwitchTile(
            title: _t(
              context,
              'Маскировка соединения (защита от блокировок)',
              'Connection masking (bypass blocking)',
            ),
            value: provider.tunnelTlsFingerprintSpoofing,
            onChanged: provider.setTunnelTlsFingerprintSpoofing,
          ),
          _CustomSwitchTile(
            title: _t(
              context,
              'Антикризисный режим магистралей (уровень ${provider.crossBorderPressureLevel})',
              'Backbone anti-crisis mode (level ${provider.crossBorderPressureLevel})',
            ),
            value: provider.antiCrisisMode,
            onChanged: provider.setAntiCrisisMode,
          ),
        ],
      ),
    );
  }
}

class _KeyAnalysisCard extends StatelessWidget {
  final TextEditingController controller;
  final bool withNetworkChecks;
  final bool inProgress;
  final String errorText;
  final KeyAnalysisResult? result;
  final ValueChanged<String> onChanged;
  final ValueChanged<bool> onToggleNetworkChecks;
  final VoidCallback onAnalyze;

  const _KeyAnalysisCard({
    required this.controller,
    required this.withNetworkChecks,
    required this.inProgress,
    required this.errorText,
    required this.result,
    required this.onChanged,
    required this.onToggleNetworkChecks,
    required this.onAnalyze,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _t(
              context,
              'Вставьте ключ, чтобы получить максимум технических сведений',
              'Paste a key to get detailed technical information',
            ),
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: AppTheme.background,
              borderRadius: BorderRadius.circular(8),
              border:
                  Border.all(color: AppTheme.primary.withValues(alpha: 0.25)),
            ),
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              style: const TextStyle(color: Colors.white, fontSize: 12),
              minLines: 2,
              maxLines: 4,
              decoration: InputDecoration(
                hintText: _t(
                  context,
                  'vless://... или ss://... или trojan://... или tuic://...',
                  'vless://... or ss://... or trojan://... or tuic://...',
                ),
                hintStyle: const TextStyle(
                    color: AppTheme.textSecondary, fontSize: 11),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Checkbox(
                value: withNetworkChecks,
                onChanged: (value) => onToggleNetworkChecks(value ?? true),
                activeColor: AppTheme.primary,
              ),
              Expanded(
                child: Text(
                  _t(
                    context,
                    'Использовать сетевые проверки (DNS/IP/ASN/RDAP/TLS)',
                    'Use network checks (DNS/IP/ASN/RDAP/TLS)',
                  ),
                  style: const TextStyle(
                      color: AppTheme.textSecondary, fontSize: 11),
                ),
              ),
            ],
          ),
          if (errorText.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                errorText,
                style: const TextStyle(color: Colors.redAccent, fontSize: 11),
              ),
            ),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: inProgress ? null : onAnalyze,
              icon: inProgress
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.analytics_outlined, size: 18),
              label: Text(
                inProgress
                    ? _t(context, 'Анализ...', 'Analyzing...')
                    : _t(context, 'Анализировать ключ', 'Analyze key'),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
                enableFeedback: false,
                padding: const EdgeInsets.symmetric(vertical: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
          if (result != null) ...[
            const SizedBox(height: 12),
            const Divider(color: AppTheme.border),
            const SizedBox(height: 8),
            Text(
              _t(context, 'Сведения', 'Details'),
              style: TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            ...result!.basicInfo.entries.map(
              (entry) => _AnalysisInfoRow(label: entry.key, value: entry.value),
            ),
            if (result!.networkInfo.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                _t(context, 'Сетевые данные', 'Network data'),
                style: TextStyle(
                  color: AppTheme.primary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              ...result!.networkInfo.entries.map(
                (entry) =>
                    _AnalysisInfoRow(label: entry.key, value: entry.value),
              ),
            ],
            if (result!.notes.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                _t(context, 'Примечания', 'Notes'),
                style: TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              ...result!.notes.map(
                (note) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    '• $note',
                    style: const TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 11,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _AnalysisInfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _AnalysisInfoRow({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 4,
            child: Text(
              '$label:',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 11,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 6,
            child: Text(
              value.isNotEmpty ? value : '—',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RoutingModeCard extends StatelessWidget {
  final RoutingMode current;
  final ValueChanged<RoutingMode> onChanged;

  const _RoutingModeCard({required this.current, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.2)),
      ),
      child: Column(
        children: RoutingMode.values.map((mode) {
          final selected = mode == current;
          return InkWell(
            onTap: () => onChanged(mode),
            enableFeedback: false,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: selected
                            ? AppTheme.primary
                            : AppTheme.textSecondary,
                        width: 2,
                      ),
                    ),
                    child: selected
                        ? Center(
                            child: Container(
                              width: 10,
                              height: 10,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: AppTheme.primary,
                              ),
                            ),
                          )
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _routingTitle(context, mode),
                          style: TextStyle(
                            color: selected ? AppTheme.primary : Colors.white,
                            fontSize: 13,
                            fontWeight:
                                selected ? FontWeight.w600 : FontWeight.normal,
                          ),
                        ),
                        Text(
                          _routingDescription(context, mode),
                          style: const TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(growable: false),
      ),
    );
  }
}



class _KeyListTypeCard extends StatelessWidget {
  final KeyListType current;
  final ValueChanged<KeyListType> onChanged;

  const _KeyListTypeCard({required this.current, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.2)),
      ),
      child: Column(
        children: KeyListType.values.map((type) {
          final selected = type == current;
          return InkWell(
            onTap: () => onChanged(type),
            enableFeedback: false,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: selected
                            ? AppTheme.primary
                            : AppTheme.textSecondary,
                        width: 2,
                      ),
                    ),
                    child: selected
                        ? Center(
                            child: Container(
                              width: 10,
                              height: 10,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: AppTheme.primary,
                              ),
                            ),
                          )
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _keyListTypeTitle(context, type),
                      style: TextStyle(
                        color: selected ? AppTheme.primary : Colors.white,
                        fontSize: 13,
                        fontWeight:
                            selected ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(growable: false),
      ),
    );
  }
}

class _SplitTunnelingCard extends StatelessWidget {
  final SplitTunnelingMode current;
  final bool isLoadingApps;
  final int selectedCount;
  final List<String> selectedLabels;
  final ValueChanged<SplitTunnelingMode> onChanged;
  final VoidCallback onChooseApps;

  const _SplitTunnelingCard({
    required this.current,
    required this.isLoadingApps,
    required this.selectedCount,
    required this.selectedLabels,
    required this.onChanged,
    required this.onChooseApps,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          ...SplitTunnelingMode.values.map((mode) {
            final selected = mode == current;
            return InkWell(
              onTap: () => onChanged(mode),
              enableFeedback: false,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 20,
                      height: 20,
                      margin: const EdgeInsets.only(top: 2),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: selected
                              ? AppTheme.primary
                              : AppTheme.textSecondary,
                          width: 2,
                        ),
                      ),
                      child: selected
                          ? Center(
                              child: Container(
                                width: 10,
                                height: 10,
                                decoration: const BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: AppTheme.primary,
                                ),
                              ),
                            )
                          : null,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _splitModeTitle(context, mode),
                            style: TextStyle(
                              color: selected ? AppTheme.primary : Colors.white,
                              fontSize: 13,
                              fontWeight: selected
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _splitModeDescription(context, mode),
                            style: const TextStyle(
                              color: AppTheme.textSecondary,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
          if (current != SplitTunnelingMode.off)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(
                    color: AppTheme.primary.withValues(alpha: 0.12),
                  ),
                ),
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
                      Expanded(
                        child: Text(
                          selectedCount > 0
                              ? _t(
                                  context,
                                  'Выбрано приложений: $selectedCount',
                                  'Selected apps: $selectedCount')
                              : _t(context, 'Список приложений пока не выбран',
                                  'No app list selected yet'),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      if (isLoadingApps)
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppTheme.primary,
                          ),
                        ),
                    ],
                  ),
                  if (selectedLabels.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ...selectedLabels.map(
                          (label) => Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: AppTheme.primary.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color: AppTheme.primary.withValues(alpha: 0.2),
                              ),
                            ),
                            child: Text(
                              label,
                              style: const TextStyle(
                                color: AppTheme.textPrimary,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ),
                        if (selectedCount > selectedLabels.length)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: AppTheme.surfaceVariant,
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(color: AppTheme.border),
                            ),
                            child: Text(
                              '+${selectedCount - selectedLabels.length}',
                              style: const TextStyle(
                                color: AppTheme.textSecondary,
                                fontSize: 11,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: onChooseApps,
                      icon: const Icon(Icons.tune_rounded, size: 16),
                      label: Text(
                          _t(context, 'Выбрать приложения', 'Choose apps')),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.primary,
                        side: const BorderSide(color: AppTheme.primary),
                        enableFeedback: false,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _SplitTunnelAppsSheet extends StatefulWidget {
  const _SplitTunnelAppsSheet();

  @override
  State<_SplitTunnelAppsSheet> createState() => _SplitTunnelAppsSheetState();
}

class _SplitTunnelAppsSheetState extends State<_SplitTunnelAppsSheet> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.88,
      minChildSize: 0.64,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Consumer<TunnelProvider>(
            builder: (context, provider, _) {
              final filteredApps = provider.installedApps.where((app) {
                if (_query.isEmpty) {
                  return true;
                }
                final lowered = _query.toLowerCase();
                return app.label.toLowerCase().contains(lowered) ||
                    app.packageName.toLowerCase().contains(lowered);
              }).toList(growable: false);

              return Column(
                children: [
                  const SizedBox(height: 10),
                  Container(
                    width: 42,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppTheme.textDisabled,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _t(context, 'Приложения для раздельного туннеля',
                              'Split-tunnel apps'),
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _splitModeDescription(
                            context,
                            provider.splitTunnelingMode,
                          ),
                          style: const TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 14),
                        TextField(
                          controller: _searchController,
                          onChanged: (value) {
                            setState(() => _query = value.trim());
                          },
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            hintText: _t(
                              context,
                              'Поиск по названию или package name',
                              'Search by app name or package name',
                            ),
                            prefixIcon: const Icon(Icons.search_rounded),
                            suffixIcon: _query.isEmpty
                                ? null
                                : IconButton(
                                    onPressed: () {
                                      _searchController.clear();
                                      setState(() => _query = '');
                                    },
                                    enableFeedback: false,
                                    icon: const Icon(Icons.close_rounded),
                                  ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _t(
                            context,
                            'Отмечено: ${provider.splitTunnelPackages.length}',
                            'Selected: ${provider.splitTunnelPackages.length}',
                          ),
                          style: const TextStyle(
                            color: AppTheme.primary,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: provider.isLoadingInstalledApps
                        ? const Center(
                            child: CircularProgressIndicator(
                              color: AppTheme.primary,
                            ),
                          )
                        : filteredApps.isEmpty
                            ? _SplitTunnelEmptyState(query: _query)
                            : ListView.builder(
                                controller: scrollController,
                                padding:
                                    const EdgeInsets.fromLTRB(16, 0, 16, 24),
                                itemCount: filteredApps.length,
                                itemBuilder: (context, index) {
                                  final app = filteredApps[index];
                                  return _SplitTunnelAppTile(
                                    app: app,
                                    selected:
                                        provider.isSplitTunnelPackageSelected(
                                      app.packageName,
                                    ),
                                    onTap: () =>
                                        provider.toggleSplitTunnelPackage(
                                      app.packageName,
                                    ),
                                  );
                                },
                              ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }
}

class _SplitTunnelAppTile extends StatelessWidget {
  final InstalledApp app;
  final bool selected;
  final VoidCallback onTap;

  const _SplitTunnelAppTile({
    required this.app,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      enableFeedback: false,
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: AppTheme.motionFast,
        curve: AppTheme.emphasizedCurve,
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: selected
              ? AppTheme.primary.withValues(alpha: 0.12)
              : AppTheme.surfaceVariant,
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
                color: AppTheme.primary.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                app.systemApp ? Icons.memory_rounded : Icons.android_rounded,
                color: AppTheme.primary,
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
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
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
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            if (app.systemApp)
              Container(
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.surface,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: AppTheme.border),
                ),
                child: const Text(
                  'SYS',
                  style: TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            Icon(
              selected
                  ? Icons.check_circle_rounded
                  : Icons.radio_button_unchecked_rounded,
              color: selected ? AppTheme.primary : AppTheme.textDisabled,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}

class _SplitTunnelEmptyState extends StatelessWidget {
  final String query;

  const _SplitTunnelEmptyState({required this.query});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              query.isEmpty ? Icons.apps_outlined : Icons.search_off_rounded,
              size: 40,
              color: AppTheme.primary.withValues(alpha: 0.45),
            ),
            const SizedBox(height: 12),
            Text(
              query.isEmpty
                  ? _t(context, 'Не удалось получить список приложений',
                      'Failed to load apps list')
                  : _t(context, 'По вашему запросу ничего не найдено',
                      'No results for your query'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AutoKeysCard extends StatelessWidget {
  final bool isLoading;
  final String message;
  final int count;
  final VoidCallback onRefresh;
  final VoidCallback onDeleteAllKeys;
  final VoidCallback onResetSettings;

  const _AutoKeysCard({
    required this.isLoading,
    required this.message,
    required this.count,
    required this.onRefresh,
    required this.onDeleteAllKeys,
    required this.onResetSettings,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.cloud_download_outlined,
                color: AppTheme.primary,
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _t(context, 'Загружено серверов: $count',
                      'Loaded servers: $count'),
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                ),
              ),
              const SizedBox(width: 8),
              if (isLoading)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppTheme.primary,
                  ),
                ),
            ],
          ),
          if (message.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              message,
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 11,
              ),
            ),
          ],
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: isLoading ? null : onRefresh,
              icon: const Icon(Icons.refresh, size: 16),
              label: Text(_t(context, 'Обновить серверы', 'Refresh servers')),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.primary,
                side: const BorderSide(color: AppTheme.primary),
                enableFeedback: false,
                padding: const EdgeInsets.symmetric(vertical: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: isLoading ? null : onDeleteAllKeys,
              icon: const Icon(Icons.delete_forever_outlined, size: 16),
              label: Text(_t(context, 'Удалить все ключи', 'Delete all keys')),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.redAccent,
                side: const BorderSide(color: Colors.redAccent),
                enableFeedback: false,
                padding: const EdgeInsets.symmetric(vertical: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onResetSettings,
              icon: const Icon(Icons.restart_alt_rounded, size: 16),
              label: Text(_t(context, 'Сбросить настройки', 'Reset settings')),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.textSecondary,
                side: BorderSide(
                  color: AppTheme.textSecondary.withValues(alpha: 0.6),
                ),
                enableFeedback: false,
                padding: const EdgeInsets.symmetric(vertical: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CustomSourcesCard extends StatefulWidget {
  final TunnelProvider provider;

  const _CustomSourcesCard({required this.provider});

  @override
  State<_CustomSourcesCard> createState() => _CustomSourcesCardState();
}

class _CustomSourcesCardState extends State<_CustomSourcesCard> {
  final _nameController = TextEditingController();
  final _urlController = TextEditingController();
  CustomSourceType _selectedType = CustomSourceType.url;
  KeyListType _selectedListType = KeyListType.blackList;

  @override
  void dispose() {
    _nameController.dispose();
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _addCustomSource() async {
    final name = _nameController.text.trim();
    final urlOrPath = _urlController.text.trim();

    if (name.isEmpty || urlOrPath.isEmpty) {
      _showError(_t(context, 'Заполните все поля', 'Fill in all fields'));
      return;
    }

    final source = CustomKeySource(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
      type: _selectedType,
      url: (_selectedType == CustomSourceType.url ||
              _selectedType == CustomSourceType.subscription)
          ? urlOrPath
          : null,
      filePath: _selectedType == CustomSourceType.localFile ? urlOrPath : null,
      listType: _selectedListType,
    );

    await widget.provider.addCustomKeySource(source);
    _nameController.clear();
    _urlController.clear();
    _selectedType = CustomSourceType.url;
    _selectedListType = KeyListType.blackList;

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_t(context, 'Источник добавлен', 'Source added')),
        backgroundColor: AppTheme.connected,
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.redAccent,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sources = widget.provider.customKeySources;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Список существующих источников
          if (sources.isNotEmpty) ...[
            Text(
              _t(context, 'Добавленные источники:', 'Added sources:'),
              style: TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            ...sources.map((source) => _CustomSourceTile(
                  source: source,
                  onDelete: () =>
                      widget.provider.deleteCustomKeySource(source.id),
                  onToggle: (enabled) =>
                      widget.provider.toggleCustomKeySource(source.id, enabled),
                )),
            const SizedBox(height: 12),
            const Divider(color: AppTheme.textSecondary, height: 1),
            const SizedBox(height: 12),
          ],

          // Форма добавления нового источника
          Text(
            _t(context, 'Добавить новый источник:', 'Add a new source:'),
            style: TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),

          // Название
          TextField(
            controller: _nameController,
            decoration: InputDecoration(
              hintText: _t(context, 'Название источника', 'Source name'),
              hintStyle: const TextStyle(color: AppTheme.textSecondary),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: AppTheme.primary),
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
            style: const TextStyle(color: Colors.white),
          ),
          const SizedBox(height: 8),

          // Тип источника
          LayoutBuilder(
            builder: (context, constraints) {
              final isCompact = constraints.maxWidth < 540;
              final typeSelector = SegmentedButton<CustomSourceType>(
                segments: [
                  ButtonSegment(
                    value: CustomSourceType.url,
                    label: Text('URL'),
                  ),
                  ButtonSegment(
                    value: CustomSourceType.subscription,
                    label: Text(_t(context, 'Подп.', 'Sub')),
                  ),
                  ButtonSegment(
                    value: CustomSourceType.localFile,
                    label: Text(_t(context, 'Файл', 'File')),
                  ),
                ],
                selected: {_selectedType},
                onSelectionChanged: (Set<CustomSourceType> newSelection) {
                  setState(() => _selectedType = newSelection.first);
                },
              );
              final listTypeSelector = SegmentedButton<KeyListType>(
                segments: const [
                  ButtonSegment(
                    value: KeyListType.blackList,
                    label: Text('Black'),
                  ),
                  ButtonSegment(
                    value: KeyListType.whiteList,
                    label: Text('White'),
                  ),
                ],
                selected: {_selectedListType},
                onSelectionChanged: (Set<KeyListType> newSelection) {
                  setState(() => _selectedListType = newSelection.first);
                },
              );

              if (isCompact) {
                return Column(
                  children: [
                    SizedBox(width: double.infinity, child: typeSelector),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: listTypeSelector,
                    ),
                  ],
                );
              }

              return Row(
                children: [
                  Expanded(child: typeSelector),
                  const SizedBox(width: 12),
                  Expanded(child: listTypeSelector),
                ],
              );
            },
          ),
          const SizedBox(height: 8),

          // URL или путь к файлу
          TextField(
            controller: _urlController,
            decoration: InputDecoration(
              hintText: _selectedType == CustomSourceType.localFile
                  ? '/path/to/file'
                  : _selectedType == CustomSourceType.subscription
                      ? 'https://host/sub/token  или  ssconf://...  sub://...'
                      : 'https://...  или  ssconf://...',
              hintStyle: const TextStyle(color: AppTheme.textSecondary),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: AppTheme.primary),
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
            style: const TextStyle(color: Colors.white),
            maxLines: 2,
          ),
          if (_selectedType == CustomSourceType.subscription) ...[
            const SizedBox(height: 4),
            Text(
              _t(
                context,
                'Форматы ответа: ss:// / vless:// / Base64-список · SIP008 JSON · Clash YAML',
                'Response formats: ss// / vless:// / Base64 list · SIP008 JSON · Clash YAML',
              ),
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 10,
              ),
            ),
          ],
          const SizedBox(height: 12),

          // Кнопка добавления
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _addCustomSource,
              icon: const Icon(Icons.add, size: 16),
              label: Text(_t(context, 'Добавить источник', 'Add source')),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),

          if (sources.isEmpty) ...[
            const SizedBox(height: 8),
            Center(
              child: Text(
                _t(context, 'Пользовательские источники не добавлены',
                    'No custom sources added'),
                style: TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 11,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CustomSourceTile extends StatelessWidget {
  final CustomKeySource source;
  final VoidCallback onDelete;
  final ValueChanged<bool> onToggle;

  const _CustomSourceTile({
    required this.source,
    required this.onDelete,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: source.enabled
              ? AppTheme.primary.withValues(alpha: 0.3)
              : AppTheme.textSecondary.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      source.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${source.type == CustomSourceType.url ? 'URL' : source.type == CustomSourceType.subscription ? _t(context, 'Подписка', 'Subscription') : _t(context, 'Локальный файл', 'Local file')} • ${source.listType == KeyListType.blackList ? 'Black' : 'White'}',
                      style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              Checkbox(
                value: source.enabled,
                onChanged: (value) => onToggle(value ?? false),
                fillColor: WidgetStateProperty.resolveWith((states) =>
                    states.contains(WidgetState.selected)
                        ? AppTheme.primary
                        : Colors.transparent),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 18),
                color: Colors.redAccent,
                onPressed: onDelete,
              ),
            ],
          ),
          if (source.url != null && source.url!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              source.url!,
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 10,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          if (source.lastErrorMessage != null &&
              source.lastErrorMessage!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              '⚠️ ${source.lastErrorMessage}',
              style: const TextStyle(
                color: Colors.orangeAccent,
                fontSize: 10,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          if (source.lastKeyCount != null) ...[
            const SizedBox(height: 4),
            Text(
              _t(
                context,
                'Последний результат: ${source.lastKeyCount} ключей',
                'Last result: ${source.lastKeyCount} keys',
              ),
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 10,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _AppInfoTile extends StatelessWidget {
  final String versionLabel;

  const _AppInfoTile({required this.versionLabel});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.1)),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Center(
              child: AppLogoMark(size: 18, color: AppTheme.primary),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Hex Tunnel',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  versionLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

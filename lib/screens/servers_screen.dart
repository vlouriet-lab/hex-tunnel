import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../l10n/app_strings.dart';
import '../models/custom_key_source.dart';
import '../models/proxy_profile.dart';
import '../models/routing_mode.dart';
import '../services/key_loader_service.dart';
import '../theme/app_theme.dart';
import '../providers/tunnel_provider.dart';

String _t(BuildContext context, String ru, String en) {
  return context.l10n.isRussian ? ru : en;
}

String _countryName(BuildContext context, String code, String name) {
  return KeyLoaderService.toLocalizedCountryName(
    code,
    name,
    useRussian: context.l10n.isRussian,
  );
}

/// Экран списка серверов: поиск, группировка по стране, выбор, тест задержки.
class ServersScreen extends StatefulWidget {
  const ServersScreen({super.key});

  @override
  State<ServersScreen> createState() => _ServersScreenState();
}

class _ServersScreenState extends State<ServersScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _searchController.addListener(() {
      setState(() => _query = _searchController.text.toLowerCase());
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text(_t(context, 'Серверы', 'Servers')),
        backgroundColor: AppTheme.surface,
        foregroundColor: Colors.white,
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppTheme.primary,
          labelColor: AppTheme.primary,
          unselectedLabelColor: AppTheme.textSecondary,
          tabs: [
            Tab(text: _t(context, 'Авто', 'Auto')),
            Tab(text: _t(context, 'Мои', 'My')),
          ],
        ),
      ),
      body: Column(
        children: [
          _SearchBar(
            controller: _searchController,
            query: _query,
            onClear: () {
              _searchController.clear();
              setState(() => _query = '');
            },
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _AutoServersList(query: _query),
                _ManualServersList(query: _query),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Search bar ─────────────────────────────────────────────────────────────

class _SearchBar extends StatelessWidget {
  final TextEditingController controller;
  final String query;
  final VoidCallback onClear;

  const _SearchBar({
    required this.controller,
    required this.query,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppTheme.surface,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: TextField(
        controller: controller,
        style: const TextStyle(color: Colors.white, fontSize: 14),
        decoration: InputDecoration(
          hintText: _t(context, 'Поиск по серверу, стране…',
              'Search by server, country...'),
          hintStyle:
              const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
          prefixIcon:
              const Icon(Icons.search, color: AppTheme.textSecondary, size: 20),
          suffixIcon: query.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.close,
                      color: AppTheme.textSecondary, size: 18),
                  onPressed: onClear,
                )
              : null,
          filled: true,
          fillColor: AppTheme.background,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide.none,
          ),
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 10),
        ),
      ),
    );
  }
}

// ── Auto servers tab ───────────────────────────────────────────────────────

class _AutoServersList extends StatelessWidget {
  final String query;
  const _AutoServersList({required this.query});

  @override
  Widget build(BuildContext context) {
    return Consumer<TunnelProvider>(
      builder: (context, provider, _) {
        if (provider.isLoadingKeys) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(color: AppTheme.primary),
                const SizedBox(height: 12),
                Text(
                  provider.loadingMessage,
                  style: const TextStyle(
                      color: AppTheme.textSecondary, fontSize: 12),
                ),
              ],
            ),
          );
        }

        final profiles = provider.autoProfiles;
        if (profiles.isEmpty) {
          return Column(
            children: [
              _ListTypeSwitcher(provider: provider),
              Expanded(
                child: _EmptyState(
                  icon: Icons.cloud_off_outlined,
                  message: _t(
                      context, 'Нет загруженных серверов', 'No servers loaded'),
                  action: _t(context, 'Обновить', 'Refresh'),
                  onAction: () => provider.refreshKeys(context),
                ),
              ),
            ],
          );
        }

        final filtered = query.isEmpty
            ? profiles
            : profiles.where((p) {
                return p.profile.server.toLowerCase().contains(query) ||
                    p.countryName.toLowerCase().contains(query) ||
                    p.countryCode.toLowerCase().contains(query) ||
                    p.profile.name.toLowerCase().contains(query);
              }).toList();

        if (filtered.isEmpty) {
          return Column(
            children: [
              Expanded(
                child: _EmptyState(
                  icon: Icons.search_off,
                  message: _t(context, 'Ничего не найдено', 'Nothing found'),
                ),
              ),
            ],
          );
        }

        // Группируем по стране
        final grouped = <String, List<AutoProfile>>{};
        for (final p in filtered) {
          final marker = provider.keyListType == KeyListType.blackList
              ? _t(context, 'Т', 'T')
              : _t(context, 'БС', 'WL');
          final key =
              '${p.flagEmoji} $marker ${_countryName(context, p.countryCode, p.countryName)}';
          grouped.putIfAbsent(key, () => []).add(p);
        }

        return Column(
          children: [
            _ListTypeSwitcher(provider: provider),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: grouped.length,
                itemBuilder: (context, groupIdx) {
                  final countryKey = grouped.keys.elementAt(groupIdx);
                  final list = grouped[countryKey]!;
                  return _CountryGroup(
                    countryKey: countryKey,
                    profiles: list,
                    activeRawUri: provider.activeProfile?.rawUri,
                    activeListType: provider.keyListType,
                    onSelect: (profile) {
                      provider.selectAutoProfileFromList(
                        provider.keyListType,
                        profile.profile.rawUri,
                      );
                      Navigator.of(context).maybePop();
                    },
                    onTestLatency: (p) => provider.testLatency(p.profile),
                    onShowDetails: (p) =>
                        _showKeyDetailsSheet(context, p.profile),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ListTypeSwitcher extends StatelessWidget {
  final TunnelProvider provider;
  const _ListTypeSwitcher({required this.provider});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _ListTypeChip(
            label: _t(context, 'Туннель', 'Tunnel'),
            marker: _t(context, 'Т', 'T'),
            selected: provider.keyListType == KeyListType.blackList,
            onTap: () => provider.setKeyListType(KeyListType.blackList),
          ),
          _ListTypeChip(
            label: _t(context, 'Белый список', 'Whitelist'),
            marker: _t(context, 'БС', 'WL'),
            selected: provider.keyListType == KeyListType.whiteList,
            onTap: () => provider.setKeyListType(KeyListType.whiteList),
          ),
        ],
      ),
    );
  }
}

class _ListTypeChip extends StatelessWidget {
  final String label;
  final String marker;
  final bool selected;
  final VoidCallback onTap;

  const _ListTypeChip({
    required this.label,
    required this.marker,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      enableFeedback: false,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? AppTheme.primary.withValues(alpha: 0.18)
              : AppTheme.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? AppTheme.primary : AppTheme.border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              marker,
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: AppTheme.primary,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: selected ? AppTheme.primary : AppTheme.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Country group ──────────────────────────────────────────────────────────

class _CountryGroup extends StatefulWidget {
  final String countryKey;
  final List<AutoProfile> profiles;
  final String? activeRawUri;
  final KeyListType activeListType;
  final ValueChanged<AutoProfile> onSelect;
  final ValueChanged<AutoProfile> onTestLatency;
  final ValueChanged<AutoProfile> onShowDetails;

  const _CountryGroup({
    required this.countryKey,
    required this.profiles,
    required this.activeRawUri,
    required this.activeListType,
    required this.onSelect,
    required this.onTestLatency,
    required this.onShowDetails,
  });

  @override
  State<_CountryGroup> createState() => _CountryGroupState();
}

class _CountryGroupState extends State<_CountryGroup> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          enableFeedback: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.countryKey,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${widget.profiles.length}',
                    style:
                        const TextStyle(color: AppTheme.primary, fontSize: 10),
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
        if (_expanded)
          ...widget.profiles.map((ap) {
            final selected = widget.activeListType == ap.listType &&
                widget.activeRawUri == ap.profile.rawUri;
            return _AutoServerTile(
              profile: ap,
              selected: selected,
              onTap: () => widget.onSelect(ap),
              onTestLatency: () => widget.onTestLatency(ap),
              onShowDetails: () => widget.onShowDetails(ap),
            );
          }),
      ],
    );
  }
}

// ── Auto server tile ───────────────────────────────────────────────────────

class _AutoServerTile extends StatelessWidget {
  final AutoProfile profile;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onTestLatency;
  final VoidCallback onShowDetails;

  const _AutoServerTile({
    required this.profile,
    required this.selected,
    required this.onTap,
    required this.onTestLatency,
    required this.onShowDetails,
  });

  Color get _latencyColor {
    if (profile.latencyMs < 0) return AppTheme.textSecondary;
    if (profile.latencyMs < 100) return AppTheme.connected;
    if (profile.latencyMs < 300) return Colors.orange;
    return Colors.redAccent;
  }

  @override
  Widget build(BuildContext context) {
    final countryName = _countryName(
      context,
      profile.countryCode,
      profile.countryName,
    );

    return InkWell(
      onTap: onTap,
      enableFeedback: false,
      child: AnimatedContainer(
        duration: AppTheme.motionFast,
        curve: AppTheme.emphasizedCurve,
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? AppTheme.primary.withValues(alpha: 0.15)
              : AppTheme.surface.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected
                ? AppTheme.primary
                : AppTheme.primary.withValues(alpha: 0.12),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _ProtocolBadge(protocol: profile.profile.protocol),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        countryName,
                        style: TextStyle(
                          color: selected ? AppTheme.primary : Colors.white,
                          fontSize: 13,
                          fontWeight:
                              selected ? FontWeight.w600 : FontWeight.normal,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        '${profile.profile.server}:${profile.profile.port}',
                        style: const TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 11,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                if (profile.latencyMs > 0 || selected) ...[
                  const SizedBox(width: 12),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      if (profile.latencyMs > 0)
                        Text(
                          '${profile.latencyMs} ${_t(context, 'мс', 'ms')}',
                          style: TextStyle(
                            color: _latencyColor,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      if (selected) ...[
                        if (profile.latencyMs > 0) const SizedBox(height: 6),
                        const Icon(
                          Icons.check_circle,
                          color: AppTheme.primary,
                          size: 18,
                        ),
                      ],
                    ],
                  ),
                ],
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                  onPressed: onTestLatency,
                  enableFeedback: false,
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                  constraints:
                      const BoxConstraints(minWidth: 32, minHeight: 32),
                  icon: const Icon(
                    Icons.speed_outlined,
                    size: 16,
                    color: AppTheme.textSecondary,
                  ),
                ),
                TextButton(
                  onPressed: onShowDetails,
                  style: TextButton.styleFrom(
                    foregroundColor: AppTheme.primary,
                    minimumSize: const Size(0, 32),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    _t(context, 'Сведения', 'Details'),
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Manual servers tab ─────────────────────────────────────────────────────

class _ManualServersList extends StatelessWidget {
  final String query;
  const _ManualServersList({required this.query});

  @override
  Widget build(BuildContext context) {
    return Consumer<TunnelProvider>(
      builder: (context, provider, _) {
        final all = provider.manualProfiles;
        final sourceGroups = provider.customSourceProfileGroups;
        final loweredQuery = query.toLowerCase();

        final filteredGroups = query.isEmpty
            ? sourceGroups
            : sourceGroups
                .map((group) {
                  final filteredProfiles = group.profiles.where((p) {
                    return p.server.toLowerCase().contains(loweredQuery) ||
                        p.name.toLowerCase().contains(loweredQuery) ||
                        p.protocol.toLowerCase().contains(loweredQuery) ||
                        group.source.name.toLowerCase().contains(loweredQuery);
                  }).toList(growable: false);

                  if (filteredProfiles.isEmpty &&
                      !group.source.name.toLowerCase().contains(loweredQuery)) {
                    return null;
                  }

                  return CustomSourceProfilesGroup(
                    source: group.source,
                    profiles: filteredProfiles,
                    errorMessage: group.errorMessage,
                  );
                })
                .whereType<CustomSourceProfilesGroup>()
                .toList(growable: false);

        if (all.isEmpty && filteredGroups.isEmpty) {
          return _EmptyState(
            icon: Icons.add_circle_outline,
            message:
                _t(context, 'Нет добавленных серверов', 'No servers added'),
            hint: _t(context, 'Добавьте URI-ключ прямо в разделе Мои',
                'Add a URI key in the My tab'),
            action: _t(context, 'Добавить ключ', 'Add key'),
            onAction: () => _showAddManualKeySheet(context, provider),
          );
        }

        final filtered = query.isEmpty
            ? all
            : all.where((p) {
                return p.server.toLowerCase().contains(loweredQuery) ||
                    p.name.toLowerCase().contains(loweredQuery) ||
                    p.protocol.toLowerCase().contains(loweredQuery);
              }).toList();

        if (filtered.isEmpty && filteredGroups.isEmpty) {
          return _EmptyState(
            icon: Icons.search_off,
            message: _t(context, 'Ничего не найдено', 'Nothing found'),
          );
        }

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => _showAddManualKeySheet(context, provider),
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: Text(_t(context, 'Добавить ключ', 'Add key')),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  if (filteredGroups.isNotEmpty)
                    _ManualSourcesGroupList(
                      groups: filteredGroups,
                      activeRawUri: provider.activeProfile?.rawUri,
                      onSelect: (profile) {
                        provider.selectManualProfile(profile);
                        Navigator.of(context).maybePop();
                      },
                      onShowDetails: (profile) =>
                          _showKeyDetailsSheet(context, profile),
                    ),
                  ...filtered.map((p) {
                    final selected =
                        provider.activeProfile?.server == p.server &&
                            provider.activeProfile?.port == p.port;
                    return _ManualServerTile(
                      profile: p,
                      selected: selected,
                      onTap: () {
                        provider.selectManualProfile(p);
                        Navigator.of(context).maybePop();
                      },
                      onEnable: () {
                        provider.selectManualProfile(p);
                        Navigator.of(context).maybePop();
                      },
                      onDelete: () => provider.removeManualProfile(p),
                      onShowDetails: () => _showKeyDetailsSheet(context, p),
                    );
                  }),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ManualSourcesGroupList extends StatelessWidget {
  final List<CustomSourceProfilesGroup> groups;
  final String? activeRawUri;
  final ValueChanged<ProxyProfile> onSelect;
  final ValueChanged<ProxyProfile> onShowDetails;

  const _ManualSourcesGroupList({
    required this.groups,
    required this.activeRawUri,
    required this.onSelect,
    required this.onShowDetails,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppTheme.surface.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.18)),
      ),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
        iconColor: AppTheme.primary,
        collapsedIconColor: AppTheme.textSecondary,
        title: Text(
          _t(context, 'Мои источники', 'My Sources'),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
        subtitle: Text(
          _t(
            context,
            'Подключено источников: ${groups.length}',
            'Connected sources: ${groups.length}',
          ),
          style: const TextStyle(
            color: AppTheme.textSecondary,
            fontSize: 11,
          ),
        ),
        children: groups
            .map(
              (group) => _CustomSourceGroupTile(
                group: group,
                activeRawUri: activeRawUri,
                onSelect: onSelect,
                onShowDetails: onShowDetails,
              ),
            )
            .toList(growable: false),
      ),
    );
  }
}

class _CustomSourceGroupTile extends StatefulWidget {
  final CustomSourceProfilesGroup group;
  final String? activeRawUri;
  final ValueChanged<ProxyProfile> onSelect;
  final ValueChanged<ProxyProfile> onShowDetails;

  const _CustomSourceGroupTile({
    required this.group,
    required this.activeRawUri,
    required this.onSelect,
    required this.onShowDetails,
  });

  @override
  State<_CustomSourceGroupTile> createState() => _CustomSourceGroupTileState();
}

class _CustomSourceGroupTileState extends State<_CustomSourceGroupTile> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final source = widget.group.source;
    final count = widget.group.profiles.length;
    final hasError = widget.group.errorMessage != null &&
        widget.group.errorMessage!.trim().isNotEmpty;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppTheme.background.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: hasError
              ? Colors.redAccent.withValues(alpha: 0.55)
              : AppTheme.border,
        ),
      ),
      child: Column(
        children: [
          ListTile(
            dense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 10),
            leading: Icon(
              source.type == CustomSourceType.url
                  ? Icons.link_rounded
                  : source.type == CustomSourceType.subscription
                      ? Icons.rss_feed_rounded
                      : Icons.description_outlined,
              color: AppTheme.primary,
              size: 18,
            ),
            title: Text(
              source.name,
              style: const TextStyle(color: Colors.white, fontSize: 12),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              hasError
                  ? _t(context, 'Ошибка загрузки', 'Load error')
                  : _t(context, 'Ключей: $count', 'Keys: $count'),
              style: TextStyle(
                color: hasError ? Colors.redAccent : AppTheme.textSecondary,
                fontSize: 11,
              ),
            ),
            trailing: Icon(
              _expanded ? Icons.expand_less : Icons.expand_more,
              color: AppTheme.textSecondary,
              size: 18,
            ),
            onTap: () => setState(() => _expanded = !_expanded),
          ),
          if (hasError)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
              child: Text(
                widget.group.errorMessage!,
                style: const TextStyle(color: Colors.redAccent, fontSize: 11),
              ),
            ),
          if (_expanded)
            ...widget.group.profiles.map((profile) {
              final selected = widget.activeRawUri == profile.rawUri;
              return _ManualServerTile(
                profile: profile,
                selected: selected,
                onTap: () => widget.onSelect(profile),
                onEnable: () => widget.onSelect(profile),
                onDelete: () {},
                onShowDetails: () => widget.onShowDetails(profile),
                showDelete: false,
              );
            }),
        ],
      ),
    );
  }
}

Future<void> _showAddManualKeySheet(
  BuildContext context,
  TunnelProvider provider,
) {
  final controller = TextEditingController();
  String errorText = '';

  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppTheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (sheetContext) {
      return StatefulBuilder(
        builder: (context, setSheetState) {
          final bottom = MediaQuery.of(context).viewInsets.bottom;
          return SafeArea(
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, 14, 16, 14 + bottom),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _t(context, 'Добавить свой ключ', 'Add your key'),
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: controller,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    minLines: 1,
                    maxLines: 3,
                    decoration: InputDecoration(
                      hintText: _t(
                        context,
                        'vless://... или ss://... или trojan://...',
                        'vless://... or ss://... or trojan://...',
                      ),
                      hintStyle: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 12,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(
                          color: errorText.isNotEmpty
                              ? Colors.redAccent
                              : AppTheme.primary.withValues(alpha: 0.35),
                        ),
                      ),
                    ),
                    onChanged: (_) {
                      if (errorText.isNotEmpty) {
                        setSheetState(() => errorText = '');
                      }
                    },
                  ),
                  if (errorText.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      errorText,
                      style: const TextStyle(
                        color: Colors.redAccent,
                        fontSize: 11,
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        final uri = controller.text.trim();
                        final error = provider.addManualProfile(uri);
                        if (error != null) {
                          setSheetState(() => errorText = error);
                          return;
                        }
                        Navigator.of(sheetContext).pop();
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              _t(context, 'Профиль добавлен', 'Profile added'),
                            ),
                            backgroundColor: AppTheme.connected,
                            duration: Duration(seconds: 2),
                          ),
                        );
                      },
                      icon: const Icon(Icons.check_rounded, size: 18),
                      label: Text(_t(context, 'Добавить', 'Add')),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        foregroundColor: Colors.white,
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
          );
        },
      );
    },
  ).whenComplete(controller.dispose);
}

// ── Manual server tile ─────────────────────────────────────────────────────

class _ManualServerTile extends StatelessWidget {
  final ProxyProfile profile;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onEnable;
  final VoidCallback onDelete;
  final VoidCallback onShowDetails;
  final bool showDelete;

  const _ManualServerTile({
    required this.profile,
    required this.selected,
    required this.onTap,
    required this.onEnable,
    required this.onDelete,
    required this.onShowDetails,
    this.showDelete = true,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      enableFeedback: false,
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: AppTheme.motionFast,
        curve: AppTheme.emphasizedCurve,
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? AppTheme.primary.withValues(alpha: 0.15)
              : AppTheme.surface.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected
                ? AppTheme.primary
                : AppTheme.primary.withValues(alpha: 0.12),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _ProtocolBadge(protocol: profile.protocol),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        profile.name.isNotEmpty
                            ? profile.name
                            : '${profile.server}:${profile.port}',
                        style: TextStyle(
                          color: selected ? AppTheme.primary : Colors.white,
                          fontSize: 13,
                          fontWeight:
                              selected ? FontWeight.w600 : FontWeight.normal,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        '${profile.server}:${profile.port}',
                        style: const TextStyle(
                            color: AppTheme.textSecondary, fontSize: 11),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                if (selected)
                  const Padding(
                    padding: EdgeInsets.only(left: 8, top: 2),
                    child: Icon(
                      Icons.check_circle,
                      color: AppTheme.primary,
                      size: 18,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: onShowDetails,
                  style: TextButton.styleFrom(
                    foregroundColor: AppTheme.primary,
                    minimumSize: const Size(0, 28),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    _t(context, 'Сведения', 'Details'),
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
                IconButton(
                  icon: const Icon(
                    Icons.power_settings_new_rounded,
                    size: 18,
                    color: AppTheme.primary,
                  ),
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 28, minHeight: 28),
                  enableFeedback: false,
                  onPressed: onEnable,
                ),
                if (showDelete)
                  IconButton(
                    icon: const Icon(Icons.delete_outline,
                        size: 18, color: AppTheme.textSecondary),
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints(minWidth: 28, minHeight: 28),
                    enableFeedback: false,
                    onPressed: onDelete,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> _showKeyDetailsSheet(BuildContext context, ProxyProfile profile) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppTheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (context) => _KeyDetailsSheet(profile: profile),
  );
}

class _KeyDetailsSheet extends StatelessWidget {
  final ProxyProfile profile;

  const _KeyDetailsSheet({required this.profile});

  @override
  Widget build(BuildContext context) {
    final ru = context.l10n.isRussian;
    final rows = <MapEntry<String, String>>[
      MapEntry(ru ? 'Имя' : 'Name', profile.displayName),
      MapEntry(ru ? 'Протокол' : 'Protocol', profile.protocolLabel),
      MapEntry(ru ? 'Сервер' : 'Server', profile.server),
      MapEntry(ru ? 'Порт' : 'Port', profile.port.toString()),
      MapEntry(ru ? 'Транспорт' : 'Transport', profile.transport),
      MapEntry('Path/Prefix', profile.wsPath.isNotEmpty ? profile.wsPath : '/'),
      MapEntry(
          'Host',
          profile.wsHost.isNotEmpty
              ? profile.wsHost
              : (ru ? 'не указан' : 'not set')),
      MapEntry(
          'TLS',
          profile.tls
              ? (ru ? 'включен' : 'enabled')
              : (ru ? 'выключен' : 'disabled')),
      MapEntry(
          'SNI',
          profile.sni.isNotEmpty
              ? profile.sni
              : (ru ? 'не указан' : 'not set')),
      MapEntry(
          'ALPN',
          profile.alpn.isNotEmpty
              ? profile.alpn
              : (ru ? 'не указан' : 'not set')),
      MapEntry('Reality',
          profile.reality ? (ru ? 'да' : 'yes') : (ru ? 'нет' : 'no')),
      MapEntry('Fingerprint', profile.fingerprint),
    ];

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _t(context, 'Сведения о ключе', 'Key details'),
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            ...rows.map(
              (row) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 4,
                      child: Text(
                        '${row.key}:',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 6,
                      child: Text(
                        row.value,
                        style:
                            const TextStyle(color: Colors.white, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Protocol badge ─────────────────────────────────────────────────────────

class _ProtocolBadge extends StatelessWidget {
  final String protocol;
  const _ProtocolBadge({required this.protocol});

  Color get _color {
    switch (protocol.toLowerCase()) {
      case 'vless':
        return const Color(0xFF7C3AED);
      case 'ss':
      case 'shadowsocks':
        return const Color(0xFF0EA5E9);
      case 'trojan':
        return const Color(0xFF10B981);
      case 'tuic':
        return const Color(0xFFF59E0B);
      default:
        return AppTheme.textSecondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final label = protocol.length > 4
        ? protocol.substring(0, 4).toUpperCase()
        : protocol.toUpperCase();
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: _color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _color.withValues(alpha: 0.3)),
      ),
      child: Center(
        child: Text(
          label,
          style: TextStyle(
              color: _color, fontSize: 9, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}

// ── Empty state ────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String message;
  final String? hint;
  final String? action;
  final VoidCallback? onAction;

  const _EmptyState({
    required this.icon,
    required this.message,
    this.hint,
    this.action,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 48,
              color: AppTheme.primary.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 12),
            Text(
              message,
              style:
                  const TextStyle(color: AppTheme.textSecondary, fontSize: 14),
              textAlign: TextAlign.center,
            ),
            if (hint != null) ...[
              const SizedBox(height: 6),
              Text(
                hint!,
                style: const TextStyle(
                    color: AppTheme.textSecondary, fontSize: 11),
                textAlign: TextAlign.center,
              ),
            ],
            if (action != null && onAction != null) ...[
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: onAction,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.primary,
                  side: const BorderSide(color: AppTheme.primary),
                  enableFeedback: false,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                child: Text(action!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

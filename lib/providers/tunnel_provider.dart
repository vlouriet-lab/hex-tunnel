import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/app_connection_mode.dart';
import '../models/custom_key_source.dart';
import '../models/deblocker_runtime_bundle.dart';
import '../models/installed_app.dart';
import '../models/offline_deblock_profile.dart';
import '../models/proxy_profile.dart';
import '../models/relay_reputation.dart';
import '../models/routing_mode.dart';
import '../models/routing_runtime_policy.dart';
import '../models/split_tunneling.dart';
import '../models/tunnel_status.dart';
import '../services/cloudflare_warp_service.dart';
import '../services/deblocker_ingress_bundle_service.dart';
import '../services/custom_key_source_service.dart';
import '../services/deblocker_transport_validation_service.dart';
import '../services/key_loader_service.dart';
import '../services/adaptive_tunnel_policy.dart';
import '../services/singbox_service.dart';
import '../services/smart_routing_service.dart';
import '../services/uri_parser.dart';

enum AutoSelectionScope {
  allCountries,
  whiteList,
  russia,
}

extension AutoSelectionScopeExt on AutoSelectionScope {
  String get key {
    switch (this) {
      case AutoSelectionScope.allCountries:
        return 'all_countries';
      case AutoSelectionScope.whiteList:
        return 'white_list';
      case AutoSelectionScope.russia:
        return 'russia';
    }
  }

  static AutoSelectionScope fromKey(String key) {
    switch (key) {
      case 'white_list':
        return AutoSelectionScope.whiteList;
      case 'russia':
        return AutoSelectionScope.russia;
      case 'all_countries':
      default:
        return AutoSelectionScope.allCountries;
    }
  }
}

class CustomSourceProfilesGroup {
  final CustomKeySource source;
  final List<ProxyProfile> profiles;
  final String? errorMessage;

  const CustomSourceProfilesGroup({
    required this.source,
    required this.profiles,
    this.errorMessage,
  });
}

/// Центральный провайдер состояния приложения.
/// Управляет туннелем, профилями, ключами и настройками.
class TunnelProvider extends ChangeNotifier {
  // Feature flag: enable sing-box core urltest outbound pool for auto mode.
  static const bool _enableCoreUrltestForAutoMode = true;
  static const bool _enableAllowlistedIngressDelivery = true;
  static const int _coreUrltestPoolSize = 4;
  static const int _postConnectProbeAttempts = 3;
  static const Duration _postConnectProbeRetryDelay = Duration(seconds: 2);
  static const Duration _networkChangeProbeDebounce = Duration(seconds: 4);
  static const Duration _runtimeHealthMonitorInterval = Duration(seconds: 45);
  static const int _runtimeHealthFailureThreshold = 2;
  static const int _crossBorderPressurePenaltyPerLevel = 90000;
  static const int _crossBorderPressureDomesticBonusPerLevel = 400;
  static const int _crossBorderPressureMaxLevel = 3;

  final SingBoxService _singbox = SingBoxService();
  final KeyLoaderService _keyLoader = KeyLoaderService();
  final CloudflareWarpService _cloudflareWarpService = CloudflareWarpService();
  final DeblockerIngressBundleService _deblockerIngressBundleService =
      const DeblockerIngressBundleService();
  final DeblockerTransportValidationService
      _deblockerTransportValidationService =
      const DeblockerTransportValidationService();
  final SmartRoutingService _smartRoutingService = SmartRoutingService();
  static final FlutterSecureStorage _secureStorage = FlutterSecureStorage(
    aOptions: const AndroidOptions(encryptedSharedPreferences: true),
  );
  static const _rogerCode = 'RR';
  static const _rogerName = 'Роджер';
  static const _rogerFlag = '🏴‍☠️';

  TunnelStatus _status = const TunnelStatus();
  AppConnectionMode _connectionMode = AppConnectionMode.tunnel;
  OfflineDeblockProfile _offlineDeblockProfile = OfflineDeblockProfile.hybrid;
  OfflineDeblockSettings _offlineDeblockCustomSettings =
      const OfflineDeblockSettings.customDefault();
  OfflineDeblockSettings _offlineDeblockHybridSettings =
      OfflineDeblockSettings.forProfile(OfflineDeblockProfile.hybrid);
  DeblockerRuntimeBundle? _deblockerRuntimeBundle;
  DeblockerRuntimeBundle? _cachedIngressRuntimeBundle;
  bool _strictAllowlistModeEnabled = false;
  bool _isRefreshingIngressBundle = false;
  String? _ingressBundleRefreshError;
  Future<void>? _ongoingIngressBundleRefresh;
  RoutingMode _routingMode = RoutingMode.bypassLan;
  RoutingRuntimePolicy _routingRuntimePolicy = const RoutingRuntimePolicy();
  KeyListType _keyListType = KeyListType.blackList;
  SplitTunnelingMode _splitTunnelingMode = SplitTunnelingMode.off;
  bool _tunnelTlsFingerprintSpoofing = true;

  String _languageCode = 'ru';

  List<AutoProfile> _autoProfiles = [];
  List<ProxyProfile> _manualProfiles = [];
  final Map<String, CustomSourceProfilesGroup> _customSourceGroups = {};
  List<InstalledApp> _installedApps = [];
  List<String> _splitTunnelPackages = [];
  int _selectedAutoIndex = 0;
  String? _selectedAutoRawUri;
  AutoSelectionScope _homeSelectionScope = AutoSelectionScope.allCountries;
  String? _selectedAllCountryCode;
  String? _selectedWhiteListCountryCode;
  KeyListType _selectedRussiaListType = KeyListType.whiteList;
  bool _isLoadingKeys = false;
  bool _isLoadingInstalledApps = false;
  bool _isToggling = false;
  bool _isProbing = false;
  String _loadingMessage = '';
  String _selectionNotice = '';
  Timer? _connectWatchdog;
  int _autoProfilesCacheAgeMs = -1;
  bool _googleProbeInProgress = false;
  bool _runtimeHealthCheckInProgress = false;
  bool _autoFailoverInProgress = false;
  bool _autoReconnectInProgress = false;
  bool _lastPreflightFailedOffline = false;
  String _lastConnectivityProbeReasonCode = '';
  int _googleFailoverAttempts = 0;
  int _runtimeHealthConsecutiveFailures = 0;
  Future<void>? _customSourceRefreshTask;
  bool _customSourceRefreshQueued = false;
  int _customSourceRefreshGeneration = 0;
  bool _transportFallbackInProgress = false;
  bool _transportFallbackTried = false;
  ProxyProfile? _lastStartProfile;
  Timer? _runtimeHealthMonitor;
  Timer? _networkChangeProbeTimer;
  Timer? _temporaryPauseTimer;
  DateTime? _temporaryPauseEndsAt;
  bool _resumeAfterTemporaryPause = false;
  String _adaptiveMitigationNote = '';
  int _latestNetworkEventId = 0;
  final Map<String, DeblockerIngressConfig> _quarantinedIngressConfigs = {};
  final Map<String, int> _ingressEdgeFailureCounts = {};
  final Map<String, int> _ingressEdgeCooldownUntilMs = {};
  final Map<String, int> _adaptiveTransportCooldownUntilMs = {};
  final Map<String, int> _adaptiveFingerprintCooldownUntilMs = {};
  final Map<String, String> _adaptivePreferredTransportByEnv = {};
  final Map<String, String> _adaptivePreferredFingerprintByEnv = {};
  int _crossBorderPressureLevel = 0;
  int _crossBorderPressureUntilMs = 0;
  int _runtimeHealthProbeSkipCounter = 0;
  bool _antiCrisisMode = false;

  // Manual profile can be selected as the active profile
  ProxyProfile? _selectedManualProfile;
  bool _useManualProfile = false;
  String? _deferredManualProfileRawUri;

  /// История успешных подключений: countryCode → число успехов.
  /// Используется для гео-оптимизации при выборе лучшего профиля.
  Map<String, int> _successCounts = {};
  Map<String, int> _keySuccessCounts = {};
  Map<String, int> _keyFailureCounts = {};
  Map<String, int> _keyCooldownUntilMs = {};
  Map<String, int> _keyReputationScores = {};
  Map<String, int> _keyReputationUpdatedAtSec = {};
  Map<String, int> _keyConsecutiveFailures = {};
  /// Ключи, постоянно забаненные из-за провала gov-пробы (RU-регион).
  Set<String> _govFailedKeys = {};

  CustomKeySourceService? _customKeySourceService;

  StreamSubscription<TunnelStatus>? _statusSub;

  static const _maxGoogleFailoverAttempts = 5;

  // ── Getters ───────────────────────────────────────────────────────────────

  TunnelStatus get status => _status;
  TunnelStatus get effectiveStatus {
    if (!isTemporarilyPaused || _status.state != TunnelState.stopped) {
      return _status;
    }
    return _status.copyWith(statusText: temporaryPauseStatusText);
  }

  AppConnectionMode get connectionMode => _connectionMode;
  OfflineDeblockProfile get offlineDeblockProfile => _offlineDeblockProfile;
  OfflineDeblockSettings get offlineDeblockCustomSettings =>
      _offlineDeblockCustomSettings;
  OfflineDeblockSettings get offlineDeblockHybridSettings =>
      _offlineDeblockHybridSettings;
  DeblockerRuntimeBundle? get deblockerRuntimeBundle => _deblockerRuntimeBundle;
  DeblockerRuntimeBundle? get cachedIngressRuntimeBundle =>
      _cachedIngressRuntimeBundle;
  bool get allowlistedIngressFeatureEnabled =>
      _enableAllowlistedIngressDelivery;
  bool get hasConfiguredIngressControlPlane =>
      _deblockerIngressBundleService.hasConfiguredRemoteSources;
  bool get strictAllowlistModeEnabled => _strictAllowlistModeEnabled;
  bool get isRefreshingIngressBundle => _isRefreshingIngressBundle;
  String? get ingressBundleRefreshError => _ingressBundleRefreshError;
  bool get cachedIngressBundleIsSeed =>
      _cachedIngressRuntimeBundle?.isBootstrapSeedBundle ?? false;
  bool get hasValidCachedIngressBundle => _deblockerIngressBundleService
      .isBundleUsable(_cachedIngressRuntimeBundle);
  DeblockerDeliveryMode get selectedOfflineDeblockDeliveryMode {
    if (_strictAllowlistModeEnabled &&
        _enableAllowlistedIngressDelivery &&
        hasValidCachedIngressBundle) {
      return DeblockerDeliveryMode.allowlistedIngress;
    }
    if (_offlineDeblockProfile == OfflineDeblockProfile.hybrid) {
      return DeblockerDeliveryMode.warpHybridLegacy;
    }
    return DeblockerDeliveryMode.directOnly;
  }

  OfflineDeblockSettings get effectiveOfflineDeblockSettings =>
      switch (_offlineDeblockProfile) {
        OfflineDeblockProfile.custom => _offlineDeblockCustomSettings,
        OfflineDeblockProfile.hybrid => _offlineDeblockHybridSettings,
        _ => OfflineDeblockSettings.forProfile(_offlineDeblockProfile),
      };
  RoutingMode get routingMode => _routingMode;
  RoutingRuntimePolicy get routingRuntimePolicy => _routingRuntimePolicy;
  KeyListType get keyListType => _keyListType;
  SplitTunnelingMode get splitTunnelingMode => _splitTunnelingMode;
  bool get tunnelTlsFingerprintSpoofing => _tunnelTlsFingerprintSpoofing;

  String get languageCode => _languageCode;
  List<AutoProfile> get allAutoProfiles => List.unmodifiable(_autoProfiles);
  List<AutoProfile> get autoProfiles =>
      List.unmodifiable(_filteredAutoProfiles);
  List<ProxyProfile> get manualProfiles => List.unmodifiable(_manualProfiles);
  List<CustomSourceProfilesGroup> get customSourceProfileGroups {
    final groups = _customSourceGroups.values.toList(growable: false);
    groups.sort(
      (a, b) => a.source.name.toLowerCase().compareTo(
            b.source.name.toLowerCase(),
          ),
    );
    return groups;
  }

  List<InstalledApp> get installedApps => List.unmodifiable(_installedApps);
  List<String> get splitTunnelPackages =>
      List.unmodifiable(_splitTunnelPackages);
  int get selectedAutoIndex => _selectedAutoIndex;
  AutoSelectionScope get homeSelectionScope => _homeSelectionScope;
  String? get selectedAllCountryCode => _selectedAllCountryCode;
  String? get selectedWhiteListCountryCode => _selectedWhiteListCountryCode;
  KeyListType get selectedRussiaListType => _selectedRussiaListType;
  String get selectionNotice => _selectionNotice;
  bool get isLoadingKeys => _isLoadingKeys;
  bool get isLoadingInstalledApps => _isLoadingInstalledApps;
  bool get isProbing => _isProbing;
  String get loadingMessage => _loadingMessage;
  bool get isAutoReconnecting => _autoReconnectInProgress;
  bool get isTunnelMode => _connectionMode == AppConnectionMode.tunnel;
  bool get isOfflineDeblockMode =>
      _connectionMode == AppConnectionMode.offlineDeblock;
  bool get isTemporarilyPaused {
    final endsAt = _temporaryPauseEndsAt;
    return endsAt != null && endsAt.isAfter(DateTime.now());
  }

  DateTime? get temporaryPauseEndsAt => _temporaryPauseEndsAt;
  bool get hasVpnCompatibilityBypass =>
      _splitTunnelingMode == SplitTunnelingMode.exceptSelected &&
      _splitTunnelPackages.isNotEmpty;
  int get vpnCompatibilityBypassCount =>
      hasVpnCompatibilityBypass ? _splitTunnelPackages.length : 0;
  String get temporaryPauseStatusText {
    final endsAt = _temporaryPauseEndsAt;
    if (endsAt == null) {
      return 'Пауза';
    }
    final remaining = endsAt.difference(DateTime.now());
    if (remaining.inSeconds <= 0) {
      return 'Пауза закончилась';
    }
    final minutes = remaining.inMinutes;
    if (minutes <= 0) {
      return 'Пауза меньше минуты';
    }
    return 'Пауза на $minutes мин';
  }

  bool get hasAdaptiveMitigations {
    _evictExpiredAdaptiveCooldowns();
    return _adaptiveTransportCooldownUntilMs.isNotEmpty ||
        _adaptiveFingerprintCooldownUntilMs.isNotEmpty ||
        _adaptivePreferredTransportByEnv.isNotEmpty ||
        _adaptivePreferredFingerprintByEnv.isNotEmpty ||
        _isCrossBorderPressureActive() ||
        _adaptiveMitigationNote.trim().isNotEmpty;
  }

  bool get antiCrisisMode => _antiCrisisMode;

  int get crossBorderPressureLevel {
    _evictExpiredCrossBorderPressure();
    return _crossBorderPressureLevel;
  }

  String get adaptiveMitigationSummary {
    _evictExpiredAdaptiveCooldowns();
    final parts = <String>[];
    if (_adaptiveMitigationNote.trim().isNotEmpty) {
      parts.add(_adaptiveMitigationNote.trim());
    }
    if (_adaptiveTransportCooldownUntilMs.isNotEmpty) {
      parts.add(
        'транспортных ограничений: ${_adaptiveTransportCooldownUntilMs.length}',
      );
    }
    if (_adaptiveFingerprintCooldownUntilMs.isNotEmpty) {
      parts.add(
        'TLS fingerprint-ротаций: ${_adaptiveFingerprintCooldownUntilMs.length}',
      );
    }
    final envStrategyCount = _adaptiveEnvironmentStrategyCount();
    if (envStrategyCount > 0) {
      parts.add('сетевых стратегий: $envStrategyCount');
    }
    if (_isCrossBorderPressureActive()) {
      parts.add(
          'перегрузка внешних каналов: уровень $_crossBorderPressureLevel');
      if (_crossBorderPressureLevel > 1) {
        parts.add(
            'режим экономии проб: каждые ${_crossBorderPressureLevel * 45}с');
      }
    }
    if (_antiCrisisMode) {
      parts.add('антикризисный режим: вкл');
    }
    if (parts.isEmpty) {
      return 'Адаптация среды активна';
    }
    return parts.join(' • ');
  }

  // Custom key sources getters
  List<CustomKeySource> get customKeySources =>
      _customKeySourceService?.getAllSources() ?? [];
  List<CustomKeySource> get enabledCustomKeySources =>
      _customKeySourceService?.getEnabledSources() ?? [];

  List<AutoProfile> get _filteredAutoProfiles => _autoProfiles
      .where((ap) => ap.listType == _keyListType)
      .toList(growable: false);

  String? get selectedHomeCountryCode {
    switch (_homeSelectionScope) {
      case AutoSelectionScope.allCountries:
        return _selectedAllCountryCode;
      case AutoSelectionScope.whiteList:
        return _selectedWhiteListCountryCode;
      case AutoSelectionScope.russia:
        return 'RU';
    }
  }

  ProxyProfile? get activeProfile {
    if (_useManualProfile && _selectedManualProfile != null) {
      return _selectedManualProfile;
    }
    if (_selectedAutoRawUri != null && _selectedAutoRawUri!.isNotEmpty) {
      for (final ap in _autoProfiles) {
        if (ap.profile.rawUri == _selectedAutoRawUri) {
          return ap.profile;
        }
      }
    }
    return null;
  }

  AutoProfile? get activeAutoProfile {
    if (_useManualProfile) {
      return null;
    }
    final current = activeProfile;
    if (current == null) {
      return null;
    }
    for (final ap in _autoProfiles) {
      if (ap.profile.rawUri == current.rawUri) {
        return ap;
      }
    }
    return null;
  }

  // ── Initialization ────────────────────────────────────────────────────────

  Future<void> init() async {
    await _loadPrefs();
    await _bootstrapCachedIngressBundle(notify: true);
    _listenStatus();
    await _syncRuntimeStatus();
    // При каждом запуске обязательно обновляем ключи с основного источника.
    // Кэш используется только как мгновенный старт до прихода свежих данных.
    if (_autoProfiles.isEmpty) {
      await refreshKeys(
        null,
        silent: true,
        allowReserveSources: false,
      );
      return;
    }

    unawaited(
      refreshKeys(
        null,
        silent: true,
        allowReserveSources: false,
      ),
    );
  }

  void _listenStatus() {
    _statusSub?.cancel();
    _statusSub = _singbox.statusStream.listen((s) {
      if (_transportFallbackInProgress && s.state != TunnelState.connected) {
        _stopRuntimeHealthMonitor(resetFailures: false);
        return;
      }

      if (_autoReconnectInProgress && s.state == TunnelState.stopped) {
        _stopRuntimeHealthMonitor(resetFailures: false);
        _status = _status.copyWith(
          state: TunnelState.connecting,
          statusText: 'Переподключение…',
          errorMessage: '',
          errorCode: '',
          stage: 'auto_reconnect',
        );
        notifyListeners();
        return;
      }

      if (_autoReconnectInProgress && s.state == TunnelState.connected) {
        _autoReconnectInProgress = false;
      }

      if (_transportFallbackInProgress && s.state == TunnelState.connected) {
        _transportFallbackInProgress = false;
      }

      final canFallbackToWs = !_transportFallbackTried &&
          !_transportFallbackInProgress &&
          _status.state == TunnelState.connecting &&
          s.state == TunnelState.error &&
          _lastStartProfile != null &&
          _supportsSilentWsFallback(_lastStartProfile!);
      if (canFallbackToWs) {
        unawaited(_attemptSilentWsFallback(_lastStartProfile!));
        return;
      }

      final prevStatus = _status;
      final normalizedError =
          (s.state == TunnelState.error && s.errorMessage.trim().isEmpty)
              ? _fallbackErrorText(s.errorCode, s.stage)
              : s.errorMessage;

      // Cancel watchdog on any terminal state
      if (s.state != TunnelState.connecting) {
        _connectWatchdog?.cancel();
        _connectWatchdog = null;
      }

      _status = s.copyWith(
        routingMode: _routingMode,
        errorMessage: normalizedError,
        statusText: _statusTextForMode(s),
      );
      if (s.state != TunnelState.connected ||
          !_shouldMonitorRuntimeHealthForCurrentMode()) {
        _stopRuntimeHealthMonitor(resetFailures: false);
        _cancelNetworkChangeHealthCheck();
      }
      notifyListeners();

      final shouldHandleNetworkChange =
          prevStatus.state == TunnelState.connected &&
              s.state == TunnelState.connected &&
              _shouldMonitorRuntimeHealthForCurrentMode() &&
              s.networkEventId > 0 &&
              s.networkEventId != prevStatus.networkEventId;
      if (shouldHandleNetworkChange) {
        _scheduleNetworkChangeHealthCheck(s);
      }

      if (s.state == TunnelState.connected &&
          prevStatus.state != TunnelState.connected) {
        if (_connectionMode == AppConnectionMode.tunnel) {
          // После поднятия туннеля проверяем именно реальный выход в интернет/Google.
          unawaited(_validateGoogleReachabilityAfterConnect(s.activeServer));
        } else if (_shouldMonitorOfflineDeblockRuntime()) {
          _startRuntimeHealthMonitor();
        }
      }
    }, onError: (error) {
      // VPN process may have crashed — reset to stopped
      debugPrint('TunnelProvider: status stream error: $error');
      _resetToStopped();
    }, onDone: () {
      // Stream closed unexpectedly (e.g. VPN process died)
      if (_status.state == TunnelState.connecting) {
        debugPrint('TunnelProvider: status stream closed while connecting');
        _resetToStopped();
      }
    });
  }

  void _resetToStopped() {
    _connectWatchdog?.cancel();
    _connectWatchdog = null;
    _stopRuntimeHealthMonitor();
    _cancelNetworkChangeHealthCheck(resetEventId: true);
    _isToggling = false;
    _status = TunnelStatus(
      state: TunnelState.error,
      statusText: 'Ошибка',
      errorMessage: 'VPN-процесс неожиданно завершился. Попробуйте снова.',
      errorCode: 'vpn_process_died',
      stage: 'runtime',
      routingMode: _routingMode,
    );
    notifyListeners();
  }

  void _startConnectWatchdog() {
    _connectWatchdog?.cancel();
    _connectWatchdog = Timer(const Duration(seconds: 30), () async {
      if (_status.state == TunnelState.connecting) {
        debugPrint('TunnelProvider: connection watchdog fired after 30s');
        try {
          await _singbox.stop();
        } catch (_) {}
        _isToggling = false;
        _status = TunnelStatus(
          state: TunnelState.error,
          statusText: 'Ошибка',
          errorMessage: 'Таймаут подключения (30с). VPN-процесс не ответил.',
          errorCode: 'connect_timeout',
          stage: 'start',
          routingMode: _routingMode,
        );
        notifyListeners();
      }
    });
  }

  void _startRuntimeHealthMonitor() {
    if (!_shouldMonitorRuntimeHealthForCurrentMode()) {
      _stopRuntimeHealthMonitor();
      return;
    }

    _runtimeHealthMonitor?.cancel();
    _runtimeHealthConsecutiveFailures = 0;
    _runtimeHealthMonitor = Timer.periodic(_runtimeHealthMonitorInterval, (_) {
      unawaited(_runRuntimeHealthMonitorTick());
    });
  }

  bool _shouldMonitorRuntimeHealthForCurrentMode() {
    if (_connectionMode == AppConnectionMode.tunnel) {
      return true;
    }
    return _shouldMonitorOfflineDeblockRuntime();
  }

  bool _shouldMonitorOfflineDeblockRuntime({
    DeblockerRuntimeBundle? runtimeBundle,
  }) {
    if (_connectionMode != AppConnectionMode.offlineDeblock) {
      return false;
    }

    final bundle = runtimeBundle ?? _deblockerRuntimeBundle;
    if (bundle?.deliveryMode == DeblockerDeliveryMode.allowlistedIngress) {
      return true;
    }

    return _strictAllowlistModeEnabled &&
        _enableAllowlistedIngressDelivery &&
        hasConfiguredIngressControlPlane;
  }

  void _stopRuntimeHealthMonitor({bool resetFailures = true}) {
    _runtimeHealthMonitor?.cancel();
    _runtimeHealthMonitor = null;
    _runtimeHealthCheckInProgress = false;
    if (resetFailures) {
      _runtimeHealthConsecutiveFailures = 0;
    }
  }

  Iterable<DeblockerIngressConfig> _activeQuarantinedIngressConfigs({
    Iterable<DeblockerIngressConfig> additionalConfigs =
        const <DeblockerIngressConfig>[],
  }) {
    _evictExpiredIngressEdgeCooldowns();
    final configs = <String, DeblockerIngressConfig>{
      ..._quarantinedIngressConfigs,
    };
    for (final config in additionalConfigs) {
      final key = _ingressEdgeKey(config);
      if (key.isEmpty) {
        continue;
      }
      configs[key] = config;
    }
    return configs.values.toList(growable: false);
  }

  bool _isIngressEdgeInCooldown(DeblockerIngressConfig? config) {
    if (config == null) {
      return false;
    }

    _evictExpiredIngressEdgeCooldowns();
    final key = _ingressEdgeKey(config);
    if (key.isEmpty) {
      return false;
    }
    final until = _ingressEdgeCooldownUntilMs[key] ?? 0;
    return until > DateTime.now().millisecondsSinceEpoch;
  }

  void _markIngressEdgeSuccess(DeblockerIngressConfig? config) {
    if (config == null) {
      return;
    }

    final key = _ingressEdgeKey(config);
    if (key.isEmpty) {
      return;
    }

    _quarantinedIngressConfigs.remove(key);
    _ingressEdgeFailureCounts.remove(key);
    _ingressEdgeCooldownUntilMs.remove(key);
  }

  void _markIngressEdgeFailure(
    DeblockerIngressConfig? config, {
    required String reason,
  }) {
    if (config == null) {
      return;
    }

    final key = _ingressEdgeKey(config);
    if (key.isEmpty) {
      return;
    }

    _evictExpiredIngressEdgeCooldowns();
    final failureCount = (_ingressEdgeFailureCounts[key] ?? 0) + 1;
    _ingressEdgeFailureCounts[key] = failureCount;
    _quarantinedIngressConfigs[key] = config;
    final cooldown = _backoffDurationForFailures(failureCount);
    final until = DateTime.now().add(cooldown).millisecondsSinceEpoch;
    _ingressEdgeCooldownUntilMs[key] = until;
    debugPrint(
      'TunnelProvider: quarantined ingress edge '
      'reason=$reason '
      'edge=${_describeIngressTarget(config)} '
      'cooldown=${cooldown.inSeconds}s '
      'failures=$failureCount',
    );
  }

  void _evictExpiredIngressEdgeCooldowns() {
    if (_ingressEdgeCooldownUntilMs.isEmpty) {
      return;
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    final expiredKeys = _ingressEdgeCooldownUntilMs.entries
        .where((entry) => entry.value <= now)
        .map((entry) => entry.key)
        .toList(growable: false);
    for (final key in expiredKeys) {
      _ingressEdgeCooldownUntilMs.remove(key);
      _quarantinedIngressConfigs.remove(key);
      _ingressEdgeFailureCounts.remove(key);
    }
  }

  String _ingressEdgeKey(DeblockerIngressConfig config) {
    final alpn = config.alpn
        .map((value) => value.trim().toLowerCase())
        .where((value) => value.isNotEmpty)
        .join(',');
    return [
      config.enabled ? '1' : '0',
      config.provider.trim().toLowerCase(),
      config.outboundType.trim().toLowerCase(),
      config.edgeHost.trim().toLowerCase(),
      config.edgePort.toString(),
      config.transport.trim().toLowerCase(),
      config.path.trim(),
      config.hostHeader.trim().toLowerCase(),
      config.sni.trim().toLowerCase(),
      alpn,
      config.grpcServiceName.trim(),
      config.username.trim(),
      config.password.trim(),
      config.uuid.trim().toLowerCase(),
      config.skipCertVerify ? '1' : '0',
      config.fingerprint.trim().toLowerCase(),
    ].join('|');
  }

  void _cancelNetworkChangeHealthCheck({bool resetEventId = false}) {
    _networkChangeProbeTimer?.cancel();
    _networkChangeProbeTimer = null;
    if (resetEventId) {
      _latestNetworkEventId = 0;
    }
  }

  void _scheduleNetworkChangeHealthCheck(TunnelStatus status) {
    final eventId = status.networkEventId;
    if (eventId <= 0) {
      return;
    }

    _latestNetworkEventId = eventId;
    _networkChangeProbeTimer?.cancel();
    final networkLabel = _networkLabel(status);
    debugPrint(
      'TunnelProvider: network change detected '
      'eventId=$eventId path=$networkLabel',
    );

    _networkChangeProbeTimer = Timer(_networkChangeProbeDebounce, () {
      _networkChangeProbeTimer = null;
      if (_latestNetworkEventId != eventId) {
        return;
      }
      unawaited(_runNetworkChangeHealthCheck(eventId, networkLabel));
    });
  }

  Future<void> _runNetworkChangeHealthCheck(
    int eventId,
    String networkLabel,
  ) async {
    if (_latestNetworkEventId != eventId ||
        _runtimeHealthCheckInProgress ||
        _autoReconnectInProgress ||
        _autoFailoverInProgress ||
        _transportFallbackInProgress ||
        _isToggling ||
        _status.state != TunnelState.connected) {
      return;
    }

    if (_connectionMode == AppConnectionMode.tunnel && _googleProbeInProgress) {
      return;
    }

    if (_connectionMode == AppConnectionMode.offlineDeblock &&
        !_shouldMonitorOfflineDeblockRuntime()) {
      return;
    }

    if (_connectionMode != AppConnectionMode.tunnel &&
        _connectionMode != AppConnectionMode.offlineDeblock) {
      return;
    }

    _runtimeHealthCheckInProgress = true;
    try {
      if (_connectionMode == AppConnectionMode.offlineDeblock) {
        await _runOfflineDeblockRuntimeHealthMonitorTick(
          triggeredByNetworkChange: true,
          networkLabel: networkLabel,
        );
        return;
      }

      final requiresGovProbe = _shouldUseGovProbeForCurrentProfile();
      final probeResult = await _runPostConnectProbeWithGrace(requiresGovProbe);
      if (probeResult.ok) {
        _runtimeHealthConsecutiveFailures = 0;
        _googleFailoverAttempts = 0;
        debugPrint(
          'TunnelProvider: network change probe succeeded '
          'path=$networkLabel scope=${requiresGovProbe ? 'gov' : 'public'}',
        );
        return;
      }

      _runtimeHealthConsecutiveFailures = 0;
      debugPrint(
        'TunnelProvider: network change probe failed '
        'path=$networkLabel scope=${requiresGovProbe ? 'gov' : 'public'} '
        'reason=${probeResult.reasonCode}',
      );
      await _handleRuntimeHealthFailure(requiresGovProbe);
    } catch (e, st) {
      debugPrint('TunnelProvider._runNetworkChangeHealthCheck error: $e\n$st');
    } finally {
      _runtimeHealthCheckInProgress = false;
    }
  }

  String _networkLabel(TunnelStatus status) {
    final transport = status.networkTransport.trim().isEmpty
        ? 'unknown'
        : status.networkTransport.trim();
    final interfaceName = status.networkInterface.trim();
    if (interfaceName.isEmpty) {
      return transport;
    }
    return '$transport/$interfaceName';
  }

  Future<void> _syncRuntimeStatus() async {
    try {
      final runtimeStatus = await _singbox.getStatus();
      if (runtimeStatus.state != TunnelState.stopped) {
        _status = runtimeStatus.copyWith(routingMode: _routingMode);
        if (runtimeStatus.state == TunnelState.connected &&
            _shouldMonitorRuntimeHealthForCurrentMode()) {
          _startRuntimeHealthMonitor();
        } else {
          _stopRuntimeHealthMonitor();
          _cancelNetworkChangeHealthCheck();
        }
        notifyListeners();
        return;
      }

      final isActuallyRunning = await _singbox.isRunning();
      if (!isActuallyRunning) {
        return;
      }

      _status = TunnelStatus(
        state: TunnelState.connected,
        statusText: _connectedStatusText(),
        routingMode: _routingMode,
      );
      if (_shouldMonitorRuntimeHealthForCurrentMode()) {
        _startRuntimeHealthMonitor();
      }
      notifyListeners();
    } catch (e, st) {
      debugPrint('TunnelProvider._syncRuntimeStatus error: $e\n$st');
    }
  }

  Future<void> _runRuntimeHealthMonitorTick() async {
    if (_runtimeHealthCheckInProgress ||
        _autoReconnectInProgress ||
        _autoFailoverInProgress ||
        _isToggling ||
        _status.state != TunnelState.connected) {
      return;
    }

    if (_connectionMode == AppConnectionMode.tunnel && _googleProbeInProgress) {
      return;
    }

    if (_connectionMode == AppConnectionMode.offlineDeblock &&
        !_shouldMonitorOfflineDeblockRuntime()) {
      return;
    }

    if (_connectionMode != AppConnectionMode.tunnel &&
        _connectionMode != AppConnectionMode.offlineDeblock) {
      return;
    }

    _runtimeHealthCheckInProgress = true;
    try {
      if (_connectionMode == AppConnectionMode.offlineDeblock) {
        await _runOfflineDeblockRuntimeHealthMonitorTick();
        return;
      }

      // Pressure-aware probe budget: under cross-border channel pressure, reduce
      // probe frequency to avoid adding load on already-congested routes.
      // Level N → skip N-1 ticks, i.e. probe every (N * 45)s instead of every 45s.
      if (_isCrossBorderPressureActive() && _crossBorderPressureLevel > 1) {
        _runtimeHealthProbeSkipCounter++;
        if (_runtimeHealthProbeSkipCounter < _crossBorderPressureLevel) {
          return;
        }
        _runtimeHealthProbeSkipCounter = 0;
      } else {
        _runtimeHealthProbeSkipCounter = 0;
      }

      final requiresGovProbe = _shouldUseGovProbeForCurrentProfile();
      final probeResult = await _runPostConnectProbeWithGrace(requiresGovProbe);
      if (probeResult.ok) {
        _runtimeHealthConsecutiveFailures = 0;
        _googleFailoverAttempts = 0;
        if (!requiresGovProbe) {
          _relaxCrossBorderPressureOnSuccess();
        }
        return;
      }

      _runtimeHealthConsecutiveFailures += 1;
      debugPrint(
        'TunnelProvider: runtime health probe failed '
        'count=$_runtimeHealthConsecutiveFailures '
        'scope=${requiresGovProbe ? 'gov' : 'public'} '
        'reason=${probeResult.reasonCode}',
      );

      if (_runtimeHealthConsecutiveFailures < _runtimeHealthFailureThreshold) {
        return;
      }

      _runtimeHealthConsecutiveFailures = 0;
      await _handleRuntimeHealthFailure(requiresGovProbe);
    } catch (e, st) {
      debugPrint('TunnelProvider._runRuntimeHealthMonitorTick error: $e\n$st');
    } finally {
      _runtimeHealthCheckInProgress = false;
    }
  }

  Future<void> _runOfflineDeblockRuntimeHealthMonitorTick({
    bool triggeredByNetworkChange = false,
    String? networkLabel,
  }) async {
    final runtimeBundle = _deblockerRuntimeBundle;
    if (_connectionMode != AppConnectionMode.offlineDeblock ||
        _status.state != TunnelState.connected ||
        !_shouldMonitorOfflineDeblockRuntime(runtimeBundle: runtimeBundle)) {
      return;
    }

    final restoredAllowlisted =
        await _attemptOfflineDeblockAllowlistedIngressRestore(
      currentBundle: runtimeBundle,
      reason: triggeredByNetworkChange
          ? 'network change'
          : 'periodic runtime monitor',
    );
    if (restoredAllowlisted) {
      _runtimeHealthConsecutiveFailures = 0;
      return;
    }

    if (runtimeBundle == null ||
        runtimeBundle.deliveryMode !=
            DeblockerDeliveryMode.allowlistedIngress) {
      _runtimeHealthConsecutiveFailures = 0;
      return;
    }

    final ingressConfig = runtimeBundle.ingressConfig;
    if (ingressConfig == null || !ingressConfig.isConfigured) {
      await _handleOfflineDeblockRuntimeBundleFailure(
        runtimeBundle,
        reason: 'runtime ingress missing',
        message: 'Активный allowlisted ingress bundle потерял рабочий edge.',
      );
      return;
    }

    if (runtimeBundle.isExpired || ingressConfig.isExpired) {
      await _handleOfflineDeblockRuntimeBundleFailure(
        runtimeBundle,
        reason: 'runtime ingress expired',
        message: 'Активный allowlisted ingress bundle устарел во время работы.',
      );
      return;
    }

    final edgeReachable =
        await _deblockerTransportValidationService.probeEdgeReachability(
      ingressConfig,
    );
    if (edgeReachable) {
      _runtimeHealthConsecutiveFailures = 0;
      if (_deblockerIngressBundleService.shouldRefreshFromControlPlane(
            _cachedIngressRuntimeBundle,
          ) &&
          !_isRefreshingIngressBundle) {
        unawaited(_refreshIngressBundleIfNeeded());
      }

      if (triggeredByNetworkChange) {
        debugPrint(
          'TunnelProvider: offline deblock ingress probe succeeded '
          'path=${networkLabel ?? '-'} '
          'edge=${_describeIngressTarget(ingressConfig)}',
        );
      }
      return;
    }

    _runtimeHealthConsecutiveFailures += 1;
    debugPrint(
      'TunnelProvider: offline deblock ingress probe failed '
      'count=$_runtimeHealthConsecutiveFailures '
      'path=${networkLabel ?? '-'} '
      'edge=${_describeIngressTarget(ingressConfig)}',
    );

    if (_runtimeHealthConsecutiveFailures < _runtimeHealthFailureThreshold) {
      return;
    }

    _runtimeHealthConsecutiveFailures = 0;
    await _handleOfflineDeblockRuntimeBundleFailure(
      runtimeBundle,
      reason: triggeredByNetworkChange
          ? 'network change ingress unreachable'
          : 'runtime ingress unreachable',
      message: 'Allowlisted ingress edge недоступен: ${ingressConfig.edgeHost}',
    );
  }

  Future<bool> _attemptOfflineDeblockAllowlistedIngressRestore({
    required DeblockerRuntimeBundle? currentBundle,
    required String reason,
  }) async {
    if (_connectionMode != AppConnectionMode.offlineDeblock ||
        _status.state != TunnelState.connected ||
        !_strictAllowlistModeEnabled ||
        !_enableAllowlistedIngressDelivery ||
        !hasConfiguredIngressControlPlane ||
        currentBundle?.deliveryMode ==
            DeblockerDeliveryMode.allowlistedIngress) {
      return false;
    }

    final cachedCandidate = _materializeCachedAllowlistedIngressBundle();
    var preparedBundle = cachedCandidate == null
        ? null
        : await _prepareRestorableAllowlistedIngressBundle(cachedCandidate);

    if (preparedBundle == null) {
      final excludedIngressConfigs = _activeQuarantinedIngressConfigs();
      final recoveredBundle = await _refreshIngressBundleForRecovery(
        excludedIngressConfigs: excludedIngressConfigs,
      );
      if (recoveredBundle != null) {
        final materializedBundle =
            _deblockerIngressBundleService.materializeBundle(
          recoveredBundle,
          profilePreset: _offlineDeblockProfile,
          settings: effectiveOfflineDeblockSettings,
          bootstrapSource: recoveredBundle.bootstrapSource ?? 'cached',
        );
        preparedBundle = await _prepareRestorableAllowlistedIngressBundle(
            materializedBundle);
      }
    }

    if (preparedBundle == null) {
      debugPrint(
        'TunnelProvider: allowlisted ingress restore skipped '
        'reason=$reason '
        'refreshError=${_ingressBundleRefreshError ?? '-'}',
      );
      return false;
    }

    debugPrint(
      'TunnelProvider: allowlisted ingress restore succeeded '
      'reason=$reason '
      'edge=${_describeIngressTarget(preparedBundle.ingressConfig)} '
      'bundleVersion=${preparedBundle.bundleVersion}',
    );
    return _restartOfflineDeblockWithRuntimeBundle(
      preparedBundle,
      statusText: 'Возвращаем allowlisted ingress…',
      stage: 'allowlisted_ingress_restore',
    );
  }

  Future<DeblockerRuntimeBundle?> _prepareRestorableAllowlistedIngressBundle(
    DeblockerRuntimeBundle runtimeBundle,
  ) async {
    final ingressConfig = runtimeBundle.ingressConfig;
    if (ingressConfig == null ||
        !ingressConfig.isConfigured ||
        ingressConfig.isExpired ||
        runtimeBundle.isExpired) {
      return null;
    }

    if (_isIngressEdgeInCooldown(ingressConfig)) {
      return null;
    }

    final validation =
        _deblockerTransportValidationService.validateConfig(ingressConfig);
    final hasBlockingIssues = validation.issues.any(
      (issue) => issue.severity == DeblockerTransportValidationSeverity.error,
    );
    if (hasBlockingIssues) {
      _markIngressEdgeFailure(
        ingressConfig,
        reason: 'restore transport rejected by policy',
      );
      return null;
    }

    final edgeReachable =
        await _deblockerTransportValidationService.probeEdgeReachability(
      ingressConfig,
    );
    if (!edgeReachable) {
      _markIngressEdgeFailure(
        ingressConfig,
        reason: 'restore edge unreachable',
      );
      return null;
    }

    _markIngressEdgeSuccess(ingressConfig);

    final preparedBundle = runtimeBundle.copyWith(
      refreshedAt: DateTime.now().toUtc().toIso8601String(),
      bootstrapSource: runtimeBundle.bootstrapSource ?? 'cached',
    );
    _deblockerRuntimeBundle = preparedBundle;
    await _savePrefs();
    return preparedBundle;
  }

  DeblockerRuntimeBundle? _materializeCachedAllowlistedIngressBundle() {
    final cachedBundle = _cachedIngressRuntimeBundle;
    if (!_deblockerIngressBundleService.isBundleUsable(cachedBundle)) {
      return null;
    }

    final materialized = _deblockerIngressBundleService.materializeBundle(
      cachedBundle!,
      profilePreset: _offlineDeblockProfile,
      settings: effectiveOfflineDeblockSettings,
      bootstrapSource: cachedBundle.bootstrapSource ?? 'cached',
    );
    if (_isIngressEdgeInCooldown(materialized.ingressConfig)) {
      return null;
    }
    return materialized;
  }

  Future<void> _handleOfflineDeblockRuntimeBundleFailure(
    DeblockerRuntimeBundle failedBundle, {
    required String reason,
    required String message,
  }) async {
    if (_connectionMode != AppConnectionMode.offlineDeblock ||
        _status.state != TunnelState.connected) {
      return;
    }

    _stopRuntimeHealthMonitor(resetFailures: false);
    _cancelNetworkChangeHealthCheck();
    _markIngressEdgeFailure(
      failedBundle.ingressConfig,
      reason: reason,
    );

    DeblockerRuntimeBundle nextBundle;
    try {
      nextBundle = await _recoverOrFallbackFromAllowlistedIngress(
        failedBundle,
        reason: reason,
        message: message,
        allowRecovery: true,
      );
    } catch (e) {
      await _singbox.stop();
      _status = TunnelStatus(
        state: TunnelState.error,
        statusText: 'Ошибка',
        errorMessage: e.toString(),
        errorCode: 'offline_deblock_runtime_recovery_failed',
        stage: 'offline_deblock_runtime_recover',
        routingMode: _routingMode,
      );
      notifyListeners();
      return;
    }

    final statusText =
        nextBundle.deliveryMode == DeblockerDeliveryMode.allowlistedIngress
            ? 'Перезапускаем ingress transport…'
            : 'Перезапускаем деблокер в fallback-режиме…';
    final stage =
        nextBundle.deliveryMode == DeblockerDeliveryMode.allowlistedIngress
            ? 'offline_deblock_runtime_restart'
            : 'offline_deblock_runtime_fallback';

    await _restartOfflineDeblockWithRuntimeBundle(
      nextBundle,
      statusText: statusText,
      stage: stage,
    );
  }

  Future<bool> _restartOfflineDeblockWithRuntimeBundle(
    DeblockerRuntimeBundle runtimeBundle, {
    required String statusText,
    required String stage,
  }) async {
    _status = _status.copyWith(
      state: TunnelState.connecting,
      statusText: statusText,
      errorMessage: '',
      errorCode: '',
      stage: stage,
    );
    notifyListeners();

    _stopRuntimeHealthMonitor(resetFailures: false);
    _cancelNetworkChangeHealthCheck();

    try {
      await _singbox.stop();
    } catch (_) {}

    _startConnectWatchdog();

    try {
      final ok = await _singbox.startOfflineDeblock(
        runtimeBundle.profilePreset,
        settings: runtimeBundle.settings,
        runtimeBundle: runtimeBundle,
        notificationRegion: 'Локальный деблок',
      );
      if (!ok) {
        await _singbox.stop();
        _status = TunnelStatus(
          state: TunnelState.error,
          statusText: 'Ошибка',
          errorMessage:
              'Не удалось перезапустить деблокер после runtime recovery.',
          errorCode: 'offline_deblock_runtime_restart_failed',
          stage: stage,
          routingMode: _routingMode,
        );
        notifyListeners();
      }
      return ok;
    } on PlatformException catch (e) {
      await _singbox.stop();
      _status = TunnelStatus(
        state: TunnelState.error,
        statusText: 'Ошибка',
        errorMessage: _platformErrorToText(e),
        errorCode: e.code,
        stage: stage,
        routingMode: _routingMode,
      );
      notifyListeners();
      return false;
    } catch (e) {
      await _singbox.stop();
      _status = TunnelStatus(
        state: TunnelState.error,
        statusText: 'Ошибка',
        errorMessage: e.toString(),
        errorCode: 'offline_deblock_runtime_restart_failed',
        stage: stage,
        routingMode: _routingMode,
      );
      notifyListeners();
      return false;
    }
  }

  Future<void> _handleRuntimeHealthFailure(bool requiresGovProbe) async {
    if (_status.state != TunnelState.connected ||
        _connectionMode != AppConnectionMode.tunnel) {
      return;
    }

    _stopRuntimeHealthMonitor(resetFailures: false);
    if (requiresGovProbe) {
      _markActiveKeyGovFailed();
    } else {
      _markActiveKeyFailure();
    }
    final reasonCode = _probeAwareErrorCode(
      requiresGovProbe ? 'runtime_gov_unreachable' : 'runtime_public_unreachable',
    );
    final detailHint = _probeFailureHint(requiresGovProbe);
    _markAdaptiveTunnelFailure(
      _lastStartProfile,
      reason: requiresGovProbe
          ? 'runtime_gov_unreachable'
          : 'runtime_public_unreachable',
    );
    if (!requiresGovProbe) {
      _recordCrossBorderPressureSignal(reason: 'runtime_public_unreachable');
    }

    if (_useManualProfile) {
      await _singbox.stop();
      _status = TunnelStatus(
        state: TunnelState.error,
        statusText: 'Ошибка',
        errorMessage: requiresGovProbe
            ? 'Соединение деградировало: gov.ru/gosuslugi.ru перестали открываться через текущий ключ.$detailHint'
            : 'Соединение деградировало: внешний интернет перестал открываться через текущий ключ.$detailHint',
        errorCode: reasonCode,
        stage: 'runtime_health_monitor',
        routingMode: _routingMode,
      );
      notifyListeners();
      return;
    }

    _googleFailoverAttempts += 1;
    if (_googleFailoverAttempts > _maxGoogleFailoverAttempts) {
      _autoReconnectInProgress = false;
      await _singbox.stop();
      _status = TunnelStatus(
        state: TunnelState.error,
        statusText: 'Ошибка',
        errorMessage: requiresGovProbe
            ? 'После нескольких попыток не удалось удержать рабочий доступ к gov.ru/gosuslugi.ru.$detailHint'
            : 'После нескольких попыток не удалось удержать рабочий доступ к внешнему интернету.$detailHint',
        errorCode: _probeAwareErrorCode(
          requiresGovProbe
              ? 'runtime_gov_unreachable_all'
              : 'runtime_public_unreachable_all',
        ),
        stage: 'runtime_health_monitor',
        routingMode: _routingMode,
      );
      notifyListeners();
      return;
    }

    _status = _status.copyWith(
      state: TunnelState.connecting,
      statusText: requiresGovProbe
          ? 'Доступ к RU-ресурсам деградировал, меняем ключ…'
          : 'Доступ в интернет деградировал, меняем ключ…',
      errorMessage: '',
      errorCode: '',
      stage: 'runtime_health_recover',
    );
    notifyListeners();

    await _autoFailoverAfterGoogleProbeFailure();
  }

  Future<void> _validateGoogleReachabilityAfterConnect(
      String activeServer) async {
    if (_googleProbeInProgress) return;

    _googleProbeInProgress = true;
    try {
      final requiresGovProbe = _shouldUseGovProbeForCurrentProfile();
      final probeResult = await _runPostConnectProbeWithGrace(requiresGovProbe);
      if (probeResult.ok) {
        _googleFailoverAttempts = 0;
        _autoReconnectInProgress = false;
        if (!requiresGovProbe) {
          _relaxCrossBorderPressureOnSuccess();
        }
        _markAdaptiveTunnelSuccess(_lastStartProfile);
        _startRuntimeHealthMonitor();
        _recordSuccessfulConnection();
        return;
      }

      // Для manual-профиля не переключаем автоматически, только сообщаем ошибку.
      if (_useManualProfile) {
        _markActiveKeyFailure();
        _markAdaptiveTunnelFailure(
          _lastStartProfile,
          reason: requiresGovProbe
              ? 'manual_gov_unreachable'
              : 'manual_public_unreachable',
        );
        await _singbox.stop();
        _status = TunnelStatus(
          state: TunnelState.error,
          statusText: 'Ошибка',
          errorMessage: requiresGovProbe
              ? 'Туннель поднят, но gov.ru/gosuslugi.ru недоступны через этот ключ. Выберите другой сервер.${_probeFailureHint(requiresGovProbe)}'
              : 'Туннель поднят, но внешний интернет недоступен через этот ключ. Выберите другой сервер.${_probeFailureHint(requiresGovProbe)}',
          errorCode: _probeAwareErrorCode(
            requiresGovProbe ? 'gov_unreachable' : 'public_internet_unreachable',
          ),
          stage: 'post_connect_check',
          routingMode: _routingMode,
        );
        notifyListeners();
        return;
      }

      _googleFailoverAttempts += 1;
      _markActiveKeyFailure();
      _markAdaptiveTunnelFailure(
        _lastStartProfile,
        reason: requiresGovProbe ? 'gov_probe_failed' : 'public_probe_failed',
      );
      if (!requiresGovProbe) {
        _recordCrossBorderPressureSignal(reason: 'public_probe_failed');
      }
      if (_googleFailoverAttempts > _maxGoogleFailoverAttempts) {
        _autoReconnectInProgress = false;
        await _singbox.stop();
        _status = TunnelStatus(
          state: TunnelState.error,
          statusText: 'Ошибка',
          errorMessage: requiresGovProbe
              ? 'Не удалось найти рабочий ключ: туннель поднимается, но gov.ru/gosuslugi.ru недоступны.${_probeFailureHint(requiresGovProbe)}'
              : 'Не удалось найти рабочий ключ: туннель поднимается, но внешний интернет недоступен.${_probeFailureHint(requiresGovProbe)}',
          errorCode: _probeAwareErrorCode(
            requiresGovProbe
                ? 'gov_unreachable_all'
                : 'public_internet_unreachable_all',
          ),
          stage: 'post_connect_check',
          routingMode: _routingMode,
        );
        notifyListeners();
        return;
      }

      await _autoFailoverAfterGoogleProbeFailure();
    } catch (e, st) {
      debugPrint(
          'TunnelProvider._validateGoogleReachabilityAfterConnect error: $e\n$st');
    } finally {
      _googleProbeInProgress = false;
    }
  }

  Future<ConnectivityProbeResult> _runPostConnectProbeWithGrace(
    bool requiresGovProbe,
  ) async {
    ConnectivityProbeResult lastFailure =
        const ConnectivityProbeResult(ok: false, reasonCode: 'unknown');
    for (var attempt = 1; attempt <= _postConnectProbeAttempts; attempt++) {
      final result = requiresGovProbe
          ? await _singbox.probeRussianGovResourcesDetailed()
          : await _singbox.probePublicInternetDetailed();
      if (result.ok) {
        _lastConnectivityProbeReasonCode = '';
        return result;
      }
      lastFailure = result;
      if (attempt < _postConnectProbeAttempts) {
        await Future<void>.delayed(_postConnectProbeRetryDelay);
      }
    }
    _lastConnectivityProbeReasonCode = lastFailure.reasonCode;
    return lastFailure;
  }

  String _probeAwareErrorCode(String baseCode) {
    final reason = _lastConnectivityProbeReasonCode.trim();
    if (reason.isEmpty) {
      return baseCode;
    }
    return '${baseCode}_$reason';
  }

  String _probeFailureHint(bool requiresGovProbe) {
    final reason = _lastConnectivityProbeReasonCode.trim();
    if (reason.isEmpty) {
      return '';
    }
    final detail = ConnectivityProbeResult.reasonDescription(
      reason,
      requiresGovProbe: requiresGovProbe,
    );
    return ' Диагностика: $detail.';
  }

  bool _shouldUseGovProbeForCurrentProfile() {
    if (_connectionMode != AppConnectionMode.tunnel) {
      return false;
    }
    if (_useManualProfile) {
      return _homeSelectionScope == AutoSelectionScope.russia;
    }
    final current = activeAutoProfile;
    if (current == null) {
      return _homeSelectionScope == AutoSelectionScope.russia;
    }
    return _normalizeCountryCode(current.countryCode) == 'RU';
  }

  Future<void> _autoFailoverAfterGoogleProbeFailure() async {
    if (_autoFailoverInProgress) return;
    _autoFailoverInProgress = true;
    try {
      _autoReconnectInProgress = true;
      await _singbox.stop();

      _status = _status.copyWith(
        state: TunnelState.connecting,
        statusText: 'Переподключение: смена ключа…',
        errorMessage: '',
        errorCode: '',
        stage: 'auto_reconnect',
      );
      notifyListeners();

      final next = await _pickReachableAutoProfileForCurrentSelection(
        allowCountryFallback: true,
        allowRussiaReload: true,
      );
      if (next == null) {
        _autoReconnectInProgress = false;
        _status = TunnelStatus(
          state: TunnelState.error,
          statusText: 'Ошибка',
          errorMessage: _noReachableServerMessage(afterProbe: true),
          errorCode: 'no_reachable_server_after_probe',
          stage: 'post_connect_failover',
          routingMode: _routingMode,
        );
        notifyListeners();
        return;
      }

      final effectiveNext = _materializeAdaptiveTunnelProfile(next.profile);
      _lastStartProfile = effectiveNext;
      _startConnectWatchdog();
      final smartRoutingPath = await _getSmartRoutingDatasetPath();
      final ok = await _singbox.start(
        effectiveNext,
        _routingMode,
        _splitTunnelingMode,
        _splitTunnelPackages,
        routingRuntimePolicy:
            _routingRuntimePolicy.hasOverrides ? _routingRuntimePolicy : null,
        enableCoreUrltest: _enableCoreUrltestForAutoMode,
        coreUrltestCandidates: _buildCoreUrltestCandidatePool(effectiveNext),
        enableTlsUtlsFingerprintSpoofing: _tunnelTlsFingerprintSpoofing,
        smartRoutingDatasetPath: smartRoutingPath,
        notificationRegion: _notificationRegionLabelForProfile(effectiveNext),
      );
      if (!ok) {
        _markAdaptiveTunnelFailure(
          effectiveNext,
          reason: 'start_failed_after_probe',
        );
        _autoReconnectInProgress = false;
        _status = TunnelStatus(
          state: TunnelState.error,
          statusText: 'Ошибка',
          errorMessage: 'Не удалось запустить следующий ключ после failover',
          errorCode: 'start_failed_after_probe',
          stage: 'post_connect_failover',
          routingMode: _routingMode,
        );
        notifyListeners();
      }
    } finally {
      _autoFailoverInProgress = false;
    }
  }

  // ── Tunnel control ────────────────────────────────────────────────────────

  Future<void> toggleConnection(BuildContext? context) async {
    if (_isToggling) return;
    if (isTemporarilyPaused) {
      _cancelTemporaryPause(notify: false);
    }
    _isToggling = true;
    try {
      final isActuallyRunning = await _singbox.isRunning();
      if (_status.state.isActive || isActuallyRunning) {
        _status = _status.copyWith(
          state: TunnelState.stopped,
          statusText: 'Отключение…',
          errorMessage: '',
          errorCode: '',
          stage: 'stop',
        );
        notifyListeners();
        await _stop();
      } else {
        if (context != null && !context.mounted) return;
        if (_connectionMode == AppConnectionMode.offlineDeblock) {
          await _startOfflineDeblock();
        } else {
          await _start(context);
        }
      }
    } finally {
      _isToggling = false;
    }
  }

  Future<void> pauseConnectionTemporarily(
    Duration duration, {
    BuildContext? context,
  }) async {
    if (_isToggling) return;

    final shouldResume = _status.state.isActive || await _singbox.isRunning();
    _temporaryPauseTimer?.cancel();
    _temporaryPauseEndsAt = DateTime.now().add(duration);
    _resumeAfterTemporaryPause = shouldResume;
    _temporaryPauseTimer = Timer(duration, _handleTemporaryPauseFinished);

    if (shouldResume) {
      _isToggling = true;
      try {
        _status = _status.copyWith(
          state: TunnelState.stopped,
          statusText: 'Пауза…',
          errorMessage: '',
          errorCode: '',
          stage: 'pause',
        );
        notifyListeners();
        await _stop();
      } finally {
        _isToggling = false;
      }
    }

    _status = _status.copyWith(
      state: TunnelState.stopped,
      statusText: temporaryPauseStatusText,
      errorMessage: '',
      errorCode: '',
      stage: 'pause',
    );
    notifyListeners();

    if (context != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('VPN приостановлен на ${duration.inMinutes} мин')),
      );
    }
  }

  Future<void> resumeConnectionAfterPause(BuildContext? context) async {
    if (_isToggling) return;
    final shouldResume = _resumeAfterTemporaryPause;
    _cancelTemporaryPause(notify: false);
    if (!shouldResume) {
      notifyListeners();
      return;
    }
    await toggleConnection(context);
  }

  Future<void> _start(BuildContext? context) async {
    _autoReconnectInProgress = false;
    _lastPreflightFailedOffline = false;
    _stopRuntimeHealthMonitor();
    _transportFallbackInProgress = false;
    _transportFallbackTried = false;
    _lastStartProfile = null;
    _evictExpiredAdaptiveCooldowns();
    final initialProfile =
        activeProfile ?? _pickDefaultProfileForQuickConnect();
    if (initialProfile == null) {
      if (context != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Выберите сервер')),
        );
      }
      return;
    }

    _status = _status.copyWith(
      state: TunnelState.connecting,
      statusText: 'Проверка сервера…',
      errorMessage: '',
      errorCode: '',
      stage: 'preflight',
    );
    notifyListeners();

    final profile = await _pickReachableProfile(initialProfile);
    if (profile == null) {
      _status = TunnelStatus(
        state: TunnelState.error,
        statusText: 'Ошибка',
        errorMessage: _noReachableServerMessage(),
        errorCode: 'no_reachable_server',
        stage: 'preflight',
        routingMode: _routingMode,
      );
      notifyListeners();
      return;
    }

    final effectiveProfile = _materializeAdaptiveTunnelProfile(profile);
    _lastStartProfile = effectiveProfile;

    _status = _status.copyWith(
      state: TunnelState.connecting,
      statusText: effectiveProfile.rawUri == profile.rawUri &&
              effectiveProfile.transport == profile.transport &&
              effectiveProfile.fingerprint == profile.fingerprint
          ? 'Подключение…'
          : 'Подключение… (адаптация среды)',
      stage: 'start',
    );
    notifyListeners();
    _startConnectWatchdog();

    try {
      final useCoreUrltest =
          _enableCoreUrltestForAutoMode && !_useManualProfile;
      final coreUrltestCandidates =
          useCoreUrltest ? _buildCoreUrltestCandidatePool(profile) : null;

      final smartRoutingPath = await _getSmartRoutingDatasetPath();
      final ok = await _singbox.start(
        effectiveProfile,
        _routingMode,
        _splitTunnelingMode,
        _splitTunnelPackages,
        routingRuntimePolicy:
            _routingRuntimePolicy.hasOverrides ? _routingRuntimePolicy : null,
        enableCoreUrltest: useCoreUrltest,
        coreUrltestCandidates: coreUrltestCandidates,
        enableTlsUtlsFingerprintSpoofing: _tunnelTlsFingerprintSpoofing,
        smartRoutingDatasetPath: smartRoutingPath,
        notificationRegion: _notificationRegionLabelForProfile(effectiveProfile),
      );
      if (!ok) {
        await _singbox.stop();
        _markAdaptiveTunnelFailure(effectiveProfile, reason: 'start_failed');
        _status = TunnelStatus(
          state: TunnelState.error,
          statusText: 'Ошибка',
          errorMessage: 'Не удалось запустить туннель',
          errorCode: 'start_failed',
          stage: 'start',
          routingMode: _routingMode,
        );
        notifyListeners();
      }
    } on PlatformException catch (e) {
      await _singbox.stop();
      _markAdaptiveTunnelFailure(
        effectiveProfile,
        reason: 'platform_${e.code.toLowerCase()}',
      );
      _status = TunnelStatus(
        state: TunnelState.error,
        statusText: 'Ошибка',
        errorMessage: _platformErrorToText(e),
        errorCode: e.code,
        stage: 'start',
        routingMode: _routingMode,
      );
      notifyListeners();
    } catch (e) {
      await _singbox.stop();
      _markAdaptiveTunnelFailure(effectiveProfile, reason: 'start_exception');
      _status = TunnelStatus(
        state: TunnelState.error,
        statusText: 'Ошибка',
        errorMessage: e.toString(),
        errorCode: 'unknown',
        stage: 'start',
        routingMode: _routingMode,
      );
      notifyListeners();
    }
  }

  bool _supportsSilentWsFallback(ProxyProfile profile) {
    return profile.protocol == 'vless' && profile.transport == 'xhttp';
  }

  Future<void> _attemptSilentWsFallback(ProxyProfile profile) async {
    if (_transportFallbackInProgress || _transportFallbackTried) {
      return;
    }

    _transportFallbackInProgress = true;
    _transportFallbackTried = true;
    try {
      _markAdaptiveTunnelFailure(profile, reason: 'xhttp_failed');
      final fallbackProfile = profile.copyWith(transport: 'ws');
      _lastStartProfile = fallbackProfile;

      _status = _status.copyWith(
        state: TunnelState.connecting,
        statusText: 'Подключение… (резервный транспорт)',
        errorMessage: '',
        errorCode: '',
        stage: 'transport_fallback_ws',
      );
      notifyListeners();

      await _singbox.stop();
      _startConnectWatchdog();

      final smartRoutingPath = await _getSmartRoutingDatasetPath();
      final ok = await _singbox.start(
        fallbackProfile,
        _routingMode,
        _splitTunnelingMode,
        _splitTunnelPackages,
        routingRuntimePolicy:
            _routingRuntimePolicy.hasOverrides ? _routingRuntimePolicy : null,
        enableCoreUrltest: false,
        enableTlsUtlsFingerprintSpoofing: _tunnelTlsFingerprintSpoofing,
        smartRoutingDatasetPath: smartRoutingPath,
        notificationRegion: _notificationRegionLabelForProfile(profile),
      );
      if (!ok) {
        _markAdaptiveTunnelFailure(
          fallbackProfile,
          reason: 'start_failed_ws_fallback',
        );
        _status = TunnelStatus(
          state: TunnelState.error,
          statusText: 'Ошибка',
          errorMessage:
              'Не удалось запустить туннель через резервный транспорт',
          errorCode: 'start_failed_ws_fallback',
          stage: 'transport_fallback_ws',
          routingMode: _routingMode,
        );
        notifyListeners();
      }
    } catch (e) {
      _markAdaptiveTunnelFailure(profile, reason: 'ws_fallback_exception');
      _status = TunnelStatus(
        state: TunnelState.error,
        statusText: 'Ошибка',
        errorMessage: e.toString(),
        errorCode: 'start_failed_ws_fallback',
        stage: 'transport_fallback_ws',
        routingMode: _routingMode,
      );
      notifyListeners();
    } finally {
      _transportFallbackInProgress = false;
    }
  }

  Future<void> _startOfflineDeblock() async {
    _autoReconnectInProgress = false;
    _stopRuntimeHealthMonitor();
    _status = _status.copyWith(
      state: TunnelState.connecting,
      statusText: 'Запуск деблокера (${_offlineDeblockProfile.displayName})…',
      errorMessage: '',
      errorCode: '',
      stage: 'start',
    );
    notifyListeners();
    _startConnectWatchdog();

    try {
      await _ensureStrictAllowlistBundleReadyBeforeStart();
      final runtimeBundle = _resolveOfflineDeblockRuntimeBundle();
      final preparedBundle = await _prepareOfflineDeblockRuntimeBundle(
        runtimeBundle,
      );
      final ok = await _singbox.startOfflineDeblock(
        preparedBundle.profilePreset,
        settings: preparedBundle.settings,
        runtimeBundle: preparedBundle,
        notificationRegion: 'Локальный деблок',
      );
      if (!ok) {
        await _singbox.stop();
        _status = TunnelStatus(
          state: TunnelState.error,
          statusText: 'Ошибка',
          errorMessage: 'Не удалось запустить деблокер',
          errorCode: 'offline_deblock_start_failed',
          stage: 'start',
          routingMode: _routingMode,
        );
        notifyListeners();
      }
    } on PlatformException catch (e) {
      await _singbox.stop();
      _status = TunnelStatus(
        state: TunnelState.error,
        statusText: 'Ошибка',
        errorMessage: _platformErrorToText(e),
        errorCode: e.code,
        stage: 'start',
        routingMode: _routingMode,
      );
      notifyListeners();
    } catch (e) {
      await _singbox.stop();
      _status = TunnelStatus(
        state: TunnelState.error,
        statusText: 'Ошибка',
        errorMessage: e.toString(),
        errorCode: 'unknown',
        stage: 'start',
        routingMode: _routingMode,
      );
      notifyListeners();
    }
  }

  Future<void> _ensureStrictAllowlistBundleReadyBeforeStart() async {
    if (!_strictAllowlistModeEnabled ||
        !_enableAllowlistedIngressDelivery ||
        !hasConfiguredIngressControlPlane) {
      return;
    }

    final cachedBundle = _cachedIngressRuntimeBundle;
    final bundleAlreadyReady = !_deblockerIngressBundleService
            .shouldRefreshFromControlPlane(cachedBundle) &&
        _deblockerIngressBundleService.isBundleUsable(cachedBundle);
    if (bundleAlreadyReady) {
      return;
    }

    _status = _status.copyWith(
      state: TunnelState.connecting,
      statusText: 'Обновляем ingress bundle перед стартом…',
      errorMessage: '',
      errorCode: '',
      stage: 'ingress_bundle_refresh',
    );
    notifyListeners();

    await _refreshIngressBundleIfNeeded(force: true);
  }

  DeblockerRuntimeBundle _resolveOfflineDeblockRuntimeBundle() {
    final settings = effectiveOfflineDeblockSettings;
    final cachedIngressBundle = _cachedIngressRuntimeBundle;

    if (_strictAllowlistModeEnabled &&
        _enableAllowlistedIngressDelivery &&
        _deblockerIngressBundleService.isBundleUsable(cachedIngressBundle)) {
      final resolvedIngressBundle =
          _deblockerIngressBundleService.materializeBundle(
        cachedIngressBundle!,
        profilePreset: _offlineDeblockProfile,
        settings: settings,
        bootstrapSource: cachedIngressBundle.bootstrapSource ?? 'cached',
      );
      debugPrint(
        'TunnelProvider: selected delivery mode=${resolvedIngressBundle.deliveryMode.key} '
        'source=${resolvedIngressBundle.bootstrapSource ?? 'cached'} '
        'version=${resolvedIngressBundle.bundleVersion}',
      );
      return resolvedIngressBundle;
    }

    final fallbackBundle = DeblockerRuntimeBundle.legacy(
      profilePreset: _offlineDeblockProfile,
      settings: settings,
    );
    debugPrint(
      'TunnelProvider: selected delivery mode=${fallbackBundle.deliveryMode.key} '
      'source=${fallbackBundle.bootstrapSource ?? 'generated_legacy'} '
      'version=${fallbackBundle.bundleVersion}',
    );
    return fallbackBundle;
  }

  Future<DeblockerRuntimeBundle> _prepareOfflineDeblockRuntimeBundle(
    DeblockerRuntimeBundle runtimeBundle,
  ) async {
    switch (runtimeBundle.deliveryMode) {
      case DeblockerDeliveryMode.directOnly:
        _deblockerRuntimeBundle = runtimeBundle;
        await _savePrefs();
        return runtimeBundle;
      case DeblockerDeliveryMode.allowlistedIngress:
        return _prepareAllowlistedIngressRuntimeBundle(runtimeBundle);
      case DeblockerDeliveryMode.warpHybridLegacy:
        return _prepareLegacyWarpHybridRuntimeBundle(runtimeBundle);
    }
  }

  Future<DeblockerRuntimeBundle> _prepareAllowlistedIngressRuntimeBundle(
    DeblockerRuntimeBundle runtimeBundle, {
    bool allowRecovery = true,
  }) async {
    final ingressConfig = runtimeBundle.ingressConfig;
    if (ingressConfig == null || !ingressConfig.isConfigured) {
      return _recoverOrFallbackFromAllowlistedIngress(
        runtimeBundle,
        reason: 'ingress bundle missing',
        message: 'Не найден allowlisted ingress bundle для выбранного профиля',
        allowRecovery: allowRecovery,
      );
    }
    if (ingressConfig.isExpired || runtimeBundle.isExpired) {
      return _recoverOrFallbackFromAllowlistedIngress(
        runtimeBundle,
        reason: 'ingress bundle expired',
        message: 'Ingress bundle устарел и требует обновления',
        allowRecovery: allowRecovery,
      );
    }
    if (_isIngressEdgeInCooldown(ingressConfig)) {
      return _recoverOrFallbackFromAllowlistedIngress(
        runtimeBundle,
        reason: 'allowlisted edge in cooldown',
        message:
            'Allowlisted edge временно находится в quarantine: ${ingressConfig.edgeHost}',
        allowRecovery: allowRecovery,
      );
    }

    _status = _status.copyWith(
      state: TunnelState.connecting,
      statusText: 'Загружаем ingress bundle…',
      errorMessage: '',
      errorCode: '',
      stage: 'ingress_bundle_prepare',
    );
    notifyListeners();

    final validation =
        _deblockerTransportValidationService.validateConfig(ingressConfig);
    final blockingIssue = validation.issues.where(
      (issue) => issue.severity == DeblockerTransportValidationSeverity.error,
    );
    if (blockingIssue.isNotEmpty) {
      _markIngressEdgeFailure(
        ingressConfig,
        reason: 'transport rejected by policy',
      );
      return _recoverOrFallbackFromAllowlistedIngress(
        runtimeBundle,
        reason: 'transport rejected by policy',
        message: blockingIssue.first.message,
        allowRecovery: allowRecovery,
      );
    }

    _status = _status.copyWith(
      state: TunnelState.connecting,
      statusText: 'Проверяем allowlisted edge…',
      errorMessage: '',
      errorCode: '',
      stage: 'ingress_edge_probe',
    );
    notifyListeners();

    final edgeReachable =
        await _deblockerTransportValidationService.probeEdgeReachability(
      ingressConfig,
    );
    if (!edgeReachable) {
      _markIngressEdgeFailure(
        ingressConfig,
        reason: 'allowlisted edge unreachable',
      );
      return _recoverOrFallbackFromAllowlistedIngress(
        runtimeBundle,
        reason: 'allowlisted edge unreachable',
        message: 'Allowlisted edge недоступен: ${ingressConfig.edgeHost}',
        allowRecovery: allowRecovery,
      );
    }

    _markIngressEdgeSuccess(ingressConfig);

    debugPrint(
      'TunnelProvider: allowlisted ingress transport=${ingressConfig.transport} '
      'outbound=${ingressConfig.outboundType} '
      'edge=${ingressConfig.edgeHost}:${ingressConfig.edgePort} '
      'bundleVersion=${runtimeBundle.bundleVersion}',
    );

    _status = _status.copyWith(
      state: TunnelState.connecting,
      statusText: 'Запускаем ingress transport…',
      errorMessage: '',
      errorCode: '',
      stage: 'ingress_transport_start',
    );
    notifyListeners();

    _deblockerRuntimeBundle = runtimeBundle.copyWith(
      refreshedAt: DateTime.now().toUtc().toIso8601String(),
      bootstrapSource: runtimeBundle.bootstrapSource ?? 'cached',
    );
    await _savePrefs();
    return _deblockerRuntimeBundle!;
  }

  Future<DeblockerRuntimeBundle> _recoverOrFallbackFromAllowlistedIngress(
    DeblockerRuntimeBundle failedBundle, {
    required String reason,
    required String message,
    required bool allowRecovery,
  }) async {
    if (allowRecovery) {
      final recoveredBundle = await _attemptAllowlistedIngressRecovery(
        failedBundle,
        reason: reason,
      );
      if (recoveredBundle != null) {
        return _prepareAllowlistedIngressRuntimeBundle(
          recoveredBundle,
          allowRecovery: false,
        );
      }
    }

    return _fallbackFromAllowlistedIngress(
      failedBundle,
      reason: reason,
      message: message,
    );
  }

  Future<DeblockerRuntimeBundle?> _attemptAllowlistedIngressRecovery(
    DeblockerRuntimeBundle failedBundle, {
    required String reason,
  }) async {
    if (!_strictAllowlistModeEnabled ||
        !_enableAllowlistedIngressDelivery ||
        !hasConfiguredIngressControlPlane) {
      return null;
    }

    final failedIngress = failedBundle.ingressConfig;
    final excludedIngressConfigs = _activeQuarantinedIngressConfigs(
      additionalConfigs: failedIngress == null
          ? const <DeblockerIngressConfig>[]
          : <DeblockerIngressConfig>[failedIngress],
    );

    _status = _status.copyWith(
      state: TunnelState.connecting,
      statusText: 'Ищем резервный ingress edge…',
      errorMessage: '',
      errorCode: '',
      stage: 'allowlisted_ingress_recover',
    );
    notifyListeners();

    final recoveredBundle = await _refreshIngressBundleForRecovery(
      excludedIngressConfigs: excludedIngressConfigs,
    );
    if (recoveredBundle == null) {
      debugPrint(
        'TunnelProvider: allowlisted ingress recovery failed '
        'reason=$reason '
        'previousEdge=${_describeIngressTarget(failedIngress)} '
        'refreshError=${_ingressBundleRefreshError ?? '-'}',
      );
      return null;
    }

    debugPrint(
      'TunnelProvider: allowlisted ingress recovery succeeded '
      'reason=$reason '
      'previousEdge=${_describeIngressTarget(failedIngress)} '
      'newEdge=${_describeIngressTarget(recoveredBundle.ingressConfig)} '
      'bundleVersion=${recoveredBundle.bundleVersion}',
    );
    return recoveredBundle;
  }

  Future<DeblockerRuntimeBundle?> _refreshIngressBundleForRecovery({
    required Iterable<DeblockerIngressConfig> excludedIngressConfigs,
  }) async {
    final ongoingRefresh = _ongoingIngressBundleRefresh;
    if (ongoingRefresh != null) {
      await ongoingRefresh;
      final cachedBundle = _cachedIngressRuntimeBundle;
      if (_isUsableAlternativeIngressBundle(
        cachedBundle,
        excludedIngressConfigs: excludedIngressConfigs,
      )) {
        return cachedBundle;
      }
    }

    final completer = Completer<void>();
    _ongoingIngressBundleRefresh = completer.future;
    _isRefreshingIngressBundle = true;
    _ingressBundleRefreshError = null;
    notifyListeners();

    try {
      final result =
          await _deblockerIngressBundleService.refreshFromControlPlane(
        cachedBundle: _cachedIngressRuntimeBundle,
        profilePreset: _offlineDeblockProfile,
        settings: effectiveOfflineDeblockSettings,
        excludedIngressConfigs: excludedIngressConfigs,
      );

      if (result.isSuccess && result.bundle != null) {
        _cachedIngressRuntimeBundle = result.bundle;
        _ingressBundleRefreshError = null;
        debugPrint(
          'TunnelProvider: ingress recovery refresh '
          'source=${result.source ?? '-'} '
          'version=${result.bundle!.bundleVersion} '
          'edge=${_describeIngressTarget(result.bundle!.ingressConfig)} '
          'changed=${result.didChange}',
        );
        await _savePrefs();
        return result.bundle;
      }

      _ingressBundleRefreshError = result.failureReason;
      debugPrint(
        'TunnelProvider: ingress recovery refresh failed '
        'reason=${result.failureReason ?? 'unknown'}',
      );
      return null;
    } catch (e) {
      _ingressBundleRefreshError = '$e';
      debugPrint('TunnelProvider: ingress recovery refresh exception=$e');
      return null;
    } finally {
      _isRefreshingIngressBundle = false;
      _ongoingIngressBundleRefresh = null;
      if (!completer.isCompleted) {
        completer.complete();
      }
      notifyListeners();
    }
  }

  bool _isUsableAlternativeIngressBundle(
    DeblockerRuntimeBundle? bundle, {
    required Iterable<DeblockerIngressConfig> excludedIngressConfigs,
  }) {
    if (!_deblockerIngressBundleService.isBundleUsable(bundle)) {
      return false;
    }

    return !_deblockerIngressBundleService.isExcludedIngressConfig(
      bundle?.ingressConfig,
      excludedIngressConfigs,
    );
  }

  String _describeIngressTarget(DeblockerIngressConfig? config) {
    if (config == null) {
      return '-';
    }

    final host = config.edgeHost.trim().isEmpty ? '-' : config.edgeHost.trim();
    final transport =
        config.transport.trim().isEmpty ? 'unknown' : config.transport.trim();
    return '$host:${config.edgePort}/$transport';
  }

  Future<DeblockerRuntimeBundle> _fallbackFromAllowlistedIngress(
    DeblockerRuntimeBundle failedBundle, {
    required String reason,
    required String message,
  }) async {
    debugPrint(
      'TunnelProvider: allowlisted ingress fallback reason=$reason '
      'edge=${failedBundle.ingressConfig?.edgeHost ?? '-'} '
      'bundleVersion=${failedBundle.bundleVersion}',
    );
    final ingressConfig = failedBundle.ingressConfig;
    if (ingressConfig != null && !ingressConfig.allowDirectFallback) {
      throw Exception(message);
    }

    final fallbackBundle = DeblockerRuntimeBundle.legacy(
      profilePreset: _offlineDeblockProfile,
      settings: effectiveOfflineDeblockSettings,
    );
    final fallbackLabel =
        fallbackBundle.deliveryMode == DeblockerDeliveryMode.warpHybridLegacy
            ? 'legacy гибрид'
            : 'direct-only';
    _status = _status.copyWith(
      state: TunnelState.connecting,
      statusText: 'Fallback на $fallbackLabel…',
      errorMessage: '',
      errorCode: '',
      stage: 'allowlisted_ingress_fallback',
    );
    notifyListeners();
    return _prepareOfflineDeblockRuntimeBundle(fallbackBundle);
  }

  Future<DeblockerRuntimeBundle> _prepareLegacyWarpHybridRuntimeBundle(
    DeblockerRuntimeBundle runtimeBundle,
  ) async {
    final settings = runtimeBundle.settings;
    if (!runtimeBundle.requiresLegacyWarpProvisioning ||
        settings.hasWarpWireguardConfig) {
      _deblockerRuntimeBundle = runtimeBundle;
      await _savePrefs();
      return runtimeBundle;
    }

    _status = _status.copyWith(
      state: TunnelState.connecting,
      statusText: 'Подготавливаем legacy Cloudflare WARP…',
      errorMessage: '',
      errorCode: '',
      stage: 'legacy_warp_prepare',
    );
    notifyListeners();

    try {
      final provisioned = await _cloudflareWarpService.provisionSettings(
        settings,
        deviceModel:
            Platform.isAndroid ? 'Hex Decensor Android' : 'Hex Decensor',
      );

      switch (_offlineDeblockProfile) {
        case OfflineDeblockProfile.hybrid:
          _offlineDeblockHybridSettings = provisioned;
          break;
        case OfflineDeblockProfile.custom:
          _offlineDeblockCustomSettings = provisioned;
          break;
        case OfflineDeblockProfile.soft:
        case OfflineDeblockProfile.balanced:
        case OfflineDeblockProfile.aggressive:
        case OfflineDeblockProfile.ultra:
          break;
      }

      final preparedBundle = runtimeBundle.copyWith(
        settings: provisioned,
        createdAt: DateTime.now().toUtc().toIso8601String(),
      );
      _deblockerRuntimeBundle = preparedBundle;
      await _savePrefs();
      notifyListeners();
      return preparedBundle;
    } catch (e) {
      throw Exception('Не удалось подготовить legacy Cloudflare WARP: $e');
    }
  }

  Future<void> _bootstrapCachedIngressBundle({bool notify = false}) async {
    final result = _deblockerIngressBundleService.bootstrap(
      cachedBundle: _cachedIngressRuntimeBundle,
      profilePreset: _offlineDeblockProfile,
      settings: effectiveOfflineDeblockSettings,
    );
    if (result.didChange) {
      _cachedIngressRuntimeBundle = result.bundle;
      debugPrint(
        'TunnelProvider: ingress bundle bootstrap source=${result.source} '
        'version=${result.bundle.bundleVersion} '
        'freshness=${result.bundle.freshness.key} '
        'edge=${result.bundle.ingressConfig?.edgeHost ?? '-'} '
        'integrity=${result.integrity.status.name}'
        '${result.fallbackReason == null ? '' : ' fallback=${result.fallbackReason}'}',
      );
      await _savePrefs();
      if (notify) {
        notifyListeners();
      }
    }

    if (_deblockerIngressBundleService.shouldRefreshFromControlPlane(
      _cachedIngressRuntimeBundle,
    )) {
      unawaited(_refreshIngressBundleIfNeeded());
    }
  }

  Future<void> _refreshIngressBundleIfNeeded({
    BuildContext? context,
    bool silent = true,
    bool force = false,
  }) async {
    final ongoingRefresh = _ongoingIngressBundleRefresh;
    if (ongoingRefresh != null) {
      await ongoingRefresh;
      return;
    }

    if (!_deblockerIngressBundleService.shouldRefreshFromControlPlane(
      _cachedIngressRuntimeBundle,
      force: force,
    )) {
      return;
    }

    final completer = Completer<void>();
    _ongoingIngressBundleRefresh = completer.future;
    _isRefreshingIngressBundle = true;
    _ingressBundleRefreshError = null;
    notifyListeners();

    try {
      final result =
          await _deblockerIngressBundleService.refreshFromControlPlane(
        cachedBundle: _cachedIngressRuntimeBundle,
        profilePreset: _offlineDeblockProfile,
        settings: effectiveOfflineDeblockSettings,
      );

      if (result.isSuccess && result.bundle != null) {
        _cachedIngressRuntimeBundle = result.bundle;
        _ingressBundleRefreshError = null;
        debugPrint(
          'TunnelProvider: ingress bundle refreshed source=${result.source ?? '-'} '
          'version=${result.bundle!.bundleVersion} '
          'freshness=${result.bundle!.freshness.key} '
          'edge=${result.bundle!.ingressConfig?.edgeHost ?? '-'} '
          'changed=${result.didChange}',
        );
        await _savePrefs();

        if (!silent && context != null && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                result.didChange
                    ? 'Ingress bundle обновлён из control plane.'
                    : 'Ingress bundle уже актуален.',
              ),
            ),
          );
        }
      } else {
        _ingressBundleRefreshError = result.failureReason;
        debugPrint(
          'TunnelProvider: ingress bundle refresh failed '
          'reason=${result.failureReason ?? 'unknown'}',
        );
        if (!silent && context != null && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Не удалось обновить ingress bundle: '
                '${result.failureReason ?? 'unknown error'}',
              ),
            ),
          );
        }
      }
    } catch (e) {
      _ingressBundleRefreshError = '$e';
      debugPrint('TunnelProvider: ingress bundle refresh exception=$e');
      if (!silent && context != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка обновления ingress bundle: $e'),
          ),
        );
      }
    } finally {
      _isRefreshingIngressBundle = false;
      _ongoingIngressBundleRefresh = null;
      if (!completer.isCompleted) {
        completer.complete();
      }
      notifyListeners();
    }
  }

  Future<ProxyProfile?> _pickReachableProfile(ProxyProfile preferred) async {
    // Manual profile mode keeps explicit user choice, no auto-fallback.
    if (_useManualProfile) {
      final latency =
          await _singbox.testLatency(preferred.server, preferred.port);
      if (latency < 0) {
        _lastPreflightFailedOffline =
            !await _singbox.hasBaselineConnectivity();
      } else {
        _lastPreflightFailedOffline = false;
      }
      return latency >= 0 ? preferred : null;
    }

    // If user explicitly selected an auto key, honor it first.
    final explicitlySelected = _selectedAutoRawUri != null &&
        _selectedAutoRawUri!.isNotEmpty &&
        preferred.rawUri == _selectedAutoRawUri;
    if (explicitlySelected) {
      final latency =
          await _singbox.testLatency(preferred.server, preferred.port);
      if (latency >= 0) {
        _lastPreflightFailedOffline = false;
        final selected = _findAutoProfileByRawUri(preferred.rawUri);
        if (selected != null) {
          _syncHomeSelectionToProfile(selected);
        }
        return preferred;
      }
      _lastPreflightFailedOffline = !await _singbox.hasBaselineConnectivity();
    }

    final picked = await _pickReachableAutoProfileForCurrentSelection(
      allowCountryFallback: true,
      allowRussiaReload: true,
    );
    return picked?.profile;
  }

  List<ProxyProfile> _buildCoreUrltestCandidatePool(ProxyProfile primary) {
    final result = <ProxyProfile>[];
    final seen = <String>{};

    void addProfile(ProxyProfile p) {
      final key = p.rawUri.isNotEmpty
          ? p.rawUri
          : '${p.protocol}|${p.server}|${p.port}|${p.transport}|${p.sni}';
      if (!seen.add(key)) return;
      result.add(p);
    }

    addProfile(primary);

    if (_useManualProfile) {
      return result;
    }

    final scopeCandidates = switch (_homeSelectionScope) {
      AutoSelectionScope.allCountries => _profilesForScope(
          AutoSelectionScope.allCountries,
          countryCode: _selectedAllCountryCode,
        ),
      AutoSelectionScope.whiteList => _profilesForScope(
          AutoSelectionScope.whiteList,
          countryCode: _selectedWhiteListCountryCode,
        ),
      AutoSelectionScope.russia => _profilesForRussiaScope(),
    };

    for (final candidate in _sortProfilesByStability(scopeCandidates)) {
      if (_isInCooldown(candidate.profile)) {
        continue;
      }
      addProfile(candidate.profile);
      if (result.length >= _coreUrltestPoolSize) {
        break;
      }
    }

    return result;
  }

  Future<AutoProfile?> _pickReachableAutoProfileForCurrentSelection({
    required bool allowCountryFallback,
    required bool allowRussiaReload,
  }) async {
    switch (_homeSelectionScope) {
      case AutoSelectionScope.allCountries:
        return _pickReachableForCountryScope(
          scope: AutoSelectionScope.allCountries,
          preferredCountryCode: _selectedAllCountryCode,
          allowCountryFallback: allowCountryFallback,
        );
      case AutoSelectionScope.whiteList:
        return _pickReachableForCountryScope(
          scope: AutoSelectionScope.whiteList,
          preferredCountryCode: _selectedWhiteListCountryCode,
          allowCountryFallback: allowCountryFallback,
        );
      case AutoSelectionScope.russia:
        return _pickReachableForRussiaScope(
          allowRussiaReload: allowRussiaReload,
        );
    }
  }

  Future<AutoProfile?> _pickReachableForCountryScope({
    required AutoSelectionScope scope,
    required String? preferredCountryCode,
    required bool allowCountryFallback,
  }) async {
    final normalizedCountry = _normalizeCountryCode(preferredCountryCode);
    if (normalizedCountry != null) {
      final preferred = await _probeProfilesUntilReachable(
        _profilesForScope(scope, countryCode: normalizedCountry),
      );
      if (preferred != null) {
        _applyScopeSelection(scope, normalizedCountry, preferred);
        return preferred;
      }
    }

    if (!allowCountryFallback) {
      return null;
    }

    final fallbackCountry = _bestCountryCodeForScope(
      scope,
      excluding:
          normalizedCountry == null ? const <String>{} : {normalizedCountry},
    );
    if (fallbackCountry == null) {
      return null;
    }

    final fallback = await _probeProfilesUntilReachable(
      _profilesForScope(scope, countryCode: fallbackCountry),
    );
    if (fallback == null) {
      return null;
    }

    final previousName = normalizedCountry == null
        ? 'выбранной страны'
        : _countryDisplayName(normalizedCountry);
    _selectionNotice =
        'Ключи для $previousName закончились. Переключились на наиболее стабильную страну: ${_countryDisplayName(fallbackCountry)}.';
    _applyScopeSelection(scope, fallbackCountry, fallback);
    return fallback;
  }

  Future<AutoProfile?> _pickReachableForRussiaScope({
    required bool allowRussiaReload,
  }) async {
    final ru = await _probeProfilesUntilReachable(
      _profilesForRussiaScope(),
    );
    if (ru != null) {
      _selectionNotice = '';
      _applyScopeSelection(AutoSelectionScope.russia, 'RU', ru);
      return ru;
    }

    final by = await _probeProfilesUntilReachable(
      _profilesForExactCountry('BY'),
    );
    if (by != null) {
      _selectionNotice =
          'Российские ключи закончились. Переключились на Беларусь как на ближайший доступный вариант.';
      _applyScopeSelection(AutoSelectionScope.russia, 'RU', by);
      return by;
    }

    if (!allowRussiaReload) {
      return null;
    }

    _status = _status.copyWith(
      state: TunnelState.connecting,
      statusText: 'Обновляем российские ключи…',
      stage: 'refresh_ru',
    );
    notifyListeners();

    await refreshKeys(
      null,
      silent: true,
      allowReserveSources: true,
    );

    final reloadedRu = await _probeProfilesUntilReachable(
      _profilesForExactCountry('RU'),
    );
    if (reloadedRu != null) {
      _selectionNotice = 'Загружены новые российские ключи.';
      _applyScopeSelection(AutoSelectionScope.russia, 'RU', reloadedRu);
      return reloadedRu;
    }

    return null;
  }

  Future<AutoProfile?> _probeProfilesUntilReachable(
    List<AutoProfile> candidates,
  ) async {
    final failedProfiles = <ProxyProfile>[];
    // Gov-забаненные ключи исключаем полностью — они непригодны для RU-региона.
    final ordered = _sortProfilesByStability(
      candidates.where((c) => !_isGovFailedKey(c.profile)).toList(),
    );
    final regular = ordered
        .where((c) =>
            !_isInCooldown(c.profile) &&
            !_shouldAvoidProfileByReputation(c.profile))
        .toList();
    final avoidable = ordered
        .where((c) =>
            !_isInCooldown(c.profile) &&
            _shouldAvoidProfileByReputation(c.profile))
        .toList();
    final cooledDown = ordered.where((c) => _isInCooldown(c.profile)).toList();

    for (final candidate in regular) {
      final latency = await _singbox.testLatency(
          candidate.profile.server, candidate.profile.port);
      if (latency >= 0) {
        _lastPreflightFailedOffline = false;
        for (final failed in failedProfiles) {
          _markKeyFailure(failed);
        }
        candidate.latencyMs = latency;
        _markKeySuccess(candidate.profile);
        _setSelectedAutoProfile(candidate);
        return candidate;
      }
      candidate.latencyMs = -1;
      failedProfiles.add(candidate.profile);
    }

    // Ключи с плохой репутацией пробуем только после обычных кандидатов.
    for (final candidate in avoidable) {
      final latency = await _singbox.testLatency(
          candidate.profile.server, candidate.profile.port);
      if (latency >= 0) {
        _lastPreflightFailedOffline = false;
        for (final failed in failedProfiles) {
          _markKeyFailure(failed);
        }
        candidate.latencyMs = latency;
        _markKeySuccess(candidate.profile);
        _setSelectedAutoProfile(candidate);
        return candidate;
      }
      candidate.latencyMs = -1;
      failedProfiles.add(candidate.profile);
    }

    // Если все кандидаты в cooldown, пробуем их как последний шанс.
    for (final candidate in cooledDown) {
      final latency = await _singbox.testLatency(
          candidate.profile.server, candidate.profile.port);
      if (latency >= 0) {
        _lastPreflightFailedOffline = false;
        for (final failed in failedProfiles) {
          _markKeyFailure(failed);
        }
        candidate.latencyMs = latency;
        _markKeySuccess(candidate.profile);
        _setSelectedAutoProfile(candidate);
        return candidate;
      }
      candidate.latencyMs = -1;
      failedProfiles.add(candidate.profile);
    }

    final hasConnectivity = await _singbox.hasBaselineConnectivity();
    if (!hasConnectivity) {
      _lastPreflightFailedOffline = true;
      debugPrint(
        'TunnelProvider: preflight failed while device appears offline; '
        'skip key penalties',
      );
      return null;
    }

    _lastPreflightFailedOffline = false;
    for (final failed in failedProfiles) {
      _markKeyFailure(failed);
    }
    return null;
  }

  List<AutoProfile> _sortProfilesByStability(Iterable<AutoProfile> profiles) {
    final list = profiles.toList(growable: false);
    final nameCache = <String, String>{};
    String cachedName(String code) =>
        nameCache.putIfAbsent(code, () => _countryDisplayName(code));
    list.sort((a, b) {
      final byScore = _profileScore(a).compareTo(_profileScore(b));
      if (byScore != 0) return byScore;

      final byCountry =
          cachedName(a.countryCode).compareTo(cachedName(b.countryCode));
      if (byCountry != 0) return byCountry;

      return a.profile.server.compareTo(b.profile.server);
    });
    return list;
  }

  int _profileScore(AutoProfile profile) {
    _evictExpiredCrossBorderPressure();
    final successes = _successCounts[profile.countryCode] ?? 0;
    final historyBonus = (successes ~/ 3) * 50;
    final uri = profile.profile.rawUri;
    final keySuccess = _keySuccessCounts[uri] ?? 0;
    final keyFailures = _keyFailureCounts[uri] ?? 0;
    final keyBonus = keySuccess * 30;
    final keyPenalty = keyFailures * 40;
    final reputation = _profileReputationScore(profile.profile);
    final reputationBonus = (reputation - RelayReputation.defaultScore) * 14;
    final avoidPenalty = RelayReputation.shouldAvoid(reputation) ? 180000 : 0;
    final preferredBonus = RelayReputation.isPreferred(reputation) ? 350 : 0;
    final cooldownPenalty = _isInCooldown(profile.profile) ? 500000 : 0;
    final protocolBonus = _protocolPreferenceBonus(profile.profile);
    final adaptivePenalty = _adaptiveProfilePenalty(profile.profile);
    final crossBorderPressurePenalty = _crossBorderPressurePenalty(profile);
    final latency = profile.latencyMs >= 0 ? profile.latencyMs : 100000;
    return latency -
        historyBonus -
        keyBonus -
        reputationBonus -
        preferredBonus -
        protocolBonus +
        keyPenalty +
        avoidPenalty +
        cooldownPenalty +
        adaptivePenalty +
        crossBorderPressurePenalty;
  }

  int _crossBorderPressurePenalty(AutoProfile profile) {
    if (!_isCrossBorderPressureActive()) {
      return 0;
    }
    final code = _normalizeCountryCode(profile.countryCode);
    if (code == null) {
      return _crossBorderPressurePenaltyPerLevel * _crossBorderPressureLevel;
    }
    if (_isDomesticPriorityCountry(code)) {
      return -_crossBorderPressureDomesticBonusPerLevel *
          _crossBorderPressureLevel;
    }
    return _crossBorderPressurePenaltyPerLevel * _crossBorderPressureLevel;
  }

  bool _isDomesticPriorityCountry(String countryCode) {
    final code = _normalizeCountryCode(countryCode);
    return code == 'RU' || code == 'BY';
  }

  int _protocolPreferenceBonus(ProxyProfile profile) {
    if (profile.protocol == 'vless' && profile.reality) {
      return 220;
    }
    if (profile.protocol == 'vless') {
      return 80;
    }
    return 0;
  }

  List<AutoProfile> _profilesForScope(
    AutoSelectionScope scope, {
    String? countryCode,
  }) {
    final normalizedCountry = _normalizeCountryCode(countryCode);
    final source = switch (scope) {
      AutoSelectionScope.allCountries => _autoProfiles.where(
          (profile) => !_isRussiaProfile(profile),
        ),
      AutoSelectionScope.whiteList => _autoProfiles.where(
          (profile) =>
              profile.listType == KeyListType.whiteList &&
              !_isRussiaProfile(profile),
        ),
      AutoSelectionScope.russia => _profilesForRussiaScope(),
    };

    if (normalizedCountry == null) {
      return source.toList(growable: false);
    }

    return source
        .where((profile) =>
            _normalizeCountryCode(profile.countryCode) == normalizedCountry)
        .toList(growable: false);
  }

  List<AutoProfile> _profilesForRussiaScope() {
    final russianProfiles = _profilesForExactCountry('RU');
    if (_selectedRussiaListType == KeyListType.whiteList) {
      return russianProfiles
          .where((p) => p.listType == KeyListType.whiteList)
          .toList(growable: false);
    }
    return russianProfiles;
  }

  List<AutoProfile> _profilesForExactCountry(String countryCode) {
    final normalizedCountry = _normalizeCountryCode(countryCode);
    if (normalizedCountry == null) {
      return const <AutoProfile>[];
    }
    return _autoProfiles
        .where((profile) =>
            _normalizeCountryCode(profile.countryCode) == normalizedCountry)
        .toList(growable: false);
  }

  String? _bestCountryCodeForScope(
    AutoSelectionScope scope, {
    Set<String> excluding = const <String>{},
  }) {
    final countries = <String, List<AutoProfile>>{};
    for (final profile in _profilesForScope(scope)) {
      final country = _normalizeCountryCode(profile.countryCode);
      if (country == null || excluding.contains(country)) {
        continue;
      }
      countries.putIfAbsent(country, () => <AutoProfile>[]).add(profile);
    }

    String? bestCountry;
    int? bestScore;
    for (final entry in countries.entries) {
      final sorted = _sortProfilesByStability(entry.value);
      if (sorted.isEmpty) {
        continue;
      }
      final score = _profileScore(sorted.first);
      if (bestScore == null || score < bestScore) {
        bestScore = score;
        bestCountry = entry.key;
      }
    }
    return bestCountry;
  }

  bool _isRussiaProfile(AutoProfile profile) {
    final code = _normalizeCountryCode(profile.countryCode);
    return code == 'RU';
  }

  String? _normalizeCountryCode(String? countryCode) {
    if (countryCode == null) {
      return null;
    }
    final normalized = countryCode.trim().toUpperCase();
    if (normalized.isEmpty) {
      return null;
    }
    return normalized;
  }

  String _countryDisplayName(String countryCode) {
    final profile = _autoProfiles.cast<AutoProfile?>().firstWhere(
          (item) => _normalizeCountryCode(item?.countryCode) == countryCode,
          orElse: () => null,
        );
    if (profile == null) {
      return KeyLoaderService.toCyrillicCountryName(countryCode, countryCode);
    }
    return KeyLoaderService.toCyrillicCountryName(
      profile.countryCode,
      profile.countryName,
    );
  }

  String _notificationRegionLabelForProfile(ProxyProfile profile) {
    if (_connectionMode == AppConnectionMode.offlineDeblock) {
      return 'Локальный деблок';
    }

    final matchedAuto = _autoProfiles.cast<AutoProfile?>().firstWhere(
          (item) => item?.profile.rawUri == profile.rawUri,
          orElse: () => null,
        );
    if (matchedAuto != null) {
      final code = _normalizeCountryCode(matchedAuto.countryCode);
      if (code != null) {
        return _countryDisplayName(code);
      }
      final countryName = matchedAuto.countryName.trim();
      if (countryName.isNotEmpty) {
        return countryName;
      }
    }

    final selectedCode = _normalizeCountryCode(selectedHomeCountryCode);
    if (selectedCode != null) {
      return _countryDisplayName(selectedCode);
    }

    return 'Не определен';
  }

  void _applyScopeSelection(
    AutoSelectionScope scope,
    String countryCode,
    AutoProfile profile,
  ) {
    _homeSelectionScope = scope;
    switch (scope) {
      case AutoSelectionScope.allCountries:
        _selectedAllCountryCode = countryCode;
      case AutoSelectionScope.whiteList:
        _selectedWhiteListCountryCode = countryCode;
      case AutoSelectionScope.russia:
        break;
    }
    _setSelectedAutoProfile(profile);
  }

  void _setSelectedAutoProfile(AutoProfile profile) {
    _selectedAutoRawUri = profile.profile.rawUri;
    _syncSelectedAutoIndex();
  }

  void _syncSelectedAutoIndex() {
    if (_selectedAutoRawUri == null || _selectedAutoRawUri!.isEmpty) {
      _normalizeSelectedAutoIndex();
      return;
    }
    final visible = _filteredAutoProfiles;
    final idx =
        visible.indexWhere((ap) => ap.profile.rawUri == _selectedAutoRawUri);
    if (idx >= 0) {
      _selectedAutoIndex = idx;
      return;
    }
    if (visible.isEmpty) {
      _selectedAutoIndex = 0;
      return;
    }
    _selectedAutoIndex = 0;
  }

  String _platformErrorToText(PlatformException e) {
    switch (e.code) {
      case 'VPN_PERMISSION_DENIED':
        return 'Разрешение VPN отклонено';
      case 'METHOD_CHANNEL_TIMEOUT':
        return 'Таймаут запуска туннеля';
      default:
        return e.message?.trim().isNotEmpty == true
            ? e.message!
            : 'Ошибка запуска (${e.code})';
    }
  }

  String _fallbackErrorText(String code, String stage) {
    if (code.isNotEmpty) {
      return 'Ошибка [$code] на этапе ${stage.isEmpty ? 'unknown' : stage}';
    }
    return 'Неизвестная ошибка подключения';
  }

  String _noReachableServerMessage({bool afterProbe = false}) {
    if (_lastPreflightFailedOffline) {
      return 'Похоже, устройство сейчас без интернета. Проверьте Wi-Fi/мобильную сеть и повторите попытку.';
    }
    if (_homeSelectionScope == AutoSelectionScope.russia) {
      return 'Железный занавес опустился, ничем не помогу';
    }
    if (afterProbe) {
      return 'Нет доступных серверов после проверки внешнего интернета. Выберите другую страну или обновите ключи.';
    }
    return 'Нет доступных серверов. Обновите ключи или выберите другую страну.';
  }

  ProxyProfile? _pickDefaultProfileForQuickConnect() {
    final isLikelyInRussia = _isLikelyUserInRussia();

    if (isLikelyInRussia) {
      final bestOutsideRussia = _sortProfilesByStability(
        _profilesForScope(AutoSelectionScope.allCountries),
      );
      if (bestOutsideRussia.isNotEmpty) {
        final profile = bestOutsideRussia.first;
        final code = _normalizeCountryCode(profile.countryCode);
        if (code != null) {
          _applyScopeSelection(AutoSelectionScope.allCountries, code, profile);
        } else {
          _setSelectedAutoProfile(profile);
        }
        return profile.profile;
      }
    } else {
      final bestRussia = _sortProfilesByStability(_profilesForRussiaScope());
      if (bestRussia.isNotEmpty) {
        final profile = bestRussia.first;
        _applyScopeSelection(AutoSelectionScope.russia, 'RU', profile);
        return profile.profile;
      }

      final bestRussiaFallback =
          _sortProfilesByStability(_profilesForExactCountry('RU'));
      if (bestRussiaFallback.isNotEmpty) {
        final profile = bestRussiaFallback.first;
        _applyScopeSelection(AutoSelectionScope.russia, 'RU', profile);
        return profile.profile;
      }
    }

    final bestAny = _bestProfileForCurrentSelection();
    if (bestAny == null) {
      return null;
    }
    _setSelectedAutoProfile(bestAny);
    return bestAny.profile;
  }

  bool _isLikelyUserInRussia() {
    final locale = WidgetsBinding.instance.platformDispatcher.locale;
    final countryCode = locale.countryCode?.trim().toUpperCase();
    if (countryCode == 'RU') {
      return true;
    }

    final languageCode = locale.languageCode.trim().toLowerCase();
    return countryCode == null && languageCode == 'ru';
  }

  Future<void> _stop() async {
    _autoReconnectInProgress = false;
    _stopRuntimeHealthMonitor();
    _cancelNetworkChangeHealthCheck(resetEventId: true);
    try {
      await _singbox.stop();
    } catch (e, st) {
      debugPrint('TunnelProvider._stop error: $e\n$st');
    }
    _status = TunnelStatus(routingMode: _routingMode);
    notifyListeners();
  }

  // ── Profile selection ─────────────────────────────────────────────────────

  void selectAutoProfile(int index) {
    final visible = _filteredAutoProfiles;
    if (index < 0 || index >= visible.length) return;
    final selected = visible[index];
    _selectedAutoIndex = index;
    _selectedAutoRawUri = selected.profile.rawUri;
    _useManualProfile = false;
    _selectedManualProfile = null;
    _syncHomeSelectionToProfile(selected);
    _savePrefs();
    notifyListeners();
  }

  void selectManualProfile(ProxyProfile profile) {
    _selectedManualProfile = profile;
    _useManualProfile = true;
    _deferredManualProfileRawUri = null;
    _selectionNotice = '';
    _savePrefs();
    notifyListeners();
  }

  // ── Manual profiles ───────────────────────────────────────────────────────

  /// Добавить профиль из URI-ссылки.
  /// Возвращает null в случае успеха или текст ошибки.
  String? addManualProfile(String uri) {
    if (!UriParser.isSupported(uri)) {
      return 'Неподдерживаемый протокол. Используйте vless://, ss://, trojan://, tuic://';
    }
    final profile = UriParser.parse(uri);
    if (!profile.isValid) {
      return 'Некорректная ссылка. Проверьте формат URI.';
    }
    // Не добавлять дубликаты
    if (_manualProfiles.any((p) => p.rawUri == profile.rawUri)) {
      return 'Этот сервер уже добавлен.';
    }
    _manualProfiles.add(profile);
    _savePrefs();
    notifyListeners();
    return null;
  }

  void removeManualProfile(ProxyProfile profile) {
    _manualProfiles.removeWhere((p) => p.rawUri == profile.rawUri);
    if (_selectedManualProfile?.rawUri == profile.rawUri) {
      _selectedManualProfile = null;
      _useManualProfile = false;
    }
    _savePrefs();
    notifyListeners();
  }

  /// Измерить задержку до сервера и обновить AutoProfile в списке.
  Future<void> testLatency(ProxyProfile profile) async {
    final ms = await _singbox.testLatency(profile.server, profile.port);
    final idx =
        _autoProfiles.indexWhere((ap) => ap.profile.rawUri == profile.rawUri);
    if (idx != -1) {
      _autoProfiles[idx].latencyMs = ms;
      notifyListeners();
    }
  }

  // ── Keys loading ──────────────────────────────────────────────────────────

  /// Фоновая QoS-проверка задержек для топ-профилей.
  /// Зондирует не более [_maxProbeTargets] кандидатов с конкурентностью 4,
  /// чтобы не перегружать сеть и UI флагманского устройства.
  /// Уведомляет UI батчами — не чаще раза в 300 мс.
  static const int _maxProbeTargets = 100;
  Future<void> probeInBackground() async {
    if (_isProbing || _autoProfiles.isEmpty) return;
    _isProbing = true;
    notifyListeners();
    try {
      final all = _filteredAutoProfiles;
      final targets = all.length > _maxProbeTargets
          ? all.sublist(0, _maxProbeTargets)
          : List<AutoProfile>.from(all);

      // Батчевые обновления UI: максимум раз в 300 мс
      var lastNotify = DateTime.now();
      await KeyLoaderService.probeProfilesInBackground(
        targets,
        concurrency: 4,
        onResult: (_) {
          final now = DateTime.now();
          if (now.difference(lastNotify).inMilliseconds >= 300) {
            lastNotify = now;
            notifyListeners();
          }
        },
      );
      _selectFastest();
    } finally {
      _isProbing = false;
      notifyListeners();
    }
  }

  /// Выбрать профиль с наименьшей задержкой среди доступных (latencyMs >= 0).
  /// Профили из стран с историей успешных подключений получают бонус -50 мс
  /// на каждые 3 успеха (гео-оптимизация).
  void _selectFastest() {
    final best = _bestProfileForCurrentSelection();
    if (best == null) {
      return;
    }
    if (_selectedAutoRawUri != best.profile.rawUri) {
      _setSelectedAutoProfile(best);
      unawaited(_savePrefs());
      notifyListeners();
    }
  }

  AutoProfile? _bestProfileForCurrentSelection() {
    if (_autoProfiles.isEmpty) {
      return null;
    }
    switch (_homeSelectionScope) {
      case AutoSelectionScope.allCountries:
        final country = _selectedAllCountryCode ??
            _bestCountryCodeForScope(AutoSelectionScope.allCountries);
        if (country == null) {
          return null;
        }
        final profiles = _sortProfilesByStability(
          _profilesForScope(
            AutoSelectionScope.allCountries,
            countryCode: country,
          ),
        );
        return profiles.isEmpty ? null : profiles.first;
      case AutoSelectionScope.whiteList:
        final country = _selectedWhiteListCountryCode ??
            _bestCountryCodeForScope(AutoSelectionScope.whiteList);
        if (country == null) {
          return null;
        }
        final profiles = _sortProfilesByStability(
          _profilesForScope(
            AutoSelectionScope.whiteList,
            countryCode: country,
          ),
        );
        return profiles.isEmpty ? null : profiles.first;
      case AutoSelectionScope.russia:
        final ruProfiles =
            _sortProfilesByStability(_profilesForExactCountry('RU'));
        if (ruProfiles.isNotEmpty) {
          return ruProfiles.first;
        }
        final byProfiles =
            _sortProfilesByStability(_profilesForExactCountry('BY'));
        return byProfiles.isEmpty ? null : byProfiles.first;
    }
  }

  /// Зафиксировать успешное подключение для текущего активного профиля.
  void _recordSuccessfulConnection() {
    if (_useManualProfile) return;
    final current = activeAutoProfile;
    if (current == null) return;
    final countryCode = current.countryCode;
    _successCounts[countryCode] = (_successCounts[countryCode] ?? 0) + 1;
    _markKeySuccess(current.profile);
    unawaited(_savePrefs());
  }

  bool _isInCooldown(ProxyProfile profile) {
    final until = _keyCooldownUntilMs[profile.rawUri] ?? 0;
    if (until <= 0) return false;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (until <= now) {
      _keyCooldownUntilMs.remove(profile.rawUri);
      return false;
    }
    return true;
  }

  AdaptiveTunnelPolicyState _currentAdaptivePolicyState() {
    return AdaptiveTunnelPolicyState(
      transportCooldownUntilMs:
          Map<String, int>.from(_adaptiveTransportCooldownUntilMs),
      fingerprintCooldownUntilMs:
          Map<String, int>.from(_adaptiveFingerprintCooldownUntilMs),
      preferredTransportByEnv:
          Map<String, String>.from(_adaptivePreferredTransportByEnv),
      preferredFingerprintByEnv:
          Map<String, String>.from(_adaptivePreferredFingerprintByEnv),
      mitigationNote: _adaptiveMitigationNote,
    );
  }

  void _applyAdaptivePolicyState(
    AdaptiveTunnelPolicyState state, {
    bool persist = false,
  }) {
    _adaptiveTransportCooldownUntilMs
      ..clear()
      ..addAll(state.transportCooldownUntilMs);
    _adaptiveFingerprintCooldownUntilMs
      ..clear()
      ..addAll(state.fingerprintCooldownUntilMs);
    _adaptivePreferredTransportByEnv
      ..clear()
      ..addAll(state.preferredTransportByEnv);
    _adaptivePreferredFingerprintByEnv
      ..clear()
      ..addAll(state.preferredFingerprintByEnv);
    _adaptiveMitigationNote = state.mitigationNote;
    if (persist) {
      unawaited(_savePrefs());
    }
  }

  AdaptiveProfileDescriptor _adaptiveDescriptorForProfile(
      ProxyProfile profile) {
    return AdaptiveProfileDescriptor(
      protocol: profile.protocol,
      transport: profile.transport,
      fingerprint: profile.fingerprint,
      tlsEnabled: profile.tls,
      supportsTransportFallback: _supportsSilentWsFallback(profile),
    );
  }

  int _adaptiveProfilePenalty(ProxyProfile profile) {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final state = AdaptiveTunnelPolicy.evictExpired(
      _currentAdaptivePolicyState(),
      nowMs: nowMs,
    );
    _applyAdaptivePolicyState(state);
    return AdaptiveTunnelPolicy.profilePenalty(
      state,
      _adaptiveDescriptorForProfile(profile),
      nowMs: nowMs,
    );
  }

  ProxyProfile _materializeAdaptiveTunnelProfile(ProxyProfile profile) {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final result = AdaptiveTunnelPolicy.materialize(
      _currentAdaptivePolicyState(),
      _adaptiveDescriptorForProfile(profile),
      environmentKey: _adaptiveEnvironmentKey(),
      nowMs: nowMs,
      fingerprintSpoofingEnabled: _tunnelTlsFingerprintSpoofing,
    );
    _applyAdaptivePolicyState(result.state);

    var effective = profile;
    if (result.transport != null && result.transport != effective.transport) {
      effective = effective.copyWith(transport: result.transport!);
    }
    if (result.fingerprint != null &&
        result.fingerprint != effective.fingerprint) {
      effective = effective.copyWith(fingerprint: result.fingerprint!);
    }
    return effective;
  }

  void _markAdaptiveTunnelFailure(
    ProxyProfile? profile, {
    required String reason,
  }) {
    if (profile == null) {
      return;
    }
    final state = AdaptiveTunnelPolicy.markFailure(
      _currentAdaptivePolicyState(),
      _adaptiveDescriptorForProfile(profile),
      environmentKey: _adaptiveEnvironmentKey(),
      reason: reason,
      nowMs: DateTime.now().millisecondsSinceEpoch,
      fingerprintSpoofingEnabled: _tunnelTlsFingerprintSpoofing,
    );
    _applyAdaptivePolicyState(state, persist: true);
  }

  bool _isCrossBorderPressureActive() {
    _evictExpiredCrossBorderPressure();
    return _crossBorderPressureLevel > 0;
  }

  void _recordCrossBorderPressureSignal({required String reason}) {
    _evictExpiredCrossBorderPressure();
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final nextLevel =
        (_crossBorderPressureLevel + 1).clamp(1, _crossBorderPressureMaxLevel);
    _crossBorderPressureLevel = nextLevel;

    final holdMinutes = switch (nextLevel) {
      1 => 5,
      2 => 15,
      _ => 30,
    };
    _crossBorderPressureUntilMs =
        nowMs + Duration(minutes: holdMinutes).inMilliseconds;

    if (_adaptiveMitigationNote.trim().isEmpty ||
        _adaptiveMitigationNote.contains('перегрузка внешних каналов')) {
      _adaptiveMitigationNote =
          'перегрузка внешних каналов: уровень $nextLevel ($reason)';
    }
    unawaited(_savePrefs());
  }

  void setAntiCrisisMode(bool enabled) {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    _antiCrisisMode = enabled;
    if (enabled) {
      _crossBorderPressureLevel = _crossBorderPressureMaxLevel;
      _crossBorderPressureUntilMs =
          nowMs + const Duration(hours: 24).inMilliseconds;
      _adaptiveMitigationNote =
          'перегрузка внешних каналов: уровень $_crossBorderPressureMaxLevel (manual_anti_crisis)';
    } else {
      _crossBorderPressureLevel = 0;
      _crossBorderPressureUntilMs = 0;
      _runtimeHealthProbeSkipCounter = 0;
      if (_adaptiveMitigationNote.contains('перегрузка внешних каналов')) {
        _adaptiveMitigationNote = '';
      }
    }
    unawaited(_savePrefs());
    notifyListeners();
  }

  void _relaxCrossBorderPressureOnSuccess() {
    if (_crossBorderPressureLevel <= 0 || _antiCrisisMode) {
      return;
    }
    _crossBorderPressureLevel -= 1;
    if (_crossBorderPressureLevel <= 0) {
      _crossBorderPressureLevel = 0;
      _crossBorderPressureUntilMs = 0;
      _runtimeHealthProbeSkipCounter = 0;
      if (_adaptiveMitigationNote.contains('перегрузка внешних каналов')) {
        _adaptiveMitigationNote = '';
      }
    }
    unawaited(_savePrefs());
  }

  void _evictExpiredCrossBorderPressure() {
    if (_crossBorderPressureLevel <= 0 || _crossBorderPressureUntilMs <= 0) {
      return;
    }
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    if (_crossBorderPressureUntilMs > nowMs) {
      return;
    }
    if (_antiCrisisMode) {
      _crossBorderPressureLevel = _crossBorderPressureMaxLevel;
      _crossBorderPressureUntilMs =
          nowMs + const Duration(hours: 24).inMilliseconds;
      return;
    }
    _crossBorderPressureLevel = 0;
    _crossBorderPressureUntilMs = 0;
    _runtimeHealthProbeSkipCounter = 0;
    if (_adaptiveMitigationNote.contains('перегрузка внешних каналов')) {
      _adaptiveMitigationNote = '';
    }
  }

  void _markAdaptiveTunnelSuccess(ProxyProfile? profile) {
    if (profile == null) {
      return;
    }
    final state = AdaptiveTunnelPolicy.markSuccess(
      _currentAdaptivePolicyState(),
      _adaptiveDescriptorForProfile(profile),
      environmentKey: _adaptiveEnvironmentKey(),
      nowMs: DateTime.now().millisecondsSinceEpoch,
      fingerprintSpoofingEnabled: _tunnelTlsFingerprintSpoofing,
    );
    _applyAdaptivePolicyState(state, persist: true);
  }

  void _evictExpiredAdaptiveCooldowns() {
    final state = AdaptiveTunnelPolicy.evictExpired(
      _currentAdaptivePolicyState(),
      nowMs: DateTime.now().millisecondsSinceEpoch,
    );
    _applyAdaptivePolicyState(state);
  }

  String _adaptiveEnvironmentKey([TunnelStatus? snapshot]) {
    final status = snapshot ?? _status;
    return AdaptiveTunnelPolicy.normalizeEnvironment(
      networkTransport: status.networkTransport,
      networkInterface: status.networkInterface,
      operatorHint: status.networkOperator,
    );
  }

  int _adaptiveEnvironmentStrategyCount() {
    return AdaptiveTunnelPolicy.environmentStrategyCount(
      _currentAdaptivePolicyState(),
    );
  }

  void _markActiveKeyFailure() {
    if (_useManualProfile) {
      final manual = _selectedManualProfile;
      if (manual != null) {
        _markKeyFailure(manual);
      }
      return;
    }
    final auto = activeAutoProfile;
    if (auto != null) {
      _markKeyFailure(auto.profile);
    }
  }

  /// Помечает активный ключ как постоянно непригодный для RU-региона
  /// (gov-проба провалилась). Такой ключ никогда больше не выбирается.
  void _markActiveKeyGovFailed() {
    if (_useManualProfile) {
      final manual = _selectedManualProfile;
      if (manual != null && manual.rawUri.isNotEmpty) {
        _govFailedKeys.add(manual.rawUri);
        _markKeyFailure(manual);
      }
      unawaited(_savePrefs());
      return;
    }
    final auto = activeAutoProfile;
    if (auto != null && auto.profile.rawUri.isNotEmpty) {
      _govFailedKeys.add(auto.profile.rawUri);
      _markKeyFailure(auto.profile);
    }
    unawaited(_savePrefs());
  }

  bool _isGovFailedKey(ProxyProfile profile) {
    return profile.rawUri.isNotEmpty &&
        _govFailedKeys.contains(profile.rawUri);
  }

  void _markKeySuccess(ProxyProfile profile) {
    final key = profile.rawUri;
    if (key.isEmpty) return;

    final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final decayed = _updateReputationWithDecay(key, nowSec);
    _keyReputationScores[key] =
        RelayReputation.scoreAfterEvent(decayed, success: true);
    _keyReputationUpdatedAtSec[key] = nowSec;
    _keyConsecutiveFailures[key] = 0;

    _keySuccessCounts[key] = (_keySuccessCounts[key] ?? 0) + 1;
    final failures = (_keyFailureCounts[key] ?? 0) - 1;
    if (failures > 0) {
      _keyFailureCounts[key] = failures;
    } else {
      _keyFailureCounts.remove(key);
    }
    _keyCooldownUntilMs.remove(key);
    unawaited(_savePrefs());
  }

  void _markKeyFailure(ProxyProfile profile) {
    final key = profile.rawUri;
    if (key.isEmpty) return;

    final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final decayed = _updateReputationWithDecay(key, nowSec);
    _keyReputationScores[key] =
        RelayReputation.scoreAfterEvent(decayed, success: false);
    _keyReputationUpdatedAtSec[key] = nowSec;

    final consecutiveFailures = (_keyConsecutiveFailures[key] ?? 0) + 1;
    _keyConsecutiveFailures[key] = consecutiveFailures;

    final failures = (_keyFailureCounts[key] ?? 0) + 1;
    _keyFailureCounts[key] = failures;

    final until = DateTime.now()
        .add(_backoffDurationForFailures(consecutiveFailures))
        .millisecondsSinceEpoch;
    _keyCooldownUntilMs[key] = until;

    unawaited(_savePrefs());
  }

  int _profileReputationScore(ProxyProfile profile) {
    final key = profile.rawUri;
    if (key.isEmpty) {
      return RelayReputation.defaultScore;
    }
    return _effectiveReputationScore(key);
  }

  bool _shouldAvoidProfileByReputation(ProxyProfile profile) {
    return RelayReputation.shouldAvoid(_profileReputationScore(profile));
  }

  int _effectiveReputationScore(String key) {
    final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    return _updateReputationWithDecay(key, nowSec);
  }

  int _updateReputationWithDecay(String key, int nowSec) {
    final current = _keyReputationScores[key] ?? RelayReputation.defaultScore;
    final updatedAt = _keyReputationUpdatedAtSec[key] ?? nowSec;
    final elapsed = nowSec - updatedAt;
    final decayed = RelayReputation.applyDecay(current, elapsed);
    _keyReputationScores[key] = decayed;
    _keyReputationUpdatedAtSec[key] = nowSec;
    return decayed;
  }

  Duration _backoffDurationForFailures(int consecutiveFailures) {
    final failures = consecutiveFailures <= 0 ? 0 : consecutiveFailures;
    final shift = (failures - 1).clamp(0, 16);
    final rawSecs = 5 * (1 << shift);
    final cappedSecs = rawSecs > 300 ? 300 : rawSecs;
    return Duration(seconds: cappedSecs);
  }

  Future<void> refreshKeys(
    BuildContext? context, {
    bool silent = false,
    bool includeSupplemental = false,
    bool allowReserveSources = false,
  }) async {
    if (_isLoadingKeys) return;

    _isLoadingKeys = true;
    _loadingMessage = 'Загрузка ключей…';
    notifyListeners();

    try {
      final previousRawUri = _selectedAutoRawUri;
      final previousScope = _homeSelectionScope;
      final previousAllCountryCode = _selectedAllCountryCode;
      final previousWhiteListCountryCode = _selectedWhiteListCountryCode;
      await _refreshCustomSourceProfiles(onProgress: (msg) {
        _loadingMessage = msg;
        notifyListeners();
      });
      final profiles = await _keyLoader.fetchAll(
        includeSupplemental: includeSupplemental,
        allowReserveSources: allowReserveSources,
        onProgress: (msg) {
          _loadingMessage = msg;
          notifyListeners();
        },
      );

      if (profiles.isNotEmpty) {
        _autoProfiles = profiles;
        _restoreSelectionAfterRefresh(
          previousRawUri: previousRawUri,
          previousScope: previousScope,
          previousAllCountryCode: previousAllCountryCode,
          previousWhiteListCountryCode: previousWhiteListCountryCode,
        );
        await _cacheAutoProfiles();
        // Запускаем фоновое QoS-зондирование после загрузки
        unawaited(probeInBackground());
      }

      if (!silent && context != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              profiles.isNotEmpty
                  ? includeSupplemental
                      ? 'Загружено серверов: ${profiles.length} (с доп. источниками)'
                      : 'Загружено серверов: ${profiles.length} (основной режим)'
                  : 'Новых серверов не найдено. Используется текущий список.',
            ),
          ),
        );
      }
    } on KeyLoadException catch (e) {
      if (!silent && context != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message)),
        );
      }
    } catch (e) {
      if (!silent && context != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка загрузки: $e')),
        );
      }
    } finally {
      _isLoadingKeys = false;
      _loadingMessage = '';
      notifyListeners();
    }
  }

  // ── Settings ──────────────────────────────────────────────────────────────

  Future<void> setRoutingMode(RoutingMode mode) async {
    if (_routingMode == mode) return;
    _routingMode = mode;
    _status = _status.copyWith(routingMode: mode);
    await _savePrefs();
    notifyListeners();

    if (mode == RoutingMode.smart) {
      final String path = await const MethodChannel('hex_decensor/singbox').invokeMethod('getAppDir');
      final appDir = Directory(path);
      if (!_smartRoutingService.hasRuleSet(appDir.path)) {
        updateSmartRoutingDataset();
      } else if (_status.state == TunnelState.connected && _connectionMode == AppConnectionMode.tunnel) {
        await toggleConnection(null);
        await toggleConnection(null);
      }
    } else if (_status.state == TunnelState.connected && _connectionMode == AppConnectionMode.tunnel) {
      await toggleConnection(null);
      await toggleConnection(null);
    }
  }

  String? setRoutingRuntimePolicyFromJsonString(String rawJson) {
    final trimmed = rawJson.trim();
    if (trimmed.isEmpty) {
      _routingRuntimePolicy = const RoutingRuntimePolicy();
      unawaited(_savePrefs());
      notifyListeners();
      return null;
    }

    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is! Map<String, dynamic>) {
        return 'Ожидается JSON-объект routing policy';
      }
      _routingRuntimePolicy = RoutingRuntimePolicy.fromJson(decoded);
      unawaited(_savePrefs());
      notifyListeners();
      return null;
    } catch (e) {
      return 'Некорректный JSON routing policy: $e';
    }
  }

  Future<void> setConnectionMode(AppConnectionMode mode) async {
    if (_connectionMode == mode) return;

    final wasActive = _status.state.isActive || await _singbox.isRunning();
    if (wasActive) {
      await _stop();
    }

    _connectionMode = mode;
    _status = TunnelStatus(
      routingMode: _routingMode,
      statusText: '',
    );
    await _savePrefs();
    notifyListeners();
  }

  void setOfflineDeblockProfile(OfflineDeblockProfile profile) {
    if (_offlineDeblockProfile == profile) return;
    _offlineDeblockProfile = profile;
    _deblockerRuntimeBundle = null;
    _quarantinedIngressConfigs.clear();
    _ingressEdgeFailureCounts.clear();
    _ingressEdgeCooldownUntilMs.clear();
    _savePrefs();
    notifyListeners();
    unawaited(_bootstrapCachedIngressBundle(notify: true));

    if (isOfflineDeblockMode && _status.state.isActive) {
      unawaited(_reapplyOfflineDeblockProfile());
    }
  }

  void setStrictAllowlistModeEnabled(bool enabled) {
    if (_strictAllowlistModeEnabled == enabled) {
      return;
    }
    _strictAllowlistModeEnabled = enabled;
    _deblockerRuntimeBundle = null;
    _quarantinedIngressConfigs.clear();
    _ingressEdgeFailureCounts.clear();
    _ingressEdgeCooldownUntilMs.clear();
    _savePrefs();
    notifyListeners();
    unawaited(_bootstrapCachedIngressBundle(notify: true));
    if (enabled) {
      unawaited(_refreshIngressBundleIfNeeded(force: true));
    }

    if (isOfflineDeblockMode && _status.state.isActive) {
      unawaited(_reapplyOfflineDeblockProfile());
    }
  }

  Future<void> refreshIngressBundle(
    BuildContext? context, {
    bool silent = false,
    bool force = true,
  }) async {
    await _refreshIngressBundleIfNeeded(
      context: context,
      silent: silent,
      force: force,
    );
  }

  void setOfflineDeblockCustomSettings(OfflineDeblockSettings settings) {
    _offlineDeblockCustomSettings = settings;
    _deblockerRuntimeBundle = null;
    _quarantinedIngressConfigs.clear();
    _ingressEdgeFailureCounts.clear();
    _ingressEdgeCooldownUntilMs.clear();
    _savePrefs();
    notifyListeners();
    unawaited(_bootstrapCachedIngressBundle(notify: true));

    if (isOfflineDeblockMode &&
        _status.state.isActive &&
        _offlineDeblockProfile == OfflineDeblockProfile.custom) {
      unawaited(_reapplyOfflineDeblockProfile());
    }
  }

  Future<void> _reapplyOfflineDeblockProfile() async {
    if (_connectionMode != AppConnectionMode.offlineDeblock) return;

    _status = _status.copyWith(
      state: TunnelState.connecting,
      statusText:
          'Применяем профиль ${_offlineDeblockProfile.displayName.toLowerCase()}…',
      errorMessage: '',
      errorCode: '',
      stage: 'profile_change',
    );
    notifyListeners();

    try {
      await _singbox.stop();
    } catch (_) {}

    await _startOfflineDeblock();
  }

  void setKeyListType(KeyListType type) {
    _keyListType = type;
    _syncSelectedAutoIndex();
    _savePrefs();
    notifyListeners();
  }

  void setSplitTunnelingMode(SplitTunnelingMode mode) {
    _splitTunnelingMode = mode;
    _savePrefs();
    notifyListeners();
  }

  void setVpnBypassForPackage(String packageName, bool enabled) {
    final normalized = packageName.trim();
    if (normalized.isEmpty) {
      return;
    }

    if (enabled) {
      if (_splitTunnelingMode != SplitTunnelingMode.exceptSelected) {
        _splitTunnelingMode = SplitTunnelingMode.exceptSelected;
      }
      if (!_splitTunnelPackages.contains(normalized)) {
        _splitTunnelPackages.add(normalized);
        _splitTunnelPackages.sort();
      }
    } else {
      _splitTunnelPackages.remove(normalized);
      if (_splitTunnelPackages.isEmpty &&
          _splitTunnelingMode == SplitTunnelingMode.exceptSelected) {
        _splitTunnelingMode = SplitTunnelingMode.off;
      }
    }

    _savePrefs();
    notifyListeners();
  }

  void setTunnelTlsFingerprintSpoofing(bool enabled) {
    _tunnelTlsFingerprintSpoofing = enabled;
    _savePrefs();
    notifyListeners();
  }

  bool isSplitTunnelPackageSelected(String packageName) {
    return _splitTunnelPackages.contains(packageName);
  }

  void toggleSplitTunnelPackage(String packageName) {
    if (_splitTunnelPackages.contains(packageName)) {
      _splitTunnelPackages.remove(packageName);
    } else {
      _splitTunnelPackages.add(packageName);
      _splitTunnelPackages.sort();
    }
    _savePrefs();
    notifyListeners();
  }

  Future<void> loadInstalledApps({bool force = false}) async {
    if (_isLoadingInstalledApps) return;
    if (_installedApps.isNotEmpty && !force) return;

    _isLoadingInstalledApps = true;
    notifyListeners();
    try {
      final apps = await _singbox.getInstalledApps();
      _installedApps = apps;
    } finally {
      _isLoadingInstalledApps = false;
      notifyListeners();
    }
  }

  void selectAutoProfileFromList(KeyListType type, String rawUri) {
    _keyListType = type;
    _selectedAutoRawUri = rawUri;
    final visible = _filteredAutoProfiles;
    final idx = visible.indexWhere((ap) => ap.profile.rawUri == rawUri);
    if (idx == -1) {
      _syncSelectedAutoIndex();
      _savePrefs();
      notifyListeners();
      return;
    }

    _selectedAutoIndex = idx;
    _useManualProfile = false;
    _selectedManualProfile = null;
    _syncHomeSelectionToProfile(visible[idx]);
    _savePrefs();
    notifyListeners();
  }

  AutoProfile? _findAutoProfileByRawUri(String rawUri) {
    if (rawUri.isEmpty) {
      return null;
    }
    return _autoProfiles.cast<AutoProfile?>().firstWhere(
          (profile) => profile?.profile.rawUri == rawUri,
          orElse: () => null,
        );
  }

  void _syncHomeSelectionToProfile(AutoProfile profile) {
    final code = _normalizeCountryCode(profile.countryCode);
    if (code == null) {
      return;
    }

    if (code == 'RU') {
      _homeSelectionScope = AutoSelectionScope.russia;
      return;
    }

    if (profile.listType == KeyListType.whiteList) {
      _homeSelectionScope = AutoSelectionScope.whiteList;
      _selectedWhiteListCountryCode = code;
      return;
    }

    _homeSelectionScope = AutoSelectionScope.allCountries;
    _selectedAllCountryCode = code;
  }

  void selectCountryForHome(AutoSelectionScope scope, String countryCode) {
    _useManualProfile = false;
    _selectedManualProfile = null;
    _selectionNotice = '';

    final normalizedCountry = _normalizeCountryCode(countryCode);
    if (normalizedCountry == null) {
      return;
    }

    _homeSelectionScope = scope;
    switch (scope) {
      case AutoSelectionScope.allCountries:
        _selectedAllCountryCode = normalizedCountry;
      case AutoSelectionScope.whiteList:
        _selectedWhiteListCountryCode = normalizedCountry;
      case AutoSelectionScope.russia:
        break;
    }

    final profiles = _sortProfilesByStability(
      _profilesForScope(scope, countryCode: normalizedCountry),
    );
    if (profiles.isNotEmpty) {
      _setSelectedAutoProfile(profiles.first);
    }
    _savePrefs();
    notifyListeners();
  }

  void selectRussiaForHome() {
    _useManualProfile = false;
    _selectedManualProfile = null;
    _selectionNotice = '';
    _homeSelectionScope = AutoSelectionScope.russia;

    final best = _bestProfileForCurrentSelection();
    if (best != null) {
      _setSelectedAutoProfile(best);
    }
    _savePrefs();
    notifyListeners();
  }

  void selectRussiaListType(KeyListType listType) {
    _useManualProfile = false;
    _selectedManualProfile = null;
    _selectionNotice = '';
    _selectedRussiaListType = listType;
    _homeSelectionScope = AutoSelectionScope.russia;

    final best = _bestProfileForCurrentSelection();
    if (best != null) {
      _setSelectedAutoProfile(best);
    }
    _savePrefs();
    notifyListeners();
  }

  void clearSelectionNotice() {
    if (_selectionNotice.isEmpty) {
      return;
    }
    _selectionNotice = '';
    notifyListeners();
  }

  Future<void> deleteAllKeys() async {
    if (_status.state.isActive || await _singbox.isRunning()) {
      await _stop();
    }

    _autoProfiles = [];
    _manualProfiles = [];
    _useManualProfile = false;
    _selectedManualProfile = null;
    _selectedAutoRawUri = null;
    _selectedAutoIndex = 0;
    _selectionNotice = '';
    _autoProfilesCacheAgeMs = -1;
    _successCounts = {};
    _keySuccessCounts = {};
    _keyFailureCounts = {};
    _keyCooldownUntilMs = {};
    _adaptiveTransportCooldownUntilMs.clear();
    _adaptiveFingerprintCooldownUntilMs.clear();
    _adaptivePreferredTransportByEnv.clear();
    _adaptivePreferredFingerprintByEnv.clear();
    _crossBorderPressureLevel = 0;
    _crossBorderPressureUntilMs = 0;
    _adaptiveMitigationNote = '';
    _keyReputationScores = {};
    _keyReputationUpdatedAtSec = {};
    _keyConsecutiveFailures = {};
    _govFailedKeys.clear();

    final prefs = await SharedPreferences.getInstance();
    await _secureStorage.delete(key: _kAutoProfilesSecure);
    await _secureStorage.delete(key: _kManualProfilesSecure);
    await prefs.remove(_kAutoProfiles);
    await prefs.remove(_kManualProfiles);
    await prefs.remove(_kCacheTime);
    await prefs.remove(_kSelectedAutoRawUri);
    await prefs.remove(_kSelectedManualUri);
    await prefs.remove(_kUseManualProfile);
    await prefs.remove(_kSelectedIdx);
    await prefs.remove(_kSuccessCounts);
    await prefs.remove(_kKeySuccessCounts);
    await prefs.remove(_kKeyFailureCounts);
    await prefs.remove(_kKeyCooldownUntilMs);
    await prefs.remove(_kAdaptiveTransportCooldownUntilMs);
    await prefs.remove(_kAdaptiveFingerprintCooldownUntilMs);
    await prefs.remove(_kAdaptiveMitigationNote);
    await prefs.remove(_kAdaptivePreferredTransportByEnv);
    await prefs.remove(_kAdaptivePreferredFingerprintByEnv);
    await prefs.remove(_kCrossBorderPressureLevel);
    await prefs.remove(_kCrossBorderPressureUntilMs);
    await prefs.remove(_kAntiCrisisMode);
    await prefs.remove(_kKeyReputationScores);
    await prefs.remove(_kKeyReputationUpdatedAtSec);
    await prefs.remove(_kKeyConsecutiveFailures);
    await prefs.remove(_kGovFailedKeys);

    await _savePrefs();
    notifyListeners();
  }

  Future<void> resetSettings() async {
    if (_status.state.isActive || await _singbox.isRunning()) {
      await _stop();
    }

    _connectionMode = AppConnectionMode.tunnel;
    _offlineDeblockProfile = OfflineDeblockProfile.hybrid;
    _offlineDeblockCustomSettings =
        const OfflineDeblockSettings.customDefault();
    _offlineDeblockHybridSettings =
        OfflineDeblockSettings.forProfile(OfflineDeblockProfile.hybrid);
    _deblockerRuntimeBundle = null;
    _cachedIngressRuntimeBundle = null;
    _strictAllowlistModeEnabled = false;
    _quarantinedIngressConfigs.clear();
    _ingressEdgeFailureCounts.clear();
    _ingressEdgeCooldownUntilMs.clear();
    _routingMode = RoutingMode.bypassLan;
    _keyListType = KeyListType.blackList;
    _splitTunnelingMode = SplitTunnelingMode.off;
    _tunnelTlsFingerprintSpoofing = true;
    _languageCode = 'ru';
    _splitTunnelPackages = [];

    _useManualProfile = false;
    _selectedManualProfile = null;
    _selectedAutoRawUri = null;
    _selectedAutoIndex = 0;
    _homeSelectionScope = AutoSelectionScope.allCountries;
    _selectedAllCountryCode = null;
    _selectedWhiteListCountryCode = null;
    _selectedRussiaListType = KeyListType.whiteList;
    _selectionNotice = '';
    _successCounts = {};
    _keySuccessCounts = {};
    _keyFailureCounts = {};
    _keyCooldownUntilMs = {};
    _adaptiveTransportCooldownUntilMs.clear();
    _adaptiveFingerprintCooldownUntilMs.clear();
    _adaptivePreferredTransportByEnv.clear();
    _adaptivePreferredFingerprintByEnv.clear();
    _crossBorderPressureLevel = 0;
    _crossBorderPressureUntilMs = 0;
    _antiCrisisMode = false;
    _runtimeHealthProbeSkipCounter = 0;
    _adaptiveMitigationNote = '';
    _keyReputationScores = {};
    _keyReputationUpdatedAtSec = {};
    _keyConsecutiveFailures = {};

    _status = TunnelStatus(routingMode: _routingMode);

    await _savePrefs();
    notifyListeners();
  }

  // ── Custom Key Sources Management ──────────────────────────────────────

  /// Add a new custom key source
  Future<void> addCustomKeySource(CustomKeySource source) async {
    final service = _customKeySourceService;
    if (service == null) return;
    await service.addSource(source);
    _markCustomSourcesChanged();
    notifyListeners();
    _scheduleCustomSourceProfilesRefresh();
  }

  /// Update an existing custom key source
  Future<void> updateCustomKeySource(CustomKeySource source) async {
    final service = _customKeySourceService;
    if (service == null) return;
    await service.updateSource(source);
    _markCustomSourcesChanged();
    notifyListeners();
    _scheduleCustomSourceProfilesRefresh();
  }

  /// Delete a custom key source by ID
  Future<void> deleteCustomKeySource(String sourceId) async {
    final service = _customKeySourceService;
    if (service == null) return;
    await service.deleteSource(sourceId);
    _markCustomSourcesChanged();
    _customSourceGroups.remove(sourceId);
    _reconcileSelectedManualProfile();
    notifyListeners();
    _scheduleCustomSourceProfilesRefresh();
  }

  /// Toggle custom key source enabled status
  Future<void> toggleCustomKeySource(String sourceId, bool enabled) async {
    final service = _customKeySourceService;
    if (service == null) return;
    await service.toggleSourceEnabled(sourceId, enabled);
    _markCustomSourcesChanged();
    if (!enabled) {
      _customSourceGroups.remove(sourceId);
      _reconcileSelectedManualProfile();
    }
    notifyListeners();
    _scheduleCustomSourceProfilesRefresh();
  }

  /// Clear all custom key sources
  Future<void> clearCustomKeySources() async {
    final service = _customKeySourceService;
    if (service == null) return;
    await service.clearAll();
    _markCustomSourcesChanged();
    _customSourceRefreshQueued = false;
    _customSourceGroups.clear();
    _reconcileSelectedManualProfile();
    notifyListeners();
  }

  Future<void> _refreshCustomSourceProfiles({
    void Function(String message)? onProgress,
  }) async {
    while (_customSourceRefreshTask != null) {
      await _customSourceRefreshTask;
    }

    await _refreshCustomSourceProfilesCore(onProgress: onProgress);
  }

  void _markCustomSourcesChanged() {
    _customSourceRefreshGeneration += 1;
  }

  void _scheduleCustomSourceProfilesRefresh() {
    if (_customSourceRefreshTask != null) {
      _customSourceRefreshQueued = true;
      return;
    }

    _customSourceRefreshTask = _runQueuedCustomSourceRefresh();
  }

  Future<void> _runQueuedCustomSourceRefresh() async {
    try {
      do {
        _customSourceRefreshQueued = false;
        await _refreshCustomSourceProfilesCore();
      } while (_customSourceRefreshQueued);
    } catch (e, st) {
      debugPrint('TunnelProvider._runQueuedCustomSourceRefresh error: $e\n$st');
    } finally {
      _customSourceRefreshTask = null;
      notifyListeners();
    }
  }

  Future<void> _refreshCustomSourceProfilesCore({
    void Function(String message)? onProgress,
  }) async {
    final service = _customKeySourceService;
    final refreshGeneration = _customSourceRefreshGeneration;
    if (service == null) {
      if (refreshGeneration == _customSourceRefreshGeneration) {
        _customSourceGroups.clear();
      }
      return;
    }

    final enabled = service.getEnabledSources();
    if (enabled.isEmpty) {
      if (refreshGeneration == _customSourceRefreshGeneration) {
        _customSourceGroups.clear();
      }
      return;
    }

    final groups = <String, CustomSourceProfilesGroup>{};
    final seen = <String>{};

    for (var i = 0; i < enabled.length; i++) {
      final source = enabled[i];
      onProgress
          ?.call('Мои источники: ${source.name} (${i + 1}/${enabled.length})…');
      try {
        final content = await _readCustomSourceContent(source);
        final parsed = _parseProfilesFromCustomSource(
          content,
          seen,
          type: source.type,
        );
        groups[source.id] = CustomSourceProfilesGroup(
          source: source,
          profiles: parsed,
        );
        await service.updateSourceFetchInfo(
          source.id,
          keyCount: parsed.length,
          timestampMs: DateTime.now().millisecondsSinceEpoch,
          errorMessage: null,
        );
      } catch (e) {
        final message = e.toString();
        groups[source.id] = CustomSourceProfilesGroup(
          source: source,
          profiles: const [],
          errorMessage: message,
        );
        await service.updateSourceFetchInfo(
          source.id,
          keyCount: 0,
          timestampMs: DateTime.now().millisecondsSinceEpoch,
          errorMessage: message,
        );
      }
    }

    if (refreshGeneration != _customSourceRefreshGeneration) {
      return;
    }

    _customSourceGroups
      ..clear()
      ..addAll(groups);
    _restoreDeferredManualProfileSelection();
    _reconcileSelectedManualProfile();
  }

  ProxyProfile? _findSelectableManualProfile(String rawUri) {
    for (final profile in _manualProfiles) {
      if (profile.rawUri == rawUri) {
        return profile;
      }
    }

    for (final group in _customSourceGroups.values) {
      for (final profile in group.profiles) {
        if (profile.rawUri == rawUri) {
          return profile;
        }
      }
    }

    return null;
  }

  void _restoreDeferredManualProfileSelection() {
    final rawUri = _deferredManualProfileRawUri;
    if (rawUri == null || rawUri.isEmpty) {
      return;
    }

    final resolved = _findSelectableManualProfile(rawUri);
    if (resolved == null) {
      return;
    }

    _selectedManualProfile = resolved;
    _useManualProfile = true;
    _deferredManualProfileRawUri = null;
  }

  void _reconcileSelectedManualProfile() {
    final selected = _selectedManualProfile;
    if (selected == null) {
      return;
    }

    final resolved = _findSelectableManualProfile(selected.rawUri);
    if (resolved != null) {
      _selectedManualProfile = resolved;
      return;
    }

    _selectedManualProfile = null;
    _useManualProfile = false;
  }

  Future<String> _readCustomSourceContent(CustomKeySource source) async {
    switch (source.type) {
      case CustomSourceType.url:
        final rawUrl = source.url?.trim() ?? '';
        if (rawUrl.isEmpty) {
          throw const FormatException('Пустой URL источника.');
        }
        final fetchUrl = _normalizeDynamicSchemeUrl(rawUrl);
        final uri = Uri.tryParse(fetchUrl);
        if (uri == null || uri.scheme.toLowerCase() != 'https') {
          throw const FormatException(
            'Источник должен использовать https:// '
            '(или динамические схемы: ssconf://, sub://)',
          );
        }
        final response = await http.get(
          uri,
          headers: {'User-Agent': 'clash.meta', 'Accept': '*/*'},
        ).timeout(const Duration(seconds: 30));
        if (response.statusCode != 200) {
          throw HttpException('HTTP ${response.statusCode}');
        }
        if (response.bodyBytes.length > 5 * 1024 * 1024) {
          throw const FormatException('Слишком большой источник (лимит 5MB).');
        }
        return response.body;

      case CustomSourceType.subscription:
        // Динамическая подписка — ответ может быть Base64, plain-text или SIP008 JSON.
        final rawSubUrl = source.url?.trim() ?? '';
        if (rawSubUrl.isEmpty) {
          throw const FormatException('Пустой URL подписки.');
        }
        final subUrl = _normalizeDynamicSchemeUrl(rawSubUrl);
        final subUri = Uri.tryParse(subUrl);
        if (subUri == null ||
            (subUri.scheme.toLowerCase() != 'https' &&
                subUri.scheme.toLowerCase() != 'http')) {
          throw const FormatException(
            'URL подписки должен начинаться с https:// или http:// '
            '(или динамические схемы: ssconf://, sub://)',
          );
        }
        final subResponse = await http.get(
          subUri,
          headers: {
            'User-Agent': 'clash.meta',
            'Accept': '*/*',
          },
        ).timeout(const Duration(seconds: 30));
        if (subResponse.statusCode != 200) {
          throw HttpException('HTTP ${subResponse.statusCode}');
        }
        if (subResponse.bodyBytes.length > 5 * 1024 * 1024) {
          throw const FormatException('Слишком большой источник (лимит 5MB).');
        }
        return subResponse.body;

      case CustomSourceType.localFile:
        final path = source.filePath?.trim() ?? '';
        if (path.isEmpty) {
          throw const FormatException('Путь к локальному файлу пустой.');
        }
        final file = File(path);
        if (!await file.exists()) {
          throw const FileSystemException('Файл источника не найден');
        }
        final length = await file.length();
        if (length > 5 * 1024 * 1024) {
          throw const FormatException('Слишком большой файл (лимит 5MB).');
        }
        return file.readAsString();
    }
  }

  /// Автоматически декодирует Base64-контент подписки.
  ///
  /// Типичные форматы ответа subscription-эндпоинтов:
  ///  - Один большой Base64-блок (стандарт Xray/V2RayN)
  ///  - Base64-URL (с `-` вместо `+` и `_` вместо `/`)
  ///  - Обычный текст с URI на каждой строке (возвращается как есть)
  static String _decodeSubscriptionContent(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return raw;

    // Если первая значимая строка уже URI — plain-text, декод не нужен.
    final firstMeaningfulLine =
        trimmed.split('\n').map((l) => l.trim()).firstWhere(
              (l) => l.isNotEmpty && !l.startsWith('#'),
              orElse: () => '',
            );
    if (firstMeaningfulLine.isNotEmpty &&
        UriParser.isSupported(firstMeaningfulLine)) {
      return trimmed;
    }

    // Убираем переносы — подписка обычно один непрерывный блок.
    final compact = trimmed.replaceAll('\r', '').replaceAll('\n', '');

    // Стандартный Base64
    final decoded = _tryBase64Decode(compact);
    if (decoded != null) return decoded;

    // URL-safe Base64 (- → +, _ → /)
    final urlSafe = compact.replaceAll('-', '+').replaceAll('_', '/');
    final decodedUrlSafe = _tryBase64Decode(urlSafe);
    if (decodedUrlSafe != null) return decodedUrlSafe;

    // Не удалось декодировать — вернуть как есть.
    return trimmed;
  }

  static String? _tryBase64Decode(String input) {
    if (input.isEmpty) return null;
    final padded = input.padRight(((input.length + 3) ~/ 4) * 4, '=');
    try {
      final bytes = base64.decode(padded);
      final text = utf8.decode(bytes, allowMalformed: false);
      if (text.contains('://')) return text;
    } catch (_) {}
    return null;
  }

  List<ProxyProfile> _parseProfilesFromCustomSource(
    String content,
    Set<String> seen, {
    CustomSourceType type = CustomSourceType.url,
  }) {
    // Для подписок — пытаемся декодировать Base64 перед парсингом.
    final workContent = type == CustomSourceType.subscription
        ? _decodeSubscriptionContent(content)
        : content;
    final out = <ProxyProfile>[];

    // SIP008 JSON (Shadowsocks Dynamic Configuration Format).
    // Встречается в ssconf://-подписках и некоторых HTTP-эндпоинтах.
    if (_looksLikeSip008Json(workContent)) {
      _parseSip008Json(workContent, seen, out);
      if (out.isNotEmpty) return out;
    }

    // Clash YAML — formат, возвращаемый многими провайдерами при
    // User-Agent: clash.meta. Поддерживаем trojan, vless, ss.
    if (_looksLikeClashYaml(workContent)) {
      _parseClashYamlProxies(workContent, seen, out);
      if (out.isNotEmpty) return out;
    }

    final lines = workContent.split('\n');
    if (lines.length > 120000) {
      throw const FormatException('Слишком много строк в источнике.');
    }

    for (final rawLine in lines) {
      final line = rawLine.trim();
      if (line.isEmpty || line.startsWith('#')) {
        continue;
      }
      if (line.length > 8192) {
        continue;
      }
      if (!UriParser.isSupported(line)) {
        continue;
      }
      if (!seen.add(line)) {
        continue;
      }

      final profile = UriParser.parse(line);
      if (!profile.isValid) {
        continue;
      }
      out.add(profile);
    }

    // Fallback: если построчный парсинг не нашёл URI (например, HTML-страница
    // с URI, встроенными в разметку вместо plain-text), ищем URI регуляркой
    // по всему телу ответа.
    if (out.isEmpty) {
      _extractEmbeddedUris(workContent, seen, out);
    }

    return out;
  }

  // Regex для поиска прокси-URI, встроенных в произвольный текст / HTML.
  // Допустимые символы URI: всё кроме пробелов, кавычек, < > и управляющих символов.
  static final _embeddedUriRegex = RegExp(
    r'(?:vless|ss|trojan|tuic|vmess|hysteria2?|hy2|ssr|wireguard|wg|awg|socks5?|ssh)://[^\s"<>]+',
    caseSensitive: false,
  );

  static void _extractEmbeddedUris(
    String content,
    Set<String> seen,
    List<ProxyProfile> out,
  ) {
    // Сначала декодируем HTML-сущности, чтобы `&amp;` → `&` и т.п.
    final decoded = content
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'");

    for (final match in _embeddedUriRegex.allMatches(decoded)) {
      var uri = match.group(0)!;
      // Срезаем возможный «мусор» от HTML/разметки в конце URI
      while (uri.isNotEmpty && ',;)>\'"'.contains(uri[uri.length - 1])) {
        uri = uri.substring(0, uri.length - 1);
      }
      if (uri.length > 8192) continue;
      if (!UriParser.isSupported(uri)) continue;
      if (!seen.add(uri)) continue;
      final profile = UriParser.parse(uri);
      if (!profile.isValid) continue;
      out.add(profile);
    }
  }

  // ── Dynamic scheme helpers ─────────────────────────────────────────────

  /// Нормализует URL, использующий динамические схемы подписок, в
  /// стандартный https://-адрес:
  /// - `ssconf://` → `https://`  (SIP008 Shadowsocks Dynamic Configuration)
  /// - `sub://`    → base64-декодирование → реальный https://-URL
  static String _normalizeDynamicSchemeUrl(String rawUrl) {
    final t = rawUrl.trim();
    final lower = t.toLowerCase();
    if (lower.startsWith('ssconf://')) {
      return 'https://${t.substring('ssconf://'.length)}';
    }
    if (lower.startsWith('sub://')) {
      final encoded = t.substring('sub://'.length);
      try {
        final padded = encoded.padRight(((encoded.length + 3) ~/ 4) * 4, '=');
        final decoded = utf8.decode(base64.decode(padded)).trim();
        if (decoded.startsWith('http://') || decoded.startsWith('https://')) {
          return decoded;
        }
      } catch (_) {}
      // Не удалось декодировать — вернуть как есть (провалит валидацию).
      return t;
    }
    return t;
  }

  /// Быстрая эвристика: является ли контент SIP008 JSON-конфигурацией.
  static bool _looksLikeSip008Json(String content) {
    final t = content.trimLeft();
    return t.startsWith('{') &&
        t.contains('"servers"') &&
        t.contains('"server_port"');
  }

  /// Разбирает SIP008 JSON (Shadowsocks Dynamic Configuration) и добавляет
  /// полученные серверы в [out] в виде ss:// профилей.
  static void _parseSip008Json(
    String content,
    Set<String> seen,
    List<ProxyProfile> out,
  ) {
    try {
      final decoded = jsonDecode(content);
      if (decoded is! Map<String, dynamic>) return;
      final servers = decoded['servers'];
      if (servers is! List) return;
      for (final entry in servers) {
        if (entry is! Map<String, dynamic>) continue;
        final server = (entry['server'] as String?)?.trim() ?? '';
        final portRaw = entry['server_port'];
        final password = (entry['password'] as String?)?.trim() ?? '';
        final method = (entry['method'] as String?)?.trim() ?? '';
        final remarks =
            ((entry['remarks'] as String?) ?? (entry['name'] as String?) ?? '')
                .trim();
        if (server.isEmpty || password.isEmpty || method.isEmpty) continue;
        final port = portRaw is int ? portRaw : int.tryParse('$portRaw') ?? 0;
        if (port <= 0 || port > 65535) continue;
        final ssUri =
            _buildSsUriFromSip008(method, password, server, port, remarks);
        if (ssUri.isEmpty) continue;
        if (!seen.add(ssUri)) continue;
        final profile = UriParser.parse(ssUri);
        if (!profile.isValid) continue;
        out.add(profile);
      }
    } catch (_) {}
  }

  /// Строит ss:// URI в SIP002-формате из SIP008-параметров.
  static String _buildSsUriFromSip008(
    String method,
    String password,
    String server,
    int port,
    String remarks,
  ) {
    try {
      // SIP002: ss://BASE64URL(method:password)@host:port[/#name]
      final userinfo = base64Url
          .encode(utf8.encode('$method:$password'))
          .replaceAll('=', '');
      final fragment =
          remarks.isNotEmpty ? '#${Uri.encodeComponent(remarks)}' : '';
      return 'ss://$userinfo@$server:$port$fragment';
    } catch (_) {
      return '';
    }
  }

  // ── Clash YAML parser ────────────────────────────────────────────────────

  /// Эвристика: похоже ли содержимое на конфиг Clash/Mihomo?
  static bool _looksLikeClashYaml(String content) {
    return (content.contains('\nproxies:\n') ||
            content.startsWith('proxies:\n')) &&
        RegExp(
          r'^\s+type:\s*(trojan|vless|ss|vmess|hysteria2?|hy2)',
          multiLine: true,
        ).hasMatch(content);
  }

  /// Парсит блок `proxies:` из Clash/Mihomo YAML и добавляет
  /// корректные URI-профили в [out].
  static void _parseClashYamlProxies(
    String content,
    Set<String> seen,
    List<ProxyProfile> out,
  ) {
    final lines = content.split('\n');
    final blocks = <Map<String, String>>[];
    Map<String, String>? current;
    bool inProxies = false;
    String? inSubKey;

    for (final line in lines) {
      // Верхний уровень «proxies:»
      if (!inProxies && line.trimRight() == 'proxies:') {
        inProxies = true;
        continue;
      }
      if (!inProxies) continue;

      // Конец секции proxies: новый ключ верхнего уровня
      if (line.isNotEmpty &&
          !line.startsWith(' ') &&
          !line.startsWith('-') &&
          !line.startsWith('\t')) {
        if (current != null) {
          blocks.add(current);
          current = null;
        }
        inProxies = false;
        continue;
      }

      // Новый элемент списка «- ...»
      if (line.startsWith('- ')) {
        if (current != null) blocks.add(current);
        current = {};
        inSubKey = null;
        final rest = line.substring(2).trimLeft();
        if (rest.startsWith('{')) {
          _parseClashInlineProxy(rest, current);
        } else {
          _addClashYamlKV(rest, current, null);
        }
        continue;
      }

      if (current == null) continue;

      // 2-space: поле прокси
      if (line.startsWith('  ') && !line.startsWith('   ')) {
        final kv = line.substring(2).trimRight();
        final ci = kv.indexOf(':');
        if (ci < 0) continue;
        final key = kv.substring(0, ci).trim();
        final val = kv.substring(ci + 1).trim();
        if (val.isEmpty) {
          inSubKey = key;
        } else {
          inSubKey = null;
          current[key] = _unquoteYamlString(val);
        }
        continue;
      }

      // 4-space: поле вложенной секции (reality-opts, tcp-opts, …)
      if (line.startsWith('    ') &&
          !line.startsWith('     ') &&
          inSubKey != null) {
        _addClashYamlKV(line.substring(4).trimRight(), current, inSubKey);
      }
    }

    if (current != null) blocks.add(current);

    for (final block in blocks) {
      try {
        final uri = _buildUriFromClashProxy(block);
        if (uri.isEmpty) continue;
        if (!seen.add(uri)) continue;
        final profile = UriParser.parse(uri);
        if (!profile.isValid) continue;
        out.add(profile);
      } catch (_) {}
    }
  }

  static void _addClashYamlKV(
    String kvLine,
    Map<String, String> map,
    String? prefix,
  ) {
    final ci = kvLine.indexOf(':');
    if (ci <= 0) return;
    final key = kvLine.substring(0, ci).trim();
    if (key.isEmpty) return;
    final value = _unquoteYamlString(kvLine.substring(ci + 1).trim());
    map[prefix != null ? '$prefix.$key' : key] = value;
  }

  static void _parseClashInlineProxy(String inline, Map<String, String> map) {
    final body = inline.startsWith('{') && inline.contains('}')
        ? inline.substring(1, inline.lastIndexOf('}'))
        : inline;
    var depth = 0;
    var start = 0;
    final parts = <String>[];
    for (var i = 0; i < body.length; i++) {
      final c = body[i];
      if (c == '{' || c == '[') {
        depth++;
      } else if (c == '}' || c == ']') {
        depth--;
      } else if (c == ',' && depth == 0) {
        parts.add(body.substring(start, i).trim());
        start = i + 1;
      }
    }
    if (start < body.length) parts.add(body.substring(start).trim());
    for (final part in parts) {
      _addClashYamlKV(part, map, null);
    }
  }

  static String _unquoteYamlString(String s) {
    final t = s.trim();
    if (t.length >= 2 && t.startsWith("'") && t.endsWith("'")) {
      return t.substring(1, t.length - 1);
    }
    if (t.length >= 2 && t.startsWith('"') && t.endsWith('"')) {
      return t.substring(1, t.length - 1);
    }
    return t;
  }

  static String _buildUriFromClashProxy(Map<String, String> proxy) {
    final type = (proxy['type'] ?? '').toLowerCase().trim();
    final rawName = proxy['name'] ?? '';
    final fragment =
        rawName.isNotEmpty ? '#${Uri.encodeComponent(rawName)}' : '';
    final server = proxy['server'] ?? '';
    final port = proxy['port'] ?? '';
    if (server.isEmpty || port.isEmpty) return '';

    switch (type) {
      case 'trojan':
        final password = proxy['password'] ?? '';
        if (password.isEmpty) return '';
        final sni = proxy['sni'] ?? server;
        return 'trojan://$password@$server:$port'
            '?sni=${Uri.encodeComponent(sni)}';

      case 'vless':
        final uuid = proxy['uuid'] ?? '';
        if (uuid.isEmpty) return '';
        final hasReality = proxy.containsKey('reality-opts.public-key');
        final security =
            hasReality ? 'reality' : (proxy['tls'] == 'true' ? 'tls' : 'none');
        // Clash YAML использует «servername» для SNI в vless, не «sni»
        final sni = proxy['servername'] ?? proxy['sni'] ?? '';
        final pbk = proxy['reality-opts.public-key'] ?? '';
        final sid = proxy['reality-opts.short-id'] ?? '';
        final fpRaw = proxy['client-fingerprint'] ?? 'chrome';
        final fp = fpRaw == 'random' ? 'chrome' : fpRaw;
        final network = proxy['network'] ?? 'tcp';
        final params = StringBuffer('security=$security&type=$network');
        if (sni.isNotEmpty) params.write('&sni=${Uri.encodeComponent(sni)}');
        if (pbk.isNotEmpty) params.write('&pbk=${Uri.encodeComponent(pbk)}');
        if (sid.isNotEmpty) params.write('&sid=${Uri.encodeComponent(sid)}');
        if (fp.isNotEmpty) params.write('&fp=${Uri.encodeComponent(fp)}');
        return 'vless://$uuid@$server:$port?$params$fragment';

      case 'ss':
      case 'shadowsocks':
        final password = proxy['password'] ?? '';
        final method = proxy['cipher'] ?? proxy['method'] ?? '';
        if (password.isEmpty || method.isEmpty) return '';
        final userinfo = base64Url
            .encode(utf8.encode('$method:$password'))
            .replaceAll('=', '');
        return 'ss://$userinfo@$server:$port$fragment';

      default:
        return '';
    }
  }

  void _normalizeSelectedAutoIndex() {
    final count = _filteredAutoProfiles.length;
    if (count == 0) {
      _selectedAutoIndex = 0;
      return;
    }
    if (_selectedAutoIndex >= count || _selectedAutoIndex < 0) {
      _selectedAutoIndex = 0;
    }
  }

  // ── Persistence ───────────────────────────────────────────────────────────

  static const _kRoutingMode = 'routing_mode';
  static const _kRoutingRuntimePolicy = 'routing_runtime_policy';
  static const _kConnectionMode = 'connection_mode';
  static const _kOfflineDeblockProfile = 'offline_deblock_profile';
  static const _kOfflineDeblockCustomSettings =
      'offline_deblock_custom_settings';
  static const _kOfflineDeblockHybridSettings =
      'offline_deblock_hybrid_settings';
  static const _kDeblockerRuntimeBundle = 'deblocker_runtime_bundle';
  static const _kCachedIngressRuntimeBundle = 'cached_ingress_runtime_bundle';
  static const _kStrictAllowlistModeEnabled = 'strict_allowlist_mode_enabled';

  static const _kKeyListType = 'key_list_type';
  static const _kManualProfiles = 'manual_profiles';
  static const _kManualProfilesSecure = 'manual_profiles_secure_v1';
  static const _kAutoProfiles = 'auto_profiles_cache';
  static const _kAutoProfilesSecure = 'auto_profiles_secure_v1';
  static const _kCacheTime = 'auto_profiles_cache_time';
  static const _kSelectedIdx = 'selected_auto_index';
  static const _kSplitTunnelMode = 'split_tunnel_mode';
  static const _kSplitTunnelPackages = 'split_tunnel_packages';
  static const _kTunnelTlsFingerprintSpoofing =
      'tunnel_tls_fingerprint_spoofing';
  static const _kLanguageCode = 'language_code';
  static const _kUseManualProfile = 'use_manual_profile';
  static const _kSelectedManualUri = 'selected_manual_uri';
  static const _kSuccessCounts = 'geo_success_counts';
  static const _kKeySuccessCounts = 'key_success_counts';
  static const _kKeyFailureCounts = 'key_failure_counts';
  static const _kKeyCooldownUntilMs = 'key_cooldown_until_ms';
  static const _kAdaptiveTransportCooldownUntilMs =
      'adaptive_transport_cooldown_until_ms';
  static const _kAdaptiveFingerprintCooldownUntilMs =
      'adaptive_fingerprint_cooldown_until_ms';
  static const _kAdaptiveMitigationNote = 'adaptive_mitigation_note';
  static const _kAdaptivePreferredTransportByEnv =
      'adaptive_preferred_transport_by_env';
  static const _kAdaptivePreferredFingerprintByEnv =
      'adaptive_preferred_fingerprint_by_env';
  static const _kCrossBorderPressureLevel = 'cross_border_pressure_level';
  static const _kCrossBorderPressureUntilMs = 'cross_border_pressure_until_ms';
  static const _kAntiCrisisMode = 'anti_crisis_mode';
  static const _kKeyReputationScores = 'key_reputation_scores';
  static const _kKeyReputationUpdatedAtSec = 'key_reputation_updated_at_sec';
  static const _kKeyConsecutiveFailures = 'key_consecutive_failures';
  static const _kGovFailedKeys = 'gov_failed_keys';
  static const _kSelectedAutoRawUri = 'selected_auto_raw_uri';
  static const _kHomeSelectionScope = 'home_selection_scope';
  static const _kSelectedAllCountryCode = 'selected_all_country_code';
  static const _kSelectedWhiteListCountryCode =
      'selected_white_list_country_code';
  static const _kSelectedRussiaListType = 'selected_russia_list_type';
  static const _cacheHardStaleTtlMs = 24 * 60 * 60 * 1000; // 24 h

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();

    _connectionMode = AppConnectionModeExt.fromKey(
      prefs.getString(_kConnectionMode) ?? AppConnectionMode.tunnel.key,
    );
    _offlineDeblockProfile = OfflineDeblockProfileExt.fromKey(
      prefs.getString(_kOfflineDeblockProfile) ??
          OfflineDeblockProfile.hybrid.key,
    );
    final customSettingsRaw = prefs.getString(_kOfflineDeblockCustomSettings);
    if (customSettingsRaw != null && customSettingsRaw.trim().isNotEmpty) {
      try {
        _offlineDeblockCustomSettings = OfflineDeblockSettings.fromJson(
          Map<String, dynamic>.from(
            jsonDecode(customSettingsRaw) as Map<String, dynamic>,
          ),
        );
      } catch (_) {
        _offlineDeblockCustomSettings =
            const OfflineDeblockSettings.customDefault();
      }
    }

    final hybridSettingsRaw = prefs.getString(_kOfflineDeblockHybridSettings);
    if (hybridSettingsRaw != null && hybridSettingsRaw.trim().isNotEmpty) {
      try {
        _offlineDeblockHybridSettings = OfflineDeblockSettings.fromJson(
          Map<String, dynamic>.from(
            jsonDecode(hybridSettingsRaw) as Map<String, dynamic>,
          ),
        );
      } catch (_) {
        _offlineDeblockHybridSettings =
            OfflineDeblockSettings.forProfile(OfflineDeblockProfile.hybrid);
      }
    }

    final runtimeBundleRaw = prefs.getString(_kDeblockerRuntimeBundle);
    if (runtimeBundleRaw != null && runtimeBundleRaw.trim().isNotEmpty) {
      try {
        _deblockerRuntimeBundle = DeblockerRuntimeBundle.fromJson(
          Map<String, dynamic>.from(
            jsonDecode(runtimeBundleRaw) as Map<String, dynamic>,
          ),
        );
      } catch (_) {
        _deblockerRuntimeBundle = null;
      }
    }

    final cachedIngressBundleRaw =
        prefs.getString(_kCachedIngressRuntimeBundle);
    if (cachedIngressBundleRaw != null &&
        cachedIngressBundleRaw.trim().isNotEmpty) {
      try {
        _cachedIngressRuntimeBundle = DeblockerRuntimeBundle.fromJson(
          Map<String, dynamic>.from(
            jsonDecode(cachedIngressBundleRaw) as Map<String, dynamic>,
          ),
        );
      } catch (_) {
        _cachedIngressRuntimeBundle = null;
      }
    }

    if (_cachedIngressRuntimeBundle == null &&
        _deblockerRuntimeBundle?.deliveryMode ==
            DeblockerDeliveryMode.allowlistedIngress) {
      _cachedIngressRuntimeBundle = _deblockerRuntimeBundle;
    }

    _strictAllowlistModeEnabled =
        prefs.getBool(_kStrictAllowlistModeEnabled) ?? false;


    _routingMode = RoutingModeExt.fromKey(
      prefs.getString(_kRoutingMode) ?? 'bypass_lan',
    );

    final routingRuntimePolicyRaw = prefs.getString(_kRoutingRuntimePolicy);
    if (routingRuntimePolicyRaw != null &&
        routingRuntimePolicyRaw.trim().isNotEmpty) {
      try {
        _routingRuntimePolicy = RoutingRuntimePolicy.fromJson(
          Map<String, dynamic>.from(
            jsonDecode(routingRuntimePolicyRaw) as Map<String, dynamic>,
          ),
        );
      } catch (_) {
        _routingRuntimePolicy = const RoutingRuntimePolicy();
      }
    }

    final klStr = prefs.getString(_kKeyListType) ?? 'blackList';
    _keyListType =
        klStr == 'whiteList' ? KeyListType.whiteList : KeyListType.blackList;
    _splitTunnelingMode = SplitTunnelingModeExt.fromKey(
      prefs.getString(_kSplitTunnelMode) ?? 'off',
    );
    _tunnelTlsFingerprintSpoofing =
        prefs.getBool(_kTunnelTlsFingerprintSpoofing) ?? true;
    _languageCode = _normalizeLanguageCode(prefs.getString(_kLanguageCode));
    _splitTunnelPackages =
        prefs.getStringList(_kSplitTunnelPackages) ?? <String>[];

    _selectedAutoIndex = prefs.getInt(_kSelectedIdx) ?? 0;
    _selectedAutoRawUri = prefs.getString(_kSelectedAutoRawUri);
    _homeSelectionScope = AutoSelectionScopeExt.fromKey(
      prefs.getString(_kHomeSelectionScope) ??
          AutoSelectionScope.allCountries.key,
    );
    _selectedAllCountryCode = _normalizeCountryCode(
      prefs.getString(_kSelectedAllCountryCode),
    );
    _selectedWhiteListCountryCode = _normalizeCountryCode(
      prefs.getString(_kSelectedWhiteListCountryCode),
    );

    final russiaListStr =
        prefs.getString(_kSelectedRussiaListType) ?? 'whiteList';
    _selectedRussiaListType = russiaListStr == 'allKeys'
        ? KeyListType.blackList
        : KeyListType.whiteList;

    final secureManualRaw = await _secureStorage.read(
      key: _kManualProfilesSecure,
    );
    _manualProfiles = _decodeManualProfiles(secureManualRaw);

    // Restore manual profile selection.
    _useManualProfile = prefs.getBool(_kUseManualProfile) ?? false;
    final savedManualUri = prefs.getString(_kSelectedManualUri);
    if (_useManualProfile &&
        savedManualUri != null &&
        savedManualUri.isNotEmpty) {
      _selectedManualProfile = _findSelectableManualProfile(savedManualUri);
      if (_selectedManualProfile == null) {
        _deferredManualProfileRawUri = savedManualUri;
        _useManualProfile = false;
      }
    } else {
      _useManualProfile = false;
      _selectedManualProfile = null;
      _deferredManualProfileRawUri = null;
    }

    // One-time migration from legacy unencrypted prefs.
    if (_manualProfiles.isEmpty) {
      final legacyManualRaw = prefs.getStringList(_kManualProfiles) ?? [];
      if (legacyManualRaw.isNotEmpty) {
        _manualProfiles = legacyManualRaw
            .map((s) {
              try {
                return ProxyProfile.fromJson(
                  Map<String, dynamic>.from(jsonDecode(s) as Map),
                );
              } catch (_) {
                return null;
              }
            })
            .whereType<ProxyProfile>()
            .toList();
        await _persistManualProfilesSecure();
      }
      await prefs.remove(_kManualProfiles);
    }

    // Cached auto profiles (tiered TTL strategy).
    final cacheTime = prefs.getInt(_kCacheTime) ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    _autoProfilesCacheAgeMs = cacheTime > 0 ? (now - cacheTime) : -1;
    if (_autoProfilesCacheAgeMs >= 0 &&
        _autoProfilesCacheAgeMs < _cacheHardStaleTtlMs) {
      await _loadCachedAutoProfiles(prefs);
    }

    // Загрузить историю успешных гео-подключений
    final successRaw = prefs.getString(_kSuccessCounts);
    if (successRaw != null) {
      try {
        final decoded = jsonDecode(successRaw) as Map<String, dynamic>;
        _successCounts = decoded.map((k, v) => MapEntry(k, (v as num).toInt()));
      } catch (_) {
        _successCounts = {};
        _keySuccessCounts = {};
        _keyFailureCounts = {};
        _keyCooldownUntilMs = {};
      }
    }

    final keySuccessRaw = prefs.getString(_kKeySuccessCounts);
    if (keySuccessRaw != null) {
      try {
        final decoded = jsonDecode(keySuccessRaw) as Map<String, dynamic>;
        _keySuccessCounts =
            decoded.map((k, v) => MapEntry(k, (v as num).toInt()));
      } catch (_) {
        _keySuccessCounts = {};
      }
    }

    final keyFailureRaw = prefs.getString(_kKeyFailureCounts);
    if (keyFailureRaw != null) {
      try {
        final decoded = jsonDecode(keyFailureRaw) as Map<String, dynamic>;
        _keyFailureCounts =
            decoded.map((k, v) => MapEntry(k, (v as num).toInt()));
      } catch (_) {
        _keyFailureCounts = {};
      }
    }

    final cooldownRaw = prefs.getString(_kKeyCooldownUntilMs);
    if (cooldownRaw != null) {
      try {
        final decoded = jsonDecode(cooldownRaw) as Map<String, dynamic>;
        _keyCooldownUntilMs =
            decoded.map((k, v) => MapEntry(k, (v as num).toInt()));
      } catch (_) {
        _keyCooldownUntilMs = {};
      }
    }

    final adaptiveTransportCooldownRaw =
        prefs.getString(_kAdaptiveTransportCooldownUntilMs);
    if (adaptiveTransportCooldownRaw != null) {
      try {
        final decoded =
            jsonDecode(adaptiveTransportCooldownRaw) as Map<String, dynamic>;
        _adaptiveTransportCooldownUntilMs
          ..clear()
          ..addAll(decoded.map((k, v) => MapEntry(k, (v as num).toInt())));
      } catch (_) {
        _adaptiveTransportCooldownUntilMs.clear();
      }
    }

    final adaptiveFingerprintCooldownRaw =
        prefs.getString(_kAdaptiveFingerprintCooldownUntilMs);
    if (adaptiveFingerprintCooldownRaw != null) {
      try {
        final decoded =
            jsonDecode(adaptiveFingerprintCooldownRaw) as Map<String, dynamic>;
        _adaptiveFingerprintCooldownUntilMs
          ..clear()
          ..addAll(decoded.map((k, v) => MapEntry(k, (v as num).toInt())));
      } catch (_) {
        _adaptiveFingerprintCooldownUntilMs.clear();
      }
    }
    _adaptiveMitigationNote =
        prefs.getString(_kAdaptiveMitigationNote)?.trim() ?? '';

    final adaptivePreferredTransportRaw =
        prefs.getString(_kAdaptivePreferredTransportByEnv);
    if (adaptivePreferredTransportRaw != null) {
      try {
        final decoded =
            jsonDecode(adaptivePreferredTransportRaw) as Map<String, dynamic>;
        _adaptivePreferredTransportByEnv
          ..clear()
          ..addAll(decoded.map((k, v) => MapEntry(k, '$v')));
      } catch (_) {
        _adaptivePreferredTransportByEnv.clear();
      }
    }

    final adaptivePreferredFingerprintRaw =
        prefs.getString(_kAdaptivePreferredFingerprintByEnv);
    if (adaptivePreferredFingerprintRaw != null) {
      try {
        final decoded =
            jsonDecode(adaptivePreferredFingerprintRaw) as Map<String, dynamic>;
        _adaptivePreferredFingerprintByEnv
          ..clear()
          ..addAll(decoded.map((k, v) => MapEntry(k, '$v')));
      } catch (_) {
        _adaptivePreferredFingerprintByEnv.clear();
      }
    }

    _evictExpiredAdaptiveCooldowns();
    _crossBorderPressureLevel = (prefs.getInt(_kCrossBorderPressureLevel) ?? 0)
        .clamp(0, _crossBorderPressureMaxLevel);
    _crossBorderPressureUntilMs =
        prefs.getInt(_kCrossBorderPressureUntilMs) ?? 0;
    _antiCrisisMode = prefs.getBool(_kAntiCrisisMode) ?? false;
    if (_antiCrisisMode) {
      _crossBorderPressureLevel = _crossBorderPressureMaxLevel;
      _crossBorderPressureUntilMs =
          DateTime.now().add(const Duration(hours: 24)).millisecondsSinceEpoch;
    }
    _evictExpiredCrossBorderPressure();

    final reputationRaw = prefs.getString(_kKeyReputationScores);
    if (reputationRaw != null) {
      try {
        final decoded = jsonDecode(reputationRaw) as Map<String, dynamic>;
        _keyReputationScores = decoded.map(
          (k, v) => MapEntry(
            k,
            RelayReputation.clampScore((v as num).toInt()),
          ),
        );
      } catch (_) {
        _keyReputationScores = {};
      }
    }

    final reputationUpdatedRaw = prefs.getString(_kKeyReputationUpdatedAtSec);
    if (reputationUpdatedRaw != null) {
      try {
        final decoded =
            jsonDecode(reputationUpdatedRaw) as Map<String, dynamic>;
        _keyReputationUpdatedAtSec =
            decoded.map((k, v) => MapEntry(k, (v as num).toInt()));
      } catch (_) {
        _keyReputationUpdatedAtSec = {};
      }
    }

    final consecutiveFailuresRaw = prefs.getString(_kKeyConsecutiveFailures);
    if (consecutiveFailuresRaw != null) {
      try {
        final decoded =
            jsonDecode(consecutiveFailuresRaw) as Map<String, dynamic>;
        _keyConsecutiveFailures =
            decoded.map((k, v) => MapEntry(k, (v as num).toInt()));
      } catch (_) {
        _keyConsecutiveFailures = {};
      }
    }

    final govFailedRaw = prefs.getStringList(_kGovFailedKeys);
    if (govFailedRaw != null) {
      _govFailedKeys = Set.from(govFailedRaw);
    }

    // One-time migration from legacy success/failure counters.
    if (_keyReputationScores.isEmpty &&
        (_keySuccessCounts.isNotEmpty || _keyFailureCounts.isNotEmpty)) {
      final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final keys = <String>{
        ..._keySuccessCounts.keys,
        ..._keyFailureCounts.keys,
      };
      for (final key in keys) {
        final success = _keySuccessCounts[key] ?? 0;
        final failure = _keyFailureCounts[key] ?? 0;
        final seeded = RelayReputation.defaultScore +
            success * RelayReputation.successBonus -
            failure * RelayReputation.failurePenalty;
        _keyReputationScores[key] = RelayReputation.clampScore(seeded);
        _keyReputationUpdatedAtSec[key] = nowSec;
      }
    }

    _restoreSelectionAfterRefresh(
      previousRawUri: _selectedAutoRawUri,
      previousScope: _homeSelectionScope,
      previousAllCountryCode: _selectedAllCountryCode,
      previousWhiteListCountryCode: _selectedWhiteListCountryCode,
    );

    // Initialize custom key source service
    _customKeySourceService = CustomKeySourceService(prefs);

    _status = _status.copyWith(routingMode: _routingMode);
    notifyListeners();
  }

  Future<void> _savePrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kConnectionMode, _connectionMode.key);
    await prefs.setString(
      _kOfflineDeblockProfile,
      _offlineDeblockProfile.key,
    );
    await prefs.setString(
      _kOfflineDeblockCustomSettings,
      jsonEncode(_offlineDeblockCustomSettings.toJson()),
    );
    await prefs.setString(
      _kOfflineDeblockHybridSettings,
      jsonEncode(_offlineDeblockHybridSettings.toJson()),
    );
    if (_deblockerRuntimeBundle != null) {
      await prefs.setString(
        _kDeblockerRuntimeBundle,
        jsonEncode(_deblockerRuntimeBundle!.toJson()),
      );
    } else {
      await prefs.remove(_kDeblockerRuntimeBundle);
    }
    if (_cachedIngressRuntimeBundle != null) {
      await prefs.setString(
        _kCachedIngressRuntimeBundle,
        jsonEncode(_cachedIngressRuntimeBundle!.toJson()),
      );
    } else {
      await prefs.remove(_kCachedIngressRuntimeBundle);
    }
    await prefs.setBool(
      _kStrictAllowlistModeEnabled,
      _strictAllowlistModeEnabled,
    );

    await prefs.setString(_kRoutingMode, _routingMode.key);
    if (_routingRuntimePolicy.hasOverrides) {
      await prefs.setString(
        _kRoutingRuntimePolicy,
        jsonEncode(_routingRuntimePolicy.toJson()),
      );
    } else {
      await prefs.remove(_kRoutingRuntimePolicy);
    }
    await prefs.setString(
      _kKeyListType,
      _keyListType == KeyListType.whiteList ? 'whiteList' : 'blackList',
    );
    await prefs.setString(_kSplitTunnelMode, _splitTunnelingMode.key);
    await prefs.setBool(
      _kTunnelTlsFingerprintSpoofing,
      _tunnelTlsFingerprintSpoofing,
    );
    await prefs.setString(_kLanguageCode, _languageCode);
    await prefs.setStringList(_kSplitTunnelPackages, _splitTunnelPackages);
    await prefs.setInt(_kSelectedIdx, _selectedAutoIndex);
    if (_selectedAutoRawUri != null && _selectedAutoRawUri!.isNotEmpty) {
      await prefs.setString(_kSelectedAutoRawUri, _selectedAutoRawUri!);
    } else {
      await prefs.remove(_kSelectedAutoRawUri);
    }
    await prefs.setString(_kHomeSelectionScope, _homeSelectionScope.key);
    if (_selectedAllCountryCode != null &&
        _selectedAllCountryCode!.isNotEmpty) {
      await prefs.setString(_kSelectedAllCountryCode, _selectedAllCountryCode!);
    } else {
      await prefs.remove(_kSelectedAllCountryCode);
    }
    if (_selectedWhiteListCountryCode != null &&
        _selectedWhiteListCountryCode!.isNotEmpty) {
      await prefs.setString(
        _kSelectedWhiteListCountryCode,
        _selectedWhiteListCountryCode!,
      );
    } else {
      await prefs.remove(_kSelectedWhiteListCountryCode);
    }
    await prefs.setString(
      _kSelectedRussiaListType,
      _selectedRussiaListType == KeyListType.blackList
          ? 'allKeys'
          : 'whiteList',
    );
    await prefs.setBool(_kUseManualProfile, _useManualProfile);
    if (_useManualProfile && _selectedManualProfile != null) {
      await prefs.setString(
          _kSelectedManualUri, _selectedManualProfile!.rawUri);
    } else {
      await prefs.remove(_kSelectedManualUri);
    }
    // Сохранить историю гео-успехов
    await prefs.setString(_kSuccessCounts, jsonEncode(_successCounts));
    await prefs.setString(_kKeySuccessCounts, jsonEncode(_keySuccessCounts));
    await prefs.setString(_kKeyFailureCounts, jsonEncode(_keyFailureCounts));
    await prefs.setString(
        _kKeyCooldownUntilMs, jsonEncode(_keyCooldownUntilMs));
    await prefs.setString(
      _kAdaptiveTransportCooldownUntilMs,
      jsonEncode(_adaptiveTransportCooldownUntilMs),
    );
    await prefs.setString(
      _kAdaptiveFingerprintCooldownUntilMs,
      jsonEncode(_adaptiveFingerprintCooldownUntilMs),
    );
    await prefs.setString(_kAdaptiveMitigationNote, _adaptiveMitigationNote);
    await prefs.setString(
      _kAdaptivePreferredTransportByEnv,
      jsonEncode(_adaptivePreferredTransportByEnv),
    );
    await prefs.setString(
      _kAdaptivePreferredFingerprintByEnv,
      jsonEncode(_adaptivePreferredFingerprintByEnv),
    );
    await prefs.setInt(_kCrossBorderPressureLevel, _crossBorderPressureLevel);
    await prefs.setInt(
        _kCrossBorderPressureUntilMs, _crossBorderPressureUntilMs);
    await prefs.setBool(_kAntiCrisisMode, _antiCrisisMode);
    await prefs.setString(
      _kKeyReputationScores,
      jsonEncode(_keyReputationScores),
    );
    await prefs.setString(
      _kKeyReputationUpdatedAtSec,
      jsonEncode(_keyReputationUpdatedAtSec),
    );
    await prefs.setString(
      _kKeyConsecutiveFailures,
      jsonEncode(_keyConsecutiveFailures),
    );
    if (_govFailedKeys.isNotEmpty) {
      await prefs.setStringList(_kGovFailedKeys, _govFailedKeys.toList());
    } else {
      await prefs.remove(_kGovFailedKeys);
    }
    await _persistManualProfilesSecure();
    await prefs.remove(_kManualProfiles);
  }

  Future<void> setLanguageCode(String languageCode) async {
    final normalized = _normalizeLanguageCode(languageCode);
    if (_languageCode == normalized) {
      return;
    }
    _languageCode = normalized;
    await _savePrefs();
    notifyListeners();
  }



  String _normalizeLanguageCode(String? value) {
    final code = value?.trim().toLowerCase();
    return code == 'en' ? 'en' : 'ru';
  }

  Future<void> _cacheAutoProfiles() async {
    final prefs = await SharedPreferences.getInstance();
    final list = _autoProfiles.map((ap) {
      return {
        'profile': ap.profile.toJson(),
        'countryCode': ap.countryCode,
        'countryName': ap.countryName,
        'flagEmoji': ap.flagEmoji,
        'listType': ap.listType == KeyListType.whiteList ? 'white' : 'black',
      };
    }).toList();
    await _secureStorage.write(
        key: _kAutoProfilesSecure, value: jsonEncode(list));
    await prefs.setInt(_kCacheTime, DateTime.now().millisecondsSinceEpoch);
    _autoProfilesCacheAgeMs = 0;
    await prefs.remove(_kAutoProfiles);
  }

  Future<void> _loadCachedAutoProfiles(SharedPreferences prefs) async {
    final secureRaw = await _secureStorage.read(key: _kAutoProfilesSecure);
    if (secureRaw != null && secureRaw.trim().isNotEmpty) {
      _autoProfiles = _decodeAutoProfiles(secureRaw);
      return;
    }

    // One-time migration from legacy unencrypted prefs.
    final legacyList = prefs.getStringList(_kAutoProfiles) ?? [];
    if (legacyList.isEmpty) {
      _autoProfiles = [];
      return;
    }

    final legacyJson = '[${legacyList.join(',')}]';
    _autoProfiles = _decodeAutoProfiles(legacyJson);
    await _secureStorage.write(key: _kAutoProfilesSecure, value: legacyJson);
    await prefs.remove(_kAutoProfiles);
  }

  void _restoreSelectionAfterRefresh({
    required String? previousRawUri,
    required AutoSelectionScope previousScope,
    required String? previousAllCountryCode,
    required String? previousWhiteListCountryCode,
  }) {
    _homeSelectionScope = previousScope;
    _selectedAllCountryCode = _resolveCountryCodeForScope(
        AutoSelectionScope.allCountries, previousAllCountryCode);
    _selectedWhiteListCountryCode = _resolveCountryCodeForScope(
      AutoSelectionScope.whiteList,
      previousWhiteListCountryCode,
    );

    final previousMatch = previousRawUri == null
        ? null
        : _autoProfiles.cast<AutoProfile?>().firstWhere(
              (profile) => profile?.profile.rawUri == previousRawUri,
              orElse: () => null,
            );
    if (previousMatch != null) {
      _selectedAutoRawUri = previousMatch.profile.rawUri;
      _syncSelectedAutoIndex();
      return;
    }

    _selectedAutoRawUri = null;
    _normalizeSelectedAutoIndex();
  }

  String? _resolveCountryCodeForScope(
    AutoSelectionScope scope,
    String? preferredCountryCode,
  ) {
    final normalizedPreferred = _normalizeCountryCode(preferredCountryCode);
    if (normalizedPreferred != null &&
        _profilesForScope(scope, countryCode: normalizedPreferred).isNotEmpty) {
      return normalizedPreferred;
    }
    return null;
  }

  Future<void> _persistManualProfilesSecure() async {
    final payload = _manualProfiles.map((p) => p.toJson()).toList();
    await _secureStorage.write(
      key: _kManualProfilesSecure,
      value: jsonEncode(payload),
    );
  }

  List<ProxyProfile> _decodeManualProfiles(String? raw) {
    if (raw == null || raw.trim().isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded
          .whereType<Map>()
          .map((m) => ProxyProfile.fromJson(Map<String, dynamic>.from(m)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  List<AutoProfile> _decodeAutoProfiles(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded
          .whereType<Map>()
          .map((item) {
            try {
              final m = Map<String, dynamic>.from(item);
              final profile = ProxyProfile.fromJson(
                Map<String, dynamic>.from(m['profile'] as Map),
              );
              final inferred = KeyLoaderService.inferCountry(
                profile.name,
                profile.server,
              );
              final hasInferredCountry =
                  inferred.$1.isNotEmpty && inferred.$1 != 'XX';
              final countryCode = hasInferredCountry
                  ? inferred.$1
                  : (m['countryCode'] as String? ?? _rogerCode);
              final countryName = KeyLoaderService.toCyrillicCountryName(
                countryCode,
                hasInferredCountry
                    ? inferred.$2
                    : (m['countryName'] as String? ?? _rogerName),
              );
              return AutoProfile(
                profile: profile,
                countryCode: countryCode,
                countryName: countryName,
                flagEmoji: hasInferredCountry
                    ? inferred.$3
                    : (m['flagEmoji'] as String? ?? _rogerFlag),
                listType: (m['listType'] as String?) == 'white'
                    ? KeyListType.whiteList
                    : KeyListType.blackList,
              );
            } catch (_) {
              return null;
            }
          })
          .whereType<AutoProfile>()
          .toList();
    } catch (_) {
      return [];
    }
  }

  @override
  void dispose() {
    _connectWatchdog?.cancel();
    _stopRuntimeHealthMonitor();
    _cancelNetworkChangeHealthCheck();
    _temporaryPauseTimer?.cancel();
    _statusSub?.cancel();
    super.dispose();
  }

  void _handleTemporaryPauseFinished() {
    _temporaryPauseTimer = null;
    final shouldResume = _resumeAfterTemporaryPause;
    _temporaryPauseEndsAt = null;
    _resumeAfterTemporaryPause = false;

    if (shouldResume) {
      unawaited(toggleConnection(null));
      return;
    }

    notifyListeners();
  }

  void _cancelTemporaryPause({bool notify = true}) {
    _temporaryPauseTimer?.cancel();
    _temporaryPauseTimer = null;
    _temporaryPauseEndsAt = null;
    _resumeAfterTemporaryPause = false;
    if (notify) {
      notifyListeners();
    }
  }

  String _statusTextForMode(TunnelStatus incoming) {
    if (_connectionMode == AppConnectionMode.offlineDeblock) {
      switch (incoming.state) {
        case TunnelState.connecting:
          return incoming.statusText.isNotEmpty
              ? incoming.statusText
              : 'Запуск деблокера…';
        case TunnelState.connected:
          return _offlineDeblockProfile.runtimeStatus;
        case TunnelState.error:
          return 'Ошибка';
        case TunnelState.stopped:
          return 'Отключено';
      }
    }
    return incoming.statusText;
  }

  String _connectedStatusText() {
    if (_connectionMode == AppConnectionMode.offlineDeblock) {
      return _offlineDeblockProfile.runtimeStatus;
    }
    return TunnelState.connected.label;
  }



  Future<void> updateSmartRoutingDataset() async {
    final String path = await const MethodChannel('hex_decensor/singbox').invokeMethod('getAppDir');
    final appDir = Directory(path);
    try {
      await _smartRoutingService.updateRuleSet(appDir.path);
      if (_status.state == TunnelState.connected && _connectionMode == AppConnectionMode.tunnel && _routingMode == RoutingMode.smart) {
        // Restart tunnel to apply new rules
        await toggleConnection(null);
        await toggleConnection(null);
      }
    } catch (e) {
      debugPrint('Failed to update smart routing dataset: $e');
    }
  }

  Future<String?> _getSmartRoutingDatasetPath() async {
    if (_routingMode != RoutingMode.smart) return null;
    final String appDirPath = await const MethodChannel('hex_decensor/singbox').invokeMethod('getAppDir');
    final appDir = Directory(appDirPath);
    final path = '${appDir.path}/smart_routing_rules.json';
    if (File(path).existsSync()) return path;
    return null;
  }
}

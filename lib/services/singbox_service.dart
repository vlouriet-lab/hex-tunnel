import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../models/app_connection_mode.dart';
import '../models/deblocker_runtime_bundle.dart';
import '../models/installed_app.dart';
import '../models/offline_deblock_profile.dart';
import '../models/proxy_profile.dart';
import '../models/routing_mode.dart';
import '../models/routing_runtime_policy.dart';
import '../models/split_tunneling.dart';
import '../models/tunnel_status.dart';
import '../config/singbox_config_generator.dart';

class ConnectivityProbeResult {
  final bool ok;
  final String reasonCode;

  const ConnectivityProbeResult({
    required this.ok,
    this.reasonCode = '',
  });

  static const success = ConnectivityProbeResult(ok: true);

  ConnectivityProbeResult fail(String code) {
    return ConnectivityProbeResult(ok: false, reasonCode: code);
  }

  static String reasonDescription(
    String code, {
    required bool requiresGovProbe,
  }) {
    switch (code) {
      case 'offline':
        return 'устройство без стабильного интернета';
      case 'dns_blocked':
        return 'DNS не отвечает через текущий маршрут';
      case 'egress_blocked':
        return 'DNS отвечает, но внешние TCP/HTTPS недоступны';
      case 'tcp_partial':
        return 'внешняя связность нестабильна (частичный TCP)';
      case 'gov_blocked':
        return requiresGovProbe
            ? 'доступ к gov-ресурсам блокируется текущим маршрутом'
            : 'доступ к целевым ресурсам блокируется текущим маршрутом';
      case 'gov_partial':
        return requiresGovProbe
            ? 'доступ к gov-ресурсам нестабилен (частичный успех)'
            : 'доступ к целевым ресурсам нестабилен';
      default:
        return 'причина деградации не определена';
    }
  }
}

/// Сервис взаимодействия с Android-слоем sing-box через MethodChannel и EventChannel.
class SingBoxService {
  static const Duration _startTimeout = Duration(seconds: 20);
  static const Duration _statusTimeout = Duration(seconds: 3);
  static const Duration _healthCheckTimeout = Duration(seconds: 5);
  static int _sessionCounter = 0;

  static const _methodChannel = MethodChannel('hex_decensor/singbox');
  static const _statusChannel = EventChannel('hex_decensor/status');

  // ── Стрим статусов ────────────────────────────────────────────────────────

  Stream<TunnelStatus> get statusStream {
    return _statusChannel.receiveBroadcastStream().map((event) {
      if (event is Map) {
        final map = Map<String, dynamic>.from(event);
        return TunnelStatus.fromStatusString(
          map['status'] as String? ?? 'stopped',
          error: map['error'] as String? ?? '',
          activeServer: map['server'] as String? ?? '',
          activeProtocol: map['protocol'] as String? ?? '',
          latencyMs: map['latencyMs'] as int? ?? -1,
          errorCode: map['errorCode'] as String? ?? '',
          stage: map['stage'] as String? ?? '',
          networkEventId: (map['networkEventId'] as num?)?.toInt() ?? 0,
          networkInterface: map['networkInterface'] as String? ?? '',
          networkTransport: map['networkTransport'] as String? ?? '',
          networkOperator: map['networkOperator'] as String? ?? '',
        );
      }
      return const TunnelStatus();
    });
  }

  // ── Управление туннелем ───────────────────────────────────────────────────

  /// Запустить туннель с указанным профилем и режимом маршрутизации.
  /// Может запросить разрешение VPN у пользователя.
  Future<bool> start(
    ProxyProfile profile,
    RoutingMode routingMode,
    SplitTunnelingMode splitMode,
    List<String> packageNames, {
    RoutingRuntimePolicy? routingRuntimePolicy,
    bool enableCoreUrltest = false,
    List<ProxyProfile>? coreUrltestCandidates,
    bool enableTlsUtlsFingerprintSpoofing = true,
    String? smartRoutingDatasetPath,
    String? notificationRegion,
  }) async {
    final sessionId = _nextSessionId(connectionMode: AppConnectionMode.tunnel);
    final privateDnsHostname = await getPrivateDnsHostname();
    final privateDnsAddresses =
        await resolvePrivateDnsAddresses(privateDnsHostname);
    final privateDnsServer = privateDnsAddresses
        .where((ip) => !ip.contains(':'))
        .cast<String?>()
        .firstWhere((ip) => ip != null, orElse: () => null);
    final config = SingBoxConfigGenerator.generate(
      profile,
      routingMode,
      routingRuntimePolicy: routingRuntimePolicy,
      enableCoreUrltest: enableCoreUrltest,
      coreUrltestCandidates: coreUrltestCandidates,
      enableTlsUtlsFingerprintSpoofing: enableTlsUtlsFingerprintSpoofing,
      privateDnsHostname: privateDnsHostname,
      privateDnsServer: privateDnsServer,
      privateDnsResolvedIps: privateDnsAddresses,
      smartRoutingDatasetPath: smartRoutingDatasetPath,
    );
    return _startConfigured(
      sessionId: sessionId,
      config: config,
      splitMode: splitMode,
      packageNames: packageNames,
      privateDnsServer: privateDnsServer,
      privateDnsHostname: privateDnsHostname,
      connectionMode: AppConnectionMode.tunnel,
      notificationRegion: notificationRegion,
    );
  }

  Future<bool> startOfflineDeblock(
    OfflineDeblockProfile profile, {
    OfflineDeblockSettings? settings,
    DeblockerRuntimeBundle? runtimeBundle,
    String? notificationRegion,
  }) async {
    final sessionId = _nextSessionId(
      connectionMode: AppConnectionMode.offlineDeblock,
    );
    final privateDnsHostname = await getPrivateDnsHostname();
    final privateDnsAddresses =
        await resolvePrivateDnsAddresses(privateDnsHostname);
    final privateDnsServer = privateDnsAddresses
        .where((ip) => !ip.contains(':'))
        .cast<String?>()
        .firstWhere((ip) => ip != null, orElse: () => null);
    final config = SingBoxConfigGenerator.generateOfflineDeblock(
      profile,
      settings: settings,
      runtimeBundle: runtimeBundle,
      privateDnsHostname: privateDnsHostname,
      privateDnsServer: privateDnsServer,
      privateDnsResolvedIps: privateDnsAddresses,
    );
    return _startConfigured(
      sessionId: sessionId,
      config: config,
      splitMode: SplitTunnelingMode.off,
      packageNames: const <String>[],
      privateDnsServer: privateDnsServer,
      privateDnsHostname: privateDnsHostname,
      connectionMode: AppConnectionMode.offlineDeblock,
      offlineDeblockSettingsJson:
          settings == null ? null : jsonEncode(settings.toJson()),
      offlineDeblockRuntimeBundleJson:
          runtimeBundle == null ? null : jsonEncode(runtimeBundle.toJson()),
      notificationRegion: notificationRegion,
    );
  }

  Future<bool> _startConfigured({
    required String sessionId,
    required String config,
    required SplitTunnelingMode splitMode,
    required List<String> packageNames,
    required String? privateDnsServer,
    required String? privateDnsHostname,
    required AppConnectionMode connectionMode,
    String? offlineDeblockSettingsJson,
    String? offlineDeblockRuntimeBundleJson,
    String? notificationRegion,
  }) async {
    try {
      debugPrint(
          'SingBoxService.start sessionId=$sessionId mode=${connectionMode.key}');
      final result = await _methodChannel.invokeMethod<bool>(
        'start',
        {
          'sessionId': sessionId,
          'config': config,
          'splitMode': splitMode.key,
          'packageNames': packageNames,
          'privateDnsServer': privateDnsServer,
          'privateDnsHostname': privateDnsHostname,
          'connectionMode': connectionMode.key,
          'offlineDeblockSettings': offlineDeblockSettingsJson,
          'offlineDeblockRuntimeBundle': offlineDeblockRuntimeBundleJson,
          'notificationRegion': notificationRegion,
        },
      ).timeout(_startTimeout);
      return result ?? false;
    } on PlatformException catch (e) {
      debugPrint(
          'SingBoxService.start failed sessionId=$sessionId code=${e.code}');
      if (e.code == 'VPN_PERMISSION_DENIED') return false;
      rethrow;
    } on TimeoutException {
      debugPrint('SingBoxService.start timeout sessionId=$sessionId');
      throw PlatformException(
        code: 'METHOD_CHANNEL_TIMEOUT',
        message: 'Таймаут запуска туннеля (${_startTimeout.inSeconds}с)',
      );
    }
  }

  String _nextSessionId({required AppConnectionMode connectionMode}) {
    _sessionCounter += 1;
    final mode = connectionMode == AppConnectionMode.offlineDeblock
        ? 'offline'
        : 'tunnel';
    return '$mode-${DateTime.now().millisecondsSinceEpoch}-$_sessionCounter';
  }

  /// Остановить туннель.
  Future<bool> stop() async {
    final result = await _methodChannel.invokeMethod<bool>('stop');
    return result ?? false;
  }

  /// Проверить, запущен ли туннель.
  Future<bool> isRunning() async {
    try {
      final result = await _methodChannel
          .invokeMethod<bool>('isRunning')
          .timeout(_statusTimeout);
      return result ?? false;
    } on TimeoutException {
      debugPrint(
        'SingBoxService.isRunning timeout after ${_statusTimeout.inSeconds}s',
      );
      return false;
    } catch (e, st) {
      debugPrint('SingBoxService.isRunning error: $e\n$st');
      return false;
    }
  }

  /// Получить текущий статус (единоразово).
  Future<TunnelStatus> getStatus() async {
    try {
      final map =
          await _methodChannel.invokeMapMethod<String, dynamic>('getStatus');
      if (map == null) return const TunnelStatus();
      return TunnelStatus.fromStatusString(
        map['status'] as String? ?? 'stopped',
        error: map['error'] as String? ?? '',
        activeServer: map['server'] as String? ?? '',
        activeProtocol: map['protocol'] as String? ?? '',
        latencyMs: map['latencyMs'] as int? ?? -1,
        errorCode: map['errorCode'] as String? ?? '',
        stage: map['stage'] as String? ?? '',
        networkEventId: (map['networkEventId'] as num?)?.toInt() ?? 0,
        networkInterface: map['networkInterface'] as String? ?? '',
        networkTransport: map['networkTransport'] as String? ?? '',
        networkOperator: map['networkOperator'] as String? ?? '',
      );
    } catch (e, st) {
      debugPrint('SingBoxService.getStatus error: $e\n$st');
      return const TunnelStatus();
    }
  }

  /// Измерить TCP-задержку до сервера.
  Future<int> testLatency(String server, int port) async {
    try {
      final result = await _methodChannel.invokeMethod<int>(
        'testLatency',
        {'server': server, 'port': port},
      );
      return result ?? -1;
    } catch (e, st) {
      debugPrint('SingBoxService.testLatency error: $e\n$st');
      return -1;
    }
  }

  /// Проверка здоровья туннеля: TCP probe к google.com через TUN.
  /// Если VPN активен, трафик идёт через TUN → sing-box → proxy.
  /// Возвращает true, если трафик проходит через прокси.
  static Future<bool> healthCheck() async {
    return _probeHost('google.com', 443);
  }

  /// Проверяет, что после подключения реально доступен внешний интернет.
  ///
  /// Использует несколько независимых HTTPS endpoints разных провайдеров,
  /// чтобы не путать деградацию конкретного вендора с потерей реальной
  /// связности через туннель.
  Future<ConnectivityProbeResult> probePublicInternetDetailed() async {
    const targets = <String>[
      'https://www.google.com/generate_204',
      'https://clients3.google.com/generate_204',
      'https://connectivitycheck.gstatic.com/generate_204',
      'https://cp.cloudflare.com/generate_204',
      'https://www.msftconnecttest.com/connecttest.txt',
    ];

    var dnsSuccess = false;
    if (await _probeDns('connectivitycheck.gstatic.com')) {
      dnsSuccess = true;
    }
    if (!dnsSuccess && await _probeDns('cp.cloudflare.com')) {
      dnsSuccess = true;
    }

    for (final target in targets) {
      final ok = await _probeHttp(target);
      if (ok) return ConnectivityProbeResult.success;
    }

    const tcpFallbackTargets = <(String, int)>[
      ('1.1.1.1', 443),
      ('8.8.8.8', 443),
      ('9.9.9.9', 443),
    ];
    var tcpSuccessCount = 0;
    for (final target in tcpFallbackTargets) {
      final ok = await _probeHost(target.$1, target.$2);
      if (ok) {
        tcpSuccessCount += 1;
      }
      if (tcpSuccessCount >= 2) {
        return ConnectivityProbeResult.success;
      }
    }

    if (!dnsSuccess && tcpSuccessCount == 0) {
      return const ConnectivityProbeResult(ok: false, reasonCode: 'offline');
    }
    if (!dnsSuccess && tcpSuccessCount > 0) {
      return const ConnectivityProbeResult(ok: false, reasonCode: 'dns_blocked');
    }
    if (dnsSuccess && tcpSuccessCount == 0) {
      return const ConnectivityProbeResult(
        ok: false,
        reasonCode: 'egress_blocked',
      );
    }
    return const ConnectivityProbeResult(ok: false, reasonCode: 'tcp_partial');
  }

  Future<bool> healthCheckPublicInternet() async {
    final result = await probePublicInternetDetailed();
    return result.ok;
  }

  Future<bool> healthCheckGoogle() async => healthCheckPublicInternet();

  /// Быстрая проверка базовой связности устройства (вне оценки конкретного ключа).
  ///
  /// Нужна для отличия ситуации "сервер недоступен" от "устройство оффлайн".
  Future<bool> hasBaselineConnectivity() async {
    if (await _probeDns('connectivitycheck.gstatic.com')) {
      return true;
    }
    if (await _probeDns('cp.cloudflare.com')) {
      return true;
    }

    const tcpTargets = <(String, int)>[
      ('1.1.1.1', 443),
      ('8.8.8.8', 443),
    ];
    for (final target in tcpTargets) {
      if (await _probeHost(target.$1, target.$2)) {
        return true;
      }
    }
    return false;
  }

  /// Проверяет доступность ключевых российских гос-доменов через активный туннель.
  ///
  /// Валидация сертификата намеренно ослаблена, так как часть гос-сайтов может
  /// иметь нестандартную TLS-цепочку, а нам важна именно фактическая доступность.
  Future<ConnectivityProbeResult> probeRussianGovResourcesDetailed() async {
    const targets = <String>[
      'https://sozd.duma.gov.ru',
      'https://duma.gov.ru',
      'https://www.gosuslugi.ru',
      'https://esia.gosuslugi.ru',
    ];

    var successCount = 0;
    for (final target in targets) {
      final ok = await _probeHttp(
        target,
        allowBadCertificate: true,
      );
      if (ok) {
        successCount += 1;
      }
    }

    // Требуем хотя бы 2 успешные проверки, чтобы отсеять случайные флапы.
    if (successCount >= 2) {
      return ConnectivityProbeResult.success;
    }

    if (successCount == 1) {
      return const ConnectivityProbeResult(ok: false, reasonCode: 'gov_partial');
    }

    final baselineOk = await hasBaselineConnectivity();
    if (!baselineOk) {
      return const ConnectivityProbeResult(ok: false, reasonCode: 'offline');
    }
    return const ConnectivityProbeResult(ok: false, reasonCode: 'gov_blocked');
  }

  Future<bool> healthCheckRussianGovResources() async {
    final result = await probeRussianGovResourcesDetailed();
    return result.ok;
  }

  static Future<bool> _probeHttp(
    String url, {
    bool allowBadCertificate = false,
  }) async {
    HttpClient? client;
    try {
      client = HttpClient()
        ..connectionTimeout = _healthCheckTimeout
        ..badCertificateCallback = (cert, host, port) => allowBadCertificate;
      final request =
          await client.getUrl(Uri.parse(url)).timeout(_healthCheckTimeout);
      request.followRedirects = false;
      request.headers.set(HttpHeaders.userAgentHeader, 'HexTunnel/1.0');
      final response = await request.close().timeout(_healthCheckTimeout);
      await response.drain<void>();
      return response.statusCode >= 200 && response.statusCode < 400;
    } catch (_) {
      return false;
    } finally {
      client?.close(force: true);
    }
  }

  static Future<bool> _probeHost(String host, int port) async {
    try {
      final socket = await Socket.connect(
        host,
        port,
        timeout: _healthCheckTimeout,
      );
      await socket.close();
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> _probeDns(String host) async {
    try {
      final resolved = await InternetAddress.lookup(host)
          .timeout(_healthCheckTimeout);
      return resolved.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<List<InstalledApp>> getInstalledApps() async {
    try {
      final result = await _methodChannel.invokeMethod<List<dynamic>>(
        'getInstalledApps',
      );
      if (result == null) return const [];
      return result
          .whereType<Map>()
          .map((entry) => InstalledApp.fromJson(
                Map<String, dynamic>.from(entry),
              ))
          .toList(growable: false);
    } catch (e, st) {
      debugPrint('SingBoxService.getInstalledApps error: $e\n$st');
      return const [];
    }
  }

  Future<String?> getPrivateDnsHostname() async {
    try {
      final map = await _methodChannel.invokeMapMethod<String, dynamic>(
        'getPrivateDnsConfig',
      );
      if (map == null) return null;
      final mode = (map['mode'] as String? ?? '').trim();
      final specifier = (map['specifier'] as String? ?? '').trim();
      if (mode == 'hostname' && specifier.isNotEmpty) {
        return specifier;
      }
    } catch (e, st) {
      debugPrint('SingBoxService.getPrivateDnsHostname error: $e\n$st');
    }
    return null;
  }

  Future<List<String>> resolvePrivateDnsAddresses(String? hostname) async {
    if (hostname == null || hostname.trim().isEmpty) return const [];
    try {
      final addresses = await InternetAddress.lookup(hostname.trim());
      return addresses
          .map((address) => address.address)
          .where((ip) => ip.isNotEmpty)
          .toSet()
          .toList(growable: false);
    } catch (e, st) {
      debugPrint('SingBoxService.resolvePrivateDnsAddresses error: $e\n$st');
      return const [];
    }
  }
}

import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../models/deblocker_runtime_bundle.dart';
import '../models/offline_deblock_profile.dart';
import '../models/proxy_profile.dart';
import '../models/routing_mode.dart';
import '../models/routing_runtime_policy.dart';

/// Генератор JSON-конфигурации для sing-box.
/// Порт логики генерации из SingBoxConfig.h (SOTA Segment).
///
/// Генерирует полный конфиг в формате sing-box для TUN-режима на Android.
class SingBoxConfigGenerator {
  SingBoxConfigGenerator._();

  /// Сгенерировать конфиг sing-box для профиля с указанным режимом маршрутизации.
  static String generate(
    ProxyProfile profile,
    RoutingMode routingMode, {
    RoutingRuntimePolicy? routingRuntimePolicy,
    bool enableCoreUrltest = false,
    List<ProxyProfile>? coreUrltestCandidates,
    bool enableTlsUtlsFingerprintSpoofing = true,
    String? privateDnsHostname,
    String? privateDnsServer,
    List<String>? privateDnsResolvedIps,
    String? smartRoutingDatasetPath,
    String? logOutputPath,
  }) {
    final useCoreUrltest =
        enableCoreUrltest && (coreUrltestCandidates?.isNotEmpty ?? false);
    final proxyOutboundTag = useCoreUrltest ? 'auto' : 'proxy';
    final resolvedRoutingPolicy =
      _resolveRoutingRuntimePolicy(routingRuntimePolicy);
    final config = {
      'log': _buildLog(logOutputPath: logOutputPath),
      'dns': _buildDns(
        routingMode,
      routingPolicy: resolvedRoutingPolicy,
        proxyServer: profile.server,
        remoteDetour: proxyOutboundTag,
        privateDnsHostname: privateDnsHostname,
        privateDnsResolvedIps: privateDnsResolvedIps,
      ),
      'inbounds': _buildInbounds(),
      'outbounds': _buildOutbounds(
        profile,
        enableCoreUrltest: useCoreUrltest,
        coreUrltestCandidates: coreUrltestCandidates,
        enableTlsUtlsFingerprintSpoofing: enableTlsUtlsFingerprintSpoofing,
      ),
      'route': _buildRoute(
        routingMode,
        routingPolicy: resolvedRoutingPolicy,
        proxyOutboundTag: proxyOutboundTag,
        privateDnsHostname: privateDnsHostname,
        privateDnsServer: privateDnsServer,
        privateDnsResolvedIps: privateDnsResolvedIps,
        smartRoutingDatasetPath: smartRoutingDatasetPath,
      ),
      'experimental': {
        'cache_file': {
          'enabled': true,
          'path': 'cache.db',
          'store_fakeip': true,
          'store_rdrc': true,
        }
      },
    };
    return const JsonEncoder.withIndent('  ').convert(config);
  }

  static String generateOfflineDeblock(
    OfflineDeblockProfile profile, {
    OfflineDeblockSettings? settings,
    DeblockerRuntimeBundle? runtimeBundle,
    String? privateDnsHostname,
    String? privateDnsServer,
    List<String>? privateDnsResolvedIps,
    String? logOutputPath,
  }) {
    final effectiveSettings =
        settings ?? OfflineDeblockSettings.forProfile(profile);
    final effectiveProfile = runtimeBundle?.profilePreset ?? profile;
    final deliveryMode = runtimeBundle?.deliveryMode;
    final allowlistedIngressActive =
        deliveryMode == DeblockerDeliveryMode.allowlistedIngress &&
            (runtimeBundle?.ingressConfig?.isConfigured ?? false);
    final warpActive = deliveryMode == null
        ? effectiveSettings.wantsWarpDetour &&
            effectiveSettings.hasWarpWireguardConfig
        : deliveryMode == DeblockerDeliveryMode.warpHybridLegacy &&
            effectiveSettings.wantsWarpDetour &&
            effectiveSettings.hasWarpWireguardConfig;
    final config = <String, dynamic>{
      'log': _buildLog(logOutputPath: logOutputPath),
      'dns': _buildOfflineDeblockDns(
        effectiveProfile,
        settings: effectiveSettings,
        runtimeBundle: runtimeBundle,
        allowlistedIngressActive: allowlistedIngressActive,
        warpActive: warpActive,
        privateDnsHostname: privateDnsHostname,
      ),
      'inbounds': _buildInbounds(offlineDeblockSettings: effectiveSettings),
      'outbounds': _buildOfflineDeblockOutbounds(
        settings: effectiveSettings,
        runtimeBundle: runtimeBundle,
        allowlistedIngressActive: allowlistedIngressActive,
        warpActive: warpActive,
      ),
    };

    if (warpActive) {
      config['endpoints'] = _buildOfflineDeblockEndpoints(
        settings: effectiveSettings,
      );
    }

    config['route'] = _buildOfflineDeblockRoute(
      effectiveProfile,
      settings: effectiveSettings,
      runtimeBundle: runtimeBundle,
      allowlistedIngressActive: allowlistedIngressActive,
      warpActive: warpActive,
      privateDnsHostname: privateDnsHostname,
      privateDnsServer: privateDnsServer,
      privateDnsResolvedIps: privateDnsResolvedIps,
    );
    config['experimental'] = {
      'cache_file': {
        'enabled': true,
        'path': 'cache.db',
        'store_fakeip': true,
        'store_rdrc': true,
      }
    };
    return const JsonEncoder.withIndent('  ').convert(config);
  }

  // ── Log ──────────────────────────────────────────────────────────────────

  static Map<String, dynamic> _buildLog({String? logOutputPath}) {
    final log = <String, dynamic>{
      'level': kReleaseMode ? 'warn' : 'debug',
      'timestamp': true,
    };
    if (logOutputPath != null && logOutputPath.isNotEmpty) {
      log['output'] = logOutputPath;
    }
    return log;
  }

  // ── DNS ───────────────────────────────────────────────────────────────────

  static Map<String, dynamic> _buildDns(
    RoutingMode mode, {
    required RoutingRuntimePolicy routingPolicy,
    String proxyServer = '',
    String remoteDetour = 'proxy',
    String? privateDnsHostname,
    List<String>? privateDnsResolvedIps,
  }) {
    final servers = <Map<String, dynamic>>[
      // DoH (DNS over HTTPS) напрямую — порт 443, ISP не блокирует.
      // Используем IP-адрес чтобы избежать bootstrap-рекурсии.
      {
        'tag': 'dns-direct',
        'address': 'https://1.1.1.1/dns-query',
        'strategy': 'prefer_ipv4',
        'detour': 'direct',
      },
      // DoH через прокси — для проксируемого трафика.
      {
        'tag': 'dns-remote',
        'address': 'https://1.1.1.1/dns-query',
        'strategy': 'prefer_ipv4',
        'detour': remoteDetour,
      },
    ];

    final rules = <Map<String, dynamic>>[];

    // Адрес прокси-сервера резолвится напрямую, чтобы избежать рекурсии
    if (proxyServer.isNotEmpty) {
      rules.add({
        'domain': [proxyServer],
        'server': 'dns-direct',
      });
    }

    if (privateDnsHostname != null && privateDnsHostname.trim().isNotEmpty) {
      rules.add({
        'domain': [privateDnsHostname.trim()],
        'server': 'dns-direct',
      });
    }

    if (routingPolicy.forceDirectDomains.isNotEmpty) {
      rules.add({
        'domain': routingPolicy.forceDirectDomains,
        'server': 'dns-direct',
      });
    }

    if (routingPolicy.forceProxyDomains.isNotEmpty) {
      rules.add({
        'domain': routingPolicy.forceProxyDomains,
        'server': 'dns-remote',
      });
    }

    if (mode == RoutingMode.ruleBased || mode == RoutingMode.ruleBasedRu) {
      rules.add({
        'domain_suffix': routingPolicy.ruDomainSuffixes,
        'server': mode == RoutingMode.ruleBasedRu ? 'dns-remote' : 'dns-direct',
      });
    }

    // Bootstrap-правило добавляем последним, чтобы более специфичные
    // domain/domain_suffix правила отрабатывали раньше.
    rules.add({
      'outbound': 'any',
      'server': 'dns-direct',
    });

    return <String, dynamic>{
      'servers': servers,
      'rules': rules,
      'final': 'dns-direct',
      'independent_cache': true,
      'strategy': 'prefer_ipv4',
    };
  }

  static Map<String, dynamic> _buildOfflineDeblockDns(
    OfflineDeblockProfile profile, {
    required OfflineDeblockSettings settings,
    DeblockerRuntimeBundle? runtimeBundle,
    required bool allowlistedIngressActive,
    required bool warpActive,
    String? privateDnsHostname,
  }) {
    final dnsDetour =
        warpActive && settings.warpDetourMode == 'dns_only' ? 'warp' : 'direct';
    final ingressConfig = runtimeBundle?.ingressConfig;
    final servers = <Map<String, dynamic>>[
      _buildOfflineDnsServer('dns-cf', '1.1.1.1', detour: dnsDetour),
      _buildOfflineDnsServer('dns-google', '8.8.8.8', detour: dnsDetour),
      _buildOfflineDnsServer('dns-quad9', '9.9.9.9', detour: dnsDetour),
      {
        'tag': 'dns-local',
        'address': 'local',
        'detour': 'direct',
      },
      {
        'tag': 'dns-block',
        'address': 'rcode://success',
      },
    ];

    final rules = <Map<String, dynamic>>[
      {
        'domain_suffix': ['.local', '.localhost'],
        'server': 'dns-local',
      },
    ];

    if (privateDnsHostname != null && privateDnsHostname.trim().isNotEmpty) {
      rules.add({
        'domain': [privateDnsHostname.trim()],
        'server': 'dns-local',
      });
    }

    if (allowlistedIngressActive &&
        ingressConfig != null &&
        ingressConfig.edgeHost.trim().isNotEmpty) {
      rules.add({
        'domain': [ingressConfig.edgeHost.trim()],
        'server': _offlineDeblockPrimaryDnsTag(profile),
      });
    }

    if (settings.blockDnsHttpsSvcb) {
      rules.add({
        'query_type': settings.blockDnsAaaa ? [28, 64, 65] : [64, 65],
        'server': 'dns-block',
      });
    } else if (settings.blockDnsAaaa) {
      rules.add({
        'query_type': [28],
        'server': 'dns-block',
      });
    }

    rules.add({
      'outbound': 'any',
      'server': _offlineDeblockPrimaryDnsTag(profile),
    });

    return <String, dynamic>{
      'servers': servers,
      'rules': rules,
      'final': _offlineDeblockPrimaryDnsTag(profile),
      'independent_cache': false,
      'cache_capacity': 4096,
      'reverse_mapping': true,
      'strategy': 'prefer_ipv4',
    };
  }

  // ── Inbounds ──────────────────────────────────────────────────────────────

  static List<Map<String, dynamic>> _buildInbounds({
    OfflineDeblockSettings? offlineDeblockSettings,
  }) =>
      [
        {
          'type': 'tun',
          'tag': 'tun-in',
          'address': [
            '172.19.0.1/30',
            'fdfe:dcba:9876::1/126',
          ],
          'mtu': _tunMtuForSettings(offlineDeblockSettings),
          'auto_route': true,
          'strict_route': true,
          'stack': 'mixed',
          'sniff': true,
          'sniff_override_destination':
              offlineDeblockSettings?.sniffOverrideDestination ?? false,
        },
      ];

  // ── Outbounds ─────────────────────────────────────────────────────────────

  static List<Map<String, dynamic>> _buildOutbounds(
    ProxyProfile p, {
    bool enableCoreUrltest = false,
    List<ProxyProfile>? coreUrltestCandidates,
    bool enableTlsUtlsFingerprintSpoofing = true,
  }) {
    final outbounds = <Map<String, dynamic>>[];
    if (enableCoreUrltest) {
      outbounds.addAll(
        _buildCoreUrltestPool(
          coreUrltestCandidates ?? [p],
          enableTlsUtlsFingerprintSpoofing: enableTlsUtlsFingerprintSpoofing,
        ),
      );
    } else {
      outbounds.add(
        _buildProxyOutbound(
          p,
          enableTlsUtlsFingerprintSpoofing: enableTlsUtlsFingerprintSpoofing,
        ),
      );
    }
    outbounds.addAll([
      {
        'type': 'direct',
        'tag': 'direct',
        'tcp_fast_open': true,
        'tcp_multi_path': true,
      },
      {'type': 'block', 'tag': 'block'},
    ]);
    return outbounds;
  }

  static List<Map<String, dynamic>> _buildCoreUrltestPool(
    List<ProxyProfile> candidates, {
    bool enableTlsUtlsFingerprintSpoofing = true,
  }) {
    final unique = <String>{};
    final pool = <ProxyProfile>[];
    for (final p in candidates) {
      final key = p.rawUri.isNotEmpty
          ? p.rawUri
          : '${p.protocol}|${p.server}|${p.port}|${p.transport}|${p.sni}';
      if (unique.add(key)) {
        pool.add(p);
      }
      if (pool.length >= 5) {
        break;
      }
    }

    if (pool.isEmpty) {
      return [
        _buildProxyOutbound(
          candidates.first,
          tag: 'proxy',
          enableTlsUtlsFingerprintSpoofing: enableTlsUtlsFingerprintSpoofing,
        )
      ];
    }

    final proxyTags = <String>[];
    final outbounds = <Map<String, dynamic>>[];
    for (var i = 0; i < pool.length; i++) {
      final tag = 'proxy-${i + 1}';
      proxyTags.add(tag);
      outbounds.add(
        _buildProxyOutbound(
          pool[i],
          tag: tag,
          enableTlsUtlsFingerprintSpoofing: enableTlsUtlsFingerprintSpoofing,
        ),
      );
    }

    outbounds.add({
      'type': 'urltest',
      'tag': 'auto',
      'outbounds': proxyTags,
      'url': 'https://www.gstatic.com/generate_204',
      'interval': '2m',
      'tolerance': 100,
      'interrupt_exist_connections': true,
    });
    return outbounds;
  }

  static List<Map<String, dynamic>> _buildOfflineDeblockEndpoints({
    required OfflineDeblockSettings settings,
  }) {
    final localAddressV4 = OfflineDeblockSettings.normalizeWarpInterfaceAddress(
      settings.warpLocalAddressV4,
    );
    final localAddressV6 = OfflineDeblockSettings.normalizeWarpInterfaceAddress(
      settings.warpLocalAddressV6,
    );
    final localAddress = <String>[
      if (localAddressV4.isNotEmpty) localAddressV4,
      if (localAddressV6.isNotEmpty) localAddressV6,
    ];

    final allowedIps = <String>[
      '0.0.0.0/0',
      if (localAddressV6.isNotEmpty) '::/0',
    ];

    final cfIps = [
      '162.159.192.1',
      '162.159.192.5',
      '162.159.193.1',
      '162.159.193.5',
      '188.114.96.1',
      '188.114.97.1',
    ];
    final cfPorts = [2408, 500, 4500, 1701];

    final endpoints = <Map<String, dynamic>>[];
    int index = 0;

    for (final ip in cfIps) {
      for (final port in cfPorts) {
        endpoints.add({
          'type': 'wireguard',
          'tag': 'warp-$index',
          'address': localAddress,
          'private_key': settings.warpPrivateKey.trim(),
          'peers': [
            {
              'address': ip,
              'port': port,
              'public_key': settings.warpPeerPublicKey.trim(),
              'allowed_ips': allowedIps,
              'persistent_keepalive_interval': 30,
            }
          ],
          'mtu': 1280,
          'detour': 'direct',
          'domain_resolver': 'dns-cf',
        });
        index++;
      }
    }

    return endpoints;
  }

  static List<Map<String, dynamic>> _buildOfflineDeblockOutbounds({
    required OfflineDeblockSettings settings,
    DeblockerRuntimeBundle? runtimeBundle,
    required bool allowlistedIngressActive,
    required bool warpActive,
  }) {
    final outbounds = <Map<String, dynamic>>[
      {
        'type': 'direct',
        'tag': 'direct',
        'tcp_fast_open': true,
        'tcp_multi_path': true,
      },
      {'type': 'block', 'tag': 'block'},
    ];
    if (allowlistedIngressActive && runtimeBundle?.ingressConfig != null) {
      outbounds.add(
        _buildAllowlistedIngressOutbound(runtimeBundle!.ingressConfig!),
      );
    }
    if (!warpActive) {
      return outbounds;
    }

    // Generate warp outbound tags to use in urltest
    final warpOutboundTags = <String>[];
    int index = 0;
    final cfIps = [
      '162.159.192.1',
      '162.159.192.5',
      '162.159.193.1',
      '162.159.193.5',
      '188.114.96.1',
      '188.114.97.1',
    ];
    final cfPorts = [2408, 500, 4500, 1701];

    for (var _ in cfIps) {
      for (var _ in cfPorts) {
        warpOutboundTags.add('warp-$index');
        index++;
      }
    }

    outbounds.add({
      'type': 'urltest',
      'tag': 'warp',
      'outbounds': warpOutboundTags,
      'url': 'http://cp.cloudflare.com/generate_204',
      'interval': '1m',
      'tolerance': 50,
    });

    return outbounds;
  }



  static Map<String, dynamic> _buildAllowlistedIngressOutbound(
    DeblockerIngressConfig config,
  ) {
    final outboundType = config.outboundType.trim().toLowerCase();
    late final Map<String, dynamic> outbound;

    switch (outboundType) {
      case 'vless':
        outbound = <String, dynamic>{
          'type': 'vless',
          'tag': 'ingress',
          'server': config.edgeHost.trim(),
          'server_port': config.edgePort,
          'uuid': config.uuid.trim(),
          'tls': _buildAllowlistedIngressTls(config),
        };
        break;
      case 'trojan':
      default:
        outbound = <String, dynamic>{
          'type': 'trojan',
          'tag': 'ingress',
          'server': config.edgeHost.trim(),
          'server_port': config.edgePort,
          'password': config.password.trim(),
          'tls': _buildAllowlistedIngressTls(config),
        };
        break;
    }

    outbound['transport'] = _buildAllowlistedIngressTransport(config);
    outbound.removeWhere((_, value) => value == null);
    return outbound;
  }
  static Map<String, dynamic> _buildAllowlistedIngressTls(
    DeblockerIngressConfig config,
  ) {
    final alpn = config.alpn
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
    
    final tls = <String, dynamic>{
      'enabled': true,
      'server_name': _resolveIngressSni(config),
      'insecure': config.skipCertVerify,
      if (alpn.isNotEmpty) 'alpn': alpn,
      'utls': {
        'enabled': true,
        'fingerprint': _resolveIngressFingerprint(config),
      },
    };

    if (config.realityEnabled) {
      tls['reality'] = {
        'enabled': true,
        'public_key': config.realityPublicKey,
        'short_id': config.realityShortId,
      };
    }

    if (config.echEnabled) {
      tls['ech'] = {
        'enabled': true,
      };
    }

    return tls;
  }

  static Map<String, dynamic> _buildAllowlistedIngressTransport(
    DeblockerIngressConfig config,
  ) {
    final path = _normalizeIngressPath(config.path);
    final hostHeader = _resolveIngressHostHeader(config);
    switch (config.transport.trim().toLowerCase()) {
      case 'grpc':
        return {
          'type': 'grpc',
          'service_name': config.grpcServiceName.trim().isNotEmpty
              ? config.grpcServiceName.trim()
              : path.replaceFirst('/', ''),
        };
      case 'httpupgrade':
        return {
          'type': 'httpupgrade',
          'host': hostHeader,
          'path': path,
          'headers': {
            'User-Agent': _kChromeUserAgent,
          },
        };
      case 'h2':
        return {
          'type': 'http',
          'host': [hostHeader],
          'path': path,
        };
      case 'ws':
      default:
        return {
          'type': 'ws',
          'path': path,
          'headers': <String, dynamic>{
            'Host': hostHeader,
            'User-Agent': _kChromeUserAgent,
          },
        };
    }
  }

  static Map<String, dynamic> _buildProxyOutbound(
    ProxyProfile p, {
    String tag = 'proxy',
    bool enableTlsUtlsFingerprintSpoofing = true,
  }) {
    late final Map<String, dynamic> outbound;
    switch (p.protocol) {
      case 'vless':
        outbound = _buildVless(
          p,
          enableTlsUtlsFingerprintSpoofing: enableTlsUtlsFingerprintSpoofing,
        );
        break;
      case 'shadowsocks':
        outbound = _buildShadowsocks(p);
        break;
      case 'trojan':
        outbound = _buildTrojan(
          p,
          enableTlsUtlsFingerprintSpoofing: enableTlsUtlsFingerprintSpoofing,
        );
        break;
      case 'tuic':
        outbound = _buildTuic(p);
        break;
      case 'vmess':
        outbound = _buildVmess(
          p,
          enableTlsUtlsFingerprintSpoofing: enableTlsUtlsFingerprintSpoofing,
        );
        break;
      case 'hysteria':
        outbound = _buildHysteria(p);
        break;
      case 'hysteria2':
        outbound = _buildHysteria2(p);
        break;
      case 'shadowsocksr':
        outbound = _buildShadowsocksR(p);
        break;
      case 'wireguard':
        outbound = _buildWireGuard(p);
        break;
      case 'awg':
        outbound = _buildAmneziaWG(p);
        break;
      case 'socks':
        outbound = _buildSocks(p);
        break;
      case 'http':
        outbound = _buildHttpProxy(
          p,
          enableTlsUtlsFingerprintSpoofing: enableTlsUtlsFingerprintSpoofing,
        );
        break;
      case 'ssh':
        outbound = _buildSsh(p);
        break;
      default:
        outbound = {'type': 'direct', 'tag': 'proxy'};
        break;
    }
    outbound['tag'] = tag;
    return outbound;
  }

  static Map<String, dynamic> _buildVless(
    ProxyProfile p, {
    bool enableTlsUtlsFingerprintSpoofing = true,
  }) {
    final outbound = <String, dynamic>{
      'type': 'vless',
      'tag': 'proxy',
      'server': p.server,
      'server_port': p.port,
      'uuid': p.uuid,
      'flow': p.flow.isNotEmpty ? p.flow : null,
    };

    outbound['tls'] = _buildTlsOptions(
      p,
      enableTlsUtlsFingerprintSpoofing: enableTlsUtlsFingerprintSpoofing,
    );
    if (p.transport != 'tcp') {
      outbound['transport'] = _buildTransport(p);
    }

    outbound.removeWhere((_, v) => v == null);
    return outbound;
  }

  static Map<String, dynamic> _buildShadowsocks(ProxyProfile p) => {
        'type': 'shadowsocks',
        'tag': 'proxy',
        'server': p.server,
        'server_port': p.port,
        'method': p.method,
        'password': p.password,
      };

  static Map<String, dynamic> _buildTrojan(
    ProxyProfile p, {
    bool enableTlsUtlsFingerprintSpoofing = true,
  }) {
    final outbound = <String, dynamic>{
      'type': 'trojan',
      'tag': 'proxy',
      'server': p.server,
      'server_port': p.port,
      'password': p.password,
      'tls': _buildTlsOptions(
        p,
        enableTlsUtlsFingerprintSpoofing: enableTlsUtlsFingerprintSpoofing,
      ),
    };

    if (p.transport != 'tcp') {
      outbound['transport'] = _buildTransport(p);
    }
    return outbound;
  }

  static Map<String, dynamic> _buildTuic(ProxyProfile p) {
    final alpnList = p.alpn.isNotEmpty
        ? p.alpn.split(',').map((s) => s.trim()).toList()
        : ['h3'];
    return {
      'type': 'tuic',
      'tag': 'proxy',
      'server': p.server,
      'server_port': p.port,
      'uuid': p.uuid,
      'password': p.password,
      'congestion_control': p.congestionControl,
      'udp_relay_mode': p.udpRelayMode,
      'tls': {
        'enabled': true,
        'server_name': p.sni.isNotEmpty ? p.sni : p.server,
        'alpn': alpnList,
      },
    };
  }

  // ── VMess ─────────────────────────────────────────────────────────────────

  static Map<String, dynamic> _buildVmess(
    ProxyProfile p, {
    bool enableTlsUtlsFingerprintSpoofing = true,
  }) {
    final outbound = <String, dynamic>{
      'type': 'vmess',
      'tag': 'proxy',
      'server': p.server,
      'server_port': p.port,
      'uuid': p.uuid,
      'security': p.security.isNotEmpty ? p.security : 'auto',
      'alter_id': p.alterId,
    };
    if (p.tls) {
      outbound['tls'] = _buildTlsOptions(
        p,
        enableTlsUtlsFingerprintSpoofing: enableTlsUtlsFingerprintSpoofing,
      );
    }
    if (p.transport != 'tcp') {
      outbound['transport'] = _buildTransport(p);
    }
    outbound.removeWhere((_, v) => v == null);
    return outbound;
  }

  // ── Hysteria ──────────────────────────────────────────────────────────────

  static Map<String, dynamic> _buildHysteria(ProxyProfile p) {
    final outbound = <String, dynamic>{
      'type': 'hysteria',
      'tag': 'proxy',
      'server': p.server,
      'server_port': p.port,
      'up_mbps': p.upMbps > 0 ? p.upMbps : 100,
      'down_mbps': p.downMbps > 0 ? p.downMbps : 100,
      'tls': {
        'enabled': true,
        'server_name': p.sni.isNotEmpty ? p.sni : p.server,
        'insecure': p.insecure,
        if (p.alpn.isNotEmpty)
          'alpn': p.alpn.split(',').map((s) => s.trim()).toList(),
      },
    };
    if (p.password.isNotEmpty) outbound['auth_str'] = p.password;
    if (p.obfsPassword.isNotEmpty) outbound['obfs'] = p.obfsPassword;
    return outbound;
  }

  // ── Hysteria2 ─────────────────────────────────────────────────────────────

  static Map<String, dynamic> _buildHysteria2(ProxyProfile p) {
    final outbound = <String, dynamic>{
      'type': 'hysteria2',
      'tag': 'proxy',
      'server': p.server,
      'server_port': p.port,
      'password': p.password,
      'tls': {
        'enabled': true,
        'server_name': p.sni.isNotEmpty ? p.sni : p.server,
        'insecure': p.insecure,
        if (p.alpn.isNotEmpty)
          'alpn': p.alpn.split(',').map((s) => s.trim()).toList(),
      },
    };
    if (p.obfsPassword.isNotEmpty) {
      outbound['obfs'] = {
        'type': 'salamander',
        'password': p.obfsPassword,
      };
    }
    return outbound;
  }

  // ── ShadowsocksR ──────────────────────────────────────────────────────────

  static Map<String, dynamic> _buildShadowsocksR(ProxyProfile p) => {
        'type': 'shadowsocksr',
        'tag': 'proxy',
        'server': p.server,
        'server_port': p.port,
        'method': p.method,
        'password': p.password,
        'obfs': p.ssrObfs,
        'obfs_param': p.ssrObfsParam,
        'protocol': p.ssrProtocol,
        'protocol_param': p.ssrProtocolParam,
      };

  // ── WireGuard ─────────────────────────────────────────────────────────────

  static Map<String, dynamic> _buildWireGuard(ProxyProfile p) {
    final localAddresses = p.wgLocalAddresses.isNotEmpty
        ? p.wgLocalAddresses
            .split(',')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList()
        : ['10.0.0.2/32'];
    final outbound = <String, dynamic>{
      'type': 'wireguard',
      'tag': 'proxy',
      'local_address': localAddresses,
      'private_key': p.wgPrivateKey,
      'peers': [
        {
          'server': p.server,
          'server_port': p.port,
          'public_key': p.wgPeerPublicKey,
        }
      ],
      'mtu': p.wgMtu > 0 ? p.wgMtu : 1408,
    };
    if (p.wgPreSharedKey.isNotEmpty) {
      outbound['pre_shared_key'] = p.wgPreSharedKey;
    }
    return outbound;
  }

  // ── AmneziaWG ─────────────────────────────────────────────────────────────

  static Map<String, dynamic> _buildAmneziaWG(ProxyProfile p) {
    final outbound = _buildWireGuard(p);
    if (p.wgJunkPacketCount > 0) {
      outbound['junk_packet_count'] = p.wgJunkPacketCount;
      outbound['junk_packet_min_size'] = p.wgJunkPacketMinSize;
      outbound['junk_packet_max_size'] = p.wgJunkPacketMaxSize;
    }
    if (p.wgInitPacketJunkSize > 0) {
      outbound['init_packet_junk_size'] = p.wgInitPacketJunkSize;
    }
    if (p.wgResponsePacketJunkSize > 0) {
      outbound['response_packet_junk_size'] = p.wgResponsePacketJunkSize;
    }
    if (p.wgInitPacketMagicHeader > 0) {
      outbound['init_packet_magic_header'] = p.wgInitPacketMagicHeader;
    }
    if (p.wgResponsePacketMagicHeader > 0) {
      outbound['response_packet_magic_header'] = p.wgResponsePacketMagicHeader;
    }
    if (p.wgTransportPacketMagicHeader > 0) {
      outbound['transport_packet_magic_header'] =
          p.wgTransportPacketMagicHeader;
    }
    if (p.wgUnderloadPacketMagicHeader > 0) {
      outbound['underload_packet_magic_header'] =
          p.wgUnderloadPacketMagicHeader;
    }
    if (p.wgReserved.isNotEmpty) {
      final parts = p.wgReserved.split(',');
      if (parts.length == 3) {
        outbound['reserved'] =
            parts.map((s) => int.tryParse(s.trim()) ?? 0).toList();
      }
    }
    return outbound;
  }

  // ── SOCKS5 ────────────────────────────────────────────────────────────────

  static Map<String, dynamic> _buildSocks(ProxyProfile p) {
    final outbound = <String, dynamic>{
      'type': 'socks',
      'tag': 'proxy',
      'server': p.server,
      'server_port': p.port,
      'version': '5',
    };
    if (p.user.isNotEmpty) {
      outbound['username'] = p.user;
      outbound['password'] = p.password;
    }
    return outbound;
  }

  // ── HTTP Proxy ────────────────────────────────────────────────────────────

  static Map<String, dynamic> _buildHttpProxy(
    ProxyProfile p, {
    bool enableTlsUtlsFingerprintSpoofing = true,
  }) {
    final outbound = <String, dynamic>{
      'type': 'http',
      'tag': 'proxy',
      'server': p.server,
      'server_port': p.port,
    };
    if (p.user.isNotEmpty) {
      outbound['username'] = p.user;
      outbound['password'] = p.password;
    }
    if (p.tls) {
      outbound['tls'] = _buildTlsOptions(
        p,
        enableTlsUtlsFingerprintSpoofing: enableTlsUtlsFingerprintSpoofing,
      );
    }
    return outbound;
  }

  // ── SSH ───────────────────────────────────────────────────────────────────

  static Map<String, dynamic> _buildSsh(ProxyProfile p) {
    final outbound = <String, dynamic>{
      'type': 'ssh',
      'tag': 'proxy',
      'server': p.server,
      'server_port': p.port,
      'user': p.user.isNotEmpty ? p.user : 'root',
    };
    if (p.sshPrivateKey.isNotEmpty) {
      outbound['private_key'] = p.sshPrivateKey;
    } else if (p.password.isNotEmpty) {
      outbound['password'] = p.password;
    }
    if (p.sshHostKeyAlgo.isNotEmpty) {
      outbound['host_key_algorithms'] = [p.sshHostKeyAlgo];
    }
    return outbound;
  }

  // ── TLS / Reality ─────────────────────────────────────────────────────────

  static Map<String, dynamic> _buildTlsOptions(
    ProxyProfile p, {
    bool enableTlsUtlsFingerprintSpoofing = true,
  }) {
    if (!p.tls) return {'enabled': false};

    final tls = <String, dynamic>{
      'enabled': true,
      'server_name': p.sni.isNotEmpty ? p.sni : p.server,
    };

    if (enableTlsUtlsFingerprintSpoofing) {
      tls['utls'] = {
        'enabled': true,
        'fingerprint': _resolveUtlsFingerprint(p),
      };
    }

    if (p.alpn.isNotEmpty) {
      tls['alpn'] = p.alpn.split(',').map((s) => s.trim()).toList();
    }

    if (p.reality) {
      tls['reality'] = {
        'enabled': true,
        'public_key': p.realityPublicKey,
        'short_id': p.realityShortId,
      };
    }

    return tls;
  }

  // ── Transport ─────────────────────────────────────────────────────────────

  // Chrome 131 на Windows — наиболее распространённый User-Agent.
  static const _kChromeUserAgent = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
      'AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/131.0.0.0 Safari/537.36';
  static const _kCommonFingerprints = <String>[
    'chrome',
    'firefox',
    'safari',
    'edge',
  ];

  static String _resolveUtlsFingerprint(ProxyProfile p) {
    final requested = p.fingerprint.trim().toLowerCase();
    if (requested.isNotEmpty && requested != 'random') {
      return requested;
    }

    final entropy =
        '${p.server}|${p.port}|${DateTime.now().millisecondsSinceEpoch ~/ 60000}';
    final idx = entropy.hashCode.abs() % _kCommonFingerprints.length;
    return _kCommonFingerprints[idx];
  }

  static String _resolveHostHeader(ProxyProfile p) {
    if (p.wsHost.isNotEmpty) {
      return p.wsHost;
    }
    if (p.sni.isNotEmpty) {
      return p.sni;
    }
    return p.server;
  }

  static String _resolveIngressHostHeader(DeblockerIngressConfig config) {
    if (config.hostHeader.trim().isNotEmpty) {
      return config.hostHeader.trim();
    }
    if (config.sni.trim().isNotEmpty) {
      return config.sni.trim();
    }
    return config.edgeHost.trim();
  }

  static String _resolveIngressSni(DeblockerIngressConfig config) {
    if (config.sni.trim().isNotEmpty) {
      return config.sni.trim();
    }
    if (config.hostHeader.trim().isNotEmpty) {
      return config.hostHeader.trim();
    }
    return config.edgeHost.trim();
  }

  static String _resolveIngressFingerprint(DeblockerIngressConfig config) {
    final requested = config.fingerprint.trim().toLowerCase();
    if (requested.isEmpty || requested == 'random') {
      return 'chrome';
    }
    return requested;
  }

  static String _normalizeIngressPath(String rawPath) {
    final trimmed = rawPath.trim();
    if (trimmed.isEmpty) {
      return '/';
    }
    return trimmed.startsWith('/') ? trimmed : '/$trimmed';
  }

  static Map<String, dynamic> _buildTransport(ProxyProfile p) {
    switch (p.transport) {
      case 'ws':
        return {
          'type': 'ws',
          'path': p.wsPath.isNotEmpty ? p.wsPath : '/',
          'headers': <String, dynamic>{
            'Host': _resolveHostHeader(p),
            'User-Agent': _kChromeUserAgent,
          },
        };
      case 'grpc':
        return {
          'type': 'grpc',
          'service_name': p.grpcServiceName,
        };
      case 'xhttp':
        // В sing-box используем HTTPUpgrade как ближайший stealth-аналог xhttp.
        // На уровне провайдера дополнительно включён тихий fallback на WS.
        return {
          'type': 'httpupgrade',
          'host': _resolveHostHeader(p),
          'path': p.wsPath.isNotEmpty ? p.wsPath : '/',
          'headers': {
            'User-Agent': _kChromeUserAgent,
          },
        };
      case 'h2':
        return {
          'type': 'http',
          'host': [p.sni.isNotEmpty ? p.sni : p.server],
          'path': '/',
        };
      default:
        return {'type': p.transport};
    }
  }

  // ── Route ─────────────────────────────────────────────────────────────────

  static Map<String, dynamic> _buildRoute(
    RoutingMode mode, {
    required RoutingRuntimePolicy routingPolicy,
    String proxyOutboundTag = 'proxy',
    String? privateDnsHostname,
    String? privateDnsServer,
    List<String>? privateDnsResolvedIps,
    String? smartRoutingDatasetPath,
  }) {
    final rules = <Map<String, dynamic>>[];

    // DNS-пакеты перехватываются sing-box и обрабатываются через dns-секцию.
    // hijack-dns позволяет sing-box самому резолвить запросы через dns-direct
    // или dns-remote согласно правилам, вместо пересылки сырого UDP/TCP,
    // что устраняет зависание protect()-сокетов при port-53 forwarding.
    rules.add({
      'network': ['udp', 'tcp'],
      'port': [53],
      'action': 'hijack-dns',
    });

    rules.add({
      'ip_is_private': true,
      'outbound': 'direct',
    });

    if (privateDnsHostname != null && privateDnsHostname.trim().isNotEmpty) {
      rules.add({
        'domain': [privateDnsHostname.trim()],
        'outbound': 'direct',
      });
    }

    if (privateDnsServer != null && privateDnsServer.trim().isNotEmpty) {
      final dnsServer = privateDnsServer.trim();
      final prefix = dnsServer.contains(':') ? 128 : 32;
      rules.add({
        'ip_cidr': ['$dnsServer/$prefix'],
        'outbound': 'direct',
      });
    }

    // Route resolved IP addresses of Private DNS through direct outbound
    if (privateDnsResolvedIps != null && privateDnsResolvedIps.isNotEmpty) {
      final cidrList = privateDnsResolvedIps.map((ip) {
        final prefix = ip.contains(':') ? 128 : 32;
        return '$ip/$prefix';
      }).toList();
      rules.add({
        'ip_cidr': cidrList,
        'outbound': 'direct',
      });
    }

    if (routingPolicy.forceDirectDomains.isNotEmpty) {
      rules.add({
        'domain': routingPolicy.forceDirectDomains,
        'outbound': 'direct',
      });
    }

    if (routingPolicy.forceProxyDomains.isNotEmpty) {
      rules.add({
        'domain': routingPolicy.forceProxyDomains,
        'outbound': proxyOutboundTag,
      });
    }

    switch (mode) {
      case RoutingMode.global:
        // Весь трафик через прокси — нет дополнительных правил
        break;

      case RoutingMode.bypassLan:
        // Весь трафик через прокси, LAN напрямую — уже обработано ip_is_private
        break;

      case RoutingMode.smart:
        // Только заблокированные сайты (из датасета smart-routing) через прокси
        // Остальное напрямую
        if (smartRoutingDatasetPath != null) {
          rules.add({
            'rule_set': ['smart-routing'],
            'outbound': proxyOutboundTag,
          });
        }
        return {
          if (smartRoutingDatasetPath != null)
            'rule_set': [
              {
                'tag': 'smart-routing',
                'type': 'local',
                'format': 'source',
                'path': smartRoutingDatasetPath,
              }
            ],
          'rules': rules,
          'final': 'direct',
          'auto_detect_interface': true,
          'override_android_vpn': true,
        };

      case RoutingMode.ruleBased:
        // RU-домены — напрямую, остальное — через прокси
        rules.add({
          'domain_suffix': routingPolicy.ruDomainSuffixes,
          'outbound': 'direct',
        });
        break;

      case RoutingMode.ruleBasedRu:
        // RU-домены — через прокси, остальное — напрямую
        rules.add({
          'domain_suffix': routingPolicy.ruDomainSuffixes,
          'outbound': proxyOutboundTag,
        });
        // Финальный outbound для этого режима — direct
        return {
          'rules': rules,
          'final': 'direct',
          'auto_detect_interface': true,
          'override_android_vpn': true,
        };
    }


    return {
      if (smartRoutingDatasetPath != null)
        'rule_set': [
          {
            'tag': 'smart-routing',
            'type': 'local',
            'format': 'source',
            'path': smartRoutingDatasetPath,
          }
        ],
      'rules': rules,
      'final': proxyOutboundTag,
      'auto_detect_interface': true,
      'override_android_vpn': true,
    };
  }

  static Map<String, dynamic> _buildOfflineDeblockRoute(
    OfflineDeblockProfile profile, {
    required OfflineDeblockSettings settings,
    DeblockerRuntimeBundle? runtimeBundle,
    required bool allowlistedIngressActive,
    required bool warpActive,
    String? privateDnsHostname,
    String? privateDnsServer,
    List<String>? privateDnsResolvedIps,
  }) {
    final trafficPolicy = runtimeBundle?.trafficPolicy ??
        DeblockerTrafficPolicy.legacyForProfile(profile, settings);
    final ingressConfig = runtimeBundle?.ingressConfig;
    final detourOutbound =
        allowlistedIngressActive ? 'ingress' : (warpActive ? 'warp' : 'direct');
    final rules = <Map<String, dynamic>>[
      {
        'network': ['udp', 'tcp'],
        'port': [53],
        'action': 'hijack-dns',
      },
    ];

    if (trafficPolicy.allowDirectForPrivateIp) {
      rules.add({
        'ip_is_private': true,
        'outbound': 'direct',
      });
    }

    if (privateDnsHostname != null && privateDnsHostname.trim().isNotEmpty) {
      rules.add({
        'domain': [privateDnsHostname.trim()],
        'outbound': 'direct',
      });
    }

    if (privateDnsServer != null && privateDnsServer.trim().isNotEmpty) {
      final dnsServer = privateDnsServer.trim();
      final prefix = dnsServer.contains(':') ? 128 : 32;
      rules.add({
        'ip_cidr': ['$dnsServer/$prefix'],
        'outbound': 'direct',
      });
    }

    if (privateDnsResolvedIps != null && privateDnsResolvedIps.isNotEmpty) {
      final cidrList = privateDnsResolvedIps.map((ip) {
        final prefix = ip.contains(':') ? 128 : 32;
        return '$ip/$prefix';
      }).toList();
      rules.add({
        'ip_cidr': cidrList,
        'outbound': 'direct',
      });
    }

    if (allowlistedIngressActive &&
        ingressConfig != null &&
        ingressConfig.edgeHost.trim().isNotEmpty) {
      rules.add({
        'domain': [ingressConfig.edgeHost.trim()],
        'outbound': 'direct',
      });
    }

    if (settings.blockUdp443) {
      rules.add({
        'network': ['udp'],
        'port': [443],
        'outbound': 'block',
      });
    }

    if (settings.blockIpv6) {
      rules.add({
        'ip_version': 6,
        'outbound': 'block',
      });
    }

    if (settings.blockAllUdp) {
      rules.add({
        'network': ['udp'],
        'outbound': 'block',
      });
    }

    if (trafficPolicy.directExactDomains.isNotEmpty) {
      rules.add({
        'domain': trafficPolicy.directExactDomains,
        'outbound': 'direct',
      });
    }

    if (trafficPolicy.directDomainSuffixes.isNotEmpty) {
      rules.add({
        'domain_suffix': trafficPolicy.directDomainSuffixes,
        'outbound': 'direct',
      });
    }

    if (allowlistedIngressActive &&
        trafficPolicy.ingressExactDomains.isNotEmpty) {
      rules.add({
        'domain': trafficPolicy.ingressExactDomains,
        'outbound': detourOutbound,
      });
    }

    if (allowlistedIngressActive &&
        trafficPolicy.ingressDomainSuffixes.isNotEmpty) {
      rules.add({
        'domain_suffix': trafficPolicy.ingressDomainSuffixes,
        'outbound': detourOutbound,
      });
    }

    if (allowlistedIngressActive &&
        trafficPolicy.fallbackToIngressForUnknownHttps) {
      rules.add({
        'network': ['tcp'],
        'port': [443],
        'outbound': detourOutbound,
      });
    }

    if (warpActive && settings.warpDetourMode == 'hybrid') {
      rules.add({
        'domain_suffix': _ruDomainSuffix,
        'outbound': 'direct',
      });
      rules.add({
        'network': ['tcp'],
        'port': [80, 443],
        'outbound': 'warp',
      });
    }

    final finalOutbound =
        warpActive && settings.warpDetourMode == 'all' ? 'warp' : 'direct';

    return {
      'rules': rules,
      'final': finalOutbound,
      'auto_detect_interface': true,
      'override_android_vpn': true,
    };
  }

  // ── Constants ─────────────────────────────────────────────────────────────

  static RoutingRuntimePolicy _resolveRoutingRuntimePolicy(
    RoutingRuntimePolicy? runtimePolicy,
  ) {
    final source = runtimePolicy;
    if (source == null) {
      return const RoutingRuntimePolicy(ruDomainSuffixes: _ruDomainSuffix);
    }
    final suffixes = source.ruDomainSuffixes.isEmpty
        ? _ruDomainSuffix
        : source.ruDomainSuffixes;
    return source.copyWith(ruDomainSuffixes: suffixes);
  }

  static const List<String> _ruDomainSuffix = [
    '.ru',
    '.рф',
    '.su',
    '.moscow',
    '.tatar',
  ];

  static Map<String, dynamic> _buildOfflineDnsServer(
    String tag,
    String ip, {
    String detour = 'direct',
  }) =>
      {
        'tag': tag,
        'address': 'https://$ip/dns-query',
        'strategy': 'prefer_ipv4',
        'detour': detour,
      };

  static String _offlineDeblockPrimaryDnsTag(OfflineDeblockProfile profile) {
    switch (profile) {
      case OfflineDeblockProfile.soft:
        return 'dns-cf';
      case OfflineDeblockProfile.balanced:
        return 'dns-google';
      case OfflineDeblockProfile.hybrid:
        return 'dns-cf';
      case OfflineDeblockProfile.aggressive:
      case OfflineDeblockProfile.ultra:
      case OfflineDeblockProfile.custom:
        return 'dns-quad9';
    }
  }

  static int _tunMtuForSettings(OfflineDeblockSettings? settings) {
    if (settings == null) {
      return 1400;
    }
    final mtu = settings.mtu;
    if (mtu < 1200) {
      return 1200;
    }
    if (mtu > 1500) {
      return 1500;
    }
    return mtu;
  }
}

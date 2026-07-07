import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hex_decensor/config/singbox_config_generator.dart';
import 'package:hex_decensor/models/deblocker_runtime_bundle.dart';
import 'package:hex_decensor/models/offline_deblock_profile.dart';
import 'package:hex_decensor/services/deblocker_bundle_integrity_service.dart';
import 'package:hex_decensor/services/deblocker_ingress_bundle_service.dart';
import 'package:hex_decensor/services/deblocker_transport_validation_service.dart';

void main() {
  group('Deblocker synthetic smoke', () {
    const ingressService = DeblockerIngressBundleService();
    const integrityService = DeblockerBundleIntegrityService();

    test('bundled seed bootstrap is integrity-valid but not rollout-ready', () {
      final settings = OfflineDeblockSettings.forProfile(
        OfflineDeblockProfile.balanced,
      );
      final result = ingressService.bootstrap(
        cachedBundle: null,
        profilePreset: OfflineDeblockProfile.balanced,
        settings: settings,
      );

      expect(result.source, 'bundled_seed');
      expect(result.bundle.isBootstrapSeedBundle, isTrue);
      expect(result.integrity.isValid, isTrue);
      expect(ingressService.isBundleUsable(result.bundle), isFalse);
      expect(result.bundle.shouldRefreshFromControlPlane, isTrue);
    });

    test('remote ingress bundle with integrity metadata is rollout-ready', () {
      final bundle = integrityService.attachIntegrityMetadata(
        _buildAllowlistedBundle(),
      );

      expect(bundle.isBootstrapSeedBundle, isFalse);
      expect(bundle.shouldRefreshFromControlPlane, isFalse);
      expect(ingressService.isBundleUsable(bundle), isTrue);
      expect(
        ingressService.validateBundle(bundle)?.isValid,
        isTrue,
      );
    });

    test(
        'service selects alternative ingress endpoint when primary is excluded',
        () {
      final primary = _buildIngressConfig(
        edgeHost: 'edge-a.example.com',
        password: 'secret-a',
      );
      final secondary = _buildIngressConfig(
        edgeHost: 'edge-b.example.com',
        password: 'secret-b',
      );

      final selected = ingressService.selectIngressConfigFromPayload(
        <String, dynamic>{
          'ingressEndpoints': <Map<String, dynamic>>[
            primary.toJson(),
            secondary.toJson(),
          ],
        },
        sourceName: 'control_plane',
        excludedIngressConfigs: <DeblockerIngressConfig>[primary],
      );

      expect(selected, isNotNull);
      expect(selected!.edgeHost, 'edge-b.example.com');
      expect(selected.password, 'secret-b');
    });

    test('allowlisted ingress generator emits ingress outbound and route rules',
        () {
      final bundle = integrityService.attachIntegrityMetadata(
        _buildAllowlistedBundle(),
      );
      final config = jsonDecode(
        SingBoxConfigGenerator.generateOfflineDeblock(
          OfflineDeblockProfile.balanced,
          settings: bundle.settings,
          runtimeBundle: bundle,
          privateDnsHostname: 'dns.example.com',
          privateDnsServer: '94.140.14.14',
          privateDnsResolvedIps: const ['94.140.14.14'],
        ),
      ) as Map<String, dynamic>;

      final outbounds =
          (config['outbounds'] as List<dynamic>).cast<Map<String, dynamic>>();
      final ingressOutbound = outbounds.firstWhere(
        (entry) => entry['tag'] == 'ingress',
      );
      expect(ingressOutbound['type'], 'trojan');
      expect(ingressOutbound['server'], 'edge.example.com');
      expect(
          (ingressOutbound['transport'] as Map<String, dynamic>)['type'], 'ws');

      final route = config['route'] as Map<String, dynamic>;
      final rules =
          (route['rules'] as List<dynamic>).cast<Map<String, dynamic>>();

      expect(
        _hasRule(
          rules,
          (rule) =>
              _stringList(rule['domain']).contains('edge.example.com') &&
              rule['outbound'] == 'direct',
        ),
        isTrue,
      );
      expect(
        _hasRule(
          rules,
          (rule) =>
              _intList(rule['port']).contains(443) &&
              _stringList(rule['network']).contains('tcp') &&
              rule['outbound'] == 'ingress',
        ),
        isTrue,
      );
      expect(
        _hasRule(
          rules,
          (rule) =>
              _stringList(rule['domain_suffix']).contains('.ru') &&
              rule['outbound'] == 'direct',
        ),
        isTrue,
      );
    });

    test('legacy hybrid generator emits warp endpoint and web detour rules',
        () {
      final settings = OfflineDeblockSettings.fromJson({
        ...OfflineDeblockSettings.forProfile(
          OfflineDeblockProfile.hybrid,
        ).toJson(),
        'warpPrivateKey': 'test-private-key',
        'warpPeerPublicKey': 'test-peer-key',
        'warpLocalAddressV4': '172.16.0.2',
        'warpLocalAddressV6': '2606:4700:110:81a7:f6a0:b8b5:31ce:6561',
        'warpEndpointHost': 'engage.cloudflareclient.com:2408',
      });
      final bundle = DeblockerRuntimeBundle.legacy(
        profilePreset: OfflineDeblockProfile.hybrid,
        settings: settings,
      );

      final config = jsonDecode(
        SingBoxConfigGenerator.generateOfflineDeblock(
          OfflineDeblockProfile.hybrid,
          settings: settings,
          runtimeBundle: bundle,
        ),
      ) as Map<String, dynamic>;

      final endpoints =
          (config['endpoints'] as List<dynamic>).cast<Map<String, dynamic>>();
      final warpEndpoint = endpoints.firstWhere(
        (entry) => (entry['tag'] as String).startsWith('warp-'),
      );
      expect(warpEndpoint['type'], 'wireguard');
      final interfaceAddresses =
          (warpEndpoint['address'] as List<dynamic>).cast<String>();
      expect(interfaceAddresses, contains('172.16.0.2/32'));
      expect(
        interfaceAddresses,
        contains('2606:4700:110:81a7:f6a0:b8b5:31ce:6561/128'),
      );
      final peers =
          (warpEndpoint['peers'] as List<dynamic>).cast<Map<String, dynamic>>();
      expect(peers.single['address'], '162.159.192.1');
      expect(peers.single['port'], 2408);
      expect(
        _stringList(peers.single['allowed_ips']),
        contains('::/0'),
      );

      final route = config['route'] as Map<String, dynamic>;
      final rules =
          (route['rules'] as List<dynamic>).cast<Map<String, dynamic>>();
      expect(
        _hasRule(
          rules,
          (rule) =>
              _intList(rule['port']).contains(80) &&
              _intList(rule['port']).contains(443) &&
              rule['outbound'] == 'warp',
        ),
        isTrue,
      );
      expect(
        _hasRule(
          rules,
          (rule) =>
              _stringList(rule['domain_suffix']).contains('.ru') &&
              rule['outbound'] == 'direct',
        ),
        isTrue,
      );
    });

    test('transport validation rejects grpc ingress without service name', () {
      const validator = DeblockerTransportValidationService();
      const ingressConfig = DeblockerIngressConfig(
        enabled: true,
        provider: 'test',
        outboundType: 'vless',
        edgeHost: 'edge.example.com',
        edgePort: 443,
        transport: 'grpc',
        path: '/grpc',
        hostHeader: 'cdn.example.com',
        sni: 'cdn.example.com',
        alpn: <String>['h2'],
        grpcServiceName: '',
        username: '',
        password: '',
        uuid: '11111111-1111-1111-1111-111111111111',
        skipCertVerify: false,
        fingerprint: 'chrome',
        realityEnabled: false,
        realityPublicKey: '',
        realityShortId: '',
        echEnabled: false,
        allowDirectFallback: true,
        originHint: 'remote_control_plane',
        policyTag: 'strict',
        configVersion: 1,
        expiresAt: null,
      );

      final result = validator.validateConfig(ingressConfig);
      expect(result.isValid, isFalse);
      expect(
        result.issues.any((issue) => issue.code == 'missing_grpc_service'),
        isTrue,
      );
    });
  });
}

DeblockerIngressConfig _buildIngressConfig({
  required String edgeHost,
  required String password,
}) {
  return DeblockerIngressConfig(
    enabled: true,
    provider: 'control_plane',
    outboundType: 'trojan',
    edgeHost: edgeHost,
    edgePort: 443,
    transport: 'ws',
    path: '/deblock',
    hostHeader: 'cdn.example.com',
    sni: 'cdn.example.com',
    alpn: const <String>['h2', 'http/1.1'],
    grpcServiceName: '',
    username: '',
    password: password,
    uuid: '',
    skipCertVerify: false,
    fingerprint: 'chrome',
    realityEnabled: false,
    realityPublicKey: '',
    realityShortId: '',
    echEnabled: false,
    allowDirectFallback: true,
    originHint: 'remote_control_plane',
    policyTag: 'strict_v1',
    configVersion: 1,
    expiresAt: null,
  );
}

DeblockerRuntimeBundle _buildAllowlistedBundle() {
  final nowIso = DateTime.now().toUtc().toIso8601String();
  const settings = OfflineDeblockSettings(
    blockUdp443: true,
    blockAllUdp: false,
    blockIpv6: false,
    blockDnsHttpsSvcb: true,
    blockDnsAaaa: false,
    sniffOverrideDestination: false,
    mtu: 1360,
    tlsFragmentEnabled: true,
    tlsFragmentSize: 20,
    tlsFragmentSleepMs: 4,
    tlsMixedSniCase: true,
    tlsPaddingEnabled: true,
    tlsPaddingSize: 384,
    warpEnabled: false,
    warpDetourMode: 'off',
    warpLicenseKey: '',
    warpPrivateKey: '',
    warpPeerPublicKey: '',
    warpLocalAddressV4: '',
    warpLocalAddressV6: '',
    warpEndpointHost: '162.159.193.10',
    warpEndpointPort: 2408,
  );

  return DeblockerRuntimeBundle(
    profilePreset: OfflineDeblockProfile.balanced,
    deliveryMode: DeblockerDeliveryMode.allowlistedIngress,
    settings: settings,
    ingressConfig: const DeblockerIngressConfig(
      enabled: true,
      provider: 'control_plane',
      outboundType: 'trojan',
      edgeHost: 'edge.example.com',
      edgePort: 443,
      transport: 'ws',
      path: '/deblock',
      hostHeader: 'cdn.example.com',
      sni: 'cdn.example.com',
      alpn: <String>['h2', 'http/1.1'],
      grpcServiceName: '',
      username: '',
      password: 'secret-password',
      uuid: '',
      skipCertVerify: false,
      fingerprint: 'chrome',
      realityEnabled: false,
      realityPublicKey: '',
      realityShortId: '',
      echEnabled: false,
      allowDirectFallback: true,
      originHint: 'remote_control_plane',
      policyTag: 'strict_v1',
      configVersion: 1,
      expiresAt: null,
    ),
    trafficPolicy: const DeblockerTrafficPolicy(
      directDomainSuffixes: <String>['.ru'],
      directExactDomains: <String>['gosuslugi.ru'],
      ingressDomainSuffixes: <String>['.youtube.com'],
      ingressExactDomains: <String>['youtube.com'],
      fallbackToIngressForUnknownHttps: true,
      allowDirectForPrivateIp: true,
      blockUnsupportedUdp: true,
      blockIpv6WhenNeeded: false,
      policyVersion: 1,
    ),
    diagnosticPolicy: 'synthetic_smoke',
    createdAt: nowIso,
    ttlSeconds: 7 * 24 * 60 * 60,
    bundleVersion: 2,
    checksum: null,
    signature: null,
    refreshedAt: nowIso,
    bootstrapSource: 'remote_control_plane:test',
  );
}

bool _hasRule(
  List<Map<String, dynamic>> rules,
  bool Function(Map<String, dynamic> rule) matcher,
) {
  for (final rule in rules) {
    if (matcher(rule)) {
      return true;
    }
  }
  return false;
}

List<String> _stringList(dynamic value) {
  if (value is List) {
    return value.whereType<String>().toList(growable: false);
  }
  return const <String>[];
}

List<int> _intList(dynamic value) {
  if (value is List) {
    return value.whereType<num>().map((entry) => entry.toInt()).toList(
          growable: false,
        );
  }
  return const <int>[];
}

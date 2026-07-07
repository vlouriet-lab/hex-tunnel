import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import '../models/deblocker_runtime_bundle.dart';
import '../models/offline_deblock_profile.dart';
import 'deblocker_bundle_integrity_service.dart';

class DeblockerIngressBundleBootstrapResult {
  final DeblockerRuntimeBundle bundle;
  final bool didChange;
  final String source;
  final DeblockerBundleIntegrityResult integrity;
  final String? fallbackReason;

  const DeblockerIngressBundleBootstrapResult({
    required this.bundle,
    required this.didChange,
    required this.source,
    required this.integrity,
    required this.fallbackReason,
  });
}

class DeblockerIngressBundleRefreshResult {
  final DeblockerRuntimeBundle? bundle;
  final bool didChange;
  final String? source;
  final DeblockerBundleIntegrityResult? integrity;
  final String? failureReason;

  const DeblockerIngressBundleRefreshResult({
    required this.bundle,
    required this.didChange,
    required this.source,
    required this.integrity,
    required this.failureReason,
  });

  bool get isSuccess => bundle != null;
}

class DeblockerIngressBundleService {
  static const int _bundledBundleVersion = 1;
  static const int _bundledBundleTtlSeconds = 180 * 24 * 60 * 60;
  static const String _bundledSeedCreatedAt = '2026-04-13T00:00:00Z';
  static const int _maxRemotePayloadBytes = 256 * 1024;
  static const Duration _controlPlaneTimeout = Duration(seconds: 10);
  static const String _controlPlaneUrl = String.fromEnvironment(
    'HEX_DEBLOCKER_CONTROL_URL',
  );
  static const String _controlPlaneUrls = String.fromEnvironment(
    'HEX_DEBLOCKER_CONTROL_URLS',
  );

  final DeblockerBundleIntegrityService _integrity;

  const DeblockerIngressBundleService({
    DeblockerBundleIntegrityService integrityService =
        const DeblockerBundleIntegrityService(),
  }) : _integrity = integrityService;

  bool get hasConfiguredRemoteSources =>
      _configuredControlPlaneSources.isNotEmpty;

  DeblockerIngressConfig? selectIngressConfigFromPayload(
    Map<String, dynamic> payload, {
    required String sourceName,
    Iterable<DeblockerIngressConfig> excludedIngressConfigs =
        const <DeblockerIngressConfig>[],
  }) {
    return _selectIngressConfig(
      payload,
      sourceName: sourceName,
      excludedCandidateKeys:
          _buildExcludedIngressCandidateKeys(excludedIngressConfigs),
    );
  }

  bool isExcludedIngressConfig(
    DeblockerIngressConfig? candidate,
    Iterable<DeblockerIngressConfig> excludedIngressConfigs,
  ) {
    return _isExcludedIngressConfig(
      candidate,
      _buildExcludedIngressCandidateKeys(excludedIngressConfigs),
    );
  }

  DeblockerIngressBundleBootstrapResult bootstrap({
    DeblockerRuntimeBundle? cachedBundle,
    required OfflineDeblockProfile profilePreset,
    required OfflineDeblockSettings settings,
  }) {
    final bundledSeed = _buildBundledSeed(
      profilePreset: profilePreset,
      settings: settings,
    );

    String? fallbackReason;
    if (cachedBundle != null) {
      final normalizedCached = materializeBundle(
        cachedBundle,
        profilePreset: profilePreset,
        settings: settings,
        bootstrapSource: cachedBundle.bootstrapSource ?? 'cached',
      );
      final integrity = _integrity.validate(normalizedCached);
      final cacheIsUsable = isBundleUsable(
        normalizedCached,
        integrity: integrity,
      );

      if (cacheIsUsable &&
          normalizedCached.bundleVersion >= bundledSeed.bundleVersion) {
        return DeblockerIngressBundleBootstrapResult(
          bundle: normalizedCached,
          didChange: !_jsonEquals(cachedBundle, normalizedCached),
          source: normalizedCached.bootstrapSource ?? 'cached',
          integrity: integrity,
          fallbackReason: null,
        );
      }

      if (!integrity.isValid) {
        fallbackReason = integrity.status.key;
      } else if (normalizedCached.isExpired) {
        fallbackReason = 'expired';
      } else if (normalizedCached.ingressConfig?.isExpired ?? false) {
        fallbackReason = 'ingress_expired';
      } else if (normalizedCached.isBootstrapSeedBundle) {
        fallbackReason = 'seed_only';
      } else if (!normalizedCached.isAllowlistedIngressBundle) {
        fallbackReason = 'not_allowlisted_ingress';
      } else if (normalizedCached.bundleVersion < bundledSeed.bundleVersion) {
        fallbackReason = 'outdated';
      }
    }

    final seedIntegrity = _integrity.validate(bundledSeed);
    return DeblockerIngressBundleBootstrapResult(
      bundle: bundledSeed,
      didChange: !_jsonEquals(cachedBundle, bundledSeed),
      source: 'bundled_seed',
      integrity: seedIntegrity,
      fallbackReason: fallbackReason,
    );
  }

  Future<DeblockerIngressBundleRefreshResult> refreshFromControlPlane({
    DeblockerRuntimeBundle? cachedBundle,
    required OfflineDeblockProfile profilePreset,
    required OfflineDeblockSettings settings,
    Iterable<DeblockerIngressConfig> excludedIngressConfigs =
        const <DeblockerIngressConfig>[],
  }) async {
    final sources = _configuredControlPlaneSources;
    if (sources.isEmpty) {
      return const DeblockerIngressBundleRefreshResult(
        bundle: null,
        didChange: false,
        source: null,
        integrity: null,
        failureReason: 'control_endpoint_not_configured',
      );
    }

    final excludedCandidateKeys =
        _buildExcludedIngressCandidateKeys(excludedIngressConfigs);
    String? lastFailure;
    for (final source in sources) {
      try {
        final payload = await _fetchRemotePayload(source);
        var bundle = _decodeRemoteBundle(
          payload.body,
          profilePreset: profilePreset,
          settings: settings,
          sourceName: source.name,
          excludedCandidateKeys: excludedCandidateKeys,
        );
        bundle = materializeBundle(
          bundle.copyWith(
            deliveryMode: DeblockerDeliveryMode.allowlistedIngress,
            refreshedAt:
                bundle.refreshedAt ?? DateTime.now().toUtc().toIso8601String(),
            bootstrapSource: 'remote_control_plane:${source.name}',
          ),
          profilePreset: profilePreset,
          settings: settings,
          bootstrapSource: 'remote_control_plane:${source.name}',
        );

        if (_isExcludedIngressConfig(
          bundle.ingressConfig,
          excludedCandidateKeys,
        )) {
          lastFailure = '${source.name}: no_alternative_ingress_candidate';
          continue;
        }

        if ((bundle.checksum?.trim().isEmpty ?? true) &&
            payload.transportIntegrityVerified) {
          bundle = _integrity.attachIntegrityMetadata(bundle);
        }

        final integrity = _integrity.validate(bundle);
        if (!isBundleUsable(bundle, integrity: integrity)) {
          lastFailure =
              '${source.name}:${_bundleFailureReason(bundle, integrity)}';
          continue;
        }

        return DeblockerIngressBundleRefreshResult(
          bundle: bundle,
          didChange: !_jsonEquals(cachedBundle, bundle),
          source: source.name,
          integrity: integrity,
          failureReason: null,
        );
      } catch (e) {
        lastFailure = '${source.name}: $e';
      }
    }

    return DeblockerIngressBundleRefreshResult(
      bundle: null,
      didChange: false,
      source: null,
      integrity: null,
      failureReason: lastFailure ?? 'control_plane_unavailable',
    );
  }

  DeblockerRuntimeBundle materializeBundle(
    DeblockerRuntimeBundle bundle, {
    required OfflineDeblockProfile profilePreset,
    required OfflineDeblockSettings settings,
    String? bootstrapSource,
  }) {
    return bundle.copyWith(
      profilePreset: profilePreset,
      settings: settings,
      bootstrapSource: bootstrapSource ?? bundle.bootstrapSource,
    );
  }

  bool shouldRefreshFromControlPlane(
    DeblockerRuntimeBundle? bundle, {
    bool force = false,
  }) {
    if (!hasConfiguredRemoteSources) {
      return false;
    }
    if (force) {
      return true;
    }
    return bundle == null || bundle.shouldRefreshFromControlPlane;
  }

  bool isBundleUsable(
    DeblockerRuntimeBundle? bundle, {
    DeblockerBundleIntegrityResult? integrity,
  }) {
    if (bundle == null ||
        bundle.isExpired ||
        (bundle.ingressConfig?.isExpired ?? false) ||
        bundle.isBootstrapSeedBundle ||
        !bundle.isAllowlistedIngressBundle) {
      return false;
    }
    final actualIntegrity = integrity ?? _integrity.validate(bundle);
    return actualIntegrity.isValid;
  }

  DeblockerBundleIntegrityResult? validateBundle(
      DeblockerRuntimeBundle? bundle) {
    if (bundle == null) {
      return null;
    }
    return _integrity.validate(bundle);
  }

  DeblockerRuntimeBundle _buildBundledSeed({
    required OfflineDeblockProfile profilePreset,
    required OfflineDeblockSettings settings,
  }) {
    final bundle = DeblockerRuntimeBundle(
      profilePreset: profilePreset,
      deliveryMode: DeblockerDeliveryMode.allowlistedIngress,
      settings: settings,
      ingressConfig: const DeblockerIngressConfig(
        enabled: true,
        provider: 'bundled_seed',
        outboundType: 'trojan',
        edgeHost: 'one.one.one.one',
        edgePort: 443,
        transport: 'ws',
        path: '/hex/bootstrap',
        hostHeader: 'one.one.one.one',
        sni: 'one.one.one.one',
        alpn: <String>['h2', 'http/1.1'],
        grpcServiceName: '',
        username: '',
        password: 'phase3-seed-placeholder',
        uuid: '',
        skipCertVerify: false,
        fingerprint: 'chrome',
        realityEnabled: false,
        realityPublicKey: '',
        realityShortId: '',
        echEnabled: false,
        allowDirectFallback: true,
        originHint: 'phase2_seed_only',
        policyTag: 'seed_allowlisted_ingress_v1',
        configVersion: 1,
        expiresAt: null,
      ),
      trafficPolicy: _defaultTrafficPolicy(settings),
      diagnosticPolicy: 'phase2_seed_bootstrap',
      createdAt: _bundledSeedCreatedAt,
      ttlSeconds: _bundledBundleTtlSeconds,
      bundleVersion: _bundledBundleVersion,
      checksum: null,
      signature: null,
      refreshedAt: _bundledSeedCreatedAt,
      bootstrapSource: 'bundled_seed',
    );
    return _integrity.attachIntegrityMetadata(bundle);
  }

  bool _jsonEquals(DeblockerRuntimeBundle? left, DeblockerRuntimeBundle right) {
    if (left == null) {
      return false;
    }
    return jsonEncode(left.toJson()) == jsonEncode(right.toJson());
  }

  DeblockerTrafficPolicy _defaultTrafficPolicy(
    OfflineDeblockSettings settings,
  ) {
    return DeblockerTrafficPolicy(
      directDomainSuffixes: const ['.ru', '.рф', '.su', '.moscow', '.tatar'],
      directExactDomains: const <String>[],
      ingressDomainSuffixes: const <String>[],
      ingressExactDomains: const <String>[],
      fallbackToIngressForUnknownHttps: true,
      allowDirectForPrivateIp: true,
      blockUnsupportedUdp: settings.blockAllUdp || settings.blockUdp443,
      blockIpv6WhenNeeded: settings.blockIpv6,
      policyVersion: 1,
    );
  }

  List<_DeblockerIngressBundleSource> get _configuredControlPlaneSources {
    final values = <String>[
      _controlPlaneUrl,
      ..._controlPlaneUrls
          .split(RegExp(r'[\r\n,;]+'))
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty),
    ];
    final unique = <String>[];
    for (final value in values) {
      final trimmed = value.trim();
      if (trimmed.isEmpty || unique.contains(trimmed)) {
        continue;
      }
      unique.add(trimmed);
    }
    return List<_DeblockerIngressBundleSource>.generate(
      unique.length,
      (index) => _DeblockerIngressBundleSource(
        name: 'configured_${index + 1}',
        url: unique[index],
      ),
      growable: false,
    );
  }

  Future<_DeblockerRemoteBundlePayload> _fetchRemotePayload(
    _DeblockerIngressBundleSource source,
  ) async {
    final uri = Uri.tryParse(source.url);
    if (uri == null ||
        uri.scheme.toLowerCase() != 'https' ||
        uri.host.isEmpty) {
      throw FormatException('control plane URL must be absolute HTTPS');
    }

    final response = await http.get(uri).timeout(_controlPlaneTimeout);
    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}');
    }
    if (response.bodyBytes.length > _maxRemotePayloadBytes) {
      throw Exception(
        'payload exceeds ${_maxRemotePayloadBytes ~/ 1024}KB limit',
      );
    }

    final transportIntegrityVerified =
        await _verifyTransportIntegrity(uri, response.body);
    return _DeblockerRemoteBundlePayload(
      body: response.body,
      transportIntegrityVerified: transportIntegrityVerified,
    );
  }

  Future<bool> _verifyTransportIntegrity(Uri uri, String body) async {
    final shaUri = Uri.parse('${uri.toString()}.sha256');
    final response = await http.get(shaUri).timeout(_controlPlaneTimeout);
    if (response.statusCode == 404) {
      return false;
    }
    if (response.statusCode != 200) {
      throw Exception('sidecar HTTP ${response.statusCode}');
    }

    final expected = _extractSha256(response.body);
    if (expected == null) {
      throw const FormatException('invalid .sha256 sidecar');
    }

    final actual = sha256.convert(utf8.encode(body)).toString();
    if (actual != expected) {
      throw Exception('sidecar checksum mismatch');
    }
    return true;
  }

  DeblockerRuntimeBundle _decodeRemoteBundle(
    String body, {
    required OfflineDeblockProfile profilePreset,
    required OfflineDeblockSettings settings,
    required String sourceName,
    required Set<String> excludedCandidateKeys,
  }) {
    final decoded = jsonDecode(body);
    if (decoded is! Map) {
      throw const FormatException(
          'control plane payload must be a JSON object');
    }

    final payload = Map<String, dynamic>.from(decoded);
    if (!_isRolloutEnabled(payload)) {
      throw const FormatException('rollout disabled by control plane');
    }

    final nestedBundle = payload['bundle'];
    if (nestedBundle is Map<String, dynamic>) {
      final normalized = _normalizeRemoteBundle(
        DeblockerRuntimeBundle.fromJson(nestedBundle),
        sourceName: sourceName,
      );
      if (!_isExcludedIngressConfig(
        normalized.ingressConfig,
        excludedCandidateKeys,
      )) {
        return normalized;
      }
      final alternative = _tryBuildBundleFromPayloadV1(
        payload,
        profilePreset: profilePreset,
        settings: settings,
        sourceName: sourceName,
        excludedCandidateKeys: excludedCandidateKeys,
      );
      if (alternative != null) {
        return alternative;
      }
      throw const FormatException(
        'control plane payload does not contain an alternative ingress',
      );
    }
    if (nestedBundle is Map) {
      final normalized = _normalizeRemoteBundle(
        DeblockerRuntimeBundle.fromJson(
            Map<String, dynamic>.from(nestedBundle)),
        sourceName: sourceName,
      );
      if (!_isExcludedIngressConfig(
        normalized.ingressConfig,
        excludedCandidateKeys,
      )) {
        return normalized;
      }
      final alternative = _tryBuildBundleFromPayloadV1(
        payload,
        profilePreset: profilePreset,
        settings: settings,
        sourceName: sourceName,
        excludedCandidateKeys: excludedCandidateKeys,
      );
      if (alternative != null) {
        return alternative;
      }
      throw const FormatException(
        'control plane payload does not contain an alternative ingress',
      );
    }

    final looksLikeBundle = payload.containsKey('deliveryMode') ||
        payload.containsKey('trafficPolicy') ||
        payload.containsKey('ingressConfig');
    if (looksLikeBundle) {
      final normalized = _normalizeRemoteBundle(
        DeblockerRuntimeBundle.fromJson(payload),
        sourceName: sourceName,
      );
      if (!_isExcludedIngressConfig(
        normalized.ingressConfig,
        excludedCandidateKeys,
      )) {
        return normalized;
      }
      final alternative = _tryBuildBundleFromPayloadV1(
        payload,
        profilePreset: profilePreset,
        settings: settings,
        sourceName: sourceName,
        excludedCandidateKeys: excludedCandidateKeys,
      );
      if (alternative != null) {
        return alternative;
      }
      throw const FormatException(
        'control plane payload does not contain an alternative ingress',
      );
    }

    return _buildBundleFromPayloadV1(
      payload,
      profilePreset: profilePreset,
      settings: settings,
      sourceName: sourceName,
      excludedCandidateKeys: excludedCandidateKeys,
    );
  }

  DeblockerRuntimeBundle _normalizeRemoteBundle(
    DeblockerRuntimeBundle bundle, {
    required String sourceName,
  }) {
    final ingressConfig = bundle.ingressConfig;
    return bundle.copyWith(
      deliveryMode: DeblockerDeliveryMode.allowlistedIngress,
      ingressConfig: ingressConfig?.copyWith(
        provider: ingressConfig.provider.trim().isEmpty
            ? sourceName
            : ingressConfig.provider,
        originHint: ingressConfig.originHint.trim().isEmpty
            ? 'remote_control_plane'
            : ingressConfig.originHint,
      ),
      bootstrapSource: 'remote_control_plane:$sourceName',
    );
  }

  DeblockerRuntimeBundle _buildBundleFromPayloadV1(
    Map<String, dynamic> payload, {
    required OfflineDeblockProfile profilePreset,
    required OfflineDeblockSettings settings,
    required String sourceName,
    Set<String> excludedCandidateKeys = const <String>{},
  }) {
    final now = DateTime.now().toUtc();
    final ingressConfig = _selectIngressConfig(
      payload,
      sourceName: sourceName,
      excludedCandidateKeys: excludedCandidateKeys,
    );
    if (ingressConfig == null || !ingressConfig.isConfigured) {
      throw const FormatException('payload does not contain a usable ingress');
    }

    return DeblockerRuntimeBundle(
      profilePreset: profilePreset,
      deliveryMode: DeblockerDeliveryMode.allowlistedIngress,
      settings: settings,
      ingressConfig: ingressConfig,
      trafficPolicy: _parseTrafficPolicy(
        payload['trafficPolicy'],
        settings: settings,
      ),
      diagnosticPolicy: _stringValue(payload['diagnosticPolicy']) ??
          _stringValue(payload['policyClass']) ??
          'remote_control_plane_v1',
      createdAt: _stringValue(payload['createdAt']) ??
          _stringValue(payload['refreshedAt']) ??
          now.toIso8601String(),
      ttlSeconds: _intValue(payload['ttlSeconds']) ??
          _ttlFromExpiry(_stringValue(payload['expiresAt']), now) ??
          _ttlFromExpiry(_stringValue(payload['expiry']), now) ??
          _bundledBundleTtlSeconds,
      bundleVersion: _intValue(payload['bundleVersion']) ??
          _intValue(payload['version']) ??
          1,
      checksum: _stringValue(payload['checksum']),
      signature: _stringValue(payload['signature']),
      refreshedAt:
          _stringValue(payload['refreshedAt']) ?? now.toIso8601String(),
      bootstrapSource: 'remote_control_plane:$sourceName',
    );
  }

  DeblockerRuntimeBundle? _tryBuildBundleFromPayloadV1(
    Map<String, dynamic> payload, {
    required OfflineDeblockProfile profilePreset,
    required OfflineDeblockSettings settings,
    required String sourceName,
    required Set<String> excludedCandidateKeys,
  }) {
    try {
      return _buildBundleFromPayloadV1(
        payload,
        profilePreset: profilePreset,
        settings: settings,
        sourceName: sourceName,
        excludedCandidateKeys: excludedCandidateKeys,
      );
    } on FormatException {
      return null;
    }
  }

  DeblockerTrafficPolicy _parseTrafficPolicy(
    dynamic rawValue, {
    required OfflineDeblockSettings settings,
  }) {
    if (rawValue is Map<String, dynamic>) {
      return DeblockerTrafficPolicy.fromJson(rawValue);
    }
    if (rawValue is Map) {
      return DeblockerTrafficPolicy.fromJson(
          Map<String, dynamic>.from(rawValue));
    }
    return _defaultTrafficPolicy(settings);
  }

  DeblockerIngressConfig? _selectIngressConfig(
    Map<String, dynamic> payload, {
    required String sourceName,
    required Set<String> excludedCandidateKeys,
  }) {
    final rawCandidates = <dynamic>[];
    if (payload['ingressConfig'] != null) {
      rawCandidates.add(payload['ingressConfig']);
    }
    if (payload['ingress'] != null) {
      rawCandidates.add(payload['ingress']);
    }
    final endpoints = payload['ingressEndpoints'];
    if (endpoints is List) {
      rawCandidates.addAll(endpoints);
    }

    final candidates = rawCandidates
        .map((candidate) => _parseIngressConfigCandidate(candidate, sourceName))
        .whereType<DeblockerIngressConfig>()
        .toList(growable: false);
    for (final candidate in candidates) {
      if (_isExcludedIngressConfig(candidate, excludedCandidateKeys)) {
        continue;
      }
      if (candidate.enabled && candidate.isConfigured && !candidate.isExpired) {
        return candidate;
      }
    }
    for (final candidate in candidates) {
      if (_isExcludedIngressConfig(candidate, excludedCandidateKeys)) {
        continue;
      }
      if (candidate.enabled && candidate.isConfigured) {
        return candidate;
      }
    }
    return null;
  }

  Set<String> _buildExcludedIngressCandidateKeys(
    Iterable<DeblockerIngressConfig> excludedIngressConfigs,
  ) {
    return excludedIngressConfigs
        .map(_ingressCandidateKey)
        .where((value) => value.isNotEmpty)
        .toSet();
  }

  bool _isExcludedIngressConfig(
    DeblockerIngressConfig? candidate,
    Set<String> excludedCandidateKeys,
  ) {
    if (candidate == null || excludedCandidateKeys.isEmpty) {
      return false;
    }
    return excludedCandidateKeys.contains(_ingressCandidateKey(candidate));
  }

  String _ingressCandidateKey(DeblockerIngressConfig config) {
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

  DeblockerIngressConfig? _parseIngressConfigCandidate(
    dynamic rawValue,
    String sourceName,
  ) {
    if (rawValue is! Map) {
      return null;
    }

    final json = Map<String, dynamic>.from(rawValue);
    json['enabled'] = json['enabled'] as bool? ?? true;
    json['provider'] = _stringValue(json['provider']) ?? sourceName;
    json['outboundType'] = _stringValue(json['outboundType']) ??
        _stringValue(json['protocol']) ??
        _stringValue(json['type']) ??
        'trojan';
    json['edgeHost'] = _stringValue(json['edgeHost']) ??
        _stringValue(json['host']) ??
        _stringValue(json['server']) ??
        '';
    json['edgePort'] =
        _intValue(json['edgePort']) ?? _intValue(json['port']) ?? 443;
    json['transport'] = _stringValue(json['transport']) ??
        _stringValue(json['transportType']) ??
        _stringValue(json['network']) ??
        'ws';
    json['path'] = _stringValue(json['path']) ??
        _stringValue(json['wsPath']) ??
        _stringValue(json['servicePath']) ??
        '';
    json['hostHeader'] = _stringValue(json['hostHeader']) ??
        _stringValue(json['host']) ??
        _stringValue(json['edgeHost']) ??
        '';
    json['sni'] = _stringValue(json['sni']) ??
        _stringValue(json['serverName']) ??
        _stringValue(json['tlsServerName']) ??
        _stringValue(json['edgeHost']) ??
        _stringValue(json['host']) ??
        '';
    json['alpn'] = _parseStringList(json['alpn'] ?? json['alpnProtocols']);
    json['grpcServiceName'] = _stringValue(json['grpcServiceName']) ??
        _stringValue(json['serviceName']) ??
        '';
    json['username'] = _stringValue(json['username']) ?? '';
    json['password'] = _stringValue(json['password']) ??
        _stringValue(json['secret']) ??
        _stringValue(json['token']) ??
        '';
    json['uuid'] = _stringValue(json['uuid']) ?? _stringValue(json['id']) ?? '';
    json['skipCertVerify'] = json['skipCertVerify'] as bool? ?? false;
    json['fingerprint'] = _stringValue(json['fingerprint']) ?? 'chrome';
    json['allowDirectFallback'] = json['allowDirectFallback'] as bool? ?? true;
    json['originHint'] =
        _stringValue(json['originHint']) ?? 'remote_control_plane';
    json['policyTag'] = _stringValue(json['policyTag']) ??
        _stringValue(json['policyClass']) ??
        'remote_control_plane';
    json['configVersion'] =
        _intValue(json['configVersion']) ?? _intValue(json['version']) ?? 1;
    json['expiresAt'] =
        _stringValue(json['expiresAt']) ?? _stringValue(json['expiry']);
    return DeblockerIngressConfig.fromJson(json);
  }

  bool _isRolloutEnabled(Map<String, dynamic> payload) {
    final rollout = payload['rolloutFlags'] ?? payload['rollout'];
    if (rollout is Map<String, dynamic>) {
      final enabled = rollout['enabled'];
      if (enabled is bool) {
        return enabled;
      }
      final strictEnabled = rollout['strictAllowlistEnabled'];
      if (strictEnabled is bool) {
        return strictEnabled;
      }
    }
    if (rollout is Map) {
      return _isRolloutEnabled(Map<String, dynamic>.from(rollout));
    }

    final enabled = payload['rolloutEnabled'];
    if (enabled is bool) {
      return enabled;
    }
    return true;
  }

  String _bundleFailureReason(
    DeblockerRuntimeBundle bundle,
    DeblockerBundleIntegrityResult integrity,
  ) {
    if (!integrity.isValid) {
      return integrity.status.key;
    }
    if (bundle.isBootstrapSeedBundle) {
      return 'seed_only';
    }
    if (bundle.isExpired) {
      return 'expired';
    }
    if (bundle.ingressConfig?.isExpired ?? false) {
      return 'ingress_expired';
    }
    if (!bundle.isAllowlistedIngressBundle) {
      return 'not_allowlisted_ingress';
    }
    return 'rejected';
  }

  List<String> _parseStringList(dynamic rawValue) {
    if (rawValue is List) {
      return rawValue
          .whereType<String>()
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty)
          .toList(growable: false);
    }
    if (rawValue is String && rawValue.trim().isNotEmpty) {
      return rawValue
          .split(RegExp(r'[\s,;]+'))
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty)
          .toList(growable: false);
    }
    return const <String>[];
  }

  String? _stringValue(dynamic rawValue) {
    if (rawValue is! String) {
      return null;
    }
    final trimmed = rawValue.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  int? _intValue(dynamic rawValue) {
    if (rawValue is int) {
      return rawValue;
    }
    if (rawValue is num) {
      return rawValue.toInt();
    }
    if (rawValue is String) {
      return int.tryParse(rawValue.trim());
    }
    return null;
  }

  int? _ttlFromExpiry(String? rawValue, DateTime nowUtc) {
    if (rawValue == null || rawValue.isEmpty) {
      return null;
    }
    final expiresAt = DateTime.tryParse(rawValue)?.toUtc();
    if (expiresAt == null) {
      return null;
    }
    final ttl = expiresAt.difference(nowUtc).inSeconds;
    return ttl <= 0 ? 0 : ttl;
  }

  String? _extractSha256(String text) {
    final match = RegExp(r'([a-fA-F0-9]{64})').firstMatch(text);
    return match?.group(1)?.toLowerCase();
  }
}

class _DeblockerIngressBundleSource {
  final String name;
  final String url;

  const _DeblockerIngressBundleSource({
    required this.name,
    required this.url,
  });
}

class _DeblockerRemoteBundlePayload {
  final String body;
  final bool transportIntegrityVerified;

  const _DeblockerRemoteBundlePayload({
    required this.body,
    required this.transportIntegrityVerified,
  });
}

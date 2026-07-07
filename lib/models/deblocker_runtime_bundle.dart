import 'offline_deblock_profile.dart';

enum DeblockerDeliveryMode {
  directOnly,
  warpHybridLegacy,
  allowlistedIngress,
}

enum DeblockerBundleFreshness {
  fresh,
  stale,
  expired,
}

extension DeblockerBundleFreshnessExt on DeblockerBundleFreshness {
  String get key {
    switch (this) {
      case DeblockerBundleFreshness.fresh:
        return 'fresh';
      case DeblockerBundleFreshness.stale:
        return 'stale';
      case DeblockerBundleFreshness.expired:
        return 'expired';
    }
  }
}

extension DeblockerDeliveryModeExt on DeblockerDeliveryMode {
  String get key {
    switch (this) {
      case DeblockerDeliveryMode.directOnly:
        return 'direct_only';
      case DeblockerDeliveryMode.warpHybridLegacy:
        return 'warp_hybrid_legacy';
      case DeblockerDeliveryMode.allowlistedIngress:
        return 'allowlisted_ingress';
    }
  }

  String get displayName {
    switch (this) {
      case DeblockerDeliveryMode.directOnly:
        return 'Direct only';
      case DeblockerDeliveryMode.warpHybridLegacy:
        return 'Legacy WARP hybrid';
      case DeblockerDeliveryMode.allowlistedIngress:
        return 'Allowlisted ingress';
    }
  }

  static DeblockerDeliveryMode fromKey(String key) {
    switch (key) {
      case 'warp_hybrid_legacy':
        return DeblockerDeliveryMode.warpHybridLegacy;
      case 'allowlisted_ingress':
        return DeblockerDeliveryMode.allowlistedIngress;
      case 'direct_only':
      default:
        return DeblockerDeliveryMode.directOnly;
    }
  }
}

class DeblockerIngressConfig {
  final bool enabled;
  final String provider;
  final String outboundType;
  final String edgeHost;
  final int edgePort;
  final String transport;
  final String path;
  final String hostHeader;
  final String sni;
  final List<String> alpn;
  final String grpcServiceName;
  final String username;
  final String password;
  final String uuid;
  final bool skipCertVerify;
  final String fingerprint;
  final bool realityEnabled;
  final String realityPublicKey;
  final String realityShortId;
  final bool echEnabled;
  final bool allowDirectFallback;
  final String originHint;
  final String policyTag;
  final int configVersion;
  final String? expiresAt;

  const DeblockerIngressConfig({
    required this.enabled,
    required this.provider,
    required this.outboundType,
    required this.edgeHost,
    required this.edgePort,
    required this.transport,
    required this.path,
    required this.hostHeader,
    required this.sni,
    required this.alpn,
    required this.grpcServiceName,
    required this.username,
    required this.password,
    required this.uuid,
    required this.skipCertVerify,
    required this.fingerprint,
    required this.realityEnabled,
    required this.realityPublicKey,
    required this.realityShortId,
    required this.echEnabled,
    required this.allowDirectFallback,
    required this.originHint,
    required this.policyTag,
    required this.configVersion,
    required this.expiresAt,
  });

  const DeblockerIngressConfig.disabled()
      : enabled = false,
        provider = '',
        outboundType = 'trojan',
        edgeHost = '',
        edgePort = 443,
        transport = '',
        path = '',
        hostHeader = '',
        sni = '',
        alpn = const <String>[],
        grpcServiceName = '',
        username = '',
        password = '',
        uuid = '',
        skipCertVerify = false,
        fingerprint = 'chrome',
        realityEnabled = false,
        realityPublicKey = '',
        realityShortId = '',
        echEnabled = false,
        allowDirectFallback = true,
        originHint = '',
        policyTag = '',
        configVersion = 1,
        expiresAt = null;

  bool get isConfigured {
    return enabled &&
        edgeHost.trim().isNotEmpty &&
        transport.trim().isNotEmpty &&
        edgePort > 0;
  }

  bool get isExpired {
    final rawValue = expiresAt?.trim();
    if (rawValue == null || rawValue.isEmpty) {
      return false;
    }
    final parsed = DateTime.tryParse(rawValue);
    if (parsed == null) {
      return false;
    }
    return DateTime.now().toUtc().isAfter(parsed.toUtc());
  }

  DeblockerIngressConfig copyWith({
    bool? enabled,
    String? provider,
    String? outboundType,
    String? edgeHost,
    int? edgePort,
    String? transport,
    String? path,
    String? hostHeader,
    String? sni,
    List<String>? alpn,
    String? grpcServiceName,
    String? username,
    String? password,
    String? uuid,
    bool? skipCertVerify,
    String? fingerprint,
    bool? realityEnabled,
    String? realityPublicKey,
    String? realityShortId,
    bool? echEnabled,
    bool? allowDirectFallback,
    String? originHint,
    String? policyTag,
    int? configVersion,
    String? expiresAt,
  }) {
    return DeblockerIngressConfig(
      enabled: enabled ?? this.enabled,
      provider: provider ?? this.provider,
      outboundType: outboundType ?? this.outboundType,
      edgeHost: edgeHost ?? this.edgeHost,
      edgePort: edgePort ?? this.edgePort,
      transport: transport ?? this.transport,
      path: path ?? this.path,
      hostHeader: hostHeader ?? this.hostHeader,
      sni: sni ?? this.sni,
      alpn: alpn ?? this.alpn,
      grpcServiceName: grpcServiceName ?? this.grpcServiceName,
      username: username ?? this.username,
      password: password ?? this.password,
      uuid: uuid ?? this.uuid,
      skipCertVerify: skipCertVerify ?? this.skipCertVerify,
      fingerprint: fingerprint ?? this.fingerprint,
      realityEnabled: realityEnabled ?? this.realityEnabled,
      realityPublicKey: realityPublicKey ?? this.realityPublicKey,
      realityShortId: realityShortId ?? this.realityShortId,
      echEnabled: echEnabled ?? this.echEnabled,
      allowDirectFallback: allowDirectFallback ?? this.allowDirectFallback,
      originHint: originHint ?? this.originHint,
      policyTag: policyTag ?? this.policyTag,
      configVersion: configVersion ?? this.configVersion,
      expiresAt: expiresAt ?? this.expiresAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'enabled': enabled,
      'provider': provider,
      'outboundType': outboundType,
      'edgeHost': edgeHost,
      'edgePort': edgePort,
      'transport': transport,
      'path': path,
      'hostHeader': hostHeader,
      'sni': sni,
      'alpn': alpn,
      'grpcServiceName': grpcServiceName,
      'username': username,
      'password': password,
      'uuid': uuid,
      'skipCertVerify': skipCertVerify,
      'fingerprint': fingerprint,
      'realityEnabled': realityEnabled,
      'realityPublicKey': realityPublicKey,
      'realityShortId': realityShortId,
      'echEnabled': echEnabled,
      'allowDirectFallback': allowDirectFallback,
      'originHint': originHint,
      'policyTag': policyTag,
      'configVersion': configVersion,
      'expiresAt': expiresAt,
    };
  }

  static DeblockerIngressConfig fromJson(Map<String, dynamic> json) {
    final rawPort = (json['edgePort'] as num?)?.toInt() ?? 443;
    final normalizedPort =
        rawPort < 1 ? 443 : (rawPort > 65535 ? 65535 : rawPort);
    final rawAlpn = (json['alpn'] as List<dynamic>? ?? const <dynamic>[])
        .whereType<String>()
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList(growable: false);

    return DeblockerIngressConfig(
      enabled: json['enabled'] as bool? ?? false,
      provider: (json['provider'] as String? ?? '').trim(),
      outboundType: (json['outboundType'] as String? ?? 'trojan').trim(),
      edgeHost: (json['edgeHost'] as String? ?? '').trim(),
      edgePort: normalizedPort,
      transport: (json['transport'] as String? ?? '').trim(),
      path: (json['path'] as String? ?? '').trim(),
      hostHeader: (json['hostHeader'] as String? ?? '').trim(),
      sni: (json['sni'] as String? ?? '').trim(),
      alpn: rawAlpn,
      grpcServiceName: (json['grpcServiceName'] as String? ?? '').trim(),
      username: (json['username'] as String? ?? '').trim(),
      password: (json['password'] as String? ?? '').trim(),
      uuid: (json['uuid'] as String? ?? '').trim(),
      skipCertVerify: json['skipCertVerify'] as bool? ?? false,
      fingerprint: (json['fingerprint'] as String? ?? 'chrome').trim(),
      realityEnabled: json['realityEnabled'] as bool? ?? false,
      realityPublicKey: (json['realityPublicKey'] as String? ?? '').trim(),
      realityShortId: (json['realityShortId'] as String? ?? '').trim(),
      echEnabled: json['echEnabled'] as bool? ?? false,
      allowDirectFallback: json['allowDirectFallback'] as bool? ?? true,
      originHint: (json['originHint'] as String? ?? '').trim(),
      policyTag: (json['policyTag'] as String? ?? '').trim(),
      configVersion: (json['configVersion'] as num?)?.toInt() ?? 1,
      expiresAt: (json['expiresAt'] as String?)?.trim(),
    );
  }
}

class DeblockerTrafficPolicy {
  final List<String> directDomainSuffixes;
  final List<String> directExactDomains;
  final List<String> ingressDomainSuffixes;
  final List<String> ingressExactDomains;
  final bool fallbackToIngressForUnknownHttps;
  final bool allowDirectForPrivateIp;
  final bool blockUnsupportedUdp;
  final bool blockIpv6WhenNeeded;
  final int policyVersion;

  const DeblockerTrafficPolicy({
    required this.directDomainSuffixes,
    required this.directExactDomains,
    required this.ingressDomainSuffixes,
    required this.ingressExactDomains,
    required this.fallbackToIngressForUnknownHttps,
    required this.allowDirectForPrivateIp,
    required this.blockUnsupportedUdp,
    required this.blockIpv6WhenNeeded,
    required this.policyVersion,
  });

  factory DeblockerTrafficPolicy.legacyForProfile(
    OfflineDeblockProfile profile,
    OfflineDeblockSettings settings,
  ) {
    return DeblockerTrafficPolicy(
      directDomainSuffixes: profile == OfflineDeblockProfile.hybrid
          ? const ['.ru', '.рф', '.su', '.moscow', '.tatar']
          : const <String>[],
      directExactDomains: const <String>[],
      ingressDomainSuffixes: const <String>[],
      ingressExactDomains: const <String>[],
      fallbackToIngressForUnknownHttps: profile == OfflineDeblockProfile.hybrid,
      allowDirectForPrivateIp: true,
      blockUnsupportedUdp: settings.blockAllUdp || settings.blockUdp443,
      blockIpv6WhenNeeded: settings.blockIpv6,
      policyVersion: 1,
    );
  }

  DeblockerTrafficPolicy copyWith({
    List<String>? directDomainSuffixes,
    List<String>? directExactDomains,
    List<String>? ingressDomainSuffixes,
    List<String>? ingressExactDomains,
    bool? fallbackToIngressForUnknownHttps,
    bool? allowDirectForPrivateIp,
    bool? blockUnsupportedUdp,
    bool? blockIpv6WhenNeeded,
    int? policyVersion,
  }) {
    return DeblockerTrafficPolicy(
      directDomainSuffixes: directDomainSuffixes ?? this.directDomainSuffixes,
      directExactDomains: directExactDomains ?? this.directExactDomains,
      ingressDomainSuffixes:
          ingressDomainSuffixes ?? this.ingressDomainSuffixes,
      ingressExactDomains: ingressExactDomains ?? this.ingressExactDomains,
      fallbackToIngressForUnknownHttps: fallbackToIngressForUnknownHttps ??
          this.fallbackToIngressForUnknownHttps,
      allowDirectForPrivateIp:
          allowDirectForPrivateIp ?? this.allowDirectForPrivateIp,
      blockUnsupportedUdp: blockUnsupportedUdp ?? this.blockUnsupportedUdp,
      blockIpv6WhenNeeded: blockIpv6WhenNeeded ?? this.blockIpv6WhenNeeded,
      policyVersion: policyVersion ?? this.policyVersion,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'directDomainSuffixes': directDomainSuffixes,
      'directExactDomains': directExactDomains,
      'ingressDomainSuffixes': ingressDomainSuffixes,
      'ingressExactDomains': ingressExactDomains,
      'fallbackToIngressForUnknownHttps': fallbackToIngressForUnknownHttps,
      'allowDirectForPrivateIp': allowDirectForPrivateIp,
      'blockUnsupportedUdp': blockUnsupportedUdp,
      'blockIpv6WhenNeeded': blockIpv6WhenNeeded,
      'policyVersion': policyVersion,
    };
  }

  static DeblockerTrafficPolicy fromJson(Map<String, dynamic> json) {
    List<String> parseStringList(String key) {
      return (json[key] as List<dynamic>? ?? const <dynamic>[])
          .whereType<String>()
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty)
          .toList(growable: false);
    }

    return DeblockerTrafficPolicy(
      directDomainSuffixes: parseStringList('directDomainSuffixes'),
      directExactDomains: parseStringList('directExactDomains'),
      ingressDomainSuffixes: parseStringList('ingressDomainSuffixes'),
      ingressExactDomains: parseStringList('ingressExactDomains'),
      fallbackToIngressForUnknownHttps:
          json['fallbackToIngressForUnknownHttps'] as bool? ?? false,
      allowDirectForPrivateIp: json['allowDirectForPrivateIp'] as bool? ?? true,
      blockUnsupportedUdp: json['blockUnsupportedUdp'] as bool? ?? true,
      blockIpv6WhenNeeded: json['blockIpv6WhenNeeded'] as bool? ?? false,
      policyVersion: (json['policyVersion'] as num?)?.toInt() ?? 1,
    );
  }
}

class DeblockerRuntimeBundle {
  final OfflineDeblockProfile profilePreset;
  final DeblockerDeliveryMode deliveryMode;
  final OfflineDeblockSettings settings;
  final DeblockerIngressConfig? ingressConfig;
  final DeblockerTrafficPolicy trafficPolicy;
  final String? diagnosticPolicy;
  final String createdAt;
  final int ttlSeconds;
  final int bundleVersion;
  final String? checksum;
  final String? signature;
  final String? refreshedAt;
  final String? bootstrapSource;

  const DeblockerRuntimeBundle({
    required this.profilePreset,
    required this.deliveryMode,
    required this.settings,
    required this.ingressConfig,
    required this.trafficPolicy,
    required this.diagnosticPolicy,
    required this.createdAt,
    required this.ttlSeconds,
    required this.bundleVersion,
    required this.checksum,
    required this.signature,
    required this.refreshedAt,
    required this.bootstrapSource,
  });

  factory DeblockerRuntimeBundle.legacy({
    required OfflineDeblockProfile profilePreset,
    required OfflineDeblockSettings settings,
  }) {
    return DeblockerRuntimeBundle(
      profilePreset: profilePreset,
      deliveryMode: profilePreset == OfflineDeblockProfile.hybrid
          ? DeblockerDeliveryMode.warpHybridLegacy
          : DeblockerDeliveryMode.directOnly,
      settings: settings,
      ingressConfig: null,
      trafficPolicy:
          DeblockerTrafficPolicy.legacyForProfile(profilePreset, settings),
      diagnosticPolicy: 'legacy_baseline',
      createdAt: DateTime.now().toUtc().toIso8601String(),
      ttlSeconds: 86400,
      bundleVersion: 1,
      checksum: null,
      signature: null,
      refreshedAt: null,
      bootstrapSource: 'generated_legacy',
    );
  }

  DateTime? get createdAtUtc => DateTime.tryParse(createdAt)?.toUtc();

  DateTime? get refreshedAtUtc {
    final rawValue = refreshedAt?.trim();
    if (rawValue == null || rawValue.isEmpty) {
      return null;
    }
    return DateTime.tryParse(rawValue)?.toUtc();
  }

  DateTime? get expiresAtUtc {
    final created = createdAtUtc;
    if (created == null || ttlSeconds <= 0) {
      return null;
    }
    return created.add(Duration(seconds: ttlSeconds)).toUtc();
  }

  int? get remainingTtlSeconds {
    final expires = expiresAtUtc;
    if (expires == null) {
      return null;
    }
    return expires.difference(DateTime.now().toUtc()).inSeconds;
  }

  int get staleThresholdSeconds {
    final rawThreshold = ttlSeconds ~/ 4;
    if (rawThreshold < 1800) {
      return 1800;
    }
    if (rawThreshold > 21600) {
      return 21600;
    }
    return rawThreshold;
  }

  bool get isExpired {
    final expires = expiresAtUtc;
    if (expires == null) {
      return false;
    }
    return DateTime.now().toUtc().isAfter(expires);
  }

  bool get isStale {
    final remaining = remainingTtlSeconds;
    if (remaining == null || isExpired) {
      return false;
    }
    return remaining <= staleThresholdSeconds;
  }

  DeblockerBundleFreshness get freshness {
    if (isExpired) {
      return DeblockerBundleFreshness.expired;
    }
    if (isStale) {
      return DeblockerBundleFreshness.stale;
    }
    return DeblockerBundleFreshness.fresh;
  }

  bool get requiresLegacyWarpProvisioning {
    return deliveryMode == DeblockerDeliveryMode.warpHybridLegacy &&
        settings.wantsWarpDetour;
  }

  bool get isAllowlistedIngressBundle {
    return deliveryMode == DeblockerDeliveryMode.allowlistedIngress &&
        (ingressConfig?.isConfigured ?? false);
  }

  bool get isBootstrapSeedBundle {
    final providerName = ingressConfig?.provider.trim().toLowerCase() ?? '';
    final originHint = ingressConfig?.originHint.trim().toLowerCase() ?? '';
    final source = bootstrapSource?.trim().toLowerCase() ?? '';
    return providerName == 'bundled_seed' ||
        source == 'bundled_seed' ||
        originHint.contains('seed');
  }

  bool get shouldRefreshFromControlPlane {
    if (!isAllowlistedIngressBundle) {
      return true;
    }
    if (isBootstrapSeedBundle) {
      return true;
    }
    return isExpired || isStale || (ingressConfig?.isExpired ?? false);
  }

  Map<String, dynamic> toIntegrityJson() {
    return {
      'deliveryMode': deliveryMode.key,
      'ingressConfig': ingressConfig?.toJson(),
      'trafficPolicy': trafficPolicy.toJson(),
      'diagnosticPolicy': diagnosticPolicy,
      'createdAt': createdAt,
      'ttlSeconds': ttlSeconds,
      'bundleVersion': bundleVersion,
    };
  }

  DeblockerRuntimeBundle copyWith({
    OfflineDeblockProfile? profilePreset,
    DeblockerDeliveryMode? deliveryMode,
    OfflineDeblockSettings? settings,
    DeblockerIngressConfig? ingressConfig,
    DeblockerTrafficPolicy? trafficPolicy,
    String? diagnosticPolicy,
    String? createdAt,
    int? ttlSeconds,
    int? bundleVersion,
    String? checksum,
    String? signature,
    String? refreshedAt,
    String? bootstrapSource,
  }) {
    return DeblockerRuntimeBundle(
      profilePreset: profilePreset ?? this.profilePreset,
      deliveryMode: deliveryMode ?? this.deliveryMode,
      settings: settings ?? this.settings,
      ingressConfig: ingressConfig ?? this.ingressConfig,
      trafficPolicy: trafficPolicy ?? this.trafficPolicy,
      diagnosticPolicy: diagnosticPolicy ?? this.diagnosticPolicy,
      createdAt: createdAt ?? this.createdAt,
      ttlSeconds: ttlSeconds ?? this.ttlSeconds,
      bundleVersion: bundleVersion ?? this.bundleVersion,
      checksum: checksum ?? this.checksum,
      signature: signature ?? this.signature,
      refreshedAt: refreshedAt ?? this.refreshedAt,
      bootstrapSource: bootstrapSource ?? this.bootstrapSource,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'profilePreset': profilePreset.key,
      'deliveryMode': deliveryMode.key,
      'settings': settings.toJson(),
      'ingressConfig': ingressConfig?.toJson(),
      'trafficPolicy': trafficPolicy.toJson(),
      'diagnosticPolicy': diagnosticPolicy,
      'createdAt': createdAt,
      'ttlSeconds': ttlSeconds,
      'bundleVersion': bundleVersion,
      'checksum': checksum,
      'signature': signature,
      'refreshedAt': refreshedAt,
      'bootstrapSource': bootstrapSource,
    };
  }

  static DeblockerRuntimeBundle fromJson(Map<String, dynamic> json) {
    final settingsJson = Map<String, dynamic>.from(
      json['settings'] as Map<String, dynamic>? ?? const <String, dynamic>{},
    );
    final ingressJson = json['ingressConfig'];
    final trafficPolicyJson = Map<String, dynamic>.from(
      json['trafficPolicy'] as Map<String, dynamic>? ??
          const <String, dynamic>{},
    );

    return DeblockerRuntimeBundle(
      profilePreset: OfflineDeblockProfileExt.fromKey(
        (json['profilePreset'] as String? ?? 'balanced').trim(),
      ),
      deliveryMode: DeblockerDeliveryModeExt.fromKey(
        (json['deliveryMode'] as String? ?? 'direct_only').trim(),
      ),
      settings: OfflineDeblockSettings.fromJson(settingsJson),
      ingressConfig: ingressJson is Map<String, dynamic>
          ? DeblockerIngressConfig.fromJson(ingressJson)
          : ingressJson is Map
              ? DeblockerIngressConfig.fromJson(
                  Map<String, dynamic>.from(ingressJson),
                )
              : null,
      trafficPolicy: DeblockerTrafficPolicy.fromJson(trafficPolicyJson),
      diagnosticPolicy: (json['diagnosticPolicy'] as String?)?.trim(),
      createdAt: (json['createdAt'] as String? ?? '').trim().isEmpty
          ? DateTime.now().toUtc().toIso8601String()
          : (json['createdAt'] as String).trim(),
      ttlSeconds: (json['ttlSeconds'] as num?)?.toInt() ?? 86400,
      bundleVersion: (json['bundleVersion'] as num?)?.toInt() ?? 1,
      checksum: (json['checksum'] as String?)?.trim().isEmpty ?? true
          ? null
          : (json['checksum'] as String).trim(),
      signature: (json['signature'] as String?)?.trim().isEmpty ?? true
          ? null
          : (json['signature'] as String).trim(),
      refreshedAt: (json['refreshedAt'] as String?)?.trim().isEmpty ?? true
          ? null
          : (json['refreshedAt'] as String).trim(),
      bootstrapSource:
          (json['bootstrapSource'] as String?)?.trim().isEmpty ?? true
              ? null
              : (json['bootstrapSource'] as String).trim(),
    );
  }
}

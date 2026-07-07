class AdaptiveProfileDescriptor {
  final String protocol;
  final String transport;
  final String fingerprint;
  final bool tlsEnabled;
  final bool supportsTransportFallback;

  const AdaptiveProfileDescriptor({
    required this.protocol,
    required this.transport,
    required this.fingerprint,
    required this.tlsEnabled,
    required this.supportsTransportFallback,
  });
}

class AdaptiveTunnelPolicyState {
  final Map<String, int> transportCooldownUntilMs;
  final Map<String, int> fingerprintCooldownUntilMs;
  final Map<String, String> preferredTransportByEnv;
  final Map<String, String> preferredFingerprintByEnv;
  final String mitigationNote;

  const AdaptiveTunnelPolicyState({
    required this.transportCooldownUntilMs,
    required this.fingerprintCooldownUntilMs,
    required this.preferredTransportByEnv,
    required this.preferredFingerprintByEnv,
    required this.mitigationNote,
  });

  const AdaptiveTunnelPolicyState.empty()
      : transportCooldownUntilMs = const <String, int>{},
        fingerprintCooldownUntilMs = const <String, int>{},
        preferredTransportByEnv = const <String, String>{},
        preferredFingerprintByEnv = const <String, String>{},
        mitigationNote = '';

  AdaptiveTunnelPolicyState copyWith({
    Map<String, int>? transportCooldownUntilMs,
    Map<String, int>? fingerprintCooldownUntilMs,
    Map<String, String>? preferredTransportByEnv,
    Map<String, String>? preferredFingerprintByEnv,
    String? mitigationNote,
  }) {
    return AdaptiveTunnelPolicyState(
      transportCooldownUntilMs:
          transportCooldownUntilMs ?? this.transportCooldownUntilMs,
      fingerprintCooldownUntilMs:
          fingerprintCooldownUntilMs ?? this.fingerprintCooldownUntilMs,
      preferredTransportByEnv:
          preferredTransportByEnv ?? this.preferredTransportByEnv,
      preferredFingerprintByEnv:
          preferredFingerprintByEnv ?? this.preferredFingerprintByEnv,
      mitigationNote: mitigationNote ?? this.mitigationNote,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'transportCooldownUntilMs': transportCooldownUntilMs,
      'fingerprintCooldownUntilMs': fingerprintCooldownUntilMs,
      'preferredTransportByEnv': preferredTransportByEnv,
      'preferredFingerprintByEnv': preferredFingerprintByEnv,
      'mitigationNote': mitigationNote,
    };
  }

  static AdaptiveTunnelPolicyState fromJson(Map<String, dynamic> json) {
    final transportMap = (json['transportCooldownUntilMs'] as Map?)
            ?.map((k, v) => MapEntry('$k', (v as num).toInt())) ??
        <String, int>{};
    final fingerprintMap = (json['fingerprintCooldownUntilMs'] as Map?)
            ?.map((k, v) => MapEntry('$k', (v as num).toInt())) ??
        <String, int>{};
    final preferredTransport = (json['preferredTransportByEnv'] as Map?)
            ?.map((k, v) => MapEntry('$k', '$v')) ??
        <String, String>{};
    final preferredFingerprint = (json['preferredFingerprintByEnv'] as Map?)
            ?.map((k, v) => MapEntry('$k', '$v')) ??
        <String, String>{};

    return AdaptiveTunnelPolicyState(
      transportCooldownUntilMs: transportMap,
      fingerprintCooldownUntilMs: fingerprintMap,
      preferredTransportByEnv: preferredTransport,
      preferredFingerprintByEnv: preferredFingerprint,
      mitigationNote: (json['mitigationNote'] as String?)?.trim() ?? '',
    );
  }
}

class AdaptiveMaterializationResult {
  final AdaptiveTunnelPolicyState state;
  final String? transport;
  final String? fingerprint;

  const AdaptiveMaterializationResult({
    required this.state,
    required this.transport,
    required this.fingerprint,
  });
}

class AdaptiveTunnelPolicy {
  static const List<String> transportPool = <String>['xhttp', 'ws'];
  static const List<String> fingerprintPool = <String>[
    'chrome',
    'firefox',
    'edge',
    'safari',
  ];

  static String normalizeEnvironment({
    required String networkTransport,
    required String networkInterface,
    String operatorHint = '',
  }) {
    final base = _normalizeBaseEnvironment(networkTransport, networkInterface);
    final op = _normalizeOperatorHint(operatorHint);
    return op.isEmpty ? base : '$base|$op';
  }

  /// Returns the base (network-type-only) component of an environment key.
  /// For `'cellular|mts'` returns `'cellular'`; for `'wifi'` returns `'wifi'`.
  static String baseEnvironmentKey(String environmentKey) {
    final idx = environmentKey.indexOf('|');
    return idx >= 0 ? environmentKey.substring(0, idx) : environmentKey;
  }

  static String _normalizeBaseEnvironment(
    String networkTransport,
    String networkInterface,
  ) {
    final rawTransport = networkTransport.trim().toLowerCase();
    final rawInterface = networkInterface.trim().toLowerCase();

    if (rawTransport.contains('wifi') ||
        rawInterface.startsWith('wlan') ||
        rawInterface.contains('wifi')) {
      return 'wifi';
    }
    if (rawTransport.contains('cell') ||
        rawTransport.contains('mobile') ||
        rawInterface.startsWith('rmnet') ||
        rawInterface.contains('cell')) {
      return 'cellular';
    }
    if (rawTransport.contains('ethernet') || rawInterface.startsWith('eth')) {
      return 'ethernet';
    }
    if (rawTransport.contains('vpn') || rawInterface.startsWith('tun')) {
      return 'vpn';
    }
    return 'unknown';
  }

  static String _normalizeOperatorHint(String hint) {
    final raw = hint.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    return raw.length > 32 ? raw.substring(0, 32) : raw;
  }

  static AdaptiveTunnelPolicyState evictExpired(
    AdaptiveTunnelPolicyState state, {
    required int nowMs,
  }) {
    final transportCooldown =
        Map<String, int>.from(state.transportCooldownUntilMs)
          ..removeWhere((_, until) => until <= nowMs);
    final fingerprintCooldown =
        Map<String, int>.from(state.fingerprintCooldownUntilMs)
          ..removeWhere((_, until) => until <= nowMs);
    final preferredTransport =
        Map<String, String>.from(state.preferredTransportByEnv)
          ..removeWhere(
            (_, value) => !transportPool.contains(value.trim().toLowerCase()),
          );
    final preferredFingerprint =
        Map<String, String>.from(state.preferredFingerprintByEnv)
          ..removeWhere((_, value) => value.trim().isEmpty);

    var note = state.mitigationNote;
    if (transportCooldown.isEmpty &&
        fingerprintCooldown.isEmpty &&
        note.contains('after ')) {
      note = '';
    }

    return state.copyWith(
      transportCooldownUntilMs: transportCooldown,
      fingerprintCooldownUntilMs: fingerprintCooldown,
      preferredTransportByEnv: preferredTransport,
      preferredFingerprintByEnv: preferredFingerprint,
      mitigationNote: note,
    );
  }

  static int profilePenalty(
    AdaptiveTunnelPolicyState state,
    AdaptiveProfileDescriptor profile, {
    required int nowMs,
  }) {
    final current = evictExpired(state, nowMs: nowMs);
    var penalty = 0;
    if (_isTransportInCooldown(current, profile, nowMs: nowMs)) {
      penalty += 240000;
    }
    if (_isFingerprintInCooldown(current, profile, nowMs: nowMs)) {
      penalty += 90000;
    }
    return penalty;
  }

  static AdaptiveMaterializationResult materialize(
    AdaptiveTunnelPolicyState state,
    AdaptiveProfileDescriptor profile, {
    required String environmentKey,
    required int nowMs,
    required bool fingerprintSpoofingEnabled,
  }) {
    var current = evictExpired(state, nowMs: nowMs);
    var selectedTransport = profile.transport.trim().toLowerCase();
    var selectedFingerprint = _normalizedFingerprint(profile);
    final notes = <String>[];
    final baseKey = baseEnvironmentKey(environmentKey);

    final preferredTransport =
        (current.preferredTransportByEnv[environmentKey] ??
                (environmentKey != baseKey
                    ? current.preferredTransportByEnv[baseKey]
                    : null))
            ?.trim()
            .toLowerCase();
    if (preferredTransport != null &&
        preferredTransport.isNotEmpty &&
        transportPool.contains(preferredTransport) &&
        profile.supportsTransportFallback &&
        selectedTransport != preferredTransport &&
        !_isTransportKeyInCooldown(
          current,
          protocol: profile.protocol,
          transport: preferredTransport,
          nowMs: nowMs,
        )) {
      selectedTransport = preferredTransport;
      notes.add('network $environmentKey: transport $preferredTransport');
    }

    if (profile.supportsTransportFallback &&
        _isTransportKeyInCooldown(
          current,
          protocol: profile.protocol,
          transport: selectedTransport,
          nowMs: nowMs,
        )) {
      selectedTransport = 'ws';
      notes.add('switch to WS after xhttp failures');
    }

    if (fingerprintSpoofingEnabled && profile.tlsEnabled) {
      final preferredFingerprint =
          (current.preferredFingerprintByEnv[environmentKey] ??
                  (environmentKey != baseKey
                      ? current.preferredFingerprintByEnv[baseKey]
                      : null))
              ?.trim()
              .toLowerCase();
      if (preferredFingerprint != null &&
          preferredFingerprint.isNotEmpty &&
          preferredFingerprint != selectedFingerprint &&
          !_isFingerprintKeyInCooldown(
            current,
            preferredFingerprint,
            nowMs: nowMs,
          )) {
        selectedFingerprint = preferredFingerprint;
        notes.add('TLS fingerprint $selectedFingerprint');
      } else if (_isFingerprintKeyInCooldown(
        current,
        selectedFingerprint,
        nowMs: nowMs,
      )) {
        final next = _pickNextFingerprint(current, selectedFingerprint, nowMs);
        if (next != null && next != selectedFingerprint) {
          selectedFingerprint = next;
          notes.add('TLS fingerprint $selectedFingerprint');
        }
      }
    }

    if (notes.isNotEmpty) {
      current = current.copyWith(mitigationNote: notes.join(' ; '));
    }

    final transportMutation =
        selectedTransport == profile.transport.trim().toLowerCase()
            ? null
            : selectedTransport;
    final fingerprintMutation =
        selectedFingerprint == _normalizedFingerprint(profile)
            ? null
            : selectedFingerprint;

    return AdaptiveMaterializationResult(
      state: current,
      transport: transportMutation,
      fingerprint: fingerprintMutation,
    );
  }

  static AdaptiveTunnelPolicyState markFailure(
    AdaptiveTunnelPolicyState state,
    AdaptiveProfileDescriptor profile, {
    required String environmentKey,
    required String reason,
    required int nowMs,
    required bool fingerprintSpoofingEnabled,
  }) {
    var current = evictExpired(state, nowMs: nowMs);
    final transportMap =
        Map<String, int>.from(current.transportCooldownUntilMs);
    final fingerprintMap =
        Map<String, int>.from(current.fingerprintCooldownUntilMs);
    final preferredTransport =
        Map<String, String>.from(current.preferredTransportByEnv);
    final preferredFingerprint =
        Map<String, String>.from(current.preferredFingerprintByEnv);

    final transportKey = _transportKey(profile.protocol, profile.transport);
    final transportFailures = (transportMap[transportKey] ?? 0) > nowMs ? 2 : 1;
    transportMap[transportKey] =
        nowMs + _backoffMsForFailures(transportFailures);

    if (profile.supportsTransportFallback) {
      final nextTransport = _nextTransport(profile.transport);
      if (nextTransport != null) {
        preferredTransport[environmentKey] = nextTransport;
      }
    }

    if (fingerprintSpoofingEnabled && profile.tlsEnabled) {
      final fingerprint = _normalizedFingerprint(profile);
      final fingerprintFailures =
          (fingerprintMap[fingerprint] ?? 0) > nowMs ? 2 : 1;
      fingerprintMap[fingerprint] =
          nowMs + _backoffMsForFailures(fingerprintFailures);
      final nextFingerprint = _pickNextFingerprintByMap(
        fingerprintMap,
        fingerprint,
        nowMs,
      );
      if (nextFingerprint != null) {
        preferredFingerprint[environmentKey] = nextFingerprint;
      }
    }

    return current.copyWith(
      transportCooldownUntilMs: transportMap,
      fingerprintCooldownUntilMs: fingerprintMap,
      preferredTransportByEnv: preferredTransport,
      preferredFingerprintByEnv: preferredFingerprint,
      mitigationNote: 'adaptive reaction on $environmentKey after $reason',
    );
  }

  static AdaptiveTunnelPolicyState markSuccess(
    AdaptiveTunnelPolicyState state,
    AdaptiveProfileDescriptor profile, {
    required String environmentKey,
    required int nowMs,
    required bool fingerprintSpoofingEnabled,
  }) {
    var current = evictExpired(state, nowMs: nowMs);
    final transportMap = Map<String, int>.from(current.transportCooldownUntilMs)
      ..remove(_transportKey(profile.protocol, profile.transport));
    final fingerprintMap =
        Map<String, int>.from(current.fingerprintCooldownUntilMs)
          ..remove(_normalizedFingerprint(profile));
    final preferredTransport =
        Map<String, String>.from(current.preferredTransportByEnv);
    final preferredFingerprint =
        Map<String, String>.from(current.preferredFingerprintByEnv);

    if (profile.supportsTransportFallback) {
      preferredTransport[environmentKey] =
          profile.transport.trim().toLowerCase();
    }
    if (fingerprintSpoofingEnabled && profile.tlsEnabled) {
      preferredFingerprint[environmentKey] = _normalizedFingerprint(profile);
    }

    final note = transportMap.isEmpty && fingerprintMap.isEmpty
        ? ''
        : 'environment stabilized on working strategy';

    return current.copyWith(
      transportCooldownUntilMs: transportMap,
      fingerprintCooldownUntilMs: fingerprintMap,
      preferredTransportByEnv: preferredTransport,
      preferredFingerprintByEnv: preferredFingerprint,
      mitigationNote: note,
    );
  }

  static int environmentStrategyCount(AdaptiveTunnelPolicyState state) {
    final keys = <String>{
      ...state.preferredTransportByEnv.keys,
      ...state.preferredFingerprintByEnv.keys,
    };
    return keys.length;
  }

  static bool _isTransportInCooldown(
    AdaptiveTunnelPolicyState state,
    AdaptiveProfileDescriptor profile, {
    required int nowMs,
  }) {
    return _isTransportKeyInCooldown(
      state,
      protocol: profile.protocol,
      transport: profile.transport,
      nowMs: nowMs,
    );
  }

  static bool _isTransportKeyInCooldown(
    AdaptiveTunnelPolicyState state, {
    required String protocol,
    required String transport,
    required int nowMs,
  }) {
    final key = _transportKey(protocol, transport);
    final until = state.transportCooldownUntilMs[key] ?? 0;
    return until > nowMs;
  }

  static bool _isFingerprintInCooldown(
    AdaptiveTunnelPolicyState state,
    AdaptiveProfileDescriptor profile, {
    required int nowMs,
  }) {
    if (!profile.tlsEnabled) {
      return false;
    }
    return _isFingerprintKeyInCooldown(
      state,
      _normalizedFingerprint(profile),
      nowMs: nowMs,
    );
  }

  static bool _isFingerprintKeyInCooldown(
    AdaptiveTunnelPolicyState state,
    String fingerprint, {
    required int nowMs,
  }) {
    final until = state.fingerprintCooldownUntilMs[fingerprint] ?? 0;
    return until > nowMs;
  }

  static String _transportKey(String protocol, String transport) {
    return '${protocol.trim().toLowerCase()}|${transport.trim().toLowerCase()}';
  }

  static String _normalizedFingerprint(AdaptiveProfileDescriptor profile) {
    final raw = profile.fingerprint.trim().toLowerCase();
    if (raw.isNotEmpty && raw != 'random') {
      return raw;
    }
    final seed =
        '${profile.protocol}|${profile.transport}|${profile.fingerprint}|${profile.tlsEnabled}';
    final idx = seed.hashCode.abs() % fingerprintPool.length;
    return fingerprintPool[idx];
  }

  static String? _pickNextFingerprint(
    AdaptiveTunnelPolicyState state,
    String current,
    int nowMs,
  ) {
    return _pickNextFingerprintByMap(
      state.fingerprintCooldownUntilMs,
      current,
      nowMs,
    );
  }

  static String? _pickNextFingerprintByMap(
    Map<String, int> map,
    String current,
    int nowMs,
  ) {
    final normalized = current.trim().toLowerCase();
    final currentIdx = fingerprintPool.indexOf(normalized);
    if (currentIdx < 0) {
      return fingerprintPool.first;
    }
    for (var offset = 1; offset <= fingerprintPool.length; offset++) {
      final candidate =
          fingerprintPool[(currentIdx + offset) % fingerprintPool.length];
      if ((map[candidate] ?? 0) <= nowMs) {
        return candidate;
      }
    }
    return null;
  }

  static String? _nextTransport(String transport) {
    final normalized = transport.trim().toLowerCase();
    if (!transportPool.contains(normalized)) {
      return transportPool.first;
    }
    final idx = transportPool.indexOf(normalized);
    return transportPool[(idx + 1) % transportPool.length];
  }

  static int _backoffMsForFailures(int failures) {
    final safe = failures <= 0 ? 0 : failures;
    final shift = (safe - 1).clamp(0, 16);
    final rawSecs = 5 * (1 << shift);
    final cappedSecs = rawSecs > 300 ? 300 : rawSecs;
    return cappedSecs * 1000;
  }
}

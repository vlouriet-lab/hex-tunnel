import 'package:flutter_test/flutter_test.dart';
import 'package:hex_decensor/services/adaptive_tunnel_policy.dart';

void main() {
  group('AdaptiveTunnelPolicy', () {
    const nowMs = 1700000000000;

    AdaptiveProfileDescriptor buildProfile({
      String protocol = 'vless',
      String transport = 'xhttp',
      String fingerprint = 'chrome',
      bool tlsEnabled = true,
      bool supportsTransportFallback = true,
    }) {
      return AdaptiveProfileDescriptor(
        protocol: protocol,
        transport: transport,
        fingerprint: fingerprint,
        tlsEnabled: tlsEnabled,
        supportsTransportFallback: supportsTransportFallback,
      );
    }

    test('normalizes network environment key', () {
      expect(
        AdaptiveTunnelPolicy.normalizeEnvironment(
          networkTransport: 'WiFi',
          networkInterface: 'wlan0',
        ),
        'wifi',
      );
      expect(
        AdaptiveTunnelPolicy.normalizeEnvironment(
          networkTransport: 'MOBILE',
          networkInterface: 'rmnet_data0',
        ),
        'cellular',
      );
      expect(
        AdaptiveTunnelPolicy.normalizeEnvironment(
          networkTransport: 'ethernet',
          networkInterface: 'eth0',
        ),
        'ethernet',
      );
      expect(
        AdaptiveTunnelPolicy.normalizeEnvironment(
          networkTransport: 'vpn',
          networkInterface: 'tun0',
        ),
        'vpn',
      );

      // operatorHint appends to the base key
      expect(
        AdaptiveTunnelPolicy.normalizeEnvironment(
          networkTransport: 'MOBILE',
          networkInterface: 'rmnet_data0',
          operatorHint: 'MTS',
        ),
        'cellular|mts',
      );
      expect(
        AdaptiveTunnelPolicy.normalizeEnvironment(
          networkTransport: 'WiFi',
          networkInterface: 'wlan0',
          operatorHint: 'Beeline WiFi',
        ),
        'wifi|beelinewifi',
      );
      // Empty hint — no suffix
      expect(
        AdaptiveTunnelPolicy.normalizeEnvironment(
          networkTransport: 'WiFi',
          networkInterface: 'wlan0',
          operatorHint: '',
        ),
        'wifi',
      );
    });

    test('baseEnvironmentKey strips operator suffix', () {
      expect(
          AdaptiveTunnelPolicy.baseEnvironmentKey('cellular|mts'), 'cellular');
      expect(AdaptiveTunnelPolicy.baseEnvironmentKey('wifi|beeline'), 'wifi');
      expect(AdaptiveTunnelPolicy.baseEnvironmentKey('wifi'), 'wifi');
    });

    test(
        'materialize falls back to base key prefs when operator-specific key is absent',
        () {
      // Prefs exist under bare 'cellular'; request is for 'cellular|mts'
      final state = AdaptiveTunnelPolicyState.empty().copyWith(
        preferredTransportByEnv: const <String, String>{'cellular': 'ws'},
        preferredFingerprintByEnv: const <String, String>{
          'cellular': 'firefox'
        },
      );
      final profile = buildProfile();

      final result = AdaptiveTunnelPolicy.materialize(
        state,
        profile,
        environmentKey: 'cellular|mts',
        nowMs: nowMs,
        fingerprintSpoofingEnabled: true,
      );

      // Should pick up the base-key prefs as fallback
      expect(result.transport, 'ws');
      expect(result.fingerprint, 'firefox');
    });

    test('operator-specific prefs take priority over base key prefs', () {
      // 'cellular|mts' has its own pref (xhttp); base 'cellular' prefers 'ws'
      final state = AdaptiveTunnelPolicyState.empty().copyWith(
        preferredTransportByEnv: const <String, String>{
          'cellular': 'ws',
          'cellular|mts': 'xhttp',
        },
        preferredFingerprintByEnv: const <String, String>{
          'cellular': 'firefox',
          'cellular|mts': 'edge',
        },
      );
      final profile = buildProfile(transport: 'ws', fingerprint: 'firefox');

      final result = AdaptiveTunnelPolicy.materialize(
        state,
        profile,
        environmentKey: 'cellular|mts',
        nowMs: nowMs,
        fingerprintSpoofingEnabled: true,
      );

      expect(result.transport, 'xhttp');
      expect(result.fingerprint, 'edge');
    });

    test('operator key learns independently from base key', () {
      var state = const AdaptiveTunnelPolicyState.empty();
      final profile = buildProfile(transport: 'xhttp', fingerprint: 'chrome');

      // Two failures on cellular|mts
      state = AdaptiveTunnelPolicy.markFailure(
        state,
        profile,
        environmentKey: 'cellular|mts',
        reason: 'probe_timeout',
        nowMs: nowMs,
        fingerprintSpoofingEnabled: true,
      );
      state = AdaptiveTunnelPolicy.markFailure(
        state,
        profile,
        environmentKey: 'cellular|mts',
        reason: 'probe_timeout',
        nowMs: nowMs + 2000,
        fingerprintSpoofingEnabled: true,
      );

      // operator-specific prefs are written under the compound key
      expect(state.preferredTransportByEnv['cellular|mts'], isNotNull);
      // base key is untouched
      expect(state.preferredTransportByEnv.containsKey('cellular'), isFalse);
    });

    test('applies preferred strategy for environment', () {
      final state = AdaptiveTunnelPolicyState.empty().copyWith(
        preferredTransportByEnv: const <String, String>{'cellular': 'ws'},
        preferredFingerprintByEnv: const <String, String>{
          'cellular': 'firefox',
        },
      );
      final profile = buildProfile();

      final result = AdaptiveTunnelPolicy.materialize(
        state,
        profile,
        environmentKey: 'cellular',
        nowMs: nowMs,
        fingerprintSpoofingEnabled: true,
      );

      expect(result.transport, 'ws');
      expect(result.fingerprint, 'firefox');
      expect(result.state.mitigationNote, contains('network cellular'));
    });

    test('falls back to ws when current transport is in cooldown', () {
      final state = AdaptiveTunnelPolicyState.empty().copyWith(
        transportCooldownUntilMs: const <String, int>{
          'vless|xhttp': nowMs + 60000,
        },
      );
      final profile = buildProfile(transport: 'xhttp');

      final result = AdaptiveTunnelPolicy.materialize(
        state,
        profile,
        environmentKey: 'wifi',
        nowMs: nowMs,
        fingerprintSpoofingEnabled: true,
      );

      expect(result.transport, 'ws');
      expect(result.state.mitigationNote, contains('switch to WS'));
    });

    test('rotates fingerprint when current fingerprint is in cooldown', () {
      final state = AdaptiveTunnelPolicyState.empty().copyWith(
        fingerprintCooldownUntilMs: const <String, int>{
          'chrome': nowMs + 60000,
        },
      );
      final profile = buildProfile(fingerprint: 'chrome');

      final result = AdaptiveTunnelPolicy.materialize(
        state,
        profile,
        environmentKey: 'wifi',
        nowMs: nowMs,
        fingerprintSpoofingEnabled: true,
      );

      expect(result.fingerprint, isNotNull);
      expect(result.fingerprint, isNot('chrome'));
    });

    test('marks failure with environment preferences and cooldowns', () {
      final profile = buildProfile(transport: 'xhttp', fingerprint: 'chrome');

      final updated = AdaptiveTunnelPolicy.markFailure(
        const AdaptiveTunnelPolicyState.empty(),
        profile,
        environmentKey: 'wifi',
        reason: 'probe_timeout',
        nowMs: nowMs,
        fingerprintSpoofingEnabled: true,
      );

      expect(
          updated.transportCooldownUntilMs['vless|xhttp'], greaterThan(nowMs));
      expect(updated.preferredTransportByEnv['wifi'], 'ws');
      expect(updated.preferredFingerprintByEnv['wifi'], isNotNull);
      expect(updated.mitigationNote, contains('probe_timeout'));
    });

    test('marks success and stores stable strategy for environment', () {
      final profile = buildProfile(transport: 'ws', fingerprint: 'edge');
      final initial = AdaptiveTunnelPolicyState.empty().copyWith(
        transportCooldownUntilMs: const <String, int>{
          'vless|ws': nowMs + 20000,
        },
        fingerprintCooldownUntilMs: const <String, int>{
          'edge': nowMs + 20000,
        },
      );

      final updated = AdaptiveTunnelPolicy.markSuccess(
        initial,
        profile,
        environmentKey: 'cellular',
        nowMs: nowMs,
        fingerprintSpoofingEnabled: true,
      );

      expect(updated.transportCooldownUntilMs.containsKey('vless|ws'), isFalse);
      expect(updated.fingerprintCooldownUntilMs.containsKey('edge'), isFalse);
      expect(updated.preferredTransportByEnv['cellular'], 'ws');
      expect(updated.preferredFingerprintByEnv['cellular'], 'edge');
    });

    test('calculates penalty for profile in cooldown', () {
      final profile = buildProfile(transport: 'xhttp', fingerprint: 'chrome');
      final state = AdaptiveTunnelPolicyState.empty().copyWith(
        transportCooldownUntilMs: const <String, int>{
          'vless|xhttp': nowMs + 20000,
        },
        fingerprintCooldownUntilMs: const <String, int>{
          'chrome': nowMs + 20000,
        },
      );

      final penalty = AdaptiveTunnelPolicy.profilePenalty(
        state,
        profile,
        nowMs: nowMs,
      );

      expect(penalty, 330000);
    });

    test('stress failover chain alternates wifi/cellular preferences', () {
      var state = const AdaptiveTunnelPolicyState.empty();
      var tick = nowMs;

      for (var i = 0; i < 24; i++) {
        final env = i.isEven ? 'wifi' : 'cellular';
        final profile = buildProfile(
          transport: i % 3 == 0 ? 'xhttp' : 'ws',
          fingerprint: i.isEven ? 'chrome' : 'edge',
        );

        final materialized = AdaptiveTunnelPolicy.materialize(
          state,
          profile,
          environmentKey: env,
          nowMs: tick,
          fingerprintSpoofingEnabled: true,
        );
        state = materialized.state;

        state = AdaptiveTunnelPolicy.markFailure(
          state,
          profile,
          environmentKey: env,
          reason: 'stress_step_$i',
          nowMs: tick,
          fingerprintSpoofingEnabled: true,
        );

        final evicted = AdaptiveTunnelPolicy.evictExpired(
          state,
          nowMs: tick + 1500,
        );
        state = evicted;
        tick += 3000;
      }

      expect(state.preferredTransportByEnv['wifi'], isNotNull);
      expect(state.preferredTransportByEnv['cellular'], isNotNull);
      expect(state.preferredFingerprintByEnv['wifi'], isNotNull);
      expect(state.preferredFingerprintByEnv['cellular'], isNotNull);
      expect(
        AdaptiveTunnelPolicy.environmentStrategyCount(state),
        greaterThanOrEqualTo(2),
      );
    });

    test('stress chain converges after repeated successes per environment', () {
      var state = const AdaptiveTunnelPolicyState.empty();
      var tick = nowMs;
      final wifiProfile = buildProfile(transport: 'ws', fingerprint: 'firefox');
      final cellProfile = buildProfile(transport: 'xhttp', fingerprint: 'edge');

      for (var i = 0; i < 12; i++) {
        final env = i.isEven ? 'wifi' : 'cellular';
        final profile = i.isEven ? wifiProfile : cellProfile;

        state = AdaptiveTunnelPolicy.markFailure(
          state,
          profile,
          environmentKey: env,
          reason: 'warmup_$i',
          nowMs: tick,
          fingerprintSpoofingEnabled: true,
        );
        tick += 2000;
      }

      for (var i = 0; i < 20; i++) {
        final env = i.isEven ? 'wifi' : 'cellular';
        final profile = i.isEven ? wifiProfile : cellProfile;
        state = AdaptiveTunnelPolicy.markSuccess(
          state,
          profile,
          environmentKey: env,
          nowMs: tick,
          fingerprintSpoofingEnabled: true,
        );
        tick += 2000;
      }

      final settled = AdaptiveTunnelPolicy.evictExpired(
        state,
        nowMs: tick + 400000,
      );

      expect(settled.transportCooldownUntilMs, isEmpty);
      expect(settled.fingerprintCooldownUntilMs, isEmpty);
      expect(settled.preferredTransportByEnv['wifi'], 'ws');
      expect(settled.preferredTransportByEnv['cellular'], 'xhttp');
      expect(settled.preferredFingerprintByEnv['wifi'], 'firefox');
      expect(settled.preferredFingerprintByEnv['cellular'], 'edge');
    });

    test('state json roundtrip keeps all policy fields', () {
      final state = AdaptiveTunnelPolicyState.empty().copyWith(
        transportCooldownUntilMs: const <String, int>{
          'vless|xhttp': nowMs + 10000,
        },
        fingerprintCooldownUntilMs: const <String, int>{
          'chrome': nowMs + 10000,
        },
        preferredTransportByEnv: const <String, String>{
          'wifi': 'ws',
        },
        preferredFingerprintByEnv: const <String, String>{
          'wifi': 'firefox',
        },
        mitigationNote: 'adaptive note',
      );

      final json = state.toJson();
      final restored = AdaptiveTunnelPolicyState.fromJson(json);

      expect(restored.transportCooldownUntilMs, state.transportCooldownUntilMs);
      expect(
        restored.fingerprintCooldownUntilMs,
        state.fingerprintCooldownUntilMs,
      );
      expect(restored.preferredTransportByEnv, state.preferredTransportByEnv);
      expect(
        restored.preferredFingerprintByEnv,
        state.preferredFingerprintByEnv,
      );
      expect(restored.mitigationNote, state.mitigationNote);
    });
  });
}

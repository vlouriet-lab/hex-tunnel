import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hex_decensor/config/singbox_config_generator.dart';
import 'package:hex_decensor/models/proxy_profile.dart';
import 'package:hex_decensor/models/routing_mode.dart';
import 'package:hex_decensor/models/routing_runtime_policy.dart';

void main() {
  group('Routing runtime policy in config generator', () {
    const profile = ProxyProfile(
      protocol: 'vless',
      server: 'edge.example.com',
      port: 443,
      uuid: '11111111-1111-1111-1111-111111111111',
      tls: true,
      sni: 'edge.example.com',
      transport: 'ws',
      wsPath: '/',
      rawUri: 'vless://example',
      isValid: true,
    );

    test('uses runtime RU suffix override in ruleBased route and dns rules', () {
      const policy = RoutingRuntimePolicy(
        ruDomainSuffixes: <String>['.custom-ru'],
      );

      final configJson = SingBoxConfigGenerator.generate(
        profile,
        RoutingMode.ruleBased,
        routingRuntimePolicy: policy,
      );
      final config = jsonDecode(configJson) as Map<String, dynamic>;

      final dns = Map<String, dynamic>.from(config['dns'] as Map);
      final dnsRules = (dns['rules'] as List)
          .whereType<Map>()
          .map((rule) => Map<String, dynamic>.from(rule))
          .toList(growable: false);
      final route = Map<String, dynamic>.from(config['route'] as Map);
      final routeRules = (route['rules'] as List)
          .whereType<Map>()
          .map((rule) => Map<String, dynamic>.from(rule))
          .toList(growable: false);

      final dnsRuRule = dnsRules.firstWhere(
        (r) => r.containsKey('domain_suffix'),
      );
      final routeRuRule = routeRules.firstWhere(
        (r) => r.containsKey('domain_suffix') && r['outbound'] == 'direct',
      );

      expect(dnsRuRule['domain_suffix'], <String>['.custom-ru']);
      expect(routeRuRule['domain_suffix'], <String>['.custom-ru']);
    });

    test('falls back to built-in RU suffixes when policy has empty override', () {
      const policy = RoutingRuntimePolicy();

      final configJson = SingBoxConfigGenerator.generate(
        profile,
        RoutingMode.ruleBased,
        routingRuntimePolicy: policy,
      );
      final config = jsonDecode(configJson) as Map<String, dynamic>;

      final route = Map<String, dynamic>.from(config['route'] as Map);
      final routeRules = (route['rules'] as List)
          .whereType<Map>()
          .map((rule) => Map<String, dynamic>.from(rule))
          .toList(growable: false);
      final routeRuRule = routeRules.firstWhere(
        (r) => r.containsKey('domain_suffix') && r['outbound'] == 'direct',
      );
      final suffixes = (routeRuRule['domain_suffix'] as List)
          .map((e) => '$e')
          .toList(growable: false);

      expect(suffixes, contains('.ru'));
      expect(suffixes, contains('.рф'));
    });
  });
}

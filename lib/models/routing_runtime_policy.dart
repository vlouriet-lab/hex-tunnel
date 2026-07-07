class RoutingRuntimePolicy {
  final int schemaVersion;
  final List<String> ruDomainSuffixes;
  final List<String> forceDirectDomains;
  final List<String> forceProxyDomains;

  const RoutingRuntimePolicy({
    this.schemaVersion = 1,
    this.ruDomainSuffixes = const <String>[],
    this.forceDirectDomains = const <String>[],
    this.forceProxyDomains = const <String>[],
  });

  bool get hasOverrides =>
      ruDomainSuffixes.isNotEmpty ||
      forceDirectDomains.isNotEmpty ||
      forceProxyDomains.isNotEmpty;

  RoutingRuntimePolicy copyWith({
    int? schemaVersion,
    List<String>? ruDomainSuffixes,
    List<String>? forceDirectDomains,
    List<String>? forceProxyDomains,
  }) {
    return RoutingRuntimePolicy(
      schemaVersion: schemaVersion ?? this.schemaVersion,
      ruDomainSuffixes: ruDomainSuffixes ?? this.ruDomainSuffixes,
      forceDirectDomains: forceDirectDomains ?? this.forceDirectDomains,
      forceProxyDomains: forceProxyDomains ?? this.forceProxyDomains,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'schemaVersion': schemaVersion,
      'ruDomainSuffixes': ruDomainSuffixes,
      'forceDirectDomains': forceDirectDomains,
      'forceProxyDomains': forceProxyDomains,
    };
  }

  factory RoutingRuntimePolicy.fromJson(Map<String, dynamic> json) {
    List<String> parseSuffixes(String key) {
      final raw = json[key];
      if (raw is! List) return const <String>[];
      return raw
          .map((e) => '$e'.trim().toLowerCase())
          .where((v) => v.isNotEmpty)
          .map((v) => v.startsWith('.') ? v : '.$v')
          .toSet()
          .toList(growable: false);
    }

    List<String> parseDomains(String key) {
      final raw = json[key];
      if (raw is! List) return const <String>[];
      return raw
          .map((e) => '$e'.trim().toLowerCase())
          .where((v) => v.isNotEmpty)
          .toSet()
          .toList(growable: false);
    }

    return RoutingRuntimePolicy(
      schemaVersion: (json['schemaVersion'] as num?)?.toInt() ?? 1,
      ruDomainSuffixes: parseSuffixes('ruDomainSuffixes'),
      forceDirectDomains: parseDomains('forceDirectDomains'),
      forceProxyDomains: parseDomains('forceProxyDomains'),
    );
  }
}

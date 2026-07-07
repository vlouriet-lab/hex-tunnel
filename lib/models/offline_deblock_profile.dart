enum OfflineDeblockProfile {
  soft,
  balanced,
  hybrid,
  aggressive,
  ultra,
  custom,
}

extension OfflineDeblockProfileExt on OfflineDeblockProfile {
  String get key {
    switch (this) {
      case OfflineDeblockProfile.soft:
        return 'soft';
      case OfflineDeblockProfile.balanced:
        return 'balanced';
      case OfflineDeblockProfile.hybrid:
        return 'hybrid';
      case OfflineDeblockProfile.aggressive:
        return 'aggressive';
      case OfflineDeblockProfile.ultra:
        return 'ultra';
      case OfflineDeblockProfile.custom:
        return 'custom';
    }
  }

  String get displayName {
    switch (this) {
      case OfflineDeblockProfile.soft:
        return 'Мягкий';
      case OfflineDeblockProfile.balanced:
        return 'Стандартный';
      case OfflineDeblockProfile.hybrid:
        return 'Авто (Cloudflare)';
      case OfflineDeblockProfile.aggressive:
        return 'Агрессивный';
      case OfflineDeblockProfile.ultra:
        return 'Ультра';
      case OfflineDeblockProfile.custom:
        return 'Настраиваемый';
    }
  }

  String get description {
    switch (this) {
      case OfflineDeblockProfile.soft:
        return 'Безопасный DNS и сглаживание соединений. Не ограничивает протоколы — хороший стартовый профиль.';
      case OfflineDeblockProfile.balanced:
        return 'Безопасный DNS с защитой от фильтрации. Блокирует быстрые видео-протоколы для надёжного обхода блокировок.';
      case OfflineDeblockProfile.hybrid:
        return 'Направляет заблокированные сайты через Cloudflare. Работает как запасной вариант, если основной канал недоступен.';
      case OfflineDeblockProfile.aggressive:
        return 'Жёсткий режим: отключает нестандартные протоколы. Помогает в сетях с глубокой фильтрацией (школы, офисы, операторы РФ).';
      case OfflineDeblockProfile.ultra:
        return 'Максимально строгие ограничения. Отключает всё лишнее — для самых тяжёлых условий фильтрации.';
      case OfflineDeblockProfile.custom:
        return 'Ручная настройка всех ограничений. Для опытных пользователей.';
    }
  }

  String get runtimeStatus {
    switch (this) {
      case OfflineDeblockProfile.soft:
        return 'Безопасный DNS активен';
      case OfflineDeblockProfile.balanced:
        return 'Безопасный DNS, QUIC-протокол отключён';
      case OfflineDeblockProfile.hybrid:
        return 'Заблокированные сайты — через Cloudflare';
      case OfflineDeblockProfile.aggressive:
        return 'Безопасный DNS, нестандартные протоколы отключены';
      case OfflineDeblockProfile.ultra:
        return 'Максимальные ограничения активны';
      case OfflineDeblockProfile.custom:
        return 'Пользовательские настройки активны';
    }
  }

  List<String> get highlights {
    switch (this) {
      case OfflineDeblockProfile.soft:
        return const [
          'Зашифрованный DNS с приоритетом IPv4',
          'DNS-кэш для ускорения открытия сайтов',
          'Не ограничивает тип соединения',
        ];
      case OfflineDeblockProfile.balanced:
        return const [
          'Зашифрованный DNS с защитой от подмены',
          'Отключает QUIC-протокол для обхода блокировок',
          'Оптимален для большинства российских сетей',
        ];
      case OfflineDeblockProfile.hybrid:
        return const [
          'Запасной вариант, если основной канал деблокировки недоступен',
          'Автоматически подключает бесплатный Cloudflare WARP',
          'Иностранный трафик — через Cloudflare, российские сайты — напрямую',
        ];
      case OfflineDeblockProfile.aggressive:
        return const [
          'Максимально защищённый DNS',
          'Отключает UDP (помогает при жёстких блокировках)',
          'Отключает IPv6 для предотвращения утечки через обходные адреса',
        ];
      case OfflineDeblockProfile.ultra:
        return const [
          'Полная фильтрация DNS-запросов',
          'Отключает UDP и IPv6',
          'Уменьшенный размер пакетов для нестабильных подключений',
        ];
      case OfflineDeblockProfile.custom:
        return const [
          'Гибкое управление DNS и типом соединений',
          'Ручная настройка размера пакетов',
          'Для тонкой настройки под вашу сеть',
        ];
    }
  }

  String get limitationText {
    switch (this) {
      case OfflineDeblockProfile.soft:
        return 'Не скрывает IP-адрес. Может не помочь при самых жёстких блокировках.';
      case OfflineDeblockProfile.balanced:
        return 'Не скрывает IP-адрес. Не обходит блокировки по IP, но хорошо работает с большинством HTTPS-сайтов.';
      case OfflineDeblockProfile.hybrid:
        return 'Резервный режим: не обеспечивает анонимность и VPN-защиту.';
      case OfflineDeblockProfile.aggressive:
        return 'Может ухудшить работу игр, видеозвонков и некоторых приложений.';
      case OfflineDeblockProfile.ultra:
        return 'Самый строгий режим: часть приложений может работать хуже.';
      case OfflineDeblockProfile.custom:
        return 'Неверные настройки могут ухудшить работу сети.';
    }
  }

  static OfflineDeblockProfile fromKey(String key) {
    switch (key) {
      case 'soft':
        return OfflineDeblockProfile.soft;
      case 'aggressive':
        return OfflineDeblockProfile.aggressive;
      case 'hybrid':
        return OfflineDeblockProfile.hybrid;
      case 'ultra':
        return OfflineDeblockProfile.ultra;
      case 'custom':
        return OfflineDeblockProfile.custom;
      case 'balanced':
        return OfflineDeblockProfile.balanced;
      default:
        return OfflineDeblockProfile.hybrid;
    }
  }
}

class OfflineDeblockSettings {
  final bool blockUdp443;
  final bool blockAllUdp;
  final bool blockIpv6;
  final bool blockDnsHttpsSvcb;
  final bool blockDnsAaaa;
  final bool sniffOverrideDestination;
  final int mtu;
  final bool tlsFragmentEnabled;
  final int tlsFragmentSize;
  final int tlsFragmentSleepMs;
  final bool tlsMixedSniCase;
  final bool tlsPaddingEnabled;
  final int tlsPaddingSize;
  final bool warpEnabled;
  final String warpDetourMode;
  final String warpLicenseKey;
  final String warpPrivateKey;
  final String warpPeerPublicKey;
  final String warpLocalAddressV4;
  final String warpLocalAddressV6;
  final String warpEndpointHost;
  final int warpEndpointPort;

  const OfflineDeblockSettings({
    required this.blockUdp443,
    required this.blockAllUdp,
    required this.blockIpv6,
    required this.blockDnsHttpsSvcb,
    required this.blockDnsAaaa,
    required this.sniffOverrideDestination,
    required this.mtu,
    required this.tlsFragmentEnabled,
    required this.tlsFragmentSize,
    required this.tlsFragmentSleepMs,
    required this.tlsMixedSniCase,
    required this.tlsPaddingEnabled,
    required this.tlsPaddingSize,
    required this.warpEnabled,
    required this.warpDetourMode,
    required this.warpLicenseKey,
    required this.warpPrivateKey,
    required this.warpPeerPublicKey,
    required this.warpLocalAddressV4,
    required this.warpLocalAddressV6,
    required this.warpEndpointHost,
    required this.warpEndpointPort,
  });

  const OfflineDeblockSettings.customDefault()
      : blockUdp443 = true,
        blockAllUdp = false,
        blockIpv6 = false,
        blockDnsHttpsSvcb = true,
        blockDnsAaaa = false,
        sniffOverrideDestination = false,
        mtu = 1360,
        tlsFragmentEnabled = false,
        tlsFragmentSize = 20,
        tlsFragmentSleepMs = 4,
        tlsMixedSniCase = false,
        tlsPaddingEnabled = false,
        tlsPaddingSize = 256,
        warpEnabled = false,
        warpDetourMode = 'off',
        warpLicenseKey = '',
        warpPrivateKey = '',
        warpPeerPublicKey = '',
        warpLocalAddressV4 = '',
        warpLocalAddressV6 = '',
        warpEndpointHost = '162.159.193.10',
        warpEndpointPort = 2408;

  static OfflineDeblockSettings forProfile(OfflineDeblockProfile profile) {
    switch (profile) {
      case OfflineDeblockProfile.soft:
        return const OfflineDeblockSettings(
          blockUdp443: false,
          blockAllUdp: false,
          blockIpv6: false,
          blockDnsHttpsSvcb: false,
          blockDnsAaaa: false,
          sniffOverrideDestination: false,
          mtu: 1400,
          tlsFragmentEnabled: true,
          tlsFragmentSize: 20,
          tlsFragmentSleepMs: 4,
          tlsMixedSniCase: false,
          tlsPaddingEnabled: true,
          tlsPaddingSize: 256,
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
      case OfflineDeblockProfile.balanced:
        return const OfflineDeblockSettings(
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
      case OfflineDeblockProfile.hybrid:
        return const OfflineDeblockSettings(
          blockUdp443: true,
          blockAllUdp: false,
          blockIpv6: false,
          blockDnsHttpsSvcb: true,
          blockDnsAaaa: false,
          sniffOverrideDestination: false,
          mtu: 1280,
          tlsFragmentEnabled: false,
          tlsFragmentSize: 20,
          tlsFragmentSleepMs: 4,
          tlsMixedSniCase: false,
          tlsPaddingEnabled: false,
          tlsPaddingSize: 256,
          warpEnabled: true,
          warpDetourMode: 'hybrid',
          warpLicenseKey: '',
          warpPrivateKey: '',
          warpPeerPublicKey: '',
          warpLocalAddressV4: '',
          warpLocalAddressV6: '',
          warpEndpointHost: '162.159.193.10',
          warpEndpointPort: 2408,
        );
      case OfflineDeblockProfile.aggressive:
        return const OfflineDeblockSettings(
          blockUdp443: true,
          blockAllUdp: true,
          blockIpv6: true,
          blockDnsHttpsSvcb: true,
          blockDnsAaaa: true,
          sniffOverrideDestination: true,
          mtu: 1280,
          tlsFragmentEnabled: true,
          tlsFragmentSize: 20,
          tlsFragmentSleepMs: 4,
          tlsMixedSniCase: true,
          tlsPaddingEnabled: true,
          tlsPaddingSize: 512,
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
      case OfflineDeblockProfile.ultra:
        return const OfflineDeblockSettings(
          blockUdp443: true,
          blockAllUdp: true,
          blockIpv6: true,
          blockDnsHttpsSvcb: true,
          blockDnsAaaa: true,
          sniffOverrideDestination: true,
          mtu: 1200,
          tlsFragmentEnabled: true,
          tlsFragmentSize: 16,
          tlsFragmentSleepMs: 6,
          tlsMixedSniCase: true,
          tlsPaddingEnabled: true,
          tlsPaddingSize: 1024,
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
      case OfflineDeblockProfile.custom:
        return const OfflineDeblockSettings.customDefault();
    }
  }

  bool get hasWarpWireguardConfig {
    return warpPrivateKey.trim().isNotEmpty &&
        warpPeerPublicKey.trim().isNotEmpty &&
        warpLocalAddressV4.trim().isNotEmpty;
  }

  bool get wantsWarpDetour {
    return warpEnabled &&
        warpDetourMode.trim().isNotEmpty &&
        warpDetourMode.trim() != 'off';
  }

  OfflineDeblockSettings copyWith({
    bool? blockUdp443,
    bool? blockAllUdp,
    bool? blockIpv6,
    bool? blockDnsHttpsSvcb,
    bool? blockDnsAaaa,
    bool? sniffOverrideDestination,
    int? mtu,
    bool? tlsFragmentEnabled,
    int? tlsFragmentSize,
    int? tlsFragmentSleepMs,
    bool? tlsMixedSniCase,
    bool? tlsPaddingEnabled,
    int? tlsPaddingSize,
    bool? warpEnabled,
    String? warpDetourMode,
    String? warpLicenseKey,
    String? warpPrivateKey,
    String? warpPeerPublicKey,
    String? warpLocalAddressV4,
    String? warpLocalAddressV6,
    String? warpEndpointHost,
    int? warpEndpointPort,
  }) {
    return OfflineDeblockSettings(
      blockUdp443: blockUdp443 ?? this.blockUdp443,
      blockAllUdp: blockAllUdp ?? this.blockAllUdp,
      blockIpv6: blockIpv6 ?? this.blockIpv6,
      blockDnsHttpsSvcb: blockDnsHttpsSvcb ?? this.blockDnsHttpsSvcb,
      blockDnsAaaa: blockDnsAaaa ?? this.blockDnsAaaa,
      sniffOverrideDestination:
          sniffOverrideDestination ?? this.sniffOverrideDestination,
      mtu: mtu ?? this.mtu,
      tlsFragmentEnabled: tlsFragmentEnabled ?? this.tlsFragmentEnabled,
      tlsFragmentSize: tlsFragmentSize ?? this.tlsFragmentSize,
      tlsFragmentSleepMs: tlsFragmentSleepMs ?? this.tlsFragmentSleepMs,
      tlsMixedSniCase: tlsMixedSniCase ?? this.tlsMixedSniCase,
      tlsPaddingEnabled: tlsPaddingEnabled ?? this.tlsPaddingEnabled,
      tlsPaddingSize: tlsPaddingSize ?? this.tlsPaddingSize,
      warpEnabled: warpEnabled ?? this.warpEnabled,
      warpDetourMode: warpDetourMode ?? this.warpDetourMode,
      warpLicenseKey: warpLicenseKey ?? this.warpLicenseKey,
      warpPrivateKey: warpPrivateKey ?? this.warpPrivateKey,
      warpPeerPublicKey: warpPeerPublicKey ?? this.warpPeerPublicKey,
      warpLocalAddressV4: normalizeWarpInterfaceAddress(
          warpLocalAddressV4 ?? this.warpLocalAddressV4),
      warpLocalAddressV6: normalizeWarpInterfaceAddress(
          warpLocalAddressV6 ?? this.warpLocalAddressV6),
      warpEndpointHost: warpEndpointHost ?? this.warpEndpointHost,
      warpEndpointPort: warpEndpointPort ?? this.warpEndpointPort,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'blockUdp443': blockUdp443,
      'blockAllUdp': blockAllUdp,
      'blockIpv6': blockIpv6,
      'blockDnsHttpsSvcb': blockDnsHttpsSvcb,
      'blockDnsAaaa': blockDnsAaaa,
      'sniffOverrideDestination': sniffOverrideDestination,
      'mtu': mtu,
      'tlsFragmentEnabled': tlsFragmentEnabled,
      'tlsFragmentSize': tlsFragmentSize,
      'tlsFragmentSleepMs': tlsFragmentSleepMs,
      'tlsMixedSniCase': tlsMixedSniCase,
      'tlsPaddingEnabled': tlsPaddingEnabled,
      'tlsPaddingSize': tlsPaddingSize,
      'warpEnabled': warpEnabled,
      'warpDetourMode': warpDetourMode,
      'warpLicenseKey': warpLicenseKey,
      'warpPrivateKey': warpPrivateKey,
      'warpPeerPublicKey': warpPeerPublicKey,
      'warpLocalAddressV4': warpLocalAddressV4,
      'warpLocalAddressV6': warpLocalAddressV6,
      'warpEndpointHost': warpEndpointHost,
      'warpEndpointPort': warpEndpointPort,
    };
  }

  static String normalizeWarpInterfaceAddress(String rawAddress) {
    final trimmed = rawAddress.trim();
    if (trimmed.isEmpty || trimmed.contains('/')) {
      return trimmed;
    }
    final prefix = trimmed.contains(':') ? 128 : 32;
    return '$trimmed/$prefix';
  }

  static OfflineDeblockSettings fromJson(Map<String, dynamic> json) {
    final rawMtu = (json['mtu'] as num?)?.toInt() ?? 1360;
    final normalizedMtu =
        rawMtu < 1200 ? 1200 : (rawMtu > 1500 ? 1500 : rawMtu);
    final rawFragmentSize = (json['tlsFragmentSize'] as num?)?.toInt() ?? 20;
    final normalizedFragmentSize = rawFragmentSize < 10
        ? 10
        : (rawFragmentSize > 30 ? 30 : rawFragmentSize);
    final rawFragmentSleep = (json['tlsFragmentSleepMs'] as num?)?.toInt() ?? 4;
    final normalizedFragmentSleep = rawFragmentSleep < 2
        ? 2
        : (rawFragmentSleep > 8 ? 8 : rawFragmentSleep);
    final rawPadding = (json['tlsPaddingSize'] as num?)?.toInt() ?? 256;
    final normalizedPadding =
        rawPadding < 1 ? 1 : (rawPadding > 1500 ? 1500 : rawPadding);
    final rawWarpPort = (json['warpEndpointPort'] as num?)?.toInt() ?? 2408;
    final normalizedWarpPort =
        rawWarpPort < 1 ? 1 : (rawWarpPort > 65535 ? 65535 : rawWarpPort);
    final normalizedWarpEndpoint = _normalizeWarpEndpoint(
      (json['warpEndpointHost'] as String? ?? '162.159.193.10').trim(),
      normalizedWarpPort,
    );

    return OfflineDeblockSettings(
      blockUdp443: json['blockUdp443'] as bool? ?? true,
      blockAllUdp: json['blockAllUdp'] as bool? ?? false,
      blockIpv6: json['blockIpv6'] as bool? ?? false,
      blockDnsHttpsSvcb: json['blockDnsHttpsSvcb'] as bool? ?? true,
      blockDnsAaaa: json['blockDnsAaaa'] as bool? ?? false,
      sniffOverrideDestination:
          json['sniffOverrideDestination'] as bool? ?? false,
      mtu: normalizedMtu,
      tlsFragmentEnabled: json['tlsFragmentEnabled'] as bool? ?? false,
      tlsFragmentSize: normalizedFragmentSize,
      tlsFragmentSleepMs: normalizedFragmentSleep,
      tlsMixedSniCase: json['tlsMixedSniCase'] as bool? ?? false,
      tlsPaddingEnabled: json['tlsPaddingEnabled'] as bool? ?? false,
      tlsPaddingSize: normalizedPadding,
      warpEnabled: json['warpEnabled'] as bool? ?? false,
      warpDetourMode: (json['warpDetourMode'] as String? ?? 'off').trim(),
      warpLicenseKey: (json['warpLicenseKey'] as String? ?? '').trim(),
      warpPrivateKey: (json['warpPrivateKey'] as String? ?? '').trim(),
      warpPeerPublicKey: (json['warpPeerPublicKey'] as String? ?? '').trim(),
      warpLocalAddressV4: normalizeWarpInterfaceAddress(
        (json['warpLocalAddressV4'] as String? ?? '').trim(),
      ),
      warpLocalAddressV6: normalizeWarpInterfaceAddress(
        (json['warpLocalAddressV6'] as String? ?? '').trim(),
      ),
      warpEndpointHost: normalizedWarpEndpoint.host,
      warpEndpointPort: normalizedWarpEndpoint.port,
    );
  }

  static ({String host, int port}) _normalizeWarpEndpoint(
    String rawHost,
    int fallbackPort,
  ) {
    final trimmed = rawHost.trim();
    if (trimmed.isEmpty) {
      return (host: '162.159.193.10', port: fallbackPort);
    }

    if (trimmed.startsWith('[')) {
      final ipv6Match = RegExp(r'^\[(.+)\]:(\d+)$').firstMatch(trimmed);
      if (ipv6Match != null) {
        final parsedPort = int.tryParse(ipv6Match.group(2)!);
        return (
          host: ipv6Match.group(1)!.trim(),
          port: parsedPort != null && parsedPort > 0 && parsedPort <= 65535
              ? parsedPort
              : fallbackPort,
        );
      }
    }

    final parsed = Uri.tryParse(
      trimmed.contains('://') ? trimmed : 'udp://$trimmed',
    );
    if (parsed != null && parsed.host.isNotEmpty) {
      return (
        host: parsed.host.trim(),
        port: parsed.hasPort ? parsed.port : fallbackPort,
      );
    }

    return (host: trimmed, port: fallbackPort);
  }
}

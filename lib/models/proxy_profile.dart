/// Профиль прокси-сервера — порт структуры ProxyProfile из SingBoxConfig.h.
class ProxyProfile {
  final String name;
  final String
      protocol; // vless | shadowsocks | trojan | tuic | vmess | hysteria | hysteria2 | shadowsocksr | wireguard | awg | socks | http | ssh
  final String server;
  final int port;

  // Аутентификация
  final String uuid; // VLESS / TUIC
  final String password; // Shadowsocks / Trojan / TUIC
  final String
      method; // Shadowsocks: шифрование (aes-128-gcm, chacha20-poly1305, …)
  final String flow; // VLESS: xtls-rprx-vision

  // TLS
  final bool tls;
  final String sni;
  final String fingerprint; // chrome | firefox | safari | edge | random
  final String alpn; // h2,http/1.1

  // Reality (VLESS)
  final bool reality;
  final String realityPublicKey;
  final String realityShortId;

  // Транспорт
  final String transport; // tcp | ws | grpc | h2
  final String wsPath;
  final String wsHost;
  final String grpcServiceName;

  // TUIC
  final String congestionControl; // bbr | cubic | new_reno
  final String udpRelayMode; // native | quic

  // VMess
  final int alterId;
  final String security; // auto | none | aes-128-gcm | chacha20-poly1305

  // Hysteria / Hysteria2
  final int upMbps;
  final int downMbps;
  final String obfsPassword; // Hysteria2 salamander obfs
  final bool insecure; // skip TLS cert verify

  // WireGuard / AWG / Warp
  final String wgPrivateKey;
  final String wgPeerPublicKey;
  final String wgPreSharedKey;
  final String wgLocalAddresses; // comma-separated CIDRs
  final int wgMtu;
  // AWG extras
  final String wgReserved; // "b1,b2,b3" decimal bytes
  final int wgJunkPacketCount;
  final int wgJunkPacketMinSize;
  final int wgJunkPacketMaxSize;
  final int wgInitPacketJunkSize;
  final int wgResponsePacketJunkSize;
  final int wgInitPacketMagicHeader;
  final int wgResponsePacketMagicHeader;
  final int wgTransportPacketMagicHeader;
  final int wgUnderloadPacketMagicHeader;

  // ShadowsocksR
  final String ssrObfs;
  final String ssrObfsParam;
  final String ssrProtocol;
  final String ssrProtocolParam;

  // SSH / SOCKS / HTTP proxy
  final String user;
  final String sshPrivateKey;
  final String sshHostKeyAlgo;

  // Метаданные
  final String rawUri;
  final bool isValid;

  const ProxyProfile({
    this.name = '',
    required this.protocol,
    required this.server,
    this.port = 443,
    this.uuid = '',
    this.password = '',
    this.method = '',
    this.flow = '',
    this.tls = true,
    this.sni = '',
    this.fingerprint = 'chrome',
    this.alpn = '',
    this.reality = false,
    this.realityPublicKey = '',
    this.realityShortId = '',
    this.transport = 'tcp',
    this.wsPath = '/',
    this.wsHost = '',
    this.grpcServiceName = '',
    this.congestionControl = 'bbr',
    this.udpRelayMode = 'native',
    this.alterId = 0,
    this.security = 'auto',
    this.upMbps = 0,
    this.downMbps = 0,
    this.obfsPassword = '',
    this.insecure = false,
    this.wgPrivateKey = '',
    this.wgPeerPublicKey = '',
    this.wgPreSharedKey = '',
    this.wgLocalAddresses = '',
    this.wgMtu = 1408,
    this.wgReserved = '',
    this.wgJunkPacketCount = 0,
    this.wgJunkPacketMinSize = 0,
    this.wgJunkPacketMaxSize = 0,
    this.wgInitPacketJunkSize = 0,
    this.wgResponsePacketJunkSize = 0,
    this.wgInitPacketMagicHeader = 0,
    this.wgResponsePacketMagicHeader = 0,
    this.wgTransportPacketMagicHeader = 0,
    this.wgUnderloadPacketMagicHeader = 0,
    this.ssrObfs = '',
    this.ssrObfsParam = '',
    this.ssrProtocol = '',
    this.ssrProtocolParam = '',
    this.user = '',
    this.sshPrivateKey = '',
    this.sshHostKeyAlgo = '',
    this.rawUri = '',
    this.isValid = false,
  });

  /// Краткое описание для отображения в UI
  String get displayName {
    if (name.isNotEmpty) return name;
    return '${protocol.toUpperCase()} $server:$port';
  }

  /// Имя без эмодзи-флагов и декоративных иконок.
  String get displayNameClean {
    final source = displayName;
    final noFlags = source.replaceAll(
      RegExp(r'[\u{1F1E6}-\u{1F1FF}]{2}', unicode: true),
      '',
    );
    final noMarkers = noFlags.replaceAll(
      RegExp(
        r'\[(?:BL|WL|WHITE|BLACK|RU|T|BS)\]',
        caseSensitive: false,
      ),
      '',
    );
    final noDecor = noMarkers
        .replaceAll('🌐', '')
        .replaceAll('🛰', '')
        .replaceAll('📡', '')
        .replaceAll('•', ' ')
        .replaceAll('|', ' ');
    final cleaned = noDecor.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (cleaned.isNotEmpty) {
      return cleaned;
    }
    return '${protocol.toUpperCase()} $server:$port';
  }

  String get protocolLabel {
    switch (protocol) {
      case 'vless':
        return reality ? 'VLESS/Reality' : 'VLESS';
      case 'shadowsocks':
        return 'Shadowsocks';
      case 'trojan':
        return 'Trojan';
      case 'tuic':
        return 'TUIC';
      case 'vmess':
        return 'VMess';
      case 'hysteria':
        return 'Hysteria';
      case 'hysteria2':
        return 'Hysteria2';
      case 'shadowsocksr':
        return 'ShadowsocksR';
      case 'wireguard':
        return 'WireGuard';
      case 'awg':
        return 'AmneziaWG';
      case 'socks':
        return 'SOCKS5';
      case 'http':
        return 'HTTP Proxy';
      case 'ssh':
        return 'SSH';
      default:
        return protocol.toUpperCase();
    }
  }

  ProxyProfile copyWith({
    String? name,
    String? protocol,
    String? server,
    int? port,
    String? uuid,
    String? password,
    String? method,
    String? flow,
    bool? tls,
    String? sni,
    String? fingerprint,
    String? alpn,
    bool? reality,
    String? realityPublicKey,
    String? realityShortId,
    String? transport,
    String? wsPath,
    String? wsHost,
    String? grpcServiceName,
    String? congestionControl,
    String? udpRelayMode,
    int? alterId,
    String? security,
    int? upMbps,
    int? downMbps,
    String? obfsPassword,
    bool? insecure,
    String? wgPrivateKey,
    String? wgPeerPublicKey,
    String? wgPreSharedKey,
    String? wgLocalAddresses,
    int? wgMtu,
    String? wgReserved,
    int? wgJunkPacketCount,
    int? wgJunkPacketMinSize,
    int? wgJunkPacketMaxSize,
    int? wgInitPacketJunkSize,
    int? wgResponsePacketJunkSize,
    int? wgInitPacketMagicHeader,
    int? wgResponsePacketMagicHeader,
    int? wgTransportPacketMagicHeader,
    int? wgUnderloadPacketMagicHeader,
    String? ssrObfs,
    String? ssrObfsParam,
    String? ssrProtocol,
    String? ssrProtocolParam,
    String? user,
    String? sshPrivateKey,
    String? sshHostKeyAlgo,
    String? rawUri,
    bool? isValid,
  }) {
    return ProxyProfile(
      name: name ?? this.name,
      protocol: protocol ?? this.protocol,
      server: server ?? this.server,
      port: port ?? this.port,
      uuid: uuid ?? this.uuid,
      password: password ?? this.password,
      method: method ?? this.method,
      flow: flow ?? this.flow,
      tls: tls ?? this.tls,
      sni: sni ?? this.sni,
      fingerprint: fingerprint ?? this.fingerprint,
      alpn: alpn ?? this.alpn,
      reality: reality ?? this.reality,
      realityPublicKey: realityPublicKey ?? this.realityPublicKey,
      realityShortId: realityShortId ?? this.realityShortId,
      transport: transport ?? this.transport,
      wsPath: wsPath ?? this.wsPath,
      wsHost: wsHost ?? this.wsHost,
      grpcServiceName: grpcServiceName ?? this.grpcServiceName,
      congestionControl: congestionControl ?? this.congestionControl,
      udpRelayMode: udpRelayMode ?? this.udpRelayMode,
      alterId: alterId ?? this.alterId,
      security: security ?? this.security,
      upMbps: upMbps ?? this.upMbps,
      downMbps: downMbps ?? this.downMbps,
      obfsPassword: obfsPassword ?? this.obfsPassword,
      insecure: insecure ?? this.insecure,
      wgPrivateKey: wgPrivateKey ?? this.wgPrivateKey,
      wgPeerPublicKey: wgPeerPublicKey ?? this.wgPeerPublicKey,
      wgPreSharedKey: wgPreSharedKey ?? this.wgPreSharedKey,
      wgLocalAddresses: wgLocalAddresses ?? this.wgLocalAddresses,
      wgMtu: wgMtu ?? this.wgMtu,
      wgReserved: wgReserved ?? this.wgReserved,
      wgJunkPacketCount: wgJunkPacketCount ?? this.wgJunkPacketCount,
      wgJunkPacketMinSize: wgJunkPacketMinSize ?? this.wgJunkPacketMinSize,
      wgJunkPacketMaxSize: wgJunkPacketMaxSize ?? this.wgJunkPacketMaxSize,
      wgInitPacketJunkSize: wgInitPacketJunkSize ?? this.wgInitPacketJunkSize,
      wgResponsePacketJunkSize:
          wgResponsePacketJunkSize ?? this.wgResponsePacketJunkSize,
      wgInitPacketMagicHeader:
          wgInitPacketMagicHeader ?? this.wgInitPacketMagicHeader,
      wgResponsePacketMagicHeader:
          wgResponsePacketMagicHeader ?? this.wgResponsePacketMagicHeader,
      wgTransportPacketMagicHeader:
          wgTransportPacketMagicHeader ?? this.wgTransportPacketMagicHeader,
      wgUnderloadPacketMagicHeader:
          wgUnderloadPacketMagicHeader ?? this.wgUnderloadPacketMagicHeader,
      ssrObfs: ssrObfs ?? this.ssrObfs,
      ssrObfsParam: ssrObfsParam ?? this.ssrObfsParam,
      ssrProtocol: ssrProtocol ?? this.ssrProtocol,
      ssrProtocolParam: ssrProtocolParam ?? this.ssrProtocolParam,
      user: user ?? this.user,
      sshPrivateKey: sshPrivateKey ?? this.sshPrivateKey,
      sshHostKeyAlgo: sshHostKeyAlgo ?? this.sshHostKeyAlgo,
      rawUri: rawUri ?? this.rawUri,
      isValid: isValid ?? this.isValid,
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'protocol': protocol,
        'server': server,
        'port': port,
        'uuid': uuid,
        'password': password,
        'method': method,
        'flow': flow,
        'tls': tls,
        'sni': sni,
        'fingerprint': fingerprint,
        'alpn': alpn,
        'reality': reality,
        'realityPublicKey': realityPublicKey,
        'realityShortId': realityShortId,
        'transport': transport,
        'wsPath': wsPath,
        'wsHost': wsHost,
        'grpcServiceName': grpcServiceName,
        'congestionControl': congestionControl,
        'udpRelayMode': udpRelayMode,
        'alterId': alterId,
        'security': security,
        'upMbps': upMbps,
        'downMbps': downMbps,
        'obfsPassword': obfsPassword,
        'insecure': insecure,
        'wgPrivateKey': wgPrivateKey,
        'wgPeerPublicKey': wgPeerPublicKey,
        'wgPreSharedKey': wgPreSharedKey,
        'wgLocalAddresses': wgLocalAddresses,
        'wgMtu': wgMtu,
        'wgReserved': wgReserved,
        'wgJunkPacketCount': wgJunkPacketCount,
        'wgJunkPacketMinSize': wgJunkPacketMinSize,
        'wgJunkPacketMaxSize': wgJunkPacketMaxSize,
        'wgInitPacketJunkSize': wgInitPacketJunkSize,
        'wgResponsePacketJunkSize': wgResponsePacketJunkSize,
        'wgInitPacketMagicHeader': wgInitPacketMagicHeader,
        'wgResponsePacketMagicHeader': wgResponsePacketMagicHeader,
        'wgTransportPacketMagicHeader': wgTransportPacketMagicHeader,
        'wgUnderloadPacketMagicHeader': wgUnderloadPacketMagicHeader,
        'ssrObfs': ssrObfs,
        'ssrObfsParam': ssrObfsParam,
        'ssrProtocol': ssrProtocol,
        'ssrProtocolParam': ssrProtocolParam,
        'user': user,
        'sshPrivateKey': sshPrivateKey,
        'sshHostKeyAlgo': sshHostKeyAlgo,
        'rawUri': rawUri,
        'isValid': isValid,
      };

  factory ProxyProfile.fromJson(Map<String, dynamic> j) => ProxyProfile(
        name: j['name'] as String? ?? '',
        protocol: j['protocol'] as String? ?? 'vless',
        server: j['server'] as String? ?? '',
        port: j['port'] as int? ?? 443,
        uuid: j['uuid'] as String? ?? '',
        password: j['password'] as String? ?? '',
        method: j['method'] as String? ?? '',
        flow: j['flow'] as String? ?? '',
        tls: j['tls'] as bool? ?? true,
        sni: j['sni'] as String? ?? '',
        fingerprint: j['fingerprint'] as String? ?? 'chrome',
        alpn: j['alpn'] as String? ?? '',
        reality: j['reality'] as bool? ?? false,
        realityPublicKey: j['realityPublicKey'] as String? ?? '',
        realityShortId: j['realityShortId'] as String? ?? '',
        transport: j['transport'] as String? ?? 'tcp',
        wsPath: j['wsPath'] as String? ?? '/',
        wsHost: j['wsHost'] as String? ?? '',
        grpcServiceName: j['grpcServiceName'] as String? ?? '',
        congestionControl: j['congestionControl'] as String? ?? 'bbr',
        udpRelayMode: j['udpRelayMode'] as String? ?? 'native',
        alterId: j['alterId'] as int? ?? 0,
        security: j['security'] as String? ?? 'auto',
        upMbps: j['upMbps'] as int? ?? 0,
        downMbps: j['downMbps'] as int? ?? 0,
        obfsPassword: j['obfsPassword'] as String? ?? '',
        insecure: j['insecure'] as bool? ?? false,
        wgPrivateKey: j['wgPrivateKey'] as String? ?? '',
        wgPeerPublicKey: j['wgPeerPublicKey'] as String? ?? '',
        wgPreSharedKey: j['wgPreSharedKey'] as String? ?? '',
        wgLocalAddresses: j['wgLocalAddresses'] as String? ?? '',
        wgMtu: j['wgMtu'] as int? ?? 1408,
        wgReserved: j['wgReserved'] as String? ?? '',
        wgJunkPacketCount: j['wgJunkPacketCount'] as int? ?? 0,
        wgJunkPacketMinSize: j['wgJunkPacketMinSize'] as int? ?? 0,
        wgJunkPacketMaxSize: j['wgJunkPacketMaxSize'] as int? ?? 0,
        wgInitPacketJunkSize: j['wgInitPacketJunkSize'] as int? ?? 0,
        wgResponsePacketJunkSize: j['wgResponsePacketJunkSize'] as int? ?? 0,
        wgInitPacketMagicHeader: j['wgInitPacketMagicHeader'] as int? ?? 0,
        wgResponsePacketMagicHeader:
            j['wgResponsePacketMagicHeader'] as int? ?? 0,
        wgTransportPacketMagicHeader:
            j['wgTransportPacketMagicHeader'] as int? ?? 0,
        wgUnderloadPacketMagicHeader:
            j['wgUnderloadPacketMagicHeader'] as int? ?? 0,
        ssrObfs: j['ssrObfs'] as String? ?? '',
        ssrObfsParam: j['ssrObfsParam'] as String? ?? '',
        ssrProtocol: j['ssrProtocol'] as String? ?? '',
        ssrProtocolParam: j['ssrProtocolParam'] as String? ?? '',
        user: j['user'] as String? ?? '',
        sshPrivateKey: j['sshPrivateKey'] as String? ?? '',
        sshHostKeyAlgo: j['sshHostKeyAlgo'] as String? ?? '',
        rawUri: j['rawUri'] as String? ?? '',
        isValid: j['isValid'] as bool? ?? false,
      );
}

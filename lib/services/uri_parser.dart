import 'dart:convert';
import '../models/proxy_profile.dart';

/// URI-парсер прокси-ссылок.
/// Порт класса URIParser из SingBoxConfig.h (SOTA Segment).
///
/// Поддерживаемые протоколы:
///   vless://      — VLESS + Reality TLS
///   ss://         — Shadowsocks (SIP002 и legacy)
///   trojan://     — Trojan
///   tuic://       — TUIC v5
///   vmess://      — VMess
///   hysteria://   — Hysteria v1
///   hy2://        — Hysteria2
///   hysteria2://  — Hysteria2
///   ssr://        — ShadowsocksR
///   wireguard://  — WireGuard
///   wg://         — WireGuard (alias)
///   awg://        — AmneziaWG
///   socks5://     — SOCKS5 proxy
///   socks://      — SOCKS5 proxy (alias)
///   http://       — HTTP proxy (только с @-авторизацией)
///   ssh://        — SSH tunnel
class UriParser {
  UriParser._();

  static bool isSupported(String uri) {
    final t = uri.trim();
    return t.startsWith('vless://') ||
        t.startsWith('ss://') ||
        t.startsWith('trojan://') ||
        t.startsWith('tuic://') ||
        t.startsWith('vmess://') ||
        t.startsWith('hysteria://') ||
        t.startsWith('hy2://') ||
        t.startsWith('hysteria2://') ||
        t.startsWith('ssr://') ||
        t.startsWith('wireguard://') ||
        t.startsWith('wg://') ||
        t.startsWith('awg://') ||
        t.startsWith('socks5://') ||
        t.startsWith('socks://') ||
        t.startsWith('ssh://') ||
        // http:// as proxy only when auth credentials present
        (t.startsWith('http://') && t.contains('@'));
  }

  static ProxyProfile parse(String uri) {
    final t = uri.trim();
    if (t.startsWith('vless://')) return _parseVless(t);
    if (t.startsWith('ss://')) return _parseShadowsocks(t);
    if (t.startsWith('trojan://')) return _parseTrojan(t);
    if (t.startsWith('tuic://')) return _parseTuic(t);
    if (t.startsWith('vmess://')) return _parseVmess(t);
    if (t.startsWith('hysteria://')) return _parseHysteria(t);
    if (t.startsWith('hy2://') || t.startsWith('hysteria2://')) {
      return _parseHysteria2(t);
    }
    if (t.startsWith('ssr://')) return _parseShadowsocksR(t);
    if (t.startsWith('wireguard://') || t.startsWith('wg://')) {
      return _parseWireGuard(t);
    }
    if (t.startsWith('awg://')) return _parseAmneziaWG(t);
    if (t.startsWith('socks5://') || t.startsWith('socks://')) {
      return _parseSocks(t);
    }
    if (t.startsWith('http://')) return _parseHttpProxy(t);
    if (t.startsWith('ssh://')) return _parseSsh(t);
    return ProxyProfile(protocol: '', server: '', rawUri: uri);
  }

  // ── VLESS ─────────────────────────────────────────────────────────────────
  // vless://uuid@server:port?params#name
  static ProxyProfile _parseVless(String uri) {
    try {
      String body = uri.substring(8);
      final name = _extractFragment(body);
      if (name != null) body = body.substring(0, body.lastIndexOf('#'));

      final params = _extractQuery(body);
      if (params != null) body = body.substring(0, body.indexOf('?'));

      final atIdx = body.indexOf('@');
      if (atIdx < 0) {
        return ProxyProfile(protocol: 'vless', server: '', rawUri: uri);
      }

      final uuid = body.substring(0, atIdx);
      final (server, port) = _parseHostPort(body.substring(atIdx + 1));

      final security = params?['security'] ?? 'tls';
      final isReality = security == 'reality';
      final transport = params?['type'] ?? 'tcp';

      return ProxyProfile(
        name: name ?? 'VLESS $server',
        protocol: 'vless',
        server: server,
        port: port,
        uuid: uuid,
        flow: params?['flow'] ?? '',
        tls: security == 'tls' || isReality,
        sni: params?['sni'] ?? '',
        fingerprint: params?['fp'] ?? 'chrome',
        alpn: params?['alpn'] ?? '',
        reality: isReality,
        realityPublicKey: params?['pbk'] ?? '',
        realityShortId: params?['sid'] ?? '',
        transport: transport,
        wsPath: (transport == 'ws' || transport == 'xhttp')
            ? (params?['path'] ?? '/')
            : '/',
        wsHost: (transport == 'ws' || transport == 'xhttp')
            ? (params?['host'] ?? '')
            : '',
        grpcServiceName:
            transport == 'grpc' ? (params?['serviceName'] ?? '') : '',
        rawUri: uri,
        isValid: server.isNotEmpty && uuid.isNotEmpty,
      );
    } catch (_) {
      return ProxyProfile(protocol: 'vless', server: '', rawUri: uri);
    }
  }

  // ── Shadowsocks ───────────────────────────────────────────────────────────
  // SIP002: ss://base64(method:password)@server:port[/?plugin=...]#name
  // Legacy: ss://base64(method:password@server:port)#name
  static ProxyProfile _parseShadowsocks(String uri) {
    try {
      String body = uri.substring(5);
      final name = _extractFragment(body);
      if (name != null) body = body.substring(0, body.lastIndexOf('#'));

      String method = '';
      String password = '';
      String server = '';
      int port = 443;

      final atIdx = body.indexOf('@');
      if (atIdx >= 0) {
        // SIP002
        final userInfo = _base64Decode(body.substring(0, atIdx));
        String hostPort = body.substring(atIdx + 1);
        final qIdx = hostPort.indexOf('?');
        if (qIdx >= 0) hostPort = hostPort.substring(0, qIdx);
        final colonIdx = userInfo.indexOf(':');
        if (colonIdx >= 0) {
          method = userInfo.substring(0, colonIdx);
          password = userInfo.substring(colonIdx + 1);
        }
        (server, port) = _parseHostPort(hostPort);
      } else {
        // Legacy
        final qIdx = body.indexOf('?');
        if (qIdx >= 0) body = body.substring(0, qIdx);
        final decoded = _base64Decode(body);
        final at2 = decoded.indexOf('@');
        if (at2 >= 0) {
          final userInfo = decoded.substring(0, at2);
          final colonIdx = userInfo.indexOf(':');
          if (colonIdx >= 0) {
            method = userInfo.substring(0, colonIdx);
            password = userInfo.substring(colonIdx + 1);
          }
          (server, port) = _parseHostPort(decoded.substring(at2 + 1));
        }
      }

      return ProxyProfile(
        name: name ?? 'SS $server',
        protocol: 'shadowsocks',
        server: server,
        port: port,
        password: password,
        method: method,
        tls: false,
        rawUri: uri,
        isValid: server.isNotEmpty && password.isNotEmpty && method.isNotEmpty,
      );
    } catch (_) {
      return ProxyProfile(protocol: 'shadowsocks', server: '', rawUri: uri);
    }
  }

  // ── Trojan ────────────────────────────────────────────────────────────────
  // trojan://password@server:port?params#name
  static ProxyProfile _parseTrojan(String uri) {
    try {
      String body = uri.substring(9);
      final name = _extractFragment(body);
      if (name != null) body = body.substring(0, body.lastIndexOf('#'));

      final params = _extractQuery(body);
      if (params != null) body = body.substring(0, body.indexOf('?'));

      final atIdx = body.indexOf('@');
      if (atIdx < 0) {
        return ProxyProfile(protocol: 'trojan', server: '', rawUri: uri);
      }

      final password = body.substring(0, atIdx);
      final (server, port) = _parseHostPort(body.substring(atIdx + 1));
      final transport = params?['type'] ?? 'tcp';

      return ProxyProfile(
        name: name ?? 'Trojan $server',
        protocol: 'trojan',
        server: server,
        port: port,
        password: password,
        tls: true,
        sni: params?['sni'] ?? server,
        fingerprint: params?['fp'] ?? 'chrome',
        alpn: params?['alpn'] ?? 'h2,http/1.1',
        transport: transport,
        wsPath: transport == 'ws' ? (params?['path'] ?? '/') : '/',
        wsHost: transport == 'ws' ? (params?['host'] ?? '') : '',
        grpcServiceName:
            transport == 'grpc' ? (params?['serviceName'] ?? '') : '',
        rawUri: uri,
        isValid: server.isNotEmpty && password.isNotEmpty,
      );
    } catch (_) {
      return ProxyProfile(protocol: 'trojan', server: '', rawUri: uri);
    }
  }

  // ── TUIC ──────────────────────────────────────────────────────────────────
  // tuic://uuid:password@server:port?params#name
  static ProxyProfile _parseTuic(String uri) {
    try {
      String body = uri.substring(7);
      final name = _extractFragment(body);
      if (name != null) body = body.substring(0, body.lastIndexOf('#'));

      final params = _extractQuery(body);
      if (params != null) body = body.substring(0, body.indexOf('?'));

      final atIdx = body.indexOf('@');
      if (atIdx < 0) {
        return ProxyProfile(protocol: 'tuic', server: '', rawUri: uri);
      }

      final userInfo = body.substring(0, atIdx);
      final colonIdx = userInfo.indexOf(':');
      final uuid = colonIdx >= 0 ? userInfo.substring(0, colonIdx) : userInfo;
      final password = colonIdx >= 0 ? userInfo.substring(colonIdx + 1) : '';
      final (server, port) = _parseHostPort(body.substring(atIdx + 1));

      return ProxyProfile(
        name: name ?? 'TUIC $server',
        protocol: 'tuic',
        server: server,
        port: port,
        uuid: uuid,
        password: password,
        tls: true,
        sni: params?['sni'] ?? server,
        alpn: params?['alpn'] ?? 'h3',
        congestionControl: params?['congestion_control'] ?? 'bbr',
        udpRelayMode: params?['udp_relay_mode'] ?? 'native',
        rawUri: uri,
        isValid: server.isNotEmpty && uuid.isNotEmpty,
      );
    } catch (_) {
      return ProxyProfile(protocol: 'tuic', server: '', rawUri: uri);
    }
  }

  // ── VMess ─────────────────────────────────────────────────────────────────
  // vmess://BASE64(JSON)
  static ProxyProfile _parseVmess(String uri) {
    try {
      final encoded = uri.substring('vmess://'.length).split('#').first;
      final decoded = _base64Decode(encoded);
      if (decoded.isEmpty) {
        return ProxyProfile(protocol: 'vmess', server: '', rawUri: uri);
      }
      final j = jsonDecode(decoded) as Map<String, dynamic>;
      final server = j['add'] as String? ?? '';
      final port = int.tryParse((j['port'] ?? '443').toString()) ?? 443;
      final uuid = j['id'] as String? ?? '';
      final alterId = int.tryParse((j['aid'] ?? '0').toString()) ?? 0;
      final security =
          j['scy'] as String? ?? j['security'] as String? ?? 'auto';
      final net = j['net'] as String? ?? 'tcp';
      final host = j['host'] as String? ?? '';
      final path = j['path'] as String? ?? '/';
      final tlsStr = j['tls'] as String? ?? '';
      final tls = tlsStr == 'tls' || tlsStr == 'reality';
      final isReality = tlsStr == 'reality';
      final sni = j['sni'] as String? ?? '';
      final fp = j['fp'] as String? ?? 'chrome';
      final alpn = j['alpn'] as String? ?? '';
      final name = Uri.decodeComponent(j['ps'] as String? ?? 'VMess $server');
      final pbk = j['pbk'] as String? ?? '';
      final sid = j['sid'] as String? ?? '';
      final flow = j['flow'] as String? ?? '';
      return ProxyProfile(
        name: name,
        protocol: 'vmess',
        server: server,
        port: port,
        uuid: uuid,
        alterId: alterId,
        security: security,
        tls: tls,
        sni: sni,
        fingerprint: fp,
        alpn: alpn,
        reality: isReality,
        realityPublicKey: pbk,
        realityShortId: sid,
        flow: flow,
        transport: net,
        wsPath: (net == 'ws' || net == 'h2') ? path : '/',
        wsHost: (net == 'ws' || net == 'h2') ? host : '',
        grpcServiceName: net == 'grpc' ? path : '',
        rawUri: uri,
        isValid: server.isNotEmpty && uuid.isNotEmpty,
      );
    } catch (_) {
      return ProxyProfile(protocol: 'vmess', server: '', rawUri: uri);
    }
  }

  // ── Hysteria ──────────────────────────────────────────────────────────────
  // hysteria://server:port?upmbps=100&downmbps=100&auth=pass&insecure=1&peer=sni#name
  static ProxyProfile _parseHysteria(String uri) {
    try {
      String body = uri.substring('hysteria://'.length);
      final name = _extractFragment(body);
      if (name != null) body = body.substring(0, body.lastIndexOf('#'));
      final params = _extractQuery(body) ?? {};
      if (body.contains('?')) body = body.substring(0, body.indexOf('?'));
      final (server, port) = _parseHostPort(body);
      return ProxyProfile(
        name: name ?? 'Hysteria $server',
        protocol: 'hysteria',
        server: server,
        port: port,
        password: params['auth'] ?? params['auth_str'] ?? '',
        tls: true,
        sni: params['peer'] ?? params['sni'] ?? server,
        alpn: params['alpn'] ?? 'h3',
        insecure: params['insecure'] == '1',
        upMbps: int.tryParse(params['upmbps'] ?? '0') ?? 0,
        downMbps: int.tryParse(params['downmbps'] ?? '0') ?? 0,
        obfsPassword: params['obfsParam'] ?? params['obfs-password'] ?? '',
        rawUri: uri,
        isValid: server.isNotEmpty,
      );
    } catch (_) {
      return ProxyProfile(protocol: 'hysteria', server: '', rawUri: uri);
    }
  }

  // ── Hysteria2 ─────────────────────────────────────────────────────────────
  // hy2://auth@server:port?sni=SNI&insecure=1&obfs=salamander&obfs-password=pass#name
  static ProxyProfile _parseHysteria2(String uri) {
    try {
      final scheme = uri.startsWith('hy2://') ? 'hy2://' : 'hysteria2://';
      String body = uri.substring(scheme.length);
      final name = _extractFragment(body);
      if (name != null) body = body.substring(0, body.lastIndexOf('#'));
      final params = _extractQuery(body) ?? {};
      if (body.contains('?')) body = body.substring(0, body.indexOf('?'));
      String password = '';
      String hostPort = body;
      final atIdx = body.indexOf('@');
      if (atIdx >= 0) {
        password = Uri.decodeComponent(body.substring(0, atIdx));
        hostPort = body.substring(atIdx + 1);
      }
      final (server, port) = _parseHostPort(hostPort);
      return ProxyProfile(
        name: name ?? 'Hysteria2 $server',
        protocol: 'hysteria2',
        server: server,
        port: port,
        password: password,
        tls: true,
        sni: params['sni'] ?? server,
        insecure: params['insecure'] == '1',
        obfsPassword: params['obfs-password'] ?? '',
        rawUri: uri,
        isValid: server.isNotEmpty,
      );
    } catch (_) {
      return ProxyProfile(protocol: 'hysteria2', server: '', rawUri: uri);
    }
  }

  // ── ShadowsocksR ──────────────────────────────────────────────────────────
  // ssr://BASE64(server:port:protocol:method:obfs:BASE64(pass)/?obfsparam=...&protoparam=...&remarks=...)
  static ProxyProfile _parseShadowsocksR(String uri) {
    try {
      final encoded = uri.substring('ssr://'.length);
      final decoded = _base64Decode(encoded);
      if (decoded.isEmpty) {
        return ProxyProfile(protocol: 'shadowsocksr', server: '', rawUri: uri);
      }
      final params = <String, String>{};
      String mainPart = decoded;
      final qIdx = decoded.indexOf('/?');
      if (qIdx >= 0) {
        mainPart = decoded.substring(0, qIdx);
        final qs = decoded.substring(qIdx + 2);
        for (final part in qs.split('&')) {
          final eq = part.indexOf('=');
          if (eq < 0) continue;
          params[part.substring(0, eq)] = _base64Decode(part.substring(eq + 1));
        }
      }
      final parts = mainPart.split(':');
      if (parts.length < 6) {
        return ProxyProfile(protocol: 'shadowsocksr', server: '', rawUri: uri);
      }
      final server = parts[0];
      final port = int.tryParse(parts[1]) ?? 443;
      final ssrProtocol = parts[2];
      final method = parts[3];
      final ssrObfs = parts[4];
      final password = _base64Decode(parts[5]);
      final remarks = params['remarks']?.trim() ?? '';
      return ProxyProfile(
        name: remarks.isNotEmpty ? remarks : 'SSR $server',
        protocol: 'shadowsocksr',
        server: server,
        port: port,
        password: password,
        method: method,
        ssrObfs: ssrObfs,
        ssrObfsParam: params['obfsparam'] ?? '',
        ssrProtocol: ssrProtocol,
        ssrProtocolParam: params['protoparam'] ?? '',
        tls: false,
        rawUri: uri,
        isValid: server.isNotEmpty && password.isNotEmpty,
      );
    } catch (_) {
      return ProxyProfile(protocol: 'shadowsocksr', server: '', rawUri: uri);
    }
  }

  // ── WireGuard ─────────────────────────────────────────────────────────────
  // wireguard://server:port?private_key=...&pub=...&psk=...&addr=10.0.0.2/32&mtu=1408#name
  static ProxyProfile _parseWireGuard(String uri) {
    try {
      final isWg = uri.startsWith('wg://');
      String body =
          uri.substring(isWg ? 'wg://'.length : 'wireguard://'.length);
      final name = _extractFragment(body);
      if (name != null) body = body.substring(0, body.lastIndexOf('#'));
      final params = _extractQuery(body) ?? {};
      if (body.contains('?')) body = body.substring(0, body.indexOf('?'));
      final (server, port) = _parseHostPort(body);
      return ProxyProfile(
        name: name ?? 'WireGuard $server',
        protocol: 'wireguard',
        server: server,
        port: port,
        wgPrivateKey: params['private_key'] ?? '',
        wgPeerPublicKey: params['pub'] ?? params['public_key'] ?? '',
        wgPreSharedKey: params['psk'] ?? params['pre_shared_key'] ?? '',
        wgLocalAddresses: params['addr'] ?? params['address'] ?? '10.0.0.2/32',
        wgMtu: int.tryParse(params['mtu'] ?? '1408') ?? 1408,
        tls: false,
        rawUri: uri,
        isValid: server.isNotEmpty,
      );
    } catch (_) {
      return ProxyProfile(protocol: 'wireguard', server: '', rawUri: uri);
    }
  }

  // ── AmneziaWG ─────────────────────────────────────────────────────────────
  // awg://server:port?private_key=...&pub=...&psk=...&addr=...&mtu=...
  //   &reserved=b1,b2,b3&junk_packet_count=...&junk_packet_min_size=...
  //   &junk_packet_max_size=...&init_packet_junk_size=...
  //   &response_packet_junk_size=...&init_packet_magic_header=...
  //   &response_packet_magic_header=...&transport_packet_magic_header=...
  //   &underload_packet_magic_header=...#name
  static ProxyProfile _parseAmneziaWG(String uri) {
    try {
      String body = uri.substring('awg://'.length);
      final name = _extractFragment(body);
      if (name != null) body = body.substring(0, body.lastIndexOf('#'));
      final params = _extractQuery(body) ?? {};
      if (body.contains('?')) body = body.substring(0, body.indexOf('?'));
      final (server, port) = _parseHostPort(body);
      return ProxyProfile(
        name: name ?? 'AWG $server',
        protocol: 'awg',
        server: server,
        port: port,
        wgPrivateKey: params['private_key'] ?? '',
        wgPeerPublicKey: params['pub'] ?? params['public_key'] ?? '',
        wgPreSharedKey: params['psk'] ?? '',
        wgLocalAddresses: params['addr'] ?? '10.0.0.2/32',
        wgMtu: int.tryParse(params['mtu'] ?? '1408') ?? 1408,
        wgReserved: params['reserved'] ?? '',
        wgJunkPacketCount:
            int.tryParse(params['junk_packet_count'] ?? '0') ?? 0,
        wgJunkPacketMinSize:
            int.tryParse(params['junk_packet_min_size'] ?? '0') ?? 0,
        wgJunkPacketMaxSize:
            int.tryParse(params['junk_packet_max_size'] ?? '0') ?? 0,
        wgInitPacketJunkSize:
            int.tryParse(params['init_packet_junk_size'] ?? '0') ?? 0,
        wgResponsePacketJunkSize:
            int.tryParse(params['response_packet_junk_size'] ?? '0') ?? 0,
        wgInitPacketMagicHeader:
            int.tryParse(params['init_packet_magic_header'] ?? '0') ?? 0,
        wgResponsePacketMagicHeader:
            int.tryParse(params['response_packet_magic_header'] ?? '0') ?? 0,
        wgTransportPacketMagicHeader:
            int.tryParse(params['transport_packet_magic_header'] ?? '0') ?? 0,
        wgUnderloadPacketMagicHeader:
            int.tryParse(params['underload_packet_magic_header'] ?? '0') ?? 0,
        tls: false,
        rawUri: uri,
        isValid: server.isNotEmpty,
      );
    } catch (_) {
      return ProxyProfile(protocol: 'awg', server: '', rawUri: uri);
    }
  }

  // ── SOCKS5 ────────────────────────────────────────────────────────────────
  // socks5://[user:pass@]server:port[#name]
  static ProxyProfile _parseSocks(String uri) {
    try {
      final isSocks5 = uri.startsWith('socks5://');
      String body =
          uri.substring(isSocks5 ? 'socks5://'.length : 'socks://'.length);
      final name = _extractFragment(body);
      if (name != null) body = body.substring(0, body.lastIndexOf('#'));
      if (body.contains('?')) body = body.substring(0, body.indexOf('?'));
      String user = '';
      String password = '';
      String hostPort = body;
      final atIdx = body.indexOf('@');
      if (atIdx >= 0) {
        final userInfo = Uri.decodeComponent(body.substring(0, atIdx));
        hostPort = body.substring(atIdx + 1);
        final colonIdx = userInfo.indexOf(':');
        if (colonIdx >= 0) {
          user = userInfo.substring(0, colonIdx);
          password = userInfo.substring(colonIdx + 1);
        } else {
          user = userInfo;
        }
      }
      final (server, port) = _parseHostPort(hostPort);
      return ProxyProfile(
        name: name ?? 'SOCKS5 $server',
        protocol: 'socks',
        server: server,
        port: port,
        user: user,
        password: password,
        tls: false,
        rawUri: uri,
        isValid: server.isNotEmpty,
      );
    } catch (_) {
      return ProxyProfile(protocol: 'socks', server: '', rawUri: uri);
    }
  }

  // ── HTTP Proxy ────────────────────────────────────────────────────────────
  // http://user:pass@server:port[#name]
  static ProxyProfile _parseHttpProxy(String uri) {
    try {
      String body = uri.substring('http://'.length);
      final name = _extractFragment(body);
      if (name != null) body = body.substring(0, body.lastIndexOf('#'));
      if (body.contains('?')) body = body.substring(0, body.indexOf('?'));
      String user = '';
      String password = '';
      String hostPort = body;
      final atIdx = body.indexOf('@');
      if (atIdx >= 0) {
        final userInfo = Uri.decodeComponent(body.substring(0, atIdx));
        hostPort = body.substring(atIdx + 1);
        final colonIdx = userInfo.indexOf(':');
        if (colonIdx >= 0) {
          user = userInfo.substring(0, colonIdx);
          password = userInfo.substring(colonIdx + 1);
        } else {
          user = userInfo;
        }
      }
      if (hostPort.contains('/')) {
        hostPort = hostPort.substring(0, hostPort.indexOf('/'));
      }
      final (server, port) = _parseHostPort(hostPort);
      return ProxyProfile(
        name: name ?? 'HTTP $server:$port',
        protocol: 'http',
        server: server,
        port: port,
        user: user,
        password: password,
        tls: false,
        rawUri: uri,
        isValid: server.isNotEmpty,
      );
    } catch (_) {
      return ProxyProfile(protocol: 'http', server: '', rawUri: uri);
    }
  }

  // ── SSH ───────────────────────────────────────────────────────────────────
  // ssh://[user[:password]@]server:port[?pk=BASE64(privateKey)&hka=algo][#name]
  static ProxyProfile _parseSsh(String uri) {
    try {
      String body = uri.substring('ssh://'.length);
      final name = _extractFragment(body);
      if (name != null) body = body.substring(0, body.lastIndexOf('#'));
      final params = _extractQuery(body) ?? {};
      if (body.contains('?')) body = body.substring(0, body.indexOf('?'));
      String user = 'root';
      String password = '';
      String hostPort = body;
      final atIdx = body.indexOf('@');
      if (atIdx >= 0) {
        final userInfo = Uri.decodeComponent(body.substring(0, atIdx));
        hostPort = body.substring(atIdx + 1);
        final colonIdx = userInfo.indexOf(':');
        if (colonIdx >= 0) {
          user = userInfo.substring(0, colonIdx);
          password = userInfo.substring(colonIdx + 1);
        } else {
          user = userInfo;
        }
      }
      final (server, port) = _parseHostPort(hostPort);
      final pk = params['pk'];
      return ProxyProfile(
        name: name ?? 'SSH $server',
        protocol: 'ssh',
        server: server,
        port: port > 0 ? port : 22,
        user: user,
        password: password,
        sshPrivateKey: pk != null ? _base64Decode(pk) : '',
        sshHostKeyAlgo: params['hka'] ?? '',
        tls: false,
        rawUri: uri,
        isValid: server.isNotEmpty,
      );
    } catch (_) {
      return ProxyProfile(protocol: 'ssh', server: '', rawUri: uri);
    }
  }

  // ── Утилиты ───────────────────────────────────────────────────────────────

  static (String server, int port) _parseHostPort(String hostPort) {
    if (hostPort.startsWith('[')) {
      // IPv6: [::1]:port
      final close = hostPort.indexOf(']');
      if (close < 0) return (hostPort, 443);
      final host = hostPort.substring(1, close);
      final rest = hostPort.substring(close + 1);
      final port =
          rest.startsWith(':') ? (int.tryParse(rest.substring(1)) ?? 443) : 443;
      return (host, port);
    }
    final colonIdx = hostPort.lastIndexOf(':');
    if (colonIdx < 0) return (hostPort, 443);
    final server = hostPort.substring(0, colonIdx);
    final port = int.tryParse(hostPort.substring(colonIdx + 1)) ?? 443;
    return (server, port);
  }

  static String? _extractFragment(String body) {
    final idx = body.lastIndexOf('#');
    if (idx < 0) return null;
    return Uri.decodeComponent(body.substring(idx + 1)).trim();
  }

  static Map<String, String>? _extractQuery(String body) {
    final idx = body.indexOf('?');
    if (idx < 0) return null;
    final qs = body.substring(idx + 1);
    final map = <String, String>{};
    for (final part in qs.split('&')) {
      final eq = part.indexOf('=');
      if (eq < 0) continue;
      final k = Uri.decodeComponent(part.substring(0, eq));
      final v = Uri.decodeComponent(part.substring(eq + 1));
      map[k] = v;
    }
    return map.isEmpty ? null : map;
  }

  static String _base64Decode(String input) {
    // Normalize: url-safe → standard + padding
    String s = input.replaceAll('-', '+').replaceAll('_', '/');
    while (s.length % 4 != 0) {
      s += '=';
    }
    try {
      return utf8.decode(base64.decode(s));
    } catch (_) {
      return '';
    }
  }
}

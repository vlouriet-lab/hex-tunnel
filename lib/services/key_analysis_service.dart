import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/proxy_profile.dart';
import 'uri_parser.dart';

class KeyAnalysisResult {
  final bool parseOk;
  final String inputScheme;
  final ProxyProfile? profile;
  final Map<String, String> basicInfo;
  final Map<String, String> networkInfo;
  final List<String> notes;

  const KeyAnalysisResult({
    required this.parseOk,
    required this.inputScheme,
    required this.profile,
    required this.basicInfo,
    required this.networkInfo,
    required this.notes,
  });
}

class KeyAnalysisService {
  KeyAnalysisService._();

  static Future<KeyAnalysisResult> analyzeUri(
    String rawUri, {
    bool withNetworkChecks = true,
  }) async {
    final uri = rawUri.trim();
    final scheme = _extractScheme(uri);

    if (!UriParser.isSupported(uri)) {
      return KeyAnalysisResult(
        parseOk: false,
        inputScheme: scheme,
        profile: null,
        basicInfo: {
          'Поддерживаемый формат': 'нет',
          'Схема': scheme.isNotEmpty ? scheme : 'не определена',
        },
        networkInfo: const {},
        notes: const [
          'Ключ не распознан как vless://, ss://, trojan:// или tuic://.',
        ],
      );
    }

    final profile = UriParser.parse(uri);
    final basic = <String, String>{
      'Поддерживаемый формат': 'да',
      'Протокол': profile.protocol.toUpperCase(),
      'Сервер': profile.server,
      'Порт': profile.port.toString(),
      'Транспорт': profile.transport,
      'TLS': profile.tls ? 'включен' : 'выключен',
      'SNI': profile.sni.isNotEmpty ? profile.sni : 'не указан',
      'ALPN': profile.alpn.isNotEmpty ? profile.alpn : 'не указан',
      'Path/Prefix': profile.wsPath.isNotEmpty ? profile.wsPath : '/',
      'Host': profile.wsHost.isNotEmpty ? profile.wsHost : 'не указан',
      'gRPC service': profile.grpcServiceName.isNotEmpty
          ? profile.grpcServiceName
          : 'не указан',
      'Reality': profile.reality ? 'да' : 'нет',
      'Fingerprint': profile.fingerprint,
    };

    final notes = <String>[];
    if (!profile.isValid) {
      notes.add('Ключ распарсен, но обязательные поля выглядят неполными.');
    }

    if (!withNetworkChecks) {
      return KeyAnalysisResult(
        parseOk: true,
        inputScheme: scheme,
        profile: profile,
        basicInfo: basic,
        networkInfo: const {},
        notes: notes,
      );
    }

    final network = <String, String>{};
    await _collectNetworkFacts(profile, network, notes);

    return KeyAnalysisResult(
      parseOk: true,
      inputScheme: scheme,
      profile: profile,
      basicInfo: basic,
      networkInfo: network,
      notes: notes,
    );
  }

  static Future<void> _collectNetworkFacts(
    ProxyProfile profile,
    Map<String, String> network,
    List<String> notes,
  ) async {
    final host = profile.server.trim();
    if (host.isEmpty) {
      notes.add('Сервер не указан, сетевые проверки пропущены.');
      return;
    }

    final isIp = InternetAddress.tryParse(host) != null;
    final resolvedIps = <String>[];

    try {
      if (isIp) {
        resolvedIps.add(host);
      } else {
        final list = await InternetAddress.lookup(host)
            .timeout(const Duration(seconds: 5));
        for (final ip in list) {
          resolvedIps.add(ip.address);
        }
      }
      if (resolvedIps.isNotEmpty) {
        network['DNS/IP'] = resolvedIps.join(', ');
      }
    } catch (e) {
      notes.add('DNS-резолвинг не выполнен: $e');
    }

    final targetIp =
        resolvedIps.isNotEmpty ? resolvedIps.first : (isIp ? host : '');
    if (targetIp.isNotEmpty) {
      await _collectIpWhoInfo(targetIp, network, notes);
    }

    if (!isIp) {
      await _collectDomainRdap(host, network, notes);
    }

    if (profile.tls) {
      await _collectTlsCertificateFacts(
          profile.server, profile.port, network, notes);
    }
  }

  static Future<void> _collectIpWhoInfo(
    String ip,
    Map<String, String> network,
    List<String> notes,
  ) async {
    try {
      final uri = Uri.parse('https://ipwho.is/$ip');
      final data = await _fetchJson(uri);
      final success = data['success'] == true;
      if (!success) {
        notes.add('ASN/Geo сервис вернул ошибку для IP $ip.');
        return;
      }

      network['IP'] = ip;
      network['Страна IP'] = _asString(data['country']);
      network['Регион IP'] = _asString(data['region']);
      network['Город IP'] = _asString(data['city']);

      final connection = data['connection'];
      if (connection is Map<String, dynamic>) {
        network['ASN'] = _asString(connection['asn']);
        network['Провайдер сети'] = _asString(connection['org']);
        network['ISP'] = _asString(connection['isp']);
      }
    } catch (e) {
      notes.add('Не удалось получить ASN/Geo сведения: $e');
    }
  }

  static Future<void> _collectDomainRdap(
    String domain,
    Map<String, String> network,
    List<String> notes,
  ) async {
    try {
      final uri = Uri.parse('https://rdap.org/domain/$domain');
      final data = await _fetchJson(uri);
      final ldh = _asString(data['ldhName']);
      if (ldh.isNotEmpty) {
        network['RDAP домен'] = ldh;
      }

      final entities = data['entities'];
      if (entities is List) {
        String registrar = '';
        for (final e in entities) {
          if (e is! Map<String, dynamic>) continue;
          final roles = e['roles'];
          if (roles is List && roles.contains('registrar')) {
            registrar = _extractEntityName(e);
            break;
          }
        }
        if (registrar.isNotEmpty) {
          network['Регистратор домена'] = registrar;
        }
      }
    } catch (e) {
      notes.add('RDAP сведения по домену недоступны: $e');
    }
  }

  static Future<void> _collectTlsCertificateFacts(
    String host,
    int port,
    Map<String, String> network,
    List<String> notes,
  ) async {
    SecureSocket? socket;
    try {
      socket = await SecureSocket.connect(
        host,
        port,
        timeout: const Duration(seconds: 6),
        onBadCertificate: (_) => true,
      );

      final cert = socket.peerCertificate;
      if (cert == null) {
        notes.add('TLS сертификат не получен.');
        return;
      }

      network['TLS Subject'] = cert.subject;
      network['TLS Issuer'] = cert.issuer;
      network['TLS Valid From'] = cert.startValidity.toIso8601String();
      network['TLS Valid To'] = cert.endValidity.toIso8601String();
    } catch (e) {
      notes.add('TLS проверка не выполнена: $e');
    } finally {
      socket?.destroy();
    }
  }

  static Future<Map<String, dynamic>> _fetchJson(Uri uri) async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 6);
    try {
      final request = await client.getUrl(uri);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final response =
          await request.close().timeout(const Duration(seconds: 8));
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException('HTTP ${response.statusCode}', uri: uri);
      }
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      throw const FormatException('JSON object expected');
    } finally {
      client.close(force: true);
    }
  }

  static String _extractScheme(String uri) {
    final idx = uri.indexOf('://');
    if (idx <= 0) return '';
    return uri.substring(0, idx).toLowerCase();
  }

  static String _extractEntityName(Map<String, dynamic> entity) {
    final vcardArray = entity['vcardArray'];
    if (vcardArray is List && vcardArray.length >= 2 && vcardArray[1] is List) {
      final props = vcardArray[1] as List;
      for (final item in props) {
        if (item is List &&
            item.isNotEmpty &&
            item[0] == 'fn' &&
            item.length >= 4) {
          return _asString(item[3]);
        }
      }
    }

    final handle = _asString(entity['handle']);
    return handle;
  }

  static String _asString(dynamic value) {
    if (value == null) return '';
    return value.toString().trim();
  }
}

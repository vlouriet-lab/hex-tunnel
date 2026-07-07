import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import '../models/offline_deblock_profile.dart';

class CloudflareWarpService {
  static const String _apiBaseUrl = 'https://api.cloudflareclient.com';
  static const String _apiVersion = 'v0a1922';
  static const String _userAgent = 'okhttp/3.12.1';
  static const String _clientVersion = 'a-6.3-1922';

  final http.Client _client;
  final X25519 _x25519;

  CloudflareWarpService({http.Client? client, X25519? x25519})
      : _client = client ?? IOClient(_buildHttpClient()),
        _x25519 = x25519 ?? X25519();

  static HttpClient _buildHttpClient() {
    final client = HttpClient();
    client.userAgent = _userAgent;
    client.connectionTimeout = const Duration(seconds: 15);
    client.idleTimeout = const Duration(seconds: 15);
    client.maxConnectionsPerHost = 4;
    client.autoUncompress = true;
    return client;
  }

  Future<OfflineDeblockSettings> provisionSettings(
    OfflineDeblockSettings baseSettings, {
    String deviceModel = 'Hex Decensor',
  }) async {
    final keyPair = await _x25519.newKeyPair();
    final publicKey = await keyPair.extractPublicKey();
    final privateKeyBytes = await keyPair.extractPrivateKeyBytes();

    var sourceDevice = await _registerDevice(
      publicKey: base64Encode(publicKey.bytes),
      deviceModel: deviceModel,
    );

    final token = _requiredString(sourceDevice['token'], 'token');
    final deviceId = _requiredString(sourceDevice['id'], 'id');
    final licenseKey = baseSettings.warpLicenseKey.trim();

    if (licenseKey.isNotEmpty) {
      await _updateLicense(
        deviceId: deviceId,
        token: token,
        licenseKey: licenseKey,
      );
      sourceDevice = await _getSourceDevice(deviceId: deviceId, token: token);
    }

    final configRaw = sourceDevice['config'];
    if (configRaw is! Map) {
      throw const FormatException('Cloudflare не вернул config для WARP');
    }
    final config = Map<String, dynamic>.from(configRaw);

    final interfaceRaw = config['interface'];
    if (interfaceRaw is! Map) {
      throw const FormatException('Cloudflare не вернул interface для WARP');
    }
    final interfaceConfig = Map<String, dynamic>.from(interfaceRaw);

    final addressesRaw = interfaceConfig['addresses'];
    if (addressesRaw is! Map) {
      throw const FormatException('Cloudflare не вернул адреса WARP');
    }
    final addresses = Map<String, dynamic>.from(addressesRaw);

    final peersRaw = config['peers'];
    if (peersRaw is! List || peersRaw.isEmpty) {
      throw const FormatException('Cloudflare не вернул peer для WARP');
    }
    final firstPeerRaw = peersRaw.first;
    if (firstPeerRaw is! Map) {
      throw const FormatException('Cloudflare вернул некорректный peer');
    }
    final firstPeer = Map<String, dynamic>.from(firstPeerRaw);

    final endpointRaw = firstPeer['endpoint'];
    if (endpointRaw is! Map) {
      throw const FormatException('Cloudflare не вернул endpoint для WARP');
    }
    final endpoint = Map<String, dynamic>.from(endpointRaw);

    final endpointHostCandidates = [
      (endpoint['host'] as String? ?? '').trim(),
      (endpoint['v4'] as String? ?? '').trim(),
      (endpoint['v6'] as String? ?? '').trim(),
    ];
    final endpointHost = endpointHostCandidates.firstWhere(
      (value) => value.isNotEmpty,
      orElse: () => '',
    );
    if (endpointHost.isEmpty) {
      throw const FormatException(
          'Cloudflare не вернул адрес endpoint для WARP');
    }
    final normalizedEndpoint = _normalizeEndpoint(
      endpointHost,
      baseSettings.warpEndpointPort > 0 ? baseSettings.warpEndpointPort : 2408,
    );

    return baseSettings.copyWith(
      warpPrivateKey: base64Encode(privateKeyBytes),
      warpPeerPublicKey:
          _requiredString(firstPeer['public_key'], 'peer public_key'),
      warpLocalAddressV4: _requiredString(addresses['v4'], 'interface v4'),
      warpLocalAddressV6: (addresses['v6'] as String? ?? '').trim(),
      warpEndpointHost: normalizedEndpoint.host,
      warpEndpointPort: normalizedEndpoint.port,
    );
  }

  Future<Map<String, dynamic>> _registerDevice({
    required String publicKey,
    required String deviceModel,
  }) async {
    final response = await _client.post(
      Uri.parse('$_apiBaseUrl/$_apiVersion/reg'),
      headers: _headers(),
      body: jsonEncode({
        'fcm_token': '',
        'install_id': '',
        'key': publicKey,
        'locale': 'en_US',
        'model': deviceModel,
        'tos': DateTime.now().toUtc().toIso8601String(),
        'type': 'Android',
      }),
    );
    return _decodeResponse(response, operation: 'register');
  }

  Future<void> _updateLicense({
    required String deviceId,
    required String token,
    required String licenseKey,
  }) async {
    final response = await _client.put(
      Uri.parse('$_apiBaseUrl/$_apiVersion/reg/$deviceId/account'),
      headers: _headers(token: token),
      body: jsonEncode({'license': licenseKey}),
    );
    _decodeResponse(response, operation: 'update account');
  }

  Future<Map<String, dynamic>> _getSourceDevice({
    required String deviceId,
    required String token,
  }) async {
    final response = await _client.get(
      Uri.parse('$_apiBaseUrl/$_apiVersion/reg/$deviceId'),
      headers: _headers(token: token),
    );
    return _decodeResponse(response, operation: 'get source device');
  }

  Map<String, String> _headers({String? token}) {
    return {
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      'User-Agent': _userAgent,
      'CF-Client-Version': _clientVersion,
      if (token != null && token.trim().isNotEmpty)
        'Authorization': 'Bearer ${token.trim()}',
    };
  }

  Map<String, dynamic> _decodeResponse(
    http.Response response, {
    required String operation,
  }) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final body = response.body.trim();
      final details = body.isEmpty ? '' : ': $body';
      throw HttpException(
        'Cloudflare WARP $operation failed with ${response.statusCode}$details',
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      throw FormatException(
        'Cloudflare WARP $operation вернул неожиданный JSON',
      );
    }
    return Map<String, dynamic>.from(decoded);
  }

  String _requiredString(Object? value, String fieldName) {
    final normalized = (value as String? ?? '').trim();
    if (normalized.isEmpty) {
      throw FormatException(
          'Cloudflare не вернул обязательное поле $fieldName');
    }
    return normalized;
  }

  ({String host, int port}) _normalizeEndpoint(
    String rawHost,
    int fallbackPort,
  ) {
    final trimmed = rawHost.trim();
    if (trimmed.isEmpty) {
      throw const FormatException(
          'Cloudflare не вернул адрес endpoint для WARP');
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

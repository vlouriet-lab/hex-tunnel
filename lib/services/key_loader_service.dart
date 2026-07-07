import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/proxy_profile.dart';
import '../models/routing_mode.dart';
import '../services/uri_parser.dart';

class KeyLoadException implements Exception {
  final String message;
  const KeyLoadException(this.message);

  @override
  String toString() => message;
}

/// Автоматически загруженный профиль с метаданными страны.
class AutoProfile {
  final ProxyProfile profile;
  final String countryCode;
  final String countryName;
  final String flagEmoji;
  final KeyListType listType;
  int latencyMs;

  AutoProfile({
    required this.profile,
    this.countryCode = 'RR',
    this.countryName = 'Роджер',
    this.flagEmoji = '🏴‍☠️',
    required this.listType,
    this.latencyMs = -1,
  });
}

/// Сервис загрузки ключей с GitHub.
/// Порт логики TunnelAutoManager из SOTA Segment.
///
/// Логика загрузки:
///  1. Основной источник — только igareck (igareck/vpn-configs-for-russia).
///  2. Обновляется несколько раз в сутки, проверенные конфиги для России.
///
class KeyLoaderService {
  static const int _maxAttempts = 3;
  static const int _maxBodyBytes = 5 * 1024 * 1024;
  static const int _maxLines = 120000;
  static const int _maxLineLength = 8192;
  static const String _rogerName = 'Роджер';
  static const String _rogerFlag = '🏴‍☠️';
  static const Set<String> _trustedHosts = {
    'raw.githubusercontent.com',
  };
  static final Map<String, _SourceHealth> _sourceHealth = {};
  static final Map<String, String> _uiSourceLabels = () {
    final ordered = <_KeySource>[
      ..._igareckSources,
    ];
    final labels = <String, String>{};
    for (var i = 0; i < ordered.length; i++) {
      labels[ordered[i].name] = 'Источник ${i + 1}';
    }
    return labels;
  }();

  static Map<String, Map<String, Object>> sourceHealthSnapshot() {
    return _sourceHealth.map(
      (k, v) => MapEntry(k, {
        'ok': v.successCount,
        'fail': v.failureCount,
        'lastError': v.lastError,
        'lastLatencyMs': v.lastLatencyMs,
        'lastSuccessAt': v.lastSuccessAtMs,
      }),
    );
  }

  // ── Единственный основной источник ключей: igareck ──
  static const _igareckSources = <_KeySource>[
    // (igareck/vpn-configs-for-russia)
    // Обновляется несколько раз в сутки, проверенные конфиги для России
    _KeySource(
      'igareck-vless',
      'https://raw.githubusercontent.com/igareck/vpn-configs-for-russia/main/BLACK_VLESS_RUS.txt',
      KeyListType.blackList,
    ),
    _KeySource(
      'igareck-ss-all',
      'https://raw.githubusercontent.com/igareck/vpn-configs-for-russia/main/BLACK_SS%2BAll_RUS.txt',
      KeyListType.blackList,
    ),
    _KeySource(
      'igareck-white',
      'https://raw.githubusercontent.com/igareck/vpn-configs-for-russia/main/WHITE-CIDR-RU-all.txt',
      KeyListType.whiteList,
    ),
    _KeySource(
      '10ium-belarus',
      'https://raw.githubusercontent.com/10ium/ScrapeAndCategorize/refs/heads/main/output_configs/Belarus.txt',
      KeyListType.blackList,
    ),
  ];

  static (String code, String name, String flag) inferCountry(
    String profileName,
    String server,
  ) {
    return _extractCountry(profileName, server);
  }

  static String toCyrillicCountryName(String countryCode, String countryName) {
    final byCode = _countryByCode(countryCode);
    if (byCode.$1 == 'RR') {
      final normalizedName = _normalizeLookupText(countryName);
      for (final entry in _countryPatterns) {
        for (final pattern in entry.patterns) {
          if (_matchesPattern(normalizedName, pattern)) {
            return entry.name;
          }
        }
      }
      return _hasCyrillic(countryName) ? countryName : _rogerName;
    }
    return byCode.$2;
  }

  static String toLocalizedCountryName(
    String countryCode,
    String countryName, {
    required bool useRussian,
  }) {
    if (useRussian) {
      return toCyrillicCountryName(countryCode, countryName);
    }

    final byCode = _countryByCode(countryCode);
    if (byCode.$1 == 'RR') {
      final normalizedName = _normalizeLookupText(countryName);
      for (final entry in _countryPatterns) {
        for (final pattern in entry.patterns) {
          if (_matchesPattern(normalizedName, pattern)) {
            return _countryNamesEn[entry.code] ?? entry.code;
          }
        }
      }
      if (!_hasCyrillic(countryName) && countryName.trim().isNotEmpty) {
        return countryName.trim();
      }
      return 'Roger';
    }

    return _countryNamesEn[byCode.$1] ?? byCode.$1;
  }

  static String _uiSourceLabel(String sourceName) {
    return _uiSourceLabels[sourceName] ?? 'Источник';
  }

  // ── QoS-зондирование ─────────────────────────────────────────────────────

  /// TLS-зондирование сервера: полный TLS-handshake.
  /// Мёртвые прокси, которые принимают TCP, но не могут проксировать,
  /// не проходят TLS-хендшейк и возвращают -1.
  /// Возвращает задержку TLS-handshake в мс, или -1 при недоступности.
  static Future<int> probeLatency(String server, int port) async {
    final stopwatch = Stopwatch()..start();
    try {
      final socket = await SecureSocket.connect(
        server,
        port,
        timeout: const Duration(seconds: 5),
        onBadCertificate: (_) =>
            true, // принимаем любой сертификат — нам важен сам handshake
      );
      stopwatch.stop();
      await socket.close();
      return stopwatch.elapsedMilliseconds;
    } catch (_) {
      return -1;
    }
  }

  /// Быстрый TCP-пинг (без TLS). Используется для health-check уже
  /// подключённого сервера, где TLS-overhead избыточен.
  static Future<int> probeTcp(String server, int port) async {
    final stopwatch = Stopwatch()..start();
    try {
      final socket = await Socket.connect(
        server,
        port,
        timeout: const Duration(seconds: 5),
      );
      stopwatch.stop();
      await socket.close();
      return stopwatch.elapsedMilliseconds;
    } catch (_) {
      return -1;
    }
  }

  /// Фоновая параллельная проверка задержек для списка профилей.
  /// [concurrency] — максимальное число одновременных соединений.
  /// [onResult] вызывается после каждого завершённого теста.
  static Future<void> probeProfilesInBackground(
    List<AutoProfile> profiles, {
    int concurrency = 8,
    void Function(AutoProfile profile)? onResult,
  }) async {
    if (profiles.isEmpty) return;

    var index = 0;

    // Каждый воркер берёт следующий незанятый профиль по индексу.
    // index++ атомарен в однопоточной Dart event loop.
    Future<void> worker() async {
      while (true) {
        final i = index++;
        if (i >= profiles.length) return;
        final ap = profiles[i];
        ap.latencyMs = await probeLatency(ap.profile.server, ap.profile.port);
        onResult?.call(ap);
      }
    }

    final workerCount = concurrency.clamp(1, profiles.length);
    await Future.wait(List.generate(workerCount, (_) => worker()));
  }

  // ── Загрузка ──────────────────────────────────────────────────────────────

  /// Загрузить ключи с логикой fallback.
  /// По умолчанию стартует только основной ebrasha-all.
  /// Резервные источники подключаются только если ebrasha-all вернул 0 ключей
  /// либо если явно включен allowReserveSources.
  /// Возвращает полный список AutoProfile (дедуплицированный).
  Future<List<AutoProfile>> fetchAll({
    void Function(String message)? onProgress,
    bool includeSupplemental = false,
    bool allowReserveSources = false,
  }) async {
    final profiles = <AutoProfile>[];
    final seen = <String>{};
    final failures = <String>[];

    // Загружаем igareck источники
    for (var i = 0; i < _igareckSources.length; i++) {
      final source = _igareckSources[i];
      onProgress?.call(
        'Загружаем: ${_uiSourceLabel(source.name)} (${i + 1}/${_igareckSources.length})…',
      );
      await _fetchAndParse(
          source.url, source.listType, profiles, seen, failures);
    }

    if (profiles.isEmpty && failures.isNotEmpty) {
      throw KeyLoadException(
        'Не удалось загрузить ключи: ${failures.join('; ')}',
      );
    }

    if (failures.isNotEmpty) {
      onProgress?.call(
        'Частично загружено (${profiles.length}). Ошибки: ${failures.length}',
      );
    }

    onProgress?.call(
      'Загружено ${profiles.length} ключей. Начинаем QoS-отбор…',
    );
    return profiles;
  }

  Future<void> _fetchAndParse(
    String url,
    KeyListType listType,
    List<AutoProfile> out,
    Set<String> seen,
    List<String> failures,
  ) async {
    final sourceName = _sourceName(url);
    final sw = Stopwatch()..start();
    var added = 0;
    try {
      _assertTrustedUrl(url);
      final response = await _getWithRetry(url);

      if (response.statusCode != 200) {
        _recordSourceFailure(
            sourceName, 'HTTP ${response.statusCode}', sw.elapsedMilliseconds);
        failures.add('$sourceName: HTTP ${response.statusCode}');
        return;
      }

      _assertResponseSize(url, response.bodyBytes.length);
      await _verifySourceIntegrity(url, response.body);

      final lines = response.body.split('\n');
      if (lines.length > _maxLines) {
        _recordSourceFailure(
          sourceName,
          'too_many_lines:${lines.length}',
          sw.elapsedMilliseconds,
        );
        failures
            .add('$sourceName: слишком большой список (${lines.length} строк)');
        return;
      }

      for (final line in lines) {
        final trimmed = line.trim();
        if (trimmed.length > _maxLineLength) continue;
        if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
        if (!UriParser.isSupported(trimmed)) continue;
        if (seen.contains(trimmed)) continue;

        final profile = UriParser.parse(trimmed);
        if (!profile.isValid) continue;

        seen.add(trimmed);

        final countryInfo = _extractCountry(profile.name, profile.server);
        out.add(AutoProfile(
          profile: profile,
          countryCode: countryInfo.$1,
          countryName: countryInfo.$2,
          flagEmoji: countryInfo.$3,
          listType: listType,
        ));
        added++;
      }
      _recordSourceSuccess(sourceName, added, sw.elapsedMilliseconds);
    } on KeyLoadException catch (e) {
      _recordSourceFailure(sourceName, e.message, sw.elapsedMilliseconds);
      failures.add('$sourceName: ${e.message}');
    } catch (e) {
      _recordSourceFailure(sourceName, '$e', sw.elapsedMilliseconds);
      failures.add('$sourceName: $e');
    }
  }

  void _recordSourceSuccess(String source, int added, int latencyMs) {
    final health = _sourceHealth.putIfAbsent(source, () => _SourceHealth());
    health.successCount += 1;
    health.lastError = '';
    health.lastLatencyMs = latencyMs;
    health.lastSuccessAtMs = DateTime.now().millisecondsSinceEpoch;
    health.lastAddedProfiles = added;
  }

  void _recordSourceFailure(String source, String error, int latencyMs) {
    final health = _sourceHealth.putIfAbsent(source, () => _SourceHealth());
    health.failureCount += 1;
    health.lastError = error;
    health.lastLatencyMs = latencyMs;
  }

  Future<http.Response> _getWithRetry(String url) async {
    Object? lastError;

    for (var attempt = 1; attempt <= _maxAttempts; attempt++) {
      try {
        return await http
            .get(Uri.parse(url))
            .timeout(const Duration(seconds: 30));
      } on TimeoutException catch (e) {
        lastError = e;
      } on SocketException catch (e) {
        lastError = e;
      } on http.ClientException catch (e) {
        lastError = e;
      }

      if (attempt < _maxAttempts) {
        await Future<void>.delayed(Duration(milliseconds: 500 * attempt));
      }
    }

    throw KeyLoadException('сеть недоступна (${lastError ?? 'unknown'})');
  }

  void _assertTrustedUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme.toLowerCase() != 'https') {
      throw KeyLoadException('небезопасный URL источника');
    }
    if (!_trustedHosts.contains(uri.host.toLowerCase())) {
      throw KeyLoadException('недоверенный хост: ${uri.host}');
    }
  }

  void _assertResponseSize(String url, int bodyBytes) {
    if (bodyBytes > _maxBodyBytes) {
      throw KeyLoadException(
        'источник ${_sourceName(url)} превысил лимит ${_maxBodyBytes ~/ 1024}KB',
      );
    }
  }

  Future<void> _verifySourceIntegrity(String url, String body) async {
    final shaUri = Uri.parse('$url.sha256');
    try {
      _assertTrustedUrl(shaUri.toString());
      final shaResponse =
          await http.get(shaUri).timeout(const Duration(seconds: 10));

      // If the .sha256 file doesn't exist, skip verification silently.
      // Verification is enforced only when the checksum file IS present
      // (guards against accidental corruption / in-flight tampering).
      if (shaResponse.statusCode != 200) {
        debugPrint(
            'KeyLoaderService: no .sha256 for ${_sourceName(url)}, skipping check');
        return;
      }

      final expected = _extractSha256(shaResponse.body);
      if (expected == null) {
        throw KeyLoadException('некорректный .sha256 для ${_sourceName(url)}');
      }

      final actual = _sha256Hex(body);
      if (actual.toLowerCase() != expected.toLowerCase()) {
        throw KeyLoadException(
            'проверка целостности не пройдена: ${_sourceName(url)}');
      }
    } on KeyLoadException {
      rethrow;
    } catch (e) {
      // Network errors when fetching the checksum file are non-fatal.
      debugPrint('KeyLoaderService: checksum fetch failed for $url ($e)');
    }
  }

  String? _extractSha256(String text) {
    final m = RegExp(r'([a-fA-F0-9]{64})').firstMatch(text);
    return m?.group(1);
  }

  String _sha256Hex(String text) {
    final bytes = utf8.encode(text);
    final digest = sha256.convert(bytes).bytes;
    final out = StringBuffer();
    for (final b in digest) {
      out.write(b.toRadixString(16).padLeft(2, '0'));
    }
    return out.toString();
  }

  String _sourceName(String url) {
    if (url.contains('BLACK_VLESS_RUS')) return 'BLACK_VLESS_RUS';
    if (url.contains('BLACK_SS%2BAll_RUS')) return 'BLACK_SS+All_RUS';
    if (url.contains('WHITE-CIDR-RU-all')) return 'WHITE-CIDR-RU-all';
    // For fallback sources return the last path segment as a readable label.
    final uri = Uri.tryParse(url);
    if (uri != null) {
      final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
      if (segments.isNotEmpty) return segments.last;
    }
    return 'unknown-source';
  }

  // ── Определение страны ────────────────────────────────────────────────────

  static (String code, String name, String flag) _extractCountry(
    String profileName,
    String server,
  ) {
    final emoji = _extractFlagEmoji(profileName);
    if (emoji != null) {
      final byFlag = _countryByFlag(emoji);
      if (byFlag != null) {
        return byFlag;
      }
    }

    final text = _normalizeLookupText('$profileName $server');

    for (final entry in _countryPatterns) {
      for (final pattern in entry.patterns) {
        if (_matchesPattern(text, pattern)) {
          return (entry.code, entry.name, entry.flag);
        }
      }
    }

    final ipCode = _extractCountryCodeFromIp(server);
    if (ipCode != null) {
      return _countryByCode(ipCode);
    }

    final tld = _extractCountryCodeFromHost(server);
    if (tld != null) {
      return _countryByCode(tld);
    }

    return ('RR', _rogerName, _rogerFlag);
  }

  static bool _matchesPattern(String text, String pattern) {
    final normalized = pattern.toLowerCase();

    if (normalized.contains(' ')) {
      return text.contains(normalized);
    }

    final tokenMatch = RegExp(
      r'(^|[^a-z0-9])' + RegExp.escape(normalized) + r'([^a-z0-9]|$)',
    );
    return tokenMatch.hasMatch(text);
  }

  static bool _hasCyrillic(String value) {
    return RegExp(r'[а-яА-ЯёЁ]').hasMatch(value);
  }

  static String _normalizeLookupText(String value) {
    return value
        .toLowerCase()
        .replaceAll('_', ' ')
        .replaceAll('-', ' ')
        .replaceAll(',', ' ')
        .replaceAll('|', ' ')
        .replaceAll('[', ' ')
        .replaceAll(']', ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static String? _extractFlagEmoji(String text) {
    final match = RegExp(
      r'[\u{1F1E6}-\u{1F1FF}]{2}',
      unicode: true,
    ).firstMatch(text);
    return match?.group(0);
  }

  static (String code, String name, String flag)? _countryByFlag(String emoji) {
    final byFlag = _flagCountryMap[emoji];
    if (byFlag != null) {
      return (byFlag.code, byFlag.name, byFlag.flag);
    }
    final code = _countryCodeFromFlagEmoji(emoji);
    if (code == null) return null;
    return _countryByCode(code);
  }

  static String? _countryCodeFromFlagEmoji(String emoji) {
    final runes = emoji.runes.toList(growable: false);
    if (runes.length != 2) return null;
    const offset = 0x1F1E6;
    final first = runes[0] - offset;
    final second = runes[1] - offset;
    if (first < 0 || first > 25 || second < 0 || second > 25) return null;
    return String.fromCharCodes([65 + first, 65 + second]);
  }

  static (String code, String name, String flag) _countryByCode(String code) {
    final normalized = code.toUpperCase();
    final byCode = _codeCountryMap[normalized.toLowerCase()];
    if (byCode != null) {
      return (byCode.code, byCode.name, byCode.flag);
    }

    final name = _countryNames[normalized];
    if (name != null) {
      return (normalized, name, _flagFromCountryCode(normalized));
    }

    return ('RR', _rogerName, _rogerFlag);
  }

  static String _flagFromCountryCode(String code) {
    final normalized = code.toUpperCase();
    if (normalized.length != 2) return _rogerFlag;
    final chars = normalized.codeUnits;
    return String.fromCharCodes([
      0x1F1E6 + chars[0] - 65,
      0x1F1E6 + chars[1] - 65,
    ]);
  }

  static String? _extractCountryCodeFromHost(String host) {
    final clean = host.toLowerCase();
    final isIpv4 = RegExp(r'^\d{1,3}(\.\d{1,3}){3}$').hasMatch(clean);
    if (isIpv4) return null;

    final parts = clean.split('.');
    if (parts.length < 2) return null;

    final lastTwo = '${parts[parts.length - 2]}.${parts.last}';
    final compositeTlds = {
      'co.uk': 'gb',
      'org.uk': 'gb',
      'gov.uk': 'gb',
      'com.au': 'au',
      'net.au': 'au',
      'co.jp': 'jp',
      'com.sg': 'sg',
      'com.tr': 'tr',
      'com.br': 'br',
    };
    final composite = compositeTlds[lastTwo];
    if (composite != null) return composite;

    final tld = parts.last;
    if (!RegExp(r'^[a-z]{2}$').hasMatch(tld)) return null;
    return tld;
  }

  static String? _extractCountryCodeFromIp(String host) {
    final ipv4 = RegExp(r'^(\d{1,3})(?:\.(\d{1,3})){3}$');
    final match = ipv4.firstMatch(host.trim());
    if (match == null) return null;

    final parsed = host.split('.').map(int.tryParse).toList(growable: false);
    if (parsed.length != 4 ||
        parsed.any((o) => o == null || o < 0 || o > 255)) {
      return null;
    }
    final octets = parsed.cast<int>();

    final ipNum =
        (octets[0] << 24) | (octets[1] << 16) | (octets[2] << 8) | octets[3];

    for (final range in _ipv4GeoRanges) {
      if (ipNum >= range.start && ipNum <= range.end) {
        return range.countryCode;
      }
    }
    return null;
  }

  static int _ipToInt(String ip) {
    final parts = ip.split('.').map(int.parse).toList(growable: false);
    return (parts[0] << 24) | (parts[1] << 16) | (parts[2] << 8) | parts[3];
  }

  static final Map<String, _CountryPattern> _flagCountryMap = {
    for (final c in _countryPatterns) c.flag: c,
  };

  static final Map<String, _CountryPattern> _codeCountryMap = {
    for (final c in _countryPatterns) c.code.toLowerCase(): c,
  };

  static final Map<String, String> _countryNames = {
    'AE': 'ОАЭ',
    'AL': 'Албания',
    'AR': 'Аргентина',
    'AT': 'Австрия',
    'AU': 'Австралия',
    'BE': 'Бельгия',
    'BG': 'Болгария',
    'BR': 'Бразилия',
    'BY': 'Беларусь',
    'CA': 'Канада',
    'CH': 'Швейцария',
    'CL': 'Чили',
    'CN': 'Китай',
    'CZ': 'Чехия',
    'DE': 'Германия',
    'DK': 'Дания',
    'EE': 'Эстония',
    'ES': 'Испания',
    'FI': 'Финляндия',
    'FR': 'Франция',
    'GB': 'Великобритания',
    'GE': 'Грузия',
    'HK': 'Гонконг',
    'HR': 'Хорватия',
    'HU': 'Венгрия',
    'ID': 'Индонезия',
    'IE': 'Ирландия',
    'IL': 'Израиль',
    'IN': 'Индия',
    'IS': 'Исландия',
    'IT': 'Италия',
    'JP': 'Япония',
    'KE': 'Кения',
    'KR': 'Корея',
    'KZ': 'Казахстан',
    'LT': 'Литва',
    'LU': 'Люксембург',
    'LV': 'Латвия',
    'MD': 'Молдова',
    'MX': 'Мексика',
    'NL': 'Нидерланды',
    'NO': 'Норвегия',
    'PL': 'Польша',
    'PT': 'Португалия',
    'RO': 'Румыния',
    'RS': 'Сербия',
    'RU': 'Россия',
    'SC': 'Сейшелы',
    'SE': 'Швеция',
    'SG': 'Сингапур',
    'SI': 'Словения',
    'SK': 'Словакия',
    'TH': 'Таиланд',
    'TR': 'Турция',
    'TW': 'Тайвань',
    'UA': 'Украина',
    'US': 'США',
    'VN': 'Вьетнам',
    'ZA': 'ЮАР',
  };

  static final Map<String, String> _countryNamesEn = {
    'AE': 'UAE',
    'AL': 'Albania',
    'AR': 'Argentina',
    'AT': 'Austria',
    'AU': 'Australia',
    'BE': 'Belgium',
    'BG': 'Bulgaria',
    'BR': 'Brazil',
    'BY': 'Belarus',
    'CA': 'Canada',
    'CH': 'Switzerland',
    'CL': 'Chile',
    'CN': 'China',
    'CZ': 'Czechia',
    'DE': 'Germany',
    'DK': 'Denmark',
    'EE': 'Estonia',
    'ES': 'Spain',
    'FI': 'Finland',
    'FR': 'France',
    'GB': 'United Kingdom',
    'GE': 'Georgia',
    'HK': 'Hong Kong',
    'HR': 'Croatia',
    'HU': 'Hungary',
    'ID': 'Indonesia',
    'IE': 'Ireland',
    'IL': 'Israel',
    'IN': 'India',
    'IS': 'Iceland',
    'IT': 'Italy',
    'JP': 'Japan',
    'KE': 'Kenya',
    'KR': 'Korea',
    'KZ': 'Kazakhstan',
    'LT': 'Lithuania',
    'LU': 'Luxembourg',
    'LV': 'Latvia',
    'MD': 'Moldova',
    'MX': 'Mexico',
    'NL': 'Netherlands',
    'NO': 'Norway',
    'PL': 'Poland',
    'PT': 'Portugal',
    'RO': 'Romania',
    'RS': 'Serbia',
    'RU': 'Russia',
    'SC': 'Seychelles',
    'SE': 'Sweden',
    'SG': 'Singapore',
    'SI': 'Slovenia',
    'SK': 'Slovakia',
    'TH': 'Thailand',
    'TR': 'Turkey',
    'TW': 'Taiwan',
    'UA': 'Ukraine',
    'US': 'USA',
    'VN': 'Vietnam',
    'ZA': 'South Africa',
  };

  static const _countryPatterns = <_CountryPattern>[
    _CountryPattern('DE', 'Германия', '🇩🇪', [
      'de',
      'germany',
      'deutschland',
      'германия',
      'berlin',
      'frankfurt',
      'munich'
    ]),
    _CountryPattern('NL', 'Нидерланды', '🇳🇱', [
      'nl',
      'netherlands',
      'holland',
      'нидерланды',
      'amsterdam',
      'rotterdam'
    ]),
    _CountryPattern('US', 'США', '🇺🇸', [
      'us',
      'usa',
      'united states',
      'america',
      'сша',
      'new york',
      'los angeles',
      'chicago',
      'miami',
      'seattle'
    ]),
    _CountryPattern('GB', 'Великобритания', '🇬🇧', [
      'gb',
      'uk',
      'united kingdom',
      'великобритания',
      'london',
      'manchester'
    ]),
    _CountryPattern('FR', 'Франция', '🇫🇷',
        ['fr', 'france', 'франция', 'paris', 'marseille']),
    _CountryPattern(
        'FI', 'Финляндия', '🇫🇮', ['fi', 'finland', 'финляндия', 'helsinki']),
    _CountryPattern(
        'SE', 'Швеция', '🇸🇪', ['se', 'sweden', 'швеция', 'stockholm']),
    _CountryPattern(
        'NO', 'Норвегия', '🇳🇴', ['no', 'norway', 'норвегия', 'oslo']),
    _CountryPattern('CH', 'Швейцария', '🇨🇭',
        ['ch', 'switzerland', 'швейцария', 'zurich', 'geneva']),
    _CountryPattern(
        'AT', 'Австрия', '🇦🇹', ['at', 'austria', 'австрия', 'vienna']),
    _CountryPattern(
        'BE', 'Бельгия', '🇧🇪', ['be', 'belgium', 'бельгия', 'brussels']),
    _CountryPattern(
        'BY', 'Беларусь', '🇧🇾', ['by', 'belarus', 'беларусь', 'minsk']),
    _CountryPattern(
        'PL', 'Польша', '🇵🇱', ['pl', 'poland', 'польша', 'warsaw']),
    _CountryPattern('CZ', 'Чехия', '🇨🇿', ['cz', 'czech', 'чехия', 'prague']),
    _CountryPattern(
        'LT', 'Литва', '🇱🇹', ['lt', 'lithuania', 'литва', 'vilnius']),
    _CountryPattern('LV', 'Латвия', '🇱🇻', ['lv', 'latvia', 'латвия', 'riga']),
    _CountryPattern(
        'EE', 'Эстония', '🇪🇪', ['ee', 'estonia', 'эстония', 'tallinn']),
    _CountryPattern(
        'JP', 'Япония', '🇯🇵', ['jp', 'japan', 'япония', 'tokyo', 'osaka']),
    _CountryPattern(
        'SG', 'Сингапур', '🇸🇬', ['sg', 'singapore', 'сингапур', 'singa']),
    _CountryPattern('HK', 'Гонконг', '🇭🇰', ['hk', 'hong kong', 'гонконг']),
    _CountryPattern(
        'ID', 'Индонезия', '🇮🇩', ['id', 'indonesia', 'индонезия', 'jakarta']),
    _CountryPattern('KR', 'Корея', '🇰🇷', ['kr', 'korea', 'корея', 'seoul']),
    _CountryPattern('ZA', 'ЮАР', '🇿🇦',
        ['za', 'south africa', 'юар', 'johannesburg', 'pretoria']),
    _CountryPattern(
        'TR', 'Турция', '🇹🇷', ['tr', 'turkey', 'турция', 'istanbul']),
    _CountryPattern('CA', 'Канада', '🇨🇦', [
      'ca',
      'canada',
      'канада',
      'toronto',
      'montreal',
      'vancouver',
      'ottawa'
    ]),
    _CountryPattern('ES', 'Испания', '🇪🇸',
        ['es', 'spain', 'испания', 'madrid', 'barcelona']),
    _CountryPattern(
        'IT', 'Италия', '🇮🇹', ['it', 'italy', 'италия', 'rome', 'milan']),
    _CountryPattern(
        'AE', 'ОАЭ', '🇦🇪', ['ae', 'uae', 'dubai', 'abu dhabi', 'оаэ']),
    _CountryPattern(
        'IL', 'Израиль', '🇮🇱', ['il', 'israel', 'израиль', 'tel aviv']),
    _CountryPattern(
        'RU', 'Россия', '🇷🇺', ['ru', 'russia', 'россия', 'moscow', 'spb']),
    _CountryPattern(
        'IE', 'Ирландия', '🇮🇪', ['ie', 'ireland', 'ирландия', 'dublin']),
    _CountryPattern(
        'BR', 'Бразилия', '🇧🇷', ['br', 'brazil', 'бразилия', 'sao paulo']),
    _CountryPattern('IN', 'Индия', '🇮🇳', ['in', 'india', 'индия', 'mumbai']),
    _CountryPattern(
        'AU', 'Австралия', '🇦🇺', ['au', 'australia', 'австралия', 'sydney']),
    _CountryPattern(
        'RO', 'Румыния', '🇷🇴', ['ro', 'romania', 'румыния', 'bucharest']),
    _CountryPattern(
        'BG', 'Болгария', '🇧🇬', ['bg', 'bulgaria', 'болгария', 'sofia']),
    _CountryPattern(
        'UA', 'Украина', '🇺🇦', ['ua', 'ukraine', 'украина', 'kyiv', 'kiev']),
    _CountryPattern('VN', 'Вьетнам', '🇻🇳',
        ['vn', 'vietnam', 'вьетнам', 'hanoi', 'ho chi minh']),
    _CountryPattern(
        'TW', 'Тайвань', '🇹🇼', ['tw', 'taiwan', 'тайвань', 'taipei']),
    _CountryPattern(
        'CN', 'Китай', '🇨🇳', ['cn', 'china', 'китай', 'beijing', 'shanghai']),
    _CountryPattern('KZ', 'Казахстан', '🇰🇿',
        ['kz', 'kazakhstan', 'казахстан', 'almaty', 'astana']),
    _CountryPattern(
        'DK', 'Дания', '🇩🇰', ['dk', 'denmark', 'дания', 'copenhagen']),
    _CountryPattern(
        'PT', 'Португалия', '🇵🇹', ['pt', 'portugal', 'португалия', 'lisbon']),
    _CountryPattern(
        'HR', 'Хорватия', '🇭🇷', ['hr', 'croatia', 'хорватия', 'zagreb']),
    _CountryPattern(
        'HU', 'Венгрия', '🇭🇺', ['hu', 'hungary', 'венгрия', 'budapest']),
    _CountryPattern(
        'TH', 'Таиланд', '🇹🇭', ['th', 'thailand', 'таиланд', 'bangkok']),
  ];

  static final _ipv4GeoRanges = <_Ipv4GeoRange>[
    _Ipv4GeoRange(_ipToInt('1.0.0.0'), _ipToInt('1.0.255.255'), 'AU'),
    _Ipv4GeoRange(_ipToInt('1.1.1.0'), _ipToInt('1.1.1.255'), 'AU'),
    _Ipv4GeoRange(_ipToInt('8.8.8.0'), _ipToInt('8.8.8.255'), 'US'),
    _Ipv4GeoRange(_ipToInt('8.34.208.0'), _ipToInt('8.34.223.255'), 'US'),
    _Ipv4GeoRange(_ipToInt('31.13.64.0'), _ipToInt('31.13.127.255'), 'US'),
    _Ipv4GeoRange(_ipToInt('34.96.0.0'), _ipToInt('34.127.255.255'), 'US'),
    _Ipv4GeoRange(_ipToInt('35.184.0.0'), _ipToInt('35.191.255.255'), 'US'),
    _Ipv4GeoRange(_ipToInt('52.95.245.0'), _ipToInt('52.95.245.255'), 'IE'),
    _Ipv4GeoRange(_ipToInt('54.93.0.0'), _ipToInt('54.93.255.255'), 'DE'),
    _Ipv4GeoRange(_ipToInt('57.128.0.0'), _ipToInt('57.255.255.255'), 'FR'),
    _Ipv4GeoRange(_ipToInt('77.88.0.0'), _ipToInt('77.88.63.255'), 'RU'),
    _Ipv4GeoRange(_ipToInt('95.85.0.0'), _ipToInt('95.85.255.255'), 'NL'),
    _Ipv4GeoRange(_ipToInt('95.163.152.0'), _ipToInt('95.163.152.255'), 'CA'),
    _Ipv4GeoRange(_ipToInt('103.21.244.0'), _ipToInt('103.21.247.255'), 'SG'),
    _Ipv4GeoRange(_ipToInt('104.16.0.0'), _ipToInt('104.31.255.255'), 'US'),
    _Ipv4GeoRange(_ipToInt('142.250.0.0'), _ipToInt('142.251.255.255'), 'US'),
    _Ipv4GeoRange(_ipToInt('151.101.0.0'), _ipToInt('151.101.255.255'), 'US'),
    _Ipv4GeoRange(_ipToInt('172.217.0.0'), _ipToInt('172.217.255.255'), 'US'),
    _Ipv4GeoRange(_ipToInt('185.199.108.0'), _ipToInt('185.199.111.255'), 'US'),
    _Ipv4GeoRange(_ipToInt('188.114.96.0'), _ipToInt('188.114.111.255'), 'US'),
    _Ipv4GeoRange(_ipToInt('199.232.0.0'), _ipToInt('199.232.255.255'), 'US'),
  ];
}

class _KeySource {
  final String name;
  final String url;
  final KeyListType listType;

  const _KeySource(this.name, this.url, this.listType);
}

class _CountryPattern {
  final String code;
  final String name;
  final String flag;
  final List<String> patterns;
  const _CountryPattern(this.code, this.name, this.flag, this.patterns);
}

class _Ipv4GeoRange {
  final int start;
  final int end;
  final String countryCode;
  const _Ipv4GeoRange(this.start, this.end, this.countryCode);
}

class _SourceHealth {
  int successCount = 0;
  int failureCount = 0;
  int lastLatencyMs = -1;
  int lastSuccessAtMs = 0;
  int lastAddedProfiles = 0;
  String lastError = '';
}

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

class SmartRoutingService {
  static const String datasetUrl =
      'https://antizapret.prostovpn.org/domains-export.txt';
  static const String ruleSetFileName = 'smart_routing_rules.json';

  static final SmartRoutingService _instance = SmartRoutingService._internal();
  factory SmartRoutingService() => _instance;
  SmartRoutingService._internal();

  /// Скачивает TXT файл со списком доменов и преобразует его
  /// в формат "headless JSON rule_set" для sing-box.
  /// Сохраняет результат в [cacheDirPath]/[ruleSetFileName].
  Future<void> updateRuleSet(String cacheDirPath) async {
    final uri = Uri.parse(datasetUrl);
    final response = await http.Client().send(http.Request('GET', uri));

    if (response.statusCode != 200) {
      throw Exception('Failed to download smart routing dataset: HTTP ${response.statusCode}');
    }

    final outFile = File('$cacheDirPath/$ruleSetFileName.tmp');
    if (!outFile.parent.existsSync()) {
      outFile.parent.createSync(recursive: true);
    }

    final sink = outFile.openWrite(encoding: utf8);
    
    // Пишем заголовок rule_set (source format)
    sink.write('{"version":1,"rules":[{"domain_suffix":[');

    bool isFirst = true;

    // Читаем по строкам, чтобы не грузить RAM огромным файлом
    await for (final line in response.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter())) {
      
      final domain = line.trim();
      if (domain.isEmpty || domain.startsWith('#')) continue;

      if (!isFirst) {
        sink.write(',');
      } else {
        isFirst = false;
      }

      // Экранируем и записываем домен
      final escaped = jsonEncode(domain);
      sink.write(escaped);
    }

    // Закрываем массив и объект
    sink.write(']}]}');
    await sink.flush();
    await sink.close();

    final finalFile = File('$cacheDirPath/$ruleSetFileName');
    if (finalFile.existsSync()) {
      finalFile.deleteSync();
    }
    outFile.renameSync(finalFile.path);
  }

  /// Возвращает путь к сгенерированному rule_set.
  String getRuleSetPath(String cacheDirPath) {
    return '$cacheDirPath/$ruleSetFileName';
  }

  bool hasRuleSet(String cacheDirPath) {
    final file = File(getRuleSetPath(cacheDirPath));
    return file.existsSync() && file.lengthSync() > 1024 * 1024; // > 1MB
  }
}

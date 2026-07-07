import 'dart:convert';
import 'package:hex_decensor/models/custom_key_source.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Сервис для управления пользовательскими источниками ключей
class CustomKeySourceService {
  static const String _customSourcesKey = 'custom_key_sources';

  final SharedPreferences _prefs;

  CustomKeySourceService(this._prefs);

  /// Получить все пользовательские источники
  List<CustomKeySource> getAllSources() {
    final json = _prefs.getStringList(_customSourcesKey) ?? [];
    final sources = <CustomKeySource>[];
    for (final jsonStr in json) {
      try {
        sources.add(
          CustomKeySource.fromJson(jsonDecode(jsonStr) as Map<String, dynamic>),
        );
      } catch (_) {
        // Пропускаем невалидные записи
      }
    }
    return sources;
  }

  /// Получить активные пользовательские источники
  List<CustomKeySource> getEnabledSources() {
    return getAllSources().where((s) => s.enabled).toList();
  }

  /// Добавить новый источник
  Future<void> addSource(CustomKeySource source) async {
    final sources = getAllSources();
    sources.add(source);
    await _saveSources(sources);
  }

  /// Обновить существующий источник
  Future<void> updateSource(CustomKeySource source) async {
    final sources = getAllSources();
    final index = sources.indexWhere((s) => s.id == source.id);
    if (index >= 0) {
      sources[index] = source;
      await _saveSources(sources);
    }
  }

  /// Удалить источник
  Future<void> deleteSource(String sourceId) async {
    final sources = getAllSources();
    sources.removeWhere((s) => s.id == sourceId);
    await _saveSources(sources);
  }

  /// Переключить статус активности источника
  Future<void> toggleSourceEnabled(String sourceId, bool enabled) async {
    final sources = getAllSources();
    final index = sources.indexWhere((s) => s.id == sourceId);
    if (index >= 0) {
      sources[index] = sources[index].copyWith(enabled: enabled);
      await _saveSources(sources);
    }
  }

  /// Очистить все пользовательские источники
  Future<void> clearAll() async {
    await _prefs.remove(_customSourcesKey);
  }

  /// Обновить информацию о последней загрузке источника
  Future<void> updateSourceFetchInfo(
    String sourceId, {
    required int keyCount,
    required int timestampMs,
    String? errorMessage,
  }) async {
    final sources = getAllSources();
    final index = sources.indexWhere((s) => s.id == sourceId);
    if (index >= 0) {
      sources[index] = sources[index].copyWith(
        lastFetchTimestampMs: timestampMs,
        lastKeyCount: keyCount,
        lastErrorMessage: errorMessage,
      );
      await _saveSources(sources);
    }
  }

  Future<void> _saveSources(List<CustomKeySource> sources) async {
    final json = [for (final source in sources) jsonEncode(source.toJson())];
    await _prefs.setStringList(_customSourcesKey, json);
  }
}

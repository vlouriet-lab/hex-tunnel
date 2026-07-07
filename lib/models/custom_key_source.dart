import 'package:hex_decensor/models/routing_mode.dart';

/// Тип пользовательского источника ключей
enum CustomSourceType {
  /// Загрузка из URL (GitHub, другие источники в сети)
  /// Ответ — обычный текст с URI на каждой строке.
  url('URL'),

  /// Динамическая подписка (V2Ray/Xray/Sing-box subscribe endpoints).
  /// Ответ может быть Base64-кодированным списком URI или простым текстом.
  subscription('Подписка'),

  /// Локальный файл на устройстве
  localFile('Локальный файл');

  final String displayName;
  const CustomSourceType(this.displayName);
}

/// Модель пользовательского источника ключей
class CustomKeySource {
  static const Object _noChange = Object();

  /// Уникальный идентификатор (UUID или просто timestamp + random)
  final String id;

  /// Название источника (для пользователя)
  final String name;

  /// Тип источника (URL или локальный файл)
  final CustomSourceType type;

  /// URL источника (для type == url)
  final String? url;

  /// Путь к локальному файлу (для type == localFile)
  final String? filePath;

  /// Тип списка (blackList или whiteList)
  final KeyListType listType;

  /// Активен ли этот источник
  final bool enabled;

  /// Когда последний раз был успешно загружен (timestamp)
  final int? lastFetchTimestampMs;

  /// Количество загруженных ключей при последней загрузке
  final int? lastKeyCount;

  /// Сообщение об ошибке при последней попытке загрузки
  final String? lastErrorMessage;

  CustomKeySource({
    required this.id,
    required this.name,
    required this.type,
    this.url,
    this.filePath,
    required this.listType,
    this.enabled = true,
    this.lastFetchTimestampMs,
    this.lastKeyCount,
    this.lastErrorMessage,
  });

  /// Копирование с изменением некоторых полей
  CustomKeySource copyWith({
    String? id,
    String? name,
    CustomSourceType? type,
    Object? url = _noChange,
    Object? filePath = _noChange,
    KeyListType? listType,
    bool? enabled,
    Object? lastFetchTimestampMs = _noChange,
    Object? lastKeyCount = _noChange,
    Object? lastErrorMessage = _noChange,
  }) {
    return CustomKeySource(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      url: identical(url, _noChange) ? this.url : url as String?,
      filePath:
          identical(filePath, _noChange) ? this.filePath : filePath as String?,
      listType: listType ?? this.listType,
      enabled: enabled ?? this.enabled,
      lastFetchTimestampMs: identical(lastFetchTimestampMs, _noChange)
          ? this.lastFetchTimestampMs
          : lastFetchTimestampMs as int?,
      lastKeyCount: identical(lastKeyCount, _noChange)
          ? this.lastKeyCount
          : lastKeyCount as int?,
      lastErrorMessage: identical(lastErrorMessage, _noChange)
          ? this.lastErrorMessage
          : lastErrorMessage as String?,
    );
  }

  /// Преобразование в JSON для сохранения
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'type': type.name,
      'url': url,
      'filePath': filePath,
      'listType': listType.name,
      'enabled': enabled,
      'lastFetchTimestampMs': lastFetchTimestampMs,
      'lastKeyCount': lastKeyCount,
      'lastErrorMessage': lastErrorMessage,
    };
  }

  /// Создание из JSON
  factory CustomKeySource.fromJson(Map<String, dynamic> json) {
    return CustomKeySource(
      id: json['id'] as String,
      name: json['name'] as String,
      type: CustomSourceType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => CustomSourceType.url,
      ),
      url: json['url'] as String?,
      filePath: json['filePath'] as String?,
      listType: KeyListType.values.firstWhere(
        (e) => e.name == json['listType'],
        orElse: () => KeyListType.blackList,
      ),
      enabled: json['enabled'] as bool? ?? true,
      lastFetchTimestampMs: json['lastFetchTimestampMs'] as int?,
      lastKeyCount: json['lastKeyCount'] as int?,
      lastErrorMessage: json['lastErrorMessage'] as String?,
    );
  }
}

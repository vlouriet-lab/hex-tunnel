/// Режимы маршрутизации трафика (порт из SingBoxConfig.h).
enum RoutingMode {
  /// Весь трафик через прокси
  global,

  /// Заблокированные (иностранные) сайты через прокси, RU-домены напрямую
  ruleBased,

  /// Умная маршрутизация: только заблокированные сайты через прокси, остальное напрямую
  smart,

  /// Весь трафик через прокси, LAN напрямую
  bypassLan,

  /// RU-домены через прокси, остальное напрямую (доступ к RU из-за рубежа)
  ruleBasedRu,
}

extension RoutingModeExt on RoutingMode {
  String get displayName {
    switch (this) {
      case RoutingMode.global:      return 'Глобальный';
      case RoutingMode.ruleBased:   return 'Обход блокировок';
      case RoutingMode.smart:       return 'Умная маршрутизация';
      case RoutingMode.bypassLan:   return 'Весь трафик + LAN';
      case RoutingMode.ruleBasedRu: return 'Только RU через прокси';
    }
  }

  String get description {
    switch (this) {
      case RoutingMode.global:
        return 'Весь трафик через прокси';
      case RoutingMode.ruleBased:
        return 'Зарубежные сайты — через прокси, RU — напрямую';
      case RoutingMode.smart:
        return 'Только заблокированные сайты через прокси. Экономит трафик.';
      case RoutingMode.bypassLan:
        return 'Весь трафик через прокси, локальная сеть напрямую';
      case RoutingMode.ruleBasedRu:
        return 'RU-домены через прокси, остальное — напрямую';
    }
  }

  String get key {
    switch (this) {
      case RoutingMode.global:      return 'global';
      case RoutingMode.ruleBased:   return 'rule_based';
      case RoutingMode.smart:       return 'smart';
      case RoutingMode.bypassLan:   return 'bypass_lan';
      case RoutingMode.ruleBasedRu: return 'rule_based_ru';
    }
  }

  static RoutingMode fromKey(String key) {
    switch (key) {
      case 'global':        return RoutingMode.global;
      case 'rule_based':    return RoutingMode.ruleBased;
      case 'smart':         return RoutingMode.smart;
      case 'bypass_lan':    return RoutingMode.bypassLan;
      case 'rule_based_ru': return RoutingMode.ruleBasedRu;
      default:              return RoutingMode.bypassLan;
    }
  }
}

/// Тип списка ключей
enum KeyListType {
  /// Обход блокировок (весь трафик / заблокированные сайты)
  blackList,

  /// Только RU-трафик через прокси
  whiteList,
}

extension KeyListTypeExt on KeyListType {
  String get displayName {
    switch (this) {
      case KeyListType.blackList: return 'Туннель';
      case KeyListType.whiteList: return 'Белый список';
    }
  }
}

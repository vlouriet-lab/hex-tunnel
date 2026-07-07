enum AppConnectionMode {
  tunnel,
  offlineDeblock,
}

extension AppConnectionModeExt on AppConnectionMode {
  String get key {
    switch (this) {
      case AppConnectionMode.tunnel:
        return 'tunnel';
      case AppConnectionMode.offlineDeblock:
        return 'offline_deblock';
    }
  }

  String get displayName {
    switch (this) {
      case AppConnectionMode.tunnel:
        return 'Туннель';
      case AppConnectionMode.offlineDeblock:
        return 'Деблокер';
    }
  }

  String get shortDescription {
    switch (this) {
      case AppConnectionMode.tunnel:
        return 'Удалённый ключ, смена IP и полный туннель';
      case AppConnectionMode.offlineDeblock:
        return 'Локальный деблок без удалённого прокси';
    }
  }

  String get idleActionText {
    switch (this) {
      case AppConnectionMode.tunnel:
        return 'Нажмите для подключения';
      case AppConnectionMode.offlineDeblock:
        return 'Нажмите для запуска деблокера';
    }
  }

  static AppConnectionMode fromKey(String key) {
    switch (key) {
      case 'offline_deblock':
        return AppConnectionMode.offlineDeblock;
      case 'tunnel':
      default:
        return AppConnectionMode.tunnel;
    }
  }
}

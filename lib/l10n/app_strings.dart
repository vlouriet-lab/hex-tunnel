import 'package:flutter/material.dart';

class AppStrings {
  final Locale locale;

  const AppStrings(this.locale);

  static const supportedLocales = <Locale>[
    Locale('ru'),
    Locale('en'),
  ];

  static const LocalizationsDelegate<AppStrings> delegate =
      _AppStringsDelegate();

  static AppStrings of(BuildContext context) {
    final value = Localizations.of<AppStrings>(context, AppStrings);
    assert(value != null, 'AppStrings is not available in this context');
    return value!;
  }

  bool get isRussian => locale.languageCode.toLowerCase() != 'en';

  String tr(String key) {
    final lang = locale.languageCode.toLowerCase() == 'en' ? 'en' : 'ru';
    return _localized[key]?[lang] ?? _localized[key]?['ru'] ?? key;
  }

  String get navProtection => tr('nav.protection');
  String get navServers => tr('nav.servers');
  String get navSettings => tr('nav.settings');

  String get appSettings => tr('settings.title');
  String get sectionLanguage => tr('settings.section.language');
  String get sectionWorkMode => tr('settings.section.workMode');
  String get sectionKeyAnalysis => tr('settings.section.keyAnalysis');
  String get sectionRoutingMode => tr('settings.section.routingMode');
  String get sectionTunneling => tr('settings.section.tunneling');
  String get sectionKeyListType => tr('settings.section.keyListType');
  String get sectionSplitTunneling => tr('settings.section.splitTunneling');
  String get sectionAutoKeys => tr('settings.section.autoKeys');
  String get sectionCustomSources => tr('settings.section.customSources');

  String get languageTitle => tr('settings.language.title');
  String get languageSubtitle => tr('settings.language.subtitle');
  String get languageRu => tr('settings.language.ru');
  String get languageEn => tr('settings.language.en');

  String get cancel => tr('common.cancel');
  String get delete => tr('common.delete');
  String get reset => tr('common.reset');
  String get settingsResetDone => tr('settings.reset.done');
  String get deleteKeysDone => tr('settings.keys.deleted');
  String appLoadFailed(String error) =>
      '${tr('settings.apps.loadFailed')}: $error';

  String get deleteAllKeysTitle => tr('settings.keys.delete.title');
  String get deleteAllKeysMessage => tr('settings.keys.delete.message');
  String get resetSettingsTitle => tr('settings.reset.title');
  String get resetSettingsMessage => tr('settings.reset.message');

  String get serversTitle => tr('main.servers.title');
  String get allLabel => tr('main.all');
  String get whiteListLabel => tr('main.whiteList');
  String get russiaLabel => tr('main.russia');
  String keysCount(int count) => '${tr('main.keysCount')}: $count';
  String get noKeys => tr('main.noKeys');
  String countriesCount(int count) => '${tr('main.countriesCount')}: $count';
  String selectedCountry(String flag, String name) =>
      '${tr('main.selected')}: $flag $name';
  String get noCountries => tr('main.noCountries');
  String get russianKeysNotLoaded => tr('main.russianKeysNotLoaded');
  String get serversNotLoaded => tr('main.serversNotLoaded');
  String get tapToRefreshServers => tr('main.tapToRefreshServers');
  String get downloadServers => tr('main.downloadServers');
  String get routingModeTitle => tr('main.routingModeTitle');
  String get routingModeSubtitle => tr('main.routingModeSubtitle');

  static const Map<String, Map<String, String>> _localized = {
    'nav.protection': {'ru': 'Защита', 'en': 'Protection'},
    'nav.servers': {'ru': 'Серверы', 'en': 'Servers'},
    'nav.settings': {'ru': 'Настройки', 'en': 'Settings'},
    'common.cancel': {'ru': 'Отмена', 'en': 'Cancel'},
    'common.delete': {'ru': 'Удалить', 'en': 'Delete'},
    'common.reset': {'ru': 'Сбросить', 'en': 'Reset'},
    'settings.title': {'ru': 'Настройки', 'en': 'Settings'},
    'settings.section.language': {
      'ru': 'Язык интерфейса',
      'en': 'App language'
    },
    'settings.section.workMode': {'ru': 'Режим работы', 'en': 'Work mode'},
    'settings.section.keyAnalysis': {
      'ru': 'Анализ ключа',
      'en': 'Key analysis'
    },
    'settings.section.routingMode': {
      'ru': 'Трафик через VPN',
      'en': 'VPN traffic'
    },
    'settings.section.tunneling': {'ru': 'Защита соединения', 'en': 'Connection security'},
    'settings.section.keyListType': {
      'ru': 'Список VPN-ключей',
      'en': 'Key list'
    },
    'settings.section.splitTunneling': {
      'ru': 'Выбор приложений для VPN',
      'en': 'App-level VPN'
    },
    'settings.section.autoKeys': {
      'ru': 'Автоматические ключи',
      'en': 'Auto keys'
    },
    'settings.section.customSources': {
      'ru': 'Пользовательские источники',
      'en': 'Custom sources'
    },
    'settings.language.title': {
      'ru': 'Язык приложения',
      'en': 'Application language'
    },
    'settings.language.subtitle': {
      'ru': 'Переключает интерфейс между русским и английским',
      'en': 'Switches interface between Russian and English'
    },
    'settings.language.ru': {'ru': 'Русский', 'en': 'Russian'},
    'settings.language.en': {'ru': 'Английский', 'en': 'English'},
    'settings.keys.delete.title': {
      'ru': 'Удалить все ключи?',
      'en': 'Delete all keys?'
    },
    'settings.keys.delete.message': {
      'ru':
          'Будут удалены все загруженные и вручную добавленные ключи. Это действие можно отменить только повторной загрузкой.',
      'en':
          'All downloaded and manually added keys will be removed. You can only restore them by loading them again.'
    },
    'settings.reset.title': {
      'ru': 'Сбросить настройки?',
      'en': 'Reset settings?'
    },
    'settings.reset.message': {
      'ru':
          'Будут сброшены параметры подключения и режима. Ключи останутся в приложении.',
      'en':
          'Connection and mode parameters will be reset. Keys will remain in the app.'
    },
    'settings.keys.deleted': {
      'ru': 'Все ключи удалены',
      'en': 'All keys were deleted'
    },
    'settings.reset.done': {
      'ru': 'Настройки сброшены',
      'en': 'Settings were reset'
    },
    'settings.apps.loadFailed': {
      'ru': 'Не удалось загрузить приложения',
      'en': 'Failed to load apps'
    },
    'main.servers.title': {'ru': 'Серверы', 'en': 'Servers'},
    'main.all': {'ru': 'Все', 'en': 'All'},
    'main.whiteList': {'ru': 'Белый список', 'en': 'Whitelist'},
    'main.russia': {'ru': 'Россия', 'en': 'Russia'},
    'main.keysCount': {'ru': 'Ключей', 'en': 'Keys'},
    'main.noKeys': {'ru': 'Нет ключей', 'en': 'No keys'},
    'main.countriesCount': {'ru': 'Стран', 'en': 'Countries'},
    'main.selected': {'ru': 'Выбрано', 'en': 'Selected'},
    'main.noCountries': {'ru': 'Нет стран', 'en': 'No countries'},
    'main.russianKeysNotLoaded': {
      'ru': 'Российские ключи не загружены',
      'en': 'Russian keys are not loaded'
    },
    'main.serversNotLoaded': {
      'ru': 'Серверы не загружены',
      'en': 'Servers are not loaded'
    },
    'main.tapToRefreshServers': {
      'ru': 'Нажмите для обновления серверов',
      'en': 'Tap to refresh servers'
    },
    'main.downloadServers': {
      'ru': 'Загрузить серверы',
      'en': 'Download servers'
    },
    'main.routingModeTitle': {
      'ru': 'Режим маршрутизации',
      'en': 'Routing mode'
    },
    'main.routingModeSubtitle': {
      'ru': 'Как направлять трафик через туннель',
      'en': 'How traffic should be routed through the tunnel'
    },
  };
}

class _AppStringsDelegate extends LocalizationsDelegate<AppStrings> {
  const _AppStringsDelegate();

  @override
  bool isSupported(Locale locale) => AppStrings.supportedLocales.any(
        (supported) => supported.languageCode == locale.languageCode,
      );

  @override
  Future<AppStrings> load(Locale locale) async => AppStrings(locale);

  @override
  bool shouldReload(covariant LocalizationsDelegate<AppStrings> old) => false;
}

extension AppStringsX on BuildContext {
  AppStrings get l10n => AppStrings.of(this);
}

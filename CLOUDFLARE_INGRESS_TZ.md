# ТЗ: Cloudflare-backed ingress для Hex Decensor

Дата: 2026-04-13
Статус: draft
Контекст: Hex Decensor (Flutter + Android VpnService + libbox/sing-box)

## 1. Цель

Добавить в Hex Decensor поддержку Cloudflare-backed ingress как дополнительного способа доставки трафика до входного узла прокси.

Ожидаемый эффект:

- повысить вероятность успешного подключения в сетях с DPI и жёсткой фильтрацией;
- уменьшить зависимость от прямой доступности origin-хоста;
- дать возможность использовать один и тот же логический профиль в двух вариантах доставки: direct и cloudflare ingress;
- сохранить совместимость с текущей архитектурой tunnel mode без добавления нового верхнеуровневого режима приложения.

## 2. Ключевое решение

Cloudflare ingress внедряется не как новый connection mode, а как способ доставки внутри существующего tunnel mode.

Это означает:

- верхнеуровневые режимы приложения остаются прежними: Tunnel и Offline Deblock;
- Cloudflare ingress применяется только к tunnel mode;
- логический профиль может иметь один или несколько delivery-вариантов;
- во внешнем UI пользователь видит это как способ подключения через edge, а не как отдельный тип VPN.

## 3. Термины

### 3.1 Logical profile

Логический профиль сервера, описывающий конечную прокси-схему с её протоколом, TLS-параметрами, транспортом и origin-сервером.

### 3.2 Delivery mode

Способ доставки трафика до входной точки профиля.

Поддерживаемые значения в рамках v1:

- direct
- cloudflare

### 3.3 Ingress

Публичная входная точка за Cloudflare, через которую клиент заходит на edge и далее попадает на origin.

### 3.4 Origin

Реальный сервер, на котором размещён совместимый inbound.

### 3.5 Effective runtime profile

Профиль, который реально передаётся в генератор sing-box конфига после применения delivery mode и runtime-политики fallback.

## 4. Scope v1

В первую итерацию входят только сценарии, которые реалистично совместимы с Cloudflare-backed ingress и текущим стеком приложения.

### 4.1 Входит в v1

- VLESS через ws
- VLESS через httpupgrade
- VLESS через grpc
- VLESS через h2
- Trojan через ws
- Trojan через grpc или h2, если серверная сторона подтверждена
- VMess только как optional compatibility path, без обязательной UI-экспозиции в первой сборке
- direct fallback для ingress-профиля
- выбор предпочтительного delivery mode
- диагностика и логирование ingress-подключений
- frontend для отображения и управления ingress-настройками

### 4.2 Не входит в v1

- отдельная relay-сеть наподобие iroh
- собственный relay-протокол
- ingress для TUIC
- ingress для Hysteria/Hysteria2
- ingress для WireGuard/AWG
- Cloudflare ingress для Reality-сценариев
- автоматическое получение edge-конфигурации из внешней control plane
- desktop и web-реализация

## 5. Ограничения и допущения

### 5.1 Ограничения протоколов

Cloudflare ingress в v1 должен использоваться только для TCP/TLS-совместимых transport-сценариев. QUIC/UDP-first протоколы должны блокироваться валидатором до старта.

### 5.2 Ограничения по Reality

Для v1 комбинация cloudflare + reality считается неподдерживаемой. Если профиль использует Reality, ingress-вариант для него не строится.

### 5.3 Ограничения по инфраструктуре

Техническое задание не покрывает автоматическое развёртывание Cloudflare-конфигурации. Предполагается, что у команды есть отдельно управляемая edge/origin инфраструктура.

### 5.4 Ограничения по режимам приложения

Offline Deblock не использует Cloudflare ingress.

## 6. Текущее состояние кодовой базы

На момент составления ТЗ проект уже содержит:

- генерацию sing-box конфигов для ws, grpc, h2 и httpupgrade;
- fallback xhttp -> ws на уровне TunnelProvider;
- сериализацию и хранение ProxyProfile;
- ручной импорт ключей через URI;
- auto/manual selection pipeline;
- Android-side запуск sing-box через libbox.

Это позволяет внедрять ingress без пересмотра всей архитектуры туннеля.

## 7. Архитектурная модель v1

### 7.1 Общая схема

Pipeline подключения в tunnel mode после внедрения:

1. Пользователь или источник выбирает logical profile.
2. TunnelProvider определяет допустимые delivery-варианты.
3. Выбирается preferred delivery mode.
4. На базе logical profile строится effective runtime profile.
5. SingBoxService передаёт runtime profile в SingBoxConfigGenerator.
6. Генератор собирает outbound с параметрами edge transport.
7. При ошибке и разрешённом fallback выполняется повторный старт через другой delivery mode.

### 7.2 Принцип совместимости

Исходный профиль не должен разрушаться при переключении delivery mode. Все runtime-изменения должны происходить в отдельной стадии резолвинга профиля перед запуском.

### 7.3 Принцип минимальной инвазивности

В v1 не вводится новый Android service, новый channel или новый libbox integration layer. Изменения ограничиваются моделью данных, провайдером, генератором конфига и UI.

## 8. Изменения в модели данных

### 8.1 Новая сущность DeliveryMode

Нужен enum DeliveryMode:

- direct
- cloudflare

### 8.2 Новая сущность IngressConfig

Нужен отдельный объект ingress-настроек, который хранится внутри logical profile или в обёртке над ним.

Рекомендуемые поля:

- enabled: bool
- provider: String, в v1 фиксированное значение cloudflare
- edgeHost: String
- edgePort: int
- edgePath: String
- hostHeader: String
- transport: String
- allowDirectFallback: bool
- preferIngress: bool
- notes: String
- logicalProfileId: String

### 8.3 Изменения в ProxyProfile

Вариант внедрения для v1:

- либо расширить ProxyProfile ingress-полями;
- либо ввести обёртку над ProxyProfile, например ManagedProxyProfile;
- для минимального объёма изменений допустимо расширить ProxyProfile, если это не делает модель неуправляемой.

Рекомендуемые новые поля в ProxyProfile:

- deliveryMode
- ingressEnabled
- ingressProvider
- ingressEdgeHost
- ingressEdgePort
- ingressPath
- ingressHostHeader
- ingressTransport
- ingressAllowDirectFallback
- logicalProfileId
- sourceProfileRawUri

### 8.4 Сериализация

Все новые поля должны быть добавлены в:

- copyWith
- toJson
- fromJson
- миграцию старых данных

Старые профили без ingress-полей должны корректно открываться как direct.

## 9. Изменения в источниках данных и импорте

### 9.1 Auto profiles

Автоисточники должны получить возможность отдавать ingress-метаданные отдельно от raw URI.

Поддерживаемые форматы v1:

- sidecar JSON рядом с набором ключей;
- встроенные поля в собственном internal feed формате;
- локальная мапа enrich-правил на стороне клиента для controlled pilot.

### 9.2 Manual profiles

Текущий ручной импорт через одну URI-строку сохраняется.

Дополнительно нужен advanced flow:

- пользователь вставляет обычный ключ;
- пользователь вручную включает Cloudflare ingress;
- пользователь задаёт edgeHost, path, Host header и предпочтительный transport;
- клиент сохраняет это как logical profile + ingress metadata.

### 9.3 Ограничения парсера URI

URI parser не должен пытаться поддерживать произвольный новый URI-диалект ради ingress. В v1 лучше хранить ingress-настройки отдельно от raw URI.

## 10. Runtime-резолвер профиля

### 10.1 Новая стадия перед стартом

Перед вызовом SingBoxService.start должен существовать отдельный шаг:

- resolveRuntimeProfile(logicalProfile, deliveryMode)

Он должен:

- валидировать совместимость профиля и delivery mode;
- подменять server, port, path, host header и transport при необходимости;
- помечать runtime profile метаданными для логов;
- возвращать direct-вариант без изменения исходного профиля.

### 10.2 Правила преобразования для cloudflare

Для cloudflare delivery runtime profile должен:

- использовать edgeHost как server;
- использовать edgePort как port;
- использовать ingress transport, если он задан отдельно;
- использовать ingress path, если transport path-based;
- использовать ingress hostHeader как Host;
- использовать edgeHost как SNI, если отдельная политика не требует иного;
- при необходимости сохранять origin host в отдельном поле для диагностики.

### 10.3 Правила преобразования для direct

Для direct delivery runtime profile должен оставаться эквивалентным исходному logical profile.

## 11. Изменения в генераторе sing-box конфига

### 11.1 Общая задача

SingBoxConfigGenerator должен уметь строить outbound из runtime profile с ingress-параметрами без знания о бизнес-происхождении этих параметров.

### 11.2 Требуемое поведение

- ws должен использовать runtime path и runtime host header;
- httpupgrade должен использовать runtime host и path;
- grpc должен использовать runtime host/SNI и service_name;
- h2 должен использовать runtime host и runtime SNI;
- лог должен содержать маркеры delivery mode;
- direct и cloudflare варианты должны генерироваться одинаковым код-путём.

### 11.3 Запрещённое поведение

- нельзя в генераторе смешивать UI-логику и техническую трансформацию;
- нельзя делать специальную ветку для cloudflare, если достаточно runtime profile abstraction;
- нельзя silently запускать неподдерживаемые protocol/delivery combinations.

## 12. Валидатор совместимости

### 12.1 Цель

До старта туннеля нужно явно отсеивать несовместимые комбинации профиля и delivery mode.

### 12.2 Минимальный набор правил v1

Cloudflare delivery запрещён, если:

- protocol = tuic
- protocol = hysteria
- protocol = hysteria2
- protocol = wireguard
- protocol = awg
- reality = true
- transport пустой или несовместимый с edge policy

### 12.3 Место применения

Валидация должна выполняться:

- на Dart-уровне до старта;
- при открытии advanced UI, чтобы скрывать нерелевантные опции;
- в preflight логике перед фактическим запуском, как safety net.

### 12.4 Формат ошибки

Нужны стабильные error codes, например:

- ingress_unsupported_protocol
- ingress_reality_not_supported
- ingress_invalid_edge_host
- ingress_missing_host_header
- ingress_transport_not_supported

## 13. Изменения в TunnelProvider

### 13.1 Выбор delivery mode

TunnelProvider должен принимать решение о способе доставки по следующей схеме:

1. Если ingress для профиля недоступен, использовать direct.
2. Если ingress доступен и preferIngress включён, первым пробовать cloudflare.
3. Если ingress доступен, но preferIngress выключён, использовать direct.
4. Если запуск cloudflare-варианта не удался и разрешён fallback, пробовать direct.
5. Если direct тоже не удался, переходить к следующему логическому профилю.

### 13.2 Новая runtime-политика

Нужны новые helper-методы:

- supportsIngress(profile)
- resolveDeliveryCandidates(profile)
- resolveRuntimeProfile(profile, deliveryMode)
- attemptDeliveryFallback(profile, failedDeliveryMode)

### 13.3 Учёт успехов и неудач

Статистика должна учитывать не только rawUri, но и delivery mode.

Минимум нужны отдельные счётчики:

- logicalProfileId + direct
- logicalProfileId + cloudflare

### 13.4 Fallback и cooldown

Нельзя трактовать падение cloudflare-варианта как полную смерть logical profile. В v1 cooldown должен быть раздельным по delivery mode.

### 13.5 Auto mode

Для auto mode логика подбора должна работать на уровне logical profiles, а не раздувать список профилей в UI дубликатами direct/cf без необходимости.

## 14. Изменения в SingBoxService

### 14.1 Новая ответственность

SingBoxService должен получать уже resolved runtime profile, а не сам принимать продуктовые решения о выборе ingress.

### 14.2 Диагностические поля

В start-пайплайне нужно пробрасывать в логи:

- logicalProfileId
- deliveryMode
- edgeHost
- transport
- fallbackAttempt

### 14.3 Совместимость

Сигнатура start может быть расширена метаданными, но базовый контракт запуска через config string должен остаться совместимым.

## 15. Frontend: общие требования

### 15.1 Принцип UX

Внешний интерфейс не должен вводить отдельный режим VPN под ingress. Пользователь должен воспринимать это как способ подключения через edge.

### 15.2 Терминология

Рекомендуемые тексты в UI:

- Cloudflare Edge
- Подключаться через edge
- Резервный прямой вход
- Способ доставки

Слово ingress допустимо в документации и логах, но не обязательно как основная пользовательская формулировка.

## 16. Frontend: Settings screen

### 16.1 Новый раздел

На settings screen нужен отдельный блок, связанный с tunnel mode.

Рабочее название секции:

- Cloudflare Edge

### 16.2 Содержимое секции

Минимальный набор элементов:

- глобальный switch "Предпочитать Cloudflare Edge, если доступен"
- switch "Разрешать резервный прямой вход"
- switch "Показывать edge-варианты в списке серверов"
- текст-подсказка с ограничениями совместимости

### 16.3 Поведение секции

- секция активна только в tunnel mode;
- изменения сохраняются в prefs;
- если пользователь выключает prefer ingress, direct остаётся дефолтом даже при наличии ingress-метаданных;
- если пользователь выключает fallback, провайдер не должен silently идти в direct после падения edge.

## 17. Frontend: Servers screen

### 17.1 Список серверов

На servers screen нужно показать способ доставки для профилей, у которых доступен ingress.

Варианты отображения:

- badge CF Edge;
- фильтр All / Direct / Cloudflare;
- иконка cloud на карточке профиля;
- дополнительная строка summary на tile.

### 17.2 Детали ключа

В details sheet нужно добавить поля:

- Delivery mode
- Edge host
- Edge path
- Host header
- Direct fallback
- Ingress compatibility

### 17.3 Manual add flow

В нижнем sheet добавления собственного ключа нужен advanced-блок:

- switch "Использовать Cloudflare Edge"
- поле edge host
- поле edge path
- поле Host header
- выбор preferred transport, если это уместно
- switch "Разрешить fallback на прямой вход"

### 17.4 Ограничение UI

Если inserted key заведомо несовместим с ingress, advanced ingress controls должны быть скрыты или disabled с пояснением причины.

## 18. Frontend: Main screen

### 18.1 Статус подключения

На главном экране после подключения нужно показать способ доставки.

Пример:

- Подключено через Cloudflare Edge
- Подключено напрямую

### 18.2 Fallback status

Если произошёл fallback с edge на direct, пользователь должен видеть это в кратком статусе и в подробных логах/снекбаре.

### 18.3 Необходимость

Это критично для диагностики и для снижения путаницы, когда один и тот же логический сервер работает по-разному в разных сетях.

## 19. Хранение настроек

### 19.1 Новые глобальные prefs

Нужны новые ключи настроек:

- prefer_cloudflare_ingress
- allow_direct_fallback_for_ingress
- show_ingress_variants_in_server_list

### 19.2 Хранение profile-level метаданных

Ingress-метаданные профилей должны попадать в сериализацию manual profiles и auto profile cache.

### 19.3 Миграция

Профили без ingress-данных должны загружаться без ошибок и трактоваться как direct-only.

## 20. Диагностика и логирование

### 20.1 Что логировать

Во Flutter и Android-логах необходимо логировать:

- logicalProfileId
- rawUri hash или безопасный идентификатор
- deliveryMode
- edgeHost
- transport
- fallback path
- errorCode
- stage

### 20.2 Что не логировать

Нельзя логировать в открытом виде:

- полный raw URI с секретами
- пароль/uuid/private key
- токены edge control plane

### 20.3 Новые стадии

Минимальный набор stage:

- ingress_resolve
- ingress_validate
- ingress_connect
- ingress_fallback_direct
- ingress_failed_terminal

### 20.4 Пользовательская диагностика

В случае ошибки UI должен показывать компактное сообщение высокого уровня, а технические детали оставлять в логах и diagnostic screens.

## 21. Безопасность

### 21.1 Секреты

Ingress-параметры сами по себе не всегда секретны, но если используются приватные edge hostname или служебные токены, они должны храниться по тем же правилам, что и ручные профили.

### 21.2 Поверхность ошибок

Нельзя автоматически пробовать опасные downgrade-path без явной политики. В v1 допустим только cloudflare -> direct fallback при включённой настройке.

### 21.3 Data minimization

UI и логи не должны раскрывать origin hostname там, где пользователю достаточно информации о delivery mode.

## 22. Производительность

### 22.1 Ограничения v1

Cloudflare ingress не должен удваивать количество отображаемых карточек и запусков без необходимости.

### 22.2 Подбор кандидатов

На этапе auto-pool следует считать direct и cloudflare вариант одного logical profile родственными вариантами, а не отдельными серверами с полным весом в ротации.

### 22.3 Сетевые проверки

Не добавлять дорогие ingress-specific probes на каждый refresh. В v1 достаточно runtime-логики во время реального connect и стандартных health-check flows.

## 23. Порядок внедрения

### Phase 0. Pilot без продуктовых правок

Цель:

- проверить жизнеспособность server-side Cloudflare ingress на текущем клиенте.

Задачи:

- поднять тестовый edge-host;
- подготовить 1-2 совместимых ключа;
- проверить подключение на текущем ws/httpupgrade pipeline;
- зафиксировать ограничения по transport и Host/SNI.

Критерий завершения:

- есть хотя бы один воспроизводимый рабочий ingress-кейс на текущем клиенте.

### Phase 1. Core model and runtime support

Цель:

- добавить model layer, сериализацию и runtime resolver.

Задачи:

- добавить DeliveryMode и ingress fields;
- реализовать миграцию;
- внедрить compatibility validator;
- добавить runtime profile resolver;
- расширить provider для delivery policy.

Критерий завершения:

- manual profile с ingress-метаданными может быть запущен через cloudflare и direct.

### Phase 2. Fallback, metrics, diagnostics

Цель:

- стабилизировать поведение и улучшить наблюдаемость.

Задачи:

- добавить fallback direct <-> cloudflare;
- разделить cooldown и success counters по delivery mode;
- расширить логи и error codes;
- добавить статус delivery mode в runtime state.

Критерий завершения:

- при падении edge-входа direct fallback работает предсказуемо и диагностируемо.

### Phase 3. Frontend rollout

Цель:

- дать пользователю управляемый и понятный UI.

Задачи:

- settings block;
- server list badges and filters;
- advanced manual add UI;
- main screen delivery status.

Критерий завершения:

- пользователь может включить ingress, понять активный delivery mode и увидеть fallback-поведение.

## 24. Изменения по файлам

Ниже приведён целевой перечень файлов, которые с высокой вероятностью потребуют изменений.

### 24.1 Модель и парсинг

- lib/models/proxy_profile.dart
- lib/services/uri_parser.dart

### 24.2 Конфиг и запуск

- lib/config/singbox_config_generator.dart
- lib/services/singbox_service.dart
- lib/providers/tunnel_provider.dart

### 24.3 UI

- lib/screens/settings_screen.dart
- lib/screens/servers_screen.dart
- lib/screens/main_screen.dart

### 24.4 Android-side логирование

- android/app/src/main/kotlin/com/sota/hexdecensor/SingBoxBridge.kt
- android/app/src/main/kotlin/com/sota/hexdecensor/HexVpnService.kt
- android/app/src/main/kotlin/com/sota/hexdecensor/SingBoxController.kt

## 25. Тест-план

### 25.1 Unit / logic tests

Нужны проверки на:

- миграцию старых профилей;
- сериализацию ingress fields;
- compatibility validator;
- runtime profile resolver;
- fallback policy;
- direct-only profile unaffected path.

### 25.2 Manual QA scenarios

Минимальный набор сценариев:

1. Direct-only профиль подключается как раньше.
2. Ingress-enabled профиль подключается через Cloudflare.
3. Ingress-enabled профиль падает на edge и уходит в direct fallback.
4. Ingress-enabled профиль падает без fallback и показывает понятную ошибку.
5. Несовместимый профиль скрывает ingress controls.
6. После перезапуска приложения ingress-настройки и выбранный режим сохраняются.
7. В details screen корректно отображаются ingress-параметры.

### 25.3 Device QA

Проверить минимум на:

- физическом Samsung/Android 16, который уже используется в диагностике проекта;
- эмуляторе Android для smoke check;
- сети с обычным доступом;
- сети с ограничениями, где direct и ingress ведут себя по-разному.

## 26. KPI и критерии успеха

### 26.1 Технические KPI

- доля успешных ingress-start попыток;
- доля успешных fallback cloudflare -> direct;
- среднее время до usable tunnel для ingress-профилей;
- доля ошибок по ingress-specific error codes;
- число регрессий direct-only профилей.

### 26.2 Продуктовые критерии успеха

- пользователь может использовать совместимый профиль через Cloudflare Edge без ручной правки конфига вне приложения;
- direct-only сценарии не деградируют;
- UI не создаёт у пользователя ложного впечатления о поддержке всех протоколов;
- диагностика позволяет отличить падение origin от падения edge-сценария.

## 27. Критерии приёмки

Функция считается реализованной, если одновременно выполнены условия:

- профиль с ingress-метаданными запускается через Cloudflare Edge в tunnel mode;
- direct profile продолжает работать без изменений поведения;
- при включённом fallback edge-failure может привести к успешному direct connect;
- в UI видно, через какой delivery mode установлено соединение;
- manual add screen позволяет ввести ingress-параметры для совместимого ключа;
- настройки ingress сохраняются между перезапусками приложения;
- логи содержат delivery mode, stage и error code без утечки секретов.

## 28. Риски

### 28.1 Технические риски

- часть transport-комбинаций окажется нестабильной на реальных сетях;
- Host/SNI/pseudo-origin настройки могут требовать серверной стандартизации;
- direct fallback может маскировать реальные ingress-problems, если логирование будет недостаточным;
- расширение ProxyProfile может привести к разрастанию модели.

### 28.2 Продуктовые риски

- пользователь решит, что ingress поддерживает все типы ключей;
- список серверов станет перегруженным без аккуратного UI-дизайна;
- manual add flow станет слишком сложным, если advanced options показать всем без контекста.

## 29. Открытые вопросы

Перед реализацией нужно финально определить:

- будут ли ingress-метаданные приходить из собственных feeds или только через ручной ввод в v1;
- нужен ли пользователю выбор transport внутри ingress, либо он фиксируется политикой сервера;
- нужен ли profile-level override поверх глобальной настройки prefer ingress;
- требуется ли отдельная визуальная группировка ingress-серверов в auto list;
- будет ли origin hostname скрываться от пользователя полностью или частично.

## 30. Рекомендуемое решение по открытым вопросам для v1

Если команда хочет минимальный и быстрый rollout, рекомендуются следующие решения:

- ingress-метаданные сначала поддерживать через manual advanced flow и controlled pilot feed;
- transport выбирать автоматически по profile metadata, без полного ручного конструктора;
- глобальная настройка prefer ingress + profile-level allow fallback достаточно для v1;
- в auto list показывать badge, а не отдельный дублирующий список;
- origin hostname не поднимать в основной UI, оставив его только в техдиагностике при необходимости.

## 31. Итог

Cloudflare-backed ingress для Hex Decensor в рамках v1 является реалистичной функцией, если трактовать его как delivery mode внутри существующего tunnel mode, а не как отдельную relay-сеть или новый тип VPN.

Главная инженерная идея внедрения:

- сохранить logical profile неизменным;
- строить effective runtime profile перед стартом;
- держать direct и cloudflare как два delivery-варианта одного логического сервера;
- оформить это понятным UI без переусложнения верхнеуровневой модели приложения.
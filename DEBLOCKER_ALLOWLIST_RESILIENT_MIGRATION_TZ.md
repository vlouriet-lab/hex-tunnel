# ТЗ: поэтапная миграция Деблокера к allowlist-resilient архитектуре

Дата: 2026-04-13
Статус: draft
Контекст: Hex Decensor (Flutter + Android VpnService + libbox/sing-box)

## 1. Цель документа

Зафиксировать целевую архитектуру и план миграции от текущего гибридного режима Деблокера, который использует выборочный Cloudflare WARP-детур, к варианту, устойчивому к жёсткому positive allowlist.

Под positive allowlist в рамках этого документа понимается режим сетевой цензуры, при котором наружу разрешены только заранее одобренные ресурсы и типы трафика, а весь остальной трафик блокируется по умолчанию.

Ожидаемый результат миграции:

- Деблокер сохраняет локальную TUN/policy архитектуру;
- наружный канал перестаёт зависеть от прямой доступности WireGuard/WARP endpoint;
- трафик обхода начинает выглядеть как разрешённый HTTPS-трафик к allowlisted ingress;
- система может работать в сетях, где разрешены только Cloudflare-hosted web-ресурсы или другой ограниченный набор edge-доменов;
- переход выполняется поэтапно, без одномоментного удаления текущего гибридного режима.

## 2. Почему текущий гибридный режим недостаточен

Текущая реализация гибридного режима полезна против сценариев массовой фильтрации и частичной блокировки, но не закрывает жёсткий positive allowlist.

### 2.1 Что делает текущая реализация

На момент составления ТЗ режим `hybrid`:

- поднимает локальный TUN как и другие профили Деблокера;
- при первом запуске автоматически регистрирует Cloudflare WARP-устройство через client API;
- сохраняет полученную WireGuard-конфигурацию локально;
- строит outbound `wireguard` с `detour: direct`;
- отправляет в `warp` только TCP 80/443;
- оставляет RU-домены direct;
- оставляет final route равным `direct`.

### 2.2 Почему это ломается под strict allowlist

Главная проблема не в policy, а в transport layer.

Даже если в стране в белом списке присутствуют Cloudflare-hosted банковские и коммерческие сайты, это не означает, что разрешён WireGuard/WARP как сетевой транспорт.

Возможные сценарии блокировки, при которых текущая реализация не выживает:

- разрешён только HTTPS к конкретным hostnames, но не произвольный UDP к Cloudflare edge;
- разрешён только TLS с допустимым SNI, но не прямой WireGuard handshake;
- разрешены только запросы к ограниченному набору IP и доменов, а WARP endpoint в него не входит;
- allowlist ориентируется на HTTP/SNI/ALPN-профиль приложений, а WireGuard не маскируется под обычный web-трафик.

### 2.3 Следствие

Чтобы переживать strict positive allowlist, нужно менять не только route rules, а сам способ доставки обходного трафика наружу.

## 3. Основное архитектурное решение

Целевой allowlist-resilient вариант должен строиться по схеме:

1. Локальный TUN и policy engine остаются в приложении.
2. Внешний транспорт больше не опирается на WARP/WireGuard.
3. Для обходного трафика используется allowlisted ingress, выглядящий как обычный HTTPS-трафик.
4. Деблокер получает отдельный delivery layer, близкий по идее к ранее обсуждавшемуся Cloudflare-backed ingress, но встроенный в локальный deblock pipeline.

Иными словами:

- текущий `hybrid` режим = TUN + selective WARP detour;
- целевой режим = TUN + selective allowlisted HTTPS ingress detour.

## 4. Термины

### 4.1 Policy engine

Локальный слой, который внутри TUN принимает решение, какой трафик отправлять напрямую, какой через обходной транспорт, а какой блокировать.

### 4.2 Delivery layer

Внешний транспортный слой, по которому трафик обхода доставляется до edge/origin.

### 4.3 Allowlisted ingress

Публичная HTTPS-совместимая входная точка, доступ к которой разрешён даже в режиме positive allowlist.

### 4.4 Deblocker profile

Профиль локального деблокера, задающий DNS/policy/transport поведение.

### 4.5 Control plane

Слой распределения конфигурации ingress-узлов, политик маршрутизации, fallback-правил и метаданных доставки.

### 4.6 Data plane

Фактическая передача полезного трафика пользователя через выбранный обходной transport.

## 5. Целевое состояние vTarget

### 5.1 Инварианты целевой архитектуры

Должны сохраняться следующие свойства:

- приложение по-прежнему работает через Android VpnService + TUN;
- локальный DNS/policy слой остаётся в Hex Decensor;
- обходной транспорт подключается выборочно, а не для всего трафика безусловно;
- direct path остаётся как отдельная траектория для разрешённых локально ресурсов;
- transport внешне выглядит как допустимый HTTPS-трафик к allowlisted endpoint.

### 5.2 Что должно измениться принципиально

Должны измениться следующие части:

- WARP перестаёт быть основной ставкой для allowlist-resilient режима;
- появляется ingress-oriented delivery model;
- outbound-профиль должен уметь выглядеть как обычный HTTPS/HTTP2/WebSocket/gRPC трафик к edge host;
- классификация трафика должна стать domain-aware и policy-driven, а не только port-aware;
- control plane должен поставлять заранее готовые ingress-конфигурации без требования онлайн-регистрации на устройстве.

## 6. Scope миграции

### 6.1 Входит в scope

- сохранение и поддержка текущего гибридного режима на переходный период;
- проектирование нового allowlist-resilient delivery layer;
- добавление ingress metadata и transport policy в модель данных;
- staged rollout через feature flags;
- migration path для UI, провайдера состояния и генератора конфига;
- диагностические и acceptance сценарии для strict allowlist.

### 6.2 Не входит в scope первого цикла

- полноценная relay-сеть собственного дизайна;
- peer-to-peer mesh;
- desktop migration;
- полная перестройка существующего tunnel mode;
- автоматический DevOps rollout edge infrastructure;
- универсальная поддержка любого CDN без ограничений.

## 7. Текущее состояние кодовой базы

### 7.1 Уже есть

- локальный TUN-based Deblocker;
- профили `soft`, `balanced`, `hybrid`, `aggressive`, `ultra`, `custom`;
- WARP provisioning service;
- persistence для hybrid settings;
- selective route rules;
- существующая tunnel-архитектура с поддержкой ws, httpupgrade, grpc, h2;
- опыт обсуждения и ТЗ для Cloudflare-backed ingress в отдельном документе.

### 7.2 Уже подтверждённые сильные стороны

- подход TUN + policy engine в Android-архитектуре уже работает;
- transport-conversion логика для tunnel mode в проекте уже существует;
- sing-box generator умеет собирать современные TCP/TLS-based outbounds;
- UI и provider-слой уже умеют работать с несколькими профилями и пресетами.

### 7.3 Уже подтверждённые слабые стороны

- текущий гибрид завязан на WARP/WireGuard transport;
- policy для гибрида пока слишком грубая: TCP 80/443 через warp, RU direct;
- нет отдельного domain allowlist / domain detour policy слоя;
- нет control plane для ingress profile distribution;
- нет offline bootstrap of delivery metadata.

## 8. Архитектурная цель после миграции

### 8.1 Общая схема

Целевая схема выглядит так:

1. TUN inbound принимает трафик приложений.
2. Локальный DNS/policy engine анализирует домены, IP, тип трафика и policy class.
3. Для direct-ресурсов трафик остаётся local direct.
4. Для blocked/unknown web-трафика используется allowlisted ingress outbound.
5. Внешний трафик до ingress выглядит как допустимый HTTPS-сеанс к разрешённому host.
6. На edge/origin происходит дальнейшая доставка к реальному upstream.

### 8.2 Принцип transport camouflage

Обходной outbound должен удовлетворять двум условиям:

- снаружи выглядеть как разрешённый web-трафик;
- внутри поддерживать проксирование пользовательского потока без необходимости отдельного VPN-протокола.

### 8.3 Принцип bootstrap independence

Для запуска allowlist-resilient режима клиент не должен требовать онлайн-регистрации нового транспорта в момент блокировки.

Это означает:

- никакой обязательной live-registration наподобие WARP device registration;
- ingress metadata должна поставляться заранее;
- клиент должен уметь запускаться с уже готовым runtime bundle.

## 9. Target architecture components

### 9.1 Новый delivery abstraction layer

Нужен отдельный слой абстракции доставки трафика, независимый от конкретного Deblocker profile.

Рекомендуемая сущность: `DeblockerDeliveryMode`

Поддерживаемые значения на переходный период:

- `direct_only`
- `warp_hybrid_legacy`
- `allowlisted_ingress`

В более поздней версии `warp_hybrid_legacy` может быть снят с production-рекомендации, но должен временно остаться для fallback и мягких сетей.

### 9.2 Новый ingress metadata object

Нужен объект с runtime-параметрами allowlisted ingress.

Рекомендуемая сущность: `DeblockerIngressConfig`

Минимальные поля:

- `enabled: bool`
- `provider: String`
- `edgeHost: String`
- `edgePort: int`
- `transport: String`
- `path: String`
- `hostHeader: String`
- `sni: String`
- `alpn: List<String>`
- `allowDirectFallback: bool`
- `originHint: String`
- `policyTag: String`
- `configVersion: int`
- `expiresAt: String?`

### 9.3 Новый traffic policy object

Нужен объект policy-классификации трафика.

Рекомендуемая сущность: `DeblockerTrafficPolicy`

Минимальные поля:

- `directDomainSuffixes: List<String>`
- `directExactDomains: List<String>`
- `ingressDomainSuffixes: List<String>`
- `ingressExactDomains: List<String>`
- `fallbackToIngressForUnknownHttps: bool`
- `allowDirectForPrivateIp: bool`
- `blockUnsupportedUdp: bool`
- `blockIpv6WhenNeeded: bool`
- `policyVersion: int`

### 9.4 Новый runtime bundle

Для стабильного bootstrap нужен единый bundle, из которого Deblocker может стартовать без live provisioning.

Рекомендуемая сущность: `DeblockerRuntimeBundle`

Поля:

- `profilePreset`
- `deliveryMode`
- `ingressConfig`
- `trafficPolicy`
- `diagnosticPolicy`
- `createdAt`
- `ttl`

## 10. Что нужно менять в модели данных

### 10.1 Профиль Деблокера

Текущий `OfflineDeblockSettings` должен перестать быть местом, где живут только WARP-specific поля.

Нужно перейти к разделению:

- policy settings;
- legacy warp settings;
- ingress delivery settings.

Рекомендуемый путь:

1. Сохранить текущие WARP-поля как legacy-compatible.
2. Добавить новый контейнер ingress-настроек.
3. Ввести явный `deliveryMode` на уровне профиля.

### 10.2 Persistence

Требуется separate persistence для:

- legacy hybrid settings;
- ingress runtime bundle;
- versioned migration markers.

### 10.3 Backward compatibility

Старые инсталляции должны продолжать открываться так:

- если есть старый hybrid profile, он загружается как `warp_hybrid_legacy`;
- если ingress bundle отсутствует, allowlisted_ingress режим считается unavailable;
- данные WARP не должны ломаться при миграции.

## 11. Что нужно менять в control plane

### 11.1 Зачем нужен control plane

В strict allowlist клиент не может рассчитывать, что сам добудет и соберёт transport-конфиг в момент старта.

Поэтому control plane должен:

- поставлять ingress host и transport metadata заранее;
- обновлять policy-маршрутизацию независимо от выпуска APK;
- ротировать ingress configs без обновления приложения;
- поддерживать emergency disable и rollback.

### 11.2 Требования к control plane

- доставка конфигурации должна быть кэшируемой локально;
- конфигурация должна иметь TTL и versioning;
- клиент должен уметь использовать последнюю валидную конфигурацию офлайн;
- конфигурация должна быть подписана или иным образом проверяема;
- смена ingress host не должна требовать миграции пользовательских данных вручную.

### 11.3 Минимальный payload control plane

Payload v1 должен включать:

- список ingress endpoints;
- transport type и path policy;
- разрешённые Host/SNI значения;
- traffic policy classes;
- rollout flags;
- expiry;
- signature/checksum.

## 12. Что нужно менять в data plane

### 12.1 Отказ от обязательного WireGuard

Для allowlist-resilient режима внешний data plane должен перестать требовать WARP/WireGuard.

WARP допускается только как:

- временный legacy fallback;
- отдельный soft-censorship профиль;
- диагностический режим.

### 12.2 Новый набор транспортов

На первом этапе для allowlisted ingress должны поддерживаться только те транспорты, которые максимально похожи на обычный web-трафик и уже частично совместимы с текущим стеком.

Рекомендуемый порядок поддержки:

1. `ws`
2. `httpupgrade`
3. `grpc`
4. `h2`

Ограничения:

- QUIC-based transports не являются первичным выбором;
- Reality не является обязательной частью первой фазы;
- transport должен быть совместим с CDN/edge моделью.

### 12.3 TLS camouflage requirements

Новый transport должен поддерживать:

- валидный SNI на allowlisted edge host;
- корректный ALPN для выбранного типа transport;
- path/header model, совместимую с обычным веб-клиентом;
- возможность варьировать host/path без перепаковки всей архитектуры.

## 13. Что нужно менять в policy engine

### 13.1 Переход от port-aware к domain-aware policy

Текущий hybrid policy в основном основан на портах и грубом RU split.

Для allowlist-resilient режима нужен policy engine с приоритетами:

1. private/local ресурсы -> direct;
2. strict direct allowlist -> direct;
3. явный ingress allowlist -> ingress;
4. unknown HTTPS -> ingress, если включён policy flag;
5. unsupported UDP -> block;
6. всё прочее -> policy-defined fallback.

### 13.2 DNS policy

DNS в strict allowlist сценарии становится критически важным.

Требования:

- локальный DNS должен уметь стабильно отделять allowlisted direct domains от ingress-routed domains;
- private DNS hostname и локальная инфраструктура должны оставаться direct;
- нужна поддержка versioned DNS policy profiles;
- желательно добавить диагностический режим, который логирует причину policy classification.

### 13.3 Classification observability

Нужна диагностика вида:

- `policy_class=direct_private`
- `policy_class=direct_allowlisted`
- `policy_class=ingress_exact`
- `policy_class=ingress_unknown_https`
- `policy_class=blocked_udp`

Без такой телеметрии strict allowlist отлаживать практически невозможно.

## 14. Что нужно менять в UI/UX

### 14.1 Профили режима

UI должен перестать объяснять `hybrid` как конечную архитектурную цель.

Рекомендуемая эволюция:

- текущий `Гибридный` временно остаётся как legacy profile;
- появляется новый профиль или delivery option, например `Через разрешённый edge`;
- в настройках ясно указано, что `Гибридный` лучше для мягкой фильтрации, а новый ingress-вариант для белых списков.

### 14.2 Статусы запуска

Статусы должны различать:

- `подготавливаем legacy WARP`;
- `загружаем ingress bundle`;
- `проверяем allowlisted edge`;
- `запускаем ingress transport`.

### 14.3 Пользовательские ошибки

Нужны отдельные ошибки:

- ingress bundle missing;
- ingress bundle expired;
- allowlisted edge unreachable;
- transport rejected by policy;
- no compatible delivery mode for strict allowlist.

## 15. Что нужно менять в диагностике

### 15.1 Метрики

Минимальные KPI:

- DeliveryModeStartSuccessRate
- AllowlistedIngressReachabilityRate
- PolicyClassificationCoverage
- UnknownHttpsIngressSuccessRate
- DirectAllowedResourceSuccessRate
- ColdStartBootstrapSuccessRate
- FirstRunSuccessWithoutLiveProvisioning

### 15.2 Логи

Нужны новые лог-сигналы:

- выбранный delivery mode;
- версия ingress bundle;
- transport type и edge host;
- причина policy classification;
- trigger fallback/rollback;
- bootstrap source: cached vs refreshed.

### 15.3 Диагностические сценарии

Нужно уметь отдельно прогонять:

- strict allowlist emulation;
- edge host reachable, origin blocked;
- edge host reachable, transport fingerprint rejected;
- stale bundle startup;
- direct-only degradation mode.

## 16. Поэтапная миграция

## Phase 0. Stabilize current hybrid as legacy baseline

Цель:

- зафиксировать текущий `hybrid` как legacy-supported режим;
- не ломать текущих пользователей;
- подготовить почву для новой delivery abstraction.

Изменения:

- переименовать внутренне текущую стратегию в `warp_hybrid_legacy`;
- ввести feature flag для нового delivery layer;
- добавить telemetry по использованию legacy hybrid;
- отделить WARP-поля от будущих ingress-полей в модели.

Критерий выхода:

- legacy режим работает без регрессий;
- telemetry показывает baseline startup/success metrics.

## Phase 1. Introduce delivery abstraction without changing behavior

Цель:

- ввести архитектурный каркас без смены транспорта в production.

Изменения:

- добавить `DeblockerDeliveryMode`;
- добавить отдельный контейнер ingress metadata;
- добавить runtime bundle abstraction;
- научить provider и generator работать через delivery resolver;
- legacy hybrid временно маппится на новый abstraction layer без изменения поведения.

Критерий выхода:

- поведение пользователей не изменилось;
- код уже умеет выбирать delivery mode через единый runtime path.

## Phase 2. Add cached ingress bundle support

Цель:

- убрать зависимость от live provisioning как prerequisite для нового режима.

Изменения:

- ввести локальное хранение ingress runtime bundle;
- добавить versioning, TTL и checksum/signature;
- поддержать cold start from cache;
- добавить UI/telemetry для bundle freshness.

Критерий выхода:

- клиент может стартовать новый режим без онлайн-регистрации транспорта;
- при отсутствии сети используется последняя валидная конфигурация.

## Phase 3. Implement allowlisted ingress transport in generator

Цель:

- научить Deblocker строить внешний outbound не как WireGuard, а как allowlisted HTTPS ingress.

Изменения:

- добавить генерацию ingress outbounds для `ws`, `httpupgrade`, `grpc`, `h2`;
- добавить mapping edgeHost/hostHeader/path/SNI/ALPN;
- добавить transport validation layer;
- не включать это по умолчанию без feature flag.

Критерий выхода:

- конфиги успешно проходят preflight;
- transport стартует в controlled test scenario.

## Phase 4. Upgrade policy engine to domain-aware routing

Цель:

- перестать полагаться на правило “TCP 80/443 -> detour”.

Изменения:

- добавить domain-aware classification;
- добавить explicit allowlisted direct rules;
- добавить ingress routing rules по exact/suffix match;
- ввести fallback policy для unknown HTTPS;
- сохранить private/local/direct path.

Критерий выхода:

- policy rules воспроизводимы и диагностируемы;
- не происходит избыточной отправки трафика в ingress.

## Phase 5. Controlled rollout as opt-in strict-allowlist mode

Цель:

- запустить новый режим ограниченному числу пользователей и сетевых сценариев.

Изменения:

- UI: новый профиль или delivery toggle;
- rollout flags по конфигурации;
- fallback на legacy hybrid или direct-only degraded mode;
- сбор подробной телеметрии и логов.

Критерий выхода:

- подтверждена работа в реальных strict allowlist сетях;
- startup/success metrics не хуже ожидаемого целевого порога.

## Phase 6. Reposition legacy hybrid and converge UX

Цель:

- сделать allowlisted ingress основным рекомендованным режимом для белых списков.

Изменения:

- `Гибридный` маркируется как legacy или “для мягкой фильтрации”;
- allowlisted ingress становится primary recommendation для strict allowlist;
- документация и onboarding обновляются;
- WARP остаётся как optional fallback, а не как центральная ставка.

Критерий выхода:

- UX понятен;
- пользователи не путают legacy hybrid с allowlist-resilient режимом.

## 17. Технические изменения по слоям

### 17.1 lib/models

Нужно:

- добавить delivery abstraction enums и config objects;
- ввести versioned runtime bundle model;
- сохранить backward compatibility current hybrid settings.

### 17.2 lib/providers/tunnel_provider.dart

Нужно:

- вынести delivery selection в отдельный resolver;
- добавить bootstrap from cached bundle;
- разделить статусы legacy WARP и allowlisted ingress;
- поддержать migration flags и fallback ordering.

### 17.3 lib/config/singbox_config_generator.dart

Нужно:

- научить генератор строить allowlisted ingress outbound;
- отделить legacy warp generation от новой transport generation;
- добавить domain-aware route emission.

### 17.4 lib/services

Нужно:

- оставить CloudflareWarpService как legacy support path;
- добавить ingress bundle service;
- добавить validation service для transport compatibility;
- добавить signature/checksum verification service.

### 17.5 Android runtime

Нужно:

- при необходимости расширить diagnostics payload;
- не менять фундаментально VpnService/TUN lifecycle;
- сохранить совместимость с TLS tricks, если они остаются нужны.

## 18. Acceptance criteria

Решение считается соответствующим ТЗ, если выполняются все условия:

1. Новый режим запускается без live WARP-registration requirement.
2. Внешний transport не зависит от прямой доступности WireGuard endpoint.
3. Outbound выглядит как allowlisted HTTPS-совместимый трафик.
4. Policy engine отделяет direct ресурсы от ingress-routed ресурсов.
5. В случае отсутствия valid ingress bundle система деградирует предсказуемо.
6. Legacy hybrid продолжает работать на переходном этапе.
7. Есть телеметрия и логи, достаточные для расследования отказов.

## 19. Основные риски

### 19.1 Транспортный риск

Даже HTTPS-looking transport может быть недостаточен, если allowlist завязан на очень узкий набор hostnames или сложную behavioral fingerprinting политику.

### 19.2 Инфраструктурный риск

Allowlisted ingress потребует устойчивого edge/origin контура и ротации конфигурации, иначе клиентская часть не даст нужного эффекта.

### 19.3 Риск UX-сложности

Если оставить слишком много терминов вроде hybrid, ingress, edge, WARP, пользователю будет сложно понять, какой режим для какой страны и сценария нужен.

### 19.4 Риск регрессий policy

Неверная domain-aware policy может либо ломать доступ к разрешённым ресурсам, либо уводить слишком много трафика в обходной transport.

## 20. Open questions

1. Какие именно hostnames реально окажутся allowlisted в целевых странах и у операторов?
2. Нужен ли единый глобальный ingress host или несколько региональных профилей доставки?
3. Должен ли ingress bundle приходить из key-source pipeline или из отдельного control endpoint?
4. Какой transport из `ws/httpupgrade/grpc/h2` даёт лучший баланс между правдоподобием и стабильностью под целевой DPI?
5. Нужен ли отдельный режим “strict allowlist only”, который отключает legacy hybrid полностью?

## 21. Рекомендуемое решение по внедрению

Рекомендуется не пытаться эволюционировать текущий WARP hybrid в allowlist-resilient режим малыми правками route rules.

Правильный путь:

- оставить текущий hybrid как legacy fallback;
- ввести новый delivery layer;
- добавить cached ingress bundle;
- реализовать allowlisted HTTPS transport;
- перевести policy engine на domain-aware model;
- выкатывать новый режим отдельно и постепенно.

Это даст архитектурно чистую миграцию без ложного ожидания, что WireGuard/WARP можно дотянуть до строгого positive allowlist только настройками маршрутизации.
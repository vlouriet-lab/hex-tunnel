# Sing-box Feature Gap and Tunnel Stabilization Plan

Дата: 2026-04-03
Контекст: Hex Decensor (Flutter + Android VpnService + libbox/sing-box)

## 1) Что уже реализовано у нас

- Поддержка широкого набора протоколов и генерация outbounds из ключей (VLESS, SS, Trojan, TUIC, VMess, Hysteria(2), SSR, WireGuard/AWG, SOCKS, HTTP, SSH).
- TUN inbound с auto_route + strict_route + mixed stack.
- Route с hijack-dns, auto_detect_interface, override_android_vpn.
- Android-side split tunneling через VpnService.Builder.addAllowedApplication/addDisallowedApplication.
- Config preflight через Libbox.checkConfig до establish TUN.
- Runtime проверки доступности (post-connect), авто-фейловер, escalation cooldown по ключам.
- Silent fallback для xhttp -> ws на уровне провайдера.
- Источники ключей с retry и optional sha256 integrity check.

## 2) Возможности sing-box ядра, которые заложены, но у нас не задействованы

Ниже перечислены фичи, доступные в sing-box, но не включенные в нашей генерации конфигов.

### 2.1 Встроенный outbound-level failover/selection

- `urltest` outbound (встроенный периодический health-check группы outbounds, выбор лучшего по latency/tolerance).
- `selector` outbound (переключаемый набор outbounds, может быть связан с API-управлением).

Почему важно:
- Сейчас failover в основном вынесен в Dart-провайдер и опирается на pre-check/post-check.
- `urltest` может снизить время обнаружения деградации уже после установления сессии и уменьшить ручную логику reconnect-каруселей.

### 2.2 rule-set и более гибкая policy routing

- `route.rule_set` (удаленные/локальные наборы правил).
- Больше возможностей для сетевой стратегии в route (`default_network_strategy`, `default_fallback_delay`, и др.).

Почему важно:
- Сейчас routing в основном доменный/базовый (RU suffix + private/direct), а ключи могут быть «живыми», но не подходить под конкретные траектории трафика.
- Rule-set позволяет централизованно и быстрее корректировать policy без большого роста ручных if/else в коде.

### 2.3 DNS-подсистема: расширенные режимы

- `fakeip` режимы/настройки (опционально, где уместно).
- `client_subnet` для DNS-запросов.
- Более глубокий DNS cache control и расширенные policy DNS rules (в том числе с персистентным кэшем через experimental cache file).

Почему важно:
- У вас уже сильный DNS baseline, но проблемы «ключ подключился, а доменные резолвы нестабильны» показывают, что встроенная DNS-политика может быть расширена.

### 2.4 Experimental cache file

- `experimental.cache_file` (персистентное хранение selected/fakeip/rejected DNS cache и др. в поддерживаемых сценариях).

Почему важно:
- Может уменьшать «холодный старт» и кратковременные всплески отказов DNS/маршрутизации после рестартов.

### 2.5 NTP service

- Встроенный `ntp` сервис sing-box.

Почему важно:
- При дрейфе времени TLS/Reality/VMess-подключения могут нестабильно валиться даже на валидных ключах.

### 2.6 PlatformInterface функции, пока заглушены

- `findConnectionOwner` не реализован.
- `localDNSTransport` возвращает null.
- `readWIFIState` возвращает null.
- system proxy status фактически отключен.

Почему важно:
- Это не всегда критично для базового туннеля, но ухудшает качество диагностики и adaptive-поведения ядра на сложных устройствах/сетях.

## 3) Рекомендованный план стабилизации (с приоритетами)

## Phase A (быстрые выигрыши, 2-4 дня)

1. Внедрить `urltest` в генератор конфига для auto-режима ключей.
2. Добавить feature-flag: `enableCoreUrltest` (по умолчанию off, включать на диагностических сборках).
3. Переключить `route.final` на tag `auto` (urltest outbound) для auto-режима.
4. Оставить текущий Dart failover как safety net на период rollout.

Критерий успеха:
- Снижение доли `google_unreachable`/`gov_unreachable` после connected.
- Снижение среднего числа reconnect-циклов на сессию.

## Phase B (DNS hardening, 3-5 дней)

1. Добавить optional блок `experimental.cache_file` (feature-flag).
2. Добавить optional DNS profile presets:
   - baseline (текущий),
   - strict-public,
   - adaptive (с аккуратной настройкой cache/reverse mapping/client_subnet).
3. Ввести metrics-логирование причин DNS fail (resolve timeout/NXDOMAIN/TLS handshake error) в унифицированном формате.

Критерий успеха:
- Снижение UnknownHost/TIMEOUT после старта на одинаковом наборе ключей.
- Более предсказуемое время до первого успешного доменного запроса.

## Phase C (ключевая надежность, 4-7 дней)

1. Перейти от single-key connect к small pool (N=3..5) для auto-режима:
   - outbounds proxy-1..proxy-N,
   - urltest auto выбирает лучший,
   - Dart-провайдер только оркестрирует источник пула.
2. Нормализовать score-модель ключа:
   - отдельные веса для connect success, DNS success, app-probe success,
   - decay по времени, чтобы старые фейлы не «убивали» ключ навсегда.
3. Добавить «карантин источника» при массовых сбоях (не только карантин ключа).

Критерий успеха:
- Снижение процента полных отказов сессии.
- Стабильный success rate для 3+ последовательных ручных циклов на одном наборе источников.

## Phase D (диагностика/наблюдаемость, 2-3 дня)

1. Добавить session correlation id в Flutter/Kotlin/logcat/sing-box log.
2. Единый словарь error_code/stage для всех путей (preflight/start/runtime/post-connect/dns).
3. Автоматический post-mortem snapshot по триггерам (`start_failed`, `post_connect_check failed`, `dns timeout burst`).

Критерий успеха:
- Время анализа инцидента сокращается, root cause выявляется в 1 лог-снимок.

## 4) Что внедрять осторожно

- `selector` имеет смысл после/вместе с API control-потоком; сначала проще и полезнее `urltest`.
- `fakeip` и aggressive DNS policy включать только под feature-flag и A/B, иначе риск регрессий приложений.
- Любые расширения route/rule_set вводить постепенно, начиная с read-only диагностических профилей.

## 5) Минимальный набор KPI для контроля стабилизации

- TunnelStartSuccessRate = успешные connected / попытки start.
- PostConnectUsabilityRate = connected + успешный app-level probe.
- MedianTimeToUsableTunnel (P50/P95).
- DNSFailureRate (UnknownHost, timeout, SERVFAIL/NXDOMAIN split).
- KeyChurnPerSession = число переключений ключа за сессию.

## 6) Практический порядок внедрения в кодовой базе

1. `lib/config/singbox_config_generator.dart`:
   - feature-flagged генерация `urltest` outbound и переключение final.
   - feature-flagged `experimental.cache_file`.
2. `lib/providers/tunnel_provider.dart`:
   - оставить текущий failover как fallback path; добавить отдельный режим наблюдения за ядром.
3. `lib/services/singbox_service.dart` и Android bridge:
   - прокинуть дополнительные опции генерации через start payload.
4. `android/app/src/main/kotlin/com/sota/hexdecensor/`:
   - унифицировать telemetry полей ошибок/этапов.

## 7) Вывод

Сейчас у проекта уже хороший уровень защитной логики на уровне приложения, но часть встроенных механизмов отказоустойчивости sing-box не используется. Наиболее выгодный следующий шаг — добавить ядровой `urltest` (под флагом) и расширить DNS/cache-стабилизацию. Это позволит снизить количество ложных connected-состояний и уменьшить отказ ключей без чрезмерного усложнения Dart-оркестратора.

## Ссылки на документацию sing-box (использовано в анализе)

- https://sing-box.sagernet.org/configuration/outbound/urltest/
- https://sing-box.sagernet.org/configuration/outbound/selector/
- https://sing-box.sagernet.org/configuration/route/
- https://sing-box.sagernet.org/configuration/dns/
- https://sing-box.sagernet.org/configuration/experimental/cache-file/
- https://sing-box.sagernet.org/configuration/ntp/
- https://sing-box.sagernet.org/configuration/inbound/tun/

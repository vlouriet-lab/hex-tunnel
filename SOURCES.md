# VPN Key Sources Documentation

## Обновленные источники ключей для Hex Decensor

Приложение автоматически загружает VPN конфигурации из следующих основных и резервных источников.

---

## 📋 Основные источники

### 1. **igareck/vpn-configs-for-russia** (основной)
Репозиторий с наиболее актуальными русскими VPN конфигурациями.

| Файл | Тип | Описание |
|------|------|---------|
| `BLACK_VLESS_RUS.txt` | VLESS | Все VLESS конфиги для обхода блокировок |
| `BLACK_SS+All_RUS.txt` | SS/Trojan/TUIC | SS и прочие протоколы для обхода |
| `WHITE-CIDR-RU-all.txt` | CIDR | Маршруты только русского трафика |

**Обновление:** Автоматически
**Статус:** ✅ Основной источник

---

## 📦 Резервные источники (Fallback)

Загружаются автоматически, если основные источники недоступны.

### 2. **ebrasha/free-v2ray-public-list**
Большая коллекция бесплатных V2Ray конфигов. Обновляется каждые **15 минут**.

| Источник | Название | Описание |
|----------|----------|---------|
| `all_extracted_configs.txt` | ebrasha-all | Все протоколы (SS + SSR + Trojan + VLESS + VMess) |
| `V2Ray-Config-By-EbraSha.txt` | ebrasha-lite | Облегченная версия (меньше конфигов) |
| `vless_configs.txt` | ebrasha-vless | Только VLESS конфиги |
| `vmess_configs.txt` | ebrasha-vmess | Только VMess конфиги |
| `ss_configs.txt` | ebrasha-ss | Только Shadowsocks конфиги |
| `trojan_configs.txt` | ebrasha-trojan | Только Trojan конфиги |

**Статистика:** ~500-1000 конфигов в каждом файле
**Протоколы:** SS, SSR, Trojan, VLESS, VMess
**Обновление:** Каждые 15 минут

---

### 3. **kort0881/vpn-vless-configs-russia**
Коллекция VLESS/VMess конфигов с фокусом на Россию и СНГ. Обновляется каждые **15 минут**.

| Источник | Название | Статистика | Описание |
|----------|----------|-----------|---------|
| `githubmirror/clean/vless.txt` | kort-clean-vless | 1247 конфигов | Валидированные VLESS |
| `githubmirror/clean/vmess.txt` | kort-clean-vmess | 892 конфигов | Валидированные VMess |
| `githubmirror/clean/ss.txt` | kort-clean-ss | 312 конфигов | Валидированные SS |
| `githubmirror/clean/trojan.txt` | kort-clean-trojan | 534 конфигов | Валидированные Trojan |
| `githubmirror/ru-sni/vless_ru.txt` | kort-ru-vless | 342 конфигов | Только RU серверы (VLESS) |
| `githubmirror/ru-sni/vmess_ru.txt` | kort-ru-vmess | 198 конфигов | Только RU серверы (VMess) |
| `subscriptions/sni_filtered.txt` | kort-sni-filtered | N/A | Отфильтрованные по SNI |
| `githubmirror/ru-sni-local/vless.txt` | kort-ru-sni-local | N/A | Локальные RU маршруты (белый список) |

**Особенность:** Все конфиги проходят валидацию и фильтрацию
**Обновление:** Каждые 15 минут

---

### 4. **AvenCores/goida-vpn-configs**
Мегаагрегатор конфигов, собирающий из 26+ источников. Обновляется каждые **9 минут**.

Используются следующие файлы агрегатора:

| Файл | Название | Описание |
|------|----------|---------|
| `githubmirror/1.txt` | goida-1 | Источник 1 (sakha1370/OpenRay) |
| `githubmirror/2.txt` | goida-2 | Источник 2 (sevcator/5ubscrpt10n) |
| `githubmirror/3.txt` | goida-3 | Источник 3 (yitong2333/proxy-mining) |
| `githubmirror/4.txt` | goida-4 | Источник 4 (acymz/AutoVPN) |
| `githubmirror/5.txt` | goida-5 | Источник 5 (miladtahanian/V2RayCFGDumper) |
| `githubmirror/6.txt` | goida-6 | Источник 6 (roosterkid/openproxylist) |
| `githubmirror/7.txt` | goida-7 | Источник 7 (Epodonios/v2ray-configs) |
| `githubmirror/10.txt` | goida-10 | Источник 10 (youfoundamin/V2rayCollector) |
| `githubmirror/12.txt` | goida-12 | Источник 12 (expressalaki/ExpressVPN) |
| `githubmirror/15.txt` | goida-15 | Источник 15 (miladtahanian/Config-Collector) |
| `githubmirror/19.txt` | goida-19 | Источник 19 (MhdiTaheri/V2rayCollector) |
| `githubmirror/23.txt` | goida-23 | Источник 23 (WhitePrime/xraycheck) |
| `githubmirror/24.txt` | goida-24 | Источник 24 (STR97/STRUGOV) |
| `githubmirror/25.txt` | goida-25 | Источник 25 (V2RayRoot/V2RayConfig) |

**Статистика:** 2985+ валидных конфигов в сумме
**Обновление:** Каждые 9 минут

---

## 🔄 Порядок загрузки

1. **Основные источники (igareck)** → 3 файла (VLESS, SS/Trojan, White List)
2. **Резервные источники** (если основные недоступны):
   - ebrasha (6 источников)
   - kort0881 (8 источников)
   - AvenCores (14 источников)

**Всего 31 резервный источник** = гарантированная доступность

---

## ⚡ Преимущества такой архитектуры

✅ **Надёжность:** Если один источник недоступен, подключаются другие  
✅ **Скорость:** Всегда есть свежие конфиги (обновление каждые 9-15 минут)  
✅ **Выбор протоколов:** SS, SSR, Trojan, VLESS, VMess  
✅ **Деревни фильтрации:** Отдельные источники для RU и локальных маршрутов  
✅ **Дедупликация:** Приложение исключает дубликаты конфигов  
✅ **Валидация:** Все конфиги проверяются на синтаксис перед использованием  

---

## 🛡️ Безопасность

- Все источники берутся только с **raw.githubusercontent.com** (HTTPS)
- URL проверяются на доверие (whitelist hosts)
- Размер ответов ограничен (5 МБ)
- Стройки ограничены (120k строк, 8KB на строку)
- Опциональная проверка целостности по SHA256 (graceful skip если отсутствует)

---

## 📊 Статистика резервных источников (на 24.03.2026)

```
ebrasha (6 источников):
  - all_extracted_configs.txt: ~1000+ конфигов
  - V2Ray-Config-By-EbraSha.txt: ~500+ конфигов
  - Отдельные файлы по протоколам: 200-500 конфигов каждый

kort0881 (8 источников):
  - Валидированные конфиги: 3985 всего
    - VLESS: 1247
    - VMess: 892
    - Trojan: 534
    - SS: 312

AvenCores (14 источников):
  - Общая статистика: 2985+ конфигов
  - Обновление каждые 9 минут
  - 26 разных источников (берутся лучшие 14)
```

---

## 🔧 Настройка новых источников

Для добавления новых источников отредактируйте `lib/services/key_loader_service.dart`:

```dart
static const _fallbackSources = <_KeySource>[
  _KeySource(
    'unique-name',  // Уникальное имя источника
    'https://raw.githubusercontent.com/owner/repo/main/file.txt',  // URL
    KeyListType.blackList,  // или .whiteList
  ),
  // ...
];
```

---

## ⚠️ Важно

Все файлы должны содержать по одному конфигу на строку в формате:
- `ss://...`
- `ssr://...`
- `trojan://...`
- `vless://...`
- `vmess://...`

Строки начиная с `#` — комментарии (игнорируются)  
Пустые строки — игнорируются  

---

**Последнее обновление:** 24 марта 2026 г.  
**Версия:** 2.0 (31 источник вместо 2)

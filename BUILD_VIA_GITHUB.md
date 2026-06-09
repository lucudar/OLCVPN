# Сборка без Mac — через GitHub Actions

Цель: получить подписанный `.ipa` без собственного компьютера Apple.
GitHub даёт бесплатные macOS-раннеры — они соберут Go-ядро, C-движок, Xcode-проект и подпишут итог.

Всё ниже делается с телефона/обычного ПК (Windows/Linux) + веб-портал Apple. Mac не нужен.

---

## Шаг 0. Что понадобится
- Платный Apple Developer аккаунт ($99/год). Бесплатный не даёт NetworkExtension (VPN).
- UDID твоего iPhone (узнаётся на udid.tech или в настройках через Apple Configurator/iTunes).
- Аккаунт GitHub.
- `openssl` (есть в Linux/macOS; на Windows — Git Bash или WSL).

---

## Шаг 1. Создать сертификат без Mac (CSR через openssl)

```bash
# 1) приватный ключ + запрос на сертификат
openssl req -new -newkey rsa:2048 -nodes \
  -keyout ios.key -out ios.csr \
  -subj "/emailAddress=твой@email/CN=OLCVPN/C=RU"
```

2) На https://developer.apple.com/account/resources/certificates → **+** →
   выбери **Apple Development** (или iOS App Development) → загрузи `ios.csr` →
   скачай `ios_development.cer`.

3) Собери `.p12` (это формат, который нужен CI):
```bash
openssl x509 -in ios_development.cer -inform DER -out ios.pem -outform PEM
openssl pkcs12 -export -inkey ios.key -in ios.pem -out ios.p12 -passout pass:MyPass123
```
Запомни пароль (`MyPass123`).

---

## Шаг 2. App IDs, устройство и профили (всё на сайте Apple)

1. **Identifiers** → создай два App ID:
   - `com.you.olcvpn` — включи **App Groups** и **Network Extensions**.
   - `com.you.olcvpn.OLCTunnel` — тоже App Groups + Network Extensions.
   - (или замени `com.you` на свой префикс — тогда поправь `project.yml`).
2. **Devices** → добавь UDID своего iPhone.
3. **Profiles** → создай два **iOS App Development** профиля:
   - для `com.you.olcvpn` → назови **OLCVPN App Profile**
   - для `com.you.olcvpn.OLCTunnel` → назови **OLCVPN Tunnel Profile**
   - оба привяжи к своему сертификату и устройству; скачай `.mobileprovision`.

Имена профилей должны совпадать с тем, что в `ExportOptions.plist`.

---

## Шаг 3. Правки в проекте
- `ExportOptions.plist` → впиши свой `teamID` (10 символов).
- `project.yml` → `DEVELOPER_TEAM` = тот же Team ID; и bundle id, если менял.

---

## Шаг 4. Залить проект на GitHub
```bash
cd OLCVPN
git init && git add . && git commit -m "OLCVPN"
git branch -M main
git remote add origin https://github.com/<ты>/OLCVPN.git
git push -u origin main
```
Сделай репозиторий **приватным** (внутри будут секреты подписи).

---

## Шаг 5. Добавить секреты
GitHub → репозиторий → **Settings → Secrets and variables → Actions → New repository secret**.

Создай 4 секрета (значения — base64):
```bash
base64 -w0 ios.p12                       # -> CERT_P12_BASE64
echo -n 'MyPass123'                      # -> CERT_PASSWORD (пароль от p12)
base64 -w0 OLCVPN_App_Profile.mobileprovision     # -> PROFILE_APP_BASE64
base64 -w0 OLCVPN_Tunnel_Profile.mobileprovision  # -> PROFILE_EXT_BASE64
```
(на macOS/BSD base64 без `-w0`: `base64 -i ios.p12`)

| Имя секрета | Что класть |
|---|---|
| `CERT_P12_BASE64` | base64 от `ios.p12` |
| `CERT_PASSWORD` | пароль от p12 |
| `PROFILE_APP_BASE64` | base64 от профиля приложения |
| `PROFILE_EXT_BASE64` | base64 от профиля расширения |

---

## Шаг 6. Запустить сборку
GitHub → вкладка **Actions** → выбери *iOS Build* → **Run workflow**.
Через ~10–20 минут в разделе **Artifacts** появится `OLCVPN-ipa` — скачай `.ipa`.

---

## Шаг 7. Установить .ipa на iPhone без Mac
Любой из вариантов (итак уже подписано твоим профилем + UDID):
- **Diawi / InstallOnAir**: загрузи `.ipa` → открой ссылку на iPhone → установка по воздуху (OTA). Проще всего.
- **Sideloadly / AltStore** (на Windows/Linux): установка через USB.
- **Apple Configurator** (только Mac — не твой случай).

После установки: Settings → General → VPN & Device Management → доверь своему разраб-профилю.

---

## Частые грабли
- **Профиль не совпадает по имени** → имя в `ExportOptions.plist` должно быть ровно как на портале.
- **"No profiles for ... were found"** → забыл включить App Groups/Network Extensions в App ID, либо UDID не в профиле.
- **gomobile префикс** → см. примечание в README про `OLCCore.swift`.
- **App Store это не пропустит** — но для личной установки по development-профилю всё работает.

# Сборка БЕЗ подписи (unsigned .ipa) через GitHub Actions

Цель: получить `.ipa` **без сертификатов и профилей Apple**. Подпись ты сделаешь сам
на телефоне/ПК (AltStore, Sideloadly, ESign и т.п.).

Mac не нужен — сборку делает бесплатный macOS-раннер GitHub.

---

## Шаги

### 1. Залить проект на GitHub
```bash
cd OLCVPN          # папка с project.yml, build.sh, .github/
git init
git add .
git commit -m "OLCVPN unsigned"
git branch -M main
git remote add origin https://github.com/<твой-ник>/OLCVPN.git
git push -u origin main
```

### 2. Запустить сборку
GitHub → вкладка **Actions** → workflow **"iOS Build (Unsigned)"** → **Run workflow**.
(Также запускается автоматически при каждом push в `main`.)

Через ~10–20 мин в разделе **Artifacts** появится `OLCVPN-unsigned-ipa` — скачай.
Внутри лежит `OLCVPN-unsigned.ipa` (без подписи).

### 3. Подписать на телефоне/ПК
Любым удобным инструментом:
- **AltStore / SideStore** — подпись бесплатным Apple ID прямо с iPhone.
- **Sideloadly** (Windows/macOS) — подпись + установка по USB.
- **ESign / Feather** — подпись своим сертификатом/профилем на устройстве.

После установки: Settings → General → VPN & Device Management → доверь профилю.

---

## Что делает unsigned-workflow
`.github/workflows/ios-unsigned.yml`:
1. ставит Go + xcodegen, клонирует ядро olcRTC;
2. `build.sh` собирает `Olcrtc.xcframework` и `hev-socks5-tunnel`, генерирует Xcode-проект;
3. `xcodebuild archive` с флагами `CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO` — без подписи;
4. упаковывает `.app` в `Payload/…` → `OLCVPN-unsigned.ipa`;
5. кладёт его в артефакты.

---

## Важные нюансы
- **VPN/Network Extension требует платный Apple Developer ($99/год).** При подписи
  **бесплатным** Apple ID (AltStore) iOS почти наверняка НЕ даст entitlement
  `packet-tunnel-provider`, и VPN-туннель не поднимется (само приложение запустится).
  Для рабочего VPN нужен платный аккаунт и профиль с Network Extensions —
  тогда смотри подписанный путь в `BUILD_VIA_GITHUB.md`.
- При самоподписи через инструмент часто нужно поменять **bundle id** на свой
  (по умолчанию `com.you.olcvpn` и `com.you.olcvpn.OLCTunnel`).
- App Store такой сборкой не пройдёт — только личная установка.

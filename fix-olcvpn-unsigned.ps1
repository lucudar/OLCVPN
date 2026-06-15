# fix-olcvpn-unsigned.ps1  -- run from the root of the OLCVPN repo
$ErrorActionPreference = 'Stop'

$wfDir = Join-Path (Get-Location) ".github\workflows"
if (-not (Test-Path $wfDir)) { throw "No .github\workflows here. Run from the OLCVPN repo root." }

# the unsigned workflow is the only one containing OLCVPN-unsigned
$target = Get-ChildItem $wfDir -Recurse -Include *.yml,*.yaml -File |
    Where-Object { (Get-Content $_.FullName -Raw) -match 'OLCVPN-unsigned' } |
    Select-Object -First 1
if (-not $target) { throw "Unsigned workflow not found (no OLCVPN-unsigned) in $wfDir." }

Copy-Item $target.FullName "$($target.FullName).bak" -Force

$yaml = @'
name: iOS Build (Unsigned)

# Builds an UNSIGNED .ipa - sign it yourself (AltStore / Sideloadly / ESign).
on:
  workflow_dispatch:
  push:
    branches: [ main ]

permissions:
  contents: write

jobs:
  build:
    runs-on: macos-15
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Setup Go
        uses: actions/setup-go@v5
        with:
          go-version: '1.22'

      - name: Install tools
        run: brew install xcodegen

      - name: Clone olcRTC core
        run: git clone --depth 1 https://github.com/openlibrecommunity/olcrtc.git "$RUNNER_TEMP/olcrtc"

      - name: Patch olcRTC (keepalive without RTX)
        run: |
          F="$RUNNER_TEMP/olcrtc/internal/engine/jitsi/jitsi.go"
          perl -0777 -i -pe 's/api := webrtc\.NewAPI\(\s*webrtc\.WithSettingEngine\(settings\),\s*webrtc\.WithInterceptorRegistry\(registry\),\s*\)/mediaEngine := \&webrtc.MediaEngine{}\n\tif err := mediaEngine.RegisterCodec(webrtc.RTPCodecParameters{RTPCodecCapability: webrtc.RTPCodecCapability{MimeType: webrtc.MimeTypeOpus, ClockRate: 48000, Channels: 2, SDPFmtpLine: "minptime=10;useinbandfec=1"}, PayloadType: 111}, webrtc.RTPCodecTypeAudio); err != nil {\n\t\treturn fmt.Errorf("register opus: %w", err)\n\t}\n\tif err := mediaEngine.RegisterCodec(webrtc.RTPCodecParameters{RTPCodecCapability: webrtc.RTPCodecCapability{MimeType: webrtc.MimeTypeVP8, ClockRate: 90000}, PayloadType: 100}, webrtc.RTPCodecTypeVideo); err != nil {\n\t\treturn fmt.Errorf("register vp8: %w", err)\n\t}\n\tapi := webrtc.NewAPI(webrtc.WithMediaEngine(mediaEngine), webrtc.WithSettingEngine(settings), webrtc.WithInterceptorRegistry(registry))/s' "$F"
          gofmt -w "$F"
          grep -q 'WithMediaEngine(mediaEngine)' "$F" && echo "PATCH OK: media engine without rtx" || { echo "PATCH FAILED: anchor not found"; exit 1; }

      - name: Build frameworks + generate Xcode project
        run: |
          chmod +x build.sh
          ./build.sh "$RUNNER_TEMP/olcrtc"

      - name: Archive (no code signing)
        run: |
          xcodebuild -project OLCVPN.xcodeproj \
            -scheme OLCVPN \
            -configuration Release \
            -sdk iphoneos \
            -archivePath "$RUNNER_TEMP/OLCVPN.xcarchive" \
            CODE_SIGN_STYLE=Manual \
            CODE_SIGN_IDENTITY="" \
            CODE_SIGNING_REQUIRED=NO \
            CODE_SIGNING_ALLOWED=NO \
            DEVELOPMENT_TEAM="" \
            archive

      - name: Package unsigned .ipa
        run: |
          APP_DIR="$RUNNER_TEMP/OLCVPN.xcarchive/Products/Applications"
          if [ ! -d "$APP_DIR" ]; then
            echo "::error::Applications folder not found in archive"; exit 1
          fi
          rm -rf "$GITHUB_WORKSPACE/export"
          mkdir -p "$GITHUB_WORKSPACE/export"
          WORKDIR="$RUNNER_TEMP/payload"
          rm -rf "$WORKDIR" && mkdir -p "$WORKDIR/Payload"
          cp -R "$APP_DIR"/*.app "$WORKDIR/Payload/"
          ( cd "$WORKDIR" && zip -qry "$GITHUB_WORKSPACE/export/OLCVPN-unsigned.ipa" Payload )
          echo "Built:"; ls -la "$GITHUB_WORKSPACE/export"

      - name: Publish .ipa to GitHub Release
        uses: softprops/action-gh-release@v2
        with:
          tag_name: unsigned
          name: OLCVPN (unsigned)
          body: Unsigned OLCVPN .ipa. Sign it yourself (AltStore / Sideloadly / ESign).
          files: export/OLCVPN-unsigned.ipa
'@

$yaml = $yaml -replace "`r`n", "`n"   # LF endings
[System.IO.File]::WriteAllText($target.FullName, $yaml, (New-Object System.Text.UTF8Encoding($false)))  # UTF-8 no BOM

Write-Host ("OK -> " + $target.FullName)
Write-Host ("Backup -> " + $target.FullName + ".bak")
Write-Host ""
Write-Host "Next:"
Write-Host "  git add ."
Write-Host "  git commit -m ""ci: keepalive without rtx (clean datachannel)"""
Write-Host "  git push"
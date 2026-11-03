#!/bin/zsh
# Shoji のビルド
#   ./build.sh            build/Shoji.app を作る
#   ./build.sh run        作ってそのまま起動する
#   ./build.sh install    /Applications にインストールして起動する
#
# 環境変数
#   SIGN_IDENTITY   署名に使う証明書（未指定なら Apple Development、なければアドホック署名）
#   ARCHS           "arm64" または "arm64 x86_64"（既定は arm64）
#   VERSION / BUILD Info.plist のバージョンを上書きする（リリース時に使う）
set -euo pipefail
cd "$(dirname "$0")"

APP="build/Shoji.app"
ARCHS="${ARCHS:-arm64}"
arch_flags=()
for a in ${=ARCHS}; do arch_flags+=(--arch "$a"); done

swift build -c release "${arch_flags[@]}"
BIN="$(swift build -c release "${arch_flags[@]}" --show-bin-path)"

# 各機能のリポジトリの場所（開発時は隣のフォルダ、それ以外は SwiftPM が取得したもの）
feature_dir() { [[ -f "../$1/Package.swift" ]] && echo "../$1" || echo ".build/checkouts/$1"; }

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$BIN/Shoji" "$APP/Contents/MacOS/Shoji"
ditto "$BIN/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"
cp Resources/Info.plist "$APP/Contents/Info.plist"
mkdir -p "$APP/Contents/Resources"
cp THIRD_PARTY_NOTICES.md LICENSE "$APP/Contents/Resources/"
# ログイン時に起動する launchd のエージェント（異常終了したら起動し直す）
mkdir -p "$APP/Contents/Library/LaunchAgents"
cp Resources/com.ryuto.Shoji.agent.plist "$APP/Contents/Library/LaunchAgents/"
# 外観で背景色が切り替わるアイコン（Assets.car と、古い表示用の AppIcon.icns ができる）
xcrun actool Resources/AppIcon.icon --compile "$APP/Contents/Resources" --platform macosx \
  --minimum-deployment-target 26.0 --app-icon AppIcon --output-partial-info-plist /dev/null >/dev/null
ditto Resources/ja.lproj "$APP/Contents/Resources/ja.lproj"

# 各機能の文言。Localizable.strings 同士がぶつからないよう、機能名のテーブルとして入れる
for lang in en ja; do
  mkdir -p "$APP/Contents/Resources/$lang.lproj"
  for f in GlassDock ShelfTabs; do
    cp "$(feature_dir $f)/Resources/$lang.lproj/Localizable.strings" "$APP/Contents/Resources/$lang.lproj/$f.strings"
  done
done

PLIST="$APP/Contents/Info.plist"
[[ -n "${VERSION:-}" ]] && /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$PLIST"
# Sparkle は CFBundleVersion で新旧を比べるため、手元のビルドも日時にして公開版より古く見えないようにする
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${BUILD:-$(date +%Y%m%d%H%M)}" "$PLIST"

# アップデート検証用の公開鍵（秘密ではない）。各機能の単体アプリと同じ鍵を使う
if [[ -s Resources/sparkle-public-key.txt ]]; then
  /usr/libexec/PlistBuddy -c "Add :SUPublicEDKey string $(tr -d '[:space:]' < Resources/sparkle-public-key.txt)" "$PLIST"
else
  echo "warning: Resources/sparkle-public-key.txt がないため、このビルドでは自動アップデートが無効です" >&2
fi

# 開発用証明書で署名すると、再ビルドしても権限が維持される
IDENTITY="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning | awk -F'"' '/Apple Development/ {print $2; exit}')}"
IDENTITY="${IDENTITY:--}"

# Sparkle の中身は内側から順に署名する（--deep は使わない）。サンドボックスを使わないため XPC サービスは外す
TIMESTAMP="--timestamp=none"
[[ "$IDENTITY" == *"Developer ID"* ]] && TIMESTAMP="--timestamp"
sign() { codesign --force "$TIMESTAMP" --options runtime --sign "$IDENTITY" "$@"; }
FW="$APP/Contents/Frameworks/Sparkle.framework"
rm -rf "$FW/Versions/B/XPCServices" "$FW/XPCServices"
sign "$FW/Versions/B/Autoupdate"
sign "$FW/Versions/B/Updater.app"
sign "$FW"
sign --entitlements Resources/Shoji.entitlements "$APP"
codesign --verify --strict "$APP"
echo "Built $APP ($(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST"), signed: ${IDENTITY/-/ad-hoc})"

case "${1:-}" in
  run)
    pkill -x Shoji || true
    sleep 0.5
    open "$APP"
    ;;
  install)
    pkill -x Shoji || true
    sleep 1
    rm -rf /Applications/Shoji.app
    ditto "$APP" /Applications/Shoji.app
    open /Applications/Shoji.app
    echo "Installed /Applications/Shoji.app"
    ;;
esac

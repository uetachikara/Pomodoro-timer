#!/bin/bash
#
# Pomoblock.app を組み立てるスクリプト。
# SwiftPM で実行ファイルをビルドし、.app バンドルの形に並べ直す。
#
set -euo pipefail

APP_NAME="Pomoblock"
BUNDLE_ID="jp.havas.pomoblock"
GUARD_LABEL="jp.havas.pomoblock.guard"
AGENT_LABEL="jp.havas.pomoblock.agent"
# macOS の最低要件。MenuBarExtra の window スタイルに必要。
MINIMUM_SYSTEM_VERSION="14.0"

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST_DIR="$PROJECT_ROOT/dist"
APP_DIR="$DIST_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"

cd "$PROJECT_ROOT"

echo "==> Swift パッケージをビルド"
swift build -c release

BINARY_PATH="$(swift build -c release --show-bin-path)/$APP_NAME"
if [ ! -f "$BINARY_PATH" ]; then
    echo "実行ファイルが見つからない: $BINARY_PATH" >&2
    exit 1
fi

# 自動起動が登録されていると KeepAlive が再起動を繰り返し、
# 差し替え中のバンドルを掴んでしまう。一旦止めて最後に入れ直す。
AGENT_PLIST="$HOME/Library/LaunchAgents/$AGENT_LABEL.plist"
AGENT_WAS_LOADED=0
if [ -f "$AGENT_PLIST" ]; then
    echo "==> 自動起動を一時停止"
    launchctl bootout "gui/$(id -u)/$AGENT_LABEL" 2>/dev/null || true
    AGENT_WAS_LOADED=1
fi

echo "==> .app バンドルを組み立て"
rm -rf "$APP_DIR"
mkdir -p "$CONTENTS_DIR/MacOS" "$CONTENTS_DIR/Resources"

cp "$BINARY_PATH" "$CONTENTS_DIR/MacOS/$APP_NAME"

# 常駐ガードの実体をバンドルへ同梱する。導入時にここから /usr/local/libexec へ複製する。
cp "$PROJECT_ROOT/Resources/pomoblock-guard.sh" "$CONTENTS_DIR/Resources/"
cp "$PROJECT_ROOT/Resources/$GUARD_LABEL.plist" "$CONTENTS_DIR/Resources/"

cat > "$CONTENTS_DIR/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>$APP_NAME</string>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>$MINIMUM_SYSTEM_VERSION</string>
    <!-- Dock とアプリ切り替えに出さず、メニューバーだけに常駐させる -->
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <!-- 遮断開始時に、開いたままのタブを再読み込みするために必要 -->
    <key>NSAppleEventsUsageDescription</key>
    <string>ブロック開始時に、対象サイトを開いているタブを再読み込みします。</string>
</dict>
</plist>
PLIST

# ad-hoc 署名。通知の許可要求や launchd との連携を安定させるため。
echo "==> ad-hoc 署名"
codesign --force --sign - --timestamp=none "$APP_DIR"

if [ "$AGENT_WAS_LOADED" -eq 1 ]; then
    echo "==> 自動起動を再開"
    launchctl bootstrap "gui/$(id -u)" "$AGENT_PLIST" 2>/dev/null || true
fi

echo "==> 完成: $APP_DIR"

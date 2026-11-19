#!/bin/bash
# winsteam 安裝腳本
#   curl -fsSL https://raw.githubusercontent.com/a8594755-maker/winsteam/main/install.sh | bash
# 做三件事：把 winsteam 下載到 ~/.winsteam、在 PATH 上放一個連結、
# 再把圖形介面 WinSteam.app 放到 ~/Applications（抓不到就略過）。
# 不需要 sudo，也不會安裝 Rosetta、Wine 或 Steam（那是 winsteam setup 的事）。
#
# 可用的環境變數：
#   WINSTEAM_NO_APP=1     不安裝圖形介面
#   WINSTEAM_HOME         命令列工具的安裝位置（預設 ~/.winsteam）
#   WINSTEAM_APP_DIR      圖形介面的安裝位置（預設 ~/Applications）
#   WINSTEAM_REPO / WINSTEAM_BRANCH   改從別的儲存庫或分支安裝
set -euo pipefail

REPO="${WINSTEAM_REPO:-a8594755-maker/winsteam}"
BRANCH="${WINSTEAM_BRANCH:-main}"
DEST="${WINSTEAM_HOME:-$HOME/.winsteam}"
APP_DIR="${WINSTEAM_APP_DIR:-$HOME/Applications}"

say()  { printf '%s\n' "$*"; }
fail() { printf '✗ %s\n' "$*" >&2; exit 1; }

[ "$(uname -s)" = Darwin ] || fail "winsteam 只支援 macOS。"
[ "$(uname -m)" = arm64 ]  || fail "winsteam 只支援 Apple Silicon 的 Mac。"

case "$DEST" in
  "$HOME"/*) ;;
  *) fail "WINSTEAM_HOME 必須在家目錄底下：$DEST" ;;
esac
case "$APP_DIR" in
  "$HOME"/*) ;;
  *) fail "WINSTEAM_APP_DIR 必須在家目錄底下：$APP_DIR" ;;
esac

say "下載 winsteam（$REPO@${BRANCH}）…"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
curl -fsSL "https://github.com/$REPO/archive/refs/heads/$BRANCH.tar.gz" -o "$tmp/src.tar.gz" \
  || fail "下載失敗。請確認儲存庫 $REPO 存在且是公開的。"
mkdir "$tmp/src"
tar -xzf "$tmp/src.tar.gz" -C "$tmp/src" --strip-components 1
[ -f "$tmp/src/bin/winsteam" ] || fail "下載的內容不完整（找不到 bin/winsteam）。"

# 只替換自己的檔案，不碰使用者可能放在 ~/.winsteam 的其他東西。
mkdir -p "$DEST"
rm -rf "$DEST/bin" "$DEST/profiles"
cp -R "$tmp/src/bin" "$tmp/src/profiles" "$DEST/"
[ -f "$tmp/src/README.md" ] && cp "$tmp/src/README.md" "$DEST/"
chmod +x "$DEST/bin/winsteam"

# 找一個不需要 sudo 就能寫入的 PATH 目錄。
bindir=""
if command -v brew >/dev/null 2>&1 && [ -w "$(brew --prefix)/bin" ]; then
  bindir="$(brew --prefix)/bin"
else
  bindir="$HOME/.local/bin"
  mkdir -p "$bindir"
fi
ln -sf "$DEST/bin/winsteam" "$bindir/winsteam"

say "✓ 已安裝到 $DEST"
say "✓ 指令連結：$bindir/winsteam"
case ":$PATH:" in
  *":$bindir:"*) ;;
  *) say "! $bindir 不在你的 PATH 裡。把這行加到 ~/.zshrc 後重開終端機："
     say "    export PATH=\"$bindir:\$PATH\"" ;;
esac

# ── 圖形介面 ─────────────────────────────────────────────────────────────
# 從 GitHub Releases 抓編好的 WinSteam.app。用 curl 下載的檔案不會被 macOS 標上
# 隔離標記，所以這個只有 ad-hoc 簽章的 App 可以直接打開。
# 回傳：0 成功、1 抓不到、2 檢查碼不符、3 內容不對或簽章驗證失敗。
install_app() {
  local base="https://github.com/$REPO/releases/latest/download" want got
  curl -fsSL "$base/WinSteam.zip" -o "$tmp/WinSteam.zip" 2>/dev/null || return 1
  curl -fsSL "$base/WinSteam.zip.sha256" -o "$tmp/WinSteam.zip.sha256" 2>/dev/null || return 1
  want="$(awk '{print $1; exit}' "$tmp/WinSteam.zip.sha256")"
  got="$(shasum -a 256 "$tmp/WinSteam.zip" | awk '{print $1}')"
  if [ -z "$want" ] || [ "$want" != "$got" ]; then return 2; fi
  mkdir "$tmp/app"
  ditto -x -k "$tmp/WinSteam.zip" "$tmp/app" 2>/dev/null || return 3
  [ -x "$tmp/app/WinSteam.app/Contents/MacOS/WinSteam" ] || return 3
  codesign --verify --deep --strict "$tmp/app/WinSteam.app" 2>/dev/null || return 3
  mkdir -p "$APP_DIR"
  rm -rf "$APP_DIR/WinSteam.app"
  mv "$tmp/app/WinSteam.app" "$APP_DIR/WinSteam.app"
}

app_ok=0
if [ "${WINSTEAM_NO_APP:-}" = 1 ]; then
  :
else
  rc=0
  install_app || rc=$?
  case "$rc" in
    0) app_ok=1; say "✓ 圖形介面：$APP_DIR/WinSteam.app" ;;
    1) say "! 沒有抓到圖形介面（可能還沒有發佈版本，或網路有問題）。命令列工具不受影響。" ;;
    2) say "! 圖形介面的檢查碼不符，已略過不安裝。命令列工具不受影響。" ;;
    *) say "! 下載到的圖形介面內容不正確，已略過不安裝。命令列工具不受影響。" ;;
  esac
fi

say ""
say "接下來："
if [ "$app_ok" = 1 ]; then
  say "  打開 WinSteam（在「應用程式」資料夾，或執行下面這行）按「安裝」："
  say "    open \"$APP_DIR/WinSteam.app\""
  say "  或用命令列：winsteam setup"
else
  say "  winsteam doctor   檢查這台 Mac"
  say "  winsteam setup    開始安裝"
fi

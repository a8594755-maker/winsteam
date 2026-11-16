#!/bin/bash
# winsteam 安裝腳本
#   curl -fsSL https://raw.githubusercontent.com/<擁有者>/<儲存庫>/main/install.sh | bash
# 只做兩件事：把 winsteam 下載到 ~/.winsteam，並在 PATH 上放一個連結。
# 不需要 sudo，也不會安裝 Rosetta、Wine 或 Steam（那是 winsteam setup 的事）。
set -euo pipefail

REPO="${WINSTEAM_REPO:-a8594755-maker/winsteam}"
BRANCH="${WINSTEAM_BRANCH:-main}"
DEST="${WINSTEAM_HOME:-$HOME/.winsteam}"

say()  { printf '%s\n' "$*"; }
fail() { printf '✗ %s\n' "$*" >&2; exit 1; }

[ "$(uname -s)" = Darwin ] || fail "winsteam 只支援 macOS。"
[ "$(uname -m)" = arm64 ]  || fail "winsteam 只支援 Apple Silicon 的 Mac。"

case "$DEST" in
  "$HOME"/*) ;;
  *) fail "WINSTEAM_HOME 必須在家目錄底下：$DEST" ;;
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
say ""
say "接下來："
say "  winsteam doctor   檢查這台 Mac"
say "  winsteam setup    開始安裝"

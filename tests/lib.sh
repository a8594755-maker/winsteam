# tests/lib.sh — 測試共用的工具函式（由 run.sh source，bash 3.2 相容）
#
# 每個案例都在自己的沙盒目錄（$SB）裡執行：
#   $SB/home       假的 HOME
#   $SB/cache      WINSTEAM_CACHE
#   $SB/Steam.app  模擬 wrapper（make_wrapper 建立）
#   $SB/fakebin    放在 PATH 最前面的假指令
#   $SB/log        假指令把收到的參數記在這裡
#   $SB/state      控制假指令行為的旗標檔
# 被測的程式一律用 env -i 啟動，只帶入這裡明確給的環境變數，
# 所以不會讀到使用者 shell 裡的 WINSTEAM_* 或真實的 HOME。

# ── 斷言 ───────────────────────────────────────────────────────────────
# 失敗時把訊息記到 $T_FAILLOG 並繼續，讓一個案例可以一次看到所有問題。
_fail() { printf '%s\n' "$*" >> "$T_FAILLOG"; return 1; }

skip() { printf '%s\n' "$*" > "$T_SKIPLOG"; }

assert_status() { # assert_status <預期> [說明]
  [ "$STATUS" = "$1" ] || _fail "${2:-結束碼}：預期 $1，實際 $STATUS$(_show_output)"
}
assert_status_nonzero() {
  [ "$STATUS" != 0 ] || _fail "${1:-結束碼}：預期非零，實際 0$(_show_output)"
}
_show_output() {
  printf '\n      stdout: %s' "$(head -c 600 "$SB/out" 2>/dev/null | tr '\n' '⏎')"
  printf '\n      stderr: %s' "$(head -c 600 "$SB/err" 2>/dev/null | tr '\n' '⏎')"
}
assert_out_contains() { # assert_out_contains <字串>（stdout 或 stderr 任一包含即可）
  cat "$SB/out" "$SB/err" | grep -qF -- "$1" || _fail "輸出應包含「$1」$(_show_output)"
}
assert_out_not_contains() {
  if cat "$SB/out" "$SB/err" | grep -qF -- "$1"; then _fail "輸出不應包含「$1」$(_show_output)"; fi
}
assert_stdout_line() { # assert_stdout_line <延伸正規式>：stdout 有一整行符合
  grep -qE -- "^$1\$" "$SB/out" || _fail "stdout 應有一行符合 /^$1\$/$(_show_output)"
}
assert_stderr_contains() {
  grep -qF -- "$1" "$SB/err" || _fail "stderr 應包含「$1」$(_show_output)"
}
assert_eq() { # assert_eq <預期> <實際> <說明>
  [ "$1" = "$2" ] || _fail "$3：預期「$1」，實際「$2」"
}
assert_exists()     { [ -e "$1" ] || [ -L "$1" ] || _fail "應該存在：$1"; }
assert_not_exists() { if [ -e "$1" ] || [ -L "$1" ]; then _fail "不應該存在：$1"; fi; }
assert_file_empty_or_missing() { # assert_file_empty_or_missing <檔案> <說明>
  if [ -s "$1" ]; then _fail "$2：$(tr '\n' '⏎' < "$1")"; fi
}

# ── Info.plist ─────────────────────────────────────────────────────────
plist() { printf '%s' "$SB/Steam.app/Contents/Info.plist"; }
pget() { plutil -extract "$1" raw -o - "$(plist)" 2>/dev/null; }
phas() { plutil -extract "$1" raw -o - "$(plist)" >/dev/null 2>&1; }
pset_int() { plutil -replace "$1" -integer "$2" "$(plist)"; }
pset_str() { plutil -replace "$1" -string "$2" "$(plist)"; }
pdel() { plutil -remove "$1" "$(plist)"; }
assert_key() { # assert_key <鍵> <預期值>
  if ! phas "$1"; then _fail "Info.plist 應有鍵「$1」（預期 $2），但不存在"; return 1; fi
  assert_eq "$2" "$(pget "$1")" "Info.plist 的 $1"
}
assert_no_key() {
  if phas "$1"; then _fail "Info.plist 不應新增鍵「$1」，但現在是「$(pget "$1")」"; fi
}
plist_sum() { shasum -a 256 "$(plist)" | awk '{print $1}'; }

# ── 沙盒 ───────────────────────────────────────────────────────────────
# 由 run.sh 在每個案例開始前呼叫，$SB 已建立。
sandbox_init() {
  mkdir -p "$SB/home" "$SB/cache" "$SB/fakebin" "$SB/log" "$SB/state" "$SB/tmp" "$SB/profiles"
  cp "$REPO_ROOT"/profiles/*.conf "$SB/profiles/"
  export WRAPPER="$SB/Steam.app"
  _make_fakes
}

# 假指令。路徑直接寫死在腳本裡，不依賴環境變數。
_fake() { # _fake <名稱>，內容從 stdin 讀
  { printf '#!/bin/bash\nSB=%q\n' "$SB"; cat; } > "$SB/fakebin/$1"
  chmod +x "$SB/fakebin/$1"
}
_make_fakes() {
  # Rosetta：預設「有」；touch $SB/state/no_rosetta 改成沒有
  _fake arch <<'EOF'
echo "$*" >> "$SB/log/arch.log"
[ -e "$SB/state/no_rosetta" ] && exit 1
exit 0
EOF
  # macOS 版 Steam：預設沒在跑；touch $SB/state/native_steam 改成在跑
  # wrapper（Windows 版 Steam）：預設沒在跑；touch $SB/state/wrapper_running 改成在跑
  _fake pgrep <<'EOF'
echo "$*" >> "$SB/log/pgrep.log"
case "$*" in
  *steam_osx*) [ -e "$SB/state/native_steam" ] && exit 0 ;;
  # 啟動器與 wineserver 分開控制：state/wrapper_running 是啟動器，state/wineserver_running 是 wineserver
  *SharedSupport/wine/*) [ -e "$SB/state/wineserver_running" ] && exit 0 ;;
  *Sikarugir*) [ -e "$SB/state/wrapper_running" ] && exit 0 ;;
esac
exit 1
EOF
  for c in open osascript softwareupdate; do
    _fake "$c" <<EOF
printf '%s\n' "\$*" >> "\$SB/log/$c.log"
exit 0
EOF
  done
  _fake sleep <<'EOF'
echo "$*" >> "$SB/log/sleep.log"
EOF
  _fake uname <<'EOF'
case "${1:-}" in
  -m) cat "$SB/state/uname_m" 2>/dev/null || echo arm64 ;;
  -s) echo Darwin ;;
  *)  exec /usr/bin/uname "$@" ;;
esac
EOF
  _fake sw_vers <<'EOF'
case "${1:-}" in
  -productVersion) echo 15.5 ;;
  *) printf 'ProductName:\tmacOS\nProductVersion:\t15.5\n' ;;
esac
EOF
  # df -k：回報 200 GB 可用
  _fake df <<'EOF'
echo "Filesystem 1024-blocks Used Available Capacity Mounted on"
echo "/dev/fake 500000000 100000000 209715200 33% /"
EOF
  # curl：有 state/curl_tarball 時把該檔寫到 -o 指定的路徑；否則失敗（exit 22）
  _fake curl <<'EOF'
printf '%s\n' "$*" >> "$SB/log/curl.log"
out=""
while [ $# -gt 0 ]; do
  case "$1" in -o) out="$2"; shift 2 ;; *) shift ;; esac
done
if [ -f "$SB/state/curl_tarball" ] && [ -n "$out" ]; then
  cp "$(cat "$SB/state/curl_tarball")" "$out"; exit 0
fi
echo "curl: (22) The requested URL returned error: 404" >&2
exit 22
EOF
}

# 需要 brew 時才呼叫：fake_brew [prefix]
fake_brew() {
  local prefix="${1:-$SB/brew}"
  mkdir -p "$prefix/bin"
  _fake brew <<EOF
printf '%s\n' "\$*" >> "\$SB/log/brew.log"
case "\${1:-}" in
  --prefix) echo $(printf '%q' "$prefix") ;;
  *) exit 0 ;;
esac
EOF
}

# ── 模擬 wrapper ───────────────────────────────────────────────────────
# 所有測試在意的鍵都有；要測「鍵不存在」時再用 pdel 移掉。
# 三個後端鍵故意都設成 1，才看得出切換後是否互斥。
make_wrapper() {
  local c="$WRAPPER/Contents"
  mkdir -p "$c/MacOS" "$c/drive_c/Program Files/Common Files" "$c/drive_c/Program Files (x86)/Steam"
  : > "$c/drive_c/Program Files (x86)/Steam/Steam.exe"
  { printf '#!/bin/bash\nLOG=%q\n' "$SB/log/sikarugir.log"; echo 'printf "%s\n" "$*" >> "$LOG"'; } > "$c/MacOS/Sikarugir"
  chmod +x "$c/MacOS/Sikarugir"
  cat > "$c/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleExecutable</key>
	<string>Sikarugir</string>
	<key>CNC_DDRAW</key>
	<integer>1</integer>
	<key>D3DMETAL</key>
	<integer>1</integer>
	<key>D9VK</key>
	<integer>1</integer>
	<key>DXMT</key>
	<integer>1</integer>
	<key>DXVK</key>
	<integer>1</integer>
	<key>METAL_HUD</key>
	<integer>0</integer>
	<key>Program Flags</key>
	<string>-old-flag</string>
	<key>Program Name and Path</key>
	<string>/Program Files (x86)/Steam/Steam.exe</string>
	<key>WINEESYNC</key>
	<integer>0</integer>
	<key>WINEMSYNC</key>
	<integer>0</integer>
</dict>
</plist>
EOF
  plutil -lint "$c/Info.plist" >/dev/null || { echo "模擬 Info.plist 格式錯誤" >&2; return 1; }
}

# ── 執行被測程式 ───────────────────────────────────────────────────────
# 安全檢查：所有路徑都必須在沙盒裡，否則直接中止整個案例。
_guard() {
  local v
  for v in "$@"; do
    case "$v" in
      "$SB"/*) ;;
      *) echo "安全檢查失敗：$v 不在沙盒 $SB 裡，拒絕執行" >&2; exit 99 ;;
    esac
  done
}

# 若目前有可用的終端機，就用 perl 的 setsid 讓被測程式脫離它，
# 確保程式裡的 confirm/pause 絕不會在測試時跳出來等人輸入。
_tty_usable() { { : < /dev/tty; } 2>/dev/null; }
NOTTY_MODE=""
_detect_notty() {
  if ! _tty_usable; then NOTTY_MODE=none; return; fi
  if [ -x /usr/bin/perl ] && /usr/bin/perl -MPOSIX -e '
      my $p = fork; if ($p) { waitpid($p,0); exit($? >> 8) }
      POSIX::setsid() or exit 3; exec @ARGV' -- /bin/bash -c '! { : < /dev/tty; } 2>/dev/null'; then
    NOTTY_MODE=perl
  else
    NOTTY_MODE=unavailable
  fi
}
_notty() {
  if [ "$NOTTY_MODE" = perl ]; then
    /usr/bin/perl -MPOSIX -e '
      my $p = fork; die "fork: $!" unless defined $p;
      if ($p) { waitpid($p,0); exit($? & 127 ? 128 + ($? & 127) : $? >> 8) }
      POSIX::setsid() or exit 97; exec @ARGV or exit 96' -- "$@"
  else
    "$@"
  fi
}
# 需要「確定沒有終端機」的案例先呼叫這個；做不到就略過。
require_notty() {
  if [ "$NOTTY_MODE" = unavailable ]; then
    skip "有終端機但無法用 perl setsid 脫離，無法模擬「沒有終端機」"
    return 1
  fi
  return 0
}

# ws [參數…]：執行 bin/winsteam。結果放在 $STATUS、$SB/out、$SB/err。
# 可先設定 WS_WRAPPER / WS_CACHE / WS_PROFILES 覆寫預設路徑（仍須在沙盒內）。
ws() {
  local wrapper="${WS_WRAPPER:-$WRAPPER}" cache="${WS_CACHE:-$SB/cache}" profiles="${WS_PROFILES:-$SB/profiles}"
  _guard "$wrapper" "$cache" "$SB/home"
  # 設定檔資料夾只會被讀取，允許指向儲存庫本身的 profiles/
  [ "$profiles" = "$REPO_ROOT/profiles" ] || _guard "$profiles"
  _notty /usr/bin/env -i \
    HOME="$SB/home" \
    PATH="$SB/fakebin:/usr/bin:/bin:/usr/sbin:/sbin" \
    TMPDIR="$SB/tmp/" \
    LANG="${WS_LANG:-$TEST_LANG}" \
    WINSTEAM_WRAPPER="$wrapper" \
    WINSTEAM_CACHE="$cache" \
    WINSTEAM_PROFILES="$profiles" \
    /bin/bash "$WINSTEAM" "$@" < /dev/null > "$SB/out" 2> "$SB/err"
  STATUS=$?
}

# inst [環境變數=值…]：執行 install.sh（從標準輸入餵給 bash，跟 curl | bash 一樣）
inst() {
  _guard "$SB/home"
  _notty /usr/bin/env -i \
    HOME="$SB/home" \
    PATH="${INST_PATH:-$SB/fakebin:/usr/bin:/bin:/usr/sbin:/sbin}" \
    TMPDIR="$SB/tmp/" \
    LANG="${WS_LANG:-$TEST_LANG}" \
    "$@" \
    /bin/bash < "$INSTALLER" > "$SB/out" 2> "$SB/err"
  STATUS=$?
}

# 列出沙盒內所有檔案（排除 log 與輸出檔），用來比對「沒有建立任何檔案」。
tree_snapshot() {
  (cd "$SB" && find . \( -path ./log -o -path ./out -o -path ./err \) -prune -o -print | LC_ALL=C sort)
}

# download()：多連線分段下載，以及退回單一連線的各種情況

# 支援 Range 的假 curl：從 $SB/state/dl_file 指到的本機檔案提供內容。
#   $SB/state/dl_norange  存在時忽略 Range（模擬不支援分段的伺服器）
#   $SB/state/dl_fail_at  內容是某一段的起始位移，該段會下載失敗
_range_curl() {
  head -c 200000 /dev/urandom > "$SB/state/src.bin"
  printf '%s' "$SB/state/src.bin" > "$SB/state/dl_file"
  _fake curl <<'EOF'
range=""; out=""; hdr=0
while [ $# -gt 0 ]; do
  case "$1" in
    -r) range="$2"; shift 2 ;;
    -o) out="$2"; shift 2 ;;
    -D) hdr=1; shift 2 ;;
    --max-time|--retry|--retry-delay) shift 2 ;;
    *) shift ;;
  esac
done
src="$(cat "$SB/state/dl_file")"; total="$(stat -f %z "$src")"
echo "range=$range" >> "$SB/log/curl.log"
if [ -n "$range" ] && [ ! -e "$SB/state/dl_norange" ]; then
  s="${range%-*}"; e="${range#*-}"
  if [ -e "$SB/state/dl_fail_at" ] && [ "$s" = "$(cat "$SB/state/dl_fail_at")" ]; then exit 22; fi
  if [ "$hdr" = 1 ]; then printf 'HTTP/2 206\r\ncontent-range: bytes %s-%s/%s\r\n\r\n' "$s" "$e" "$total"; fi
  dd if="$src" bs=1 skip="$s" count="$(( e - s + 1 ))" 2>/dev/null > "$out"
else
  if [ "$hdr" = 1 ]; then printf 'HTTP/2 200\r\n\r\n'; fi
  cat "$src" > "$out"
fi
EOF
}

# dl [環境變數=值…]：在沙盒裡載入 winsteam 的函式並呼叫 download
dl() {
  _guard "$SB/cache" "$SB/home"
  _notty /usr/bin/env -i \
    HOME="$SB/home" \
    PATH="$SB/fakebin:/usr/bin:/bin:/usr/sbin:/sbin" \
    TMPDIR="$SB/tmp/" \
    LANG="${WS_LANG:-$TEST_LANG}" \
    WINSTEAM_WRAPPER="$WRAPPER" \
    WINSTEAM_CACHE="$SB/cache" \
    WINSTEAM_PROFILES="$SB/profiles" \
    WINSTEAM_SOURCE_ONLY=1 \
    WINSTEAM_PARALLEL_MIN_BYTES=1 \
    "$@" \
    /bin/bash -c 'set -euo pipefail; source "$0"; download "https://example.invalid/file.bin" "$1"' \
      "$WINSTEAM" "$SB/cache/file.bin" < /dev/null > "$SB/out" 2> "$SB/err"
  STATUS=$?
}

_same_as_source() {
  assert_eq "$(shasum -a 256 "$SB/state/src.bin" | awk '{print $1}')" \
            "$(shasum -a 256 "$SB/cache/file.bin" 2>/dev/null | awk '{print $1}')" "下載結果應與來源完全相同"
  assert_not_exists "$SB/cache/file.bin.part"
}
_range_requests() { grep -c '^range=[0-9]' "$SB/log/curl.log" 2>/dev/null || true; }

t_download_parallel_assembles() { # 八條連線分段下載後接起來，內容與來源一致
  _range_curl
  dl
  assert_status 0
  _same_as_source
  assert_eq 9 "$(_range_requests)" "Range 請求數（1 次探測 + 8 段）"
}

t_download_no_range_support() { # 伺服器不支援分段：退回單一連線，內容一致
  _range_curl
  : > "$SB/state/dl_norange"
  dl
  assert_status 0
  _same_as_source
}

t_download_part_fails_falls_back() { # 其中一段失敗：退回單一連線重抓整個檔案，內容一致
  _range_curl
  printf '50000' > "$SB/state/dl_fail_at"
  dl
  assert_status 0
  _same_as_source
}

t_download_single_connection() { # WINSTEAM_CONNECTIONS=1：完全不發 Range 請求
  _range_curl
  dl WINSTEAM_CONNECTIONS=1
  assert_status 0
  _same_as_source
  assert_eq 0 "$(_range_requests)" "Range 請求數"
}

t_download_bad_connections_value() { # WINSTEAM_CONNECTIONS 不是數字：當成 1，不會出錯
  _range_curl
  dl WINSTEAM_CONNECTIONS=abc
  assert_status 0
  _same_as_source
  assert_eq 0 "$(_range_requests)" "Range 請求數"
}

t_download_small_file_not_split() { # 小於門檻的檔案不分段
  _range_curl
  dl WINSTEAM_PARALLEL_MIN_BYTES=16777216
  assert_status 0
  _same_as_source
  assert_eq 1 "$(_range_requests)" "Range 請求數（只有探測）"
}

t_source_only_does_not_run() { # WINSTEAM_SOURCE_ONLY=1 時 source 不會執行任何指令
  /usr/bin/env -i PATH="/usr/bin:/bin" WINSTEAM_SOURCE_ONLY=1 WINSTEAM_WRAPPER="$WRAPPER" WINSTEAM_CACHE="$SB/cache" \
    /bin/bash -c 'source "$0"; echo "loaded:$(type -t download)"' "$WINSTEAM" > "$SB/out" 2> "$SB/err"
  STATUS=$?
  assert_status 0
  assert_eq "loaded:function" "$(cat "$SB/out")" "只載入函式"
}

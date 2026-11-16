#!/bin/bash
# winsteam 自動化測試：純 bash（相容 macOS 內建的 bash 3.2），零相依。
#
#   tests/run.sh              跑全部案例
#   tests/run.sh backend      只跑名稱含有 "backend" 的案例
#   KEEP_SANDBOX=1 tests/run.sh   跑完保留暫存目錄方便除錯
#   TEST_LANG=en_US.UTF-8 tests/run.sh   用指定的 LANG 跑所有案例（預設 C）
#
# 行為類的案例預設在 LANG=C 下執行，以免單一的語系問題蓋掉其他檢查；
# test_locale.sh 另外專門在 UTF-8 語系下（一般使用者的終端機環境）跑主要指令。
#
# 每個案例都有自己的暫存沙盒；被測程式的 HOME、WINSTEAM_WRAPPER、
# WINSTEAM_CACHE、WINSTEAM_PROFILES 全部指向沙盒，絕不碰真實路徑。
# 有任何案例失敗時以結束碼 1 結束。
set -u

TESTS_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$TESTS_DIR/.." && pwd)"
WINSTEAM="$REPO_ROOT/bin/winsteam"
INSTALLER="$REPO_ROOT/install.sh"
FILTER="${1:-}"
TEST_LANG="${TEST_LANG:-C}"

. "$TESTS_DIR/lib.sh"

if [ -t 1 ]; then G=$'\033[32m'; R=$'\033[31m'; Y=$'\033[33m'; D=$'\033[2m'; Z=$'\033[0m'
else G=""; R=""; Y=""; D=""; Z=""; fi

RUN_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/winsteam-tests.XXXXXX")" || { echo "無法建立暫存目錄" >&2; exit 1; }
# mktemp 可能回傳經過 symlink 的路徑（/var → /private/var），統一成實體路徑
RUN_ROOT="$(cd -P "$RUN_ROOT" && pwd)"
cleanup() {
  if [ "${KEEP_SANDBOX:-0}" = 1 ]; then echo "${D}沙盒保留在：$RUN_ROOT${Z}"
  else rm -rf "$RUN_ROOT"; fi
}
trap cleanup EXIT

# ── 共用素材：install.sh 要下載的 tarball ────────────────────────────────
build_fixtures() {
  local fx="$RUN_ROOT/fixtures"
  mkdir -p "$fx/ok/winsteam-main" "$fx/broken/winsteam-main"
  cp -R "$REPO_ROOT/bin" "$REPO_ROOT/profiles" "$fx/ok/winsteam-main/"
  cp "$REPO_ROOT/README.md" "$REPO_ROOT/install.sh" "$fx/ok/winsteam-main/"
  cp -R "$REPO_ROOT/profiles" "$fx/broken/winsteam-main/"   # 少了 bin/winsteam
  (cd "$fx/ok" && COPYFILE_DISABLE=1 tar -czf "$fx/winsteam-main.tar.gz" winsteam-main)
  (cd "$fx/broken" && COPYFILE_DISABLE=1 tar -czf "$fx/broken.tar.gz" winsteam-main)
  TARBALL_OK="$fx/winsteam-main.tar.gz"
  TARBALL_BROKEN="$fx/broken.tar.gz"
}
build_fixtures || { echo "建立測試素材失敗" >&2; exit 1; }

_detect_notty

# ── 執行 ───────────────────────────────────────────────────────────────
total=0; passed=0; failed=0; skipped=0
failed_names=""

run_case() { # run_case <函式> <說明>
  local fn="$1" desc="$2" rc
  total=$((total + 1))
  SB="$RUN_ROOT/case-$total"
  mkdir -p "$SB"
  T_FAILLOG="$SB/.fail"; T_SKIPLOG="$SB/.skip"
  : > "$T_FAILLOG"
  (
    cd "$SB" || exit 1
    sandbox_init || { _fail "沙盒初始化失敗"; exit 1; }
    "$fn"
  ) > "$SB/.case.log" 2>&1
  rc=$?
  local label="$fn${desc:+ — $desc}"
  if [ -s "$T_SKIPLOG" ]; then
    skipped=$((skipped + 1))
    printf '%s[略過]%s %s\n       %s\n' "$Y" "$Z" "$label" "$(cat "$T_SKIPLOG")"
  elif [ -s "$T_FAILLOG" ] || [ "$rc" != 0 ]; then
    failed=$((failed + 1)); failed_names="$failed_names $fn"
    printf '%s[失敗]%s %s\n' "$R" "$Z" "$label"
    if [ -s "$T_FAILLOG" ]; then sed 's/^/       - /' "$T_FAILLOG"
    else printf '       - 案例異常結束（結束碼 %s）\n' "$rc"; fi
    if [ -s "$SB/.case.log" ]; then sed -e 's/^/       | /' "$SB/.case.log" | head -n 20; fi
  else
    passed=$((passed + 1))
    printf '%s[通過]%s %s\n' "$G" "$Z" "$label"
  fi
}

for file in "$TESTS_DIR"/test_*.sh; do
  [ -f "$file" ] || continue
  . "$file"
  printf '\n%s# %s%s\n' "$D" "$(basename "$file")" "$Z"
  # 依定義順序取出 t_xxx() { # 說明
  while IFS= read -r line; do
    fn="$(printf '%s' "$line" | sed -E 's/^(t_[A-Za-z0-9_]+).*/\1/')"
    desc="$(printf '%s' "$line" | sed -nE 's/^[^#]*# *//p')"
    case "$fn" in *"$FILTER"*) ;; *) continue ;; esac
    run_case "$fn" "$desc"
  done <<EOF
$(grep -E '^t_[A-Za-z0-9_]+ *\(\)' "$file")
EOF
done

echo
printf '結果：%d 個案例，%s%d 通過%s，%s%d 失敗%s，%d 略過\n' \
  "$total" "$G" "$passed" "$Z" "$([ "$failed" -gt 0 ] && echo "$R")" "$failed" "$Z" "$skipped"
[ "$failed" = 0 ] || { printf '失敗的案例：%s\n' "$failed_names"; exit 1; }
[ "$total" -gt 0 ] || { echo "沒有符合「$FILTER」的案例" >&2; exit 1; }
exit 0

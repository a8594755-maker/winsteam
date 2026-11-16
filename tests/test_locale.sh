# 語系：macOS 的終端機預設 LANG=xx_XX.UTF-8。bash 3.2 在 UTF-8 語系下，
# 會把 "$name（" 裡全形字元的位元組當成變數名稱的一部分，配合 set -u 直接中止。
# 這裡的案例在一般使用者的語系下跑主要指令。

UTF8_LOCALES="en_US.UTF-8 zh_TW.UTF-8"

t_lint_no_bare_var_before_multibyte() { # bin/winsteam 與 install.sh 沒有「$變數 緊接非 ASCII 字元」（應寫成 ${變數}）
  local pat hits f
  pat="\\\$[A-Za-z_][A-Za-z0-9_]*[$(printf '\200')-$(printf '\377')]"
  for f in "$WINSTEAM" "$INSTALLER"; do
    hits="$(LC_ALL=C grep -nE "$pat" "$f" | LC_ALL=C grep -vE '^[0-9]+: *#')"
    [ -z "$hits" ] || _fail "$(basename "$f") 有 $(printf '%s\n' "$hits" | wc -l | tr -d ' ') 處：$(printf '%s\n' "$hits" | cut -d: -f1 | tr '\n' ' ')"
  done
}

t_locale_play() { # UTF-8 語系下 play repo 能完成
  local l
  for l in $UTF8_LOCALES; do
    rm -f "$SB/log/open.log"
    make_wrapper
    WS_LANG="$l" ws play repo
    assert_status 0 "LANG=$l"
    assert_key "Program Flags" "-applaunch 3241660"
    assert_exists "$SB/log/open.log"
  done
}

t_locale_logs() { # UTF-8 語系下 logs 能顯示記錄檔
  make_wrapper
  local dir="$WRAPPER/Contents/drive_c/Program Files (x86)/Steam/logs" l
  mkdir -p "$dir"; echo "hello log" > "$dir/bootstrap_log.txt"
  for l in $UTF8_LOCALES; do
    WS_LANG="$l" ws logs
    assert_status 0 "LANG=$l"
    assert_stdout_line "hello log"
  done
}

t_locale_backend_error_message() { # UTF-8 語系下不認得的後端仍顯示正確的錯誤訊息
  make_wrapper
  local l
  for l in $UTF8_LOCALES; do
    WS_LANG="$l" ws backend metal
    assert_status 1 "LANG=$l"
    assert_out_contains "不認得的後端：metal"
  done
}

t_locale_setup_dry_run() { # UTF-8 語系下 --dry-run setup 能跑完七個步驟
  fake_brew
  local l
  for l in $UTF8_LOCALES; do
    WS_LANG="$l" ws --dry-run setup
    assert_status 0 "LANG=$l"
    assert_out_contains "▸ 7/7 "
  done
  assert_not_exists "$SB/Steam.app"
}

t_locale_status_and_help() { # UTF-8 語系下 help、status 正常
  make_wrapper
  local l
  for l in $UTF8_LOCALES; do
    WS_LANG="$l" ws help;   assert_status 0 "help LANG=$l"
    WS_LANG="$l" ws status; assert_status 0 "status LANG=$l"
  done
}

t_locale_install() { # UTF-8 語系下 curl | bash 安裝能成功
  printf '%s' "$TARBALL_OK" > "$SB/state/curl_tarball"
  local l
  for l in $UTF8_LOCALES; do
    WS_LANG="$l" inst
    assert_status 0 "LANG=$l"
    assert_exists "$SB/home/.winsteam/bin/winsteam"
  done
}

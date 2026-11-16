# 基本指令：help、version、games、不認得的指令、--dry-run setup

t_help() { # help 印出用法並以 0 結束
  ws help
  assert_status 0
  assert_out_contains "用法：winsteam [--dry-run] [--yes] <指令>"
  local c
  for c in doctor setup run games play backend hud status logs kill uninstall version; do
    assert_stdout_line "  $c .*"
  done
}

t_help_default() { # 沒有參數時等同 help
  ws
  assert_status 0
  assert_out_contains "用法：winsteam"
}

t_help_aliases() { # --help 與 -h
  ws --help; assert_status 0 "--help"; assert_out_contains "用法：winsteam"
  ws -h;     assert_status 0 "-h";     assert_out_contains "用法：winsteam"
}

t_version() { # version / --version / -v 印出與腳本相同的版本號
  local want
  want="$(sed -n 's/^VERSION="\(.*\)"$/\1/p' "$WINSTEAM")"
  [ -n "$want" ] || _fail "無法從 bin/winsteam 讀出 VERSION"
  local a
  for a in version --version -v; do
    ws "$a"
    assert_status 0 "$a"
    assert_eq "winsteam $want" "$(cat "$SB/out")" "$a 的輸出"
  done
}

t_unknown_command() { # 不認得的指令：結束碼 2，提示並附上說明
  ws frobnicate
  assert_status 2
  assert_out_contains "不認得的指令：frobnicate"
  assert_out_contains "用法：winsteam"
}

t_games_lists_repo_profiles() { # games 列出 profiles/ 裡每個設定檔的名稱、App ID、後端
  WS_PROFILES="$REPO_ROOT/profiles" ws games
  assert_status 0
  local f base appid backend n=0
  for f in "$REPO_ROOT"/profiles/*.conf; do
    n=$((n + 1))
    base="$(basename "$f" .conf)"
    appid="$(sed -n 's/^APPID=//p' "$f")"
    backend="$(sed -n 's/^BACKEND=//p' "$f")"
    assert_stdout_line "$base +.* +$appid +$backend"
  done
  [ "$n" -ge 2 ] || _fail "profiles/ 應至少有 repo 與 mimesis 兩個設定檔，只找到 $n 個"
  assert_stdout_line "repo +R\.E\.P\.O\. +3241660 +dxmt"
}

t_games_custom_dir() { # games 讀 WINSTEAM_PROFILES 指定的資料夾
  printf 'NAME="Test Game"\nAPPID=42\nBACKEND=dxvk\n' > "$SB/profiles/zzz.conf"
  ws games
  assert_status 0
  assert_stdout_line "zzz +Test Game +42 +dxvk"
}

t_games_empty_dir() { # 沒有任何設定檔時警告但不失敗
  mkdir -p "$SB/empty"
  WS_PROFILES="$SB/empty" ws games
  assert_status 0
  assert_out_contains "找不到任何設定檔"
}

t_setup_dry_run_lists_seven_steps() { # --dry-run setup 依序列出七個步驟，且不建立任何檔案
  fake_brew
  local before after
  before="$(tree_snapshot)"
  ws --dry-run setup
  after="$(tree_snapshot)"
  assert_status 0
  local i
  for i in 1 2 3 4 5 6 7; do assert_out_contains "▸ $i/7 "; done
  # 七個步驟要依序出現
  local order
  order="$(grep -oE '▸ [0-9]/7' "$SB/out" | sed 's/.* //' | tr '\n' ' ')"
  assert_eq "1/7 2/7 3/7 4/7 5/7 6/7 7/7 " "$order" "步驟順序"
  assert_out_contains "[dry-run]"
  assert_out_contains "乾跑結束"
  assert_eq "$before" "$after" "dry-run 前後沙盒內容"
  assert_not_exists "$SB/Steam.app"
  assert_not_exists "$SB/cache/Engines"
  assert_not_exists "$SB/cache/Template"
  assert_not_exists "$SB/cache/SteamSetup.exe"
  assert_file_empty_or_missing "$SB/log/curl.log" "dry-run 不應真的呼叫 curl"
  assert_file_empty_or_missing "$SB/log/softwareupdate.log" "dry-run 不應呼叫 softwareupdate"
  assert_file_empty_or_missing "$SB/log/sikarugir.log" "dry-run 不應執行 wrapper"
}

t_setup_dry_run_without_rosetta() { # 沒有 Rosetta 時 --dry-run setup 只印出安裝指令
  fake_brew
  touch "$SB/state/no_rosetta"
  ws --dry-run setup
  assert_status 0
  assert_out_contains "softwareupdate --install-rosetta"
  assert_file_empty_or_missing "$SB/log/softwareupdate.log" "dry-run 不應呼叫 softwareupdate"
  assert_not_exists "$SB/Steam.app"
}

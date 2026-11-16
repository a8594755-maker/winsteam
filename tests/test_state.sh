# state（機器可讀狀態）與 prefetch（預先下載 Steam 套件）

_steam_dir() { printf '%s' "$WRAPPER/Contents/drive_c/Program Files (x86)/Steam"; }

t_state_no_wrapper() { # 沒有 wrapper：全部是 0，結束碼 0
  ws state
  assert_status 0
  assert_stdout_line 'wrapper=0'
  assert_stdout_line 'steam_installed=0'
  assert_stdout_line 'client_ready=0'
  assert_stdout_line 'has_logged_in=0'
  assert_stdout_line 'game\.repo\.appid=3241660'
  assert_stdout_line 'game\.repo\.installed=0'
}

t_state_fresh_install() { # 剛裝好 Steam：已安裝，但用戶端未更新完、沒登入過、遊戲沒裝
  make_wrapper
  ws state
  assert_status 0
  assert_stdout_line 'wrapper=1'
  assert_stdout_line 'steam_installed=1'
  assert_stdout_line 'client_ready=0'
  assert_stdout_line 'running=0'
  assert_stdout_line 'has_logged_in=0'
  assert_stdout_line 'game\.mimesis\.installed=0'
}

t_state_ready_logged_in_game_installed() { # 用戶端更新完、登入過、repo 已完整安裝、mimesis 下載中
  make_wrapper
  d="$(_steam_dir)"
  mkdir -p "$d/package" "$d/config" "$d/steamapps"
  : > "$d/package/steam_client_win64.installed"
  printf '"users"\n{\n\t"76561198000000000"\n\t{\n\t\t"AccountName"\t\t"someone"\n\t}\n}\n' > "$d/config/loginusers.vdf"
  printf '"AppState"\n{\n\t"appid"\t\t"3241660"\n\t"StateFlags"\t\t"4"\n}\n' > "$d/steamapps/appmanifest_3241660.acf"
  printf '"AppState"\n{\n\t"appid"\t\t"2827200"\n\t"StateFlags"\t\t"1026"\n}\n' > "$d/steamapps/appmanifest_2827200.acf"
  : > "$SB/state/wrapper_running"
  ws state
  assert_status 0
  assert_stdout_line 'client_ready=1'
  assert_stdout_line 'running=1'
  assert_stdout_line 'has_logged_in=1'
  assert_stdout_line 'game\.repo\.installed=1'
  assert_stdout_line 'game\.repo\.installing=0'
  assert_stdout_line 'game\.mimesis\.installed=0'
  assert_stdout_line 'game\.mimesis\.installing=1'
}

t_state_empty_loginusers() { # loginusers.vdf 存在但沒有帳號：視為沒登入過
  make_wrapper
  d="$(_steam_dir)"; mkdir -p "$d/config"
  printf '"users"\n{\n}\n' > "$d/config/loginusers.vdf"
  ws state
  assert_stdout_line 'has_logged_in=0'
}

t_prefetch_dry_run() { # --dry-run prefetch 不下載、不建立 package 資料夾
  make_wrapper
  ws --dry-run prefetch
  assert_status 0
  assert_not_exists "$(_steam_dir)/package"
  assert_not_exists "$SB/log/curl.log"
}

t_prefetch_download_fails_gracefully() { # 下載失敗：只警告、結束碼 0、不留下任何套件檔
  make_wrapper
  ws prefetch
  assert_status 0
  assert_out_contains "沒有預先下載成功"
  n="$(ls "$(_steam_dir)/package" 2>/dev/null | wc -l | tr -d ' ')"
  assert_eq 0 "$n" "package 資料夾內的檔案數"
}

t_prefetch_requires_steam() { # wrapper 裡還沒有 Steam 時報錯
  make_wrapper
  rm -f "$(_steam_dir)/Steam.exe"
  ws prefetch
  assert_status_nonzero
  assert_out_contains "還沒有 Steam"
}

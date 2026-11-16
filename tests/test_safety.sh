# 安全性：uninstall 的確認與路徑檢查、遊戲名稱的路徑穿越

steam_exe() { printf '%s' "$WRAPPER/Contents/drive_c/Program Files (x86)/Steam/Steam.exe"; }

make_cache_files() {
  mkdir -p "$SB/cache/Engines" "$SB/cache/Template"
  : > "$SB/cache/Engines/WS12WineSikarugir10.0_6.tar.xz"
  : > "$SB/cache/Template/Template-1.0.11.tar.xz"
  : > "$SB/cache/SteamSetup.exe"
  : > "$SB/cache/keep-me.txt"
}

t_uninstall_no_tty_no_yes_keeps_wrapper() { # 沒有終端機且沒加 --yes：uninstall 不刪除
  require_notty || return 0
  make_wrapper
  ws uninstall
  assert_status_nonzero
  assert_out_contains "沒有終端機可以輸入"
  assert_exists "$(steam_exe)"
  assert_file_empty_or_missing "$SB/log/sikarugir.log" "取消時不應結束 wineserver"
}

t_uninstall_all_no_tty_no_yes_keeps_everything() { # 沒有終端機且沒加 --yes：uninstall --all 連快取也不刪
  require_notty || return 0
  make_wrapper
  make_cache_files
  ws uninstall --all
  assert_status_nonzero
  assert_exists "$(steam_exe)"
  assert_exists "$SB/cache/Engines/WS12WineSikarugir10.0_6.tar.xz"
  assert_exists "$SB/cache/SteamSetup.exe"
}

t_uninstall_all_no_wrapper_no_tty_no_yes() { # 沒有 wrapper、沒有終端機、沒加 --yes：uninstall --all 不應未經確認就刪快取
  require_notty || return 0
  make_cache_files
  ws uninstall --all
  assert_exists "$SB/cache/Engines/WS12WineSikarugir10.0_6.tar.xz"
  assert_exists "$SB/cache/Template/Template-1.0.11.tar.xz"
  assert_exists "$SB/cache/SteamSetup.exe"
}

t_uninstall_dry_run() { # --dry-run uninstall 不刪除
  make_wrapper
  ws --dry-run uninstall
  assert_status 0
  assert_out_contains "[dry-run]"
  assert_exists "$(steam_exe)"
  assert_file_empty_or_missing "$SB/log/sikarugir.log" "dry-run 不應執行 wrapper"
}

t_uninstall_dry_run_all() { # --dry-run uninstall --all 不刪 wrapper 也不刪快取
  make_wrapper
  make_cache_files
  ws --dry-run uninstall --all
  assert_status 0
  assert_exists "$(steam_exe)"
  assert_exists "$SB/cache/Engines/WS12WineSikarugir10.0_6.tar.xz"
  assert_exists "$SB/cache/Template/Template-1.0.11.tar.xz"
  assert_exists "$SB/cache/SteamSetup.exe"
}

t_uninstall_rejects_non_app_path() { # WINSTEAM_WRAPPER 不是 .app 結尾：即使加了 --yes 也拒絕刪除
  local victim="$SB/home/Documents"
  mkdir -p "$victim"; echo important > "$victim/thesis.txt"
  WS_WRAPPER="$victim" ws --yes uninstall
  assert_status_nonzero
  assert_out_contains "拒絕刪除"
  assert_exists "$victim/thesis.txt"
}

t_uninstall_rejects_trailing_slash_and_dotdot() { # .app/ 結尾或 .app/.. 這類路徑也拒絕
  mkdir -p "$SB/x.app" "$SB/keep"; : > "$SB/keep/file"
  WS_WRAPPER="$SB/x.app/.." ws --yes uninstall
  assert_status_nonzero "x.app/.."
  assert_exists "$SB/keep/file"
  assert_exists "$SB/x.app"
  WS_WRAPPER="$SB/x.app/" ws --yes uninstall
  assert_status_nonzero "x.app/"
  assert_exists "$SB/x.app"
}

t_uninstall_with_yes_deletes_wrapper_only() { # --yes uninstall 刪 wrapper，但不動快取
  make_wrapper
  make_cache_files
  ws --yes uninstall
  assert_status 0
  assert_not_exists "$WRAPPER"
  assert_exists "$SB/cache/SteamSetup.exe"
  grep -qx WSS-wineserverkill "$SB/log/sikarugir.log" 2>/dev/null || _fail "刪除前應先結束 wineserver"
}

t_uninstall_with_yes_all() { # --yes uninstall --all 只刪 Engines、Template、SteamSetup.exe
  make_wrapper
  make_cache_files
  ws --yes uninstall --all
  assert_status 0
  assert_not_exists "$WRAPPER"
  assert_not_exists "$SB/cache/Engines"
  assert_not_exists "$SB/cache/Template"
  assert_not_exists "$SB/cache/SteamSetup.exe"
  assert_exists "$SB/cache/keep-me.txt"
}

t_uninstall_nothing_to_remove() { # 沒有 wrapper 時說明沒有東西要刪
  ws --yes uninstall
  assert_status 0
  assert_out_contains "沒有 wrapper 需要刪除"
}

t_play_path_traversal() { # play '../etc/passwd' 被擋下，不碰 Info.plist、不啟動
  make_wrapper
  local before; before="$(plist_sum)"
  ws play '../etc/passwd'
  assert_status_nonzero
  assert_out_contains "沒有「../etc/passwd」的設定檔"
  assert_eq "$before" "$(plist_sum)" "Info.plist 雜湊"
  assert_not_exists "$SB/log/open.log"
}

t_play_path_traversal_existing_file() { # 名稱指向 profiles 外面真實存在的 .conf 也不會被讀
  make_wrapper
  printf 'NAME="Evil"\nAPPID=666\nBACKEND=dxvk\n' > "$SB/evil.conf"
  local before; before="$(plist_sum)"
  ws play '../evil'
  assert_status_nonzero
  assert_eq "$before" "$(plist_sum)" "Info.plist 雜湊"
  assert_out_not_contains "Evil"
  WS_PROFILES="$SB/profiles" ws play "$SB/evil"
  assert_status_nonzero "絕對路徑"
  assert_eq "$before" "$(plist_sum)" "Info.plist 雜湊（絕對路徑）"
}

t_play_name_only_separators() { # 名稱只剩特殊字元（例如 '../'）時要求指定遊戲
  make_wrapper
  ws play '../'
  assert_status_nonzero
  assert_out_contains "請指定遊戲名稱"
  assert_not_exists "$SB/log/open.log"
}

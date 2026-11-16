# 在模擬 wrapper 上操作：backend、hud、status、run、play、logs、kill，以及鍵不存在的情況

# 檢查三個後端鍵的值：assert_backend_keys <D3DMETAL> <DXMT> <DXVK>
assert_backend_keys() {
  assert_key D3DMETAL "$1"
  assert_key DXMT "$2"
  assert_key DXVK "$3"
}

# ── backend ────────────────────────────────────────────────────────────
t_backend_d3dmetal() { # backend d3dmetal：只有 D3DMETAL=1，D9VK 與 CNC_DDRAW 歸零
  make_wrapper
  ws backend d3dmetal
  assert_status 0
  assert_backend_keys 1 0 0
  assert_key D9VK 0
  assert_key CNC_DDRAW 0
  ws backend; assert_out_contains "目前的圖形後端：d3dmetal"
}

t_backend_dxmt() { # backend dxmt：只有 DXMT=1，D9VK 與 CNC_DDRAW 不動
  make_wrapper
  ws backend dxmt
  assert_status 0
  assert_backend_keys 0 1 0
  assert_key D9VK 1
  assert_key CNC_DDRAW 1
  ws backend; assert_out_contains "目前的圖形後端：dxmt"
}

t_backend_dxvk() { # backend dxvk：只有 DXVK=1
  make_wrapper
  ws backend dxvk
  assert_status 0
  assert_backend_keys 0 0 1
  assert_key D9VK 1
  ws backend; assert_out_contains "目前的圖形後端：dxvk"
}

t_backend_wined3d() { # backend wined3d：三個後端鍵都是 0
  make_wrapper
  ws backend wined3d
  assert_status 0
  assert_backend_keys 0 0 0
  ws backend; assert_out_contains "目前的圖形後端：wined3d"
}

t_backend_sequence() { # 連續切換四種後端，每次都只有一個（或零個）後端鍵是 1
  make_wrapper
  ws backend dxvk;     assert_backend_keys 0 0 1
  ws backend dxmt;     assert_backend_keys 0 1 0
  ws backend wined3d;  assert_backend_keys 0 0 0
  ws backend d3dmetal; assert_backend_keys 1 0 0
}

t_backend_kills_wineserver() { # 切換後端前會先結束 wineserver
  make_wrapper
  ws backend dxmt
  grep -qx WSS-wineserverkill "$SB/log/sikarugir.log" 2>/dev/null || _fail "應以 WSS-wineserverkill 呼叫 wrapper"
}

t_backend_invalid_value() { # 不認得的後端：報錯、非零結束，Info.plist 不變
  make_wrapper
  local before; before="$(plist_sum)"
  ws backend metal
  assert_status_nonzero
  assert_out_contains "不認得的後端：metal"
  assert_eq "$before" "$(plist_sum)" "Info.plist 雜湊"
}

t_backend_invalid_no_side_effects() { # 不認得的後端不應結束執行中的 Wine（打錯字不該讓遊戲被關掉）
  make_wrapper
  ws backend metal
  assert_status_nonzero
  assert_file_empty_or_missing "$SB/log/sikarugir.log" "輸入錯誤時不應呼叫 wrapper（WSS-wineserverkill）"
}

t_backend_dry_run() { # --dry-run backend 不改 Info.plist
  make_wrapper
  local before; before="$(plist_sum)"
  ws --dry-run backend dxvk
  assert_status 0
  assert_eq "$before" "$(plist_sum)" "Info.plist 雜湊"
  assert_out_contains "[dry-run]"
  assert_file_empty_or_missing "$SB/log/sikarugir.log" "dry-run 不應執行 wrapper"
}

t_backend_without_wrapper() { # 沒有 wrapper 時提示先執行 setup
  ws backend dxmt
  assert_status_nonzero
  assert_out_contains "找不到 wrapper"
  assert_not_exists "$WRAPPER"
}

# ── hud ────────────────────────────────────────────────────────────────
t_hud_on_off() { # hud on / off 切換 METAL_HUD
  make_wrapper
  ws hud on;  assert_status 0 "hud on";  assert_key METAL_HUD 1
  ws hud off; assert_status 0 "hud off"; assert_key METAL_HUD 0
}

t_hud_invalid_arg() { # hud 參數錯誤時顯示用法
  make_wrapper
  local before; before="$(plist_sum)"
  ws hud maybe
  assert_status_nonzero
  assert_out_contains "用法：winsteam hud on|off"
  assert_eq "$before" "$(plist_sum)" "Info.plist 雜湊"
}

t_hud_missing_key() { # Info.plist 沒有 METAL_HUD：報錯，不新增鍵
  make_wrapper
  pdel METAL_HUD
  ws hud on
  assert_status_nonzero
  assert_out_contains "沒有 METAL_HUD 鍵"
  assert_no_key METAL_HUD
}

# ── status ─────────────────────────────────────────────────────────────
t_status() { # status 顯示 wrapper 路徑、後端與各個鍵
  make_wrapper
  ws backend dxmt
  pset_int WINEMSYNC 1
  pset_str "Program Flags" "-applaunch 123"
  ws status
  assert_status 0
  assert_stdout_line "Wrapper +$(printf '%s' "$WRAPPER" | sed 's/[][\.*^$()+?{}|]/\\&/g')"
  assert_stdout_line "圖形後端 +dxmt"
  assert_stdout_line "WINEMSYNC +1"
  assert_stdout_line "WINEESYNC +0"
  assert_stdout_line "METAL_HUD +0"
  assert_stdout_line "Program Flags -applaunch 123"
  assert_stdout_line "Program Name and Path /Program Files \(x86\)/Steam/Steam\.exe"
  assert_out_contains "佔用空間"
}

t_status_missing_keys() { # 缺少部分鍵時 status 仍正常結束，只列出存在的鍵
  make_wrapper
  pdel WINEMSYNC; pdel METAL_HUD; pdel "Program Name and Path"
  ws status
  assert_status 0
  assert_out_not_contains "WINEMSYNC"
  assert_out_not_contains "METAL_HUD"
  assert_out_contains "佔用空間"
  assert_no_key WINEMSYNC
  assert_no_key METAL_HUD
}

t_status_engine_version() { # 有 wine/version 檔時顯示引擎版本
  make_wrapper
  mkdir -p "$WRAPPER/Contents/SharedSupport/wine"
  echo "wine-10.0 (Sikarugir)" > "$WRAPPER/Contents/SharedSupport/wine/version"
  ws status
  assert_stdout_line "引擎 +wine-10\.0 \(Sikarugir\)"
}

# ── run ────────────────────────────────────────────────────────────────
t_run_clears_program_flags() { # run 清空 Program Flags 並用 open 開啟 wrapper
  make_wrapper
  pset_str "Program Flags" "-applaunch 3241660"
  ws run
  assert_status 0
  assert_key "Program Flags" ""
  assert_eq "$WRAPPER" "$(cat "$SB/log/open.log" 2>/dev/null)" "open 的參數"
  assert_out_contains "已啟動 Windows 版 Steam"
}

t_run_without_program_flags_key() { # 沒有 Program Flags 鍵時 run 不新增它，仍會啟動
  make_wrapper
  pdel "Program Flags"
  ws run
  assert_status 0
  assert_no_key "Program Flags"
  assert_eq "$WRAPPER" "$(cat "$SB/log/open.log" 2>/dev/null)" "open 的參數"
}

t_run_requires_steam_exe() { # wrapper 裡沒有 Steam.exe 時 run 拒絕啟動
  make_wrapper
  rm "$WRAPPER/Contents/drive_c/Program Files (x86)/Steam/Steam.exe"
  ws run
  assert_status_nonzero
  assert_out_contains "還沒有 Steam"
  assert_not_exists "$SB/log/open.log"
}

t_run_requires_rosetta() { # 沒有 Rosetta 時 run 拒絕啟動
  make_wrapper
  touch "$SB/state/no_rosetta"
  ws run
  assert_status_nonzero
  assert_out_contains "Rosetta 2 未安裝"
  assert_not_exists "$SB/log/open.log"
}

t_run_quits_native_steam_with_yes() { # --yes run：macOS 版 Steam 執行中時先叫它結束
  make_wrapper
  touch "$SB/state/native_steam"
  ws --yes run
  assert_status 0
  grep -qF 'tell application "Steam" to quit' "$SB/log/osascript.log" 2>/dev/null \
    || _fail "應以 osascript 結束 macOS 版 Steam"
  assert_exists "$SB/log/open.log"
}

# ── play ───────────────────────────────────────────────────────────────
t_play_repo() { # play repo：後端 dxmt、MSync 1、Program Flags 帶 App ID，並啟動
  make_wrapper
  ws play repo
  assert_status 0
  assert_backend_keys 0 1 0
  assert_key WINEMSYNC 1
  assert_key "Program Flags" "-applaunch 3241660"
  assert_eq "$WRAPPER" "$(cat "$SB/log/open.log" 2>/dev/null)" "open 的參數"
  grep -qx WSS-wineserverkill "$SB/log/sikarugir.log" 2>/dev/null || _fail "套用設定前應結束 wineserver"
  assert_out_contains "App ID 3241660"
  assert_out_contains "winsteam play repo --backend d3dmetal"   # BACKEND_ALT 提示
}

t_play_mimesis() { # play mimesis：後端 dxmt（與 repo 相同），Program Flags 帶 App ID
  make_wrapper
  ws play mimesis
  assert_status 0
  assert_backend_keys 0 1 0
  assert_key "Program Flags" "-applaunch 2827200"
  assert_out_contains "winsteam play mimesis --backend d3dmetal"   # BACKEND_ALT 提示
}

t_play_switch_games_no_restart() { # repo 與 mimesis 設定相同：玩完一款換另一款不需要重啟 Wine
  make_wrapper
  ws play repo
  assert_status 0
  rm -f "$SB/log/sikarugir.log"
  : > "$SB/state/wineserver_running"
  ws play mimesis
  assert_status 0
  assert_not_exists "$SB/log/sikarugir.log"
  assert_out_contains "不需要重新啟動"
}

t_play_case_insensitive() { # play 的遊戲名稱不分大小寫
  make_wrapper
  ws play REPO
  assert_status 0
  assert_key "Program Flags" "-applaunch 3241660"
}

_apply_repo_settings() { # 把模擬 wrapper 設成 repo 設定檔要的樣子
  pset_int D3DMETAL 0; pset_int DXMT 1; pset_int DXVK 0; pset_int WINEMSYNC 1
}

t_play_already_applied() { # 設定已符合且 Steam 沒在跑：不結束 wineserver，照常帶 App ID 啟動
  make_wrapper
  _apply_repo_settings
  ws play repo
  assert_status 0
  assert_not_exists "$SB/log/sikarugir.log"
  assert_key "Program Flags" "-applaunch 3241660"
  assert_eq "$WRAPPER" "$(cat "$SB/log/open.log" 2>/dev/null)" "open 的參數"
  assert_out_contains "不需要重新啟動"
}

t_play_already_applied_steam_running() { # 設定已符合且 Steam 正在跑：完全不動它，只叫到前面
  make_wrapper
  _apply_repo_settings
  : > "$SB/state/wrapper_running"
  ws play repo
  assert_status 0
  assert_not_exists "$SB/log/sikarugir.log"
  assert_key "Program Flags" "-old-flag"
  assert_out_contains "Steam 已經在執行"
}

t_play_launcher_gone_but_wine_running() { # 啟動器已結束但 wineserver 還在（Steam 自己重啟過）：仍視為執行中，不動它
  make_wrapper
  _apply_repo_settings
  : > "$SB/state/wineserver_running"
  ws play repo
  assert_status 0
  assert_not_exists "$SB/log/sikarugir.log"
  assert_key "Program Flags" "-old-flag"
  assert_out_contains "Steam 已經在執行"
}

t_state_running_when_only_wineserver() { # state 的 running 在只有 wineserver 時也是 1
  make_wrapper
  : > "$SB/state/wineserver_running"
  ws state
  assert_stdout_line 'running=1'
}

t_play_change_needed_steam_running() { # 設定不同且 Steam 正在跑：先警告，再結束 wineserver 並套用
  make_wrapper
  : > "$SB/state/wrapper_running"
  ws play repo
  assert_status 0
  assert_out_contains "需要重新啟動 Steam"
  grep -qx WSS-wineserverkill "$SB/log/sikarugir.log" 2>/dev/null || _fail "應結束 wineserver"
  assert_backend_keys 0 1 0
}

t_backend_same_no_kill() { # backend 指定的就是目前的後端：不結束 wineserver、不改 Info.plist
  make_wrapper
  _apply_repo_settings
  before="$(plist_sum)"
  ws backend dxmt
  assert_status 0
  assert_out_contains "沒有變更"
  assert_not_exists "$SB/log/sikarugir.log"
  assert_eq "$before" "$(plist_sum)" "Info.plist 不應變更"
}

t_play_backend_override() { # play repo --backend dxvk：覆寫設定檔的後端
  make_wrapper
  ws play repo --backend dxvk
  assert_status 0
  assert_backend_keys 0 0 1
  assert_key "Program Flags" "-applaunch 3241660"
  assert_out_not_contains "換另一個後端試試"
}

t_play_backend_override_d3dmetal() { # play repo --backend d3dmetal：也會把 D9VK 與 CNC_DDRAW 歸零
  make_wrapper
  ws play repo --backend d3dmetal
  assert_status 0
  assert_backend_keys 1 0 0
  assert_key D9VK 0
  assert_key CNC_DDRAW 0
}

t_play_backend_override_invalid() { # play --backend 不認得的值：報錯，不啟動、不寫 Program Flags
  make_wrapper
  ws play repo --backend vulkan
  assert_status_nonzero
  assert_out_contains "不認得的後端：vulkan"
  assert_key "Program Flags" "-old-flag"
  assert_backend_keys 1 1 1
  assert_not_exists "$SB/log/open.log"
}

t_play_backend_missing_value() { # play --backend 後面沒有值
  make_wrapper
  ws play repo --backend
  assert_status_nonzero
  assert_out_contains "--backend 後面要接後端名稱"
  assert_not_exists "$SB/log/open.log"
}

t_play_unknown_arg() { # play 不認得的參數
  make_wrapper
  ws play repo --fast
  assert_status_nonzero
  assert_out_contains "不認得的參數：--fast"
  assert_not_exists "$SB/log/open.log"
}

t_play_unknown_game() { # play 沒有設定檔的遊戲
  make_wrapper
  ws play halflife3
  assert_status_nonzero
  assert_out_contains "沒有「halflife3」的設定檔"
  assert_not_exists "$SB/log/open.log"
}

t_play_requires_name() { # play 沒給遊戲名稱
  make_wrapper
  ws play
  assert_status_nonzero
  assert_out_contains "用法：winsteam play"
}

t_play_without_appid() { # 設定檔沒有 APPID：不寫 Program Flags，只開 Steam
  make_wrapper
  printf 'NAME="No ID"\nBACKEND=dxvk\n' > "$SB/profiles/noid.conf"
  ws play noid
  assert_status 0
  assert_key "Program Flags" "-old-flag"
  assert_backend_keys 0 0 1
  assert_out_contains "請在收藏庫裡按「執行」開啟 No ID"
  assert_exists "$SB/log/open.log"
}

t_play_without_program_flags_key() { # Info.plist 沒有 Program Flags：不新增鍵，只開 Steam
  make_wrapper
  pdel "Program Flags"
  ws play repo
  assert_status 0
  assert_no_key "Program Flags"
  assert_out_contains "請在收藏庫裡按「執行」"
  assert_exists "$SB/log/open.log"
}

t_play_missing_msync_uses_esync() { # 沒有 WINEMSYNC 時改寫 WINEESYNC，且不新增 WINEMSYNC
  make_wrapper
  pdel WINEMSYNC
  ws play repo
  assert_status 0
  assert_no_key WINEMSYNC
  assert_key WINEESYNC 1
  assert_out_contains "ESync：1"
}

t_play_missing_both_sync_keys() { # WINEMSYNC 與 WINEESYNC 都沒有時略過並警告，不新增鍵
  make_wrapper
  pdel WINEMSYNC; pdel WINEESYNC
  ws play repo
  assert_status 0
  assert_no_key WINEMSYNC
  assert_no_key WINEESYNC
  assert_out_contains "沒有 MSync / ESync 鍵，略過"
  assert_key "Program Flags" "-applaunch 3241660"
}

t_play_dry_run() { # --dry-run play 不改 Info.plist、不啟動
  make_wrapper
  local before; before="$(plist_sum)"
  ws --dry-run play repo
  assert_status 0
  assert_eq "$before" "$(plist_sum)" "Info.plist 雜湊"
  assert_not_exists "$SB/log/open.log"
  assert_file_empty_or_missing "$SB/log/sikarugir.log" "dry-run 不應執行 wrapper"
}

# ── logs / kill ────────────────────────────────────────────────────────
t_logs_shows_tail() { # logs 顯示資料夾位置與兩個記錄檔的最後 15 行
  make_wrapper
  local dir="$WRAPPER/Contents/drive_c/Program Files (x86)/Steam/logs" i
  mkdir -p "$dir"
  for i in $(seq 1 20); do echo "boot $i"; done > "$dir/bootstrap_log.txt"
  printf 'conn a\nconn b\n' > "$dir/connection_log.txt"
  ws logs
  assert_status 0
  assert_out_contains "記錄檔資料夾：$dir"
  assert_stdout_line "boot 6"
  assert_stdout_line "boot 20"
  if grep -qx "boot 5" "$SB/out"; then _fail "只應顯示最後 15 行，卻出現 boot 5"; fi
  assert_stdout_line "conn b"
  assert_out_contains "bootstrap_log.txt（最後 15 行）"
}

t_logs_missing_dir() { # 還沒有記錄檔資料夾時報錯
  make_wrapper
  ws logs
  assert_status_nonzero
  assert_out_contains "還沒有記錄檔"
}

t_kill() { # kill 以 WSS-wineserverkill 呼叫 wrapper
  make_wrapper
  ws kill
  assert_status 0
  assert_eq "WSS-wineserverkill" "$(cat "$SB/log/sikarugir.log" 2>/dev/null)" "wrapper 收到的參數"
}

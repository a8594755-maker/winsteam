# install.sh：假的 HOME 與假的 curl（把本機打包的 tarball 寫到 -o 指定的路徑）

serve_tarball() { printf '%s' "${1:-$TARBALL_OK}" > "$SB/state/curl_tarball"; }

# 安裝完的結構是否正確
assert_installed() {
  local dest="$SB/home/.winsteam"
  assert_exists "$dest/bin/winsteam"
  [ -x "$dest/bin/winsteam" ] || _fail "$dest/bin/winsteam 應可執行"
  assert_exists "$dest/profiles/repo.conf"
  assert_exists "$dest/profiles/mimesis.conf"
  assert_exists "$dest/README.md"
  cmp -s "$dest/bin/winsteam" "$WINSTEAM" || _fail "安裝的 bin/winsteam 與原始檔不同"
}

t_install_success() { # curl | bash 成功：裝到 ~/.winsteam，連結放在 ~/.local/bin
  serve_tarball
  inst
  assert_status 0
  assert_installed
  local link="$SB/home/.local/bin/winsteam"
  [ -L "$link" ] || _fail "應建立 symlink：$link"
  assert_eq "$SB/home/.winsteam/bin/winsteam" "$(readlink "$link")" "symlink 目標"
  assert_out_contains "已安裝到 $SB/home/.winsteam"
  assert_out_contains "指令連結：$link"
  assert_out_contains "不在你的 PATH 裡"           # ~/.local/bin 不在測試的 PATH
  grep -qF "https://github.com/a8594755-maker/winsteam/archive/refs/heads/main.tar.gz" "$SB/log/curl.log" \
    || _fail "curl 應下載預設儲存庫的 main 分支：$(cat "$SB/log/curl.log")"
  assert_eq "" "$(ls -A "$SB/tmp")" "暫存目錄應在結束時清掉"
}

t_install_link_runs() { # 透過 symlink 執行安裝好的 winsteam：version 與 games 都能用
  serve_tarball
  inst
  assert_status 0 "安裝"
  local link="$SB/home/.local/bin/winsteam" out
  out="$(/usr/bin/env -i HOME="$SB/home" PATH=/usr/bin:/bin /bin/bash "$link" version 2>&1)"
  assert_eq "winsteam $(sed -n 's/^VERSION="\(.*\)"$/\1/p' "$WINSTEAM")" "$out" "透過連結執行 version"
  out="$(/usr/bin/env -i HOME="$SB/home" PATH=/usr/bin:/bin /bin/bash "$link" games 2>&1)"
  printf '%s\n' "$out" | grep -qE '^repo +' || _fail "透過連結執行 games 應找到 ~/.winsteam/profiles：$out"
}

t_install_twice() { # 重複安裝：成功、更新自己的檔案，保留使用者放在 ~/.winsteam 的其他東西
  serve_tarball
  inst
  assert_status 0 "第一次安裝"
  echo mine > "$SB/home/.winsteam/notes.txt"
  echo stale > "$SB/home/.winsteam/profiles/old.conf"
  echo stale > "$SB/home/.winsteam/bin/winsteam"
  inst
  assert_status 0 "第二次安裝"
  assert_installed
  assert_exists "$SB/home/.winsteam/notes.txt"
  assert_not_exists "$SB/home/.winsteam/profiles/old.conf"
  assert_eq "$SB/home/.winsteam/bin/winsteam" "$(readlink "$SB/home/.local/bin/winsteam")" "symlink 目標"
  assert_eq "" "$(ls -A "$SB/tmp")" "暫存目錄應在結束時清掉"
}

t_install_download_failure() { # 下載失敗：結束碼 1、stderr 有說明，什麼都沒裝
  inst
  assert_status 1
  assert_stderr_contains "下載失敗。請確認儲存庫 a8594755-maker/winsteam 存在且是公開的。"
  assert_not_exists "$SB/home/.winsteam"
  assert_not_exists "$SB/home/.local/bin/winsteam"
  assert_eq "" "$(ls -A "$SB/tmp")" "暫存目錄應在結束時清掉"
}

t_install_download_failure_keeps_existing() { # 已安裝後再次安裝但下載失敗：原本的安裝不受影響
  serve_tarball
  inst
  assert_status 0 "第一次安裝"
  rm "$SB/state/curl_tarball"
  inst
  assert_status 1 "下載失敗的第二次安裝"
  assert_installed
}

t_install_incomplete_tarball() { # 下載內容缺 bin/winsteam：報錯且不安裝
  serve_tarball "$TARBALL_BROKEN"
  inst
  assert_status 1
  assert_stderr_contains "找不到 bin/winsteam"
  assert_not_exists "$SB/home/.winsteam"
}

t_install_custom_repo_branch() { # WINSTEAM_REPO / WINSTEAM_BRANCH 改變下載網址
  serve_tarball
  inst WINSTEAM_REPO=someone/fork WINSTEAM_BRANCH=dev
  assert_status 0
  grep -qF "https://github.com/someone/fork/archive/refs/heads/dev.tar.gz" "$SB/log/curl.log" \
    || _fail "下載網址不對：$(cat "$SB/log/curl.log")"
  assert_out_contains "someone/fork@dev"
}

t_install_rejects_dest_outside_home() { # WINSTEAM_HOME 不在家目錄底下：拒絕，且不下載
  serve_tarball
  inst WINSTEAM_HOME="$SB/elsewhere"
  assert_status 1
  assert_stderr_contains "WINSTEAM_HOME 必須在家目錄底下"
  assert_not_exists "$SB/elsewhere"
  assert_file_empty_or_missing "$SB/log/curl.log" "不應開始下載"
}

t_install_uses_writable_brew_bin() { # 有 Homebrew 且其 bin 可寫入時，連結放在那裡
  serve_tarball
  fake_brew "$SB/brew"
  INST_PATH="$SB/fakebin:$SB/brew/bin:/usr/bin:/bin:/usr/sbin:/sbin" inst
  assert_status 0
  [ -L "$SB/brew/bin/winsteam" ] || _fail "應在 $SB/brew/bin 建立 symlink"
  assert_not_exists "$SB/home/.local/bin/winsteam"
  assert_out_not_contains "不在你的 PATH 裡"
}

t_install_rejects_intel() { # 不是 Apple Silicon：拒絕安裝
  serve_tarball
  echo x86_64 > "$SB/state/uname_m"
  inst
  assert_status 1
  assert_stderr_contains "只支援 Apple Silicon"
  assert_not_exists "$SB/home/.winsteam"
}

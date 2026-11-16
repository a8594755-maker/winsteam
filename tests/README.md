# winsteam 測試

純 bash、零相依，在 macOS 內建的 `/bin/bash` 3.2 下執行：

```bash
tests/run.sh                         # 全部
tests/run.sh play                    # 只跑名稱含 play 的案例
TEST_LANG=zh_TW.UTF-8 tests/run.sh   # 全部案例改用指定語系（預設 C）
KEEP_SANDBOX=1 tests/run.sh          # 保留暫存目錄方便除錯
```

有任何案例失敗時結束碼為 1。

## 隔離方式

- 每個案例都有自己的暫存沙盒，跑完整個刪掉。
- 被測程式用 `env -i` 啟動，`HOME`、`WINSTEAM_WRAPPER`、`WINSTEAM_CACHE`、`WINSTEAM_PROFILES`、`TMPDIR` 全部指向沙盒；`ws` / `inst` 在執行前會檢查路徑，不在沙盒裡就中止。
- `PATH` 只有沙盒的假指令目錄加上 `/usr/bin:/bin:/usr/sbin:/sbin`，所以不會用到真的 Homebrew。假指令包括 `arch`（Rosetta）、`pgrep`、`open`、`osascript`、`softwareupdate`、`sleep`、`uname`、`sw_vers`、`df`、`curl`，需要時再加上 `brew`。它們都會把收到的參數記在 `$SB/log/`。
- 模擬 wrapper 是 `$SB/Steam.app`：假的 `Contents/MacOS/Sikarugir` 會記下參數，另有手寫的 `Info.plist`，以及空的 `Steam.exe`。
- 如果執行時有終端機，會用 `/usr/bin/perl` 的 `setsid` 讓被測程式脫離它，所以 `confirm` 不會停下來等人輸入。

## 檔案

| 檔案 | 內容 |
| --- | --- |
| `run.sh` | 執行器：找出 `test_*.sh` 裡的 `t_*` 函式，依定義順序執行 |
| `lib.sh` | 斷言、沙盒、假指令、模擬 wrapper |
| `test_basic.sh` | help、version、games、不認得的指令、`--dry-run setup` |
| `test_wrapper.sh` | backend、hud、status、run、play、logs、kill、鍵不存在 |
| `test_safety.sh` | uninstall 的確認與路徑檢查、遊戲名稱的路徑穿越 |
| `test_install.sh` | install.sh：成功、重複安裝、下載失敗等 |
| `test_locale.sh` | 在 UTF-8 語系（使用者終端機的預設）下跑主要指令 |

新增案例：在任一個 `test_*.sh` 加上 `t_名稱() { # 說明`，函式裡用 `ws …` / `inst` 執行，再用 `assert_*` 檢查。

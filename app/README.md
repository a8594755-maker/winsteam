# WinSteam（macOS App）

`bin/winsteam` 的原生 SwiftUI 圖形介面，讓不熟終端機的人也能安裝、啟動與調校 Windows 版 Steam。需要 Apple Silicon 與 macOS 14 以上，不使用任何第三方套件，App 本身不發任何網路請求（下載都是 CLI 做的）。所有動作都是呼叫 App 裡附帶的那份 `winsteam`，輸出即時顯示在視窗下方的面板。

**編譯**：在 `app/` 目錄執行 `swift build -c release`（需要 Xcode 或 Command Line Tools 內附的 Swift 5.10 以上）。

**組成 App**：在儲存庫根目錄執行 `app/scripts/bundle.sh`。它會編譯、把 `bin/winsteam` 與 `profiles/` 複製進 `Contents/Resources/`、寫入 `Info.plist`（bundle id `io.github.winsteam.app`），最後做 ad-hoc 簽章，產出 `app/build/WinSteam.app`。因為沒有經過 Apple 公證，從別台 Mac 下載的版本第一次開啟時要按右鍵 →「打開」。

**執行**：`open app/build/WinSteam.app`。App 和 CLI 一樣尊重 `WINSTEAM_WRAPPER`、`WINSTEAM_CACHE`、`WINSTEAM_PROFILES` 環境變數；開發時另外可以用 `WINSTEAM_CLI` 指定要呼叫的 `winsteam`。想在不碰真實安裝的情況下試介面，可以把 wrapper 指到一個假的資料夾，例如：

```bash
open --env WINSTEAM_WRAPPER=/tmp/fake/Steam.app --env WINSTEAM_CACHE=/tmp/fake/cache app/build/WinSteam.app
```

安裝畫面的「預演一次」會執行 `winsteam --dry-run setup`，只顯示會做什麼、不改動任何東西。Rosetta 2 的授權條款不會被自動同意：App 偵測到 Apple 的提示時會跳出視窗，只有使用者按下「我同意」才把 `A` 送進安裝程式；也可以改在「終端機」裡自己完成。

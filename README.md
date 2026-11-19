# winsteam

在 Apple Silicon 的 Mac 上跑 **Windows 版 Steam** 和 Windows 專屬遊戲的命令列工具。

一個指令裝好 Rosetta 2、Sikarugir（Wine wrapper）、Wine 引擎和 Windows 版 Steam，再用內建的遊戲設定檔切換圖形後端與同步設定。免費，不需要 CrossOver 授權。

> **狀態：v0.1.0，早期版本。** 已在一台 M2 MacBook Air（16 GB、macOS 27.0.1）上實機驗證：安裝流程每個步驟都成功，Steam 可以登入、下載遊戲，R.E.P.O. 與 MIMESIS 都能啟動遊玩。尚未驗證的：在一台全新的 Mac 上不中斷地從頭跑完 `setup`、其他機型與 macOS 版本、實際 FPS。

## 需求

- Apple Silicon 的 Mac（M1 以後）
- macOS 14 到 27（macOS 28 起 Apple 不再提供一般用途的 Rosetta 2，這個做法會失效）
- [Homebrew](https://brew.sh)
- 至少 12 GB 可用空間
- **遊戲要已經在你自己的 Steam 帳號裡**

## 安裝

```bash
curl -fsSL https://raw.githubusercontent.com/a8594755-maker/winsteam/main/install.sh | bash
```

安裝腳本會做三件事，都不需要 `sudo`：

- 把命令列工具放到 `~/.winsteam`，並在 PATH 上建立 `winsteam` 連結。
- 把圖形介面 **WinSteam.app** 放到 `~/Applications`（從最新的 [Release](https://github.com/a8594755-maker/winsteam/releases/latest) 下載，會比對檢查碼並驗證簽章）。不想要圖形介面的話，在指令前面加 `WINSTEAM_NO_APP=1`。

裝好後有兩種用法，擇一即可。

**用圖形介面：** 打開 WinSteam，按「安裝」。

```bash
open ~/Applications/WinSteam.app
```

**用命令列：**

```bash
winsteam doctor
```

```bash
winsteam setup
```

`setup` 會自動下載、組裝、安裝 Steam 並把它打開。只有兩個地方需要你自己動手：

1. **Rosetta 2**（只有還沒裝過的 Mac）：閱讀並同意 Apple 的授權條款。
2. **登入 Steam**：在跳出的 Steam 視窗輸入你自己的帳號密碼。

全程不需要打開 Sikarugir 自己的設定視窗。

## 使用

| 指令 | 作用 |
|---|---|
| `winsteam doctor` | 檢查這台 Mac 是否符合條件、目前裝到哪一步 |
| `winsteam setup` | 一次裝好所有東西；可以重複執行，做過的步驟會略過 |
| `winsteam run` | 啟動 Windows 版 Steam |
| `winsteam games` | 列出內建的遊戲設定檔 |
| `winsteam play repo` | 套用該遊戲的設定並啟動 |
| `winsteam play repo --backend d3dmetal` | 這次改用指定的圖形後端 |
| `winsteam backend dxmt` | 切換整個 wrapper 的圖形後端 |
| `winsteam hud on` | 顯示 Metal 效能 HUD（FPS、畫格時間） |
| `winsteam status` | 顯示目前的設定 |
| `winsteam logs` | 顯示 Steam 記錄檔 |
| `winsteam kill` | 強制結束卡住的 Wine 程序 |
| `winsteam prefetch` | 用較快的官方主機預先下載 Steam 用戶端更新（`setup` 會自動做） |
| `winsteam state` | 輸出機器可讀的狀態，給圖形介面使用 |
| `winsteam uninstall` | 刪除 wrapper，包含裡面的 Steam 和遊戲 |

任何指令前面加 `--dry-run` 都只會印出要做的事，不會真的執行。

## 支援的遊戲

| 指令名稱 | 遊戲 | 預設後端 | 狀況 |
|---|---|---|---|
| `repo` | R.E.P.O. | DXMT | 實測可玩（M2 Air，macOS 27）。CodeWeavers 評「Runs Great」、ProtonDB Platinum |
| `mimesis` | MIMESIS | DXMT | 實測可玩（M2 Air，macOS 27），麥克風可用。ProtonDB Gold |

兩款用同一個圖形後端，所以玩完一款換另一款不需要重新啟動 Steam。

沒有設定檔的遊戲也能玩：`winsteam run` 開 Steam 後照常安裝、執行即可。使用核心層反作弊的遊戲（例如 Vanguard）無法在任何 Wine 方案下執行。

### 新增遊戲

在 `profiles/` 放一個 `<名稱>.conf`：

```ini
NAME="遊戲顯示名稱"
APPID=1234567
BACKEND=dxmt
BACKEND_ALT=d3dmetal
MSYNC=1
TIPS="第一條提醒|第二條提醒"
```

`APPID` 是 Steam 商店網址裡的數字。歡迎把測過的設定檔用 PR 送回來。

## 下載為什麼這麼快

第一次安裝要下載約 730 MB。其中兩個來源在某些網路上單一連線只有每秒 0.1 到 0.4 MB，所以 winsteam 做了兩件事：

- **Steam 用戶端更新（約 480 MB）**：Steam 自己寫死的下載主機可能很慢。`setup` 會先從 Valve 放在 Akamai / Cloudflare 的同一批檔案抓好，逐一比對大小與 SHA-256 後放進 Steam 的 `package` 資料夾，Steam 核對後直接採用。
- **Wine 引擎與 wrapper 範本（約 250 MB，來自 GitHub）**：切成 8 段同時下載再接起來，並比對內建的 SHA-256。設 `WINSTEAM_CONNECTIONS=1` 可以關掉。

任何一步失敗都會自動退回原本的下載方式。

## 圖形介面

WinSteam.app 是原生的 macOS App，把上面的指令包成按鈕：還沒安裝時只有一顆「安裝」，裝好並登入 Steam 後顯示遊戲清單，每款遊戲依狀態顯示「到 Steam 安裝」、「下載中」或「開始遊戲」。圖形後端、記錄、移除等選項收在右上角的「進階」。

安裝腳本會自動把它放到 `~/Applications`。它內含自己的一份命令列工具，所以單獨使用也可以。

**如果你是從 Releases 頁面用瀏覽器手動下載 `WinSteam.zip`：** 這個 App 只有 ad-hoc 簽章，沒有經過 Apple 公證，第一次打開時 macOS 會說無法驗證開發者。到「系統設定 → 隱私權與安全性」往下捲，按「仍要打開」即可。用上面的安裝指令則不會遇到這個提示。

原始碼在 `app/`，自行編譯的方式見 [app/README.md](app/README.md)。

## 效能調校

- **圖形後端**是影響最大的選項。DirectX 11 的遊戲通常 DXMT 比較快；DirectX 12 只有 D3DMetal 能跑。用 `winsteam hud on` 看 FPS，兩個都試。
- **解析度**：Wine 預設不使用 Retina 模式，遊戲看到的是較低的邏輯解析度，這對效能有利。在遊戲內選 1440 × 900 或更低。
- **Steam 設定**：關掉「在網頁檢視中啟用 GPU 加速算繪」和遊戲內嵌介面，這兩個在 Wine 下常當掉。
- **散熱**：MacBook Air 沒有風扇，插電玩，墊高或用散熱墊。
- **記憶體**：CPU 和 GPU 共用記憶體，遊戲前關掉瀏覽器等大型程式。

## 疑難排解

| 症狀 | 原因與處理 |
|---|---|
| Steam 啟動時 `Unexpected Transport Error (0x3008)` | 引擎不對。確認 `winsteam status` 顯示的是 `sikarugir 10.0` 系列 |
| 登入成功後立刻顯示 NO CONNECTION | 同一個帳號在 macOS 版 Steam 也登入了。關掉 macOS 版，`winsteam kill` 後再 `winsteam run` |
| 改了設定沒有反應 | 舊的 Wine 程序還在。`winsteam kill` 後重新啟動 |
| Steam 的「重新啟動」按鈕讓設定跑掉 | 那個按鈕會繞過 wrapper。改用「離開 Steam」，再 `winsteam run` |
| 第一次啟動視窗像當掉 | 正在下載用戶端更新，等幾分鐘 |

## 限制與風險

- **沒有人保固。** Steam 更新、遊戲更新、macOS 更新或引擎更新都可能讓它壞掉。需要長期穩定的方案請考慮付費的 [CrossOver](https://www.codeweavers.com/crossover)。
- **Sikarugir 沒有經過 Apple 公證**（ad-hoc 簽章），Homebrew 安裝時會移除隔離標記。等於你信任的是該專案而不是 Apple。
- macOS 版 Steam 幫不上忙：Windows 專屬遊戲沒有 macOS 版本可下載，wrapper 裡的 Steam 是獨立的登入和獨立的遊戲下載。
- 這個工具不處理購買、DRM、反作弊或區域限制。

## 移除

```bash
winsteam uninstall --all
```

```bash
rm -rf ~/.winsteam "$(command -v winsteam)"
```

Sikarugir Creator 和 Rosetta 2 會留著。要移除 Creator：`brew uninstall --cask sikarugir`。

## 致謝

- [Sikarugir](https://github.com/Sikarugir-App/Sikarugir)，由 Gcenx 維護。
- 安裝步驟參考 [mirpo/windows-steam-on-apple-silicon](https://github.com/mirpo/windows-steam-on-apple-silicon)（CC0）。
- 相容性資料來自 [CodeWeavers](https://www.codeweavers.com/compatibility) 與 [ProtonDB](https://www.protondb.com)。

winsteam 與 Valve、Steam、CodeWeavers 或任何遊戲開發商沒有關係。

## 授權

winsteam 本身以 [MIT 授權](LICENSE)釋出。

這份授權只涵蓋這個儲存庫裡的檔案。winsteam 在安裝過程中下載的 Sikarugir、Wine、Rosetta 2、Steam 與各款遊戲，各自適用它們原本的授權與使用條款。

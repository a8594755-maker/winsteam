# mac-steam-windows-games

在 Apple Silicon MacBook 上，用轉譯層跑 Windows 版 Steam 與 Windows 專屬遊戲的設定專案。

目標遊戲：

| 遊戲 | Steam App ID | 狀態 |
|---|---|---|
| R.E.P.O. | 3241660 | 尚未安裝 |
| MIMESIS | 2827200 | 尚未安裝 |

## 這台機器（2026-11-15 檢查）

- MacBook Air M2（Mac14,2），8 核心（4P + 4E），無風扇
- 16 GB 記憶體，內建螢幕 2560 × 1664
- macOS 27.0.1，Metal 4
- 可用磁碟空間約 50 GB（已用 89%）
- Rosetta 2：**未安裝**（目前所有轉譯方案都需要）
- 已安裝：macOS 版 Steam（沒有遊戲）、Sikarugir Creator 1.0.1（沒有引擎、沒有 wrapper）、Homebrew

## 可行性評估

### R.E.P.O.：可行性高

- CodeWeavers 相容性資料庫評為「Runs Great」（CrossOver 26.2.0、macOS 26）。
- ProtonDB 為 Platinum（392 份回報），代表在 Wine 系轉譯下沒有反作弊阻擋。
- 官方最低需求 GTX 970、建議 GTX 1070，容量 1 GB。
- 已知問題：在 CrossOver 下主選單的「Join Game」按鈕有時沒反應。

### MIMESIS：不確定，要實測

- ProtonDB 為 Gold、近期趨勢 Platinum（19 份回報），所以 Wine 系轉譯在 Linux 上跑得起來。
- 但 CodeWeavers 對 Mac 的評級是「Installs, Will Not Run」（只有一筆測試，版本是較舊的 CrossOver 26.0.0）。失敗原因沒查到。
- 官方最低需求 GTX 1050 Ti、建議 GTX 1660 Super + 16 GB RAM，容量 4 GB，必須有麥克風。
- 比 R.E.P.O. 吃效能，M2 Air 就算跑得起來也要降解析度與畫質。

## 方案比較

| 方案 | 費用 | 優點 | 缺點 |
|---|---|---|---|
| Sikarugir + D3DMetal / DXMT | 免費 | Creator 已安裝；有人在同款 M2 Air 16 GB 上測通 Windows Steam | Steam 更新容易弄壞；沒有人負責修；尚無 macOS 27 的實測回報 |
| CrossOver 26.3 | 付費，14 天試用 | 對 Steam 的支援最穩；內建 D3DMetal 3.0 與 DXMT | 要花錢 |
| Parallels（Windows on ARM 虛擬機） | 付費 | 相容性走另一條路 | 16 GB 要分給虛擬機，圖形效能較差 |

## 效能優化方向

1. 逐款遊戲比較圖形後端：DXMT（DX10/11）對 D3DMetal（DX11/12）。
2. 開啟 MSync / ESync。
3. 關閉 Retina 高解析模式，改以 1440 × 900 左右輸出。
4. Steam 內關閉「網頁檢視使用 GPU 加速」與遊戲內 Overlay。
5. 插電遊玩；這台沒有風扇，長時間會降頻，散熱墊有幫助。
6. 遊戲前關掉其他吃記憶體的程式（16 GB 是 CPU 與 GPU 共用）。

## 注意事項

- 兩款遊戲都要先在自己的 Steam 帳號擁有。
- Rosetta 2 在 macOS 27 仍可完整使用；依 Apple 公布的規劃，macOS 28 起不再支援這種用途，屆時要改用 CrossOver 27（內建 FEX 轉譯）這類不靠 Rosetta 的方案。

## 參考資料

- [CodeWeavers：R.E.P.O.](https://www.codeweavers.com/compatibility/crossover/repo)
- [CodeWeavers：MIMESIS](https://www.codeweavers.com/compatibility/crossover/mimesis)
- [windows-steam-on-apple-silicon（M2 Air 實測指南）](https://github.com/mirpo/windows-steam-on-apple-silicon)
- [Sikarugir](https://github.com/Sikarugir-App/Sikarugir)
- [AppleInsider：CrossOver 的 Apple Silicon 原生版測試中](https://appleinsider.com/articles/26/07/31/first-apple-silicon-native-crossover-build-in-testing-as-rosettas-end-nears)

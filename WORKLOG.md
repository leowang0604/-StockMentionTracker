# Work Log

## 2026-04-02 (commit a015a10)

### 背景
本次工作主要處理兩大類問題：**假陽性偵測（false positive）**過多，以及**族群分類（sector）**不準確。

---

### 一、假陽性修正（scanner/main.py）

#### 1. 移除 EDGAR 動態股票的 ticker 識別
**問題**：S&P 500 / SEC EDGAR 的動態美股之前是以 ticker 加入 stock_dict，導致 BBU、L、ASIC、EP、SR 等短 ticker 誤匹配中文財經逐字稿中的隨機詞。
**修法**：EDGAR 股票（sector = "其他"）完全不加入 stock_dict。S&P 500 股票改用全名識別（見下）。

#### 2. 通用年份代碼規則
**問題**：股票代碼形如年份（2008、2024、2025…）的台股，會誤匹配「從2024年開始」、「2025年之前」等日曆年描述。過去只手動加了 2008/2009/2025 到 CONTEXT_REQUIRED，無法 scale。
**修法**：在 `recognize_stocks()` 加通用規則：code 符合 `(19|20)\d{2}` 且不在 CONTEXT_REQUIRED 的，自動要求 context 中出現公司名。刪除舊的手動條目（2008/2009/2025）。

#### 3. CONTEXT_REQUIRED 新增條目
| Code | 公司 | 誤判原因 |
|------|------|---------|
| ASIC | Ategrity Specialty Insurance | 「ASIC」在中文逐字稿 = AI 晶片加速器術語 |
| 1565 | 精華光學 | 「精華」是日常用語（精華片段、精華時段）|
| 1109 | 信大水泥 | 「信大」出現在「相信大家」等句子中 |
| 6923 | 中台 | 「中台」出現在「情況中台股跌不下去」（情況中 + 台股）|

#### 4. 新增 hardcoded 美股
**網路安全族群**（新增族群 "網路安全"）：
- Cloudflare (NET)、Palo Alto Networks (PANW)、CrowdStrike (CRWD)
- Zscaler (ZS)、Fortinet (FTNT)、Okta (OKTA)

**企業軟體族群**：
- Adobe (ADBE)

#### 5. S&P 500 動態股票改用名稱識別
**修法**：對有真實 GICS sector 的 S&P 500 股票，改以**公司全名**（≥5 字元）+ 剝除 Inc./Corp. 的短名加入 stock_dict；ticker 只在 ≥4 字元時才加。
**效果**：
- `ADBE` → 認得（4 字元 ticker ✓）
- `"Adobe"` → 認得（全名剝除 "Inc." ✓）
- `NET`、`L`、`EP` → 不加 ticker，只靠全名識別

---

### 二、台股族群從 TWSE API 自動取得（scanner/main.py）

**問題**：台股 sector 只靠手動維護的 `TW_STOCK_SECTORS`，大部分股票 sector 為空，造成「同族群個股」顯示大量不相關股票。
**修法**：
1. 新增 `_TW_INDUSTRY_CODE_MAP`，對應 TWSE 官方產業別代碼（01–31）到中文族群名
2. `_fetch()` 抓取 `IndustryCategoryCode` 欄位
3. `build_stock_dict()` 優先用 `TW_STOCK_SECTORS`（手動精細分類），無資料再 fallback 到 TWSE 官方產業別

---

### 三、iOS 修正（StockDetailView.swift）

#### 1. 同族群個股排除「其他」
`sectorPeers` 加 `sector != "其他"` guard，避免所有「其他」股票擠在同一個族群。

#### 2. Highlight 修正
`shortNameTerms()` 新增：
- **英文後綴剝除**：`"Adobe Inc."` → `"Adobe"`、`"Cloudflare, Inc."` → `"Cloudflare"`
- **中文後綴剝除**：`"南俊國際"` → `"南俊"`、`"股份有限公司"` 等逐層剝除

---

### 待確認（測試中）
- TWSE API 是否真的回傳 `IndustryCategoryCode` 欄位
- S&P 500 全名識別有無誤判（如 "Target"、"Home Depot" 等常見英文詞）
- 假陽性（ASIC、BBU、L）是否完全消失

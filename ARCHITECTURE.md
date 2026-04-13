# StockMentionTracker — 專案架構報告

*生成日期：2026-04-08，最後更新：2026-04-08*

---

## 一、總覽

本專案分為兩個獨立系統：

1. **Scanner（Python）** — 跑在 GitHub Actions，抓取並分析 YouTube/Podcast 內容，輸出 JSON 資料。
2. **iOS App（SwiftUI）** — 讀取 Scanner 輸出的 JSON，只讀不寫，呈現股票提及排行榜。

資料流向：`GitHub Actions → scanner/main.py → data/latest.json → GitHub Raw URL → iOS App`

---

## 二、目錄結構

```
StockMentionTracker/
├── scanner/
│   ├── main.py              # 核心掃描邏輯（唯一 Python 檔）
│   └── sources.json         # 頻道清單（由 iOS App 管理，Scanner 唯讀）
├── data/
│   ├── latest.json          # 掃描結果（Scanner 輸出，iOS App 讀取）
│   ├── stocks.json          # 台股清單快取
│   ├── learned_aliases.json # Gemini 自動學習的 Whisper 錯字對應（auto-generated）
│   └── gemini_usage.json    # Gemini API 每日使用量追蹤（auto-generated）
├── .github/
│   └── workflows/
│       └── daily_scan.yml   # GitHub Actions 工作流程
└── StockMentionTracker/     # iOS App (Xcode project)
    ├── Models/
    │   ├── AppState.swift
    │   ├── DataModels.swift
    │   └── DataService.swift
    ├── Views/
    │   ├── Ranking/
    │   │   ├── RankingView.swift
    │   │   ├── StockDetailView.swift
    │   │   └── SectorRankingView.swift
    │   ├── Trend/
    │   │   └── TrendView.swift
    │   ├── Radar/
    │   │   └── RadarView.swift
    │   ├── Sources/
    │   │   ├── SourceManagementView.swift
    │   │   ├── ChannelDetailView.swift
    │   │   ├── AddYouTubeView.swift
    │   │   └── AddPodcastView.swift
    │   ├── ContentList/
    │   │   └── ContentListView.swift
    │   └── Settings/
    │       └── SettingsView.swift
    ├── MainTabView.swift
    ├── WORKLOG.md
    └── ARCHITECTURE.md      # 本文件
```

---

## 三、Scanner（scanner/main.py）

### 3.1 主要資料結構

```python
ALIASES: dict[str, str]          # keyword → stock_code（含 Whisper 錯字）
WHISPER_ALIAS_KEYWORDS: set[str] # 已知 Whisper 錯字關鍵字（送 Gemini 驗證）
CONTEXT_REQUIRED: dict[str, list[str]]  # code → 必須出現的上下文詞（預過濾）
CONTEXT_FORBIDDEN: dict[str, list[str]] # code → 禁止出現的上下文詞
KEYWORD_PATTERN_OVERRIDE: dict[str, str] # keyword → regex（子字串防誤觸）
```

### 3.2 股票偵測流程（每個 channel 的處理）

```
Pass 1：逐影片偵測（無 Gemini）
  影片文字（字幕 / Whisper / 標題+描述）
       ↓
  recognize_stocks()          # regex 比對所有關鍵字
       ↓
  pre-Gemini 過濾（依序）：
    1. price_level_filter     # 過濾股價誤觸（4字元數字後接「點/億/%」等）
    2. CONTEXT_REQUIRED       # 需要上下文關鍵字才算合法
    3. CONTEXT_FORBIDDEN      # 上下文有禁詞則排除
    4. KEYWORD_PATTERN_OVERRIDE # regex lookbehind/lookahead 防子字串誤觸
       ↓
  deduplicate_hits()

Pass 1.5：跨影片批次 Gemini ambiguous filter（一個 channel 一起送）
  _batch_filter_ambiguous_hits(detected)
    - 收集所有影片的 ambiguous hits（_is_ambiguous_hit() 判斷）
    - 每批最多 20 個 hits 合成一次 Gemini 呼叫
    - Prompt 標註每個 hit 的來源影片標題
    - 回傳 per-hit JSON: {is_stock, corrected_code, corrected_name}
    - 若 corrected_code 非空 → auto-save 到 learned_aliases.json

Pass 2：批次情緒分析（一個 channel 一次呼叫）
  _batch_channel_sentiments()

Pass 3：組合輸出，存入 data/latest.json
```

### 3.3 Gemini 整合

**模型**：`gemini-2.5-flash-lite`

**實際限制**：**20 RPD**（free tier，2026-04-08 實測確認）

**限流機制**（`_gemini_generate()`）：
- RPM gate：12 RPM，超過則 sleep 至下一分鐘
- 每日使用量追蹤：寫入 `gemini_usage.json`（7 日滾動）
- 閾值警告：超過設定值輸出警告

**呼叫場景**（每次完整掃描）：
1. 每個 channel 的 ambiguous hits 跨影片批次（`_batch_filter_ambiguous_hits`）— 預計 3-4 次
2. 每個 channel 的批次情緒分析（`_batch_channel_sentiments`）
3. US 股票 enriched keywords（`enrich_us_stocks_with_gemini`）
4. 週摘要生成（`generate_weekly_summary`）

**注意**：同一 UTC 日只能跑一次完整掃描。排程在 UTC 17:00（台灣凌晨 01:00），若當天再手動觸發測試會爆 quota。

### 3.4 Auto-learned Aliases

- `_load_learned_aliases()` 在 `build_stock_dict()` 啟動時載入
- `_save_learned_alias(wrong, code, name)` 在 Gemini 確認 Whisper 錯字後寫入
- 格式：`{"台波": "1802", "光盛": "6442", ...}`
- 優點：Whisper 錯字自動累積，不需每次手動加 ALIASES

### 3.5 已知誤報防護規則（截至 2026-04-13）

| 類型 | 對象 | 規則 |
|------|------|------|
| CONTEXT_REQUIRED | 3118 進階 | 需含「光電/LED/磊晶」 |
| CONTEXT_REQUIRED | 8047 星雲 | 需含「油電/能源/燃氣」（Whisper 辛耘→星雲） |
| CONTEXT_REQUIRED | BX (美股) | 需含 Blackstone 相關詞 |
| KEYWORD_PATTERN_OVERRIDE | 天剛 (5310) | `(?<![昨今前上那這每])天剛` — 排除「昨天剛好」 |
| KEYWORD_PATTERN_OVERRIDE | 全訊 (5222) | `全訊(?!息)` — 排除「全訊息」 |
| KEYWORD_PATTERN_OVERRIDE | 達新 (1315) | `(?<!輝)達新` — 排除 Whisper 把「輝達新…」誤切 |
| KEYWORD_PATTERN_OVERRIDE | 新產 (2850) | `新產(?!品)` — 排除「新產品」 |
| KEYWORD_PATTERN_OVERRIDE | 新建 (2516) | `(?<!重新)新建(?!立)` — 排除「重新建立」 |
| KEYWORD_PATTERN_OVERRIDE | 國巨 (2327) | `(?<!中)國巨(?!石)` — 排除「中國巨石」 |
| KEYWORD_PATTERN_OVERRIDE | 大立 (4716) | `大立(?!光)` — 排除「大立光」(3008) |
| KEYWORD_PATTERN_OVERRIDE | 力士 | `(?<!海)力士` — 排除「海力士」(SK Hynix) |
| CONTEXT_FORBIDDEN | 2327 國巨 | 禁止「中國巨石」 |
| CONTEXT_FORBIDDEN | 4128 中天 | 禁止「如日中天」（成語） |
| CONTEXT_FORBIDDEN | 1806 冠軍 | 禁止「冠軍是/以來冠軍/年度冠軍/績效冠軍」（ETF排名） |
| price_level_filter | 4/3字元股碼 | 「漲到XXXX」/ 「XXXX點/元」型誤觸 |

### 3.6 已知 Whisper 錯字 ALIASES（截至 2026-04-08）

| 錯字 | 正確股票 | 代碼 |
|------|---------|------|
| 台波 | 台玻 | 1802 |
| 光盛 | 光聖 | 6442 |
| 台澳 | 台燿 | 6274 |
| 連帽 / 連貌 | 聯茂 | 6213 |
| 紅塑 / 宏塑 | 弘塑 | 3131 |
| 波諾威 / 波若威 | 博威合金 | 3163 |

---

## 四、iOS App

### 4.1 架構模式

- **SwiftUI + @Observable** (iOS 17+)
- `AppState`：使用者設定（dataURL、selectedDays、ETF 顯示開關），存 UserDefaults
- `DataService`：負責 fetch + decode JSON，暴露 `scanResult: ScanResult`
- 所有 View 透過 `@Environment` 取得 AppState / DataService

### 4.2 核心資料模型（DataModels.swift）

```swift
ScanResult       // 頂層：stocksRanking + weeklySummary + generatedAt
StockEntry       // 個股：code, name, market, sector, contexts, sentimentScore
MentionContext   // 單筆提及：video, channel, date, text, sentiment, matchedKeyword
SectorEntry      // 族群：sector, market, totalMentions, stockCodes
WeeklySummary    // AI 週摘要：text, hotStocks, keyThemes, generatedAt
```

### 4.3 計算屬性

| 屬性 | 說明 |
|------|------|
| `episodeCount` | 不重複的 channel+video 組合數（≠ totalMentions） |
| `channelCount` | 不重複頻道數 |
| `sentimentScore` | bullish / (bullish + bearish)，純中性回傳 nil |
| `lastDateText` | 最新提及日期（human-friendly） |
| `analysisSourceSymbols` | whisper/captions 對應 SF Symbol |

### 4.4 日期篩選

`AppState.selectedDays`（1–90，預設 30）→ `cutoffDate` → 各 View 在客戶端即時重算，無需重新 fetch。

### 4.5 Tab 結構（MainTabView）

| Tab | View | 功能 |
|-----|------|------|
| 排行榜 | `RankingView` | 個股提及排行 + WeeklySummaryCard |
| 族群 | `SectorRankingView` | 族群排行榜 |
| 雷達 | `RadarView` | 看多/看空共識、近期暴紅/新上榜/降溫 |
| 趨勢圖 | `TrendView` | 個股/族群折線圖 + 情緒堆疊圖 |
| 內容清單 | `ContentListView` | 影片/集數列表 |
| 頻道管理 | `SourceManagementView` | 新增/刪除頻道（寫回 GitHub sources.json） |
| 設定 | `SettingsView` | dataURL、GitHub PAT、ETF 篩選器 |

### 4.6 頻道管理

- 修改透過 GitHub API（PUT /contents）直接更新 `sources.json`
- **不應手動編輯 sources.json**（詳見 feedback_channel_management.md）

---

## 五、GitHub Actions 工作流程（daily_scan.yml）

```yaml
排程：每天 UTC 17:00（台灣時間凌晨 01:00）
手動觸發 inputs:
  use_whisper: true/false  # 預設 true
  max_items: int           # 每個來源最多幾部（預設 5，測試用 3）
  days_back: int           # 往回掃幾天（預設 7）
```

觸發短測試指令：
```bash
curl -X POST \
  -H "Authorization: token $TOKEN" \
  -H "Accept: application/vnd.github.v3+json" \
  "https://api.github.com/repos/leowang0604/-StockMentionTracker/actions/workflows/250254781/dispatches" \
  -d '{"ref":"main","inputs":{"days_back":"7","use_whisper":"false","max_items":"3"}}'
```

---

## 六、已知限制

1. **YouTube IP 封鎖**：GitHub Actions IP 被 YouTube 封鎖，無法抓字幕，只能靠標題+描述。接受現狀，不嘗試修復。
2. **Whisper 錯字不穩定**：同一公司在不同影片可能辨識出不同錯字（波諾威/波羅威），auto-learn 只能累積已見過的錯字。
3. **matched_keyword 歷史缺值**：早期掃描未記錄 matchedKeyword，iOS 已 workaround（從全量 contexts 收集 keywords）。
4. **Gemini 每日上限**：`gemini-2.5-flash-lite` 實際上限 **20 RPD**（free tier）。同一 UTC 日跑兩次完整掃描會爆。

---

## 七、TODO / 待觀察

- [ ] 明天觸發短測試，確認 `_batch_filter_ambiguous_hits` Gemini 呼叫次數降到預期的 3-4 次
- [ ] 觀察 auto-learn 是否在後續掃描中正確套用 learned_aliases.json
- [ ] 評估是否需要增加更多 CONTEXT_REQUIRED 規則（視 false positive 出現頻率）
- [ ] 拼音比對（Pinyin matching）：已評估風險太高（「時間點」→尖點），暫不實作

# StockMentionTracker 完整架構文件

這份文件說明整個系統的技術架構，供接手的開發者或自己未來回顧使用。

---

## 1. 系統總覽

### 整體架構

```
                    ┌─────────────────────────────────────┐
                    │         GitHub Actions               │
                    │  每天 UTC 17:00 自動執行              │
                    │  (台灣時間 01:00)                    │
                    └──────────────┬──────────────────────┘
                                   │
                    ┌──────────────▼──────────────────────┐
                    │     scanner/main.py                  │
                    │                                      │
                    │  ┌─────────────┐  ┌──────────────┐  │
                    │  │  YouTube    │  │ Apple Podcast │  │
                    │  │  字幕/描述  │  │ RSS + Whisper │  │
                    │  └──────┬──────┘  └──────┬───────┘  │
                    │         │                 │          │
                    │  ┌──────▼─────────────────▼──────┐  │
                    │  │      股票辨識引擎               │  │
                    │  │  ┌──────────┐ ┌─────────────┐ │  │
                    │  │  │ Keyword  │ │   Gemini AI │ │  │
                    │  │  │  Path    │ │    Path     │ │  │
                    │  │  └────┬─────┘ └──────┬──────┘ │  │
                    │  │       └──────┬────────┘        │  │
                    │  │         ┌────▼────┐             │  │
                    │  │         │  Merge  │             │  │
                    │  │         └────┬────┘             │  │
                    │  └─────────────┼───────────────────┘  │
                    └────────────────┼─────────────────────┘
                                     │
                    ┌────────────────▼─────────────────────┐
                    │         data/latest.json             │
                    │  (commit 到 GitHub repo)              │
                    └────────────────┬─────────────────────┘
                                     │
                    ┌────────────────▼─────────────────────┐
                    │           iOS App                    │
                    │  (read-only，從 GitHub raw 拉資料)    │
                    └──────────────────────────────────────┘
```

### 資料流向

```
頻道來源
  │
  ├─ YouTube → YouTube Data API v3（取得影片清單）
  │               └─ 有字幕 → youtube-transcript-api
  │               └─ 無字幕 → 只用標題+描述
  │
  └─ Apple Podcast → iTunes RSS（取得集數清單）
                         └─ yt-dlp 下載 MP3
                         └─ faster-whisper 轉錄成文字
  │
  ▼
文字（逐字稿 or 描述）
  │
  ├─ Keyword Path：STOCK_DICT 關鍵字比對
  │                CONTEXT_REQUIRED / CONTEXT_FORBIDDEN 過濾
  │                情緒關鍵字分析
  │
  └─ Gemini Path：送整集文字給 Gemini API
                  _validate_gemini_stocks() 驗證
                  情緒評分由 Gemini 直接提供
  │
  ▼
_merge_extraction_results()
  │
  ▼
merge_into_history() → data/latest.json
```

---

## 2. 後端（scanner/）

### 檔案清單

| 檔案 | 說明 |
|---|---|
| `scanner/main.py` | 全部邏輯，約 3700 行，一個大檔案 |
| `scanner/sources.json` | 頻道設定（YouTube / Apple Podcast） |
| `scanner/requirements.txt` | Python 依賴 |

### main.py 主要區塊（依行號）

| 行號 | 內容 |
|---|---|
| 1–60 | 設定檔（env vars, paths, 常數） |
| 64–245 | `ALIASES` — 靜態 keyword→code 對應（英文名/別名/ETF代號） |
| 247–252 | `WHISPER_ALIAS_KEYWORDS` — 已知 Whisper 誤字集合 |
| 255–303 | `_load_learned_aliases()` / `_save_learned_alias()` |
| 326–405 | 情緒關鍵字 (`BULLISH_STRONG/MILD`, `BEARISH_STRONG/MILD`, `CONTEXT_PAIRS`) |
| 446–572 | `_US_STOCKS_DATA` — 美股關鍵字清單 |
| 588–714 | `TW_STOCK_SECTORS` — 台股代號→族群（hardcoded） |
| 720–747 | `SECTOR_KEYWORDS` — 族群→代表性關鍵字（用於 context 偵測） |
| 750–754 | 執行時全域 dict（`STOCK_DICT`, `CODE_TO_NAME` 等） |
| 760–918 | `fetch_tw_industry_map()` — 從 TWSE/TPEx 抓產業分類 |
| 919–1079 | `fetch_stock_list()` — 從 TWSE/TPEx 抓全部上市櫃股票 |
| 1081–1174 | `enrich_us_stocks_with_gemini()` — Gemini 補充美股清單 |
| 1277–1382 | `generate_weekly_summary()` — 每週摘要（目前未用） |
| 1383–1560 | `build_stock_dict()` — 建立 STOCK_DICT 等執行時 dict |
| 1568–1580 | `WHISPER_ORIG_BLACKLIST` — 不能是股票誤字的黑名單詞 |
| 1582–1644 | `CONTEXT_REQUIRED` — 需要特定詞才算數的股票 |
| 1647–1652 | `CONTEXT_FORBIDDEN` — 出現特定詞就排除的股票 |
| 1656–1669 | `KEYWORD_PATTERN_OVERRIDE` — 特殊 regex 比對 |
| 1675–1793 | `recognize_stocks()` — Keyword path 主函式 |
| 1794–1828 | `deduplicate_hits()` — 去重複邏輯 |
| 1829–1868 | `_split_into_chunks()` — 切割長文字 |
| 1869–1878 | `_get_extraction_mode()` — 決定用哪種模式 |
| 1881–1928 | `_keyword_sentiment()` — 內建情緒分析 |
| 1928–2007 | Gemini model 初始化 / 用量追蹤 |
| 2008–2183 | `analyze_sentiment_batch_gemini()` — Gemini 批次情緒分析 |
| 2184–2221 | `_levenshtein()` — Levenshtein 距離計算 |
| 2200–2221 | `_find_keyword_pos()` — 模糊位置搜尋（支援臺/台 + Lev≤1） |
| 2222–2309 | `_is_ambiguous_hit()` / `_suspicious_chinese_hits()` — 模糊判斷 |
| 2310–2323 | `analyze_sentiment()` — 單一情緒分析 |
| 2324–2547 | `_validate_gemini_stocks()` — Gemini 結果驗證（核心防幻覺） |
| 2549–2641 | `_gemini_extract_full_video()` — 送整集逐字稿給 Gemini |
| 2644–2679 | `_merge_extraction_results()` — 合併兩條軌道結果 |
| 2686–2801 | YouTube 影片取得（API + RSS fallback） |
| 2802–2913 | `fetch_captions()` / `download_audio()` / `transcribe_audio()` |
| 2914–3170 | `_detect_youtube_video()` — 處理單集 YouTube 影片 |
| 3170–3203 | `_build_youtube_mentions()` — 格式化 YouTube 結果 |
| 3204–3375 | Apple Podcast 抓取與處理 |
| 3376–3432 | Spotify 整合（備用） |
| 3434–3623 | `load_history()` / `merge_into_history()` — 歷史累積邏輯 |
| 3624–3634 | `load_sources()` — 讀取 sources.json |
| 3635–末尾 | `main()` — 主流程 |

---

## 3. 雙軌並行邏輯

系統有兩條平行的股票辨識路徑，最後合併。

### Keyword Path（關鍵字路徑）

```
STOCK_DICT（關鍵字→代號）
  │
  ▼
遍歷每個 keyword
  │
  ├─ ASCII 關鍵字：加 \b word boundary
  ├─ 有 KEYWORD_PATTERN_OVERRIDE：用自訂 regex
  └─ 其他：re.escape(keyword)
  │
  ▼
找到 match 位置後
  │
  ├─ CONTEXT_REQUIRED：context 裡需有指定詞
  ├─ CONTEXT_FORBIDDEN：context 裡不能有黑名單詞
  ├─ 年份 regex 過濾（2019–2030 年份不算股號）
  ├─ 純數字短代號需有 CONTEXT_REQUIRED
  └─ 擷取 context 窗口 [pos-100 : pos+len+200]
  │
  ▼
_is_ambiguous_hit()
  │
  ├─ 是→ 加入 ambiguous_hits，等 Gemini 批次驗證
  └─ 否→ keyword_sentiment() 分析情緒，直接加入結果
```

### Gemini Path（AI 提取路徑）

```
整集完整逐字稿
  │
  ▼
_gemini_extract_full_video()
  │
  ├─ 建構 prompt（含頻道名、標題、完整逐字稿）
  ├─ 呼叫 Gemini API（gemini-2.5-flash-lite）
  └─ 解析 JSON 回傳（name, code, sentiment, score, context, whisper_original）
  │
  ▼
_validate_gemini_stocks()（防幻覺核心）
  │
  ├─ 解析代號（直接/Levenshtein/name lookup）
  ├─ WHISPER_ORIG_BLACKLIST 過濾
  ├─ correction resolver：
  │   ├─ learned alias / contextual alias / phonetic winner
  │   ├─ 檢查音近分數、top1 領先幅度、股票語境
  │   └─ 檢查產業衝突與 rejected_aliases
  ├─ name_appears 檢查：
  │   ├─ stock_keywords in chunk_text?
  │   ├─ whisper_orig in chunk_text + core-name Lev≤1?
  │   ├─ -KY bare-name 支援
  │   └─ Levenshtein / phonetic evidence fallback
  ├─ Levenshtein fallback 窗口比對
  ├─ 通過→ ctx_has_keyword 檢查（context 是否含關鍵字）
  ├─ 不含→ re-center：用 _find_keyword_pos 找位置重建 context
  ├─ 同一股票多段 context 保留為多筆 hit
  └─ 輸出 validated list；拒絕項目寫 skip_log
```

### Merge 邏輯

```python
_merge_extraction_results(hits_keyword, hits_gemini)
```

- Gemini 結果優先（情緒分析更準）
- Keyword 補充 Gemini 沒抓到的（冷門股、只有關鍵字比對能找到的）
- 相同代號：用 Gemini 情緒，但若 keyword context 比較長則保留 keyword 的 context
- 同一支股票若在不同段落被提到，保留多筆 context，讓 App 能分段顯示與 highlight

### 決定用哪個模式

`_get_extraction_mode(source, sources_config)` 讀取：
1. 個別 source 的 `extraction_mode` 欄位
2. 若沒有 → `sources_config["global_extraction_mode"]`
3. 預設 `"keyword"`

`"auto"` 模式 = 兩條都跑再 merge。

---

## 4. 資料格式

### sources.json

```json
{
  "global_extraction_mode": "auto",
  "sources": [
    {
      "id": "唯一ID（UUID 或 slug）",
      "name": "顯示名稱",
      "type": "applePodcast | youtube",
      "identifier": "Apple Podcast 節目ID 或 YouTube channel ID",
      "active": true,
      "extraction_mode": "keyword | gemini | auto"
    }
  ]
}
```

### latest.json

```json
{
  "updated_at": "2026-04-25T20:39:46",
  "days_back": 7,
  "stocks_ranking": [
    {
      "code": "2330",
      "name": "台積電",
      "market": "TW",
      "sector": "晶圓代工",
      "total_mentions": 15,
      "sentiment_score": 0.72,
      "daily": {
        "2026-04-25": {
          "mentions": 3,
          "bullish": 2,
          "bearish": 0,
          "neutral": 1,
          "sentiment_score": 0.8
        }
      },
      "contexts": [
        {
          "video": "EP123 | 影片標題",
          "channel": "股癌",
          "date": "2026-04-25",
          "text": "…提及 context 原文（約 300 字）…",
          "matched_keyword": "台積電",
          "analysis_source": "whisper | description | title | captions",
          "sentiment": "bullish | bearish | neutral",
          "sentiment_score": 0.8,
          "video_url": "https://...",
          "extraction_mode": "keyword | gemini"
        }
      ]
    }
  ]
}
```

`contexts` 最多保留 30 筆（`MAX_CONTEXTS_PER_STOCK = 30`）。

### learned_aliases.json

```json
{
  "Whisper寫的錯誤詞": "股票代號",
  "細創": "8016",
  "信骅": "6414"
}
```

人工確認後保留的穩定 Whisper 錯字對應。Scanner 會把新錯字先寫入
`alias_candidates.json`，不會因單次 Gemini/phonetic 猜測自動升級到這裡。人工升級前至少要確認：
1. `correct_code` 必須在 `CODE_TO_NAME` 裡
2. 錯字詞確實出現在 transcript / artifact
3. 附近是在討論該股票或同族群，不是普通文字
4. `wrong_keyword` 不會覆蓋正式股票名稱或高頻普通詞

### skip_log_YYYY-MM-DD.json

```json
[
  {
    "keyword": "過濾的關鍵字或 whisper_original",
    "reason": "context_required | gemini_extraction_rejected | keyword_pattern_override | context_forbidden | price_level_filter | auto_learn_rejected",
    "detail": "詳細原因",
    "video_id": "影片ID",
    "channel": "頻道名",
    "date": "2026-04-25",
    "title": "影片標題"
  }
]
```

每天一個檔案，累積不清除（可手動刪舊的）。

---

## 5. iOS App

### 架構

純 SwiftUI read-only app。不跑本地邏輯，只顯示 GitHub 上的 `data/latest.json`。

### 頁面

| 頁面 | 功能 |
|---|---|
| 排行榜 (RankingView) | 股票提及次數排名，可按族群/市場篩選 |
| 族群 (SectorView) | 按產業族群瀏覽 |
| 雷達 (RadarView) | 市場情緒雷達圖 |
| 趨勢圖 (TrendView) | 各股時間軸趨勢 |
| StockDetailView | 點進單支股票，看所有 context 紀錄 |
| SettingsView | 全局設定、extraction mode 選擇 |
| SourceManagementView | 管理頻道清單（直接 PATCH sources.json 到 GitHub） |

### 資料模型

主要在 `StockMentionTracker/Models/`：
- `StockInfo.swift` — 股票資料 (code, name, market, sector, mentions, contexts)
- `Source.swift` — 頻道來源 (id, name, type, identifier, active, extraction_mode)

### 與 GitHub 的互動

- **讀取**：`https://raw.githubusercontent.com/leowang0604/-StockMentionTracker/main/data/latest.json`
- **管理頻道**：透過 GitHub API PUT `scanner/sources.json`（需 Personal Access Token）
- Token 儲存在 iOS Keychain

---

## 6. GitHub Actions

### 排程

```yaml
on:
  schedule:
    - cron: '0 17 * * *'   # UTC 17:00 = 台灣 01:00
  workflow_dispatch:         # 手動觸發
    inputs:
      use_whisper: ...        # true/false
      max_items: ...          # 每來源幾集
      days_back: ...          # 往回幾天
      test_download_only: ... # 只測試下載不 Whisper
```

### 環境變數

| 變數 | 來源 | 說明 |
|---|---|---|
| `GEMINI_API_KEY` | Secret | Gemini API 金鑰 |
| `YOUTUBE_API_KEY` | Secret | YouTube Data API v3 |
| `HF_TOKEN` | Secret | Hugging Face token（下載 Whisper 模型） |
| `YOUTUBE_COOKIES_FILE` | workflow 設定 | cookies 檔案路徑（從 Secret 寫入） |
| `USE_WHISPER` | input / var | 是否啟用 Whisper |
| `MAX_ITEMS` | input / var | 每來源最多幾集 |
| `DAYS_BACK` | input / var | 往回幾天 |

### 步驟

1. Checkout repo
2. Setup Python 3.11
3. Install base deps（yt-dlp, requests, youtube-transcript-api, google-genai）
4. 若 use_whisper=true → Cache Whisper model + Install faster-whisper
5. 寫 YouTube cookies 檔案
6. `python scanner/main.py`
7. Commit + Push `data/` 目錄變更

Workflow ID：`250254781`（手動觸發 curl 時用這個）

---

## 7. 關鍵資料結構說明

### STOCK_DICT（執行時）

`keyword → stock_code`，由 `build_stock_dict()` 在每次執行時建立：

- 台股：來自 TWSE/TPEx live API（stocks.json cache）
  - 加入：`name → code`、`code → code`、短別名（如「台積電工業」→「台積電」）
- 美股：來自 hardcoded `_US_STOCKS_DATA`
- 靜態 ALIASES：直接 merge 進來
- learned_aliases.json：動態讀入

### CONTEXT_REQUIRED

`stock_code → [required_keywords]`

Keyword path 用：找到關鍵字後，context 裡必須出現 list 中至少一個詞才算命中。Gemini path 不直接套
`CONTEXT_REQUIRED`，但 validator 會用「名稱是否真的出現在 chunk / whisper_original 是否可信 / local evidence 是否有股票討論 / 產業語境是否衝突」擋掉幻覺。

### KEYWORD_PATTERN_OVERRIDE

`keyword → regex_pattern`

取代預設的 `re.escape(keyword)` 比對，可用 lookbehind/lookahead 精準排除特定前後文。

### CONTEXT_FORBIDDEN

`stock_code → [forbidden_strings]`

若任一 forbidden string 出現在 context 裡，這次命中被拒絕。

### WHISPER_ORIG_BLACKLIST

Gemini 回傳的 `whisper_original` 若在此集合裡，整筆被拒絕（不會驗證也不會存入 learned_aliases）。

### learned_aliases.json

持久化儲存的 Whisper 修正對應，每次執行都會讀入並 merge 進 STOCK_DICT。現在原則是「人工確認後才進 learned aliases」；scanner 會把新候選寫入 `alias_candidates.json`，不會因單次 Gemini/phonetic 猜測自動升級成永久 alias。

### alias_candidates.json / rejected_aliases.json

- `alias_candidates.json`：記錄 Gemini validator、phonetic discovery、KY discovery 發現的待審候選，包含信心分數、最近上下文、候選排名與觀察次數。
- `rejected_aliases.json`：人工拒絕後的候選，不會重複排隊，也不會在同次 scan 被當成正式規則。

### phonetic discovery

只在 Whisper 文字啟用，用台股官方名稱建立拼音索引，從股票語境附近的未知詞找音近候選。它可以：

- 在當次 scan 補入高信心 hit
- 把候選寫入 `alias_candidates.json`
- 透過 log 顯示 sampled / dropped / reject 原因，診斷長逐字稿是否被 quota 影響

它不會把候選自動寫入 `learned_aliases.json`。穩定錯字仍要人工確認，例如「漢堂」→「漢唐」。

### transcript artifacts

每次 scan 會把已處理項目的完整文字保存到 `artifacts/transcripts/`，workflow 上傳為
`scan-transcripts-<run_id>` artifact，保留 14 天。artifact 只供診斷，不會 commit，也不會進
`data/latest.json`。用途是查證 `not in chunk → skipped`：到底整集真的沒出現，還是只是不在 Gemini 回傳片段附近。

---

## 8. 已知限制與取捨

### YouTube IP 封鎖

GitHub Actions 的 IP 被 YouTube 封鎖，無法下載音訊跑 Whisper。目前策略是只用字幕（有的話）或標題+描述。這個問題無法在不換執行環境的情況下解決。

### Whisper 錯字無法完全處理

Whisper small 模型在台語夾雜、口音、同音異字上錯誤率高。目前靠：
- ALIASES（已知錯誤→正確對應）
- Gemini validator 的 `whisper_original` 機制
- phonetic discovery 產生候選與當次高信心補抓
- alias_candidates.json 人工審核
- learned_aliases.json 儲存已確認的穩定錯字

alias 的定位是「Whisper 穩定錯字」，不是普通文字全部都補 pattern。新的錯字會先進候選池；人工確認後才升級，避免補不完也避免亂抓。

### 2 字股票名稱的假陽性風險

2 字名稱（如「達新」「天剛」「新建」）很容易被自然語言切出來。用 KEYWORD_PATTERN_OVERRIDE 或 CONTEXT_REQUIRED 逐一處理，但無法全自動解決。

### Gemini 幻覺問題

Gemini 有時會在完全不相關的 context 裡幻覺出某支股票。`_validate_gemini_stocks()` 有多道防線：
1. `name_appears`：股票名稱或 whisper_original 必須出現在原文（含 core-name Levenshtein 驗證）
2. correction resolver：音近分數、top1 lead、股票語境、產業衝突、rejected alias
3. Levenshtein / phonetic fallback（局部窗口比對，不採用整段無錨點文字）
4. `ctx_has_keyword` / local evidence：Gemini 提供的 context 必須能錨定股票討論

因此看到 `hallucination? ... not in chunk → skipped` 通常是正常保護。若要確認整集是否真的完全沒有該詞，下載 transcript artifact 搜整份逐字稿。

### Gemini API 費率

`gemini-2.5-flash-lite`：
- 實測 free tier 約 20 RPD，完整掃描同一 UTC 日不要重跑太多次
- 收費版很便宜但需要設 spend cap 防止爆單

`gemini-2.0-flash` 有 rate limit=0（無法使用）。
`gemini-2.5-flash`（非 lite）：20 RPD 免費版，超過需付費。
`gemini-1.5-flash`：已下架（404）。

---

## 9. 未來改進方向

### 若有預算

1. **換更好的 Whisper 模型**：用 `medium` 或 `large-v3` 錯字率大幅下降，但需要更多 RAM（Actions 需升級 runner）
2. **換 Claude 做驗證**：Claude 的幻覺問題比 Gemini 少，且支援 structured output；但費用約 5–10x
3. **自建 CI runner**：用自己的 VPS 跑 Actions，解決 YouTube IP 封鎖問題，能真正跑 YouTube 音訊
4. **向量資料庫去重**：目前 context 去重靠位置比較，若有 embedding 可以語意去重

### 已知 Bug / 已處理風險

1. **長集數逐字稿 context 窗口**：每支股票仍有 `MAX_CONTEXTS_PER_STOCK` 上限，避免 JSON 爆大；但同一節目同一股票的多段內容已可保留為多筆 context。
2. **Gemini 對 KY 股的 whisper_original 帶後綴**：已支援 bare-name / explicit KY discovery，可處理「真頂ky」這類口語或 Whisper 變體；仍需靠 replay/skip_log 觀察新型態。
3. **phonetic discovery 長逐字稿 sampling**：不做無限制全量掃描以避免時間爆炸；目前有 sampled/dropped/quota log，遇到漏抓時優先看 artifact + log，再決定是否升級 learned alias 或調整 discovery。

### 待優化

1. **公司身份 vs 普通文字**：目前用 short-company gate 擋常見誤判；未全面導入外部 registry lookup，避免一次改太大造成漏抓。
2. **sources.json 由 iOS app 管理但沒有 conflict 保護**：若兩個裝置同時修改，後寫的會覆蓋先寫的。
3. **baseline replay 覆蓋率**：已有 fixture replay，但仍需要持續把實際出錯片段加入 fixture，才能防止未來 regression。

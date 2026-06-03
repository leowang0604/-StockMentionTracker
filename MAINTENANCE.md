# StockMentionTracker 維護手冊

這份文件是給自己或接手的人看的操作手冊。不需要看懂所有程式碼，按步驟操作即可。

---

## 目錄

1. [環境設定](#1-環境設定)
2. [日常觸發掃描](#2-日常觸發掃描)
3. [新增／刪除頻道](#3-新增刪除頻道)
4. [修正誤判（假陽性）](#4-修正誤判假陽性)
5. [資料清理](#5-資料清理)
6. [費用監控](#6-費用監控)
7. [模式切換與 Quota 處理](#7-模式切換與-quota-處理)
8. [常見問題排查](#8-常見問題排查)

---

## 1. 環境設定

### Clone repo

```bash
git clone https://github.com/leowang0604/-StockMentionTracker.git
cd -StockMentionTracker
```

### 安裝 Python 依賴

```bash
pip install "yt-dlp>=2025.1.1" requests "youtube-transcript-api>=1.0.0" google-genai "pypinyin>=0.53,<1"
# 若要跑 Whisper（轉錄 Podcast 音訊）
pip install faster-whisper==1.1.1
```

Python 版本需 **3.11+**（type union `X | Y` 語法）。

### GitHub Secrets 設定

在 GitHub repo → Settings → Secrets and variables → Actions 新增：

| Secret 名稱 | 用途 | 必填 |
|---|---|---|
| `GEMINI_API_KEY` | Gemini AI 提取股票 / 情緒分析 | 是 |
| `YOUTUBE_API_KEY` | 取得 YouTube 頻道影片清單 | 建議 |
| `HF_TOKEN` | 下載 Whisper 模型（Hugging Face） | Whisper 啟用時 |
| `SPOTIFY_CLIENT_ID` | Spotify Podcast 備用來源 | 否 |
| `SPOTIFY_CLIENT_SECRET` | 同上 | 否 |
| `YOUTUBE_COOKIES` | YouTube 登入 cookies（繞過年齡限制等） | 否 |

`YOUTUBE_API_KEY` 沒設定時會 fallback 到 RSS，功能大致一樣但速度較慢。

### 本地測試

```bash
# 設定環境變數
export GEMINI_API_KEY="your-key"
export YOUTUBE_API_KEY="your-key"   # 可不設
export USE_WHISPER=false             # 本地測試關掉 Whisper（太慢）
export MAX_ITEMS=2                   # 每個來源最多掃 2 集
export DAYS_BACK=3

# 跑掃描
cd scanner/
python main.py
```

輸出結果在 `data/latest.json`。

---

## 2. 日常觸發掃描

### 自動排程

每天 UTC 17:00（台灣時間 01:00）自動執行，結果 commit 到 `data/latest.json`。

### 手動觸發（GitHub Actions 網頁）

1. 開 GitHub repo → Actions → Daily Stock Mention Scan
2. 點「Run workflow」
3. 填入參數（或保持預設）：
   - `use_whisper`：`true`/`false`（false 較快，Podcast 只用 RSS 描述）
   - `max_items`：每來源最多幾集（測試用 `2`，正式用 `5`）
   - `days_back`：往回掃幾天（預設 `7`）

### 手動觸發（curl 指令）

```bash
export TOKEN="ghp_your_token"

# 快速測試（不跑 Whisper，每源最多 3 集）
curl -s -X POST \
  -H "Authorization: token $TOKEN" \
  -H "Accept: application/vnd.github.v3+json" \
  "https://api.github.com/repos/leowang0604/-StockMentionTracker/actions/workflows/250254781/dispatches" \
  -d '{"ref":"main","inputs":{"days_back":"7","use_whisper":"false","max_items":"3"}}'
# 正常回應是 HTTP 204（無輸出）

# 確認觸發成功
curl -s -H "Authorization: token $TOKEN" \
  "https://api.github.com/repos/leowang0604/-StockMentionTracker/actions/runs?per_page=3" \
  | python3 -c "import sys,json; [print(f\"#{r['run_number']} {r['status']} {r['conclusion'] or ''} {r['updated_at']}\") for r in json.load(sys.stdin)['workflow_runs']]"
```

### 看掃描 log

在 GitHub Actions → 選最新一次 run → 點「Run scanner」步驟可看即時 log。

重要 log 標記：
- `[scanner]` — 整體流程
- `[gemini_extract]` — Gemini 提取結果
- `[alias-candidate]` — 新增待審核的 Whisper 修正候選
- `[SKIP]` — 被過濾掉的誤判
- `[tw_industry]` — 台股產業分類更新

### 查看 gemini_usage.json

```bash
curl -s "https://raw.githubusercontent.com/leowang0604/-StockMentionTracker/main/data/gemini_usage.json" \
  | python3 -m json.tool
```

欄位說明：
- `daily` — 今天已用幾次 API 呼叫
- `monthly_cost_usd` — 本月預估費用

---

## 3. 新增／刪除頻道

頻道清單在 `scanner/sources.json`。

### sources.json 欄位說明

```json
{
  "global_extraction_mode": "auto",
  "sources": [
    {
      "id": "唯一ID（UUID或英文slug）",
      "name": "頻道顯示名稱",
      "type": "applePodcast",
      "identifier": "Apple Podcast 節目ID",
      "active": true,
      "extraction_mode": "auto"
    }
  ]
}
```

`type` 可為：
- `applePodcast` — 用 iTunes RSS 抓集數描述，Whisper 轉錄音訊
- `youtube` — 用 YouTube API/RSS 抓影片，優先用 CC 字幕

`extraction_mode` 可為：
- `keyword` — 只用關鍵字比對（快、省錢，適合有字幕的頻道）
- `gemini` — 只用 Gemini AI 提取
- `auto` — 兩種都跑再合併（最準但最貴）
- 不填 → 用 `global_extraction_mode`

`active: false` 暫停這個頻道不掃。

### 如何取得 Apple Podcast ID

1. 開 Apple Podcast 找到節目
2. 右鍵 → 複製連結，格式如 `https://podcasts.apple.com/tw/podcast/股癌/id1500839292`
3. 最後的數字就是 `identifier`（例如 `1500839292`）

### 如何取得 YouTube 頻道 ID

1. 開頻道頁面
2. 網址通常是 `https://www.youtube.com/@ChannelName` 或 `https://www.youtube.com/channel/UC...`
3. 若是 `UC...` 開頭的就直接用
4. 若是 `@ChannelName` 格式，開 F12 → Network → 搜尋 `browse?key` 可找到真實 channel ID
5. 或用 `yt-dlp --print channel_id "https://www.youtube.com/@ChannelName"` 取得

### 新增頻道步驟

1. 編輯 `scanner/sources.json`，在 `sources` 陣列新增一筆
2. 建議先設 `"active": true, "extraction_mode": "keyword"` 測試一次
3. Commit + Push
4. 手動觸發一次掃描，確認 `data/latest.json` 有該頻道的結果
5. 若結果正常，可改為 `"extraction_mode": "auto"`

### 刪除／停用頻道

- **暫停**：改 `"active": false`（保留設定，之後可以開回來）
- **刪除**：直接從 `sources` 陣列移除整筆

---

## 4. 修正誤判（假陽性）

誤判有幾種類型，修法不同。先看 skip_log 診斷（見 §8），確認是哪種情況。

### 類型一：關鍵字本身就是日常詞（如「統一」「大同」「全家」）

**修法**：加進 `CONTEXT_REQUIRED`，要求 context 裡必須出現指定詞才算數。

找到 `scanner/main.py` 的 `CONTEXT_REQUIRED` 字典（約第 1582 行），新增一筆：

```python
"1234": ["1234", "公司全名", "股票簡稱"],
# 鍵是股票代號，值是至少要出現一個的詞
```

**使用時機**：
- 關鍵字是常用中文詞（「統一」「信大」「世界」）
- 關鍵字是常見縮寫（「AI」「LINE」）

### 類型二：Whisper 把某詞誤切成股票代號子字串

**修法**：加進 `KEYWORD_PATTERN_OVERRIDE`，用正規表示式排除特定前後文。

找到約第 1656 行：

```python
# 排除「輝達新高」被切成「達新」
"達新": r"(?<!輝)達新",

# 排除「全訊息」
"全訊": r"全訊(?!息)",
```

Regex 語法：
- `(?<!前面)` — 前面不是這個詞才匹配（negative lookbehind）
- `(?!後面)` — 後面不是這個詞才匹配（negative lookahead）

**使用時機**：誤判有固定的前後文模式，可以用 regex 精準排除。

### 類型三：某個特定詞出現在 context 就一定是誤判

**修法**：加進 `CONTEXT_FORBIDDEN`（約第 1647 行）：

```python
"2327": ["中國巨石"],  # "國巨" 出現在 "中國巨石" 裡不是 Yageo
```

**使用時機**：有特定的「干擾詞」會導致誤判。

### 類型四：Whisper 某個特定輸出詞完全不可能是股票

**修法**：加進 `WHISPER_ORIG_BLACKLIST`（約第 1568 行）：

```python
WHISPER_ORIG_BLACKLIST: frozenset[str] = frozenset({
    "GDP", "CPI", "美國", "台灣",
    # 新增你想排除的詞
})
```

**使用時機**：Gemini 把「台灣」「GDP」「PMI」等詞當成 Whisper 誤字送來驗證，浪費 API。

### 類型五：新增 Whisper 已知誤字對應（ALIASES）

**修法**：在 `ALIASES` 字典（約第 64 行）新增：

```python
"連帽": "6213",   # Whisper 常將「聯茂」誤轉為「連帽」
```

鍵是 Whisper 寫的錯誤詞，值是正確的股票代號。

**注意**：這裡新增的 alias 會直接進 STOCK_DICT，作為 keyword path 的比對關鍵字。若這個詞太常見，可能引入新的誤判。可以同時加 CONTEXT_REQUIRED 限制。

---

## 5. 資料清理

### 清掉 latest.json 裡某支股票的錯誤紀錄

`data/latest.json` 是自動生成的，每次掃描會累積近期結果。最快的做法是等下次掃描自然更新。

若要立刻刪除：
```bash
# 本地編輯 data/latest.json，找到對應 stock_code 的整筆刪掉
# 然後 commit + push
git add data/latest.json
git commit -m "fix: remove false positive for XXXX"
git push
```

### 檢查 Whisper alias 候選

`data/alias_candidates.json` 會記錄 Gemini 與 validator 發現的 Whisper 修正候選、信心分數、不同集數證據與最近上下文。Scanner 不會因為單次猜測就自動升級為永久 alias。

人工確認後，才將候選加入 `scanner/main.py` 的 `ALIASES` 或 `data/learned_aliases.json`。

### 清空 learned_aliases.json

`data/learned_aliases.json` 是人工確認後保留的 Whisper 修正對應。若懷疑有錯誤的對應：

```bash
echo "{}" > data/learned_aliases.json
git add data/learned_aliases.json
git commit -m "fix: reset learned_aliases"
git push
```

清空後，下次掃描 Gemini 會重新學習，但有嚴格驗證邏輯保護（代號/名稱必須一致、不能覆蓋正式關鍵字）。

### 完整重掃（清掉所有快取資料）

```bash
# 保留 stocks.json（台股清單），清掉其他快取
rm data/tw_industry_cache.json data/etf_names_cache.json data/sectors_cache.json
git add -u data/
git commit -m "chore: clear caches for rescan"
git push
```

然後手動觸發掃描，設 `use_whisper=true, max_items=5, days_back=14`。

---

## 6. 費用監控

### Gemini API 用量

```bash
curl -s "https://raw.githubusercontent.com/leowang0604/-StockMentionTracker/main/data/gemini_usage.json"
```

### 在 Google AI Studio 設定 spend cap

1. 開 https://aistudio.google.com/
2. 左側 → Settings → Billing
3. 設定每月上限（建議 $5–10 USD）

### 預期費用範圍

使用 `gemini-2.5-flash-lite` 模型：
- **每天** `use_whisper=false`（只看 RSS 描述）：~5–10 次 API 呼叫，幾乎免費
- **每天** `use_whisper=true`（完整轉錄）：~20–50 次 API 呼叫，約 $0.01–0.05/天
- **每月** 正常使用：$0.5–2 USD

若 `gemini_usage.json` 顯示 `daily` 超過 50 次，代表有頻道在頻繁失敗重試，建議查 log。

---

## 7. 模式切換與 Quota 處理

### 切換 extraction mode

編輯 `scanner/sources.json`：

```json
{
  "global_extraction_mode": "keyword",
  // 改 "keyword" = 關閉 Gemini，只用關鍵字比對（免費但較不準）
  // 改 "gemini"  = 只用 Gemini（最準，最貴）
  // 改 "auto"    = 兩者並行合併（預設推薦）
}
```

個別頻道可用 `"extraction_mode"` 覆蓋全局設定。

### Gemini Quota 超出

症狀：log 出現 `[gemini] quota exceeded` 或 `RESOURCE_EXHAUSTED`。

處理方式：
1. **短期**：在 `sources.json` 將 `global_extraction_mode` 改為 `"keyword"`，下次掃描不用 Gemini
2. **查用量**：開 Google AI Studio → API Keys → 查看配額
3. 目前用的是 `gemini-2.5-flash-lite`，免費版 RPD（每日請求數）= 500 次

### 完全關閉 Gemini（純 keyword 模式）

```json
// sources.json
{ "global_extraction_mode": "keyword" }
```

純 keyword 模式不用 API，完全免費。代價是：
- Whisper 誤字無法自動修正（需手動加 ALIASES）
- 情緒分析用內建規則，不如 Gemini 準確
- 新上市股票如果名字不在字典裡，抓不到

---

## 8. 常見問題排查

### 某支股票沒被抓到

1. **確認它在 STOCK_DICT**：這支股票的名稱或代號有沒有在 `ALIASES` 或 `scanner/main.py` 的 `_US_STOCKS_DATA` 裡？若是台股，有沒有在 `stocks.json` 裡？

2. **查 skip_log**：
   ```bash
   curl -s "https://raw.githubusercontent.com/leowang0604/-StockMentionTracker/main/data/skip_log_$(date +%Y-%m-%d).json" \
     | python3 -c "
   import sys, json
   logs = json.load(sys.stdin)
   target = '股票名稱或代號'
   matches = [r for r in logs if target in str(r)]
   for m in matches:
       print(m)
   "
   ```

3. **常見 skip 原因**：
   - `context_required`：被 CONTEXT_REQUIRED 過濾（context 裡沒有必要詞）
   - `gemini_extraction_rejected`：Gemini 回傳但驗證失敗（名稱不在原文）
   - `keyword_pattern_override`：被 KEYWORD_PATTERN_OVERRIDE 的 regex 過濾

### 某筆資料被誤判

1. 先看 context（iOS app 點進去看「提及內容」）
2. 判斷是哪種誤判：
   - Context 完全不相關 → Gemini 幻覺（加 CONTEXT_REQUIRED）
   - Context 是另一支股票的討論 → 先檢查 alias_candidates.json 與 learned_aliases.json
   - 關鍵字是日常詞 → 加 CONTEXT_REQUIRED 或 KEYWORD_PATTERN_OVERRIDE
3. 修改後 commit + push，觸發一次測試掃描確認

### 如何看 skip_log 診斷

```bash
# 看今天的 skip_log 統計
curl -s "https://raw.githubusercontent.com/leowang0604/-StockMentionTracker/main/data/skip_log_$(date +%Y-%m-%d).json" \
  | python3 -c "
import sys, json
from collections import Counter
logs = json.load(sys.stdin)
print('總計:', len(logs))
reasons = Counter(r.get('reason','?') for r in logs)
for k, v in reasons.most_common():
    print(f'  {k}: {v}')
print()
# 看 gemini_extraction_rejected 的細節
for r in logs:
    if r.get('reason') == 'gemini_extraction_rejected':
        print(r.get('keyword','?'), '->', r.get('detail',''))
"
```

### 從 latest.json 找特定股票

```bash
curl -s "https://raw.githubusercontent.com/leowang0604/-StockMentionTracker/main/data/latest.json" \
  | python3 -c "
import sys, json
d = json.load(sys.stdin)
target_code = '2330'  # 改成你要查的代號
for s in d.get('stocks_ranking', []):
    if s['code'] == target_code:
        for ctx in s.get('contexts', [])[:3]:
            print(ctx['channel'], ctx['date'])
            print(ctx['text'][:200])
            print()
"
```

### YouTube 字幕抓不到

YouTube 在 GitHub Actions 的 IP 上封鎖了部分請求，這是已知限制。症狀是 log 出現 `[captions] blocked` 或 `403`。

目前策略：
- 字幕抓不到 → 只用影片標題 + 描述做關鍵字比對
- 不再嘗試下載音訊跑 Whisper（IP 同樣被封）
- 不需要修，這是已知取捨

---

## 附錄：重要檔案位置

| 檔案 | 用途 |
|---|---|
| `scanner/main.py` | 主掃描程式，所有邏輯都在這 |
| `scanner/sources.json` | 頻道清單，唯一需要常修改的設定檔 |
| `data/latest.json` | 最新掃描結果（自動更新） |
| `data/alias_candidates.json` | 待人工審核的 Whisper 修正候選 |
| `data/learned_aliases.json` | 人工確認後保留的 Whisper 修正（可清空） |
| `data/skip_log_YYYY-MM-DD.json` | 每日過濾記錄，診斷用 |
| `data/gemini_usage.json` | Gemini API 用量追蹤 |
| `data/stocks.json` | 台股清單快取（30 天更新一次） |
| `.github/workflows/daily_scan.yml` | GitHub Actions 排程設定 |

---

## 離線發音 Alias Benchmark

在把發音分數接進 production scanner 前，先用這個離線 benchmark 驗證。它只讀
`data/stocks.json` 和人工整理的 fixtures，不會呼叫 Gemini、不會修改掃描結果，也不會自動升級 alias。

```bash
python -m pip install -r scanner/tools/requirements-benchmark.txt
python scanner/tools/benchmark_phonetic_aliases.py
```

正例與反例案例放在：

```text
scanner/tests/fixtures/phonetic_alias_cases.json
```

最初用 6 個已確認的中文 Whisper 變體測得的 baseline：

```text
baseline Top-1: 3/6
phonetic Top-1: 5/6
baseline Top-3: 3/6
phonetic Top-3: 6/6
negative Top-1 failures: 0/4
```

發音分數應該只作為候選排序訊號，不要單獨用來自動升級 alias。

production scanner 目前保守使用同一套發音分數：

- 每次掃描在記憶體建立一次台股發音索引
- 把發音證據加入 alias candidate 的信心分數
- 把最接近的 3 個股票名稱寫進 `data/alias_candidates.json`
- App 的審核頁會顯示這些候選，供人工判斷

發音分數本身不會自動改變偵測到的股票，也不會自動核准 alias。

---

## 離線 Scanner Fixture Replay

修 Whisper alias、漏抓股票、誤判、highlight 或 context regression 時，優先跑 fixture replay。
它會把已保存的逐字稿片段直接丟進 production scanner 的辨識邏輯，不會下載影片、不會跑
Whisper、不會呼叫 Gemini，也不會寫入真正的 `data/alias_candidates.json`。

跑全部 replay fixtures：

```bash
make replay
```

只跑單一 fixture：

```bash
make replay CASE=cpo_lianjun
```

列出目前可用 fixture：

```bash
/Users/leowang/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3 \
  scanner/tools/replay_scan_fixture.py --list
```

fixture 檔案位置：

```text
scanner/tests/fixtures/transcripts/*.txt
scanner/tests/fixtures/expected_mentions.json
```

新增 regression 的方式：先把有問題的逐字稿片段存成
`transcripts/<case_id>.txt`，再到 `expected_mentions.json` 補上預期的
`must_include`、`must_exclude`，以及可選的 `expected_candidates`。

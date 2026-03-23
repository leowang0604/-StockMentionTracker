#!/usr/bin/env python3
"""
Stock Mention Tracker — GitHub Actions Scanner

Steps:
  1. YouTube Data API v3 → get latest videos per channel
  2. yt-dlp → fetch captions; download audio if no captions
  3. faster-whisper → transcribe audio to text
  4. Recognize Taiwan stock names / codes in transcript
  5. Count mentions and extract surrounding context
  6. Write results to data/latest.json
"""

import json
import os
import re
import sys
import shutil
import tempfile
import urllib.request as urequest
import xml.etree.ElementTree as ET
from datetime import datetime, timezone, timedelta
from email.utils import parsedate_to_datetime
from pathlib import Path

import requests
import yt_dlp

# ─────────────────────────────────────────────────────────────────────────────
# Configuration
# ─────────────────────────────────────────────────────────────────────────────

YOUTUBE_API_KEY    = os.environ.get("YOUTUBE_API_KEY", "")
USE_WHISPER        = os.environ.get("USE_WHISPER", "true").lower() == "true"
SPOTIFY_CLIENT_ID  = os.environ.get("SPOTIFY_CLIENT_ID", "")
SPOTIFY_CLIENT_SECRET = os.environ.get("SPOTIFY_CLIENT_SECRET", "")

MAX_ITEMS_PER_SOURCE = int(os.environ.get("MAX_ITEMS", "10"))
DAYS_BACK            = int(os.environ.get("DAYS_BACK", "7"))
CONTEXT_CHARS        = 90   # characters of context around each mention
MAX_CONTEXTS_PER_STOCK = 30 # cap to keep JSON manageable

SOURCES_FILE = Path(__file__).parent / "sources.json"
OUTPUT_FILE  = Path(__file__).parent.parent / "data" / "latest.json"

# ─────────────────────────────────────────────────────────────────────────────
# Taiwan Stock Dictionary
# ─────────────────────────────────────────────────────────────────────────────

STOCK_DICT: dict[str, str] = {
    # ── 半導體 / 晶圓代工 ──────────────────────────────────────────────────
    "台積電": "2330", "台灣積體電路": "2330", "TSMC": "2330", "台積": "2330",
    "聯電":   "2303", "UMC": "2303",
    "力積電": "6770", "PSMC": "6770",
    "世界先進": "5347",
    "環球晶":  "6488",
    "合晶":    "6182",
    "嘉晶":    "3016",

    # ── IC 設計 ────────────────────────────────────────────────────────────
    "聯發科": "2454", "MediaTek": "2454", "MTK": "2454",
    "瑞昱":   "2379", "Realtek": "2379",
    "聯詠":   "3034", "Novatek": "3034",
    "矽力":   "6415",
    "信驊":   "5274",
    "創意":   "3443",
    "群聯":   "8299", "Phison": "8299",
    "義隆電": "2458",
    "原相":   "3227",
    "神盾":   "6462",
    "M31":    "6643",
    "力旺":   "3529",
    "譜瑞":   "4966",
    "聯陽":   "3038",
    "晶心科": "6533",
    "奕力":   "3598",
    "敦泰":   "3545",

    # ── OSAT / 封測 ───────────────────────────────────────────────────────
    "日月光": "3711", "ASE": "3711",

    # ── 面板 ───────────────────────────────────────────────────────────────
    "友達":   "2409", "AUO": "2409",
    "群創":   "3481", "Innolux": "3481",
    "彩晶":   "6116",

    # ── EMS / ODM ─────────────────────────────────────────────────────────
    "鴻海":   "2317", "富士康": "2317", "Foxconn": "2317", "Hon Hai": "2317",
    "廣達":   "2382", "Quanta": "2382",
    "仁寶":   "2324", "Compal": "2324",
    "緯創":   "3231", "Wistron": "3231",
    "英業達": "2356", "Inventec": "2356",
    "和碩":   "4938", "Pegatron": "4938",
    "鴻準":   "2354",

    # ── 品牌電腦 / 伺服器 ─────────────────────────────────────────────────
    "華碩":   "2357", "ASUS": "2357",
    "宏碁":   "2353", "Acer": "2353",
    "微星":   "2377", "MSI": "2377",
    "技嘉":   "2376", "GIGABYTE": "2376",
    "緯穎":   "6669",

    # ── AI 伺服器 / 散熱 ──────────────────────────────────────────────────
    "奇鋐":   "3017",
    "雙鴻":   "3324",
    "建準":   "2421",
    "超眾":   "6230",
    "訊凱":   "3088",

    # ── PCB / 載板 ────────────────────────────────────────────────────────
    "欣興":   "3037",
    "健鼎":   "3044",
    "南電":   "8046",
    "台郡":   "6269",
    "臻鼎":   "4958",
    "景碩":   "3189",
    "燿華":   "2367",
    "金像電": "2368",

    # ── 被動元件 ──────────────────────────────────────────────────────────
    "國巨":   "2327", "YAGEO": "2327",
    "禾伸堂": "3026",
    "智寶":   "2375",

    # ── 光學 / 鏡頭 ──────────────────────────────────────────────────────
    "大立光": "3008", "Largan": "3008",
    "玉晶光": "3406",
    "亞光":   "3019",

    # ── 記憶體 / 儲存 ─────────────────────────────────────────────────────
    "威剛":   "3260", "ADATA": "3260",
    "群聯":   "8299",

    # ── 電源 / 電子零組件 ─────────────────────────────────────────────────
    "台達電": "2308", "Delta": "2308",
    "正崴":   "2392",
    "可成":   "2474",
    "亞德客": "1590",

    # ── 化工 / 石化 ───────────────────────────────────────────────────────
    "台塑":   "1301",
    "南亞":   "1303",
    "台化":   "1326",
    "台塑化": "6505",

    # ── 鋼鐵 ──────────────────────────────────────────────────────────────
    "中鋼":   "2002",

    # ── 金融 ──────────────────────────────────────────────────────────────
    "國泰金": "2882", "國泰人壽": "2882",
    "富邦金": "2881", "富邦人壽": "2881",
    "中信金": "2891",
    "兆豐金": "2886",
    "台新金": "2887",
    "永豐金": "2890",
    "元大金": "2885",
    "第一金": "2892",
    "合庫金": "5880",
    "玉山金": "2884", "玉山銀行": "2884",
    "開發金": "2883",

    # ── 電信 ──────────────────────────────────────────────────────────────
    "中華電": "2412", "中華電信": "2412",
    "台灣大": "3045", "台灣大哥大": "3045", "台哥大": "3045",
    "遠傳":   "4904",

    # ── 航運 ──────────────────────────────────────────────────────────────
    "長榮":   "2603", "長榮海運": "2603",
    "陽明":   "2609", "陽明海運": "2609",
    "萬海":   "2615",
    "長榮航": "2618", "長榮航空": "2618",
    "華航":   "2610", "中華航空": "2610",

    # ── 汽車 / 零組件 ─────────────────────────────────────────────────────
    "裕隆":   "2201",
    "和泰":   "2207",

    # ── 零售 / 通路 ───────────────────────────────────────────────────────
    "統一超": "2912", "7-ELEVEN": "2912", "統一超商": "2912",
    "全家":   "5903",
    "統一":   "1216",

    # ── 建設 ──────────────────────────────────────────────────────────────
    "遠雄":   "5522",
    "興富發": "2542",

    # ── ETF ───────────────────────────────────────────────────────────────
    "台灣50":       "0050", "元大台灣50": "0050",
    "高股息":       "0056", "元大高股息": "0056",
    "國泰永續高股息": "00878",
    "富邦台50":     "006208",
    "中信關鍵半導體": "00891",

    # ── 4 位代號直接辨識（主要大型股）────────────────────────────────────
    "2330": "2330", "2317": "2317", "2454": "2454",
    "2303": "2303", "2382": "2382", "3711": "3711",
    "2409": "2409", "3008": "3008", "2379": "2379",
    "3034": "3034", "2412": "2412", "2884": "2884",
    "2882": "2882", "2881": "2881", "2891": "2891",
    "2308": "2308", "1301": "1301", "2357": "2357",
    "2353": "2353", "6670": "6670", "3481": "3481",
    "2603": "2603", "2609": "2609", "6669": "6669",
    "3017": "3017", "5274": "5274", "6533": "6533",
}

# Build canonical name map (code → display name)
CODE_TO_NAME: dict[str, str] = {
    "2330": "台積電", "2317": "鴻海",   "2454": "聯發科", "2303": "聯電",
    "2382": "廣達",   "3711": "日月光", "2409": "友達",   "3008": "大立光",
    "2379": "瑞昱",   "3034": "聯詠",   "2412": "中華電", "2884": "玉山金",
    "2882": "國泰金", "2881": "富邦金", "2891": "中信金", "1301": "台塑",
    "1303": "南亞",   "2357": "華碩",   "2353": "宏碁",   "2308": "台達電",
    "0050": "元大台灣50", "0056": "元大高股息", "00878": "國泰永續高股息",
    "3481": "群創",   "4938": "和碩",   "2324": "仁寶",   "2356": "英業達",
    "3231": "緯創",   "6770": "力積電", "5347": "世界先進","3443": "創意",
    "8299": "群聯",   "6415": "矽力",   "5274": "信驊",   "6669": "緯穎",
    "3037": "欣興",   "3044": "健鼎",   "8046": "南電",   "2327": "國巨",
    "2603": "長榮",   "2609": "陽明",   "2615": "萬海",   "2610": "華航",
    "2002": "中鋼",   "3045": "台灣大", "4904": "遠傳",   "3260": "威剛",
    "2886": "兆豐金", "2887": "台新金", "2890": "永豐金", "2885": "元大金",
    "2892": "第一金", "5880": "合庫金", "2883": "開發金",
    "2201": "裕隆",   "2207": "和泰",   "1216": "統一",   "2912": "統一超",
    "5903": "全家",   "6505": "台塑化", "2618": "長榮航", "3017": "奇鋐",
    "3324": "雙鴻",   "6533": "晶心科", "2376": "技嘉",   "2377": "微星",
    "1590": "亞德客", "2354": "鴻準",   "2474": "可成",   "2392": "正崴",
}

# ─────────────────────────────────────────────────────────────────────────────
# Stock Recognition
# ─────────────────────────────────────────────────────────────────────────────

def recognize_stocks(text: str) -> list[dict]:
    """
    掃描文字，找出所有台股提及，回傳含上下文的列表。
    對同一支股票在相近位置的重複 match 做去重。
    """
    hits: list[dict] = []
    seen: dict[str, list[int]] = {}  # code → [positions]

    for keyword, code in STOCK_DICT.items():
        for m in re.finditer(re.escape(keyword), text):
            pos = m.start()
            # Deduplicate: skip if same stock already matched within 40 chars
            if any(abs(pos - p) < 40 for p in seen.get(code, [])):
                continue
            seen.setdefault(code, []).append(pos)

            start = max(0, pos - CONTEXT_CHARS)
            end   = min(len(text), pos + len(keyword) + CONTEXT_CHARS)
            ctx   = text[start:end].replace("\n", " ").strip()

            hits.append({
                "stock_code": code,
                "stock_name": CODE_TO_NAME.get(code, keyword),
                "context": ctx,
            })

    return hits

# ─────────────────────────────────────────────────────────────────────────────
# YouTube — channel video listing
# ─────────────────────────────────────────────────────────────────────────────

def get_channel_videos(
    channel_id: str,
    max_results: int = MAX_ITEMS_PER_SOURCE,
    days_back: int   = DAYS_BACK,
) -> list[dict]:
    """取得頻道最新影片：優先 YouTube Data API v3，fallback RSS"""
    if YOUTUBE_API_KEY:
        videos = _videos_via_api(channel_id, max_results, days_back)
        if videos:
            return videos
        print(f"  [youtube] API returned 0 → fallback to RSS", file=sys.stderr)
    return _videos_via_rss(channel_id, max_results, days_back)


def _videos_via_api(channel_id: str, max_results: int, days_back: int) -> list[dict]:
    """YouTube Data API v3 /search endpoint"""
    published_after = (
        datetime.now(timezone.utc) - timedelta(days=days_back)
    ).isoformat()
    try:
        resp = requests.get(
            "https://www.googleapis.com/youtube/v3/search",
            params={
                "key":            YOUTUBE_API_KEY,
                "channelId":      channel_id,
                "part":           "snippet",
                "order":          "date",
                "type":           "video",
                "maxResults":     max_results,
                "publishedAfter": published_after,
            },
            timeout=15,
        )
        resp.raise_for_status()
        data = resp.json()
        if "error" in data:
            print(f"  [api] {data['error']['message']}", file=sys.stderr)
            return []
        videos = []
        for item in data.get("items", []):
            snippet  = item.get("snippet", {})
            video_id = item.get("id", {}).get("videoId")
            if not video_id:
                continue
            pub = snippet.get("publishedAt", "")
            videos.append({
                "id":            video_id,
                "title":         snippet.get("title", ""),
                "description":   snippet.get("description", "")[:500],
                "published_at":  pub,
                "date":          pub[:10],
                "thumbnail_url": (
                    snippet.get("thumbnails", {})
                    .get("medium", {})
                    .get("url")
                ),
            })
        print(f"  [api] {channel_id}: {len(videos)} videos")
        return videos
    except Exception as e:
        print(f"  [api] {channel_id}: {e}", file=sys.stderr)
        return []


def _videos_via_rss(channel_id: str, max_results: int, days_back: int) -> list[dict]:
    """YouTube RSS feed（無需 API key，無 bot 限制）"""
    cutoff  = datetime.now(timezone.utc) - timedelta(days=days_back)
    rss_url = f"https://www.youtube.com/feeds/videos.xml?channel_id={channel_id}"
    try:
        resp = requests.get(rss_url, timeout=15, headers={"User-Agent": "Mozilla/5.0"})
        if resp.status_code != 200:
            print(f"  [rss] {channel_id}: HTTP {resp.status_code}", file=sys.stderr)
            return []
        ns = {
            "atom":  "http://www.w3.org/2005/Atom",
            "yt":    "http://www.youtube.com/xml/schemas/2015",
            "media": "http://search.yahoo.com/mrss/",
        }
        root    = ET.fromstring(resp.content)
        videos  = []
        for entry in root.findall("atom:entry", ns)[:max_results]:
            video_id = entry.findtext("yt:videoId", namespaces=ns)
            if not video_id:
                continue
            pub_str = entry.findtext("atom:published", namespaces=ns) or ""
            # Filter by date
            try:
                pub_dt = datetime.fromisoformat(pub_str.replace("Z", "+00:00"))
                if pub_dt < cutoff:
                    continue
            except Exception:
                pass
            title    = entry.findtext("atom:title", namespaces=ns) or ""
            desc_el  = entry.find("media:group/media:description", ns)
            desc     = re.sub(
                r"<[^>]+>", "",
                (desc_el.text or "") if desc_el is not None else ""
            )[:500]
            videos.append({
                "id":            video_id,
                "title":         title,
                "description":   desc,
                "published_at":  pub_str,
                "date":          pub_str[:10],
                "thumbnail_url": f"https://i.ytimg.com/vi/{video_id}/mqdefault.jpg",
            })
        print(f"  [rss] {channel_id}: {len(videos)} videos")
        return videos
    except Exception as e:
        print(f"  [rss] {channel_id}: {e}", file=sys.stderr)
        return []

# ─────────────────────────────────────────────────────────────────────────────
# YouTube — captions (fast path, no download needed)
# ─────────────────────────────────────────────────────────────────────────────

def fetch_captions(video_id: str) -> str | None:
    """
    用 yt-dlp 取得 YouTube 字幕（json3 格式），嘗試多種 player client。
    回傳合併後的純文字，或 None（若無字幕）。
    """
    video_url = f"https://www.youtube.com/watch?v={video_id}"
    preferred = ["zh-TW", "zh-Hant", "zh", "zh-Hans", "en"]

    info = None
    for clients in [["ios"], ["tv_embedded"], ["android"], ["mweb"]]:
        try:
            opts = {
                "quiet": True, "no_warnings": True, "noplaylist": True,
                "extractor_args": {"youtube": {"player_client": clients}},
            }
            with yt_dlp.YoutubeDL(opts) as ydl:
                info = ydl.extract_info(video_url, download=False, process=False)
            if info:
                break
        except Exception:
            continue

    if not info:
        return None

    # Manual subtitles first, then auto-captions
    all_caps: dict = {}
    all_caps.update(info.get("subtitles", {}))
    all_caps.update(info.get("automatic_captions", {}))
    if not all_caps:
        return None

    caption_url: str | None = None
    for lang in preferred:
        if lang in all_caps:
            j = next((f for f in all_caps[lang] if f.get("ext") == "json3"), None)
            if j:
                caption_url = j["url"]
                break
    if not caption_url:
        for formats in all_caps.values():
            j = next((f for f in formats if f.get("ext") == "json3"), None)
            if j:
                caption_url = j["url"]
                break
    if not caption_url:
        return None

    try:
        req  = urequest.Request(caption_url, headers={"User-Agent": "Mozilla/5.0"})
        data = urequest.urlopen(req, timeout=15).read()
        obj  = json.loads(data)
        text = "".join(
            seg.get("utf8", "")
            for event in obj.get("events", [])
            for seg in event.get("segs", [])
        ).replace("\n", " ").strip()
        return text or None
    except Exception as e:
        print(f"  [captions] {video_id}: {e}", file=sys.stderr)
        return None

# ─────────────────────────────────────────────────────────────────────────────
# YouTube — audio download + Whisper transcription
# ─────────────────────────────────────────────────────────────────────────────

_whisper_model = None

def _get_whisper_model():
    global _whisper_model
    if _whisper_model is None:
        from faster_whisper import WhisperModel
        print("[whisper] Loading model (small/int8)…")
        _whisper_model = WhisperModel("small", device="cpu", compute_type="int8")
        print("[whisper] Model ready.")
    return _whisper_model


def download_audio(video_id: str, tmpdir: str) -> str | None:
    """用 yt-dlp 下載 YouTube 最佳音訊到 tmpdir，回傳檔案路徑或 None"""
    for clients in [["ios"], ["tv_embedded"], ["android"], ["mweb"]]:
        try:
            opts = {
                "format":       "bestaudio[ext=m4a]/bestaudio/best",
                "outtmpl":      os.path.join(tmpdir, "%(id)s.%(ext)s"),
                "quiet":        True,
                "no_warnings":  True,
                "noplaylist":   True,
                "max_filesize": 150 * 1024 * 1024,
                "extractor_args": {"youtube": {"player_client": clients}},
            }
            with yt_dlp.YoutubeDL(opts) as ydl:
                info = ydl.extract_info(
                    f"https://www.youtube.com/watch?v={video_id}", download=True
                )
                if (info.get("duration") or 0) > 5400:  # skip > 90 min
                    print(f"  [audio] {video_id}: too long, skip")
                    return None
            files = [f for f in os.listdir(tmpdir) if os.path.isfile(os.path.join(tmpdir, f))]
            if files:
                return os.path.join(tmpdir, files[0])
        except Exception as e:
            print(f"  [audio] {video_id} {clients}: {str(e)[:80]}", file=sys.stderr)
    return None


def transcribe_audio(audio_path: str) -> str | None:
    """用 faster-whisper 將音訊轉成逐字稿文字"""
    try:
        model = _get_whisper_model()
        segments, _ = model.transcribe(
            audio_path,
            language="zh",
            beam_size=5,
            vad_filter=True,
        )
        text = " ".join(seg.text for seg in segments).strip()
        return text or None
    except Exception as e:
        print(f"  [whisper] {audio_path}: {e}", file=sys.stderr)
        return None

# ─────────────────────────────────────────────────────────────────────────────
# YouTube — process one video
# ─────────────────────────────────────────────────────────────────────────────

def process_youtube_video(
    video: dict, source_name: str
) -> tuple[dict, list[dict]]:
    """
    處理單支 YouTube 影片：
      1. 嘗試抓字幕（快速）
      2. 若無字幕且 USE_WHISPER → 下載音訊並轉逐字稿
      3. Fallback → 標題 + 描述
    回傳 (video_entry, mention_list)
    """
    video_id  = video["id"]
    title     = video["title"]
    date      = video["date"]

    text: str | None = None
    analysis_source  = "titleAndDescription"

    # ── Step 1: captions ──────────────────────────────────────────────────
    print(f"  [{source_name}] {title[:45]!r} — fetching captions…")
    caps = fetch_captions(video_id)
    if caps and len(caps) > 50:
        text            = caps
        analysis_source = "captions"
        print(f"  ✓ captions ({len(caps)} chars)")
    else:
        print(f"  ✗ no captions")

    # ── Step 2: Whisper ───────────────────────────────────────────────────
    if text is None and USE_WHISPER:
        print(f"  ⏳ transcribing with Whisper…")
        with tempfile.TemporaryDirectory() as tmpdir:
            audio = download_audio(video_id, tmpdir)
            if audio:
                transcript = transcribe_audio(audio)
                if transcript:
                    text            = transcript
                    analysis_source = "whisper"
                    print(f"  ✓ whisper ({len(transcript)} chars)")
                else:
                    print(f"  ✗ whisper failed")

    # ── Step 3: fallback ──────────────────────────────────────────────────
    if text is None:
        text            = title + " " + video.get("description", "")
        analysis_source = "titleAndDescription"
        print(f"  ⚠ fallback → title+description")

    # ── Recognize stocks ──────────────────────────────────────────────────
    hits        = recognize_stocks(text)
    stock_codes = list({h["stock_code"] for h in hits})
    if stock_codes:
        print(f"  📌 {stock_codes}")

    video_entry = {
        "video_id":       video_id,
        "title":          title,
        "channel":        source_name,
        "date":           date,
        "stocks_found":   stock_codes,
        "analysis_source": analysis_source,
        "thumbnail_url":  video.get("thumbnail_url"),
    }

    mentions = [
        {
            "stock_code": h["stock_code"],
            "stock_name": h["stock_name"],
            "video_title": title,
            "channel":     source_name,
            "date":        date,
            "context":     h["context"],
            "analysis_source": analysis_source,
        }
        for h in hits
    ]

    return video_entry, mentions

# ─────────────────────────────────────────────────────────────────────────────
# Apple Podcast
# ─────────────────────────────────────────────────────────────────────────────

def fetch_apple_podcast_episodes(
    podcast_id: str, limit: int = MAX_ITEMS_PER_SOURCE, days_back: int = DAYS_BACK
) -> list[dict]:
    """iTunes lookup → RSS feed → parse episodes"""
    cutoff = datetime.now(timezone.utc) - timedelta(days=days_back)
    try:
        lookup = requests.get(
            f"https://itunes.apple.com/lookup?id={podcast_id}&country=tw", timeout=15
        ).json()
        results  = lookup.get("results", [])
        if not results:
            return []
        feed_url = results[0].get("feedUrl")
        if not feed_url:
            return []

        resp = requests.get(feed_url, timeout=15, headers={"User-Agent": "Mozilla/5.0"})
        resp.raise_for_status()
        root    = ET.fromstring(resp.content)
        channel = root.find("channel")
        if channel is None:
            return []

        ns       = {"itunes": "http://www.itunes.com/dtds/podcast-1.0.dtd"}
        episodes = []
        for item in channel.findall("item"):
            if len(episodes) >= limit:
                break
            title = (item.findtext("title") or "").strip()
            if not title:
                continue
            # Date filter
            pub_str = item.findtext("pubDate") or ""
            pub_dt  = None
            try:
                pub_dt = parsedate_to_datetime(pub_str)
                if pub_dt.tzinfo is None:
                    pub_dt = pub_dt.replace(tzinfo=timezone.utc)
                if pub_dt < cutoff:
                    continue
            except Exception:
                pass

            desc = re.sub(
                r"<[^>]+>", "",
                (
                    item.findtext("itunes:summary", namespaces=ns) or
                    item.findtext("description") or ""
                )
            ).strip()[:500]

            enc       = item.find("enclosure")
            audio_url = enc.get("url") if enc is not None else None
            guid      = (item.findtext("guid") or f"{podcast_id}_{len(episodes)}").strip()
            date_str  = pub_dt.strftime("%Y-%m-%d") if pub_dt else pub_str[:10]

            episodes.append({
                "id":          guid,
                "title":       title,
                "description": desc,
                "audio_url":   audio_url,
                "date":        date_str,
            })
        return episodes
    except Exception as e:
        print(f"  [apple] {podcast_id}: {e}", file=sys.stderr)
        return []


def process_podcast_episode(
    ep: dict, source: dict
) -> tuple[dict, list[dict]]:
    """處理 Podcast 集數（title+desc，或 Whisper）"""
    title       = ep["title"]
    date        = ep.get("date", "")
    source_name = source["name"]
    audio_url   = ep.get("audio_url")

    text: str | None = None
    analysis_source  = "titleAndDescription"

    if USE_WHISPER and audio_url:
        print(f"  ⏳ {title[:40]!r} — Whisper…")
        with tempfile.TemporaryDirectory() as tmpdir:
            out_path = os.path.join(tmpdir, "episode.mp3")
            try:
                resp = requests.get(audio_url, timeout=30, stream=True,
                                    headers={"User-Agent": "Mozilla/5.0"})
                with open(out_path, "wb") as f:
                    for chunk in resp.iter_content(chunk_size=65536):
                        f.write(chunk)
                text = transcribe_audio(out_path)
                if text:
                    analysis_source = "whisper"
                    print(f"  ✓ whisper ({len(text)} chars)")
            except Exception as e:
                print(f"  ✗ whisper error: {e}", file=sys.stderr)

    if text is None:
        text = title + " " + ep.get("description", "")
        analysis_source = "titleAndDescription"

    hits        = recognize_stocks(text)
    stock_codes = list({h["stock_code"] for h in hits})
    if stock_codes:
        print(f"  📌 {stock_codes}")

    video_entry = {
        "video_id":        ep["id"],
        "title":           title,
        "channel":         source_name,
        "date":            date,
        "stocks_found":    stock_codes,
        "analysis_source": analysis_source,
        "thumbnail_url":   None,
    }

    mentions = [
        {
            "stock_code":      h["stock_code"],
            "stock_name":      h["stock_name"],
            "video_title":     title,
            "channel":         source_name,
            "date":            date,
            "context":         h["context"],
            "analysis_source": analysis_source,
        }
        for h in hits
    ]

    return video_entry, mentions

# ─────────────────────────────────────────────────────────────────────────────
# Spotify
# ─────────────────────────────────────────────────────────────────────────────

def _get_spotify_token() -> str | None:
    if not SPOTIFY_CLIENT_ID or not SPOTIFY_CLIENT_SECRET:
        return None
    try:
        resp = requests.post(
            "https://accounts.spotify.com/api/token",
            data={"grant_type": "client_credentials"},
            auth=(SPOTIFY_CLIENT_ID, SPOTIFY_CLIENT_SECRET),
            timeout=10,
        )
        resp.raise_for_status()
        return resp.json().get("access_token")
    except Exception as e:
        print(f"  [spotify] token error: {e}", file=sys.stderr)
        return None


def fetch_spotify_episodes(
    show_id: str, limit: int = MAX_ITEMS_PER_SOURCE
) -> list[dict]:
    token = _get_spotify_token()
    if not token:
        return []
    cutoff = datetime.now(timezone.utc) - timedelta(days=DAYS_BACK)
    try:
        resp = requests.get(
            f"https://api.spotify.com/v1/shows/{show_id}/episodes",
            headers={"Authorization": f"Bearer {token}"},
            params={"market": "TW", "limit": limit},
            timeout=15,
        )
        resp.raise_for_status()
        items    = resp.json().get("items", [])
        episodes = []
        for item in items:
            release = item.get("release_date", "")[:10]
            try:
                rd = datetime.fromisoformat(release).replace(tzinfo=timezone.utc)
                if rd < cutoff:
                    continue
            except Exception:
                pass
            episodes.append({
                "id":          item.get("id", ""),
                "title":       item.get("name", ""),
                "description": (item.get("description") or "")[:500],
                "audio_url":   None,
                "date":        release,
            })
        return episodes
    except Exception as e:
        print(f"  [spotify] {show_id}: {e}", file=sys.stderr)
        return []

# ─────────────────────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────────────────────

def load_sources() -> list[dict]:
    try:
        with open(SOURCES_FILE, encoding="utf-8") as f:
            return json.load(f).get("sources", [])
    except Exception as e:
        print(f"[scanner] Cannot load sources: {e}", file=sys.stderr)
        return []


def main() -> None:
    print(
        f"[scanner] Start — "
        f"YOUTUBE_API={'set' if YOUTUBE_API_KEY else 'not set'} | "
        f"USE_WHISPER={USE_WHISPER} | "
        f"DAYS_BACK={DAYS_BACK}"
    )

    sources        = load_sources()
    active_sources = [s for s in sources if s.get("active", True)]
    print(f"[scanner] {len(active_sources)} active sources")

    all_mentions: list[dict] = []
    all_videos:   list[dict] = []

    for source in active_sources:
        stype = source.get("type", "")
        sname = source.get("name", "")
        ident = source.get("identifier", "")
        print(f"\n[scanner] ── {sname} ({stype}) ──")

        if stype == "youtube":
            videos = get_channel_videos(ident)
            print(f"  → {len(videos)} videos")
            for video in videos:
                v_entry, mentions = process_youtube_video(video, sname)
                all_videos.append(v_entry)
                all_mentions.extend(mentions)

        elif stype == "applePodcast":
            episodes = fetch_apple_podcast_episodes(ident)
            print(f"  → {len(episodes)} episodes")
            for ep in episodes:
                v_entry, mentions = process_podcast_episode(ep, source)
                all_videos.append(v_entry)
                all_mentions.extend(mentions)

        elif stype == "spotify":
            episodes = fetch_spotify_episodes(ident)
            print(f"  → {len(episodes)} episodes")
            for ep in episodes:
                v_entry, mentions = process_podcast_episode(ep, source)
                all_videos.append(v_entry)
                all_mentions.extend(mentions)

    # ── Build stocks ranking ───────────────────────────────────────────────
    stocks_map: dict[str, dict] = {}
    for m in all_mentions:
        code = m["stock_code"]
        if code not in stocks_map:
            stocks_map[code] = {
                "code":           code,
                "name":           m["stock_name"],
                "total_mentions": 0,
                "contexts":       [],
            }
        stocks_map[code]["total_mentions"] += 1
        if len(stocks_map[code]["contexts"]) < MAX_CONTEXTS_PER_STOCK:
            stocks_map[code]["contexts"].append({
                "video":   m["video_title"],
                "channel": m["channel"],
                "date":    m["date"],
                "text":    m["context"],
            })

    stocks_ranking = sorted(
        stocks_map.values(), key=lambda x: -x["total_mentions"]
    )

    output = {
        "updated_at":     datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S"),
        "stocks_ranking": stocks_ranking,
        "videos_scanned": all_videos,
    }

    OUTPUT_FILE.parent.mkdir(parents=True, exist_ok=True)
    with open(OUTPUT_FILE, "w", encoding="utf-8") as f:
        json.dump(output, f, ensure_ascii=False, indent=2)

    print(
        f"\n[scanner] ✅ Done — "
        f"{len(all_videos)} videos/episodes | "
        f"{len(stocks_ranking)} stocks | "
        f"{len(all_mentions)} total mentions"
    )
    print(f"[scanner] Output → {OUTPUT_FILE}")


if __name__ == "__main__":
    main()

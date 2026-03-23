#!/usr/bin/env python3
"""
Stock Mention Tracker - GitHub Actions Scanner
每日掃描 YouTube / Apple Podcast / Spotify，辨識台灣股票提及，輸出 data/latest.json
"""

import json
import os
import re
import sys
import shutil
import tempfile
import urllib.request as urequest
import xml.etree.ElementTree as ET
from datetime import datetime, timezone
from email.utils import parsedate_to_datetime
from pathlib import Path

import requests
import yt_dlp

# ─────────────────────────────────────────────
# Taiwan Stock Dictionary (常見台股)
# ─────────────────────────────────────────────

STOCK_DICT = {
    # 上市大型股
    "台積電": "2330", "TSMC": "2330", "台灣積體電路": "2330",
    "鴻海": "2317", "富士康": "2317", "Hon Hai": "2317", "Foxconn": "2317",
    "聯發科": "2454", "MediaTek": "2454",
    "台塑": "1301",
    "南亞": "1303",
    "台化": "1326",
    "中鋼": "2002",
    "台達電": "2308", "Delta": "2308",
    "聯電": "2303", "UMC": "2303",
    "廣達": "2382", "Quanta": "2382",
    "仁寶": "2324", "Compal": "2324",
    "日月光": "3711", "ASE": "3711",
    "友達": "2409", "AUO": "2409",
    "奇美": "3009",
    "群創": "3481",
    "華碩": "2357", "ASUS": "2357", "Asus": "2357",
    "宏碁": "2353", "Acer": "2353",
    "大立光": "3008", "Largan": "3008",
    "瑞昱": "2379", "Realtek": "2379",
    "聯詠": "3034", "Novatek": "3034",
    "玉山金": "2884", "玉山銀行": "2884",
    "國泰金": "2882", "國泰人壽": "2882",
    "富邦金": "2881", "富邦人壽": "2881",
    "中信金": "2891",
    "台新金": "2887",
    "第一金": "2892",
    "兆豐金": "2886",
    "合庫金": "5880",
    "元大金": "2885",
    "中華電": "2412", "中華電信": "2412", "Chunghwa": "2412",
    "台灣大": "3045", "台灣大哥大": "3045",
    "遠傳": "4904",
    "威剛": "3260",
    "創意": "3443",
    "力積電": "6770", "PSMC": "6770",
    "世界先進": "5347",
    "矽力": "6415",
    "信驊": "5274",
    "緯穎": "6669",
    "緯創": "3231",
    "英業達": "2356",
    "和碩": "4938", "Pegatron": "4938",
    "台灣高鐵": "2633",
    "統一": "1216",
    "統一超": "2912", "7-ELEVEN": "2912",
    "全家": "5903",
    "台灣50": "0050",
    "元大台灣50": "0050",
    "00878": "00878",
    "高股息": "00878",
    "台積": "2330",
    # 4碼代號直接辨識
    "2330": "2330", "2317": "2317", "2454": "2454",
    "2303": "2303", "2382": "2382", "3711": "3711",
    "2409": "2409", "3008": "3008", "2379": "2379",
    "3034": "3034", "2412": "2412", "2884": "2884",
    "2882": "2882", "2881": "2881", "2891": "2891",
}

CODE_TO_NAME = {}
for _name, _code in STOCK_DICT.items():
    if _code not in CODE_TO_NAME and not _name.isdigit() and not _name.startswith("00"):
        CODE_TO_NAME[_code] = _name

CODE_TO_NAME.update({
    "2330": "台積電", "2317": "鴻海", "2454": "聯發科", "2303": "聯電",
    "2382": "廣達", "3711": "日月光", "2409": "友達", "3008": "大立光",
    "2379": "瑞昱", "3034": "聯詠", "2412": "中華電", "2884": "玉山金",
    "2882": "國泰金", "2881": "富邦金", "2891": "中信金", "1301": "台塑",
    "1303": "南亞", "2357": "華碩", "2353": "宏碁", "2308": "台達電",
    "0050": "元大台灣50", "00878": "元大高股息",
})


# ─────────────────────────────────────────────
# Stock Recognition
# ─────────────────────────────────────────────

def recognize_stocks(text: str) -> list[dict]:
    """辨識文字中的台股股票代號和名稱"""
    found = {}
    for keyword, code in STOCK_DICT.items():
        for match in re.finditer(re.escape(keyword), text):
            if code not in found:
                start = max(0, match.start() - 40)
                end = min(len(text), match.end() + 40)
                found[code] = {
                    "stock_code": code,
                    "stock_name": CODE_TO_NAME.get(code, keyword),
                    "context": text[start:end].strip(),
                }
    return list(found.values())


# ─────────────────────────────────────────────
# Whisper Transcription
# ─────────────────────────────────────────────

_whisper_model = None


def get_whisper_model():
    global _whisper_model
    if _whisper_model is None:
        try:
            from faster_whisper import WhisperModel
            print("[whisper] Loading faster-whisper small model...")
            _whisper_model = WhisperModel("small", device="cpu", compute_type="int8")
            print("[whisper] Model ready.")
        except Exception as e:
            print(f"[whisper] Failed to load: {e}", file=sys.stderr)
    return _whisper_model


def transcribe_file(audio_path: str) -> str | None:
    """用 faster-whisper 轉逐字稿（傳入本地檔案路徑）"""
    model = get_whisper_model()
    if not model:
        return None
    try:
        segments, _ = model.transcribe(
            audio_path, beam_size=3, vad_filter=True,
            vad_parameters={"min_silence_duration_ms": 500},
        )
        result = " ".join(seg.text.strip() for seg in segments)
        return result or None
    except Exception as e:
        print(f"  [whisper] transcribe_file failed: {e}", file=sys.stderr)
        return None


def transcribe_audio_url(audio_url: str) -> str | None:
    """從 URL 下載音訊並轉逐字稿（Podcast 用）"""
    if not audio_url:
        return None
    model = get_whisper_model()
    if not model:
        return None

    tmpdir = tempfile.mkdtemp()
    try:
        ext = audio_url.split("?")[0].rsplit(".", 1)[-1][:4] or "mp3"
        dest = os.path.join(tmpdir, f"podcast.{ext}")

        req = urequest.Request(audio_url, headers={"User-Agent": "Mozilla/5.0"})
        with urequest.urlopen(req, timeout=120) as resp:
            with open(dest, "wb") as f:
                shutil.copyfileobj(resp, f)

        size_mb = os.path.getsize(dest) / 1024 / 1024
        if size_mb > 300:
            print(f"  [whisper] Audio too large ({size_mb:.0f}MB), skip")
            return None

        return transcribe_file(dest)
    except Exception as e:
        print(f"  [whisper] transcribe_audio_url: {e}", file=sys.stderr)
        return None
    finally:
        shutil.rmtree(tmpdir, ignore_errors=True)


# ─────────────────────────────────────────────
# YouTube
# ─────────────────────────────────────────────

def fetch_captions(video_id: str) -> tuple[str | None, str | None]:
    """用 yt-dlp 抓 YouTube 字幕，嘗試多種 player client，回傳 (text, lang)"""
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
        return None, None
    try:
        all_caps = {}
        all_caps.update(info.get("automatic_captions", {}))
        all_caps.update(info.get("subtitles", {}))
        if not all_caps:
            return None, None

        caption_url, found_lang = None, None
        for lang in preferred:
            if lang in all_caps:
                j = next((f for f in all_caps[lang] if f.get("ext") == "json3"), None)
                if j:
                    caption_url, found_lang = j["url"], lang
                    break
        if not caption_url:
            for lang, formats in all_caps.items():
                j = next((f for f in formats if f.get("ext") == "json3"), None)
                if j:
                    caption_url, found_lang = j["url"], lang
                    break
        if not caption_url:
            return None, None

        req = urequest.Request(
            caption_url,
            headers={"User-Agent": "com.google.ios.youtube/19.29.1 (iPhone; CPU iPhone OS 17_0 like Mac OS X)"}
        )
        data = urequest.urlopen(req, timeout=15).read()
        text = _parse_json3(data)
        return text, found_lang
    except Exception as e:
        print(f"  [captions] {video_id}: {e}", file=sys.stderr)
        return None, None


def _parse_json3(data: bytes) -> str | None:
    try:
        obj = json.loads(data)
        text = "".join(
            seg.get("utf8", "")
            for event in obj.get("events", [])
            for seg in event.get("segs", [])
        )
        return text.replace("\n", " ").strip() or None
    except Exception:
        return None


def fetch_channel_videos(channel_id: str, max_results: int = 10) -> list[dict]:
    """抓頻道最新影片：優先用 YouTube RSS（不需認證），再 fallback 到 yt-dlp"""
    videos = _fetch_channel_videos_rss(channel_id, max_results)
    if videos:
        return videos
    return _fetch_channel_videos_ytdlp(channel_id, max_results)


def _fetch_channel_videos_rss(channel_id: str, max_results: int) -> list[dict]:
    """用 YouTube RSS feed 取得影片清單（公開，無 bot 限制）"""
    rss_url = f"https://www.youtube.com/feeds/videos.xml?channel_id={channel_id}"
    try:
        resp = requests.get(rss_url, timeout=15, headers={"User-Agent": "Mozilla/5.0"})
        if resp.status_code != 200:
            return []
        ns = {
            "atom": "http://www.w3.org/2005/Atom",
            "yt": "http://www.youtube.com/xml/schemas/2015",
            "media": "http://search.yahoo.com/mrss/",
        }
        root = ET.fromstring(resp.content)
        videos = []
        for entry in root.findall("atom:entry", ns)[:max_results]:
            video_id = entry.findtext("yt:videoId", namespaces=ns)
            if not video_id:
                continue
            title = entry.findtext("atom:title", namespaces=ns) or ""
            description = (
                entry.find("media:group/media:description", ns) or
                entry.find(".//media:description", ns)
            )
            desc_text = re.sub(r"<[^>]+>", "", (description.text or "") if description is not None else "")[:1000]
            pub_str = entry.findtext("atom:published", namespaces=ns) or ""
            videos.append({
                "id": video_id,
                "title": title,
                "description": desc_text,
                "published_at": pub_str or datetime.now(timezone.utc).isoformat(),
                "thumbnail_url": f"https://i.ytimg.com/vi/{video_id}/mqdefault.jpg",
            })
        return videos
    except Exception as e:
        print(f"  [rss] {channel_id}: {e}", file=sys.stderr)
        return []


def _fetch_channel_videos_ytdlp(channel_id: str, max_results: int) -> list[dict]:
    """yt-dlp fallback：嘗試多種 URL 和 player client"""
    urls_to_try = [
        f"https://www.youtube.com/channel/{channel_id}/videos",
        f"https://www.youtube.com/channel/{channel_id}",
    ]
    clients_to_try = [["ios"], ["android"], ["mweb"]]
    for url in urls_to_try:
        for clients in clients_to_try:
            opts = {
                "quiet": True, "no_warnings": True,
                "flat_playlist": True,
                "playlist_items": f"1:{max_results}",
                "extractor_args": {"youtube": {"player_client": clients}},
            }
            try:
                with yt_dlp.YoutubeDL(opts) as ydl:
                    info = ydl.extract_info(url, download=False)
                    entries = info.get("entries", []) if info else []
                    videos = []
                    for entry in entries:
                        if not entry:
                            continue
                        video_id = entry.get("id") or entry.get("url", "").split("?v=")[-1]
                        if not video_id or len(video_id) != 11:
                            continue
                        videos.append({
                            "id": video_id,
                            "title": entry.get("title", ""),
                            "description": entry.get("description", ""),
                            "published_at": _parse_upload_date(entry.get("upload_date")),
                            "thumbnail_url": entry.get("thumbnail"),
                        })
                    if videos:
                        return videos
            except Exception:
                continue
    print(f"  [channel] {channel_id}: all methods failed", file=sys.stderr)
    return []


def transcribe_youtube(video_id: str) -> str | None:
    """下載 YouTube 音訊並轉逐字稿"""
    tmpdir = tempfile.mkdtemp()
    try:
        opts = {
            "format": "bestaudio[ext=m4a][filesize<100M]/bestaudio[filesize<100M]/bestaudio/18/best",
            "outtmpl": os.path.join(tmpdir, "%(id)s.%(ext)s"),
            "quiet": True, "no_warnings": True, "noplaylist": True,
        }
        with yt_dlp.YoutubeDL(opts) as ydl:
            info = ydl.extract_info(f"https://www.youtube.com/watch?v={video_id}", download=True)
            if (info.get("duration") or 0) > 5400:
                print(f"  [whisper] {video_id} too long, skip")
                return None
        audio_files = [f for f in os.listdir(tmpdir) if os.path.isfile(os.path.join(tmpdir, f))]
        if not audio_files:
            return None
        return transcribe_file(os.path.join(tmpdir, audio_files[0]))
    except Exception as e:
        print(f"  [whisper] {video_id}: {e}", file=sys.stderr)
        return None
    finally:
        shutil.rmtree(tmpdir, ignore_errors=True)


def _parse_upload_date(upload_date: str | None) -> str:
    if not upload_date or len(upload_date) != 8:
        return datetime.now(timezone.utc).isoformat()
    try:
        return datetime.strptime(upload_date, "%Y%m%d").replace(tzinfo=timezone.utc).isoformat()
    except Exception:
        return datetime.now(timezone.utc).isoformat()


# ─────────────────────────────────────────────
# Apple Podcast (iTunes API + RSS)
# ─────────────────────────────────────────────

def fetch_apple_podcast_episodes(podcast_id: str, limit: int = 10) -> list[dict]:
    """用 iTunes API 取得 RSS 網址，再解析 RSS 抓集數（含音訊 URL）"""
    try:
        # Step 1: 取得節目資訊 + feedUrl
        lookup = requests.get(
            f"https://itunes.apple.com/lookup?id={podcast_id}&country=tw",
            timeout=15
        ).json()
        results = lookup.get("results", [])
        if not results:
            print(f"  [apple] podcast {podcast_id}: not found", file=sys.stderr)
            return []

        feed_url = results[0].get("feedUrl")
        if not feed_url:
            print(f"  [apple] podcast {podcast_id}: no feedUrl", file=sys.stderr)
            return []

        # Step 2: 解析 RSS feed
        resp = requests.get(feed_url, timeout=15, headers={"User-Agent": "Mozilla/5.0"})
        resp.raise_for_status()
        root = ET.fromstring(resp.content)
        channel = root.find("channel")
        if channel is None:
            return []

        ns = {"itunes": "http://www.itunes.com/dtds/podcast-1.0.dtd"}
        episodes = []

        for item in channel.findall("item")[:limit]:
            title = (item.findtext("title") or "").strip()
            if not title:
                continue

            # Description（優先用 itunes:summary，再用 description）
            description = (
                item.findtext("itunes:summary", namespaces=ns) or
                item.findtext("description") or ""
            ).strip()
            # 去除 HTML tags
            description = re.sub(r"<[^>]+>", "", description)[:1000]

            pub_date = item.findtext("pubDate") or ""
            published_at = _parse_rfc_date(pub_date)

            # 音訊 URL from <enclosure>
            enclosure = item.find("enclosure")
            audio_url = enclosure.get("url") if enclosure is not None else None

            # Episode ID（用 guid 或 fallback）
            guid = (item.findtext("guid") or f"{podcast_id}_{len(episodes)}").strip()

            # 時長
            duration_str = item.findtext("itunes:duration", namespaces=ns) or ""

            episodes.append({
                "id": guid,
                "title": title,
                "description": description,
                "published_at": published_at,
                "audio_url": audio_url,
                "duration": duration_str,
            })

        return episodes

    except Exception as e:
        print(f"  [apple] {podcast_id}: {e}", file=sys.stderr)
        return []


def _parse_rfc_date(date_str: str) -> str:
    """RSS pubDate (RFC 2822) → ISO8601"""
    try:
        return parsedate_to_datetime(date_str).isoformat()
    except Exception:
        return datetime.now(timezone.utc).isoformat()


# ─────────────────────────────────────────────
# Spotify (Web API, 需要 Client Credentials)
# ─────────────────────────────────────────────

_spotify_token: str | None = None


def get_spotify_token(client_id: str, client_secret: str) -> str | None:
    global _spotify_token
    if _spotify_token:
        return _spotify_token
    try:
        import base64
        credentials = base64.b64encode(f"{client_id}:{client_secret}".encode()).decode()
        resp = requests.post(
            "https://accounts.spotify.com/api/token",
            headers={"Authorization": f"Basic {credentials}"},
            data={"grant_type": "client_credentials"},
            timeout=15,
        )
        if resp.status_code == 200:
            _spotify_token = resp.json().get("access_token")
            return _spotify_token
        print(f"  [spotify] token failed: {resp.status_code} {resp.text[:100]}", file=sys.stderr)
    except Exception as e:
        print(f"  [spotify] token error: {e}", file=sys.stderr)
    return None


def fetch_spotify_episodes(show_id: str, client_id: str, client_secret: str, limit: int = 10) -> list[dict]:
    """用 Spotify API 抓節目最新集數（音訊需 RSS，此處僅取 title+description）"""
    token = get_spotify_token(client_id, client_secret)
    if not token:
        return []
    try:
        resp = requests.get(
            f"https://api.spotify.com/v1/shows/{show_id}/episodes",
            headers={"Authorization": f"Bearer {token}"},
            params={"limit": limit, "market": "TW"},
            timeout=15,
        )
        if resp.status_code != 200:
            print(f"  [spotify] episodes {show_id}: {resp.status_code}", file=sys.stderr)
            return []

        episodes = []
        for item in resp.json().get("items", []):
            name = item.get("name", "")
            description = re.sub(r"<[^>]+>", "", item.get("description") or item.get("html_description") or "")[:1000]
            release_date = item.get("release_date", "")
            # Convert YYYY-MM-DD to ISO8601
            try:
                published_at = datetime.strptime(release_date, "%Y-%m-%d").replace(tzinfo=timezone.utc).isoformat()
            except Exception:
                published_at = datetime.now(timezone.utc).isoformat()

            # Spotify 不提供全長音訊 URL（只有 30 秒預覽），跳過音訊轉錄
            episodes.append({
                "id": item["id"],
                "title": name,
                "description": description,
                "published_at": published_at,
                "audio_url": None,  # Spotify API 無法取得完整音訊
                "duration": str(item.get("duration_ms", 0) // 1000),
            })
        return episodes
    except Exception as e:
        print(f"  [spotify] {show_id}: {e}", file=sys.stderr)
        return []


# ─────────────────────────────────────────────
# Process Episodes (shared for podcasts)
# ─────────────────────────────────────────────

def process_podcast_episode(
    ep: dict,
    source: dict,
    source_type: str,
    use_whisper: bool,
) -> tuple[dict, list[dict]]:
    """處理單一 Podcast 集數，回傳 (episode_json, mentions)"""
    title = ep["title"]
    description = ep.get("description", "")
    audio_url = ep.get("audio_url")
    ep_id = ep["id"]

    transcript_text = None
    analysis_source = "titleAndDescription"

    if use_whisper and audio_url:
        print(f"  ⏳ {title[:40]!r} → transcribing...")
        transcript_text = transcribe_audio_url(audio_url)
        if transcript_text:
            analysis_source = "transcript"
            print(f"  ✓ {title[:40]!r} whisper ({len(transcript_text)} chars)")
        else:
            print(f"  ✗ whisper failed → title+desc")
    elif not audio_url:
        print(f"  – {title[:40]!r} no audio URL → title+desc")
    else:
        print(f"  – {title[:40]!r} whisper disabled → title+desc")

    # Build text
    parts = [title]
    if description:
        parts.append(description)
    if transcript_text:
        parts.append(transcript_text)
    text_to_analyze = "\n".join(parts)

    stock_hits = recognize_stocks(text_to_analyze)
    stock_codes = list({h["stock_code"] for h in stock_hits})

    if stock_codes:
        print(f"  📌 {title[:40]!r} → {stock_codes}")

    episode = {
        "id": ep_id,
        "title": title,
        "published_at": ep.get("published_at", datetime.now(timezone.utc).isoformat()),
        "source_type": source_type,
        "source_name": source["name"],
        "thumbnail_url": None,
        "analysis_source": analysis_source,
        "mentioned_stocks": stock_codes,
    }

    mentions = [{
        "stock_code": h["stock_code"],
        "stock_name": h["stock_name"],
        "mentioned_at": ep.get("published_at", datetime.now(timezone.utc).isoformat()),
        "context": h["context"],
        "analysis_source": analysis_source,
        "source_type": source_type,
        "source_name": source["name"],
        "episode_id": ep_id,
        "episode_title": title,
    } for h in stock_hits]

    return episode, mentions


# ─────────────────────────────────────────────
# Main Scanner
# ─────────────────────────────────────────────

def scan_source(
    source: dict,
    use_whisper: bool,
    spotify_client_id: str,
    spotify_client_secret: str,
) -> tuple[list[dict], list[dict]]:
    """掃描單一來源，回傳 (episodes, mentions)"""
    source_type = source["type"]
    identifier = source["identifier"]

    if source_type == "youtube":
        print(f"\n[scan] 📺 {source['name']} ({identifier})")
        videos = fetch_channel_videos(identifier, max_results=10)
        print(f"  → {len(videos)} videos found")

        episodes, mentions = [], []
        for video in videos:
            vid_id = video["id"]
            title = video["title"]
            description = video.get("description", "")

            # 1. YouTube 字幕（快速）
            captions, lang = fetch_captions(vid_id)
            if captions:
                transcript_text = captions
                analysis_source = "transcript"
                print(f"  ✓ {vid_id} captions ({lang}, {len(captions)} chars)")
            elif use_whisper:
                print(f"  ⏳ {vid_id} transcribing with Whisper...")
                transcript_text = transcribe_youtube(vid_id)
                analysis_source = "transcript" if transcript_text else "titleAndDescription"
                if transcript_text:
                    print(f"  ✓ {vid_id} whisper ({len(transcript_text)} chars)")
                else:
                    print(f"  ✗ {vid_id} whisper failed → title+desc")
            else:
                transcript_text = None
                analysis_source = "titleAndDescription"
                print(f"  – {vid_id} no captions → title+desc")

            parts = [title]
            if description:
                parts.append(description[:500])
            if transcript_text:
                parts.append(transcript_text)
            text_to_analyze = "\n".join(parts)

            stock_hits = recognize_stocks(text_to_analyze)
            stock_codes = list({h["stock_code"] for h in stock_hits})
            if stock_codes:
                print(f"  📌 {title[:40]!r} → {stock_codes}")

            episodes.append({
                "id": vid_id,
                "title": title,
                "published_at": video["published_at"],
                "source_type": "youtube",
                "source_name": source["name"],
                "thumbnail_url": video.get("thumbnail_url"),
                "analysis_source": analysis_source,
                "mentioned_stocks": stock_codes,
            })
            for h in stock_hits:
                mentions.append({
                    "stock_code": h["stock_code"],
                    "stock_name": h["stock_name"],
                    "mentioned_at": video["published_at"],
                    "context": h["context"],
                    "analysis_source": analysis_source,
                    "source_type": "youtube",
                    "source_name": source["name"],
                    "episode_id": vid_id,
                    "episode_title": title,
                })
        return episodes, mentions

    elif source_type == "applePodcast":
        print(f"\n[scan] 🎙 {source['name']} (Apple Podcast {identifier})")
        raw_eps = fetch_apple_podcast_episodes(identifier, limit=10)
        print(f"  → {len(raw_eps)} episodes found")

        episodes, mentions = [], []
        for ep in raw_eps:
            ep_result, ep_mentions = process_podcast_episode(ep, source, "applePodcast", use_whisper)
            episodes.append(ep_result)
            mentions.extend(ep_mentions)
        return episodes, mentions

    elif source_type == "spotify":
        print(f"\n[scan] 🎵 {source['name']} (Spotify {identifier})")
        if not spotify_client_id or not spotify_client_secret:
            print("  [skip] SPOTIFY_CLIENT_ID / SPOTIFY_CLIENT_SECRET not set", file=sys.stderr)
            return [], []
        raw_eps = fetch_spotify_episodes(identifier, spotify_client_id, spotify_client_secret, limit=10)
        print(f"  → {len(raw_eps)} episodes found (title+description only)")

        episodes, mentions = [], []
        for ep in raw_eps:
            # Spotify 無法取得全長音訊，強制 titleAndDescription
            ep["audio_url"] = None
            ep_result, ep_mentions = process_podcast_episode(ep, source, "spotify", use_whisper=False)
            episodes.append(ep_result)
            mentions.extend(ep_mentions)
        return episodes, mentions

    else:
        print(f"  [skip] {source['name']}: unknown type '{source_type}'", file=sys.stderr)
        return [], []


def main():
    repo_root = Path(__file__).parent.parent
    sources_path = repo_root / "scanner" / "sources.json"
    output_path = repo_root / "data" / "latest.json"

    with open(sources_path) as f:
        sources_config = json.load(f)

    active_sources = [s for s in sources_config["sources"] if s.get("active", True)]
    print(f"[scanner] {len(active_sources)} active sources")

    use_whisper = os.environ.get("USE_WHISPER", "false").lower() == "true"
    spotify_client_id = os.environ.get("SPOTIFY_CLIENT_ID", "")
    spotify_client_secret = os.environ.get("SPOTIFY_CLIENT_SECRET", "")

    if use_whisper:
        print("[scanner] Whisper transcription ENABLED")
    if spotify_client_id:
        print("[scanner] Spotify credentials found")

    all_episodes: list[dict] = []
    all_mentions: list[dict] = []

    for source in active_sources:
        episodes, mentions = scan_source(source, use_whisper, spotify_client_id, spotify_client_secret)
        all_episodes.extend(episodes)
        all_mentions.extend(mentions)

    result = {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "sources": active_sources,
        "episodes": all_episodes,
        "mentions": all_mentions,
    }

    output_path.parent.mkdir(parents=True, exist_ok=True)
    with open(output_path, "w", encoding="utf-8") as f:
        json.dump(result, f, ensure_ascii=False, indent=2)

    print(f"\n[scanner] ✅ Done: {len(all_episodes)} episodes, {len(all_mentions)} mentions")
    print(f"[scanner] Output: {output_path}")


if __name__ == "__main__":
    main()

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
TEST_DOWNLOAD_ONLY = os.environ.get("TEST_DOWNLOAD_ONLY", "false").lower() == "true"
SPOTIFY_CLIENT_ID  = os.environ.get("SPOTIFY_CLIENT_ID", "")
SPOTIFY_CLIENT_SECRET = os.environ.get("SPOTIFY_CLIENT_SECRET", "")

# Path to Netscape-format cookies file (set by workflow from YOUTUBE_COOKIES secret)
COOKIES_FILE = os.environ.get("YOUTUBE_COOKIES_FILE", "")

MAX_ITEMS_PER_SOURCE = int(os.environ.get("MAX_ITEMS", "10"))
DAYS_BACK            = int(os.environ.get("DAYS_BACK", "7"))
CONTEXT_CHARS        = 90   # characters of context around each mention
MAX_CONTEXTS_PER_STOCK = 30 # cap to keep JSON manageable

SOURCES_FILE     = Path(__file__).parent / "sources.json"
OUTPUT_FILE      = Path(__file__).parent.parent / "data" / "latest.json"
STOCKS_CACHE_FILE = Path(__file__).parent.parent / "data" / "stocks.json"

# ─────────────────────────────────────────────────────────────────────────────
# Static aliases: English names, abbreviations, nicknames not in official list
# ─────────────────────────────────────────────────────────────────────────────

ALIASES: dict[str, str] = {
    # Semiconductors
    "TSMC": "2330", "台積": "2330", "台灣積體電路": "2330",
    "UMC": "2303",
    "PSMC": "6770",
    "ASE": "3711",
    # IC Design
    "MediaTek": "2454", "MTK": "2454",
    "Realtek": "2379",
    "Novatek": "3034",
    "Phison": "8299",
    # Panel
    "AUO": "2409",
    "Innolux": "3481",
    # EMS / ODM
    "Foxconn": "2317", "Hon Hai": "2317", "富士康": "2317",
    "Quanta": "2382",
    "Compal": "2324",
    "Wistron": "3231",
    "Inventec": "2356",
    "Pegatron": "4938",
    # Brands
    "ASUS": "2357",
    "Acer": "2353",
    "MSI": "2377",
    "GIGABYTE": "2376",
    # Optical
    "Largan": "3008",
    # Passive
    "YAGEO": "2327",
    # Storage
    "ADATA": "3260",
    # Power
    "Delta": "2308",
    # Telecom
    "中華電信": "2412", "台灣大哥大": "3045", "台哥大": "3045",
    # Shipping
    "長榮海運": "2603", "陽明海運": "2609", "長榮航空": "2618", "中華航空": "2610",
    # Retail
    "7-ELEVEN": "2912", "統一超商": "2912",
    # Finance
    "國泰人壽": "2882", "富邦人壽": "2881", "玉山銀行": "2884",
    # ETF common names
    "台灣50": "0050", "元大台灣50": "0050",
    "高股息": "0056", "元大高股息": "0056",
    "國泰永續高股息": "00878",
    "富邦台50": "006208",
    "中信關鍵半導體": "00891",
    "00919": "00919", "00929": "00929", "00934": "00934",
}

# ─────────────────────────────────────────────────────────────────────────────
# Sentiment keywords (financial Chinese)
# ─────────────────────────────────────────────────────────────────────────────

# ── 強看多關鍵字（權重 0.6）────────────────────────────────────────────────────
BULLISH_STRONG: set[str] = {
    # 短線交易信號
    "買進", "布局", "強勢", "利多", "創高", "突破",
    "籌碼轉強", "外資買超", "逢低買", "上漲", "噴出", "飆漲", "加碼", "看漲",
    # 產業趨勢看多
    "產業趨勢向上", "超級循環", "需求爆發", "供不應求",
    "AI需求不減", "AI商機", "新應用爆發",
    "訂單滿載", "急單湧入", "出貨暢旺",
    "毛利率提升", "獲利成長", "EPS創高",
    "景氣復甦", "景氣回升", "景氣反轉向上",
    "產業底部確立", "拉貨潮", "超級成長", "爆發性成長", "倍增成長",
    "獨家供應", "技術領先",
}

# ── 弱看多關鍵字（權重 0.3）────────────────────────────────────────────────────
BULLISH_MILD: set[str] = {
    # 短線
    "看好", "低估", "便宜", "機會",
    # 產業趨勢中性偏多
    "景氣回溫中", "庫存健康", "需求穩定", "訂單穩定",
    "產業整合", "強者恆強", "等待催化劑", "靜待訊號",
    "趨勢不變", "需求持續成長", "長期趨勢", "結構性成長",
    "AI趨勢", "長線看好", "轉機股", "產業升級", "訂單能見度高",
    "客戶拉貨", "市佔率提升", "競爭力提升", "護城河",
    "本益比低估", "股價落後基本面",
    "需求回溫", "新客戶導入", "新產品貢獻", "差異化競爭", "新應用打開",
}

# ── 強看空關鍵字（權重 0.6）────────────────────────────────────────────────────
BEARISH_STRONG: set[str] = {
    # 短線交易信號
    "賣出", "獲利了結", "看空", "利空", "超漲", "籌碼轉弱",
    "外資賣超", "下跌", "套牢", "泡沫", "高估", "減碼", "看跌",
    # 產業趨勢看空
    "產業趨勢向下", "趨勢反轉", "景氣下行",
    "需求萎縮", "供過於求",
    "砍單", "客戶砍單",
    "產業寒冬", "景氣谷底", "景氣衰退",
    "獲利衰退", "EPS下修",
    "市佔率流失", "產能過剩",
    "需求見頂", "高峰已過",
    "景氣反轉向下",
}

# ── 弱看空關鍵字（權重 0.3）────────────────────────────────────────────────────
BEARISH_MILD: set[str] = {
    # 短線
    "回檔", "壓力", "風險", "貴", "警示",
    # 產業趨勢中性偏空
    "景氣還在底部", "需求還沒起來", "庫存還高", "還需要時間",
    "短期壓力", "暫時觀望",
    "需求疲弱", "庫存去化", "庫存調整", "去庫存",
    "訂單縮減", "毛利率下滑",
    "競爭加劇", "價格戰", "殺價競爭",
    "成長趨緩", "客戶去庫存", "終端需求疲弱",
    "本益比過高", "股價超漲基本面",
    "需求轉弱", "推貨困難", "替代品威脅", "技術被取代", "失去競爭力",
}

# ── 前後文配對規則（優先於單一關鍵字，命中時權重 0.6）──────────────────────────
# 格式：(樞紐詞, [看多搭配詞], [看空搭配詞])
CONTEXT_PAIRS: list[tuple[str, list[str], list[str]]] = [
    ("庫存",  ["去化完畢", "落底", "健康"],          ["持續累積", "還高", "嚴重"]),
    ("循環",  ["向上", "啟動", "開始"],              ["向下", "結束", "反轉"]),
    ("趨勢",  ["不變", "持續", "看好", "向上"],      ["反轉", "結束", "改變", "向下"]),
    ("需求",  ["強勁", "成長", "爆發", "回溫"],      ["疲弱", "萎縮", "下滑", "見頂"]),
    ("訂單",  ["滿載", "能見度高", "急單", "回溫"],  ["縮減", "砍單", "延後", "取消"]),
    ("景氣",  ["復甦", "回升", "反轉向上"],          ["衰退", "下行", "反轉向下"]),
    ("毛利率", ["提升", "改善", "擴大"],             ["下滑", "壓縮", "縮小"]),
    ("EPS",   ["成長", "創高", "上修"],              ["衰退", "下修", "縮水"]),
]

# 向下相容：供舊版引用
BULLISH_KEYWORDS = BULLISH_STRONG | BULLISH_MILD
BEARISH_KEYWORDS = BEARISH_STRONG | BEARISH_MILD

# ─────────────────────────────────────────────────────────────────────────────
# US Stock built-in dictionary (Chinese/English aliases)
# Format: (keyword_list, ticker, display_name, sector)
# ─────────────────────────────────────────────────────────────────────────────

_US_STOCKS_DATA: list[tuple[list[str], str, str, str]] = [
    (["輝達", "黃仁勳", "NVIDIA", "Nvidia", "NVDA"],  "NVDA",  "NVIDIA",             "AI晶片"),
    (["美光", "Micron", "MU"],                         "MU",    "Micron",             "記憶體"),
    (["AMD", "超微半導體"],                             "AMD",   "AMD",                "AI晶片"),
    (["蘋果", "Apple", "AAPL"],                        "AAPL",  "Apple",              "消費電子"),
    (["微軟", "Microsoft", "MSFT", "OpenAI"],          "MSFT",  "Microsoft",          "雲端/AI"),
    (["谷歌", "Google", "Alphabet", "GOOGL"],          "GOOGL", "Alphabet",           "雲端/AI"),
    (["亞馬遜", "Amazon", "AMZN"],                     "AMZN",  "Amazon",             "雲端"),
    (["特斯拉", "Tesla", "TSLA"],                      "TSLA",  "Tesla",              "電動車"),
    (["台積電ADR", "台積ADR", "TSM"],                  "TSM",   "TSMC ADR",           "晶圓代工"),
    (["英特爾", "Intel", "INTC"],                      "INTC",  "Intel",              "半導體"),
    (["高通", "Qualcomm", "QCOM"],                     "QCOM",  "Qualcomm",           "手機晶片"),
    (["博通", "Broadcom", "AVGO"],                     "AVGO",  "Broadcom",           "AI網路"),
    (["ARM"],                                          "ARM",   "ARM Holdings",       "晶片架構"),
    (["Meta", "臉書", "Facebook", "META"],             "META",  "Meta",               "社群媒體"),
    (["Netflix", "網飛", "NFLX"],                      "NFLX",  "Netflix",            "串流媒體"),
    (["波音", "Boeing"],                               "BA",    "Boeing",             "航太"),
    (["摩根大通", "JPMorgan", "JPM"],                  "JPM",   "JPMorgan",           "金融"),
    (["巴菲特", "波克夏", "Berkshire"],                "BRK.B", "Berkshire",          "金融"),
    (["輝瑞", "Pfizer", "PFE"],                        "PFE",   "Pfizer",             "生技"),
    (["埃克森美孚", "ExxonMobil", "XOM"],              "XOM",   "ExxonMobil",         "能源"),
    (["Salesforce", "CRM"],                            "CRM",   "Salesforce",         "企業軟體"),
    (["甲骨文", "Oracle", "ORCL"],                     "ORCL",  "Oracle",             "企業軟體"),
    (["IBM"],                                          "IBM",   "IBM",                "企業軟體"),
    (["Dell", "戴爾", "DELL"],                         "DELL",  "Dell",               "伺服器"),
    (["惠普", "HPQ"],                                  "HPQ",   "HP Inc",             "消費電子"),
    (["思科", "Cisco", "CSCO"],                        "CSCO",  "Cisco",              "網路設備"),
    (["威騰", "Western Digital", "WDC"],               "WDC",   "Western Digital",    "儲存"),
    (["希捷", "Seagate", "STX"],                       "STX",   "Seagate",            "儲存"),
    (["安森美", "ON Semi"],                            "ON",    "ON Semi",            "半導體"),
    (["德州儀器", "Texas Instruments", "TXN"],         "TXN",   "Texas Instruments",  "半導體"),
    (["應用材料", "Applied Materials", "AMAT"],        "AMAT",  "Applied Materials",  "半導體設備"),
    (["科林研發", "Lam Research", "LRCX"],             "LRCX",  "Lam Research",       "半導體設備"),
    (["科磊", "KLA", "KLAC"],                          "KLAC",  "KLA",                "半導體設備"),
    (["ASML"],                                         "ASML",  "ASML",               "半導體設備"),
    (["Palantir", "PLTR"],                             "PLTR",  "Palantir",           "AI軟體"),
    (["超微電腦", "Super Micro", "SMCI"],              "SMCI",  "Super Micro",        "伺服器"),
    (["Arista", "ANET"],                               "ANET",  "Arista Networks",    "AI網路"),
    (["Marvell", "MRVL"],                              "MRVL",  "Marvell",            "AI晶片"),
    (["Rivian", "RIVN"],                               "RIVN",  "Rivian",             "電動車"),
    (["美國銀行", "Bank of America", "BAC"],           "BAC",   "Bank of America",    "金融"),
    (["高盛", "Goldman Sachs"],                        "GS",    "Goldman Sachs",      "金融"),
    (["Moderna", "莫德納", "MRNA"],                    "MRNA",  "Moderna",            "生技"),
    (["嬌生", "JNJ"],                                  "JNJ",   "J&J",                "生技"),
    (["雪佛龍", "Chevron", "CVX"],                     "CVX",   "Chevron",            "能源"),
    (["洛克希德", "Lockheed Martin", "LMT"],           "LMT",   "Lockheed Martin",    "航太"),
    (["雷神", "Raytheon", "RTX"],                      "RTX",   "Raytheon",           "航太"),
    (["Disney", "迪士尼", "DIS"],                      "DIS",   "Disney",             "串流媒體"),
    # 光通訊 / CPO
    (["Lumentum", "流明騰", "LITE"],                   "LITE",  "Lumentum",           "光通訊"),
    (["Coherent", "COHR"],                             "COHR",  "Coherent",           "光通訊"),
    (["Fabrinet", "法布瑞", "FN"],                     "FN",    "Fabrinet",           "光通訊"),
    (["Ciena", "CIEN"],                                "CIEN",  "Ciena",              "光通訊"),
    (["Viavi", "VIAV"],                                "VIAV",  "Viavi Solutions",    "光通訊"),
    (["Applied Optoelectronics", "AAOI"],              "AAOI",  "Applied Opto",       "光通訊"),
    (["II-VI", "IIVI"],                                "IIVI",  "II-VI",              "光通訊"),
    # 銅纜 / 高速連接
    (["Amphenol", "安費諾", "APH"],                    "APH",   "Amphenol",           "高速連接"),
    (["TE Connectivity", "TEL"],                       "TEL",   "TE Connectivity",    "高速連接"),
    (["Credo Technology", "CRDO"],                     "CRDO",  "Credo Technology",   "高速連接"),
    (["Astera Labs", "ALAB"],                          "ALAB",  "Astera Labs",        "高速連接"),
    # 液冷 / 電網
    (["Vertiv", "VRT"],                                "VRT",   "Vertiv",             "液冷/電網"),
    (["Eaton", "ETN"],                                 "ETN",   "Eaton",              "液冷/電網"),
    (["Quanta Services", "PWR"],                       "PWR",   "Quanta Services",    "液冷/電網"),
    (["GE Vernova", "GEV"],                            "GEV",   "GE Vernova",         "液冷/電網"),
]

US_KEYWORD_TO_CODE: dict[str, str] = {}
US_CODE_TO_INFO:    dict[str, dict] = {}
for _kws, _ticker, _name, _sector in _US_STOCKS_DATA:
    US_CODE_TO_INFO[_ticker] = {"name": _name, "sector": _sector}
    for _kw in _kws:
        US_KEYWORD_TO_CODE[_kw] = _ticker

# ─────────────────────────────────────────────────────────────────────────────
# Taiwan stock sector mapping (code → sector)
# ─────────────────────────────────────────────────────────────────────────────

TW_STOCK_SECTORS: dict[str, str] = {
    # 晶圓代工
    "2330": "晶圓代工", "2303": "晶圓代工", "6770": "晶圓代工",
    # IC設計
    "2454": "IC設計",   "2379": "IC設計",   "3034": "IC設計",
    "6415": "IC設計",   "3443": "IC設計",   "5274": "IC設計",   "6533": "IC設計",
    # 組裝代工
    "2317": "組裝代工", "4938": "組裝代工",
    # 伺服器
    "2382": "伺服器",   "3231": "伺服器",   "2356": "伺服器",   "6669": "伺服器",
    # 電源管理
    "2308": "電源管理", "2301": "電源管理",
    # 半導體設備
    "6187": "半導體設備", "3131": "半導體設備", "3583": "半導體設備",
    # 記憶體
    "2408": "記憶體",   "2344": "記憶體",   "2337": "記憶體",
    # NAND Flash
    "8299": "NAND Flash", "6286": "NAND Flash",
    # PCB載板
    "3037": "PCB載板",  "8046": "PCB載板",  "3189": "PCB載板",
    # PCB
    "4958": "PCB",      "3044": "PCB",      "2368": "PCB",      "2367": "PCB",
    # CCL
    "2383": "CCL",      "6213": "CCL",
    # FPC
    "6153": "FPC",      "6269": "FPC",
    # 散熱
    "3324": "散熱",     "3017": "散熱",     "2421": "散熱",     "6230": "散熱",
    # CPO光通訊
    "6451": "CPO光通訊", "2345": "CPO光通訊",
    "3234": "CPO光通訊", "3081": "CPO光通訊", "6616": "CPO光通訊",
    "4977": "CPO光通訊", "3706": "CPO光通訊", "6183": "CPO光通訊",
    # 被動元件
    "2327": "被動元件", "2492": "被動元件", "3026": "被動元件",
    # 封裝
    "3711": "封裝",
    # 面板
    "2409": "面板",     "3481": "面板",
    # 金融
    "2881": "金融", "2882": "金融", "2883": "金融", "2884": "金融",
    "2885": "金融", "2886": "金融", "2887": "金融", "2890": "金融",
    "2891": "金融", "2892": "金融", "5880": "金融",
    # 航運
    "2609": "航運",     "2603": "航運",     "2615": "航運",
    # 電動車零件
    "1536": "電動車",   "3665": "電動車",   "1319": "電動車",
    # 太陽能
    "6443": "太陽能",   "6244": "太陽能",
    # 生技
    "4180": "生技",     "6547": "生技",     "4174": "生技",
    # ETF
    "0050": "ETF",  "0056": "ETF",  "00878": "ETF", "006208": "ETF",
    "00891": "ETF", "00919": "ETF", "00929": "ETF", "00934": "ETF",
    # 電信
    "2412": "電信",     "3045": "電信",     "4904": "電信",
    # 航空
    "2618": "航空",     "2610": "航空",
    # 鋼鐵
    "2002": "鋼鐵",
}

# Runtime-populated dicts (filled by build_stock_dict() in main)
STOCK_DICT:   dict[str, str] = {}
CODE_TO_NAME: dict[str, str] = {}
STOCK_MARKET: dict[str, str] = {}  # code → "TW" or "US"
STOCK_SECTOR: dict[str, str] = {}  # code → sector name

# ─────────────────────────────────────────────────────────────────────────────
# Dynamic stock list — TWSE + TPEx OpenAPI
# ─────────────────────────────────────────────────────────────────────────────

def fetch_stock_list() -> list[dict]:
    """
    從 TWSE（上市）與 TPEx（上櫃）官方 OpenAPI 抓取完整股票清單。
    每筆格式：{"code": "2330", "name": "台積電", "market": "twse"}
    失敗時 fallback 讀取快取 data/stocks.json。
    """
    TWSE_URL = "https://openapi.twse.com.tw/v1/referenceData/listOfSecurities"
    TPEX_URL = "https://www.tpex.org.tw/openapi/v1/mopsfin_t187ap03_O"

    stocks: list[dict] = []

    def _fetch(url: str, market: str) -> list[dict]:
        try:
            resp = requests.get(url, timeout=15, headers={"Accept": "application/json"})
            resp.raise_for_status()
            data = resp.json()
            result = []
            for item in data:
                code = (item.get("Code") or item.get("SecuritiesCode") or "").strip()
                name = (item.get("Name") or item.get("CompanyName") or "").strip()
                # Keep only numeric codes (exclude warrants, preferred shares, etc.)
                if code and name and re.match(r"^\d{4,6}$", code):
                    result.append({"code": code, "name": name, "market": market})
            print(f"  [stocks] {market}: {len(result)} securities fetched", file=sys.stderr)
            return result
        except Exception as e:
            print(f"  [stocks] {market} fetch error: {e}", file=sys.stderr)
            return []

    twse = _fetch(TWSE_URL, "twse")
    tpex = _fetch(TPEX_URL, "tpex")
    stocks = twse + tpex

    if stocks:
        # Save to cache
        STOCKS_CACHE_FILE.parent.mkdir(parents=True, exist_ok=True)
        with open(STOCKS_CACHE_FILE, "w", encoding="utf-8") as f:
            json.dump({
                "updated_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S"),
                "count": len(stocks),
                "stocks": stocks,
            }, f, ensure_ascii=False, indent=2)
        print(f"  [stocks] Saved {len(stocks)} stocks to cache", file=sys.stderr)
    else:
        # Fallback 1: local cache
        print("  [stocks] Falling back to cached stock list", file=sys.stderr)
        try:
            with open(STOCKS_CACHE_FILE, encoding="utf-8") as f:
                stocks = json.load(f).get("stocks", [])
            print(f"  [stocks] Loaded {len(stocks)} stocks from cache", file=sys.stderr)
        except Exception as e:
            print(f"  [stocks] Cache read error: {e}", file=sys.stderr)

        # Fallback 2: built-in minimal list (covers top ~100 commonly mentioned stocks)
        if not stocks:
            print("  [stocks] Using built-in fallback stock list", file=sys.stderr)
            stocks = [
                {"code":"2330","name":"台積電","market":"twse"},{"code":"2317","name":"鴻海","market":"twse"},
                {"code":"2454","name":"聯發科","market":"twse"},{"code":"2303","name":"聯電","market":"twse"},
                {"code":"2382","name":"廣達","market":"twse"},{"code":"3711","name":"日月光投控","market":"twse"},
                {"code":"2409","name":"友達","market":"twse"},{"code":"3008","name":"大立光","market":"twse"},
                {"code":"2379","name":"瑞昱","market":"twse"},{"code":"3034","name":"聯詠","market":"twse"},
                {"code":"2412","name":"中華電","market":"twse"},{"code":"2884","name":"玉山金","market":"twse"},
                {"code":"2882","name":"國泰金","market":"twse"},{"code":"2881","name":"富邦金","market":"twse"},
                {"code":"2891","name":"中信金","market":"twse"},{"code":"1301","name":"台塑","market":"twse"},
                {"code":"1303","name":"南亞","market":"twse"},{"code":"2357","name":"華碩","market":"twse"},
                {"code":"2353","name":"宏碁","market":"twse"},{"code":"2308","name":"台達電","market":"twse"},
                {"code":"2376","name":"技嘉","market":"twse"},{"code":"2377","name":"微星","market":"twse"},
                {"code":"3481","name":"群創","market":"twse"},{"code":"4938","name":"和碩","market":"twse"},
                {"code":"2324","name":"仁寶","market":"twse"},{"code":"2356","name":"英業達","market":"twse"},
                {"code":"3231","name":"緯創","market":"twse"},{"code":"6770","name":"力積電","market":"twse"},
                {"code":"5347","name":"世界先進","market":"twse"},{"code":"3443","name":"創意","market":"twse"},
                {"code":"8299","name":"群聯","market":"twse"},{"code":"6415","name":"矽力-KY","market":"twse"},
                {"code":"5274","name":"信驊","market":"twse"},{"code":"6669","name":"緯穎","market":"twse"},
                {"code":"3037","name":"欣興","market":"twse"},{"code":"3044","name":"健鼎","market":"twse"},
                {"code":"8046","name":"南電","market":"twse"},{"code":"2327","name":"國巨","market":"twse"},
                {"code":"2603","name":"長榮","market":"twse"},{"code":"2609","name":"陽明","market":"twse"},
                {"code":"2615","name":"萬海","market":"twse"},{"code":"2610","name":"華航","market":"twse"},
                {"code":"2618","name":"長榮航","market":"twse"},{"code":"2002","name":"中鋼","market":"twse"},
                {"code":"3045","name":"台灣大","market":"twse"},{"code":"4904","name":"遠傳","market":"twse"},
                {"code":"2412","name":"中華電","market":"twse"},{"code":"3260","name":"威剛","market":"twse"},
                {"code":"2886","name":"兆豐金","market":"twse"},{"code":"2887","name":"台新金","market":"twse"},
                {"code":"2890","name":"永豐金","market":"twse"},{"code":"2885","name":"元大金","market":"twse"},
                {"code":"2892","name":"第一金","market":"twse"},{"code":"5880","name":"合庫金","market":"twse"},
                {"code":"2883","name":"開發金","market":"twse"},{"code":"2201","name":"裕隆","market":"twse"},
                {"code":"2207","name":"和泰車","market":"twse"},{"code":"1216","name":"統一","market":"twse"},
                {"code":"2912","name":"統一超","market":"twse"},{"code":"5903","name":"全家","market":"twse"},
                {"code":"6505","name":"台塑化","market":"twse"},{"code":"3017","name":"奇鋐","market":"twse"},
                {"code":"3324","name":"雙鴻","market":"twse"},{"code":"6533","name":"晶心科","market":"twse"},
                {"code":"1326","name":"台化","market":"twse"},{"code":"6488","name":"環球晶","market":"twse"},
                {"code":"2354","name":"鴻準","market":"twse"},{"code":"2474","name":"可成","market":"twse"},
                {"code":"1590","name":"亞德客-KY","market":"twse"},{"code":"6182","name":"合晶","market":"twse"},
                {"code":"3016","name":"嘉晶","market":"twse"},{"code":"2458","name":"義隆","market":"twse"},
                {"code":"3227","name":"原相","market":"twse"},{"code":"6462","name":"神盾","market":"twse"},
                {"code":"6643","name":"M31","market":"twse"},{"code":"3529","name":"力旺","market":"twse"},
                {"code":"4966","name":"譜瑞-KY","market":"twse"},{"code":"3038","name":"全台晶像","market":"twse"},
                {"code":"3598","name":"奕力","market":"twse"},{"code":"3545","name":"敦泰","market":"twse"},
                {"code":"6116","name":"彩晶","market":"twse"},{"code":"6269","name":"台郡","market":"twse"},
                {"code":"4958","name":"臻鼎-KY","market":"twse"},{"code":"3189","name":"景碩","market":"twse"},
                {"code":"2367","name":"燿華","market":"twse"},{"code":"2368","name":"金像電","market":"twse"},
                {"code":"3026","name":"禾伸堂","market":"twse"},{"code":"2375","name":"智寶","market":"twse"},
                {"code":"3406","name":"玉晶光","market":"twse"},{"code":"3019","name":"亞光","market":"twse"},
                {"code":"2392","name":"正崴","market":"twse"},{"code":"5522","name":"遠雄","market":"twse"},
                {"code":"2542","name":"興富發","market":"twse"},{"code":"2421","name":"建準","market":"twse"},
                {"code":"6230","name":"超眾","market":"twse"},{"code":"3088","name":"艾訊","market":"twse"},
                {"code":"0050","name":"元大台灣50","market":"twse"},{"code":"0056","name":"元大高股息","market":"twse"},
                {"code":"00878","name":"國泰永續高股息","market":"twse"},{"code":"006208","name":"富邦台50","market":"twse"},
                {"code":"00891","name":"中信關鍵半導體","market":"twse"},{"code":"00919","name":"群益台灣精選高息","market":"twse"},
                {"code":"00929","name":"復華台灣科技優息","market":"twse"},{"code":"00934","name":"中信成長高股息","market":"twse"},
            ]

    return stocks


def build_stock_dict(
    stocks: list[dict],
) -> tuple[dict[str, str], dict[str, str], dict[str, str], dict[str, str]]:
    """
    從台股清單 + US built-in dict 建立：
    - stock_dict:   keyword → code
    - code_to_name: code → canonical name
    - stock_market: code → "TW" | "US"
    - stock_sector: code → sector name
    """
    code_to_name: dict[str, str] = {}
    stock_dict:   dict[str, str] = {}
    stock_market: dict[str, str] = {}
    stock_sector: dict[str, str] = {}

    # ── Taiwan stocks (TWSE / TPEx) ───────────────────────────────────────
    for s in stocks:
        code = s["code"]
        name = s["name"]
        code_to_name[code] = name
        stock_dict[name]   = code
        stock_dict[code]   = code
        stock_market[code] = "TW"
        if code in TW_STOCK_SECTORS:
            stock_sector[code] = TW_STOCK_SECTORS[code]

    # ── US stocks (built-in) — added BEFORE aliases so aliases can override ─
    for kw, ticker in US_KEYWORD_TO_CODE.items():
        stock_dict[kw] = ticker
    for ticker, info in US_CODE_TO_INFO.items():
        if ticker not in code_to_name:
            code_to_name[ticker] = info["name"]
        stock_market[ticker] = "US"
        stock_sector[ticker] = info["sector"]

    # ── Taiwan aliases (override conflicts; TW wins over US for same keyword) ─
    for alias, code in ALIASES.items():
        stock_dict[alias] = code
        if re.match(r"^\d{4,6}$", alias) and alias not in code_to_name:
            code_to_name[alias] = alias
        if code not in stock_market:
            stock_market[code] = "TW"

    return stock_dict, code_to_name, stock_market, stock_sector

# ─────────────────────────────────────────────────────────────────────────────
# Stock Recognition
# ─────────────────────────────────────────────────────────────────────────────

def recognize_stocks(text: str) -> list[dict]:
    """
    掃描文字，找出所有台股 / 美股提及，回傳含上下文的列表。
    英文關鍵字加 word-boundary 避免誤匹配；相近重複 match 去重。
    """
    hits: list[dict] = []
    seen: dict[str, list[int]] = {}  # code → [positions]

    for keyword, code in STOCK_DICT.items():
        # Use word boundaries for ASCII-starting keywords (avoids partial matches)
        if re.match(r"^[A-Za-z]", keyword):
            pattern = r"(?<![A-Za-z0-9])" + re.escape(keyword) + r"(?![A-Za-z0-9])"
        else:
            pattern = re.escape(keyword)

        try:
            matches = list(re.finditer(pattern, text))
        except re.error:
            continue

        for m in matches:
            pos = m.start()
            # Deduplicate: skip if same stock already matched within 40 chars
            if any(abs(pos - p) < 40 for p in seen.get(code, [])):
                continue
            seen.setdefault(code, []).append(pos)

            start = max(0, pos - CONTEXT_CHARS)
            end   = min(len(text), pos + len(keyword) + CONTEXT_CHARS)
            ctx   = text[start:end].replace("\n", " ").strip()

            hits.append({
                "stock_code":   code,
                "stock_name":   CODE_TO_NAME.get(code, keyword),
                "stock_market": STOCK_MARKET.get(code, "TW"),
                "stock_sector": STOCK_SECTOR.get(code),
                "context":      ctx,
            })

    return hits


def analyze_sentiment(text: str) -> tuple[str, float]:
    """
    Returns (label, score) where label is 'bullish'/'bearish'/'neutral'
    and score is 0.0 (bearish) to 1.0 (bullish).

    Scoring:
    1. Context pairs (pivot + followup in same text) → ±0.6 each
    2. Strong keywords → ±0.6 each
    3. Mild keywords → ±0.3 each
    Final score = bullish_weight / (bullish_weight + bearish_weight)
    Fallback to SnowNLP when no signals found.
    """
    bull_w = 0.0
    bear_w = 0.0

    # 1. Context pair rules (checked first, highest priority)
    for pivot, pos_words, neg_words in CONTEXT_PAIRS:
        if pivot in text:
            for w in pos_words:
                if w in text:
                    bull_w += 0.6
            for w in neg_words:
                if w in text:
                    bear_w += 0.6

    # 2. Strong individual keywords
    for kw in BULLISH_STRONG:
        if kw in text:
            bull_w += 0.6
    for kw in BEARISH_STRONG:
        if kw in text:
            bear_w += 0.6

    # 3. Mild individual keywords
    for kw in BULLISH_MILD:
        if kw in text:
            bull_w += 0.3
    for kw in BEARISH_MILD:
        if kw in text:
            bear_w += 0.3

    if bull_w == 0.0 and bear_w == 0.0:
        try:
            from snownlp import SnowNLP
            score = float(SnowNLP(text[:200]).sentiments)
            if score > 0.6:
                return "bullish", round(score, 3)
            elif score < 0.4:
                return "bearish", round(score, 3)
        except Exception:
            pass
        return "neutral", 0.5

    total_w = bull_w + bear_w
    score = round(bull_w / total_w, 3)
    if score > 0.5:
        return "bullish", score
    elif score < 0.5:
        return "bearish", score
    return "neutral", 0.5

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
    取得 YouTube 字幕文字。
    優先用 youtube-transcript-api（輕量、不易被偵測），
    失敗再 fallback yt-dlp。
    """
    preferred = ["zh-TW", "zh-Hant", "zh", "zh-Hans", "en"]

    # ── 1. youtube-transcript-api ──────────────────────────────────────────
    try:
        from youtube_transcript_api import YouTubeTranscriptApi, NoTranscriptFound, TranscriptsDisabled
        api = YouTubeTranscriptApi()
        transcript_list = api.list(video_id)
        transcript = None
        for lang in preferred:
            try:
                transcript = transcript_list.find_transcript([lang])
                break
            except Exception:
                continue
        if transcript is None:
            # Try any available transcript
            try:
                transcript = next(iter(transcript_list))
            except StopIteration:
                pass
        if transcript:
            fetched = transcript.fetch()
            text = " ".join(s.text for s in fetched).replace("\n", " ").strip()
            if text:
                return text
    except Exception:
        pass

    # yt-dlp fallback removed — always blocked by YouTube bot detection on CI
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
                "format":       "bestaudio/best",
                "outtmpl":      os.path.join(tmpdir, "%(id)s.%(ext)s"),
                "quiet":        True,
                "no_warnings":  True,
                "noplaylist":   True,
                "max_filesize": 150 * 1024 * 1024,
                "extractor_args": {"youtube": {"player_client": clients}},
            }
            if COOKIES_FILE and os.path.isfile(COOKIES_FILE):
                opts["cookiefile"] = COOKIES_FILE
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
    if text is None and (USE_WHISPER or TEST_DOWNLOAD_ONLY):
        print(f"  ⏳ {'testing audio download' if TEST_DOWNLOAD_ONLY else 'transcribing with Whisper'}…")
        with tempfile.TemporaryDirectory() as tmpdir:
            audio = download_audio(video_id, tmpdir)
            if audio:
                if TEST_DOWNLOAD_ONLY:
                    size = os.path.getsize(audio) // 1024
                    print(f"  ✓ download OK ({size} KB) — skipping Whisper (TEST_DOWNLOAD_ONLY)")
                else:
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

    mentions = []
    for h in hits:
        label, score = analyze_sentiment(h["context"])
        mentions.append({
            "stock_code":      h["stock_code"],
            "stock_name":      h["stock_name"],
            "stock_market":    h.get("stock_market", "TW"),
            "stock_sector":    h.get("stock_sector"),
            "video_title":     title,
            "channel":         source_name,
            "date":            date,
            "context":         h["context"],
            "analysis_source": analysis_source,
            "sentiment":       label,
            "sentiment_score": score,
        })

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

    mentions = []
    for h in hits:
        label, score = analyze_sentiment(h["context"])
        mentions.append({
            "stock_code":      h["stock_code"],
            "stock_name":      h["stock_name"],
            "stock_market":    h.get("stock_market", "TW"),
            "stock_sector":    h.get("stock_sector"),
            "video_title":     title,
            "channel":         source_name,
            "date":            date,
            "context":         h["context"],
            "analysis_source": analysis_source,
            "sentiment":       label,
            "sentiment_score": score,
        })

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

def load_history() -> dict:
    """Load existing latest.json for cumulative merging. Returns empty structure if not found."""
    if OUTPUT_FILE.exists():
        try:
            with open(OUTPUT_FILE, encoding="utf-8") as f:
                data = json.load(f)
            n_videos = len(data.get("videos_scanned", []))
            n_stocks = len(data.get("stocks_ranking", []))
            print(f"[scanner] History loaded: {n_videos} videos, {n_stocks} stocks")
            return data
        except Exception as e:
            print(f"[scanner] Could not load history (starting fresh): {e}", file=sys.stderr)
    return {"stocks_ranking": [], "sectors_ranking": [], "videos_scanned": []}


def get_video_key(video: dict) -> str:
    """Unique dedup key: prefer video_id, fallback to title+date."""
    vid = (video.get("video_id") or "").strip()
    if vid:
        return vid
    return f"{video.get('title', '')}_{video.get('date', '')}"


def merge_into_history(
    history: dict,
    new_videos: list[dict],
    new_mentions: list[dict],
) -> dict:
    """
    Merge this scan's results into cumulative history.
    - Skips videos already seen (dedup by video_id or title+date)
    - Appends new mention contexts to existing stocks
    - Recalculates total_mentions and sectors_ranking from all data
    """
    existing_keys = {get_video_key(v) for v in history["videos_scanned"]}

    actually_new: list[dict] = []
    for v in new_videos:
        if get_video_key(v) not in existing_keys:
            actually_new.append(v)

    skipped = len(new_videos) - len(actually_new)
    print(f"[scanner] New: {len(actually_new)} videos/episodes (skipped {skipped} duplicates)")

    merged_videos = history["videos_scanned"] + actually_new
    new_titles    = {v["title"] for v in actually_new}

    # Start from existing stocks
    merged_stocks: dict[str, dict] = {}
    for s in history.get("stocks_ranking", []):
        merged_stocks[s["code"]] = {
            "code":     s["code"],
            "name":     s["name"],
            "market":   s.get("market", "TW"),
            "sector":   s.get("sector"),
            "contexts": list(s["contexts"]),
        }

    # Add contexts from new videos only
    for m in new_mentions:
        if m["video_title"] not in new_titles:
            continue
        code = m["stock_code"]
        if code not in merged_stocks:
            merged_stocks[code] = {
                "code":     code,
                "name":     m["stock_name"],
                "market":   m.get("stock_market", "TW"),
                "sector":   m.get("stock_sector"),
                "contexts": [],
            }
        if len(merged_stocks[code]["contexts"]) < MAX_CONTEXTS_PER_STOCK:
            merged_stocks[code]["contexts"].append({
                "video":           m["video_title"],
                "channel":         m["channel"],
                "date":            m["date"],
                "text":            m["context"],
                "analysis_source": m.get("analysis_source", "titleAndDescription"),
                "sentiment":       m.get("sentiment", "neutral"),
                "sentiment_score": m.get("sentiment_score", 0.5),
            })

    # Rebuild stocks_ranking with daily aggregation and sentiment_score
    stocks_ranking = []
    for info in merged_stocks.values():
        ctxs = info["contexts"]
        if not ctxs:
            continue
        # Daily aggregation
        daily: dict[str, dict] = {}
        for ctx in ctxs:
            d = ctx.get("date", "")[:10]
            if d not in daily:
                daily[d] = {"mentions": 0, "bullish": 0, "bearish": 0, "neutral": 0}
            daily[d]["mentions"] += 1
            sent = ctx.get("sentiment", "neutral")
            daily[d][sent] = daily[d].get(sent, 0) + 1
        for d, stats in daily.items():
            b = stats["bullish"]
            bear = stats["bearish"]
            signaled = b + bear
            stats["sentiment_score"] = round(b / signaled, 3) if signaled > 0 else 0.5
        # Overall sentiment_score
        total = len(ctxs)
        bullish_total = sum(1 for c in ctxs if c.get("sentiment") == "bullish")
        bearish_total = sum(1 for c in ctxs if c.get("sentiment") == "bearish")
        signaled = bullish_total + bearish_total
        sentiment_score = round(bullish_total / signaled, 3) if signaled > 0 else 0.5
        stocks_ranking.append({
            **info,
            "total_mentions":  total,
            "sentiment_score": sentiment_score,
            "daily":           daily,
        })
    stocks_ranking.sort(key=lambda x: -x["total_mentions"])

    # Rebuild sectors_ranking
    sectors_map: dict[str, dict] = {}
    for stock in stocks_ranking:
        sector = stock.get("sector")
        if not sector:
            continue
        market = stock.get("market", "TW")
        key    = f"{market}_{sector}"
        if key not in sectors_map:
            sectors_map[key] = {"sector": sector, "market": market,
                                "total_mentions": 0, "stock_codes": []}
        sectors_map[key]["total_mentions"] += stock["total_mentions"]
        sectors_map[key]["stock_codes"].append(stock["code"])
    sectors_ranking = sorted(sectors_map.values(), key=lambda x: -x["total_mentions"])

    return {
        "updated_at":      datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S"),
        "stocks_ranking":  stocks_ranking,
        "sectors_ranking": sectors_ranking,
        "videos_scanned":  merged_videos,
    }


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

    # ── Build dynamic stock dictionary ────────────────────────────────────
    global STOCK_DICT, CODE_TO_NAME, STOCK_MARKET, STOCK_SECTOR
    print("[scanner] Fetching Taiwan stock list…")
    stocks = fetch_stock_list()
    STOCK_DICT, CODE_TO_NAME, STOCK_MARKET, STOCK_SECTOR = build_stock_dict(stocks)
    us_count = sum(1 for v in STOCK_MARKET.values() if v == "US")
    tw_count = sum(1 for v in STOCK_MARKET.values() if v == "TW")
    print(f"[scanner] Stock dict ready — {len(STOCK_DICT)} keywords | TW: {tw_count}, US: {us_count}")

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

    # ── Merge with cumulative history ─────────────────────────────────────
    history = load_history()
    output  = merge_into_history(history, all_videos, all_mentions)
    stocks_ranking = output["stocks_ranking"]

    OUTPUT_FILE.parent.mkdir(parents=True, exist_ok=True)
    with open(OUTPUT_FILE, "w", encoding="utf-8") as f:
        json.dump(output, f, ensure_ascii=False, indent=2)

    print(
        f"\n[scanner] ✅ Done — "
        f"{len(output['videos_scanned'])} total videos | "
        f"{len(stocks_ranking)} stocks | "
        f"{len(all_mentions)} new mentions this run"
    )
    print(f"[scanner] Output → {OUTPUT_FILE}")


if __name__ == "__main__":
    main()

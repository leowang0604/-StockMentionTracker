import importlib.util
import json
import sys
import tempfile
import types
import unittest
from unittest import mock
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SCANNER_PATH = ROOT / "scanner" / "main.py"
STOCKS_PATH = ROOT / "data" / "stocks.json"


def load_scanner():
    sys.modules["requests"] = types.SimpleNamespace(
        get=lambda *args, **kwargs: None,
        post=lambda *args, **kwargs: None,
    )
    sys.modules["yt_dlp"] = types.SimpleNamespace(YoutubeDL=object)
    spec = importlib.util.spec_from_file_location("scanner_main", SCANNER_PATH)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    stocks = json.loads(STOCKS_PATH.read_text(encoding="utf-8"))["stocks"]
    by_code = {str(stock.get("code", "")): stock for stock in stocks}
    for stock in [
        {"code": "2330", "name": "台積電", "market": "listed", "sector": "半導體業"},
        {"code": "2317", "name": "鴻海", "market": "listed", "sector": "其他電子業"},
        {"code": "2059", "name": "川湖", "market": "listed", "sector": "電子零組件業"},
        {"code": "2368", "name": "金像電", "market": "listed", "sector": "電子零組件業"},
        {"code": "2615", "name": "萬海", "market": "listed", "sector": "航運業"},
        {"code": "3026", "name": "禾伸堂", "market": "listed", "sector": "電子零組件業"},
        {"code": "3450", "name": "聯鈞", "market": "listed", "sector": "半導體業"},
        {"code": "6147", "name": "頎邦", "market": "listed", "sector": "半導體業"},
        {"code": "6214", "name": "精誠", "market": "listed", "sector": "資訊服務業"},
        {"code": "6669", "name": "緯穎", "market": "listed", "sector": "電腦及週邊設備業"},
        {"code": "6690", "name": "安碁資訊", "market": "listed", "sector": "資訊服務業"},
        {"code": "8131", "name": "福懋科", "market": "listed", "sector": "半導體業"},
        {"code": "8043", "name": "蜜望實", "market": "listed", "sector": "電子零組件業"},
        {"code": "00403A", "name": "00403A", "market": "listed", "sector": "ETF・主動型"},
        {"code": "00993A", "name": "主動安聯台灣", "market": "listed", "sector": "ETF・主動型"},
        {"code": "GS", "name": "Goldman Sachs", "market": "US", "sector": "金融"},
    ]:
        by_code.setdefault(stock["code"], stock)
    stocks = list(by_code.values())
    (
        module.STOCK_DICT,
        module.CODE_TO_NAME,
        module.STOCK_MARKET,
        module.STOCK_SECTOR,
        module.NAME_TO_CODE,
    ) = module.build_stock_dict(stocks)
    module.STOCK_SECTOR.update({
        "2010": "鋼鐵工業",
        "2891": "金融",
        "3004": "鋼鐵工業",
        "3532": "半導體業",
        "5880": "金融",
        "8131": "半導體業",
    })
    return module


class ValidatorRegressionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.scanner = load_scanner()

    def validate(self, row, text):
        return self.scanner._validate_gemini_stocks([row], text)

    def validate_isolated(self, row, text):
        with tempfile.TemporaryDirectory() as tmpdir:
            candidates_path = Path(tmpdir) / "alias_candidates.json"
            rejected_path = Path(tmpdir) / "rejected_aliases.json"
            candidates_path.write_text("{}", encoding="utf-8")
            rejected_path.write_text("{}", encoding="utf-8")
            old_candidates = self.scanner.ALIAS_CANDIDATES_FILE
            old_rejected = self.scanner.REJECTED_ALIASES_FILE
            self.scanner.ALIAS_CANDIDATES_FILE = candidates_path
            self.scanner.REJECTED_ALIASES_FILE = rejected_path
            try:
                return self.validate(row, text)
            finally:
                self.scanner.ALIAS_CANDIDATES_FILE = old_candidates
                self.scanner.REJECTED_ALIASES_FILE = old_rejected

    def test_official_name_still_resolves(self):
        text = "台積電營收持續成長，市場仍然看好。"
        hits = self.validate(
            {
                "name": "台積電",
                "code": "2330",
                "context": text,
                "sentiment": "bullish",
                "score": 0.7,
            },
            text,
        )
        self.assertEqual([hit["stock_code"] for hit in hits], ["2330"])

    def test_gemini_context_is_always_recentered_and_bounded(self):
        text = ("這是節目前言與閒聊。" * 220) + "接著討論台積電先進製程與三奈米展望。" + ("後續市場說明。" * 80)
        hits = self.validate(
            {
                "name": "台積電",
                "code": "2330",
                "context": text,
                "sentiment": "neutral",
                "score": 0.5,
            },
            text,
        )
        self.assertEqual(len(hits), 1)
        self.assertIn("台積電", hits[0]["context"])
        self.assertLessEqual(len(hits[0]["context"]), 303)
        self.assertEqual(hits[0]["position"], text.index("台積電"))
        self.assertIn(hits[0]["matched_keyword"], hits[0]["context"])

    def test_similar_stock_name_uses_actual_transcript_term(self):
        text = "前面先談台積電先進製程。" + ("其他市場內容。" * 80) + "後面回到利基電的成熟製程與產能。"
        hits = self.validate(
            {
                "name": "力積電",
                "code": "6770",
                "whisper_original": "利基電",
                "context": "前面先談台積電先進製程。",
                "sentiment": "bullish",
                "score": 0.7,
            },
            text,
        )
        self.assertEqual([hit["stock_code"] for hit in hits], ["6770"])
        self.assertEqual(hits[0]["matched_keyword"], "利基電")
        self.assertIn("利基電", hits[0]["context"])
        self.assertNotIn("台積電", hits[0]["context"])

    def test_merge_preserves_distinct_segments_for_same_stock(self):
        keyword_hits = [
            {
                "stock_code": "2330",
                "stock_name": "台積電",
                "stock_market": "TW",
                "stock_sector": "半導體業",
                "matched_keyword": "台積電",
                "context": "第一段談台積電先進製程。",
                "position": 100,
                "mention_count": 1,
            },
            {
                "stock_code": "2330",
                "stock_name": "台積電",
                "stock_market": "TW",
                "stock_sector": "半導體業",
                "matched_keyword": "台積電",
                "context": "第二段談台積電資本支出。",
                "position": 500,
                "mention_count": 1,
            },
        ]
        gemini_hits = [{
            "stock_code": "2330",
            "stock_name": "台積電",
            "stock_market": "TW",
            "stock_sector": "半導體業",
            "matched_keyword": "台積電",
            "context": "第一段談台積電先進製程。",
            "position": 100,
            "sentiment": "bullish",
            "sentiment_score": 0.8,
            "extraction_mode": "gemini",
            "mention_count": 1,
        }]

        hits = self.scanner._merge_extraction_results(keyword_hits, gemini_hits)

        self.assertEqual(len(hits), 2)
        self.assertEqual([hit["position"] for hit in hits], [100, 500])
        self.assertTrue(all("台積電" in hit["context"] for hit in hits))
        self.assertTrue(all(hit["extraction_mode"] == "gemini" for hit in hits))

    def test_second_pass_merge_does_not_collapse_existing_segments(self):
        base_hits = [
            {
                "stock_code": "2330",
                "stock_name": "台積電",
                "context": "第一段談台積電先進製程。",
                "matched_keyword": "台積電",
                "position": 100,
                "extraction_mode": "keyword",
            },
            {
                "stock_code": "2330",
                "stock_name": "台積電",
                "context": "第二段談台積電資本支出。",
                "matched_keyword": "台積電",
                "position": 500,
                "extraction_mode": "keyword",
            },
        ]
        extra_hits = [{
            "stock_code": "2330",
            "stock_name": "台積電",
            "context": "第一段談台積電先進製程。",
            "matched_keyword": "台積電",
            "position": 100,
            "sentiment": "bullish",
            "sentiment_score": 0.8,
            "extraction_mode": "gemini",
        }]

        hits = self.scanner._merge_additional_hits(base_hits, extra_hits)

        self.assertEqual(len(hits), 2)
        self.assertEqual([hit["position"] for hit in hits], [100, 500])

    def test_confirmed_whisper_alias_keeps_priority_over_gemini_guess(self):
        text = "維印借到很多AI大客戶的單，營收成長但毛利承壓。"
        hits = self.validate(
            {
                "name": "維熹",
                "code": "3501",
                "whisper_original": "維印",
                "context": text,
                "sentiment": "bullish",
                "score": 0.7,
            },
            text,
        )
        self.assertEqual([hit["stock_code"] for hit in hits], ["6669"])

    def test_existing_whisper_alias_still_resolves(self):
        text = "被動元件族群裡面的和聲堂最近營收也不錯。"
        hits = self.validate(
            {
                "name": "禾伸堂",
                "code": "3026",
                "whisper_original": "和聲堂",
                "context": text,
                "sentiment": "neutral",
                "score": 0.5,
            },
            text,
        )
        self.assertEqual([hit["stock_code"] for hit in hits], ["3026"])

    def test_jincheng_info_alias_resolves_to_systex_not_acer_cyber(self):
        text = "跟以前金城資訊一樣，他是配5塊。"
        hits = self.scanner.recognize_stocks(text)
        self.assertIn("6214", [hit["stock_code"] for hit in hits])
        self.assertNotIn("6690", [hit["stock_code"] for hit in hits])

    def test_gemini_misread_jincheng_info_remaps_to_systex_not_acer_cyber(self):
        text = "跟以前金城資訊一樣，他是配5塊。"
        hits = self.validate(
            {
                "name": "安碁資訊",
                "code": "6690",
                "whisper_original": "金城資訊",
                "context": text,
                "sentiment": "neutral",
                "score": 0.5,
            },
            text,
        )
        self.assertEqual([hit["stock_code"] for hit in hits], ["6214"])
        self.assertEqual([hit["matched_keyword"] for hit in hits], ["金城資訊"])

    def test_active_etf_short_code_403a_does_not_merge_into_993a(self):
        text = "像我們常常講到981A 403A 992A 991A，各自有他們喜歡的領域。"
        hits = self.scanner.recognize_stocks(text)
        codes = [hit["stock_code"] for hit in hits]
        self.assertIn("00403A", codes)
        self.assertNotIn("00993A", codes)

    def test_active_etf_993a_still_resolves_to_anlian(self):
        text = "我要看到安聯的993A，也要看到群益的992A。"
        hits = self.scanner.recognize_stocks(text)
        codes = [hit["stock_code"] for hit in hits]
        self.assertIn("00993A", codes)
        self.assertIn("00992A", codes)

    def test_gse_does_not_match_short_ticker_gs(self):
        text = "我記得好像GSE有寫，下個禮拜某個A加也要進去寫。"
        hits = self.validate(
            {
                "name": "Goldman Sachs",
                "code": "GS",
                "context": text,
                "sentiment": "neutral",
                "score": 0.5,
            },
            text,
        )
        self.assertEqual(hits, [])

    def test_standalone_gs_still_matches_goldman_sachs(self):
        text = "GS 這次上修了目標價，市場反應偏中性。"
        hits = self.validate(
            {
                "name": "Goldman Sachs",
                "code": "GS",
                "context": text,
                "sentiment": "neutral",
                "score": 0.5,
            },
            text,
        )
        self.assertEqual([hit["stock_code"] for hit in hits], ["GS"])

    def test_spacex_official_ticker_is_recognized(self):
        text = "SpaceX 掛牌後，市場開始重新評估低軌衛星供應鏈。"
        hits = self.scanner.recognize_stocks(text)
        spacex_hits = [hit for hit in hits if hit["stock_code"] == "SPCX"]
        self.assertEqual(len(spacex_hits), 1)
        self.assertEqual(spacex_hits[0]["stock_name"], "SpaceX")

    def test_arm_chinese_alias_is_recognized(self):
        text = "安謀這次公布新的手機晶片架構，市場反應偏正面。"
        hits = self.scanner.recognize_stocks(text)
        self.assertIn("ARM", [hit["stock_code"] for hit in hits])

    def test_arm_one_letter_whisper_error_survives_short_us_identity_gate(self):
        text = "ARN 這家公司最近股價上漲，市場也在討論它的新晶片架構。"
        with tempfile.TemporaryDirectory() as tmpdir:
            candidates_path = Path(tmpdir) / "alias_candidates.json"
            rejected_path = Path(tmpdir) / "rejected_aliases.json"
            candidates_path.write_text("{}", encoding="utf-8")
            rejected_path.write_text("{}", encoding="utf-8")
            old_candidates = self.scanner.ALIAS_CANDIDATES_FILE
            old_rejected = self.scanner.REJECTED_ALIASES_FILE
            self.scanner.ALIAS_CANDIDATES_FILE = candidates_path
            self.scanner.REJECTED_ALIASES_FILE = rejected_path
            try:
                hits = self.validate(
                    {
                        "name": "ARM",
                        "code": "ARM",
                        "whisper_original": "ARN",
                        "context": text,
                        "sentiment": "bullish",
                        "score": 0.7,
                    },
                    text,
                )
            finally:
                self.scanner.ALIAS_CANDIDATES_FILE = old_candidates
                self.scanner.REJECTED_ALIASES_FILE = old_rejected
        self.assertEqual([hit["stock_code"] for hit in hits], ["ARM"])

    def test_short_us_correction_still_requires_same_length_identity(self):
        text = "ND 這家公司最近股價上漲，市場正在討論晶片題材。"
        hits = self.validate(
            {
                "name": "AMD",
                "code": "AMD",
                "whisper_original": "ND",
                "context": text,
                "sentiment": "bullish",
                "score": 0.7,
            },
            text,
        )
        self.assertEqual(hits, [])

    def test_parenthetical_gemini_name_resolves_case_insensitively(self):
        text = "接下來討論 Intel 的先進製程與晶圓代工策略。"
        hits = self.validate(
            {
                "name": "Inter（intel）",
                "code": "",
                "context": text,
                "sentiment": "neutral",
                "score": 0.5,
            },
            text,
        )
        self.assertEqual([hit["stock_code"] for hit in hits], ["INTC"])

    def test_trailing_attention_marker_has_clean_spoken_alias(self):
        self.assertEqual(self.scanner.STOCK_DICT.get("愛普"), "6531")
        text = "愛普這次矽電容缺口擴大，市場正在討論後續訂單。"
        hits = self.validate(
            {
                "name": "愛普",
                "code": "6531",
                "context": text,
                "sentiment": "neutral",
                "score": 0.5,
            },
            text,
        )
        self.assertEqual([hit["stock_code"] for hit in hits], ["6531"])

    def test_clear_phonetic_match_survives_unrelated_sector_context(self):
        if self.scanner.lazy_pinyin is None:
            self.skipTest("pypinyin is not installed")

        text = "車用零件今天漲價，不過福茂科這檔股票也有新的訂單題材。"
        self.assertTrue(self.scanner._has_strong_sector_mismatch(text, "8131"))
        self.assertTrue(self.scanner._has_clear_phonetic_support("福茂科", "8131"))
        with tempfile.TemporaryDirectory() as tmpdir:
            candidates_path = Path(tmpdir) / "alias_candidates.json"
            rejected_path = Path(tmpdir) / "rejected_aliases.json"
            candidates_path.write_text("{}", encoding="utf-8")
            rejected_path.write_text("{}", encoding="utf-8")
            old_candidates = self.scanner.ALIAS_CANDIDATES_FILE
            old_rejected = self.scanner.REJECTED_ALIASES_FILE
            self.scanner.ALIAS_CANDIDATES_FILE = candidates_path
            self.scanner.REJECTED_ALIASES_FILE = rejected_path
            try:
                hits = self.validate(
                    {
                        "name": "福懋科",
                        "code": "8131",
                        "whisper_original": "福茂科",
                        "context": text,
                        "sentiment": "neutral",
                        "score": 0.5,
                    },
                    text,
                )
            finally:
                self.scanner.ALIAS_CANDIDATES_FILE = old_candidates
                self.scanner.REJECTED_ALIASES_FILE = old_rejected
        self.assertEqual([hit["stock_code"] for hit in hits], ["8131"])

    def test_non_phonetic_sector_mismatch_stays_rejected(self):
        text = "被動元件今天漲價，CPU 供應狀況則維持正常。"
        self.assertTrue(self.scanner._has_strong_sector_mismatch(text, "2301"))
        self.assertFalse(self.scanner._has_clear_phonetic_support("CPU", "2301"))
        hits = self.validate(
            {
                "name": "光寶科",
                "code": "2301",
                "whisper_original": "CPU",
                "context": text,
                "sentiment": "neutral",
                "score": 0.5,
            },
            text,
        )
        self.assertEqual(hits, [])

    def test_sector_scoped_aliases_override_wrong_gemini_targets(self):
        cases = [
            (
                "矽晶圓族群今天很強，環球金、中美金和台盛科都亮燈漲停。",
                "中美金", "中信金", "2891", "5483",
            ),
            (
                "被動元件裡面的台慶柯今天鎖漲停，電感也要漲價。",
                "台慶柯", "台勝科", "3532", "3357",
            ),
            (
                "低軌衛星的重點指標股升達科偏弱，SpaceX 供應鏈受到關注。",
                "升達科", "豐達科", "3004", "3491",
            ),
            (
                "低階被動元件漲價，滑星科是二哥，電容與電阻報價都在走高。",
                "滑星科", "台星科", "3265", "2492",
            ),
            (
                "最近高股息成分股除息，富方美連續兩天貼息，投信也在調節。",
                "富方美", "豐泰", "9910", "8454",
            ),
            (
                "被動元件裡面的信長店有新訂單，電阻材料也準備漲價。",
                "信長店", "日月光投控", "3711", "6173",
            ),
        ]
        for text, original, wrong_name, wrong_code, expected_code in cases:
            with self.subTest(original=original):
                hits = self.validate_isolated(
                    {
                        "name": wrong_name,
                        "code": wrong_code,
                        "whisper_original": original,
                        "context": text,
                        "sentiment": "neutral",
                        "score": 0.5,
                    },
                    text,
                )
                self.assertEqual([hit["stock_code"] for hit in hits], [expected_code])

    def test_compound_silicon_wafer_names_are_split_not_mapped_to_financial_stock(self):
        text = "矽晶圓族群今天很強，環球金、中美金、合金加金、台盛科都亮燈漲停。"
        hits = self.validate_isolated(
            {
                "name": "合庫金",
                "code": "5880",
                "whisper_original": "合金加金",
                "context": text,
                "sentiment": "bullish",
                "score": 0.7,
            },
            text,
        )
        self.assertEqual(hits, [])

        recognized = self.scanner.recognize_stocks(text)
        by_keyword = {hit["matched_keyword"]: hit["stock_code"] for hit in recognized}
        self.assertEqual(by_keyword["合金"], "6182")
        self.assertEqual(by_keyword["加金"], "3016")

    def test_passive_component_context_rejects_spring_source_steel_misread(self):
        text = "被動元件像春田，我也覺得很貴，但如果 EPS 狂拉、漲價成功就會上去。"
        hits = self.validate_isolated(
            {
                "name": "春源",
                "code": "2010",
                "whisper_original": "春田",
                "context": text,
                "sentiment": "neutral",
                "score": 0.5,
            },
            text,
        )
        self.assertEqual(hits, [])

    def test_correction_requires_local_evidence_even_if_stock_name_appears_later(self):
        filler = "這段只是在聊總體市場和節目安排。" * 12
        text = f"代稱最近常被主持人掛在嘴邊。{filler}最後補充，春源今天公布營收。"
        self.scanner._skip_log.clear()

        hits = self.validate_isolated(
            {
                "name": "春源",
                "code": "2010",
                "whisper_original": "代稱",
                "context": "最後補充，春源今天公布營收。",
                "sentiment": "neutral",
                "score": 0.5,
            },
            text,
        )

        self.assertEqual(hits, [])
        reasons = [entry.get("reason") for entry in self.scanner._skip_log]
        self.assertIn("whisper_correction_rejected", reasons)

    def test_correction_with_nearby_official_identity_remains_valid(self):
        text = "代稱這個口誤指的是春源，這檔股票今天公布營收。"
        hits = self.validate_isolated(
            {
                "name": "春源",
                "code": "2010",
                "whisper_original": "代稱",
                "context": text,
                "sentiment": "neutral",
                "score": 0.5,
            },
            text,
        )
        self.assertEqual([hit["stock_code"] for hit in hits], ["2010"])

    def test_nearby_official_identity_does_not_queue_unrelated_phrase(self):
        text = "南亞今天也收藏停辦，後面仍在討論南亞的庫存與本業。"
        self.scanner._skip_log.clear()
        hits = self.validate_isolated(
            {
                "name": "南亞",
                "code": "1303",
                "whisper_original": "收藏停辦",
                "context": text,
                "sentiment": "neutral",
                "score": 0.5,
            },
            text,
        )
        self.assertEqual(hits, [])
        self.assertIn(
            "whisper_correction_rejected",
            [entry.get("reason") for entry in self.scanner._skip_log],
        )

    def test_close_dafang_whisper_alias_is_recognized(self):
        text = "電子零組件裡面的達芳今天訂單增加，鍵盤與電源產品都有成長。"
        hits = self.scanner.recognize_stocks(text)
        self.assertIn("8163", [hit["stock_code"] for hit in hits])
        self.assertIn("達芳", [hit["matched_keyword"] for hit in hits])

    def test_new_whisper_correction_is_review_candidate_only(self):
        text = "緯印這檔股票最近營收成長，AI伺服器客戶訂單也增加。"
        with tempfile.TemporaryDirectory() as tmpdir:
            candidates_path = Path(tmpdir) / "alias_candidates.json"
            learned_path = Path(tmpdir) / "learned_aliases.json"
            rejected_path = Path(tmpdir) / "rejected_aliases.json"
            candidates_path.write_text("{}", encoding="utf-8")
            learned_path.write_text("{}", encoding="utf-8")
            rejected_path.write_text("{}", encoding="utf-8")
            old_candidates = self.scanner.ALIAS_CANDIDATES_FILE
            old_learned = self.scanner.LEARNED_ALIASES_FILE
            old_rejected = self.scanner.REJECTED_ALIASES_FILE
            self.scanner.ALIAS_CANDIDATES_FILE = candidates_path
            self.scanner.LEARNED_ALIASES_FILE = learned_path
            self.scanner.REJECTED_ALIASES_FILE = rejected_path
            try:
                hits = self.validate(
                    {
                        "name": "緯穎",
                        "code": "6669",
                        "whisper_original": "緯印",
                        "context": text,
                        "sentiment": "bullish",
                        "score": 0.7,
                    },
                    text,
                )
            finally:
                self.scanner.ALIAS_CANDIDATES_FILE = old_candidates
                self.scanner.LEARNED_ALIASES_FILE = old_learned
                self.scanner.REJECTED_ALIASES_FILE = old_rejected

            self.assertEqual([hit["stock_code"] for hit in hits], ["6669"])
            candidates = json.loads(candidates_path.read_text(encoding="utf-8"))
            learned = json.loads(learned_path.read_text(encoding="utf-8"))
            self.assertIn("緯印|6669", candidates)
            self.assertEqual(candidates["緯印|6669"]["confidence"], "high")
            self.assertEqual(learned, {})

    def test_rejected_whisper_correction_is_not_queued_again(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            candidates_path = Path(tmpdir) / "alias_candidates.json"
            rejected_path = Path(tmpdir) / "rejected_aliases.json"
            candidates_path.write_text("{}", encoding="utf-8")
            rejected_path.write_text('{"紅海|2615": {}}', encoding="utf-8")
            old_candidates = self.scanner.ALIAS_CANDIDATES_FILE
            old_rejected = self.scanner.REJECTED_ALIASES_FILE
            self.scanner.ALIAS_CANDIDATES_FILE = candidates_path
            self.scanner.REJECTED_ALIASES_FILE = rejected_path
            try:
                self.scanner._record_alias_candidate(
                    "紅海",
                    "2615",
                    "萬海",
                    context="紅海最近上漲。",
                    source="regression-test",
                )
            finally:
                self.scanner.ALIAS_CANDIDATES_FILE = old_candidates
                self.scanner.REJECTED_ALIASES_FILE = old_rejected

            candidates = json.loads(candidates_path.read_text(encoding="utf-8"))
            self.assertEqual(candidates, {})

    def test_phonetic_review_candidates_prefer_hon_hai_for_homophone(self):
        if self.scanner.lazy_pinyin is None:
            self.skipTest("pypinyin is not installed")
        self.scanner._PHONETIC_STOCK_INDEX = None
        candidates = self.scanner._phonetic_alias_candidates("紅海")
        self.assertEqual(candidates[0]["code"], "2317")
        self.assertEqual(candidates[0]["name"], "鴻海")
        _, reasons = self.scanner._alias_candidate_score("紅海", "2615", "萬海", "紅海最近上漲。")
        self.assertIn("phonetic_conflict", reasons)

    def test_alias_candidate_uses_clear_phonetic_winner_over_gemini_guess(self):
        if self.scanner.lazy_pinyin is None:
            self.skipTest("pypinyin is not installed")

        text = "所以川湖今天的漲停板很有意義，還有再來就是祕望時的漲停板，讓我們知道被動元件這個族群沒死掉。"
        with tempfile.TemporaryDirectory() as tmpdir:
            candidates_path = Path(tmpdir) / "alias_candidates.json"
            rejected_path = Path(tmpdir) / "rejected_aliases.json"
            candidates_path.write_text("{}", encoding="utf-8")
            rejected_path.write_text("{}", encoding="utf-8")
            old_candidates = self.scanner.ALIAS_CANDIDATES_FILE
            old_rejected = self.scanner.REJECTED_ALIASES_FILE
            self.scanner.ALIAS_CANDIDATES_FILE = candidates_path
            self.scanner.REJECTED_ALIASES_FILE = rejected_path
            self.scanner._PHONETIC_STOCK_INDEX = None
            try:
                self.scanner._record_alias_candidate(
                    "祕望時",
                    "2059",
                    "川湖",
                    context=text,
                    source="regression-test",
                )
            finally:
                self.scanner.ALIAS_CANDIDATES_FILE = old_candidates
                self.scanner.REJECTED_ALIASES_FILE = old_rejected

            candidates = json.loads(candidates_path.read_text(encoding="utf-8"))
            self.assertIn("祕望時|8043", candidates)
            self.assertNotIn("祕望時|2059", candidates)
            self.assertEqual(candidates["祕望時|8043"]["correct_name"], "蜜望實")
            evidence = candidates["祕望時|8043"]["evidence"][-1]
            self.assertEqual(evidence["override_kind"], "phonetic")
            self.assertEqual(evidence["original_code"], "2059")
            self.assertEqual(evidence["original_name"], "川湖")
            self.assertGreaterEqual(evidence["phonetic_top_score"], 0.65)
            self.assertGreaterEqual(evidence["phonetic_lead"], 0.10)

    def test_gemini_result_uses_clear_phonetic_winner_over_wrong_target(self):
        if self.scanner.lazy_pinyin is None:
            self.skipTest("pypinyin is not installed")

        text = "例如說大立光，例如說國劇出現了目標價，終於出現一個離他現價超過一倍的目標價，金像電、騎幫等等的。"
        with tempfile.TemporaryDirectory() as tmpdir:
            candidates_path = Path(tmpdir) / "alias_candidates.json"
            rejected_path = Path(tmpdir) / "rejected_aliases.json"
            candidates_path.write_text("{}", encoding="utf-8")
            rejected_path.write_text("{}", encoding="utf-8")
            old_candidates = self.scanner.ALIAS_CANDIDATES_FILE
            old_rejected = self.scanner.REJECTED_ALIASES_FILE
            self.scanner.ALIAS_CANDIDATES_FILE = candidates_path
            self.scanner.REJECTED_ALIASES_FILE = rejected_path
            self.scanner._PHONETIC_STOCK_INDEX = None
            try:
                hits = self.validate(
                    {
                        "name": "金像電",
                        "code": "2368",
                        "whisper_original": "騎幫",
                        "context": text,
                        "sentiment": "neutral",
                        "score": 0.5,
                    },
                    text,
                )
            finally:
                self.scanner.ALIAS_CANDIDATES_FILE = old_candidates
                self.scanner.REJECTED_ALIASES_FILE = old_rejected
            candidates = json.loads(candidates_path.read_text(encoding="utf-8"))

        self.assertIn("6147", [hit["stock_code"] for hit in hits])
        self.assertNotIn("2368", [hit["stock_code"] for hit in hits if hit["matched_keyword"] == "騎幫"])
        self.assertIn("騎幫", [hit["matched_keyword"] for hit in hits])
        if "騎幫" not in self.scanner.STOCK_DICT:
            evidence = candidates["騎幫|6147"]["evidence"][-1]
            self.assertEqual(evidence["override_kind"], "phonetic")
            self.assertEqual(evidence["original_code"], "2368")
            self.assertEqual(evidence["original_name"], "金像電")

    def test_lianjun_only_matches_lianjun_in_cpo_context(self):
        cpo_text = "CPO族群裡面光盛和聯亞先休息，但是聯軍這些開始補漲。"
        hits = self.scanner.recognize_stocks(cpo_text)
        self.assertIn("3450", [hit["stock_code"] for hit in hits])

        ordinary_text = "這次AI聯軍一起推出新服務，大家都很期待。"
        hits = self.scanner.recognize_stocks(ordinary_text)
        self.assertNotIn("3450", [hit["stock_code"] for hit in hits])

    def test_phonetic_discovery_adds_current_scan_hit_and_review_candidate(self):
        if self.scanner.lazy_pinyin is None:
            self.skipTest("pypinyin is not installed")

        text = "聯均這檔股票今天漲停，股價和營收都很強。"
        with tempfile.TemporaryDirectory() as tmpdir:
            candidates_path = Path(tmpdir) / "alias_candidates.json"
            rejected_path = Path(tmpdir) / "rejected_aliases.json"
            candidates_path.write_text("{}", encoding="utf-8")
            rejected_path.write_text("{}", encoding="utf-8")
            old_candidates = self.scanner.ALIAS_CANDIDATES_FILE
            old_rejected = self.scanner.REJECTED_ALIASES_FILE
            self.scanner.ALIAS_CANDIDATES_FILE = candidates_path
            self.scanner.REJECTED_ALIASES_FILE = rejected_path
            self.scanner._PHONETIC_STOCK_INDEX = None
            try:
                hits = self.scanner.recognize_stocks(text, enable_phonetic_discovery=True)
            finally:
                self.scanner.ALIAS_CANDIDATES_FILE = old_candidates
                self.scanner.REJECTED_ALIASES_FILE = old_rejected

            self.assertIn("3450", [hit["stock_code"] for hit in hits])
            candidates = json.loads(candidates_path.read_text(encoding="utf-8"))
            self.assertIn("聯均|3450", candidates)

    def test_phonetic_discovery_requires_stock_context(self):
        if self.scanner.lazy_pinyin is None:
            self.skipTest("pypinyin is not installed")

        text = "這次AI聯軍一起推出新服務，大家都很期待。"
        hits = self.scanner.recognize_stocks(text, enable_phonetic_discovery=True)
        self.assertNotIn("3450", [hit["stock_code"] for hit in hits])

    def test_missing_whisper_original_can_be_recovered_from_phonetic_evidence(self):
        if self.scanner.lazy_pinyin is None:
            self.skipTest("pypinyin is not installed")

        text = "散熱族群裡面的奇宏今天漲停，訂單與營收都持續成長。"
        with tempfile.TemporaryDirectory() as tmpdir:
            candidates_path = Path(tmpdir) / "alias_candidates.json"
            rejected_path = Path(tmpdir) / "rejected_aliases.json"
            candidates_path.write_text("{}", encoding="utf-8")
            rejected_path.write_text("{}", encoding="utf-8")
            old_candidates = self.scanner.ALIAS_CANDIDATES_FILE
            old_rejected = self.scanner.REJECTED_ALIASES_FILE
            self.scanner.ALIAS_CANDIDATES_FILE = candidates_path
            self.scanner.REJECTED_ALIASES_FILE = rejected_path
            self.scanner._PHONETIC_STOCK_INDEX = None
            try:
                hits = self.validate(
                    {
                        "name": "奇鋐",
                        "code": "3017",
                        "context": text,
                        "sentiment": "bullish",
                        "score": 0.7,
                    },
                    text + " 摩根大通也發布了報告。",
                )
            finally:
                self.scanner.ALIAS_CANDIDATES_FILE = old_candidates
                self.scanner.REJECTED_ALIASES_FILE = old_rejected

        self.assertEqual([hit["stock_code"] for hit in hits], ["3017"])
        self.assertEqual([hit["matched_keyword"] for hit in hits], ["奇宏"])

    def test_shared_resolver_accepts_scoped_context_alias(self):
        text = "被動元件族群裡面的滑星科，最近營收與股價都很強。"
        decision = self.scanner._resolve_stock_correction(
            "滑星科",
            context=text,
            suggested_code="3265",
            policy="override",
        )
        self.assertEqual(decision["action"], "accept")
        self.assertEqual(decision["code"], "2492")
        self.assertEqual(decision["source"], "contextual_alias")

    def test_shared_resolver_does_not_promote_ambiguous_term_without_stock_context(self):
        decision = self.scanner._resolve_stock_correction(
            "聯軍",
            context="這次AI聯軍一起推出新服務，大家都很期待。",
            policy="discovery",
        )
        self.assertNotEqual(decision["action"], "accept")

    def test_shared_resolver_rejects_sector_conflict(self):
        decision = self.scanner._resolve_stock_correction(
            "春田",
            context="被動元件族群裡面的春田，電阻電容需求回升。",
            suggested_code="2010",
            policy="validation",
        )
        self.assertEqual(decision["action"], "reject")
        self.assertEqual(decision["reason"], "sector_mismatch")

    def test_shared_resolver_accepts_sixty_percent_top1_with_context_for_review(self):
        candidates = [
            {"code": "6770", "name": "力積電", "score": 0.62},
            {"code": "2330", "name": "台積電", "score": 0.60},
        ]
        with mock.patch.object(self.scanner, "_phonetic_alias_candidates", return_value=candidates):
            decision = self.scanner._resolve_stock_correction(
                "立即電",
                context="晶圓代工族群裡面，立即電這檔股票最近訂單與股價都很強。",
                suggested_code="2330",
                policy="override",
            )
        self.assertEqual(decision["action"], "accept")
        self.assertEqual(decision["code"], "6770")
        self.assertTrue(decision["needs_review"])
        self.assertEqual(decision["reason"], "phonetic_top1_needs_review")

    def test_validator_does_not_reject_an_accepted_resolver_remap_twice(self):
        text = "晶圓代工族群裡面，立即電這檔股票最近訂單與股價都很強。"
        candidates = [
            {"code": "6770", "name": "力積電", "score": 0.62},
            {"code": "2330", "name": "台積電", "score": 0.60},
        ]
        with mock.patch.object(self.scanner, "_phonetic_alias_candidates", return_value=candidates):
            hits = self.validate_isolated(
                {
                    "name": "台積電",
                    "code": "2330",
                    "whisper_original": "立即電",
                    "context": text,
                    "sentiment": "neutral",
                    "score": 0.5,
                },
                text,
            )
        self.assertEqual([hit["stock_code"] for hit in hits], ["6770"])
        self.assertTrue(hits[0]["correction_needs_review"])

    def test_validator_only_company_registry_resolves_without_global_keyword_scan(self):
        for identity, code in {
            "ON": "ON",
            "STM": "STM",
            "英飛凌": "IFNNY",
            "羅姆": "ROHCY",
            "VSH": "VSH",
        }.items():
            self.assertEqual(self.scanner.NAME_TO_CODE.get(identity), code)
            self.assertNotEqual(self.scanner.STOCK_DICT.get(identity), code)

    def test_prescan_filter_skips_existing_item_by_id(self):
        history = {
            "videos_scanned": [
                {"video_id": "episode-1", "title": "舊集數", "date": "2026-06-18"}
            ]
        }
        items = [
            {"id": "episode-1", "title": "標題後來有修改", "date": "2026-06-18"},
            {"id": "episode-2", "title": "新集數", "date": "2026-06-19"},
        ]
        unseen, skipped = self.scanner._filter_unseen_content(items, history)
        self.assertEqual([item["id"] for item in unseen], ["episode-2"])
        self.assertEqual(skipped, 1)

    def test_prescan_filter_falls_back_to_title_and_date(self):
        history = {
            "videos_scanned": [
                {"title": "沒有穩定 ID 的節目", "date": "2026-06-18"}
            ]
        }
        items = [
            {"id": "", "title": "沒有穩定 ID 的節目", "date": "2026-06-18"}
        ]
        unseen, skipped = self.scanner._filter_unseen_content(items, history)
        self.assertEqual(unseen, [])
        self.assertEqual(skipped, 1)

    def test_prescan_filter_keeps_new_content(self):
        history = {
            "videos_scanned": [
                {"video_id": "episode-1", "title": "舊集數", "date": "2026-06-18"}
            ]
        }
        items = [
            {"id": "episode-2", "title": "新集數", "date": "2026-06-19"}
        ]
        unseen, skipped = self.scanner._filter_unseen_content(items, history)
        self.assertEqual(unseen, items)
        self.assertEqual(skipped, 0)


if __name__ == "__main__":
    unittest.main()

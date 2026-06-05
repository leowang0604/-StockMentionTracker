import importlib.util
import json
import sys
import tempfile
import types
import unittest
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
        {"code": "2615", "name": "萬海", "market": "listed", "sector": "航運業"},
        {"code": "3026", "name": "禾伸堂", "market": "listed", "sector": "電子零組件業"},
        {"code": "3450", "name": "聯鈞", "market": "listed", "sector": "半導體業"},
        {"code": "6214", "name": "精誠", "market": "listed", "sector": "資訊服務業"},
        {"code": "6669", "name": "緯穎", "market": "listed", "sector": "電腦及週邊設備業"},
        {"code": "6690", "name": "安碁資訊", "market": "listed", "sector": "資訊服務業"},
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
    return module


class ValidatorRegressionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.scanner = load_scanner()

    def validate(self, row, text):
        return self.scanner._validate_gemini_stocks([row], text)

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


if __name__ == "__main__":
    unittest.main()

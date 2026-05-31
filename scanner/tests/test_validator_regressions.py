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

    def test_new_whisper_correction_is_review_candidate_only(self):
        text = "緯印這檔股票最近營收成長，AI伺服器客戶訂單也增加。"
        with tempfile.TemporaryDirectory() as tmpdir:
            candidates_path = Path(tmpdir) / "alias_candidates.json"
            learned_path = Path(tmpdir) / "learned_aliases.json"
            candidates_path.write_text("{}", encoding="utf-8")
            learned_path.write_text("{}", encoding="utf-8")
            old_candidates = self.scanner.ALIAS_CANDIDATES_FILE
            old_learned = self.scanner.LEARNED_ALIASES_FILE
            self.scanner.ALIAS_CANDIDATES_FILE = candidates_path
            self.scanner.LEARNED_ALIASES_FILE = learned_path
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

            self.assertEqual([hit["stock_code"] for hit in hits], ["6669"])
            candidates = json.loads(candidates_path.read_text(encoding="utf-8"))
            learned = json.loads(learned_path.read_text(encoding="utf-8"))
            self.assertIn("緯印|6669", candidates)
            self.assertEqual(candidates["緯印|6669"]["confidence"], "high")
            self.assertEqual(learned, {})


if __name__ == "__main__":
    unittest.main()

#!/usr/bin/env python3
"""Replay saved transcript fixtures through the production stock recognizer.

This is intentionally offline: no YouTube, no Whisper, and no Gemini calls.
It imports scanner/main.py, rebuilds the stock dictionaries, runs
recognize_stocks(), and checks stock-code and matched-keyword expectations.
"""

from __future__ import annotations

import argparse
import importlib.util
import json
import sys
import tempfile
import types
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SCANNER_PATH = ROOT / "scanner" / "main.py"
STOCKS_PATH = ROOT / "data" / "stocks.json"
FIXTURE_DIR = ROOT / "scanner" / "tests" / "fixtures"
TRANSCRIPTS_DIR = FIXTURE_DIR / "transcripts"
EXPECTED_PATH = FIXTURE_DIR / "expected_mentions.json"

REQUIRED_STOCKS = [
    {"code": "2207", "name": "和泰車", "market": "listed", "sector": "汽車工業"},
    {"code": "1423", "name": "利華", "market": "listed", "sector": "紡織纖維"},
    {"code": "1449", "name": "佳和", "market": "listed", "sector": "紡織纖維"},
    {"code": "2317", "name": "鴻海", "market": "listed", "sector": "組裝代工"},
    {"code": "2301", "name": "光寶科", "market": "listed", "sector": "電腦及週邊設備業"},
    {"code": "2308", "name": "台達電", "market": "listed", "sector": "電源供應器"},
    {"code": "2344", "name": "華邦電", "market": "listed", "sector": "半導體業"},
    {"code": "2368", "name": "金像電", "market": "listed", "sector": "PCB"},
    {"code": "2382", "name": "廣達", "market": "listed", "sector": "伺服器"},
    {"code": "3026", "name": "禾伸堂", "market": "listed", "sector": "電子零組件業"},
    {"code": "3450", "name": "聯鈞", "market": "listed", "sector": "半導體業"},
    {"code": "4905", "name": "台聯電", "market": "tpex", "sector": "光電"},
    {"code": "6116", "name": "彩晶", "market": "listed", "sector": "光電業"},
    {"code": "6121", "name": "新普", "market": "listed", "sector": "電腦及週邊設備業"},
    {"code": "6173", "name": "信昌電", "market": "listed", "sector": "電子零組件業"},
    {"code": "6190", "name": "萬泰科", "market": "listed", "sector": "電子通路"},
    {"code": "6442", "name": "光聖", "market": "listed", "sector": "通信網路業"},
    {"code": "8028", "name": "昇陽半導體", "market": "listed", "sector": "半導體業"},
]


def load_scanner():
    sys.modules["requests"] = types.SimpleNamespace(
        get=lambda *args, **kwargs: None,
        post=lambda *args, **kwargs: None,
    )
    sys.modules["yt_dlp"] = types.SimpleNamespace(YoutubeDL=object)
    spec = importlib.util.spec_from_file_location("scanner_main", SCANNER_PATH)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


def load_stocks() -> list[dict]:
    stocks = json.loads(STOCKS_PATH.read_text(encoding="utf-8"))["stocks"]
    by_code = {str(stock.get("code", "")): stock for stock in stocks}
    for stock in REQUIRED_STOCKS:
        by_code.setdefault(stock["code"], stock)
    return list(by_code.values())


def configure_scanner(scanner, tmpdir: Path, learned_aliases: dict[str, str] | None = None) -> None:
    scanner.ALIAS_CANDIDATES_FILE = tmpdir / "alias_candidates.json"
    scanner.REJECTED_ALIASES_FILE = tmpdir / "rejected_aliases.json"
    scanner.LEARNED_ALIASES_FILE = tmpdir / "learned_aliases.json"
    scanner.ALIAS_CANDIDATES_FILE.write_text("{}", encoding="utf-8")
    scanner.REJECTED_ALIASES_FILE.write_text("{}", encoding="utf-8")
    scanner.LEARNED_ALIASES_FILE.write_text(
        json.dumps(learned_aliases or {}, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )
    scanner._PHONETIC_STOCK_INDEX = None
    scanner._skip_log.clear()
    (
        scanner.STOCK_DICT,
        scanner.CODE_TO_NAME,
        scanner.STOCK_MARKET,
        scanner.STOCK_SECTOR,
        scanner.NAME_TO_CODE,
    ) = scanner.build_stock_dict(load_stocks())


def run_case(scanner, case_id: str, expected: dict) -> tuple[bool, list[str]]:
    transcript_name = expected.get("transcript", f"{case_id}.txt")
    transcript_path = TRANSCRIPTS_DIR / transcript_name
    if not transcript_path.exists():
        return False, [f"missing transcript: {transcript_path}"]

    with tempfile.TemporaryDirectory() as tmp:
        tmpdir = Path(tmp)
        configure_scanner(scanner, tmpdir, expected.get("learned_aliases"))
        text = transcript_path.read_text(encoding="utf-8")
        hits = scanner.deduplicate_hits(scanner.recognize_stocks(
            text,
            video_ctx={"video_id": f"fixture:{case_id}", "channel": "fixture", "date": "", "title": case_id},
            enable_phonetic_discovery=bool(expected.get("enable_phonetic_discovery")),
        ))
        codes = {hit["stock_code"] for hit in hits}
        keywords = {
            (hit.get("matched_keyword") or "").strip()
            for hit in hits
            if (hit.get("matched_keyword") or "").strip()
        }
        candidates = json.loads(scanner.ALIAS_CANDIDATES_FILE.read_text(encoding="utf-8"))

    errors: list[str] = []
    for code in expected.get("must_include", []):
        if code not in codes:
            errors.append(f"missing expected code {code}")
    for code in expected.get("must_exclude", []):
        if code in codes:
            errors.append(f"unexpected code {code}")
    for key in expected.get("expected_candidates", []):
        if key not in candidates:
            errors.append(f"missing expected alias candidate {key}")
    for keyword in expected.get("must_highlight", []):
        if keyword not in keywords:
            errors.append(f"missing expected matched_keyword {keyword!r}")
    for keyword in expected.get("must_not_highlight", []):
        if keyword in keywords:
            errors.append(f"unexpected matched_keyword {keyword!r}")

    if errors:
        found = ", ".join(sorted(codes)) or "none"
        errors.append(f"found codes: {found}")
        found_keywords = ", ".join(sorted(keywords)) or "none"
        errors.append(f"found matched_keywords: {found_keywords}")
    return not errors, errors


def main() -> int:
    parser = argparse.ArgumentParser(description="Replay scanner transcript fixtures.")
    parser.add_argument("cases", nargs="*", help="Optional fixture case id(s). Runs all by default.")
    parser.add_argument("--list", action="store_true", help="List available fixtures and exit.")
    args = parser.parse_args()

    expected = json.loads(EXPECTED_PATH.read_text(encoding="utf-8"))
    if args.list:
        for case_id, config in expected.items():
            print(f"{case_id}: {config.get('description', '')}")
        return 0

    selected = args.cases or list(expected.keys())
    unknown = [case_id for case_id in selected if case_id not in expected]
    if unknown:
        print(f"Unknown fixture case(s): {', '.join(unknown)}", file=sys.stderr)
        return 2

    scanner = load_scanner()
    failures = 0
    for case_id in selected:
        ok, errors = run_case(scanner, case_id, expected[case_id])
        if ok:
            print(f"PASS {case_id}")
        else:
            failures += 1
            print(f"FAIL {case_id}")
            for error in errors:
                print(f"  - {error}")

    passed = len(selected) - failures
    print(f"\nSummary: {passed} passed, {failures} failed")
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())

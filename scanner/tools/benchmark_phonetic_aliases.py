#!/usr/bin/env python3
"""Compare stock alias candidate ranking with and without Mandarin pronunciation.

This is an offline experiment. It reads static fixtures and stocks.json only:
no Gemini calls, network access, scanner output changes, or alias promotion.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from dataclasses import dataclass
from pathlib import Path

try:
    from pypinyin import Style, lazy_pinyin
except ImportError:
    print(
        "Missing pypinyin. Install benchmark-only dependencies with:\n"
        "  python -m pip install -r scanner/tools/requirements-benchmark.txt",
        file=sys.stderr,
    )
    raise SystemExit(2)


ROOT = Path(__file__).resolve().parents[2]
DEFAULT_STOCKS = ROOT / "data" / "stocks.json"
DEFAULT_FIXTURES = ROOT / "scanner" / "tests" / "fixtures" / "phonetic_alias_cases.json"
CHINESE_RE = re.compile(r"[\u3400-\u9fff]+")


@dataclass(frozen=True)
class Stock:
    code: str
    name: str


@dataclass(frozen=True)
class RankedStock:
    stock: Stock
    score: float
    text_similarity: float
    phonetic_similarity: float


def levenshtein(left: str, right: str) -> int:
    if left == right:
        return 0
    if not left:
        return len(right)
    if not right:
        return len(left)
    previous = list(range(len(right) + 1))
    for left_index, left_char in enumerate(left, start=1):
        current = [left_index]
        for right_index, right_char in enumerate(right, start=1):
            current.append(
                min(
                    current[-1] + 1,
                    previous[right_index] + 1,
                    previous[right_index - 1] + (left_char != right_char),
                )
            )
        previous = current
    return previous[-1]


def similarity(left: str, right: str) -> float:
    if not left or not right:
        return 0.0
    return 1.0 - levenshtein(left, right) / max(len(left), len(right))


def phonetic_key(text: str) -> str:
    """Return compact tone-less Mandarin pinyin for Chinese text."""
    return "".join(
        lazy_pinyin(
            text,
            style=Style.NORMAL,
            errors=lambda chars: list(chars),
        )
    ).lower()


def is_chinese_stock(stock: Stock) -> bool:
    return bool(CHINESE_RE.search(stock.name))


def load_stocks(path: Path) -> list[Stock]:
    rows = json.loads(path.read_text(encoding="utf-8"))["stocks"]
    seen: set[tuple[str, str]] = set()
    stocks: list[Stock] = []
    for row in rows:
        stock = Stock(code=str(row["code"]), name=str(row["name"]).strip())
        key = (stock.code, stock.name)
        if stock.name and key not in seen and is_chinese_stock(stock):
            stocks.append(stock)
            seen.add(key)
    return stocks


def rank_stocks(wrong_keyword: str, stocks: list[Stock], *, use_phonetic: bool) -> list[RankedStock]:
    wrong_phonetic = phonetic_key(wrong_keyword)
    ranked: list[RankedStock] = []
    for stock in stocks:
        text_score = similarity(wrong_keyword, stock.name)
        phonetic_score = similarity(wrong_phonetic, phonetic_key(stock.name))
        score = text_score if not use_phonetic else 0.35 * text_score + 0.65 * phonetic_score
        ranked.append(
            RankedStock(
                stock=stock,
                score=score,
                text_similarity=text_score,
                phonetic_similarity=phonetic_score,
            )
        )
    return sorted(ranked, key=lambda item: (-item.score, item.stock.code, item.stock.name))


def find_rank(ranked: list[RankedStock], code: str) -> int | None:
    for index, item in enumerate(ranked, start=1):
        if item.stock.code == code:
            return index
    return None


def compact_top(ranked: list[RankedStock], limit: int = 3) -> str:
    return ", ".join(
        f"{item.stock.name}({item.stock.code}, {item.score:.2f})"
        for item in ranked[:limit]
    )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--stocks", type=Path, default=DEFAULT_STOCKS)
    parser.add_argument("--fixtures", type=Path, default=DEFAULT_FIXTURES)
    args = parser.parse_args()

    stocks = load_stocks(args.stocks)
    fixtures = json.loads(args.fixtures.read_text(encoding="utf-8"))
    positives = fixtures["positive_cases"]
    negatives = fixtures["negative_cases"]

    baseline_top1 = baseline_top3 = phonetic_top1 = phonetic_top3 = 0
    print(f"Loaded {len(stocks)} Chinese-name stocks\n")
    print("POSITIVE CASES")
    for case in positives:
        baseline = rank_stocks(case["wrong_keyword"], stocks, use_phonetic=False)
        phonetic = rank_stocks(case["wrong_keyword"], stocks, use_phonetic=True)
        baseline_rank = find_rank(baseline, case["expected_code"])
        phonetic_rank = find_rank(phonetic, case["expected_code"])
        baseline_top1 += baseline_rank == 1
        baseline_top3 += baseline_rank is not None and baseline_rank <= 3
        phonetic_top1 += phonetic_rank == 1
        phonetic_top3 += phonetic_rank is not None and phonetic_rank <= 3
        print(
            f"- {case['wrong_keyword']} -> {case['expected_name']}({case['expected_code']}): "
            f"baseline rank={baseline_rank}, phonetic rank={phonetic_rank}\n"
            f"  baseline top3: {compact_top(baseline)}\n"
            f"  phonetic top3: {compact_top(phonetic)}"
        )

    print("\nNEGATIVE CASES")
    negative_failures = 0
    for case in negatives:
        phonetic = rank_stocks(case["wrong_keyword"], stocks, use_phonetic=True)
        forbidden_rank = find_rank(phonetic, case["must_not_match_code"])
        if forbidden_rank == 1:
            negative_failures += 1
        print(
            f"- {case['wrong_keyword']} must not prefer "
            f"{case['must_not_match_name']}({case['must_not_match_code']}): "
            f"forbidden rank={forbidden_rank}\n"
            f"  phonetic top3: {compact_top(phonetic)}"
        )

    count = len(positives)
    print("\nSUMMARY")
    print(f"- baseline Top-1: {baseline_top1}/{count} ({baseline_top1 / count:.0%})")
    print(f"- phonetic Top-1: {phonetic_top1}/{count} ({phonetic_top1 / count:.0%})")
    print(f"- baseline Top-3: {baseline_top3}/{count} ({baseline_top3 / count:.0%})")
    print(f"- phonetic Top-3: {phonetic_top3}/{count} ({phonetic_top3 / count:.0%})")
    print(f"- negative Top-1 failures: {negative_failures}/{len(negatives)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

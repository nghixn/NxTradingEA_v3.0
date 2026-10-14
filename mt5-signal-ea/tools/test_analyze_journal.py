"""Kiểm thử analyze_journal.py: python -m unittest -v test_analyze_journal.py"""
import math
import tempfile
import unittest
from pathlib import Path

import analyze_journal as aj

HEADER = ("id;symbol;tier;group;side;type;pending_risk;score;max_score;created;entry;sl;tp1;tp2;rr1;rr2;"
          "spread;lot;risk_money;risk_pct;risk_warning;filled;fill_time;minutes_to_fill;outcome;r_a;r_b;r_c;"
          "mfe_r;mae_r;hold_hours;close_time;money_a;note")


def row(i, filled, ra, rb, rc, tier="priority", pending="0", outcome=None, close=None):
    out = outcome or ("NOT_FILLED" if not filled else ("SL" if ra < 0 else "TP1"))
    vals = [f"ID{i}", "XAUUSD", tier, "metals", "sell", "pullback", pending, "6", "9", "2026-10-14 13:00",
            "4175", "4196", "4135", "4100", "1.9", "3.57", "0.25", "0.01", "21", "2.1", "1",
            "1" if filled else "0", "2026-10-14 14:00" if filled else "", "60" if filled else "", out,
            "" if ra is None else str(ra), "" if rb is None else str(rb), "" if rc is None else str(rc),
            "1.5" if filled else "", "0.6" if filled else "", "5.0" if filled else "",
            close or f"2026-10-14 {10 + i:02d}:00", "" if ra is None else str(ra * 21), ""]
    return ";".join(vals)


class AnalyzeTest(unittest.TestCase):
    def write(self, lines):
        tmp = Path(tempfile.mkdtemp()) / "journal.csv"
        tmp.write_text("﻿" + HEADER + "\r\n" + "\r\n".join(lines) + "\r\n", encoding="utf-8")
        return tmp

    def test_stats_values(self):
        # chuỗi: +2, -1, -1, -1, +2 -> thắng 40%, tổng +1, chuỗi thua 3, DD 3
        s = aj.r_stats([2, -1, -1, -1, 2])
        self.assertEqual(s["n"], 5)
        self.assertAlmostEqual(s["win_rate"], 0.4)
        self.assertAlmostEqual(s["total"], 1.0)
        self.assertAlmostEqual(s["profit_factor"], 4 / 3)
        self.assertEqual(s["max_losing_streak"], 3)
        self.assertAlmostEqual(s["max_drawdown"], 3.0)
        self.assertTrue(math.isinf(aj.r_stats([1, 2])["profit_factor"]))

    def test_load_excludes_pending_by_default(self):
        path = self.write([row(1, True, 1.9, 3.57, 2.7), row(2, True, -1, -1, -1, pending="1"),
                           row(3, False, None, None, None)])
        self.assertEqual(len(aj.load_rows(path, include_pending=False)), 2)
        self.assertEqual(len(aj.load_rows(path, include_pending=True)), 3)

    def test_report_small_sample_warning(self):
        path = self.write([row(1, True, 1.9, 3.57, 2.7), row(2, True, -1, -1, -1), row(3, False, None, None, None)])
        text = aj.report(aj.load_rows(path, False), "A")
        self.assertIn("Tổng tín hiệu đã đóng: 3 | khớp: 2 (67%)", text)
        self.assertIn("A - Chốt toàn bộ ở TP1: n=2 | thắng 50%", text)
        self.assertIn("CẢNH BÁO: mới có 2 kèo khớp", text)
        self.assertIn("priority", text)

    def test_report_verdict_positive(self):
        lines = [row(i, True, 1.9 if i % 3 else -1, 1.9, 1.0, close=f"2026-10-{1 + i // 20:02d} {i % 20:02d}:00")
                 for i in range(60)]
        text = aj.report(aj.load_rows(self.write(lines), False), "A")
        self.assertIn("kỳ vọng DƯƠNG", text)

    def test_report_verdict_negative(self):
        lines = [row(i, True, -1 if i % 4 else 1.3, -1, -1, close=f"2026-10-{1 + i // 20:02d} {i % 20:02d}:00")
                 for i in range(60)]
        text = aj.report(aj.load_rows(self.write(lines), False), "A")
        self.assertIn("kỳ vọng ÂM", text)

    def test_cli_missing_file(self):
        self.assertEqual(aj.main(["khong_ton_tai.csv"]), 1)


if __name__ == "__main__":
    unittest.main()

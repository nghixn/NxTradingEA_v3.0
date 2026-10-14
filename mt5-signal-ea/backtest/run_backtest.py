#!/usr/bin/env python3
"""Chạy backtest SignalEA trên dữ liệu xuất bởi Scripts/ExportHistory.mq5.

Ví dụ:
    python run_backtest.py --data-dir "C:\\...\\MQL5\\Files\\SignalEA\\history"
    python run_backtest.py --data-dir data --symbols XAUUSD,BTCUSD --start 2025-01-01 --out trades.csv
    python run_backtest.py --data-dir data --set min_score_other=6 --set enable_breakout=false
Kết quả ghi theo đúng định dạng journal_<login>.csv để phân tích bằng tools/analyze_journal.py.
"""
from __future__ import annotations

import argparse
import calendar
import dataclasses
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(HERE.parent / "tools"))

from bt_data import discover_symbols, load_symbol  # noqa: E402
from bt_engine import Backtest  # noqa: E402
from bt_strategy import Params  # noqa: E402


def parse_date(text: str | None) -> int | None:
    if not text:
        return None
    d = datetime.strptime(text, "%Y-%m-%d")
    return calendar.timegm(d.timetuple())


def apply_overrides(p: Params, items: list[str]) -> Params:
    fields = {f.name: f for f in dataclasses.fields(Params)}
    changes = {}
    for item in items:
        if "=" not in item:
            raise SystemExit(f"--set cần dạng ten=gia_tri, nhận '{item}'")
        key, val = (x.strip() for x in item.split("=", 1))
        if key not in fields:
            raise SystemExit(f"Tham số không tồn tại: {key}. Có: {', '.join(sorted(fields))}")
        cur = getattr(p, key)
        if isinstance(cur, bool):
            changes[key] = val.lower() in ("1", "true", "yes", "on")
        elif isinstance(cur, int):
            changes[key] = int(val)
        elif isinstance(cur, float):
            changes[key] = float(val)
        elif isinstance(cur, tuple):
            parts = [x.strip() for x in val.split(",") if x.strip()]
            changes[key] = tuple(int(x) for x in parts) if key == "weights" else tuple(parts)
        else:
            changes[key] = val
    return dataclasses.replace(p, **changes)


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description="Backtest SignalEA")
    ap.add_argument("--data-dir", required=True, type=Path, help="Thư mục chứa <SYM>_<TF>.csv và <SYM>_spec.csv")
    ap.add_argument("--symbols", default="", help="Danh sách symbol (mặc định: mọi symbol có file H1)")
    ap.add_argument("--start", help="Ngày bắt đầu YYYY-MM-DD (giờ server)")
    ap.add_argument("--end", help="Ngày kết thúc YYYY-MM-DD")
    ap.add_argument("--out", type=Path, default=Path("backtest_trades.csv"), help="File CSV kết quả")
    ap.add_argument("--no-m1", action="store_true", help="Không dùng M1, mô phỏng trên H1 (thô hơn)")
    ap.add_argument("--set", action="append", default=[], metavar="TEN=GIA_TRI", help="Đổi tham số (lặp lại được)")
    ap.add_argument("--scenario", default="A", choices=["A", "B", "C"], help="Kịch bản cho bảng chi tiết")
    ap.add_argument("--no-report", action="store_true", help="Không in báo cáo phân tích")
    a = ap.parse_args(argv)

    if not a.data_dir.is_dir():
        print(f"Không tìm thấy thư mục dữ liệu: {a.data_dir}", file=sys.stderr)
        return 1
    symbols = [s.strip() for s in a.symbols.split(",") if s.strip()] or discover_symbols(a.data_dir)
    if not symbols:
        print("Không có symbol nào (cần file <SYM>_H1.csv).", file=sys.stderr)
        return 1
    p = apply_overrides(Params(), a.set)

    t0 = time.time()
    datas = []
    for sym in symbols:
        d = load_symbol(a.data_dir, sym)
        m1 = len(d.m1) if d.m1 else 0
        print(f"Nạp {sym}: " + ", ".join(f"{tf}={len(s)}" for tf, s in d.tf.items()) + f", M1={m1}")
        if not len(d.tf["H1"]):
            print(f"  bỏ qua {sym}: không có H1")
            continue
        datas.append(d)
    bt = Backtest(datas, p, use_m1=not a.no_m1)
    res = bt.run(parse_date(a.start), parse_date(a.end))
    lines = bt.csv_lines()
    a.out.write_text("\ufeff" + "\r\n".join(lines) + "\r\n", encoding="utf-8")

    def fmt(t: int) -> str:
        return datetime.fromtimestamp(t, tz=timezone.utc).strftime("%Y-%m-%d %H:%M") if t else "-"
    print()
    print(f"Khoảng thời gian: {fmt(res.start)} -> {fmt(res.end)} (giờ server) | {len(datas)} symbol | "
          f"{res.evaluations} lượt phân tích | {time.time() - t0:.1f}s")
    print("Bộ đếm:")
    for k, v in sorted(res.counters.items()):
        print(f"  {k}: {v}")
    print("Setup theo symbol: " + (", ".join(f"{k} {v}" for k, v in res.setups_by_symbol.most_common()) or "(không có)"))
    print(f"Đã ghi {len(lines) - 1} kèo vào {a.out} | còn {res.open_at_end} kèo chưa kết thúc lúc hết dữ liệu (không ghi)")

    if not a.no_report:
        try:
            import analyze_journal
        except ImportError:
            print("(Không tìm thấy tools/analyze_journal.py - bỏ qua báo cáo)")
            return 0
        print()
        print(analyze_journal.report(analyze_journal.load_rows(a.out, include_pending=False), a.scenario))
    return 0


if __name__ == "__main__":
    sys.exit(main())

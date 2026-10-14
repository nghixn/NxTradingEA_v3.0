#!/usr/bin/env python3
"""Sinh dữ liệu GIẢ LẬP (random walk có xu hướng) theo đúng định dạng ExportHistory.mq5.

Chỉ để chạy thử bộ backtest khi chưa có dữ liệu thật. KHÔNG dùng kết quả trên dữ liệu này
để đánh giá EA.
    python make_sample_data.py --out sample_data --days 420
"""
from __future__ import annotations

import argparse
import calendar
import math
import random
from datetime import datetime, timezone
from pathlib import Path

PRESETS = {
    # tên: (giá đầu, biến động mỗi phút, spread point, digits, spec)
    "XAUUSD": (2400.0, 0.00028, 160, 2, dict(tick_size=0.01, tick_value_loss=1.0, contract_size=100,
                                             currency_base="XAU", currency_profit="USD", path="Metals\\XAUUSD",
                                             calc_mode="SYMBOL_CALC_MODE_CFDLEVERAGE")),
    "BTCUSD": (60000.0, 0.0006, 1800, 2, dict(tick_size=0.01, tick_value_loss=0.01, contract_size=1,
                                              currency_base="BTC", currency_profit="USD", path="Crypto\\BTCUSD",
                                              calc_mode="SYMBOL_CALC_MODE_CFD")),
    "EURUSD": (1.08, 0.00012, 7, 5, dict(tick_size=0.00001, tick_value_loss=1.0, contract_size=100000,
                                        currency_base="EUR", currency_profit="USD", path="Forex\\EURUSD",
                                        calc_mode="SYMBOL_CALC_MODE_FOREX")),
}


def gen_minutes(start: int, days: int, price: float, vol: float, seed: int):
    rnd = random.Random(seed)
    drift = 0.0
    for i in range(days * 1440):
        if i % (1440 * 5) == 0:
            drift = rnd.gauss(0, vol * 0.08)       # đổi chế độ xu hướng mỗi ~5 ngày
        o = price
        c = o * math.exp(drift + rnd.gauss(0, vol))
        h = max(o, c) * (1 + abs(rnd.gauss(0, vol * 0.5)))
        lo = min(o, c) * (1 - abs(rnd.gauss(0, vol * 0.5)))
        yield start + i * 60, o, h, lo, c
        price = c


def bucket(t: int, tf: str) -> int:
    if tf == "M1":
        return t - t % 60
    if tf == "H1":
        return t - t % 3600
    if tf == "H4":
        return t - t % 14400
    if tf == "D1":
        return t - t % 86400
    d = datetime.fromtimestamp(t, tz=timezone.utc)
    if tf == "W1":       # MT5: tuần bắt đầu Chủ nhật
        day0 = t - t % 86400
        return day0 - ((d.weekday() + 1) % 7) * 86400
    return calendar.timegm((d.year, d.month, 1, 0, 0, 0))   # MN1


def write(path: Path, rows, digits: int, spread: int) -> None:
    with path.open("w", encoding="utf-8", newline="") as fh:
        fh.write("time;open;high;low;close;spread\r\n")
        for t, o, h, lo, c in rows:
            fh.write(f"{t};{o:.{digits}f};{h:.{digits}f};{lo:.{digits}f};{c:.{digits}f};{spread}\r\n")


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", type=Path, default=Path("sample_data"))
    ap.add_argument("--days", type=int, default=420)
    ap.add_argument("--m1-days", type=int, default=60, help="Số ngày cuối có xuất M1")
    ap.add_argument("--symbols", default="XAUUSD,BTCUSD,EURUSD")
    a = ap.parse_args()
    a.out.mkdir(parents=True, exist_ok=True)
    start = calendar.timegm((2024, 1, 7, 0, 0, 0))
    for n, sym in enumerate(s.strip() for s in a.symbols.split(",")):
        price, vol, spread, digits, spec = PRESETS[sym]
        agg = {tf: {} for tf in ("M1", "H1", "H4", "D1", "W1", "MN1")}
        m1_from = start + (a.days - a.m1_days) * 86400
        for t, o, h, lo, c in gen_minutes(start, a.days, price, vol, seed=100 + n):
            for tf, store in agg.items():
                if tf == "M1" and t < m1_from:
                    continue
                k = bucket(t, tf)
                bar = store.get(k)
                store[k] = [o, h, lo, c] if bar is None else [bar[0], max(bar[1], h), min(bar[2], lo), c]
        for tf, store in agg.items():
            write(a.out / f"{sym}_{tf}.csv", ((k, *v) for k, v in sorted(store.items())), digits, spread)
        point = 10 ** -digits
        lines = ["key;value", f"symbol;{sym}", f"digits;{digits}", f"point;{point:.10f}",
                 f"volume_min;0.01", "volume_step;0.01", "volume_max;100", "account_currency;USD",
                 "server_gmt_offset_sec;0"] + [f"{k};{v}" for k, v in spec.items()]
        (a.out / f"{sym}_spec.csv").write_text("\r\n".join(lines) + "\r\n", encoding="utf-8")
        print(f"{sym}: " + ", ".join(f"{tf}={len(v)}" for tf, v in agg.items()))
    print(f"Đã ghi dữ liệu giả lập vào {a.out} (CHỈ để chạy thử, không dùng để đánh giá EA).")


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Phân tích nhật ký kết quả tín hiệu SignalEA (journal_<login>.csv).

Chỉ dùng thư viện chuẩn. Ví dụ:
    python analyze_journal.py "C:\\...\\MQL5\\Files\\SignalEA\\journal_12345678.csv"
    python analyze_journal.py journal.csv --scenario C --include-pending
"""
from __future__ import annotations

import argparse
import csv
import math
import statistics
import sys
from collections import defaultdict
from pathlib import Path

SCENARIOS = {
    "A": ("r_a", "Chốt toàn bộ ở TP1"),
    "B": ("r_b", "Chốt toàn bộ ở TP2"),
    "C": ("r_c", "50% TP1 + 50% dời SL hòa vốn chờ TP2"),
}
MIN_SAMPLE = 30


def to_float(value: str):
    try:
        return float(value) if value not in ("", None) else None
    except ValueError:
        return None


def load_rows(path: Path, include_pending: bool) -> list[dict]:
    with path.open(encoding="utf-8-sig", newline="") as fh:
        rows = list(csv.DictReader(fh, delimiter=";"))
    if not include_pending:
        rows = [r for r in rows if r.get("pending_risk") != "1"]
    rows.sort(key=lambda r: r.get("close_time") or "")
    for r in rows:
        r["month"] = (r.get("close_time") or "?")[:7]
    return rows


def r_stats(values: list[float]) -> dict:
    """Thống kê theo R cho danh sách kết quả đã khớp (theo thứ tự thời gian đóng)."""
    n = len(values)
    if n == 0:
        return {"n": 0}
    wins = [v for v in values if v > 0]
    losses = [v for v in values if v < 0]
    total = sum(values)
    mean = total / n
    sd = statistics.stdev(values) if n > 1 else 0.0
    se = sd / math.sqrt(n) if n > 1 else 0.0
    gross_win = sum(wins)
    gross_loss = -sum(losses)
    # chuỗi thua liên tiếp dài nhất và drawdown lớn nhất (theo R)
    streak = max_streak = 0
    equity = peak = max_dd = 0.0
    for v in values:
        streak = streak + 1 if v < 0 else 0
        max_streak = max(max_streak, streak)
        equity += v
        peak = max(peak, equity)
        max_dd = max(max_dd, peak - equity)
    return {
        "n": n,
        "win_rate": len(wins) / n,
        "mean": mean,
        "total": total,
        "ci_low": mean - 1.96 * se,
        "ci_high": mean + 1.96 * se,
        "profit_factor": (gross_win / gross_loss) if gross_loss > 0 else math.inf,
        "avg_win": statistics.mean(wins) if wins else 0.0,
        "avg_loss": statistics.mean(losses) if losses else 0.0,
        "max_losing_streak": max_streak,
        "max_drawdown": max_dd,
    }


def fmt_stats(s: dict) -> str:
    if s["n"] == 0:
        return "chưa có kèo khớp"
    pf = "∞" if math.isinf(s["profit_factor"]) else f"{s['profit_factor']:.2f}"
    return (f"n={s['n']} | thắng {s['win_rate']:.0%} | TB {s['mean']:+.2f}R "
            f"(95%: {s['ci_low']:+.2f}..{s['ci_high']:+.2f}) | tổng {s['total']:+.1f}R | PF {pf} | "
            f"lãi TB {s['avg_win']:+.2f}R, lỗ TB {s['avg_loss']:+.2f}R | "
            f"thua liên tiếp max {s['max_losing_streak']} | DD max {s['max_drawdown']:.1f}R")


def breakdown(rows: list[dict], key: str, col: str, top: int | None = None) -> list[str]:
    groups: dict[str, list[float]] = defaultdict(list)
    signals: dict[str, int] = defaultdict(int)
    for r in rows:
        k = r.get(key) or "?"
        signals[k] += 1
        v = to_float(r.get(col, ""))
        if r.get("filled") == "1" and v is not None:
            groups[k].append(v)
    keys = sorted(signals, key=lambda k: -signals[k])
    if top:
        keys = keys[:top]
    lines = []
    for k in keys:
        s = r_stats(groups[k])
        fill = len(groups[k]) / signals[k] if signals[k] else 0.0
        body = fmt_stats(s) if s["n"] else "chưa có kèo khớp"
        lines.append(f"  {k:<14} tín hiệu {signals[k]:>3}, khớp {fill:>4.0%} | {body}")
    return lines


def pct_drawdown(rows: list[dict], col: str) -> float | None:
    """Drawdown lớn nhất theo % số dư: cộng đơn R × risk_pct lúc báo (không lãi kép)."""
    equity = peak = max_dd = 0.0
    seen = False
    for r in rows:
        v, rp = to_float(r.get(col, "")), to_float(r.get("risk_pct", ""))
        if r.get("filled") != "1" or v is None or rp is None:
            continue
        seen = True
        equity += v * rp
        peak = max(peak, equity)
        max_dd = max(max_dd, peak - equity)
    return max_dd if seen else None


def quality_lines(filled: list[dict], col: str) -> list[str]:
    """Chất lượng tín hiệu: tỷ lệ thắng hòa vốn, MFE/MAE của kèo thua và kèo thắng."""
    out: list[str] = []
    vals = [v for v in (to_float(r.get(col, "")) for r in filled) if v is not None]
    s = r_stats(vals)
    if s["n"] and s["avg_win"] > 0 and s["avg_loss"] < 0:
        be = -s["avg_loss"] / (s["avg_win"] - s["avg_loss"])
        out.append(f"Tỷ lệ thắng cần để hòa vốn (với lãi/lỗ TB hiện tại): {be:.0%} | thực tế {s['win_rate']:.0%} "
                   f"({'trên' if s['win_rate'] > be else 'dưới'} ngưỡng {abs(s['win_rate'] - be) * 100:.0f} điểm %)")
    pairs = [(to_float(r.get(col, "")), to_float(r.get("mfe_r", "")), to_float(r.get("mae_r", ""))) for r in filled]
    pairs = [p for p in pairs if None not in p]
    if not pairs:
        return out
    reach1 = sum(1 for _, mfe, _ in pairs if mfe >= 1.0)
    out.append(f"Kèo đã khớp đi thuận được >= 1R: {reach1}/{len(pairs)} ({reach1 / len(pairs):.0%})")
    losers = [(mfe, mae) for v, mfe, mae in pairs if v < 0]
    if losers:
        gave_back = sum(1 for mfe, _ in losers if mfe >= 1.0)
        never = sum(1 for mfe, _ in losers if mfe < 0.3)
        out.append(f"Kèo thua: {len(losers)} | từng lãi >= 1R rồi quay đầu {gave_back} ({gave_back / len(losers):.0%}) "
                   f"-> quản lý lệnh | chưa từng lãi 0.3R {never} ({never / len(losers):.0%}) -> chất lượng điểm vào/hướng")
    winners = [mae for v, _, mae in pairs if v > 0]
    if winners:
        out.append(f"Kèo thắng: đi ngược (MAE) trung vị {statistics.median(winners):.2f}R, "
                   f"lớn nhất {max(winners):.2f}R -> nếu thường < 0.5R, SL có thể đang quá rộng")
    return out


def report(rows: list[dict], scenario: str) -> str:
    col, label = SCENARIOS[scenario]
    out: list[str] = []
    total = len(rows)
    filled = [r for r in rows if r.get("filled") == "1"]
    out.append(f"Tổng tín hiệu đã đóng: {total} | khớp: {len(filled)}"
               + (f" ({len(filled) / total:.0%})" if total else ""))
    if not total:
        return "\n".join(out + ["Chưa có dữ liệu."])

    outcomes: dict[str, int] = defaultdict(int)
    for r in rows:
        outcomes[r.get("outcome") or "?"] += 1
    out.append("Kết quả: " + ", ".join(f"{k} {v}" for k, v in sorted(outcomes.items(), key=lambda x: -x[1])))

    out.append("")
    out.append("== Kỳ vọng theo kịch bản (chỉ kèo đã khớp, đơn vị R = khoảng cách Entry-SL) ==")
    for sc, (c, lbl) in SCENARIOS.items():
        vals = [v for v in (to_float(r.get(c, "")) for r in filled) if v is not None]
        out.append(f"{sc} - {lbl}: {fmt_stats(r_stats(vals))}")

    money = [v for v in (to_float(r.get("money_a", "")) for r in filled) if v is not None]
    if money:
        out.append(f"Lãi/lỗ lý thuyết kịch bản A theo lot gợi ý: {sum(money):+.2f} (tiền tệ tài khoản)")

    mtf = [v for v in (to_float(r.get("minutes_to_fill", "")) for r in filled) if v is not None]
    hold = [v for v in (to_float(r.get("hold_hours", "")) for r in filled) if v is not None]
    mfe = [v for v in (to_float(r.get("mfe_r", "")) for r in filled) if v is not None]
    mae = [v for v in (to_float(r.get("mae_r", "")) for r in filled) if v is not None]
    if mtf:
        out.append(f"Thời gian chờ khớp (trung vị): {statistics.median(mtf):.0f} phút")
    if hold:
        out.append(f"Thời gian giữ lệnh (trung vị): {statistics.median(hold):.1f} giờ")
    if mfe and mae:
        out.append(f"Đi thuận lớn nhất (MFE) trung vị {statistics.median(mfe):.2f}R | "
                   f"đi ngược lớn nhất (MAE) trung vị {statistics.median(mae):.2f}R")

    out.append("")
    out.append(f"== Chất lượng tín hiệu (kịch bản {scenario}) ==")
    out.extend(quality_lines(filled, col))
    dd = pct_drawdown(rows, col)
    if dd is not None:
        out.append(f"Drawdown max theo % số dư (cộng đơn R × % rủi ro lúc báo): {dd:.1f}%")

    out.append("")
    out.append(f"== Chi tiết theo kịch bản {scenario} ({label}) ==")
    for key, title, top in (("tier", "Tầng", None), ("group", "Nhóm tài sản", None), ("type", "Loại setup", None),
                            ("side", "Hướng", None), ("score", "Điểm bias", None), ("month", "Tháng (độ ổn định)", None),
                            ("symbol", "Symbol (top 10)", 10)):
        out.append(f"{title}:")
        out.extend(breakdown(rows, key, col, top))

    out.append("")
    if len(filled) < MIN_SAMPLE:
        out.append(f"CẢNH BÁO: mới có {len(filled)} kèo khớp (< {MIN_SAMPLE}). Kết quả chưa đủ tin cậy - "
                   "khoảng tin cậy 95% còn rất rộng. Tiếp tục thu thập trước khi kết luận.")
    else:
        vals = [v for v in (to_float(r.get(col, "")) for r in filled) if v is not None]
        s = r_stats(vals)
        if s["ci_low"] > 0:
            verdict = "kỳ vọng DƯƠNG có ý nghĩa thống kê (cận dưới 95% > 0)."
        elif s["ci_high"] < 0:
            verdict = "kỳ vọng ÂM có ý nghĩa thống kê - không nên giao dịch theo cấu hình này."
        else:
            verdict = "chưa phân biệt được với 0 (khoảng tin cậy chứa 0) - cần thêm dữ liệu hoặc cải tiến logic."
        out.append(f"Đánh giá kịch bản {scenario}: {verdict}")
    out.append("Lưu ý: kết quả là mô phỏng trên nến M1 (SL và TP cùng nến tính SL trước), chưa gồm trượt giá/commission.")
    return "\n".join(out)


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description="Phân tích nhật ký kết quả tín hiệu SignalEA")
    p.add_argument("csv", type=Path, help="Đường dẫn journal_<login>.csv")
    p.add_argument("--scenario", choices=sorted(SCENARIOS), default="A", help="Kịch bản dùng cho bảng chi tiết")
    p.add_argument("--include-pending", action="store_true",
                   help="Tính cả setup 'đang chờ, vượt ngưỡng rủi ro' (mặc định loại)")
    a = p.parse_args(argv)
    if not a.csv.is_file():
        print(f"Không tìm thấy file: {a.csv}", file=sys.stderr)
        return 1
    print(report(load_rows(a.csv, a.include_pending), a.scenario))
    return 0


if __name__ == "__main__":
    sys.exit(main())

"""Logic phân tích của SignalEA (chuyển từ Analysis.mqh), dùng cho backtest.

Giữ đúng thứ tự và điều kiện của EA để kết quả backtest phản ánh đúng EA.
"""
from __future__ import annotations

import bisect
from dataclasses import dataclass, field
from typing import Optional

from bt_data import TF_ORDER, SymbolData
from bt_indicators import TfIndicators, swing_flags

SIDE_BUY, SIDE_SELL = 1, -1
PULLBACK, BREAKOUT = 0, 1


@dataclass
class Params:
    """Mặc định trùng input của SignalEA.mq5."""
    # danh sách
    priority: tuple = ("BTCUSD", "XAUUSD")
    secondary: tuple = ("ETHUSD", "XAGUSD")
    suffix: str = ""
    # chỉ báo
    sma_fast: int = 10
    sma_base: int = 20
    sma_mid: int = 50
    sma_slow: int = 200
    bb_period: int = 20
    bb_dev: float = 2.0
    rsi_period: int = 14
    atr_period: int = 14
    slope_bars: int = 3
    bars_window: int = 320
    # lọc
    min_bars_d1: int = 250
    min_bars_h1: int = 300
    min_bars_h4: int = 100
    max_spread_atr_pct: float = 15.0
    max_min_lot_risk_pct: float = 4.0
    feas_sl_atr_mult: float = 1.0
    # bias & ngưỡng
    weights: tuple = (1, 2, 3, 2, 1)          # MN1, W1, D1, H4, H1
    bias_min_conditions: int = 3
    min_score_priority: int = 5
    min_rr_priority: float = 1.3
    min_score_other: int = 7
    min_rr_other: float = 1.8
    # setup
    enable_pullback: bool = True
    enable_breakout: bool = True
    entry_zone_atr_h1: float = 0.3
    confluence_tol_atr_h1: float = 0.5
    min_confluence: int = 2
    max_entry_dist_atr_h4: float = 2.0
    swing_strength_h1: int = 3
    swing_strength_h4: int = 2
    swing_strength_d1: int = 2
    swing_lookback: int = 150
    sl_buffer_atr_h4: float = 0.25
    sl_fallback_atr_h4: float = 1.0
    tp_min_gap_atr_h4: float = 0.3
    setup_expiry_hours: int = 24
    triggered_max_hours: int = 72
    cooldown_minutes: int = 240
    # xếp hạng, tương quan
    top_k: int = 3
    max_new_per_day: int = 10
    correlation_groups: str = ("KIM_LOAI:XAU,XAG,XPT,XPD;CRYPTO:BTC,ETH,LTC,XRP,BCH,SOL,ADA,DOGE;"
                               "CHI_SO_MY:US30,US500,USTEC,US100;DAU:UKOIL,USOIL,XBR,XTI")
    max_currency_same_side: int = 2
    # vốn
    balance: float = 1000.0
    risk_per_trade_pct: float = 1.5
    max_total_risk_pct: float = 5.0
    # nhật ký / mô phỏng
    journal_max_hold_hours: int = 120
    display_gmt_offset_hours: float = 7.0

    def tier_of(self, base: str) -> int:
        if base in self.priority:
            return 0
        if base in self.secondary:
            return 1
        return 2


@dataclass
class Snapshot:
    ok: bool = False
    bars: int = 0
    close: Optional[float] = None
    sma_fast: Optional[float] = None
    sma_base: Optional[float] = None
    sma_mid: Optional[float] = None
    sma_slow: Optional[float] = None
    sma_base_prev: Optional[float] = None
    rsi: Optional[float] = None
    atr: Optional[float] = None


@dataclass
class Geom:
    type: int = PULLBACK
    side: int = 0
    entry_low: float = 0.0
    entry_high: float = 0.0
    entry_ref: float = 0.0
    sl: float = 0.0
    tp1: float = 0.0
    tp2: Optional[float] = None
    rr1: float = 0.0
    rr2: Optional[float] = None
    confluence: int = 0


@dataclass
class AnaResult:
    bias_tf: list = field(default_factory=lambda: [0] * 5)
    score: int = 0
    max_score: int = 9
    has_setup: bool = False
    geom: Geom = field(default_factory=Geom)
    reasons: str = ""
    note: str = ""


class SymbolModel:
    """Chỉ báo + swing tính trước cho 1 symbol."""

    def __init__(self, data: SymbolData, p: Params):
        self.data = data
        self.p = p
        self.ind = {tf: TfIndicators(data.tf[tf], p.bars_window) for tf in TF_ORDER}
        self._swings: dict[tuple, list[int]] = {}
        for tf, st in (("H1", p.swing_strength_h1), ("H4", p.swing_strength_h4), ("D1", p.swing_strength_d1)):
            for highs in (True, False):
                flags = swing_flags(data.tf[tf], st, highs)
                self._swings[(tf, highs)] = [j for j, f in enumerate(flags) if f]

    def snapshot(self, tf: str, k: int) -> Snapshot:
        s = Snapshot()
        if k < 1:
            return s
        ind, p = self.ind[tf], self.p
        s.bars = min(k + 1, p.bars_window - 1)
        s.close = self.data.tf[tf].close[k]
        s.sma_fast = ind.sma(k, p.sma_fast)
        s.sma_base = ind.sma(k, p.sma_base)
        s.sma_mid = ind.sma(k, p.sma_mid)
        s.sma_slow = ind.sma(k, p.sma_slow)
        s.sma_base_prev = ind.sma(k - p.slope_bars, p.sma_base) if k - p.slope_bars >= 0 else None
        s.rsi = ind.rsi(k, p.rsi_period)
        s.atr = ind.atr(k, p.atr_period)
        s.ok = s.sma_base is not None and s.atr is not None
        return s

    def swings(self, tf: str, k: int, strength: int, highs: bool, min_shift: int) -> list[float]:
        """Giá các swing gần nhất trước (như AnaSwings, series index i <-> j = k+1-i)."""
        n = min(k + 2, self.p.bars_window)            # số nến EA tải, gồm nến đang chạy
        if strength < 1 or n < 2 * strength + 3:
            return []
        first = max(strength + 1, min_shift)
        last = min(self.p.swing_lookback, n - strength - 1)
        if last < first:
            return []
        j_hi, j_lo = k + 1 - first, k + 1 - last
        idx = self._swings[(tf, highs)]
        lo_pos = bisect.bisect_left(idx, j_lo)
        hi_pos = bisect.bisect_right(idx, j_hi)
        vals = self.data.tf[tf].high if highs else self.data.tf[tf].low
        return [vals[j] for j in reversed(idx[lo_pos:hi_pos])]


# ---------------------------------------------------------------------------
# Bias
# ---------------------------------------------------------------------------
def tf_bias(s: Snapshot, min_cond: int) -> int:
    if s.bars <= 0 or s.close is None:
        return 0
    bull = bear = 0
    if s.sma_base is not None:
        bull += s.close > s.sma_base
        bear += s.close < s.sma_base
    if s.sma_mid is not None:
        bull += s.close > s.sma_mid
        bear += s.close < s.sma_mid
    if s.sma_base is not None and s.sma_base_prev is not None:
        bull += s.sma_base > s.sma_base_prev
        bear += s.sma_base < s.sma_base_prev
    if s.rsi is not None:
        bull += s.rsi > 50.0
        bear += s.rsi < 50.0
    if bull >= min_cond:
        return 1
    if bear >= min_cond:
        return -1
    return 0


def bias_text(res: AnaResult) -> str:
    parts = []
    for t, tf in enumerate(TF_ORDER):
        v = res.bias_tf[t]
        parts.append(f"{tf} {'tăng' if v > 0 else ('giảm' if v < 0 else '0')}")
    return " | ".join(parts) + f"  (điểm {abs(res.score)}/{res.max_score})"


# ---------------------------------------------------------------------------
# SL / TP
# ---------------------------------------------------------------------------
def stop_loss(side: int, zone_low: float, zone_high: float, a: list[float], b: list[float],
              atr_h4: float, p: Params) -> float:
    found = None
    limit = 3.0 * atr_h4
    for price in a + b:
        if side < 0:
            if zone_low <= price <= zone_high + limit and (found is None or price < found):
                found = price
        else:
            if zone_low - limit <= price <= zone_high and (found is None or price > found):
                found = price
    if side < 0:
        if found is None:
            return zone_high + p.sl_fallback_atr_h4 * atr_h4
        return max(found, zone_high) + p.sl_buffer_atr_h4 * atr_h4
    if found is None:
        return zone_low - p.sl_fallback_atr_h4 * atr_h4
    return min(found, zone_low) - p.sl_buffer_atr_h4 * atr_h4


def targets(side: int, entry: float, a: list[float], b: list[float], atr_h4: float,
            p: Params) -> tuple[Optional[float], Optional[float]]:
    gap = p.tp_min_gap_atr_h4 * atr_h4
    dedup = 0.25 * atr_h4
    c = [x for x in a + b if (x < entry - gap if side < 0 else x > entry + gap)]
    if not c:
        return None, None
    c.sort(key=lambda x: abs(x - entry))      # sort ổn định như insertion sort của EA
    tp1 = c[0]
    tp2 = next((x for x in c[1:] if abs(x - tp1) >= dedup), None)
    return tp1, tp2


def finalize(g: Geom, sl_a: list[float], sl_b: list[float], tp_a: list[float], tp_b: list[float],
             atr_h4: float, min_rr: float, p: Params) -> tuple[bool, str]:
    g.sl = stop_loss(g.side, g.entry_low, g.entry_high, sl_a, sl_b, atr_h4, p)
    risk = (g.sl - g.entry_ref) if g.side < 0 else (g.entry_ref - g.sl)
    if risk <= 0:
        return False, "SL không hợp lệ"
    tp1, tp2 = targets(g.side, g.entry_ref, tp_a, tp_b, atr_h4, p)
    if tp1 is None:
        return False, "không tìm được mức TP (swing H4/D1)"
    g.tp1, g.tp2 = tp1, tp2
    g.rr1 = abs(tp1 - g.entry_ref) / risk
    g.rr2 = abs(tp2 - g.entry_ref) / risk if tp2 is not None else None
    if g.rr1 < min_rr:
        return False, f"RR TP1 {g.rr1:.2f} < {min_rr:.2f}"
    return True, ""


# ---------------------------------------------------------------------------
# Vùng Entry
# ---------------------------------------------------------------------------
def pullback_zone(side: int, snaps: dict, sw_h1: list[float], sw_h4: list[float], ref: float,
                  p: Params) -> tuple[Optional[Geom], str, str]:
    atr_h1, atr_h4 = snaps["H1"].atr, snaps["H4"].atr
    w = p.entry_zone_atr_h1 * atr_h1
    tol = p.confluence_tol_atr_h1 * atr_h1
    max_dist = p.max_entry_dist_atr_h4 * atr_h4
    allv: list[tuple[float, str]] = []
    for price, kind in ((snaps["H4"].sma_mid, f"SMA{p.sma_mid} H4"),
                        (snaps["H1"].sma_slow, f"SMA{p.sma_slow} H1"),
                        (snaps["H1"].sma_mid, f"SMA{p.sma_mid} H1")):
        if price is not None and price > 0:
            allv.append((price, kind))
    allv += [(x, "swing H1") for x in sw_h1 if x > 0]
    allv += [(x, "swing H4") for x in sw_h4 if x > 0]
    if side < 0:
        lv = [(x, k) for x, k in allv if ref + w * 0.5 < x <= ref + max_dist]
    else:
        lv = [(x, k) for x, k in allv if ref - max_dist <= x < ref - w * 0.5]
    if len(lv) < p.min_confluence:
        return None, "", f"không đủ mức giá phía {'trên' if side < 0 else 'dưới'}"
    lv.sort(key=lambda t: abs(t[0] - ref))
    for a_price, _ in lv:
        kinds: list[str] = []
        total, members = 0.0, 0
        for x, kind in lv:
            d = (x - a_price) if side < 0 else (a_price - x)
            if d < 0.0 or d > tol:
                continue
            total += x
            members += 1
            if kind not in kinds:
                kinds.append(kind)
        if len(kinds) < p.min_confluence:
            continue
        center = total / members
        lo, hi = center - w * 0.5, center + w * 0.5
        if side < 0 and lo <= ref:
            continue
        if side > 0 and hi >= ref:
            continue
        g = Geom(type=PULLBACK, side=side, entry_low=lo, entry_high=hi, entry_ref=center, confluence=len(kinds))
        return g, "hội tụ " + " + ".join(kinds), ""
    return None, "", f"không có vùng hội tụ >= {p.min_confluence} yếu tố"


def breakout_zone(model: SymbolModel, side: int, k4: int, snaps: dict, point: float,
                  p: Params) -> tuple[Optional[Geom], str, str]:
    h4 = model.data.tf["H4"]
    n_h4 = min(k4 + 2, p.bars_window)
    if n_h4 < 10 or k4 < 1:
        return None, "", "thiếu nến H4"
    st = p.swing_strength_h4
    sw = model.swings("H4", k4, st, side > 0, st + 2)
    if not sw:
        return None, "", "không có swing H4"
    level = sw[0]
    c1, c2 = h4.close[k4], h4.close[k4 - 1]
    broke = (c1 < level <= c2) if side < 0 else (c2 <= level < c1)
    if not broke:
        return None, "", "H4 chưa phá swing gần nhất"
    atr_h4 = snaps["H4"].atr
    w = max(p.entry_zone_atr_h1 * snaps["H1"].atr, point)
    if side < 0:
        lo = c1
        hi = min(level, c1 + 0.5 * atr_h4)
        if hi - lo < w:
            hi = lo + w
    else:
        hi = c1
        lo = max(level, c1 - 0.5 * atr_h4)
        if hi - lo < w:
            lo = hi - w
    g = Geom(type=BREAKOUT, side=side, entry_low=lo, entry_high=hi, entry_ref=(lo + hi) * 0.5, confluence=1)
    word = "dưới đáy" if side < 0 else "trên đỉnh"
    return g, f"H4 đóng {c1} {word} swing H4 {level}", ""


# ---------------------------------------------------------------------------
# Phân tích 1 symbol tại thời điểm t (đóng nến H1)
# ---------------------------------------------------------------------------
def analyze(model: SymbolModel, idx: dict, snaps: dict, tier: int, bid: float, ask: float,
            new_h4: bool, allow: bool) -> AnaResult:
    p = model.p
    res = AnaResult(max_score=sum(p.weights))
    for t, tf in enumerate(TF_ORDER):
        res.bias_tf[t] = tf_bias(snaps[tf], p.bias_min_conditions)
        res.score += res.bias_tf[t] * p.weights[t]
    if not allow:
        res.note = "đang có setup/cooldown"
        return res
    min_score = p.min_score_priority if tier == 0 else p.min_score_other
    min_rr = p.min_rr_priority if tier == 0 else p.min_rr_other
    if abs(res.score) < min_score:
        res.note = f"bias {abs(res.score)}/{res.max_score} chưa đạt ngưỡng {min_score}"
        return res
    side = SIDE_BUY if res.score > 0 else SIDE_SELL
    atr_h4 = snaps["H4"].atr
    k1, k4, kd = idx["H1"], idx["H4"], idx["D1"]
    sh1, sh4, sd1 = p.swing_strength_h1, p.swing_strength_h4, p.swing_strength_d1
    h1_hi, h1_lo = model.swings("H1", k1, sh1, True, 1), model.swings("H1", k1, sh1, False, 1)
    h4_hi, h4_lo = model.swings("H4", k4, sh4, True, 1), model.swings("H4", k4, sh4, False, 1)
    d1_hi, d1_lo = model.swings("D1", kd, sd1, True, 1), model.swings("D1", kd, sd1, False, 1)
    ref = bid if side < 0 else ask

    pb_ok = bo_ok = False
    pb = bo = None
    pb_reason = bo_reason = pb_why = bo_why = ""
    if p.enable_pullback:
        pb, pb_reason, pb_why = pullback_zone(side, snaps, h1_hi if side < 0 else h1_lo,
                                              h4_hi if side < 0 else h4_lo, ref, p)
        if pb is not None:
            if side < 0:
                pb_ok, pb_why = finalize(pb, h1_hi, h4_hi, h4_lo, d1_lo, atr_h4, min_rr, p)
            else:
                pb_ok, pb_why = finalize(pb, h1_lo, h4_lo, h4_hi, d1_hi, atr_h4, min_rr, p)
    if p.enable_breakout and new_h4:
        bo, bo_reason, bo_why = breakout_zone(model, side, k4, snaps, model.data.spec.point, p)
        if bo is not None:
            if side < 0:
                bo_ok, bo_why = finalize(bo, h1_hi, h4_hi, h4_lo, d1_lo, atr_h4, min_rr, p)
            else:
                bo_ok, bo_why = finalize(bo, h1_lo, h4_lo, h4_hi, d1_hi, atr_h4, min_rr, p)
    elif p.enable_breakout:
        bo_why = "chưa có nến H4 mới"
    if not pb_ok and not bo_ok:
        res.note = f"chờ hồi: {pb_why or 'tắt'} | phá vỡ: {bo_why or 'tắt'}"
        return res
    use_bo = bo_ok and (not pb_ok or bo.rr1 > pb.rr1)
    res.geom = bo if use_bo else pb
    res.reasons = bo_reason if use_bo else pb_reason
    res.has_setup = True
    return res

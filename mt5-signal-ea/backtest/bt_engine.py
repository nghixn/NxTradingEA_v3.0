"""Engine backtest đa symbol: chạy lại đúng luồng của SignalEA theo từng giờ.

Mỗi lần đóng nến H1 (thời điểm T):
  1. Theo dõi setup và nhật ký trên các nến giá (M1 nếu có, không thì H1) trong [T trước, T).
  2. Phân tích từng symbol (ưu tiên trước), như ProcessSymbol + AnaAnalyze.
  3. Ưu tiên báo ngay; phụ/khám phá xếp hạng cuối vòng (top K, giới hạn tin/ngày).
Kiểm tra trước khi báo, vòng đời setup và mô phỏng kết quả chuyển từ Signals.mqh / Journal.mqh.
"""
from __future__ import annotations

import math
from collections import Counter, defaultdict
from dataclasses import dataclass, field
from datetime import datetime, timedelta, timezone
from typing import Optional

from bt_data import TF_ORDER, Series, SymbolData
from bt_strategy import (BREAKOUT, SIDE_BUY, AnaResult, Params, SymbolModel, analyze, bias_text)

# Trạng thái setup (giống Signals.mqh)
ACTIVE, TRIGGERED, PENDING_RISK, INVALIDATED, EXPIRED, DONE = range(6)
OPEN_STATES = (ACTIVE, TRIGGERED, PENDING_RISK)
RISK_STATES = (ACTIVE, TRIGGERED)
STATE_NAME = {ACTIVE: "chờ Entry", TRIGGERED: "đã vào vùng", PENDING_RISK: "chờ (vượt rủi ro)",
              INVALIDATED: "đã hủy", EXPIRED: "hết hạn", DONE: "đạt mục tiêu"}
# Nhật ký
J_WAIT, J_TRADE, J_CLOSED = range(3)

METALS = ("XAU", "XAG", "XPT", "XPD")
CRYPTOS = ("BTC", "ETH", "LTC", "XRP", "BCH", "ADA", "DOT", "SOL", "DOGE", "BNB", "LINK", "UNI", "XLM",
           "AVAX", "MATIC", "POL", "TRX", "ATOM", "XTZ", "EOS", "FIL", "AAVE", "SHIB", "TON", "NEAR", "ARB", "OP")
ENERGIES = ("OIL", "BRENT", "WTI", "NGAS", "XNG", "XTI", "XBR", "GASOIL")
INDICES = ("US30", "US500", "USTEC", "US100", "US2000", "NAS100", "SPX", "DJ30", "DE30", "DE40", "GER",
           "UK100", "FR40", "JP225", "HK50", "AUS200", "STOXX50", "EU50", "CN50", "ES35", "IT40", "IN50")
GROUP_CODES = ["forex", "metals", "crypto", "indices", "energies", "stocks", "other"]
TIER_CODES = ["priority", "secondary", "discovery"]


def classify(data: SymbolData) -> int:
    """Như UniClassify: SYMBOL_PATH -> tiền tệ cơ sở/tên -> kiểu tính margin."""
    path = data.spec.path.lower()
    up = data.name.upper()
    base = data.spec.currency_base.upper()
    g = 6
    if "crypto" in path:
        g = 2
    elif "metal" in path:
        g = 1
    elif "energ" in path or "oil" in path:
        g = 4
    elif "indic" in path or "index" in path or "indices" in path:
        g = 3
    elif "stock" in path or "share" in path or "equit" in path:
        g = 5
    elif any(w in path for w in ("forex", "currenc", "major", "minor", "exotic")) or path.startswith("fx"):
        g = 0
    if g in (0, 6):
        if base.startswith(METALS) or up.startswith(METALS):
            g = 1
        elif base.startswith(CRYPTOS) or (g == 6 and up.startswith(CRYPTOS)):
            g = 2
        elif any(e in up for e in ENERGIES):
            g = 4
    if g == 6:
        cm = data.spec.calc_mode
        if cm in ("SYMBOL_CALC_MODE_FOREX", "SYMBOL_CALC_MODE_FOREX_NO_LEVERAGE"):
            g = 0
        elif cm == "SYMBOL_CALC_MODE_CFDINDEX" or up.startswith(INDICES):
            g = 3
        elif cm == "SYMBOL_CALC_MODE_EXCH_STOCKS":
            g = 5
    return g


def parse_corr_groups(text: str) -> list[tuple[str, list[str]]]:
    out = []
    for part in text.split(";"):
        if ":" not in part:
            continue
        name, codes = part.split(":", 1)
        out.append((name.strip(), [c.strip().upper() for c in codes.split(",") if c.strip()]))
    return out


@dataclass
class Setup:
    id: str
    sym: str
    tier: int
    group: int
    corr: str
    base_ccy: str
    quote_ccy: str
    side: int
    type: int
    score: int
    max_score: int
    confluence: int
    entry_low: float
    entry_high: float
    entry_ref: float
    sl: float
    tp1: float
    tp2: Optional[float]
    rr1: float
    rr2: Optional[float]
    spread_pct: float
    reasons: str
    bias_text: str
    created: int
    expires: int
    last_h4_close: int
    state: int = ACTIVE
    lots: float = 0.0
    risk_money: float = 0.0
    risk_pct: float = 0.0
    min_lot_risk_money: float = 0.0
    min_lot_risk_pct: float = 0.0
    risk_warn: bool = False
    quality: float = 0.0
    triggered_at: int = 0
    closed_at: int = 0


@dataclass
class Journal:
    setup: Setup
    pending: bool
    spread: float
    phase: int = J_WAIT
    fill_time: int = 0
    close_time: int = 0
    r_a: Optional[float] = None
    r_b: Optional[float] = None
    r_c1: Optional[float] = None
    r_c2: Optional[float] = None
    c2_active: bool = False
    mfe: float = 0.0
    mae: float = 0.0
    outcome: str = ""
    note: str = ""


@dataclass
class SymState:
    model: SymbolModel
    tier: int
    group: int
    corr: str
    last_h4_seen: int = -1
    last_closed: int = -10 ** 12      # lần đóng setup gần nhất (cooldown)


@dataclass
class Result:
    rows: list = field(default_factory=list)          # Journal đã đóng
    open_at_end: int = 0
    counters: Counter = field(default_factory=Counter)
    setups_by_symbol: Counter = field(default_factory=Counter)
    evaluations: int = 0
    start: int = 0
    end: int = 0


def _no_setup_reason(note: str) -> str:
    if note.startswith("bias"):
        return "bias chưa đạt ngưỡng"
    pb = note.split(" | ")[0]
    if "RR TP1" in pb:
        return "RR TP1 thấp"
    if "TP" in pb:
        return "không có mức TP"
    if "SL" in pb:
        return "SL không hợp lệ"
    return "không có vùng hội tụ"


class Backtest:
    def __init__(self, symbols: list[SymbolData], p: Params, use_m1: bool = True):
        self.p = p
        self.use_m1 = use_m1
        self.corr_groups = parse_corr_groups(p.correlation_groups)
        self.syms: dict[str, SymState] = {}
        for d in symbols:
            err = d.spec.validate()
            if err:
                raise ValueError(f"{d.name}: {err}")
            base = d.name[: -len(p.suffix)] if p.suffix and d.name.endswith(p.suffix) else d.name
            self.syms[d.name] = SymState(model=SymbolModel(d, p), tier=p.tier_of(base), group=classify(d),
                                         corr=self._corr_of(base))
        self.setups: list[Setup] = []         # đang mở
        self.journals: list[Journal] = []     # đang theo dõi
        self.res = Result()
        self.day_key = None
        self.new_today = 0

    # ------------------------------------------------------------------ tiện ích
    def _corr_of(self, base: str) -> str:
        up = base.upper()
        for name, codes in self.corr_groups:
            if any(up.startswith(c) for c in codes):
                return name
        return ""

    def _display_day(self, t: int, spec_offset: int) -> str:
        d = datetime.fromtimestamp(t - spec_offset, tz=timezone.utc) + timedelta(hours=self.p.display_gmt_offset_hours)
        return d.strftime("%Y-%m-%d")

    def _fmt_time(self, t: int, spec_offset: int) -> str:
        if not t:
            return ""
        d = datetime.fromtimestamp(t - spec_offset, tz=timezone.utc) + timedelta(hours=self.p.display_gmt_offset_hours)
        return d.strftime("%Y-%m-%d %H:%M")

    def total_risk(self) -> float:
        return sum(s.risk_money for s in self.setups if s.state in RISK_STATES)

    # ------------------------------------------------------------------ dữ liệu giá
    def _feed(self, sym: str, t0: int, t1: int):
        """Các nến giá mở trong [t0, t1): M1 nếu có dữ liệu cho đoạn này, không thì H1."""
        data = self.syms[sym].model.data
        m1 = data.m1 if self.use_m1 else None
        s: Series = m1 if (m1 is not None and len(m1) and t0 >= m1.time[0]) else data.tf["H1"]
        i = s.first_open_at_or_after(t0)
        while i < len(s) and s.time[i] < t1:
            yield s, i
            i += 1

    # ------------------------------------------------------------------ vòng đời setup
    def _h4_invalidation(self, st: Setup, t: int) -> bool:
        h4 = self.syms[st.sym].model.data.tf["H4"]
        k = h4.last_closed(t)
        if k < 0 or h4.close_time[k] <= st.last_h4_close:
            return False
        j = k
        while j > 0 and h4.close_time[j - 1] > st.last_h4_close:
            j -= 1
        broken_at = 0
        for q in range(j, k + 1):
            c = h4.close[q]
            if (c > st.sl) if st.side < 0 else (c < st.sl):
                broken_at = h4.close_time[q]
                break
        st.last_h4_close = h4.close_time[k]
        if broken_at:
            self._close_setup(st, INVALIDATED, broken_at, "H4 đóng vượt SL")
            return True
        return False

    def _close_setup(self, st: Setup, state: int, when: int, why: str) -> None:
        st.state = state
        st.closed_at = when
        self.syms[st.sym].last_closed = when
        self.res.counters[f"setup đóng: {STATE_NAME[state]}"] += 1

    def _monitor_bar(self, st: Setup, s: Series, i: int, spread: float) -> None:
        t = s.time[i]
        bar_end = s.close_time[i]
        hi, lo = s.high[i], s.low[i]
        if st.state == PENDING_RISK:
            if bar_end >= st.expires:
                self._close_setup(st, EXPIRED, st.expires, "chờ rủi ro hết hạn")
            return
        if self._h4_invalidation(st, t):
            return
        if st.state == ACTIVE:
            touched = (hi >= st.entry_low) if st.side < 0 else (lo + spread <= st.entry_high)
            if touched:
                st.state = TRIGGERED
                st.triggered_at = t
                return
            missed = (lo <= st.tp1) if st.side < 0 else (hi >= st.tp1)
            if missed:
                self._close_setup(st, INVALIDATED, bar_end, "lỡ kèo")
                return
            if bar_end >= st.expires:
                self._close_setup(st, EXPIRED, st.expires, "hết hạn")
        elif st.state == TRIGGERED:
            target = st.tp2 if st.tp2 is not None else st.tp1
            hit = (lo <= target) if st.side < 0 else (hi >= target)
            if hit:
                self._close_setup(st, DONE, bar_end, "đạt mục tiêu")
            elif t - st.triggered_at >= self.p.triggered_max_hours * 3600:
                self._close_setup(st, EXPIRED, bar_end, "vào vùng quá lâu")

    # ------------------------------------------------------------------ nhật ký (Journal.mqh)
    @staticmethod
    def _hit_sl(j: Journal, hi: float, lo: float) -> bool:
        return (hi + j.spread >= j.setup.sl) if j.setup.side < 0 else (lo <= j.setup.sl)

    @staticmethod
    def _hit_target(j: Journal, hi: float, lo: float, target: float) -> bool:
        return (lo + j.spread <= target) if j.setup.side < 0 else (hi >= target)

    @staticmethod
    def _hit_be(j: Journal, hi: float, lo: float) -> bool:
        e = j.setup.entry_ref
        return (hi + j.spread >= e) if j.setup.side < 0 else (lo <= e)

    @staticmethod
    def _track(j: Journal, hi: float, lo: float, fill_bar: bool = False) -> None:
        e = j.setup.entry_ref
        if j.setup.side < 0:
            fav, adv = e - (lo + j.spread), (hi + j.spread) - e
        else:
            fav, adv = hi - e, e - lo
        if not fill_bar and fav > j.mfe:     # nến khớp: chỉ tính MAE
            j.mfe = fav
        if adv > j.mae:
            j.mae = adv

    def _journal_finish(self, j: Journal, when: int, outcome: str, note: str = "") -> None:
        j.phase = J_CLOSED
        j.close_time = when
        j.outcome = outcome
        j.note = note
        self.res.rows.append(j)

    def _journal_bar(self, j: Journal, s: Series, i: int) -> None:
        st = j.setup
        t, hi, lo, close = s.time[i], s.high[i], s.low[i], s.close[i]
        if j.phase == J_WAIT:
            filled = (hi >= st.entry_ref) if st.side < 0 else (lo + j.spread <= st.entry_ref)
            if not filled:
                return
            j.phase = J_TRADE
            j.fill_time = t
            self._track(j, hi, lo, fill_bar=True)
            if self._hit_sl(j, hi, lo):
                j.r_a = j.r_b = j.r_c1 = j.r_c2 = -1.0
                self._journal_finish(j, t, "SL", "chạm SL ngay trong nến khớp")
            return
        if j.phase != J_TRADE:
            return
        self._track(j, hi, lo)
        sl = self._hit_sl(j, hi, lo)
        has_tp2 = st.tp2 is not None
        t2 = st.tp2 if has_tp2 else st.tp1
        r2 = st.rr2 if has_tp2 else st.rr1
        if j.r_a is None:
            if sl:
                j.r_a = -1.0
            elif self._hit_target(j, hi, lo, st.tp1):
                j.r_a = st.rr1
        if j.r_b is None:
            if sl:
                j.r_b = -1.0
            elif self._hit_target(j, hi, lo, t2):
                j.r_b = r2
        if j.r_c1 is None:
            if sl:
                j.r_c1 = j.r_c2 = -1.0
            elif self._hit_target(j, hi, lo, st.tp1):
                j.r_c1 = st.rr1
                if has_tp2:
                    j.c2_active = True
                else:
                    j.r_c2 = st.rr1
        elif j.r_c2 is None and j.c2_active:
            if self._hit_be(j, hi, lo):
                j.r_c2 = 0.0
            elif self._hit_target(j, hi, lo, t2):
                j.r_c2 = r2
        if None not in (j.r_a, j.r_b, j.r_c1, j.r_c2):
            if j.r_a < 0:
                label = "SL"
            elif not has_tp2:
                label = "TP1"
            elif j.r_b > 0:
                label = "TP2"
            else:
                label = "TP1_SL"
            self._journal_finish(j, t, label)
            return
        if t - j.fill_time >= self.p.journal_max_hold_hours * 3600:
            risk = abs(st.entry_ref - st.sl)
            mark = ((st.entry_ref - (close + j.spread)) if st.side < 0 else (close - st.entry_ref)) / risk
            j.r_a = mark if j.r_a is None else j.r_a
            j.r_b = mark if j.r_b is None else j.r_b
            j.r_c1 = mark if j.r_c1 is None else j.r_c1
            j.r_c2 = mark if j.r_c2 is None else j.r_c2
            self._journal_finish(j, t, "TIMEOUT", f"quá {self.p.journal_max_hold_hours}h, chốt theo giá đóng cửa")

    # ------------------------------------------------------------------ cập nhật giữa 2 lần đóng H1
    def _advance(self, t0: int, t1: int) -> None:
        syms = {s.sym for s in self.setups} | {j.setup.sym for j in self.journals}
        for sym in syms:
            sts = [s for s in self.setups if s.sym == sym]
            jns = [j for j in self.journals if j.setup.sym == sym]
            for s, i in self._feed(sym, t0, t1):
                spread_now = s.spread[i] * self.syms[sym].model.data.spec.point
                for st in sts:
                    if st.state in OPEN_STATES:
                        self._monitor_bar(st, s, i, spread_now)
                for j in jns:
                    if j.phase == J_CLOSED:
                        continue
                    st = j.setup
                    if j.phase == J_WAIT and st.state not in OPEN_STATES and s.time[i] >= st.closed_at:
                        continue
                    self._journal_bar(j, s, i)
            # setup đã đóng mà giá chưa tới entry_ref -> không khớp
            for j in jns:
                if j.phase == J_WAIT and j.setup.state not in OPEN_STATES:
                    self._journal_finish(j, j.setup.closed_at, "NOT_FILLED", "setup " + STATE_NAME[j.setup.state])
        self.setups = [s for s in self.setups if s.state in OPEN_STATES]
        self.journals = [j for j in self.journals if j.phase != J_CLOSED]

    # ------------------------------------------------------------------ kiểm tra trước khi báo
    def _can_create(self, sym: str, t: int) -> bool:
        if any(s.sym == sym for s in self.setups if s.state in OPEN_STATES):
            return False
        return t - self.syms[sym].last_closed >= self.p.cooldown_minutes * 60

    def _correlation_ok(self, c: Setup) -> tuple[bool, str, list]:
        yield_list = []
        if not c.corr:
            return True, "", yield_list
        for s in self.setups:
            if s.state not in RISK_STATES or s.corr != c.corr or s.sym == c.sym:
                continue
            opposite = s.side != c.side
            if c.tier == 0:
                if not opposite:
                    continue
                if s.tier != 0 and s.state == ACTIVE:
                    yield_list.append(s)
                    continue
                return False, "tương quan: ngược hướng", []
            return False, "tương quan: nhóm đã có setup", []
        return True, "", yield_list

    def _exposure_ok(self, c: Setup) -> bool:
        if c.group != 0 or not c.base_ccy or not c.quote_ccy:
            return True
        long_c = c.base_ccy if c.side > 0 else c.quote_ccy
        short_c = c.quote_ccy if c.side > 0 else c.base_ccy
        n_long = n_short = 0
        for s in self.setups:
            if s.state not in RISK_STATES or s.group != 0:
                continue
            l_ = s.base_ccy if s.side > 0 else s.quote_ccy
            sh = s.quote_ccy if s.side > 0 else s.base_ccy
            n_long += l_ == long_c
            n_short += sh == short_c
        return n_long + 1 <= self.p.max_currency_same_side and n_short + 1 <= self.p.max_currency_same_side

    def _admit(self, c: Setup, bid: float, ask: float, spread: float, t: int) -> int:
        """1 = báo, 2 = báo dạng 'đang chờ, vượt ngưỡng rủi ro', 0 = bị loại."""
        if (bid >= c.sl or bid <= c.tp1) if c.side < 0 else (bid <= c.sl or bid >= c.tp1):
            self.res.counters["loại: giá đã chạy quá SL/TP1"] += 1
            return 0
        ok, why, yields = self._correlation_ok(c)
        if not ok:
            self.res.counters["loại: " + why] += 1
            return 0
        if not self._exposure_ok(c):
            self.res.counters["loại: phơi nhiễm tiền tệ"] += 1
            return 0
        for s in yields:
            self._close_setup(s, INVALIDATED, t, "nhường cho setup ưu tiên")
        pending = self.total_risk() + c.risk_money > self.p.balance * self.p.max_total_risk_pct / 100.0
        if pending:
            c.state = PENDING_RISK
        elif (bid >= c.entry_low) if c.side < 0 else (ask <= c.entry_high):
            c.state = TRIGGERED
            c.triggered_at = t
        self.setups.append(c)
        self.journals.append(Journal(setup=c, pending=pending, spread=max(spread, 0.0)))
        self.res.setups_by_symbol[c.sym] += 1
        self.res.counters["báo: chờ rủi ro" if pending else f"báo: {TIER_CODES[c.tier]}"] += 1
        return 2 if pending else 1

    # ------------------------------------------------------------------ dựng setup (SigBuild)
    def _build(self, ss: SymState, res: AnaResult, spread_pct: float, t: int, last_h4_close: int) -> Optional[Setup]:
        p, d = self.p, ss.model.data
        g = res.geom
        st = Setup(
            id=f"{d.name}-{datetime.fromtimestamp(t, tz=timezone.utc):%Y%m%d%H}-{'BUY' if g.side > 0 else 'SELL'}-"
               f"{'BO' if g.type == BREAKOUT else 'PB'}",
            sym=d.name, tier=ss.tier, group=ss.group, corr=ss.corr, base_ccy=d.spec.currency_base,
            quote_ccy=d.spec.currency_profit, side=g.side, type=g.type, score=abs(res.score), max_score=res.max_score,
            confluence=g.confluence, entry_low=g.entry_low, entry_high=g.entry_high, entry_ref=g.entry_ref,
            sl=g.sl, tp1=g.tp1, tp2=g.tp2, rr1=g.rr1, rr2=g.rr2, spread_pct=spread_pct, reasons=res.reasons,
            bias_text=bias_text(res), created=t, expires=t + p.setup_expiry_hours * 3600, last_h4_close=last_h4_close)
        spec = d.spec
        dist = abs(st.entry_ref - st.sl)
        per_lot = dist / spec.tick_size * spec.tick_value_loss
        st.min_lot_risk_money = spec.volume_min * per_lot
        st.min_lot_risk_pct = st.min_lot_risk_money / p.balance * 100.0
        if st.min_lot_risk_pct > p.max_min_lot_risk_pct:
            self.res.counters["loại: lot tối thiểu vượt ngưỡng cứng (SL thật)"] += 1
            return None
        budget = p.balance * p.risk_per_trade_pct / 100.0
        lots = math.floor(budget / per_lot / spec.volume_step + 1e-9) * spec.volume_step if per_lot > 0 else 0.0
        lots = min(lots, math.floor(spec.volume_max / spec.volume_step + 1e-9) * spec.volume_step)
        st.risk_warn = lots < spec.volume_min - 1e-12
        st.lots = spec.volume_min if st.risk_warn else round(lots, 8)
        st.risk_money = st.lots * per_lot
        st.risk_pct = st.risk_money / p.balance * 100.0
        rr_part = min(st.rr1, 4.0) / 4.0
        conf_part = min(float(st.confluence), 4.0) / 4.0
        spread_part = max(0.0, 1.0 - spread_pct / max(p.max_spread_atr_pct, 0.01))
        st.quality = 40.0 * st.score / max(st.max_score, 1) + 30.0 * rr_part + 20.0 * conf_part + 10.0 * spread_part
        return st

    # ------------------------------------------------------------------ phân tích 1 symbol (ProcessSymbol)
    def _evaluate(self, sym: str, t: int) -> Optional[tuple]:
        ss = self.syms[sym]
        m, p = ss.model, self.p
        d = m.data
        h1 = d.tf["H1"]
        k1 = h1.last_closed(t)
        if k1 < 0 or h1.close_time[k1] != t:
            return None               # symbol không có nến H1 đóng đúng lúc này (nghỉ)
        idx = {tf: d.tf[tf].last_closed(t) for tf in TF_ORDER}
        c = self.res.counters
        if k1 + 1 < p.min_bars_h1 or idx["D1"] + 1 < p.min_bars_d1 or idx["H4"] + 1 < p.min_bars_h4:
            c["bỏ qua: thiếu lịch sử"] += 1
            return None
        self.res.evaluations += 1
        snaps = {tf: m.snapshot(tf, idx[tf]) for tf in TF_ORDER}
        atr_h1, atr_h4 = snaps["H1"].atr, snaps["H4"].atr
        if not atr_h1 or not atr_h4:
            c["bỏ qua: thiếu ATR"] += 1
            return None
        bid = h1.close[k1]
        spread = h1.spread[k1] * d.spec.point
        ask = bid + spread
        spread_pct = spread / atr_h1 * 100.0
        if spread_pct > p.max_spread_atr_pct:
            c["loại: spread rộng"] += 1
            return None
        min_risk = d.spec.volume_min * (p.feas_sl_atr_mult * atr_h4 / d.spec.tick_size) * d.spec.tick_value_loss
        if min_risk / p.balance * 100.0 > p.max_min_lot_risk_pct:
            c["loại: vượt khả năng vốn (lọc sớm)"] += 1
            return None
        allow = self._can_create(sym, t)
        h4 = d.tf["H4"]
        h4_close = h4.close_time[idx["H4"]]
        new_h4 = h4_close != ss.last_h4_seen
        res = analyze(m, idx, snaps, ss.tier, bid, ask, new_h4, allow)
        ss.last_h4_seen = h4_close
        if not allow:
            return None
        if not res.has_setup:
            c["không setup: " + _no_setup_reason(res.note)] += 1
            return None
        st = self._build(ss, res, spread_pct, t, h4_close)
        if st is None:
            return None
        return st, bid, ask, spread

    # ------------------------------------------------------------------ chạy
    def run(self, start: Optional[int] = None, end: Optional[int] = None) -> Result:
        times = sorted({ct for ss in self.syms.values() for ct in ss.model.data.tf["H1"].close_time})
        if start is not None:
            times = [x for x in times if x >= start]
        if end is not None:
            times = [x for x in times if x <= end]
        if not times:
            return self.res
        self.res.start, self.res.end = times[0], times[-1]
        order = sorted(self.syms, key=lambda s: (self.syms[s].tier, s))
        prev = times[0] - 3600
        any_offset = next(iter(self.syms.values())).model.data.spec.server_gmt_offset_sec
        for t in times:
            self._advance(prev, t)
            prev = t
            day = self._display_day(t, any_offset)
            if day != self.day_key:
                self.day_key, self.new_today = day, 0
            cands = []
            for sym in order:
                out = self._evaluate(sym, t)
                if out is None:
                    continue
                st, bid, ask, spread = out
                if st.tier == 0:
                    self._admit(st, bid, ask, spread, t)      # ưu tiên: báo ngay
                else:
                    cands.append(out)
            # cuối vòng: xếp hạng phụ/khám phá
            cands.sort(key=lambda o: -o[0].quality)
            sent = 0
            for st, bid, ask, spread in cands:
                if sent >= self.p.top_k:
                    self.res.counters["bỏ qua: ngoài top K"] += 1
                    continue
                if self.new_today >= self.p.max_new_per_day:
                    self.res.counters["bỏ qua: giới hạn tin/ngày"] += 1
                    continue
                if not self._can_create(st.sym, t):
                    continue
                if self._admit(st, bid, ask, spread, t):
                    sent += 1
                    self.new_today += 1
        self.res.open_at_end = len(self.journals)
        return self.res

    # ------------------------------------------------------------------ xuất CSV (định dạng journal_<login>.csv)
    def csv_lines(self) -> list[str]:
        header = ("id;symbol;tier;group;side;type;pending_risk;score;max_score;created;entry;sl;tp1;tp2;rr1;rr2;"
                  "spread;lot;risk_money;risk_pct;risk_warning;filled;fill_time;minutes_to_fill;outcome;r_a;r_b;r_c;"
                  "mfe_r;mae_r;hold_hours;close_time;money_a;note")
        lines = [header]
        for j in sorted(self.res.rows, key=lambda x: x.close_time):
            st = j.setup
            d = self.syms[st.sym].model.data
            off, dg = d.spec.server_gmt_offset_sec, d.spec.digits
            risk = abs(st.entry_ref - st.sl)
            filled = j.fill_time > 0
            r_c = 0.5 * (j.r_c1 + j.r_c2) if (j.r_c1 is not None and j.r_c2 is not None) else None

            def num(v, k=dg):
                return "" if v is None else f"{v:.{k}f}"
            vals = [st.id, st.sym, TIER_CODES[st.tier], GROUP_CODES[st.group], "buy" if st.side == SIDE_BUY else "sell",
                    "breakout" if st.type == BREAKOUT else "pullback", "1" if j.pending else "0", str(st.score),
                    str(st.max_score), self._fmt_time(st.created, off), num(st.entry_ref), num(st.sl), num(st.tp1),
                    num(st.tp2), num(st.rr1, 2), num(st.rr2, 2), num(j.spread), f"{st.lots:.2f}",
                    f"{st.risk_money:.2f}", f"{st.risk_pct:.2f}", "1" if st.risk_warn else "0",
                    "1" if filled else "0", self._fmt_time(j.fill_time, off),
                    str((j.fill_time - st.created) // 60) if filled else "", j.outcome, num(j.r_a, 2), num(j.r_b, 2),
                    num(r_c, 2), f"{j.mfe / risk:.2f}" if filled else "", f"{j.mae / risk:.2f}" if filled else "",
                    f"{(j.close_time - j.fill_time) / 3600:.1f}" if filled else "", self._fmt_time(j.close_time, off),
                    f"{j.r_a * st.risk_money:.2f}" if j.r_a is not None else "", j.note.replace(";", ",")]
            lines.append(";".join(vals))
        return lines

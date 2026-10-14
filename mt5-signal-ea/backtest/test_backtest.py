"""Kiểm thử bộ backtest: python -m unittest -v test_backtest.py"""
import math
import random
import tempfile
import unittest
from pathlib import Path

import bt_engine as E
from bt_data import Series, Spec, SymbolData, TF_ORDER, load_symbol
from bt_indicators import TfIndicators, swing_flags
from bt_strategy import Params, SymbolModel, tf_bias, Snapshot, targets, stop_loss


def make_series(tf, closes, start=0, step=3600, spread=10):
    s = Series(tf=tf)
    prev = closes[0]
    for i, c in enumerate(closes):
        s.time.append(start + i * step)
        s.open.append(prev)
        s.high.append(max(prev, c) + 0.5)
        s.low.append(min(prev, c) - 0.5)
        s.close.append(c)
        s.spread.append(spread)
        prev = c
    s.finalize()
    return s


def rnd_closes(n, seed=1, start=100.0):
    r = random.Random(seed)
    out, p = [], start
    for _ in range(n):
        p += r.gauss(0, 1)
        out.append(p)
    return out


class IndicatorTest(unittest.TestCase):
    def setUp(self):
        self.s = make_series("H1", rnd_closes(500))
        self.ind = TfIndicators(self.s, 320)

    def test_sma_bands_atr_match_naive(self):
        c, k = self.s.close, 450
        self.assertAlmostEqual(self.ind.sma(k, 20), sum(c[k - 19:k + 1]) / 20, places=9)
        up, mid, lo = self.ind.bands(k, 20, 2.0)
        m = sum(c[k - 19:k + 1]) / 20
        sd = math.sqrt(sum((x - m) ** 2 for x in c[k - 19:k + 1]) / 20)
        self.assertAlmostEqual(up, m + 2 * sd, places=7)
        self.assertAlmostEqual(lo, m - 2 * sd, places=7)
        tr = [max(self.s.high[i], c[i - 1]) - min(self.s.low[i], c[i - 1]) for i in range(k - 13, k + 1)]
        self.assertAlmostEqual(self.ind.atr(k, 14), sum(tr) / 14, places=9)

    def test_rsi_matches_window_version(self):
        # EA tính RSI trên ~320 nến: sai khác so với toàn bộ lịch sử phải rất nhỏ
        c, k, p = self.s.close, 480, 14
        win = c[k - 318:k + 1]
        pos = sum(max(win[i] - win[i - 1], 0) for i in range(1, p + 1)) / p
        neg = sum(max(win[i - 1] - win[i], 0) for i in range(1, p + 1)) / p
        for i in range(p + 1, len(win)):
            d = win[i] - win[i - 1]
            pos = (pos * (p - 1) + max(d, 0)) / p
            neg = (neg * (p - 1) + max(-d, 0)) / p
        self.assertAlmostEqual(self.ind.rsi(k, p), 100 - 100 / (1 + pos / neg), places=4)

    def test_window_limits_like_ea(self):
        self.assertIsNone(self.ind.sma(150, 200))       # chưa đủ 200 nến
        self.assertIsNotNone(self.ind.sma(450, 200))
        self.assertIsNone(self.ind.sma(10, 20))


class SwingTest(unittest.TestCase):
    def test_matches_ea_loop(self):
        s = make_series("H1", rnd_closes(400, seed=7))
        p = Params()
        model = SymbolModel(SymbolData(spec=Spec("X"), tf={tf: s for tf in TF_ORDER}), p)
        for k in (200, 333, 398):
            for highs in (True, False):
                got = model.swings("H1", k, 3, highs, 1)
                # chép nguyên vòng lặp AnaSwings trên mảng series (r[0] = nến đang chạy)
                n = min(k + 2, p.bars_window)
                r = lambda i: (s.high if highs else s.low)[k + 1 - i]  # noqa: E731
                want = []
                for i in range(max(4, 1), min(p.swing_lookback, n - 3 - 1) + 1):
                    v = r(i)
                    ok = all((v > r(i + m) and v >= r(i - m)) if highs else (v < r(i + m) and v <= r(i - m))
                             for m in range(1, 4))
                    if ok:
                        want.append(v)
                self.assertEqual(got, want)


class StrategyTest(unittest.TestCase):
    def test_bias_three_of_four(self):
        s = Snapshot(bars=100, close=110, sma_base=100, sma_mid=105, sma_base_prev=99, rsi=45)
        self.assertEqual(tf_bias(s, 3), 1)          # 3 điều kiện tăng
        s.rsi, s.sma_base_prev = 45, 101
        self.assertEqual(tf_bias(s, 3), 0)          # còn 2/4
        self.assertEqual(tf_bias(Snapshot(bars=100, close=90, sma_base=100, sma_mid=95, sma_base_prev=101, rsi=40), 3), -1)

    def test_targets_and_sl(self):
        p = Params()
        tp1, tp2 = targets(-1, 100.0, [95.0, 99.9, 90.0], [94.9], 2.0, p)
        self.assertEqual((tp1, tp2), (95.0, 90.0))   # 99.9 quá gần, 94.9 trùng TP1 (< 0.25 ATR)
        sl = stop_loss(-1, 101.0, 101.6, [102.0, 103.0], [], 2.0, p)
        self.assertAlmostEqual(sl, 102.0 + 0.25 * 2.0)


def bare_backtest(p=None):
    bt = E.Backtest.__new__(E.Backtest)
    bt.p = p or Params()
    bt.res = E.Result()
    bt.setups, bt.journals = [], []
    bt.syms = {}
    return bt


def setup(side=-1, entry=100.0, sl=102.0, tp1=97.0, tp2=94.0, **kw):
    risk = abs(entry - sl)
    st = E.Setup(id="T", sym="X", tier=0, group=1, corr="", base_ccy="", quote_ccy="", side=side, type=0, score=6,
                 max_score=9, confluence=2, entry_low=entry - 0.3, entry_high=entry + 0.3, entry_ref=entry, sl=sl,
                 tp1=tp1, tp2=tp2, rr1=abs(tp1 - entry) / risk, rr2=abs(tp2 - entry) / risk if tp2 else None,
                 spread_pct=1.0, reasons="", bias_text="", created=0, expires=10 ** 9, last_h4_close=0)
    for k, v in kw.items():
        setattr(st, k, v)
    return st


def bars(rows):
    s = Series(tf="M1")
    for i, (h, lo, c) in enumerate(rows):
        s.time.append(i * 60)
        s.open.append(c)
        s.high.append(h)
        s.low.append(lo)
        s.close.append(c)
        s.spread.append(0)
    s.finalize()
    return s


class JournalTest(unittest.TestCase):
    def run_journal(self, rows, **kw):
        bt = bare_backtest()
        j = E.Journal(setup=setup(**kw), pending=False, spread=0.0)
        s = bars(rows)
        for i in range(len(s)):
            if j.phase == E.J_CLOSED:
                break
            bt._journal_bar(j, s, i)
        return j

    def test_sell_sl_first(self):
        j = self.run_journal([(100.1, 99.5, 99.8), (102.5, 99.0, 101)])   # khớp, rồi chạm SL
        self.assertEqual((j.outcome, j.r_a, j.r_b), ("SL", -1.0, -1.0))

    def test_same_bar_sl_and_tp_counts_sl(self):
        j = self.run_journal([(100.1, 99.5, 99.8), (102.5, 96.0, 97)])
        self.assertEqual(j.outcome, "SL")

    def test_tp1_then_breakeven(self):
        rows = [(100.1, 99.5, 99.8), (99.0, 96.5, 97), (100.5, 98.0, 100.2)]
        j = self.run_journal(rows)
        # chạm TP1, về hòa vốn: A xong, C xong (nửa sau = 0), B vẫn chờ TP2/SL -> kèo chưa đóng
        self.assertEqual(j.phase, E.J_TRADE)
        self.assertAlmostEqual(j.r_a, 1.5)          # (100-97)/2
        self.assertEqual(j.r_c2, 0.0)
        self.assertIsNone(j.r_b)
        j = self.run_journal(rows + [(102.5, 100.0, 102.2)])
        self.assertEqual(j.outcome, "TP1_SL")
        self.assertEqual(j.r_b, -1.0)
        self.assertAlmostEqual(0.5 * (j.r_c1 + j.r_c2), 0.75)

    def test_tp2_all(self):
        j = self.run_journal([(100.1, 99.5, 99.8), (99.0, 96.5, 97), (97.0, 93.5, 94)])
        self.assertEqual(j.outcome, "TP2")
        self.assertAlmostEqual(j.r_b, 3.0)
        self.assertAlmostEqual(0.5 * (j.r_c1 + j.r_c2), 2.25)

    def test_fill_bar_sl_and_mfe_skip(self):
        j = self.run_journal([(102.5, 95.0, 99)])
        self.assertEqual(j.outcome, "SL")
        self.assertEqual(j.mfe, 0.0)                # nến khớp không tính MFE

    def test_buy_side(self):
        j = self.run_journal([(100.5, 99.9, 100.2), (103.5, 100.1, 103.2)], side=1, entry=100.0, sl=98.0,
                             tp1=103.0, tp2=106.0)
        self.assertAlmostEqual(j.r_a, 1.5)


class GatingTest(unittest.TestCase):
    def test_secondary_blocked_by_priority_in_group(self):
        bt = bare_backtest()
        bt.setups = [setup(tier=0, corr="KIM_LOAI", sym="XAUUSD")]
        ok, why, _ = bt._correlation_ok(setup(tier=1, corr="KIM_LOAI", sym="XAGUSD"))
        self.assertFalse(ok)

    def test_priority_yields_opposite_discovery(self):
        bt = bare_backtest()
        other = setup(tier=2, corr="CRYPTO", sym="ETHUSD", side=1)
        bt.setups = [other]
        ok, _, yields = bt._correlation_ok(setup(tier=0, corr="CRYPTO", sym="BTCUSD", side=-1))
        self.assertTrue(ok)
        self.assertEqual(yields, [other])

    def test_currency_exposure(self):
        bt = bare_backtest()
        mk = lambda sym, b, q, side: setup(sym=sym, group=0, base_ccy=b, quote_ccy=q, side=side)  # noqa: E731
        bt.setups = [mk("EURUSD", "EUR", "USD", 1), mk("GBPUSD", "GBP", "USD", 1)]   # 2 lần bán USD
        self.assertFalse(bt._exposure_ok(mk("AUDUSD", "AUD", "USD", 1)))
        self.assertTrue(bt._exposure_ok(mk("USDJPY", "USD", "JPY", 1)))


class EndToEndTest(unittest.TestCase):
    def test_run_on_synthetic_h1(self):
        tmp = Path(tempfile.mkdtemp())
        closes = rnd_closes(24 * 200, seed=3, start=2000)
        h1 = make_series("H1", closes)
        def agg(step):
            s = Series(tf="X")
            for i in range(0, len(closes), step // 3600):
                chunk = range(i, min(i + step // 3600, len(closes)))
                s.time.append(h1.time[i]); s.open.append(h1.open[i])
                s.high.append(max(h1.high[j] for j in chunk)); s.low.append(min(h1.low[j] for j in chunk))
                s.close.append(h1.close[chunk[-1]]); s.spread.append(10)
            return s
        for tf, step in (("H1", 3600), ("H4", 14400), ("D1", 86400), ("W1", 7 * 86400), ("MN1", 30 * 86400)):
            s = h1 if tf == "H1" else agg(step)
            with (tmp / f"XAUUSD_{tf}.csv").open("w") as fh:
                fh.write("time;open;high;low;close;spread\n")
                for i in range(len(s.time)):
                    fh.write(f"{s.time[i]};{s.open[i]};{s.high[i]};{s.low[i]};{s.close[i]};{s.spread[i]}\n")
        (tmp / "XAUUSD_spec.csv").write_text("key;value\ndigits;2\npoint;0.01\ntick_size;0.01\ntick_value_loss;1\n"
                                            "contract_size;100\nvolume_min;0.01\nvolume_step;0.01\nvolume_max;100\n"
                                            "currency_base;XAU\ncurrency_profit;USD\npath;Metals\\XAUUSD\n")
        p = Params(min_bars_d1=60, min_bars_h1=300, min_bars_h4=100, max_min_lot_risk_pct=50, balance=10000)
        bt = E.Backtest([load_symbol(tmp, "XAUUSD")], p, use_m1=False)
        res = bt.run()
        self.assertGreater(res.evaluations, 1000)
        lines = bt.csv_lines()
        self.assertEqual(len(lines) - 1, len(res.rows))
        for j in res.rows:
            if j.fill_time:
                self.assertNotIn(None, (j.r_a, j.r_b, j.r_c1, j.r_c2))
                self.assertGreaterEqual(j.r_a, -1.0 - 1e-9)
            else:
                self.assertEqual(j.outcome, "NOT_FILLED")


if __name__ == "__main__":
    unittest.main()

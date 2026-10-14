"""Chỉ báo tính trước trên toàn bộ chuỗi (cùng công thức Indicators.mqh của EA).

- SMA: trung bình cộng close
- BB : SMA +/- dev x độ lệch chuẩn tổng thể (chia cho period)
- RSI: làm trơn Wilder, khởi tạo bằng trung bình period thay đổi đầu tiên
       (EA tính trên ~320 nến; sai khác hội tụ về 0 sau vài trăm nến)
- ATR: trung bình cộng (SMA) của True Range
Mọi hàm trả giá trị tại chỉ số nến đã đóng k (tăng dần theo thời gian), None nếu thiếu dữ liệu.
"""
from __future__ import annotations

import math
from typing import Optional

from bt_data import Series


class TfIndicators:
    def __init__(self, s: Series, bars_window: int = 320):
        self.s = s
        self.n = len(s)
        self.window = bars_window          # EA chỉ tải tối đa ~320 nến/khung
        c = s.close
        self._ps = [0.0]
        self._ps2 = [0.0]
        for v in c:
            self._ps.append(self._ps[-1] + v)
            self._ps2.append(self._ps2[-1] + v * v)
        tr = [0.0] * self.n
        for i in range(1, self.n):
            tr[i] = max(s.high[i], c[i - 1]) - min(s.low[i], c[i - 1])
        self._tr_ps = [0.0]
        for v in tr:
            self._tr_ps.append(self._tr_ps[-1] + v)
        self._rsi_cache: dict[int, list[Optional[float]]] = {}

    def _avail(self, k: int) -> int:
        """Số nến đã đóng EA nhìn thấy tại k (giới hạn bởi cửa sổ tải)."""
        return min(k + 1, self.window - 1)

    def sma(self, k: int, period: int) -> Optional[float]:
        if k < 0 or period <= 0 or period > self._avail(k):
            return None
        return (self._ps[k + 1] - self._ps[k + 1 - period]) / period

    def bands(self, k: int, period: int, dev: float) -> tuple[Optional[float], Optional[float], Optional[float]]:
        ma = self.sma(k, period)
        if ma is None:
            return None, None, None
        sq = self._ps2[k + 1] - self._ps2[k + 1 - period]
        var = max(sq / period - ma * ma, 0.0)
        sd = math.sqrt(var)
        return ma + dev * sd, ma, ma - dev * sd

    def atr(self, k: int, period: int) -> Optional[float]:
        # cần thêm 1 nến trước để có close trước đó
        if k < 0 or period <= 0 or period + 1 > self._avail(k) or k - period + 1 < 1:
            return None
        return (self._tr_ps[k + 1] - self._tr_ps[k + 1 - period]) / period

    def _rsi_series(self, period: int) -> list[Optional[float]]:
        if period in self._rsi_cache:
            return self._rsi_cache[period]
        c = self.s.close
        out: list[Optional[float]] = [None] * self.n
        if self.n > period:
            pos = neg = 0.0
            for i in range(1, period + 1):
                d = c[i] - c[i - 1]
                if d > 0:
                    pos += d
                else:
                    neg -= d
            pos /= period
            neg /= period
            out[period] = _rsi(pos, neg)
            for i in range(period + 1, self.n):
                d = c[i] - c[i - 1]
                pos = (pos * (period - 1) + (d if d > 0 else 0.0)) / period
                neg = (neg * (period - 1) + (-d if d < 0 else 0.0)) / period
                out[i] = _rsi(pos, neg)
        self._rsi_cache[period] = out
        return out

    def rsi(self, k: int, period: int) -> Optional[float]:
        if k < 0 or self._avail(k) < period + 1:
            return None
        return self._rsi_series(period)[k]


def _rsi(pos: float, neg: float) -> float:
    if neg != 0.0:
        return 100.0 - 100.0 / (1.0 + pos / neg)
    return 100.0 if pos != 0.0 else 50.0


def swing_flags(s: Series, strength: int, highs: bool) -> list[bool]:
    """Fractal như AnaSwings: cao hơn hẳn `strength` nến cũ hơn, >= `strength` nến mới hơn."""
    n = len(s)
    vals = s.high if highs else s.low
    flags = [False] * n
    for j in range(strength, n - strength):
        v = vals[j]
        ok = True
        for m in range(1, strength + 1):
            older, newer = vals[j - m], vals[j + m]
            if highs:
                if not (v > older and v >= newer):
                    ok = False
                    break
            else:
                if not (v < older and v <= newer):
                    ok = False
                    break
        flags[j] = ok
    return flags

"""Nạp dữ liệu lịch sử do Scripts/ExportHistory.mq5 xuất ra.

<SYM>_<TF>.csv : time;open;high;low;close;spread   (time = giây Unix theo giờ server, spread = point)
<SYM>_spec.csv : key;value
"""
from __future__ import annotations

import bisect
import calendar
import csv
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional

TF_SECONDS = {"M1": 60, "H1": 3600, "H4": 14400, "D1": 86400, "W1": 7 * 86400}
TF_ORDER = ["MN1", "W1", "D1", "H4", "H1"]   # cùng thứ tự TFI_* của EA


@dataclass
class Series:
    tf: str
    time: list[int] = field(default_factory=list)       # giờ mở nến
    open: list[float] = field(default_factory=list)
    high: list[float] = field(default_factory=list)
    low: list[float] = field(default_factory=list)
    close: list[float] = field(default_factory=list)
    spread: list[int] = field(default_factory=list)
    close_time: list[int] = field(default_factory=list)  # giờ đóng nến

    def __len__(self) -> int:
        return len(self.time)

    def finalize(self) -> None:
        if self.tf == "MN1":
            self.close_time = [_next_month(t) for t in self.time]
        else:
            sec = TF_SECONDS[self.tf]
            self.close_time = [t + sec for t in self.time]

    def last_closed(self, t: int) -> int:
        """Chỉ số nến đã đóng gần nhất tại thời điểm t (đóng <= t), -1 nếu chưa có."""
        return bisect.bisect_right(self.close_time, t) - 1

    def first_open_at_or_after(self, t: int) -> int:
        return bisect.bisect_left(self.time, t)


def _next_month(t: int) -> int:
    d = datetime.fromtimestamp(t, tz=timezone.utc)
    y, m = (d.year + 1, 1) if d.month == 12 else (d.year, d.month + 1)
    return calendar.timegm((y, m, 1, 0, 0, 0))


@dataclass
class Spec:
    symbol: str
    digits: int = 5
    point: float = 0.00001
    tick_size: float = 0.00001
    tick_value_loss: float = 1.0
    contract_size: float = 100000.0
    volume_min: float = 0.01
    volume_step: float = 0.01
    volume_max: float = 100.0
    currency_base: str = ""
    currency_profit: str = ""
    path: str = ""
    calc_mode: str = ""
    account_currency: str = "USD"
    server_gmt_offset_sec: int = 0

    def validate(self) -> Optional[str]:
        if self.tick_size <= 0 or self.tick_value_loss <= 0:
            return "tick size/value bất thường"
        if self.volume_min <= 0 or self.volume_step <= 0 or self.volume_max < self.volume_min:
            return "volume min/step/max bất thường"
        return None


@dataclass
class SymbolData:
    spec: Spec
    tf: dict[str, Series]
    m1: Optional[Series] = None

    @property
    def name(self) -> str:
        return self.spec.symbol


def read_series(path: Path, tf: str) -> Series:
    s = Series(tf=tf)
    with path.open(encoding="utf-8-sig", newline="") as fh:
        reader = csv.reader(fh, delimiter=";")
        header = next(reader, None)
        if not header or header[0].strip().lower() != "time":
            raise ValueError(f"{path.name}: thiếu dòng tiêu đề time;open;high;low;close;spread")
        last = None
        for row in reader:
            if len(row) < 5:
                continue
            t = int(row[0])
            if last is not None and t <= last:
                continue   # bỏ dòng trùng/lộn thứ tự
            last = t
            s.time.append(t)
            s.open.append(float(row[1]))
            s.high.append(float(row[2]))
            s.low.append(float(row[3]))
            s.close.append(float(row[4]))
            s.spread.append(int(row[5]) if len(row) > 5 and row[5] else 0)
    s.finalize()
    return s


def read_spec(path: Path, symbol: str) -> Spec:
    spec = Spec(symbol=symbol)
    if not path.exists():
        return spec
    with path.open(encoding="utf-8-sig", newline="") as fh:
        for row in csv.reader(fh, delimiter=";"):
            if len(row) < 2 or row[0] == "key":
                continue
            key, val = row[0].strip(), row[1].strip()
            if not hasattr(spec, key) or key == "symbol":
                continue
            cur = getattr(spec, key)
            try:
                setattr(spec, key, type(cur)(float(val)) if isinstance(cur, (int, float)) else val)
            except ValueError:
                pass
    if spec.tick_value_loss <= 0:
        # một số broker chỉ có tick_value
        spec.tick_value_loss = spec.tick_value_loss or 0.0
    return spec


def load_symbol(data_dir: Path, symbol: str) -> SymbolData:
    tfs: dict[str, Series] = {}
    for tf in TF_ORDER:
        p = data_dir / f"{symbol}_{tf}.csv"
        tfs[tf] = read_series(p, tf) if p.exists() else Series(tf=tf)
    m1_path = data_dir / f"{symbol}_M1.csv"
    m1 = read_series(m1_path, "M1") if m1_path.exists() else None
    return SymbolData(spec=read_spec(data_dir / f"{symbol}_spec.csv", symbol), tf=tfs, m1=m1)


def discover_symbols(data_dir: Path) -> list[str]:
    return sorted(p.name[: -len("_H1.csv")] for p in data_dir.glob("*_H1.csv"))

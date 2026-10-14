# SignalEA: EA báo tín hiệu qua Telegram cho MetaTrader 5

> **EA chỉ báo tín hiệu. Tuyệt đối không đặt, sửa hay đóng lệnh.** Mã nguồn không gọi `OrderSend`, `CTrade` hay bất kỳ hàm giao dịch nào, và không dùng DLL.
> Tín hiệu chỉ để tham khảo, không phải lời khuyên đầu tư.

Phiên bản hiện tại: **0.1.0, Giai đoạn 1** (khung EA, khám phá/lọc symbol, đọc chỉ báo, DryRun, self-test).

---

## 1. Kế hoạch tổng thể

### Các giai đoạn

| GĐ | Nội dung | Trạng thái |
|---|---|---|
| 1 | Khung EA (`OnInit/OnTimer/OnDeinit`), khám phá + phân loại + lọc symbol, quét xoay vòng, tính SMA/BB/RSI/ATR từ `CopyRates`, DryRun, bảng trạng thái, self-test đối chiếu `iMA/iBands/iRSI/iATR` + bảng tick value | **Đã giao** |
| 2 | Chấm điểm bias đa khung, tìm vùng Entry (confluence), setup chờ hồi/phá vỡ, SL/TP/RR, hủy kèo, hai tầng ngưỡng, nhóm tương quan, phơi nhiễm tiền tệ, xếp hạng top K, cảnh báo tin tức | Chưa làm |
| 3 | Quản lý vốn đầy đủ: lot gợi ý theo SL thật, `CẢNH BÁO RỦI RO`, tổng rủi ro các setup đang mở, trạng thái "vượt ngưỡng rủi ro" | Chưa làm (GĐ1 đã có hàm tính lot/rủi ro) |
| 4 | Telegram thật (`WebRequest`, hàng đợi, retry, rate limit, tin tổng hợp + chi tiết), lưu trạng thái setup ra file, chống báo trùng khi khởi động lại, giới hạn tin/ngày, tóm tắt cuối ngày | Chưa làm (GĐ1 đã có tách tin + DryRun) |
| 5 | Đọc vùng vẽ tay (`OBJ_RECTANGLE`, `OBJ_TREND`) trên mọi chart đang mở | Chưa làm |
| 6 | Hoàn thiện README/TESTING, đối chiếu nghiệm thu | Một phần (tài liệu GĐ1) |

### Module

```
mt5-signal-ea/
  SignalEA.mq5             File chính: input, OnInit/OnTimer/OnDeinit, pipeline xử lý 1 symbol, bảng trạng thái
  Include/Common.mqh       Enum, log, tiện ích chuỗi/thời gian (thêm so với đề bài, dùng chung)
  Include/Universe.mqh     Khám phá, phân loại, lọc symbol, quản lý Market Watch, quét xoay vòng
  Include/Indicators.mqh   SMA/BB/RSI/ATR tự tính từ CopyRates + cache handle (tùy chọn) cho ưu tiên/phụ
  Include/Risk.mqh         Thông số hợp đồng, rủi ro ở lot X, lot gợi ý theo % rủi ro
  Include/Telegram.mqh     Tách tin theo giới hạn ký tự, DryRun (GĐ4: WebRequest, hàng đợi, retry)
  Include/SelfTest.mqh     Đối chiếu chỉ báo tự tính với iMA/iBands/iRSI/iATR + bảng tick value (thêm)
  Include/Analysis.mqh     (GĐ2) chấm điểm bias, tìm vùng, SL/TP
  Include/State.mqh        (GĐ4) lưu/đọc trạng thái
  README.md, TESTING.md
```

### Luồng dữ liệu

```
OnTimer (30s)
 ├─ (mỗi 6h) UniBuild: SymbolsTotal/SymbolName → lọc hậu tố, nhóm, trade mode → g_uni[] + log nhận/loại + universe.csv
 ├─ Giờ server mới? → mọi symbol thành "đến hạn"
 └─ RunScanCycle: ưu tiên/phụ trước, rồi xoay vòng nhóm khám phá; tối đa N symbol nặng/chu kỳ + ngân sách ms
      ProcessSymbol(sym):
        phiên giao dịch → Market Watch → báo giá mới → spec hợp đồng
        → CopyRates H1 (có nến H1 mới đóng?) → D1, H4 (bắt buộc) → W1, MN1 (tùy chọn)
        → snapshot SMA/BB/RSI/ATR 5 khung (shift 1 = nến đã đóng)
        → lọc spread ≤ 15% ATR(H1) → lọc vốn (lot tối thiểu ≤ 4% số dư)
        → [GĐ2] bias + setup → [GĐ3] rủi ro → [GĐ4] Telegram + lưu trạng thái
        → gỡ symbol khám phá khỏi Market Watch (nếu EA đã thêm)
```

---

## 2. Giả định và mặc định đã chọn

1. **Phân loại nhóm**: dựa vào từ khóa trong `SYMBOL_PATH` (crypto, metal, energ/oil, indic/index, stock/share/equit, forex/currenc/major/minor/exotic). Nếu không nhận ra thì dựa vào tiền tệ cơ sở (XAU/XAG/XPT/XPD → Kim loại; BTC/ETH/... → Crypto), tên (OIL/BRENT/WTI/XNG → Năng lượng) và `SYMBOL_TRADE_CALC_MODE`. Không nhận ra được thì xếp vào nhóm "Khác" (mặc định tắt). File `MQL5/Files/SignalEA/universe.csv` ghi nhóm của từng symbol để bạn kiểm tra.
2. **Hậu tố**: `InpSymbolSuffix` để trống (Exness Pro). Khi để trống, EA loại các symbol kết thúc bằng hậu tố của loại tài khoản khác (`InpForeignSuffixes = "m,c"`, ví dụ `XAUUSDm`, `XAUUSDc`), với điều kiện phần còn lại viết hoa toàn bộ. Khi có hậu tố, EA chỉ nhận symbol kết thúc đúng hậu tố đó. Danh sách ưu tiên/phụ tự được thêm hậu tố.
3. **Danh sách ưu tiên/phụ** luôn được đưa vào, kể cả khi nhóm tài sản của chúng đang tắt, nhưng vẫn phải qua các bộ lọc (phiên, spread, lịch sử, vốn).
4. **Trade mode**: chỉ nhận `SYMBOL_TRADE_MODE_FULL`.
5. **Phiên giao dịch**: dùng `SymbolInfoSessionTrade` theo giờ server. Nếu báo giá cũ hơn `InpMaxQuoteAgeMin` (mặc định 60 phút) thì coi như nghỉ lễ.
6. **Market Watch**: symbol khám phá chưa có trong Market Watch được EA thêm vào (để có báo giá/tick value) khi số symbol đang hiển thị < `InpMaxMarketWatch` (60), rồi gỡ ra sau khi quét (`InpReleaseSymbolsAfterScan`). Symbol bạn tự thêm thì EA không gỡ. Khi bạn đã có > 60 symbol trong Market Watch, EA cảnh báo mỗi giờ.
7. **Lọc vốn ở GĐ1** dùng **SL giả định = 1.0 × ATR(H4)** (`InpFeasSlAtrMult`) vì chưa có SL thật. Từ GĐ2, rủi ro được tính lại theo SL thật của setup.
8. **Nhịp phân tích**: mỗi symbol được phân tích tối đa 1 lần/giờ server, ngay sau khi nến H1 đóng và đã có tick của giờ mới. Với khoảng 200 symbol, N = 5 và timer 30s, một vòng quét hết khoảng 20 phút. Ưu tiên/phụ luôn xử lý trước, thường trong chu kỳ đầu tiên của giờ. (GĐ2 sẽ thêm kiểm tra giá vào vùng Entry mỗi chu kỳ cho các setup đang hoạt động, rất nhẹ vì chỉ đọc bid/ask.)
9. **Chỉ báo**: tự tính từ `CopyRates` cho mọi symbol, cùng công thức với chỉ báo chuẩn MT5: BB dùng độ lệch chuẩn tổng thể, RSI làm trơn Wilder, ATR là SMA của True Range. Handle `iMA/iBands/iRSI/iATR` cho ưu tiên/phụ là tùy chọn (`InpUseHandlesForWatchlist`, mặc định tắt để tiết kiệm RAM; nếu bật thì cần 35 handle cho mỗi symbol và chúng được giải phóng ở `OnDeinit`).
10. **MN1/W1 thiếu dữ liệu** (ví dụ thiếu nến cho SMA200): giá trị là `EMPTY_VALUE`, hiển thị `n/a`, không báo lỗi.
11. **Múi giờ hiển thị**: GMT+7. Độ lệch giờ server được tính bằng `TimeTradeServer() - TimeGMT()` và làm tròn tới 15 phút.
12. **Mã hóa file**: các file nguồn là UTF-8 có BOM để MetaEditor đọc đúng chuỗi tiếng Việt.

---

## 3. Cài đặt

1. Trong MT5: **File → Open Data Folder**. Chép **cả thư mục** `mt5-signal-ea` vào `MQL5/Experts/`, để được `MQL5/Experts/mt5-signal-ea/SignalEA.mq5` và `MQL5/Experts/mt5-signal-ea/Include/*.mqh`.
2. Mở `SignalEA.mq5` trong MetaEditor rồi bấm **Compile** (F7). Hoặc biên dịch bằng dòng lệnh:
   ```
   "C:\Program Files\MetaTrader 5\metaeditor64.exe" /compile:"MQL5\Experts\mt5-signal-ea\SignalEA.mq5" /log
   ```
   Kết quả nằm trong file `SignalEA.log` cạnh file nguồn.
3. Kéo `SignalEA` lên **một chart bất kỳ** (ví dụ XAUUSD H1). EA tự quét các symbol khác, không phụ thuộc symbol của chart.
4. Tab **Common**: không cần bật "Algo Trading" để EA chạy timer, nhưng nên bật để EA không bị chặn. EA không đặt lệnh.
5. Xem log trong tab **Experts** (Toolbox → Experts).

### Tối ưu cho VPS Exness cấu hình thấp
- Ẩn bớt symbol trong Market Watch (chuột phải → **Hide All**, rồi chỉ thêm những symbol bạn cần).
- **Tools → Options → Charts → Max bars in chart**: 5000–10000 là đủ, vì EA chỉ cần khoảng 320 nến mỗi khung.
- Đóng các chart không dùng.

---

## 4. Telegram (dùng thật từ Giai đoạn 4)

> ⚠️ **BẢO MẬT TOKEN**: Bot token cho phép bất kỳ ai điều khiển bot của bạn. **Không chia sẻ** token, không chụp màn hình phần input, không commit token lên Git. EA không hard-code token; bạn nhập token qua input của EA.

### Tạo bot
1. Trên Telegram, mở **@BotFather** → gửi `/newbot` → đặt tên → nhận **token** dạng `123456789:AA...`.
2. Mở chat với bot vừa tạo và bấm **Start** (bot chỉ gửi được tin cho người đã nhắn với nó trước).

### Lấy chat id
- Cách 1: nhắn một tin bất kỳ cho bot, rồi mở trên trình duyệt `https://api.telegram.org/bot<TOKEN>/getUpdates` và tìm `"chat":{"id":...}`.
- Cách 2: nhắn cho **@userinfobot** để lấy id của bạn.
- Nếu muốn gửi vào group: thêm bot vào group, nhắn một tin trong group, rồi dùng `getUpdates`. Id của group là số âm, ví dụ `-100...`.

### Cho phép WebRequest
**Tools → Options → Expert Advisors → Allow WebRequest for listed URL** → thêm `https://api.telegram.org`.
Nếu chưa làm bước này, EA sẽ báo lỗi 4060 và in lại hướng dẫn này trong log (từ GĐ4).

---

## 5. Tham số (input)

| Nhóm | Input | Mặc định | Ý nghĩa |
|---|---|---|---|
| Chung | `InpDryRun` | true | Chỉ in nội dung tin ra log, không gọi Telegram |
| | `InpLogLevel` | INFO | DEBUG để xem chi tiết từng symbol |
| | `InpTimerSeconds` | 30 | Chu kỳ OnTimer |
| | `InpDisplayGmtOffset` | 7 | Múi giờ hiển thị |
| | `InpShowPanel` | true | Bảng trạng thái (Comment) trên chart |
| Telegram | `InpTgEnabled`, `InpTgToken`, `InpTgChatId` | tắt / trống | Dùng từ GĐ4 |
| | `InpTgMaxChars` | 3800 | Tin dài hơn được tự tách (Telegram giới hạn 4096) |
| Symbol | `InpPrioritySymbols` | BTCUSD,XAUUSD | Danh sách ưu tiên |
| | `InpSecondarySymbols` | ETHUSD,XAGUSD | Danh sách phụ |
| | `InpSymbolSuffix` | (trống) | Hậu tố symbol |
| | `InpForeignSuffixes` | m,c | Hậu tố của loại tài khoản khác cần loại khi hậu tố trống |
| | `InpUniverseMode` | ALL_BROKER_SYMBOLS | WATCHLIST_ONLY / MARKET_WATCH / ALL_BROKER_SYMBOLS |
| | `InpExcludeSymbols` | (trống) | Loại trừ thủ công |
| | `InpEnable*` | Forex, Kim loại, Crypto, Chỉ số, Năng lượng bật; Cổ phiếu, Khác tắt | Bật/tắt nhóm |
| Bộ lọc | `InpMaxSpreadAtrPct` | 15 | Spread tối đa tính theo % ATR(H1) |
| | `InpMinBarsD1/H1/H4` | 250/300/100 | Số nến tối thiểu |
| | `InpMaxQuoteAgeMin` | 60 | Báo giá cũ hơn mức này thì coi như nghỉ |
| | `InpMaxDeferPerHour` | 3 | Số lần chờ dữ liệu tối đa mỗi giờ, quá thì bỏ qua giờ đó |
| | `InpMaxMinLotRiskPct` | 4 | Ngưỡng cứng: rủi ro ở lot tối thiểu vượt mức này thì loại |
| | `InpFeasSlAtrMult` | 1.0 | SL giả định khi lọc vốn (× ATR H4) |
| Hiệu năng | `InpSymbolsPerCycle` | 5 | N symbol phân tích mỗi chu kỳ |
| | `InpCycleBudgetMs` | 2000 | Hết ngân sách thời gian thì dừng chu kỳ |
| | `InpMaxMarketWatch` | 60 | Giới hạn số symbol trong Market Watch |
| | `InpReleaseSymbolsAfterScan` | true | Gỡ symbol khám phá khỏi Market Watch sau khi quét |
| | `InpUniverseRefreshHours` | 6 | Dựng lại danh sách symbol |
| | `InpBarsToLoad` | 320 | Số nến tải mỗi khung (tự tăng nếu cần, không vượt `TERMINAL_MAXBARS`) |
| Chỉ báo | `InpSma*`, `InpBb*`, `InpRsiPeriod`, `InpAtrPeriod` | 10/20/50/200, 20/2.0, 14, 14 | |
| | `InpSlopeBars` | 3 | Độ dốc SMA20 = SMA20[1] so với SMA20[1+3] |
| | `InpUseHandlesForWatchlist` | false | Dùng handle chuẩn cho ưu tiên/phụ |
| Vốn | `InpRiskPerTradePct` | 1.5 | % rủi ro mỗi setup |
| | `InpMaxTotalRiskPct` | 5 | Tổng rủi ro tối đa (dùng từ GĐ3) |
| Kiểm thử | `InpSelfTest` | false | Đối chiếu chỉ báo + in bảng tick value |
| | `InpSelfTestSymbols` | BTCUSD,XAUUSD,EURUSD,USDJPY,US30 | Ít nhất 3 nhóm tài sản |
| | `InpLogSnapshots` | true | In snapshot chỉ báo của ưu tiên/phụ mỗi giờ |

Input của GĐ2–5 (trọng số bias, ngưỡng điểm/RR theo tầng, top K, giới hạn tin/ngày, nhóm tương quan, phơi nhiễm tiền tệ, hệ số ATR cho Entry/SL, thời hạn setup, cooldown, đọc vùng vẽ tay) sẽ được thêm ở giai đoạn tương ứng.

---

## 6. Logic phân tích (thiết kế cho Giai đoạn 2, để bạn duyệt trước)

- **Bias từng khung** (+1/-1/0): +1 khi Close > SMA20 và Close > SMA50, SMA20 dốc lên và RSI > 50. -1 khi ngược lại hoàn toàn. Các trường hợp còn lại là 0 (trung tính). Dự kiến có input cho số điều kiện tối thiểu, ví dụ đạt 3/4 điều kiện là đủ.
- **Bias tổng** = Σ trọng số × bias, với MN1 = 1, W1 = 2, D1 = 3, H4 = 2, H1 = 1 (tối đa 9). Khung nào thiếu dữ liệu thì tính 0.
- **Ngưỡng theo tầng**: Ưu tiên |điểm| ≥ 5 và RR ≥ 1.3; Phụ/Khám phá |điểm| ≥ 7 và RR ≥ 1.8.
- **Chờ hồi**: Entry là vùng hội tụ của ít nhất 2 yếu tố (SMA50 H4, SMA200/SMA50 H1, swing H1/H4, vùng vẽ tay). Độ rộng vùng = 0.3 × ATR(H1).
- **Phá vỡ**: H4 đóng ngoài swing gần nhất, cùng hướng bias.
- **SL** = ngoài swing + 0.25 × ATR(H4). **TP1/TP2** = mức hỗ trợ/kháng cự swing H4/D1 kế tiếp.
- **Hủy kèo**: H4 đóng vượt SL thì báo `INVALIDATED`.

---

## 7. Giao diện dữ liệu cho cầu nối Python + Claude API (chỉ thiết kế, chưa cài đặt)

EA sẽ ghi một file JSON cho mỗi sự kiện vào `MQL5/Files/SignalEA/ai_queue/<id>.json`, **chỉ** khi có `SETUP MỚI` hoặc `GIÁ VÀO VÙNG ENTRY`. Script Python đọc file, gọi Claude API, gửi bình luận lên Telegram, rồi chuyển file sang thư mục `done/`. Không dùng ảnh. Script in số token của mỗi lần gọi và giới hạn số lần gọi mỗi ngày.

```json
{
  "schema": "signalea.setup.v1",
  "event": "NEW_SETUP | ENTRY_TOUCHED",
  "id": "XAUUSD-20261014-13-SELL-PB",
  "symbol": "XAUUSD", "tier": "priority", "asset_group": "metals",
  "time_server": "2026-10-14T09:00:00", "time_display": "14/10 13:55 (GMT+7)",
  "price": { "bid": 4150.2, "ask": 4150.5, "spread_atr_pct": 3.1 },
  "setup": { "type": "pullback|breakout", "side": "sell|buy",
             "entry_low": 4172, "entry_high": 4178, "sl": 4196, "tp1": 4135, "tp2": 4100,
             "rr1": 1.7, "rr2": 3.2, "invalidation": "H4 close above 4196", "expiry_hours": 24,
             "confluence": ["SMA50_H4", "SMA200_H1", "manual_zone"] },
  "bias": { "score": -6, "max": 9, "by_tf": { "MN1": 0, "W1": 0, "D1": -1, "H4": -1, "H1": -1 } },
  "indicators": { "H1": { "close": 0, "sma10": 0, "sma20": 0, "sma50": 0, "sma200": 0,
                          "bb_up": 0, "bb_mid": 0, "bb_low": 0, "rsi": 0, "atr": 0 },
                  "H4": {}, "D1": {}, "W1": {}, "MN1": {} },
  "risk": { "balance": 1000, "lot": 0.01, "risk_money": 21, "risk_pct": 2.1,
            "risk_warning": false, "total_open_risk_pct": 3.9 },
  "news": [ { "time": "...", "currency": "USD", "title": "..." } ]
}
```

---

## 8. Xử lý sự cố

| Hiện tượng | Cách xử lý |
|---|---|
| `Symbol ưu tiên 'XAUUSD' không tồn tại` | Kiểm tra tên/hậu tố (`InpSymbolSuffix`) |
| Nhiều symbol bị loại vì "Market Watch đầy" | Tăng `InpMaxMarketWatch` hoặc ẩn bớt symbol |
| "thiếu lịch sử" | Lần đầu tải dữ liệu cần thời gian, EA sẽ tự thử lại ở giờ sau. Có thể mở chart D1 của symbol đó một lần để tải nhanh |
| Chu kỳ chậm (> 2 lần ngân sách) | Giảm `InpSymbolsPerCycle` |
| Lỗi 4060 khi gửi Telegram (GĐ4) | Whitelist `https://api.telegram.org` (mục 4) |

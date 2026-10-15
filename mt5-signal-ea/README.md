# SignalEA: EA báo tín hiệu qua Telegram cho MetaTrader 5

> **EA chỉ báo tín hiệu. Tuyệt đối không đặt, sửa hay đóng lệnh.** Mã nguồn không gọi `OrderSend`, `CTrade` hay bất kỳ hàm giao dịch nào, và không dùng DLL.
> Tín hiệu chỉ để tham khảo, không phải lời khuyên đầu tư.

Phiên bản hiện tại: **0.9.3**, ứng viên phát hành. Đã đủ các giai đoạn 1–5, cộng thêm cầu nối Python gọi Claude API (giai đoạn 6, thư mục `ai-bridge/`), nhật ký kết quả tín hiệu (giai đoạn 7, mục 10), bộ backtest Python (giai đoạn 8, mục 11) và vẽ vùng hỗ trợ/kháng cự lên chart (giai đoạn 9, mục 12). **Mã chưa được biên dịch bằng MetaEditor**: sẽ lên 1.0.0 sau khi biên dịch sạch và đạt các mục nghiệm thu ở mục 9.

---

## 1. Kế hoạch tổng thể

### Các giai đoạn

| GĐ | Nội dung | Trạng thái |
|---|---|---|
| 1 | Khung EA (`OnInit/OnTimer/OnDeinit`), khám phá + phân loại + lọc symbol, quét xoay vòng, tính SMA/BB/RSI/ATR từ `CopyRates`, DryRun, bảng trạng thái, self-test đối chiếu `iMA/iBands/iRSI/iATR` + bảng tick value | Đã giao |
| 2 | Chấm điểm bias đa khung, tìm vùng Entry (confluence), setup chờ hồi/phá vỡ, SL/TP/RR, hủy kèo, hai tầng ngưỡng, nhóm tương quan, phơi nhiễm tiền tệ, xếp hạng top K, giới hạn tin/ngày, cảnh báo tin tức | Đã giao |
| 3 | Quản lý vốn: lot theo SL thật, `CẢNH BÁO RỦI RO`, tổng rủi ro, "đang chờ, vượt ngưỡng rủi ro" | **Đã giao** (phần tính toán làm sớm ở GĐ2; GĐ3 thêm kiểm chéo tick value và log diễn giải) |
| 4 | Telegram thật (`WebRequest`, hàng đợi, retry, rate limit, tin tổng hợp + chi tiết), lưu trạng thái setup ra file, chống báo trùng khi khởi động lại, giới hạn tin/ngày, tóm tắt cuối ngày | Đã giao |
| 5 | Rà soát toàn bộ mã nguồn, hoàn thiện README/TESTING, bảng đối chiếu nghiệm thu (mục 9) | Đã giao |
| 6 | Cầu nối Python gọi Claude API: EA xuất JSON → script gọi Claude → gửi nhận định lên Telegram, in token, giới hạn lần gọi/ngày | Đã giao |
| 7 | Nhật ký kết quả tín hiệu: mô phỏng từng setup trên nến M1, ghi CSV, thống kê trong tóm tắt ngày, script phân tích | Đã giao |
| 8 | Backtest Python: script MT5 xuất lịch sử + engine chạy lại logic EA theo từng giờ, xuất CSV cùng định dạng nhật ký | Đã giao |
| 9 | Vẽ vùng hỗ trợ/kháng cự (swing W1/D1/H4 gom vùng, chấm điểm) lên mọi chart đang mở | **Đã giao** |

### Module

```
mt5-signal-ea/
  SignalEA.mq5             File chính: input, OnInit/OnTimer/OnDeinit, pipeline xử lý 1 symbol, bảng trạng thái
  Include/Common.mqh       Enum, log, tiện ích chuỗi/thời gian (thêm so với đề bài, dùng chung)
  Include/Universe.mqh     Khám phá, phân loại, lọc symbol, quản lý Market Watch, quét xoay vòng
  Include/Indicators.mqh   SMA/BB/RSI/ATR tự tính từ CopyRates + cache handle (tùy chọn) cho ưu tiên/phụ
  Include/Risk.mqh         Thông số hợp đồng, rủi ro ở lot X, lot gợi ý theo % rủi ro, kiểm chéo tick value, diễn giải cách tính
  Include/Telegram.mqh     WebRequest sendMessage, tách tin, hàng đợi, retry, xử lý 429/4014/4060, DryRun
  Include/SelfTest.mqh     Đối chiếu chỉ báo tự tính với iMA/iBands/iRSI/iATR + bảng tick value (thêm)
  Include/AiExport.mqh     Xuất JSON sự kiện cho cầu nối AI (thêm)
  Include/Journal.mqh      Nhật ký kết quả tín hiệu: mô phỏng trên M1, CSV, thống kê (thêm)
  Include/Levels.mqh       Tìm và vẽ vùng hỗ trợ/kháng cự lên chart (thêm)
  tools/analyze_journal.py Phân tích file nhật ký CSV + test (thêm)
  Scripts/ExportHistory.mq5 Script MT5 xuất lịch sử nến + spec cho backtest (thêm)
  backtest/                Bộ backtest Python + test + README riêng (thêm)
  ai-bridge/               Script Python gọi Claude API + test + README riêng (thêm)
  Include/Analysis.mqh     Chấm điểm bias, swing, vùng Entry hội tụ, phá vỡ H4, SL/TP/RR
  Include/Signals.mqh      Vòng đời setup, ưu tiên/tương quan/phơi nhiễm, tổng rủi ro, top K, nội dung tin (thêm)
  Include/News.mqh         Lịch kinh tế MT5: tin mức cao trong 2 giờ tới (best-effort, thêm)
  Include/State.mqh        Lưu/đọc trạng thái setup + bộ đếm ngày (MQL5/Files/SignalEA/state_<login>.txt)
  README.md, TESTING.md
```

### Luồng dữ liệu

```
OnTimer (1s): TgProcessQueue (gửi tối đa 1 tin, giãn cách InpTgMinIntervalMs)
ScanCycle (mỗi 30s)
 ├─ (mỗi 6h) UniBuild: SymbolsTotal/SymbolName → lọc hậu tố, nhóm, trade mode → g_uni[] + log nhận/loại + universe.csv
 ├─ Giờ server mới? → mọi symbol thành "đến hạn"
 └─ RunScanCycle: ưu tiên/phụ trước, rồi xoay vòng nhóm khám phá; tối đa N symbol nặng/chu kỳ + ngân sách ms
      ProcessSymbol(sym):
        phiên giao dịch → Market Watch → báo giá mới → spec hợp đồng
        → CopyRates H1 (có nến H1 mới đóng?) → D1, H4 (bắt buộc) → W1, MN1 (tùy chọn)
        → snapshot SMA/BB/RSI/ATR 5 khung (shift 1 = nến đã đóng)
        → lọc spread ≤ 15% ATR(H1) → lọc vốn (lot tối thiểu ≤ 4% số dư)
        → bias 5 khung → setup chờ hồi / phá vỡ → SL/TP/RR → lot/rủi ro theo SL thật
        → Ưu tiên: kiểm tra tương quan/phơi nhiễm/tổng rủi ro → báo NGAY (tin chi tiết)
        → Phụ/Khám phá: vào danh sách ứng viên
 ├─ Hết vòng quét giờ (hoặc sang giờ mới): xếp hạng ứng viên → top K → giới hạn tin/ngày
 │     → kiểm tra tương quan/phơi nhiễm/tổng rủi ro → 1 tin tổng hợp (hoặc 1 tin chi tiết nếu chỉ có 1 setup)
 └─ SigMonitor (mỗi chu kỳ, rất nhẹ): giá vào vùng Entry / H4 đóng vượt SL / hết hạn / chạm mục tiêu
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
7. **Lọc vốn có hai lớp**. Lớp 1 (trước khi phân tích, để loại sớm và tiết kiệm CPU) dùng **SL giả định = 1.0 × ATR(H4)** (`InpFeasSlAtrMult`). Lớp 2 tính lại theo SL thật của setup.
8. **Nhịp phân tích**: mỗi symbol được phân tích tối đa 1 lần/giờ server, ngay sau khi nến H1 đóng và đã có tick của giờ mới. Với khoảng 200 symbol, N = 5 và timer 30s, một vòng quét hết khoảng 20 phút. Ưu tiên/phụ luôn xử lý trước, thường trong chu kỳ đầu tiên của giờ. Các setup đang mở được theo dõi mỗi chu kỳ (giá vào vùng Entry, hủy kèo, hết hạn); việc này rất nhẹ vì chỉ đọc bid/ask và 1 nến H4.
9. **Chỉ báo**: tự tính từ `CopyRates` cho mọi symbol, cùng công thức với chỉ báo chuẩn MT5: BB dùng độ lệch chuẩn tổng thể, RSI làm trơn Wilder, ATR là SMA của True Range. Handle `iMA/iBands/iRSI/iATR` cho ưu tiên/phụ là tùy chọn (`InpUseHandlesForWatchlist`, mặc định tắt để tiết kiệm RAM; nếu bật thì cần 35 handle cho mỗi symbol và chúng được giải phóng ở `OnDeinit`).
10. **MN1/W1 thiếu dữ liệu** (ví dụ thiếu nến cho SMA200): giá trị là `EMPTY_VALUE`, hiển thị `n/a`, không báo lỗi.
11. **Múi giờ hiển thị**: GMT+7. Độ lệch giờ server được tính bằng `TimeTradeServer() - TimeGMT()` và làm tròn tới 15 phút.
12. **Mã hóa file**: các file nguồn là UTF-8 có BOM để MetaEditor đọc đúng chuỗi tiếng Việt.
13. **Trạng thái setup** được lưu vào `MQL5/Files/SignalEA/state_<số tài khoản>.txt` mỗi khi có thay đổi. File được ghi qua file tạm rồi đổi tên nên không bị hỏng giữa chừng. Khởi động lại EA thì setup đang mở và cooldown được nạp lại, nên không báo trùng. Nếu EA tắt trong lúc có nến H4 đóng vượt SL, khi chạy lại EA vẫn xét các nến đã bỏ lỡ và báo HỦY KÈO. Hàng đợi Telegram chưa gửi thì không được lưu: khi gỡ EA, các tin đó được in ra log.
14. **Tin tổng hợp** được gửi khi xong vòng quét giờ (hoặc khi sang giờ mới). Tin chi tiết cho ưu tiên được gửi ngay, không đợi hết vòng.

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

## 4. Telegram

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
Nếu chưa làm bước này, WebRequest sẽ báo lỗi (4014/4060) và EA in lại hướng dẫn này trong log, tối đa 10 phút một lần.

### Bật gửi thật
1. Đặt `InpDryRun=false`, `InpTgEnabled=true`, nhập `InpTgToken` và `InpTgChatId`.
2. Gắn EA. Tin "EA ĐÃ CHẠY" là **tin thử**: nhận được tin này nghĩa là cấu hình đúng.
3. Trong Strategy Tester, WebRequest không hoạt động nên EA tự chuyển sang chỉ in log.

### Cách gửi
- Gửi POST tới `https://api.telegram.org/bot<TOKEN>/sendMessage` dạng form-urlencoded, UTF-8, **không dùng `parse_mode`** (văn bản thuần, không lỗi ký tự).
- **Hàng đợi** giữ đúng thứ tự. Mỗi giây gửi tối đa 1 tin, các tin cách nhau ít nhất `InpTgMinIntervalMs` (3000 ms, tức 20 tin/phút, đúng giới hạn của group).
- **Thử lại** tối đa `InpTgMaxRetries` (3) lần, giãn cách 5s → 15s → 45s, khi lỗi mạng, timeout, WebRequest bị chặn hoặc HTTP 5xx.
- **HTTP 429**: chờ đúng `retry_after` mà Telegram trả về, không tính là một lần thử.
- **HTTP 400/401/403/404** (token sai, chat id sai, bot bị chặn hoặc chưa bấm Start): không thử lại, EA ghi log gợi ý cách sửa.
- Tin bị bỏ sau khi hết lượt thử, hoặc còn trong hàng đợi lúc gỡ EA, được in nguyên văn ra log để không mất.
- Token không bao giờ được in ra log.

### Các loại tin
`EA ĐÃ CHẠY` (khởi động), `SETUP` (chi tiết, kèm nhãn `CẢNH BÁO RỦI RO` hoặc `ĐANG CHỜ, VƯỢT NGƯỠNG RỦI RO` khi cần), `[TỔNG HỢP]`, `GIÁ VÀO VÙNG ENTRY`, `HỦY KÈO`, `HẾT HẠN`, `TÓM TẮT NGÀY` (tùy chọn, lúc 22h GMT+7). Mỗi tin đều có nhãn nhóm `Ưu tiên` / `Phụ` / `Khám phá`.

---

## 5. Tham số (input)

| Nhóm | Input | Mặc định | Ý nghĩa |
|---|---|---|---|
| Chung | `InpDryRun` | true | Chỉ in nội dung tin ra log, không gọi Telegram |
| | `InpLogLevel` | INFO | DEBUG để xem chi tiết từng symbol |
| | `InpTimerSeconds` | 30 | Chu kỳ quét symbol (timer nền chạy 1 giây để gửi Telegram) |
| | `InpDisplayGmtOffset` | 7 | Múi giờ hiển thị |
| | `InpShowPanel` | true | Bảng trạng thái (Comment) trên chart |
| Telegram | `InpTgEnabled`, `InpTgToken`, `InpTgChatId` | tắt / trống | Cấu hình bot |
| | `InpTgMinIntervalMs` | 3000 | Giãn cách tối thiểu giữa 2 tin |
| | `InpTgMaxRetries` | 3 | Số lần thử lại |
| | `InpDailySummary`, `InpDailySummaryHour` | true, 22 | Tóm tắt cuối ngày (giờ theo múi giờ hiển thị) |
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
| | `InpMaxTotalRiskPct` | 5 | Tổng rủi ro tối đa của các setup đang mở |
| | `InpTickValueTolPct` | 5 | Cảnh báo khi tick value của broker lệch kiểm chéo quá mức này |
| Kiểm thử | `InpSelfTest` | false | Đối chiếu chỉ báo + in bảng tick value |
| | `InpSelfTestSymbols` | BTCUSD,XAUUSD,EURUSD,USDJPY,US30 | Ít nhất 3 nhóm tài sản |
| | `InpLogSnapshots` | true | In snapshot chỉ báo của ưu tiên/phụ mỗi giờ |
| Cầu nối AI | `InpAiExport` | false | Xuất JSON khi có SETUP MỚI / GIÁ VÀO VÙNG ENTRY cho script `ai-bridge` |
| Nhật ký | `InpJournalEnabled` | true | Mô phỏng kết quả từng setup, ghi `journal_<login>.csv` |
| | `InpJournalMaxHoldHours` | 120 | Giữ lệnh mô phỏng tối đa bao nhiêu giờ, quá thì chốt theo giá đóng cửa |

| Bias & ngưỡng | `InpWeightMN1/W1/D1/H4/H1` | 1/2/3/2/1 | Trọng số bias |
| | `InpBiasMinConditions` | 3 | Số điều kiện (trên 4) để một khung là tăng/giảm |
| | `InpMinScorePriority`, `InpMinRRPriority` | 5, 1.3 | Ngưỡng của tầng Ưu tiên |
| | `InpMinScoreOther`, `InpMinRROther` | 7, 1.8 | Ngưỡng của tầng Phụ/Khám phá |
| Setup | `InpEnablePullback`, `InpEnableBreakout` | true | Bật/tắt từng loại setup |
| | `InpEntryZoneAtrH1` | 0.3 | Độ rộng vùng Entry |
| | `InpConfluenceTolAtrH1` | 0.5 | Khoảng gom các yếu tố hội tụ |
| | `InpMinConfluence` | 2 | Số loại yếu tố tối thiểu |
| | `InpMaxEntryDistAtrH4` | 2.0 | Vùng Entry cách giá tối đa |
| | `InpSwingStrengthH1/H4/D1`, `InpSwingLookback` | 3/2/2, 150 | Cách tìm swing |
| | `InpSlBufferAtrH4`, `InpSlFallbackAtrH4` | 0.25, 1.0 | SL |
| | `InpTpMinGapAtrH4` | 0.3 | TP phải cách Entry tối thiểu |
| | `InpSetupExpiryHours`, `InpTriggeredMaxHours` | 24, 72 | Thời hạn |
| | `InpCooldownMinutes` | 240 | Cooldown cho mỗi symbol |
| Xếp hạng | `InpTopK` | 3 | Top K mỗi vòng quét (Phụ/Khám phá) |
| | `InpMaxNewPerDay` | 10 | Số tin setup mới tối đa mỗi ngày (Phụ/Khám phá) |
| | `InpCorrelationGroups` | KIM_LOAI:XAU,XAG,XPT,XPD; CRYPTO:BTC,ETH,...; CHI_SO_MY:US30,US500,USTEC,US100; DAU:UKOIL,USOIL,XBR,XTI | Nhóm tương quan |
| | `InpMaxCurrencySameSide` | 2 | Phơi nhiễm Forex |
| Tin tức | `InpNewsEnabled`, `InpNewsLookaheadMin`, `InpNewsCurrencies`, `InpNewsIncludeSymbolCcy` | true, 120, USD, false | |
| Hỗ trợ/kháng cự | `InpLevelsEnabled`, `InpLevelsAllCharts` | true, true | Bật vẽ; vẽ trên mọi chart đang mở hay chỉ chart gắn EA |
| | `InpLevelsPerSide` | 4 | Số vùng tối đa phía trên và phía dưới giá |
| | `InpLevelsUseW1`, `InpLevelsMinScore`, `InpLevelsStrongScore` | true, 3, 6 | Dùng swing W1; điểm tối thiểu; điểm của vùng mạnh |
| | `InpLevelsClusterAtrH4`, `InpLevelsRangeAtrD1` | 0.5, 6.0 | Khoảng gom swing; khoảng cách tối đa tới giá |
| | `InpLevelsDrawZones`, `InpLevelsShowLabels`, các màu | true, true | Tô nền vùng, nhãn giá, màu đường/nền |

---

## 6. Logic phân tích (Giai đoạn 2)

### 6.1 Bias từng khung và bias tổng
Với mỗi khung MN1, W1, D1, H4, H1, EA xét 4 điều kiện trên nến đã đóng gần nhất:
1. Close so với SMA20
2. Close so với SMA50
3. Độ dốc SMA20: SMA20[1] so với SMA20[1+3]
4. RSI14 so với 50

Khung là **tăng (+1)** khi có ít nhất `InpBiasMinConditions = 3` điều kiện phía tăng, **giảm (-1)** khi có ít nhất 3 điều kiện phía giảm, còn lại là **0**. Điều kiện nào thiếu dữ liệu thì không tính cho phía nào.
Bias tổng = Σ trọng số × bias (MN1 1, W1 2, D1 3, H4 2, H1 1; tối đa 9). Hướng setup theo dấu của bias tổng.

| Tầng | |điểm| tối thiểu | RR TP1 tối thiểu |
|---|---|---|
| Ưu tiên | 5 | 1.3 |
| Phụ / Khám phá | 7 | 1.8 |

### 6.2 Setup chờ hồi (Buy/Sell Limit)
- Các mức giá được xét: SMA50 H4, SMA200 H1, SMA50 H1, swing H1 (3 nến mỗi bên), swing H4 (2 nến mỗi bên). Swing là fractal: đỉnh cao hơn N nến mỗi bên.
- Bias giảm thì xét các mức **phía trên** giá; bias tăng thì xét các mức phía dưới. Mức phải cách giá không quá 2 × ATR(H4).
- Đi từ mức gần giá nhất ra xa, EA gom các mức nằm trong khoảng 0.5 × ATR(H1). Cụm đầu tiên có **≥ 2 loại yếu tố khác nhau** được chọn (hai swing H1 chỉ tính là một loại).
- Vùng Entry = trung bình cụm ± 0.15 × ATR(H1), tức rộng 0.3 × ATR(H1). Vùng không được chứa giá hiện tại.

### 6.3 Setup phá vỡ
- Chỉ xét khi có nến H4 mới đóng. Sell khi H4[1] đóng **dưới** đáy swing H4 gần nhất trong lúc H4[2] còn đóng trên đáy đó (tức phá vỡ vừa xảy ra). Buy thì ngược lại. Hướng phải cùng chiều bias.
- Vùng Entry: từ giá đóng H4 đến mức bị phá, giới hạn tối đa 0.5 × ATR(H4), tối thiểu 0.3 × ATR(H1). Có thể vào theo giá thị trường hoặc chờ retest.
- Nếu cả hai loại setup đều hợp lệ, EA chọn setup có RR cao hơn.

### 6.4 SL / TP / RR
- **SL** = swing gần nhất phía bảo vệ (H1/H4, trong phạm vi 3 × ATR(H4)) + 0.25 × ATR(H4). Không có swing thì SL = mép vùng Entry + 1.0 × ATR(H4).
- **TP1/TP2** = các swing H4/D1 kế tiếp theo hướng lệnh, cách Entry ít nhất 0.3 × ATR(H4). TP2 phải cách TP1 ít nhất 0.25 × ATR(H4). Không có TP2 thì hiển thị một TP.
- RR tính từ giữa vùng Entry. Setup bị loại nếu RR của TP1 nhỏ hơn ngưỡng của tầng.

### 6.5 Vòng đời setup (mỗi chu kỳ 30 giây, chỉ đọc bid/ask và 1 nến H4)
| Sự kiện | Kết quả | Tin |
|---|---|---|
| Giá vào vùng Entry | `đã vào vùng` | `GIÁ VÀO VÙNG ENTRY` |
| H4 đóng vượt SL | `INVALIDATED` | `HỦY KÈO` |
| Giá chạy tới TP1 trước khi vào vùng | `INVALIDATED` | `HỦY KÈO` (lỡ kèo) |
| Giá chưa vào vùng sau 24h | `EXPIRED` | `HẾT HẠN` |
| Đã vào vùng quá 72h | `EXPIRED` | `HẾT HẠN` |
| Đã vào vùng và giá chạm TP2 (hoặc TP1 nếu không có TP2) | `DONE` | chỉ ghi log |

Mỗi symbol chỉ có tối đa 1 setup mở. Sau khi setup đóng, symbol đó không có setup mới trong `InpCooldownMinutes` (240 phút).

### 6.6 Ưu tiên, tương quan, phơi nhiễm, rủi ro
- **Ưu tiên** được báo ngay khi phân tích xong, không bị giới hạn top K hay số tin/ngày.
- **Phụ/Khám phá** được xếp hạng ở cuối vòng quét theo điểm chất lượng 0–100:
  40 × |bias|/9 + 30 × min(RR, 4)/4 + 20 × min(số yếu tố hội tụ, 4)/4 + 10 × (1 − spread%/ngưỡng spread).
  Tối đa **top 3 mỗi vòng** và **10 tin/ngày** (tính theo ngày GMT+7).
- **Nhóm tương quan** (`InpCorrelationGroups`; symbol được xếp vào nhóm khi tên bắt đầu bằng mã trong nhóm):
  - Phụ/Khám phá bị chặn nếu trong nhóm đã có một setup đang mở bất kỳ. Quy tắc này bao gồm cả "phụ chỉ báo khi ưu tiên cùng nhóm không có setup" và "mỗi nhóm chỉ giữ một setup". Trong cùng một vòng, ứng viên có điểm cao nhất được xét trước.
  - Ưu tiên không bị chặn bởi setup cùng hướng. Nếu ngược hướng với một setup Phụ/Khám phá **chưa vào vùng**, setup đó bị hủy (`HỦY KÈO`, nhường chỗ). Nếu ngược hướng với một setup ưu tiên, hoặc với một setup đã vào vùng, thì setup ưu tiên mới không được báo.
  - Symbol phụ không thuộc nhóm tương quan nào thì không bị ràng buộc với ưu tiên.
- **Phơi nhiễm Forex**: mỗi setup được tách thành vị thế mua/bán từng đồng tiền (Sell EURUSD = bán EUR, mua USD). Setup mới bị chặn nếu làm một đồng tiền có quá 2 setup cùng phía.
- **Rủi ro**:
  - Lot = rủi ro 1.5% chia cho (khoảng cách SL × tick value), làm tròn xuống theo volume step.
  - Nếu lot tối thiểu đã vượt 1.5%: dùng lot tối thiểu và gắn nhãn `CẢNH BÁO RỦI RO`.
  - Nếu lot tối thiểu vượt 4% (ngưỡng cứng): không báo, chỉ ghi log.
  - Nếu tổng rủi ro của các setup đang mở cộng thêm setup mới vượt 5%: tin được gắn nhãn **"ĐANG CHỜ, VƯỢT NGƯỠNG RỦI RO"**, setup không được tính vào tổng rủi ro và không được theo dõi giá.
  - Chưa đọc được số dư (bằng 0, ví dụ lúc terminal mới kết nối): không tạo setup.

### 6.8 Kiểm chéo tick value
- Rủi ro luôn tính bằng `SYMBOL_TRADE_TICK_VALUE_LOSS` / `TICK_SIZE` của broker. Terminal đã quy đổi giá trị này về tiền tệ tài khoản, nên dùng đúng cho mọi loại tài sản và cả tài khoản không phải USD.
- Mỗi lần phân tích, EA tự tính lại giá trị kỳ vọng = tick size × contract size × tỷ giá (tiền tệ lợi nhuận → tiền tệ tài khoản). Tỷ giá lấy từ cặp tiền trực tiếp hoặc nghịch đảo, ví dụ USDJPY cho JP225.
  - Lệch > `InpTickValueTolPct` (5%): log cảnh báo một lần, vẫn dùng số của broker.
  - Lệch > 10 lần: coi là dữ liệu hỏng, loại symbol (trạng thái "spec bất thường").
  - Kiểu tính futures hoặc không tìm được tỷ giá: bỏ qua kiểm chéo.
  - Để lấy tỷ giá, EA có thể thêm cặp quy đổi (ví dụ USDJPY) vào Market Watch.
- Mỗi setup được báo có một dòng log `[RISK] <symbol> <id>: SL cách ... = N tick × tick value = $/lot | ngân sách 1.5% × số dư = $ → x lot → làm tròn xuống step → lot | rủi ro $ (%)` để đối chiếu tay.
- **Tin tức**: nếu có tin USD mức cao trong 2 giờ tới (lịch kinh tế MT5), tin setup có thêm dòng ghi chú. Nếu không có dữ liệu lịch thì bỏ qua.

### 6.7 Mẫu tin
```
[XAUUSD] SETUP SELL (chờ hồi) - Nhóm: Ưu tiên
Giá hiện tại: 4150.20 | Thời gian: 14/10 13:55 (GMT+7)
Bias: MN1 0 | W1 0 | D1 giảm | H4 giảm | H1 giảm  (điểm 6/9)
Entry (Sell Limit): 4172.00 - 4178.00
SL: 4196.00 (cách ~21.00)
TP1: 4135.00 (RR 1:1.7) | TP2: 4100.00 (RR 1:3.2)
Lot gợi ý: 0.01 (rủi ro ≈ $21 = 2.1%)
Hủy kèo: H4 đóng trên 4196.00 | Hết hạn: 24h
Lý do: hội tụ SMA50 H4 + swing H1
Tổng rủi ro các setup đang mở: $39 (3.9%)
Chỉ là tín hiệu tham khảo, không phải lời khuyên đầu tư.
```

## 7. Cầu nối Python + Claude API (giai đoạn 6)

Hướng dẫn đầy đủ nằm ở **`ai-bridge/README.md`**. Tóm tắt:
- Đặt `InpAiExport=true`. Mỗi khi EA báo `SETUP MỚI` hoặc `GIÁ VÀO VÙNG ENTRY`, EA ghi một file JSON (`signalea.setup.v1`, không có ảnh) vào `MQL5/Files/SignalEA/ai_queue/`. Setup "đang chờ, vượt ngưỡng rủi ro" không được xuất.
- `ai-bridge/signal_ai_bridge.py` chạy trên cùng VPS:
  - đọc từng file JSON và gọi Claude (`claude-opus-5-5`, effort `medium`, tự chuyển model dự phòng nếu bị từ chối);
  - gửi nhận định tiếng Việt lên Telegram (`[SYM] NHẬN ĐỊNH AI - ...`);
  - **in số token và chi phí ước tính** sau mỗi lần gọi;
  - **giới hạn số lần gọi mỗi ngày** (mặc định 20).
- API key, token Telegram và chat id được đặt qua biến môi trường (`setx`), không ghi trong file.
- Mẫu JSON: `ai-bridge/sample_event.json`. Test: `python -m unittest -v test_signal_ai_bridge.py` (12 test, không gọi mạng).

---

## 8. Xử lý sự cố

| Hiện tượng | Cách xử lý |
|---|---|
| `Symbol ưu tiên 'XAUUSD' không tồn tại` | Kiểm tra tên/hậu tố (`InpSymbolSuffix`) |
| Nhiều symbol bị loại vì "Market Watch đầy" | Tăng `InpMaxMarketWatch` hoặc ẩn bớt symbol |
| "thiếu lịch sử" | Lần đầu tải dữ liệu cần thời gian, EA sẽ tự thử lại ở giờ sau. Có thể mở chart D1 của symbol đó một lần để tải nhanh |
| Chu kỳ chậm (> 2 lần ngân sách) | Giảm `InpSymbolsPerCycle` |
| Lỗi 4014/4060 khi gửi Telegram | Whitelist `https://api.telegram.org` (mục 4) rồi gắn lại EA |
| `Telegram từ chối (HTTP 401...)` | Token sai: lấy lại token từ @BotFather |
| `Telegram từ chối (HTTP 400: chat not found)` | Chat id sai, hoặc chưa nhắn cho bot / chưa thêm bot vào group |
| `Telegram từ chối (HTTP 403...)` | Bạn đã chặn bot hoặc bot bị kick khỏi group |
| `[RISK] ... tick value broker lệch x%` | Gửi tôi dòng log đó kèm thông số hợp đồng trên Exness để kiểm tra |
| Muốn xóa toàn bộ setup đã lưu | Gỡ EA, xóa `MQL5/Files/SignalEA/state_<số TK>.txt`, rồi gắn lại EA |

---

## 9. Đối chiếu nghiệm thu

| # | Tiêu chí | Cách đáp ứng trong mã | Cách kiểm (TESTING.md) | Trạng thái |
|---|---|---|---|---|
| 1 | Biên dịch không lỗi, không cảnh báo nghiêm trọng | Đã rà soát tĩnh: ngoặc cân bằng, không gọi hàm trước khi khai báo, ép kiểu rõ ràng (`IntMax/IntMin/IntAbs`), file UTF-8 có BOM | T1.1, T2.1 | **Chờ bạn biên dịch** |
| 2 | DryRun in đúng nội dung tin cho BTCUSD, XAUUSD | `InpDryRun=true` → mọi tin in ra log với tiền tố `[DRYRUN]`; mỗi giờ có `[SNAPSHOT]` cho ưu tiên/phụ; mẫu tin ở mục 6.7 | T1.2, T2.3 | Chờ chạy thử |
| 3 | Gửi được tin thử; khởi động lại không báo trùng | Tin "EA ĐÃ CHẠY" là tin thử; `State.mqh` lưu setup đang mở và cooldown, nạp lại khi khởi động | T4.1, T4.4 | Chờ chạy thử |
| 4 | Chỉ báo khớp CSV của `ExportChartData.mq5` | Self-test ghi `MQL5/Files/SignalEA/selftest_values.csv` (giá trị nến đã đóng) để so sánh | T1.6 | Chờ chạy thử |
| 5 | Lot/rủi ro đúng theo tick value Exness | Lot tính từ `TICK_VALUE_LOSS/TICK_SIZE`, làm tròn xuống theo step; kiểm chéo tick value; log `[RISK]` diễn giải từng bước | T1.7, T3.1–T3.3 | Chờ chạy thử |
| 6 | Không có hàm giao dịch | Không có `OrderSend`, `CTrade`, `Position*`, `OrderCalc*`, `#import`/DLL (đã tìm trong toàn bộ mã) | T1.1 | **Đạt** (kiểm tĩnh) |
| 7 | Quét ổn định hàng trăm symbol; RAM/CPU không tăng dần; một chu kỳ không quá vài giây | N symbol/chu kỳ + ngân sách ms; chỉ báo tự tính (không giữ handle); gỡ symbol khám phá khỏi Market Watch sau khi quét; mọi mảng đều có giới hạn (setup đóng được dọn, hàng đợi Telegram ≤ 100, ứng viên xóa mỗi vòng) | T1.4, T1.8, T2.10 | Chờ chạy 24h |
| 8 | Log nhận/loại kèm lý do; DryRun cả ngày không gây bão tin | Log + `universe.csv`; top K/vòng, giới hạn tin/ngày, 1 setup/symbol, cooldown | T1.3, T2.5, T4.6 | Chờ chạy 24h |
| 9 | Chỉ báo tự tính khớp `iMA/iBands/iRSI/iATR` trên ≥ 5 symbol, 3 nhóm | Self-test 5 symbol mặc định (Crypto, Kim loại, Forex, Chỉ số) × H1/H4/D1 | T1.6 | Chờ chạy thử |

Những điểm cần lưu ý (giới hạn đã biết):
- **Chưa biên dịch**: môi trường phát triển không có MetaEditor. Lỗi cú pháp nếu có thường nhỏ (kiểu dữ liệu, tên hằng) và sửa nhanh khi có `SignalEA.log`.
- **Phân loại nhóm** dựa trên `SYMBOL_PATH` của Exness. Cần kiểm tra cột nhóm trong `universe.csv` ở lần chạy đầu.
- **RSI tự tính** dùng khoảng 320 nến, nên có thể lệch iRSI ở chữ số thập phân thứ 3–4 (dung sai self-test 0.05).
- **Hàng đợi Telegram** không được lưu qua lần khởi động lại; tin chưa gửi được in ra log.
- **Tin tức** phụ thuộc lịch kinh tế của MT5; không có dữ liệu thì bỏ qua, không báo lỗi.

---

## 10. Nhật ký kết quả tín hiệu (giai đoạn 7)

Mục đích: trả lời câu hỏi **"tín hiệu của EA có lãi không?"** bằng số liệu, thay vì cảm nhận.

### Cách mô phỏng
- Mỗi setup được báo đều có một bản ghi trong nhật ký. Setup "đang chờ, vượt ngưỡng rủi ro" cũng được ghi, nhưng đánh dấu `pending_risk=1` và **không** tính vào thống kê chính.
- Mỗi chu kỳ quét, EA đọc các nến **M1** mới đóng của symbol (giá bid) và cộng spread lúc báo tín hiệu cho các mức chạy theo giá ask.
- **Khớp lệnh** khi giá chạm `entry_ref`, tức giữa vùng Entry, cũng là mức dùng để tính RR và lot. Chỉ chạm mép vùng thì chưa tính là khớp.
- **Quy tắc thận trọng:**
  - Trong nến khớp, chỉ xét SL; TP được xét từ nến kế tiếp.
  - SL và TP cùng nằm trong một nến M1 thì tính SL chạm trước.
- **Không khớp:** setup bị hủy, hết hạn hoặc lỡ kèo trước khi giá tới `entry_ref` → kết quả `NOT_FILLED`.
- **Ba kịch bản thoát lệnh**, tính theo R (1R = khoảng cách Entry–SL):

| Kịch bản | Cách thoát |
|---|---|
| A | Chốt toàn bộ ở TP1 |
| B | Chốt toàn bộ ở TP2 (không có TP2 thì dùng TP1) |
| C | Chốt 50% ở TP1, 50% còn lại dời SL về hòa vốn và chờ TP2 |

- Giữ quá `InpJournalMaxHoldHours` (120 giờ) thì chốt theo giá đóng cửa, kết quả `TIMEOUT`.
- Chưa tính trượt giá hay commission (tài khoản Pro của Exness không có commission).
- Bản ghi đang theo dõi được lưu vào `journal_<login>_open.txt`, nên khởi động lại EA vẫn tiếp tục. Khi EA chạy lại, nó đọc bù các nến M1 bị bỏ lỡ, tối đa khoảng 14 ngày.

### File `MQL5/Files/SignalEA/journal_<login>.csv`
Mỗi kèo đóng được ghi một dòng. File dùng UTF-8, phân cách `;`, mở được bằng Excel. Thời gian theo GMT+7.

| Cột | Ý nghĩa |
|---|---|
| `id`, `symbol`, `tier`, `group`, `side`, `type`, `score` | Thông tin setup |
| `pending_risk` | 1 = setup "đang chờ, vượt ngưỡng rủi ro" |
| `entry`, `sl`, `tp1`, `tp2`, `rr1`, `rr2`, `spread`, `lot`, `risk_money`, `risk_pct`, `risk_warning` | Thông số lúc báo |
| `filled`, `fill_time`, `minutes_to_fill` | Có khớp không, khớp lúc nào |
| `outcome` | `SL`, `TP1` (khi không có TP2), `TP1_SL` (chạm TP1 rồi quay về SL), `TP2`, `TIMEOUT`, `NOT_FILLED` |
| `r_a`, `r_b`, `r_c` | Kết quả theo R của kịch bản A, B, C |
| `mfe_r`, `mae_r` | Mức đi thuận / đi ngược lớn nhất, tính theo R |
| `hold_hours`, `close_time` | Thời gian giữ lệnh, lúc đóng |
| `money_a` | Lãi/lỗ lý thuyết của kịch bản A theo lot gợi ý |

### Xem kết quả
- **Tóm tắt cuối ngày** trên Telegram có thêm thống kê tích lũy: số kèo, tỷ lệ khớp, tỷ lệ thắng và tổng R của từng kịch bản.
- **Bảng trạng thái** trên chart có một dòng tóm tắt nhật ký.
- **Phân tích chi tiết** bằng script Python (chỉ dùng thư viện chuẩn):
  ```
  python tools\analyze_journal.py "...\MQL5\Files\SignalEA\journal_<login>.csv"
  python tools\analyze_journal.py journal.csv --scenario C
  ```
  Script in ra:
  - tỷ lệ thắng, kỳ vọng trung bình theo R kèm khoảng tin cậy 95%;
  - profit factor, chuỗi thua dài nhất, drawdown lớn nhất (theo R);
  - bảng tách theo tầng, nhóm tài sản, loại setup, hướng, điểm bias, symbol.

### Cách đọc kết quả
- **Cần ít nhất 30 kèo khớp**, tốt hơn là 100, trước khi kết luận. Với ít kèo, khoảng tin cậy rất rộng và kết quả tốt có thể chỉ là may mắn.
- **Kỳ vọng trung bình > 0 và cận dưới khoảng tin cậy 95% > 0** thì mới có dấu hiệu có lợi thế thật.
- **So sánh A/B/C** để chọn cách chốt lời phù hợp với các setup này.
- **Xem bảng tách nhóm** để tìm nhóm/loại setup kéo kết quả xuống, rồi tắt hoặc sửa nhóm đó. Mỗi lần chỉ thay đổi một thứ, tránh tối ưu quá khớp với dữ liệu quá khứ.
- **Đây là mô phỏng**, không phải lệnh thật. Kết quả thật còn phụ thuộc trượt giá và việc bạn có vào lệnh đúng như tín hiệu hay không.

---

## 11. Backtest bằng Python (giai đoạn 8)

Hướng dẫn đầy đủ nằm ở **`backtest/README.md`**. Tóm tắt:
1. **Lấy dữ liệu:** chạy `Scripts/ExportHistory.mq5` trong MT5 để xuất lịch sử MN1/W1/D1/H4/H1/M1 và thông số hợp đồng ra `MQL5/Files/SignalEA/history/`.
2. **Chạy backtest:** `python backtest/run_backtest.py --data-dir <thư mục history>`. Bộ backtest chạy lại logic của EA theo từng giờ trên nhiều symbol: bias, setup, SL/TP, các bộ lọc, tương quan, phơi nhiễm, tổng rủi ro, top K, giới hạn tin/ngày, vòng đời setup. Kết quả lệnh được mô phỏng theo đúng quy tắc của nhật ký.
3. **Xem kết quả:** CSV có cùng định dạng `journal_<login>.csv`, và báo cáo được in ra bằng `tools/analyze_journal.py`.

Chỉ dùng thư viện chuẩn Python, không cần cài thêm. Đọc mục 3–4 của `backtest/README.md` để biết các khác biệt so với EA chạy thật và cách tránh tối ưu quá khớp với dữ liệu quá khứ.

## 12. Vùng hỗ trợ/kháng cự trên chart (giai đoạn 9)

EA tự vẽ các vùng hỗ trợ (HT, xanh) và kháng cự (KC, đỏ) lên **mọi chart đang mở** trong terminal (hoặc chỉ chart gắn EA nếu `InpLevelsAllCharts=false`). Mở chart BTCUSD hay XAUUSD ở bất kỳ khung nào là thấy vùng, không cần gắn EA lên từng chart. Phần này chỉ vẽ đối tượng đồ họa, không giao dịch và không ảnh hưởng tới logic tín hiệu.

**Cách tìm vùng:**
1. Lấy các đỉnh/đáy swing đã xác nhận (fractal) trên W1 (khoảng 3 năm, 2 nến mỗi bên), D1 (khoảng 1 năm, `InpSwingStrengthD1`) và H4 (khoảng 2 tháng, `InpSwingStrengthH4`). Chỉ dùng nến đã đóng.
2. Gom các swing có giá cách nhau ≤ `InpLevelsClusterAtrH4` × ATR(H4) thành một vùng. Đỉnh cũ và đáy cũ được gom chung, vì kháng cự bị phá thường thành hỗ trợ và ngược lại.
3. **Điểm vùng** = tổng trọng số các lần chạm: W1 = 3, D1 = 2, H4 = 1. Bỏ vùng có điểm < `InpLevelsMinScore` (mặc định 3: ví dụ 1 lần chạm D1 + 1 lần H4, hoặc 1 lần chạm W1) và vùng cách giá > `InpLevelsRangeAtrD1` × ATR(D1).
4. Vùng có tâm trên giá hiện tại là **kháng cự**, dưới giá là **hỗ trợ**. Mỗi phía vẽ `InpLevelsPerSide` vùng gần giá nhất.

**Cách đọc trên chart:**
- Nét đậm (3) là vùng **mạnh** (điểm ≥ `InpLevelsStrongScore`), nét vừa (2) là vùng trung bình, nét đứt là vùng yếu.
- Nhãn bên phải nến cuối có dạng `KC 82700 · D1x1 H4x3 · TB`: giá tâm vùng, số lần chạm theo khung, độ mạnh.
- Rê chuột lên đường hoặc vùng để xem tooltip: biên dưới/biên trên của vùng, điểm, lần chạm gần nhất, và "GIÁ ĐANG TEST" khi giá đang nằm trong vùng.
- Phần tô nền bắt đầu từ lần chạm cũ nhất.

**Cập nhật:**
- Vùng được tính lại mỗi khi có nến H1 mới đóng, tối đa 2 symbol mỗi chu kỳ 30 giây, nên không nặng cho VPS.
- Chart được vẽ lại khi vùng thay đổi, khi giá vượt sang phía khác của vùng, khi có nến mới, hoặc khi bạn đổi khung.
- Log có dòng `[LEVELS] BTCUSD KC: ... | HT: ...` mỗi lần tính lại.
- Gỡ EA thì mọi đối tượng (tiền tố `SEA_LV_`) được xóa.

**Lưu ý:**
- Chart nền tối nên đổi `InpLevelsZoneColorRes/Sup` sang màu tối, hoặc tắt `InpLevelsDrawZones` để chỉ còn đường kẻ.
- Đây là vùng tính máy móc từ swing. Các vùng tâm lý (số tròn như 80.000, 4.000) và đường xu hướng chéo không được vẽ. Dùng vùng này làm điểm tham chiếu và tự xác nhận bằng hành động giá.

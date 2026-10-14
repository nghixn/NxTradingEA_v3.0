# SignalEA: EA báo tín hiệu qua Telegram cho MetaTrader 5

> **EA chỉ báo tín hiệu. Tuyệt đối không đặt, sửa hay đóng lệnh.** Mã nguồn không gọi `OrderSend`, `CTrade` hay bất kỳ hàm giao dịch nào, và không dùng DLL.
> Tín hiệu chỉ để tham khảo, không phải lời khuyên đầu tư.

Phiên bản hiện tại: **0.4.0, Giai đoạn 4** (thêm gửi Telegram thật, hàng đợi + retry, lưu trạng thái để khởi động lại không báo trùng, tóm tắt cuối ngày).

---

## 1. Kế hoạch tổng thể

### Các giai đoạn

| GĐ | Nội dung | Trạng thái |
|---|---|---|
| 1 | Khung EA (`OnInit/OnTimer/OnDeinit`), khám phá + phân loại + lọc symbol, quét xoay vòng, tính SMA/BB/RSI/ATR từ `CopyRates`, DryRun, bảng trạng thái, self-test đối chiếu `iMA/iBands/iRSI/iATR` + bảng tick value | Đã giao |
| 2 | Chấm điểm bias đa khung, tìm vùng Entry (confluence), setup chờ hồi/phá vỡ, SL/TP/RR, hủy kèo, hai tầng ngưỡng, nhóm tương quan, phơi nhiễm tiền tệ, xếp hạng top K, giới hạn tin/ngày, cảnh báo tin tức | Đã giao |
| 3 | Quản lý vốn: lot theo SL thật, `CẢNH BÁO RỦI RO`, tổng rủi ro, "đang chờ, vượt ngưỡng rủi ro" | Phần lớn đã làm sớm ở GĐ2 (mục 4.6 yêu cầu tính tổng rủi ro). GĐ3 còn lại: đối chiếu số liệu thật, tinh chỉnh |
| 4 | Telegram thật (`WebRequest`, hàng đợi, retry, rate limit, tin tổng hợp + chi tiết), lưu trạng thái setup ra file, chống báo trùng khi khởi động lại, giới hạn tin/ngày, tóm tắt cuối ngày | **Đã giao** |
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
  Include/Telegram.mqh     WebRequest sendMessage, tách tin, hàng đợi, retry, xử lý 429/4014/4060, DryRun
  Include/SelfTest.mqh     Đối chiếu chỉ báo tự tính với iMA/iBands/iRSI/iATR + bảng tick value (thêm)
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
| | `InpMaxTotalRiskPct` | 5 | Tổng rủi ro tối đa (dùng từ GĐ3) |
| Kiểm thử | `InpSelfTest` | false | Đối chiếu chỉ báo + in bảng tick value |
| | `InpSelfTestSymbols` | BTCUSD,XAUUSD,EURUSD,USDJPY,US30 | Ít nhất 3 nhóm tài sản |
| | `InpLogSnapshots` | true | In snapshot chỉ báo của ưu tiên/phụ mỗi giờ |

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

Input của GĐ5 (đọc vùng vẽ tay) sẽ được thêm khi giao giai đoạn đó.

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
- Các mức giá được xét: SMA50 H4, SMA200 H1, SMA50 H1, swing H1 (3 nến mỗi bên), swing H4 (2 nến mỗi bên), và vùng vẽ tay (GĐ5). Swing là fractal: đỉnh cao hơn N nến mỗi bên.
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
| Lỗi 4014/4060 khi gửi Telegram | Whitelist `https://api.telegram.org` (mục 4) rồi gắn lại EA |
| `Telegram từ chối (HTTP 401...)` | Token sai: lấy lại token từ @BotFather |
| `Telegram từ chối (HTTP 400: chat not found)` | Chat id sai, hoặc chưa nhắn cho bot / chưa thêm bot vào group |
| `Telegram từ chối (HTTP 403...)` | Bạn đã chặn bot hoặc bot bị kick khỏi group |
| Muốn xóa toàn bộ setup đã lưu | Gỡ EA, xóa `MQL5/Files/SignalEA/state_<số TK>.txt`, rồi gắn lại EA |

# Kế hoạch kiểm thử

Tài liệu này được cập nhật theo từng giai đoạn. Ký hiệu: ☐ chưa kiểm, ☑ đạt.

## Giai đoạn 1: khung EA, universe, chỉ báo, DryRun

### T1.1 Biên dịch (nghiệm thu 1, 6)
- ☐ `metaeditor64.exe /compile:"...\SignalEA.mq5" /log` cho kết quả **0 errors**, không có cảnh báo nghiêm trọng. Gửi lại cho tôi file `SignalEA.log` nếu có lỗi.
- ☐ Tìm trong toàn bộ thư mục: không có `OrderSend`, `CTrade`, `PositionClose`, `OrderModify`, `#import` hoặc `.dll`.

### T1.2 Khởi động và tin khởi động (nghiệm thu 2)
Input: `InpDryRun=true`, `InpLogLevel=INFO`. Gắn EA lên một chart bất kỳ.
- ☐ Log có dòng `=== SignalEA v0.1.0 (Giai đoạn 1) khởi động ...` với độ lệch giờ server hợp lý (Exness: GMT+0).
- ☐ Log có các dòng `[DRYRUN]` của tin "EA ĐÃ CHẠY": tài khoản, số dư, danh sách ưu tiên/phụ, số symbol khám phá theo nhóm, thời gian GMT+7.
- ☐ Bảng trạng thái hiện ở góc trái chart.

### T1.3 Universe: nhận/loại kèm lý do (nghiệm thu 8)
- ☐ Log có `=== Universe: chế độ ALL_BROKER_SYMBOLS | nhận X | loại Y ...`.
- ☐ Các dòng `Nhận - Forex (..)`, `Nhận - Kim loại (..)`, ... BTCUSD, XAUUSD có nhãn `(Ưu tiên)`; ETHUSD, XAGUSD có nhãn `(Phụ)`.
- ☐ Các dòng `Loại - <lý do> (n): ...`, ví dụ `nhóm Cổ phiếu đang tắt`, `hậu tố khác 'm'`, `không cho phép giao dịch đầy đủ`.
- ☐ File `MQL5/Files/SignalEA/universe.csv` liệt kê từng symbol, kết quả (NHAN/LOAI), lý do, nhóm và path. **Hãy mở file và kiểm tra cột nhóm**: nếu có symbol bị phân loại sai, gửi tôi vài dòng để chỉnh từ khóa.
- ☐ Đặt `InpPrioritySymbols="BTCUSD,ABCXYZ"`: log báo `[LỖI] Symbol Ưu tiên 'ABCXYZ' không tồn tại trên broker - bỏ qua.`, EA vẫn chạy.
- ☐ Đặt `InpUniverseMode=WATCHLIST_ONLY`: chỉ còn 4 symbol.
- ☐ Đặt `InpUniverseMode=MARKET_WATCH`: chỉ gồm ưu tiên + phụ + các symbol đang có trong Market Watch.

### T1.4 Quét xoay vòng và nến H1 mới
Input: `InpLogLevel=DEBUG` trong 1–2 giờ.
- ☐ Sau mỗi lần sang giờ server mới, ưu tiên/phụ được xử lý ở chu kỳ đầu tiên (xem các dòng `[SNAPSHOT]`).
- ☐ Bảng trạng thái: `Chu kỳ #n: ≤5 symbol, ... ms`. Thời gian mỗi chu kỳ thường dưới 2000 ms.
- ☐ Log `Hoàn tất vòng quét giờ ... sau X phút: phân tích A/B symbol | OK .. | ngoài phiên .. | spread rộng .. | vượt khả năng vốn ..`.
- ☐ Trong cùng một giờ, symbol đã xử lý không bị phân tích lại (không có thêm `[SNAPSHOT]` của symbol đó).
- ☐ Cuối tuần: Forex/chỉ số có trạng thái "ngoài phiên", crypto vẫn được quét.

### T1.5 Bộ lọc
- ☐ Spread: tạm đặt `InpMaxSpreadAtrPct=0.1`, nhiều symbol bị loại với lý do `spread ... = x% ATR(H1) > 0.1%`. Trả lại 15 sau khi kiểm tra.
- ☐ Vốn: các chỉ số lớn (ví dụ US30, JP225) hoặc symbol có lot tối thiểu lớn bị loại với lý do `lot tối thiểu ... rủi ro ≈ $X (Y%) > 4.0% số dư`.
- ☐ Lịch sử: symbol mới thêm vào có trạng thái "đang tải lịch sử", sau đó OK hoặc "thiếu lịch sử - bỏ qua giờ này". Không có lỗi crash.

### T1.6 Chỉ báo khớp iMA/iBands/iRSI/iATR (nghiệm thu 4, 9)
Input: `InpSelfTest=true`, `InpSelfTestSymbols="BTCUSD,XAUUSD,EURUSD,USDJPY,US30"` (Crypto, Kim loại, Forex, Chỉ số).
- ☐ Sau 1–3 chu kỳ timer, log có hai dòng `[SELFTEST] <sym> <TF> ...` cho mỗi symbol × H1/H4/D1, với `=> KHỚP`.
- ☐ Dòng tổng kết `[SELFTEST] KẾT QUẢ: N khớp, 0 lệch | 5 symbol, 4 nhóm tài sản (...) | ĐẠT`.
- ☐ Mở `MQL5/Files/SignalEA/selftest_values.csv` và so với CSV của `ExportChartData.mq5` ở cùng thời gian nến. Sai số chỉ nên ở mức làm tròn. Lưu ý: giá trị trong self-test là của **nến đã đóng gần nhất** (shift 1).
- Ghi chú: RSI tự tính dùng khoảng 320 nến nên có thể lệch iRSI (tính trên toàn bộ lịch sử) ở chữ số thập phân rất nhỏ. Dung sai của RSI là 0.05.

### T1.7 Tick value và lot (nghiệm thu 5)
Vẫn với `InpSelfTest=true`:
- ☐ Các dòng `[RISK] <sym> | tick size .. | tick value .. (lỗ ..) USD/lot | contract .. | lot min .. step .. max ..`.
- ☐ Các dòng `[RISK] <sym> | ATR(H4) .. | SL .. (= n tick) | lot min rủi ro $X (Y%) | lot cho 1.50% ($15): L`.
- ☐ Đối chiếu thủ công với thông số hợp đồng trên Exness. Ví dụ XAUUSD có contract 100 oz, nên giá đi 1.00 với 0.01 lot = $1. Vậy SL cách 20.0 với 0.01 lot có rủi ro khoảng $20.

### T1.8 Ổn định và tài nguyên (nghiệm thu 7)
Chạy EA ≥ 24 giờ trên VPS với `ALL_BROKER_SYMBOLS`:
- ☐ Task Manager: RAM của `terminal64.exe` không tăng dần theo giờ (chênh lệch giữa giờ thứ 2 và giờ thứ 24 nhỏ).
- ☐ CPU nền thấp. Terminal không bị đơ khi kéo chart.
- ☐ `max` trong bảng trạng thái (thời gian chu kỳ lâu nhất) chỉ vài giây.
- ☐ Market Watch không phình quá `InpMaxMarketWatch`.
- ☐ Gỡ EA: log `Đã gỡ n symbol do EA thêm khỏi Market Watch` và `Đã giải phóng .. handle` (nếu dùng handle).

### T1.9 Lỗi không làm dừng EA (ràng buộc 5)
- ☐ Ngắt mạng VPS khoảng 1 phút: bảng hiện `MẤT KẾT NỐI ...`, có mạng lại thì EA tự quét tiếp.
- ☐ Nhập input sai (ví dụ `InpTimerSeconds=1`): EA từ chối khởi động với lỗi rõ ràng (INIT_PARAMETERS_INCORRECT).

## Giai đoạn 2: bias, setup, SL/TP, quy tắc ưu tiên/tương quan, rủi ro

Input chung: `InpDryRun=true`, `InpLogSnapshots=true`. Nên dùng `InpLogLevel=DEBUG` trong lúc kiểm tra.

### T2.1 Biên dịch
- ☐ 0 errors. Gửi lại `SignalEA.log` nếu có lỗi hoặc cảnh báo.
- ☐ Tin khởi động có thêm dòng `Ngưỡng: Ưu tiên điểm >= 5 ...` và `Rủi ro: 1.5%/setup ...`. Log có dòng `Nhóm tương quan: KIM_LOAI: ... | CRYPTO: ...`.

### T2.2 Bias từng khung (quy tắc 3/4)
- ☐ Với XAUUSD và BTCUSD, mỗi giờ log có `[SNAPSHOT] Bias: MN1 .. | W1 .. | D1 .. | H4 .. | H1 ..  (điểm x/9)` và `[SNAPSHOT] Phân tích: ...`.
- ☐ Kiểm tra tay 1–2 khung trên chart (SMA20, SMA50, RSI14, nến đã đóng gần nhất):
  - Có ít nhất 3 trong 4 điều kiện Close > SMA20, Close > SMA50, SMA20[1] > SMA20[4], RSI > 50 thì khung là "tăng".
  - Có ít nhất 3 điều kiện ngược lại thì là "giảm".
  - Còn lại là "0".
- ☐ Bảng trạng thái hiện `bias +x` hoặc `bias -x` cho ưu tiên/phụ.

### T2.3 Setup chờ hồi
- ☐ Khi có setup, log có `[XAUUSD] SETUP MỚI SELL chờ hồi | điểm 6/9 | RR 1.70 | ...`, kèm tin `[DRYRUN]` theo đúng mẫu ở README mục 6.7.
- ☐ Đối chiếu trên chart:
  - Vùng Entry nằm phía trên giá (Sell) hoặc phía dưới giá (Buy), cách giá không quá 2 × ATR(H4).
  - Dòng "Lý do" nêu ít nhất 2 yếu tố, và các yếu tố đó (SMA/swing) thực sự nằm gần vùng.
  - SL nằm ngoài swing gần nhất. TP1/TP2 trùng với đỉnh/đáy H4 hoặc D1.
- ☐ Khi không có setup, dòng `Phân tích:` nêu rõ lý do, ví dụ `bias 3/9 chưa đạt ngưỡng 5`, `RR TP1 1.10 < 1.30`, `không có vùng hội tụ >= 2 yếu tố`.

### T2.4 Setup phá vỡ
- ☐ Chỉ xuất hiện sau khi một nến H4 vừa đóng phá đỉnh/đáy swing H4, và cùng hướng bias. Lý do có dạng `H4 đóng 4120.5 dưới đáy swing H4 4125.0`.
- ☐ Kiểm tra nhanh: tạm đặt `InpEnablePullback=false` để chỉ còn setup phá vỡ.

### T2.5 Hai tầng ngưỡng, top K, giới hạn ngày
- ☐ Setup Phụ/Khám phá chỉ xuất hiện khi |điểm| ≥ 7 và RR ≥ 1.8.
- ☐ Cuối vòng quét giờ: log có `Hoàn tất vòng quét ...`, sau đó là `[TỔNG HỢP] n setup mới` (khi có từ 2 setup) hoặc một tin chi tiết (khi chỉ có 1 setup).
- ☐ Mỗi vòng có tối đa 3 setup Phụ/Khám phá. Các ứng viên còn lại có log `ứng viên bỏ qua: ngoài top 3`.
- ☐ Thử giới hạn ngày: đặt `InpMaxNewPerDay=1`, tạm hạ `InpMinScoreOther=5` và `InpMinRROther=1.3` để có nhiều ứng viên. Từ tin thứ 2 trở đi phải có log `đã đạt giới hạn 1 tin/ngày`, còn setup ưu tiên vẫn được báo. Trả lại giá trị cũ sau khi kiểm tra.

### T2.6 Tương quan và phơi nhiễm
- ☐ Khi XAUUSD có setup đang mở, XAGUSD (phụ) không được báo: log `cùng nhóm KIM_LOAI với setup ưu tiên XAUUSD đang hoạt động`.
- ☐ Hai symbol khám phá cùng nhóm (ví dụ US30 và US500): chỉ symbol đầu tiên được báo, symbol sau có log `nhóm CHI_SO_MY đã có setup ...`.
- ☐ Forex: tạm hạ ngưỡng để có nhiều setup cùng bán USD. Từ setup thứ 3 trở đi có log `phơi nhiễm: đã có 2 setup MUA/BÁN USD`.

### T2.7 Rủi ro
- ☐ `Lot gợi ý` khớp với cách tính tay: lot = 1.5% số dư / (khoảng cách SL / tick size × tick value), làm tròn xuống.
- ☐ Symbol mà lot tối thiểu đã vượt 1.5%: tin có nhãn `CẢNH BÁO RỦI RO` và dòng `Lot tối thiểu 0.01 rủi ro ≈ $X (Y%) vượt ngưỡng 1.5%`.
- ☐ Lot tối thiểu vượt 4%: không có tin, log có `setup bị loại: lot tối thiểu rủi ro ≈ ... > ngưỡng cứng 4.0%`.
- ☐ Tạm đặt `InpMaxTotalRiskPct=2`. Từ setup thứ 2 trở đi, tin có nhãn `ĐANG CHỜ, VƯỢT NGƯỠNG RỦI RO` và setup đó không được cộng vào dòng "Tổng rủi ro".

### T2.8 Vòng đời
- ☐ Giá chạm vùng Entry: có tin `GIÁ VÀO VÙNG ENTRY`, bảng trạng thái đổi sang `đã vào vùng`.
- ☐ H4 đóng vượt SL: có tin `HỦY KÈO` với lý do `H4 đóng X trên mức hủy Y`.
- ☐ Sau 24h giá vẫn chưa vào vùng: có tin `HẾT HẠN`.
- ☐ Trong 240 phút sau khi setup đóng, symbol đó không có setup mới (log debug `cooldown`).
- ☐ Một symbol chỉ có tối đa 1 setup mở. Phân tích các giờ sau không báo lại setup đó (chống spam).

### T2.9 Tin tức
- ☐ Trước tin USD mức cao (NFP, CPI, FOMC) khoảng 2 giờ, tin setup có dòng `Lưu ý tin mức cao trong 2 giờ tới (GMT+7): USD ... lúc HH:MM`.
- ☐ Trong Strategy Tester (không có lịch): không có lỗi nào.

### T2.10 Hiệu năng
- ☐ Chạy cả ngày với `ALL_BROKER_SYMBOLS`: thời gian chu kỳ max vẫn chỉ vài giây, RAM không tăng dần.

## Giai đoạn 4: Telegram thật, trạng thái, tóm tắt ngày

### T4.1 Gửi tin thử (nghiệm thu 3)
- ☐ Whitelist `https://api.telegram.org` (README mục 4).
- ☐ Đặt `InpDryRun=false`, `InpTgEnabled=true`, nhập token và chat id rồi gắn EA. Điện thoại nhận tin `[SignalEA] EA ĐÃ CHẠY`, tiếng Việt hiển thị đúng dấu.
- ☐ Log có `[TG] đã gửi: [SignalEA] EA ĐÃ CHẠY ...`. Bảng trạng thái có dòng `Telegram: đã gửi 1, lỗi 0, chờ 0 | OK hh:mm`.
- ☐ Trong toàn bộ log không xuất hiện token.

### T4.2 Lỗi cấu hình
- ☐ Bỏ URL khỏi whitelist rồi gắn lại EA: log có `WebRequest bị chặn (lỗi 4014 hoặc 4060)` kèm hướng dẫn, sau đó là các lần thử lại 5s/15s/45s. Hết lượt thì tin bị bỏ và nội dung được in ra log. EA vẫn chạy bình thường.
- ☐ Token sai (ví dụ đổi 1 ký tự): log `Telegram từ chối (HTTP 401 ...)` và không thử lại.
- ☐ Chat id sai: log `HTTP 400 ... chat not found`.
- ☐ `InpTgEnabled=true`, `InpDryRun=false` nhưng token trống: cảnh báo một lần, tin chỉ in ra log.

### T4.3 Hàng đợi, tách tin, giới hạn tốc độ
- ☐ Khi có nhiều tin cùng lúc (khởi động + tổng hợp + chi tiết), các tin đến **đúng thứ tự** và cách nhau ít nhất khoảng 3 giây.
- ☐ Tạm đặt `InpTgMaxChars=300`: một tin dài được tách thành nhiều tin và không mất dòng nào.
- ☐ (Nếu gặp) HTTP 429: log `Telegram giới hạn tốc độ (429) - chờ N giây.`, sau đó tin vẫn được gửi.

### T4.4 Lưu trạng thái và không báo trùng (nghiệm thu 3)
- ☐ Khi có ít nhất một setup đang mở, file `MQL5/Files/SignalEA/state_<số TK>.txt` tồn tại, có dòng `H|1|...` và dòng `S|<id>|...`.
- ☐ Gỡ EA rồi gắn lại (hoặc khởi động lại terminal):
  - Log có `Đã nạp trạng thái: n setup (m đang mở)`.
  - Tin khởi động ghi `Setup đang mở (khôi phục từ file trạng thái): m`.
  - **Không có tin SETUP nào bị gửi lại** cho các symbol đó, kể cả khi EA phân tích lại ngay trong giờ hiện tại (log debug `đang có setup ...`).
- ☐ Setup đã ở trạng thái "đã vào vùng" thì sau khi khởi động lại không gửi lại tin `GIÁ VÀO VÙNG ENTRY`.
- ☐ Tắt EA qua một nến H4 đóng vượt SL rồi bật lại: có tin `HỦY KÈO` (EA xét cả nến đã bỏ lỡ).
- ☐ Đổi `InpTimerSeconds` hoặc đổi khung chart (EA được nạp lại): trạng thái vẫn giữ nguyên.
- ☐ Bộ đếm `tin phụ/khám phá hôm nay x/10` được giữ qua lần khởi động lại trong cùng ngày, và về 0 khi sang ngày mới (GMT+7).

### T4.5 Tóm tắt cuối ngày
- ☐ Tạm đặt `InpDailySummaryHour` bằng giờ hiện tại (GMT+7): trong vòng 30 giây nhận tin `TÓM TẮT NGÀY dd/mm`, có số setup mới, số vào vùng/hủy/hết hạn/đạt mục tiêu, danh sách setup đang mở và tổng rủi ro.
- ☐ Khởi động lại EA trong cùng ngày: không gửi lại tóm tắt.

### T4.6 DryRun cả ngày (nghiệm thu 8)
- ☐ Chạy `InpDryRun=true` 24 giờ với `ALL_BROKER_SYMBOLS`. Đếm các dòng `[DRYRUN] ----- Tin Telegram`:
  - Tin SETUP của Phụ/Khám phá không vượt 10 (trong log có `đã đạt giới hạn ...` nếu chạm ngưỡng).
  - Mỗi tin tổng hợp có tối đa 3 setup.
  - Không có setup nào bị báo hai lần.
- ☐ RAM/CPU ổn định (như T1.8). Bảng trạng thái hiện `max` thời gian chu kỳ chỉ vài giây.

## Giai đoạn 3: quản lý vốn, đối chiếu tick value (nghiệm thu 5)

### T3.1 Self-test rủi ro
Input: `InpSelfTest=true`, `InpSelfTestSymbols="BTCUSD,XAUUSD,EURUSD,USDJPY,US30,JP225"`. JP225 dùng để thử quy đổi JPY sang USD; nếu tên trên Exness khác thì thay bằng tên đúng.
- ☐ Với mỗi symbol, log có các dòng:
  - `[RISK] <sym> | tick size .. | tick value .. (lỗ ..) USD/lot | contract .. | lot min/step/max`.
  - `[RISK] <sym> | KHỚP | kiểm chéo: tick size × contract × tỷ giá ... = ...; broker ...; lệch x%` (hoặc `LỆCH` / `HỎNG` / `không kiểm được`, kèm lý do).
  - `[RISK] <sym> | SL cách ... = N tick × ... = $/lot | ngân sách 1.50% × $1000 = $15 → x lot → làm tròn xuống step 0.01 (min 0.01) = L lot | rủi ro $ (%)`.
- ☐ Đối chiếu tay với **Contract specification** trên Exness (chuột phải symbol trong Market Watch → Specification): contract size, tick size, volume min/step khớp với log.
- ☐ Kiểm tra bằng tay: giá đi 1 điểm giá với 1 lot thì lỗ = contract size × tỷ giá. Ví dụ XAUUSD (contract 100): 1.00 giá × 1 lot = $100, nên 0.01 lot = $1.
- ☐ Các symbol Forex/kim loại/crypto/chỉ số đều ra `KHỚP`. Gửi tôi các dòng `LỆCH` nếu có.

### T3.2 Lot và cảnh báo trên setup thật
- ☐ Mỗi tin SETUP có một dòng `[RISK] <sym> <id>: ...` tương ứng trong log. Lot trong tin bằng lot trong dòng log, và lot × khoảng cách SL × tick value / tick size khớp "rủi ro ≈ $".
- ☐ Lot luôn **làm tròn xuống** theo volume step: rủi ro thực tế ≤ 1.5%, trừ khi có nhãn CẢNH BÁO RỦI RO.
- ☐ CẢNH BÁO RỦI RO: lot = lot tối thiểu, dòng `Lot tối thiểu 0.01 rủi ro ≈ $X (Y%) vượt ngưỡng 1.5%`, và Y nằm trong khoảng 1.5–4%.
- ☐ Dòng "Tổng rủi ro các setup đang mở" bằng tổng "rủi ro ≈ $" của các setup đang mở (không tính setup "đang chờ, vượt ngưỡng").

### T3.3 Trường hợp biên
- ☐ Ngay sau khi terminal khởi động (số dư chưa có): không có setup nào, log `setup bị loại: chưa đọc được số dư tài khoản` (nếu có ứng viên).
- ☐ (Nếu có tài khoản demo không phải USD) số tiền hiển thị theo tiền tệ tài khoản, ví dụ `21.00 EUR`, và kiểm chéo vẫn `KHỚP`.

## Giai đoạn 5: quy trình nghiệm thu đầy đủ

Làm lần lượt; bước nào lỗi thì gửi log cho tôi trước khi làm tiếp. Bảng đối chiếu 9 tiêu chí nằm ở README mục 9.

| Bước | Việc | Input chính | Mục kiểm | Tiêu chí |
|---|---|---|---|---|
| 1 | Biên dịch, gửi `SignalEA.log` nếu có lỗi hoặc cảnh báo | | T1.1 | 1, 6 |
| 2 | Gắn lên 1 chart, xem log khởi động, universe, `universe.csv` | `InpDryRun=true` | T1.2, T1.3 | 8 |
| 3 | Self-test chỉ báo và rủi ro | `InpSelfTest=true` | T1.6, T1.7, T3.1 | 4, 5, 9 |
| 4 | Chạy 2–3 giờ, xem `[SNAPSHOT]`, `[DRYRUN]`, `[RISK]` của BTCUSD/XAUUSD | `InpLogLevel=DEBUG` | T1.4, T2.2–T2.4, T3.2 | 2, 5 |
| 5 | Thử các quy tắc bằng cách tạm hạ ngưỡng (top K, giới hạn ngày, tương quan, tổng rủi ro) | xem từng mục | T2.5–T2.8 | 8 |
| 6 | Bật Telegram thật, thử lỗi cấu hình | `InpDryRun=false` | T4.1–T4.3 | 3 |
| 7 | Khởi động lại EA khi đang có setup mở | | T4.4 | 3 |
| 8 | Chạy 24h, theo dõi RAM/CPU, đếm tin | `ALL_BROKER_SYMBOLS` | T1.8, T2.10, T4.6 | 7, 8 |

Thông tin nên gửi lại cho tôi:
1. `SignalEA.log` (biên dịch).
2. Đoạn log từ lúc khởi động đến hết vòng quét đầu tiên.
3. Các dòng `[SELFTEST]` và `[RISK]`.
4. `MQL5/Files/SignalEA/universe.csv` (hoặc vài dòng có nhóm bị phân loại sai).

## Giai đoạn 6: cầu nối Python + Claude API

### T6.1 Test tự động (không gọi mạng)
- ☐ Trong thư mục `ai-bridge`: `pip install -r requirements.txt` rồi `python -m unittest -v test_signal_ai_bridge.py` → 12 test OK. (Tôi đã chạy đạt trên môi trường phát triển với `anthropic` 1.13.)

### T6.2 EA xuất JSON
- ☐ Đặt `InpAiExport=true`. Log khởi động có `Cầu nối AI: xuất JSON vào ...`.
- ☐ Khi có setup mới: log có `[AI] Đã xuất NEW_SETUP -> MQL5\Files\SignalEA\ai_queue\<id>-NEW_SETUP.json`. Mở file thấy JSON hợp lệ (có thể dán vào jsonlint.com) với đủ các khối `setup`, `bias`, `indicators`, `risk`.
- ☐ Khi giá vào vùng Entry: có file `<id>-ENTRY_TOUCHED.json`.
- ☐ Setup "ĐANG CHỜ, VƯỢT NGƯỠNG RỦI RO" không tạo file JSON.

### T6.3 Luồng file, không tốn tiền
- ☐ `python signal_ai_bridge.py --no-api --dry-run --once`: in prompt cho từng file và chuyển file sang `ai_queue/done/`.

### T6.4 Gọi Claude thật
- ☐ `python signal_ai_bridge.py --dry-run --once` với `sample_event.json`: in nhận định gồm 4 đoạn (Nhận định / Điểm ủng hộ / Rủi ro cần để ý / Gợi ý xử lý), tiếng Việt, không Markdown. Có dòng `[TOKEN] ... input N | output M | ước tính $x | hôm nay 1/20 lần`.
- ☐ Bỏ `--dry-run`: Telegram nhận tin `[XAUUSD] NHẬN ĐỊNH AI - SETUP SELL (chờ hồi) - Nhóm: Ưu tiên`.
- ☐ Đặt sai `ANTHROPIC_API_KEY`: script dừng với thông báo kiểm tra API key (mã thoát 2), file JSON vẫn nằm trong hàng đợi.

### T6.5 Giới hạn và chi phí
- ☐ `--max-calls 1`, đặt 2 file vào hàng đợi: file thứ 2 vào `skipped/`, Telegram nhận đúng 1 tin báo đạt giới hạn.
- ☐ Sang ngày mới (GMT+7): bộ đếm trong `ai_bridge_state.json` về 0.
- ☐ Sau vài ngày, đối chiếu tổng chi phí ước tính trong log với số liệu trên console.anthropic.com.

## Giai đoạn 7: nhật ký kết quả tín hiệu

### T7.1 Test tự động script phân tích
- ☐ `cd tools` rồi `python -m unittest -v test_analyze_journal.py` → 6 test OK. (Đã chạy đạt trên môi trường phát triển.)

### T7.2 Ghi nhật ký trong EA
- ☐ Khi khởi động, log có `[JOURNAL] Nạp n kèo đang theo dõi; tích lũy m kèo đã đóng.`
- ☐ Bảng trạng thái có dòng `Nhật ký: ... đang theo dõi x (chờ a, chạy b)`.
- ☐ Sau khi một setup đóng (hủy, hết hạn, chạm SL/TP): log có `[JOURNAL] <id>: <outcome> (A ...R | B ...R | C ...R)`, và file `MQL5/Files/SignalEA/journal_<login>.csv` có thêm 1 dòng. Mở bằng Excel thấy đúng cột, tiếng Việt hiển thị đúng.

### T7.3 Đối chiếu tay 2–3 kèo (quan trọng)
- ☐ Với một kèo `SL` hoặc `TP1`/`TP2`, mở chart M1 của symbol và tìm đúng thời điểm `fill_time`:
  - giá có chạm `entry` không;
  - sau đó SL hay TP1 bị chạm trước;
  - `r_a`/`r_b`/`r_c` có đúng với `rr1`/`rr2` hoặc −1 không.
- ☐ Với một kèo `NOT_FILLED`: giá chưa từng chạm `entry` trước khi setup đóng.
- ☐ Kèo `TP1_SL` ở kịch bản C: `r_c` = 0.5 × rr1 (nửa sau hòa vốn).

### T7.4 Khởi động lại
- ☐ Gỡ EA khi đang có kèo "đang chạy", chờ 30–60 phút rồi gắn lại: kèo vẫn được theo dõi tiếp (EA đọc bù nến M1 đã bỏ lỡ), không bị ghi trùng vào CSV.

### T7.5 Phân tích
- ☐ Sau vài tuần: `python tools\analyze_journal.py journal_<login>.csv` in ra số liệu tổng, ba kịch bản và các bảng tách nhóm. Nếu chưa đủ 30 kèo khớp, script phải in cảnh báo mẫu nhỏ.

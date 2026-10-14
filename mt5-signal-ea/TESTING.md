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

## Giai đoạn 2–6 (sẽ chi tiết hóa khi giao)
- GĐ2: kiểm tra bias từng khung bằng tay trên chart; setup chờ hồi/phá vỡ; RR; hai tầng ngưỡng; nhóm tương quan; phơi nhiễm tiền tệ; top K; DryRun in đúng mẫu `SETUP MỚI` cho BTCUSD/XAUUSD (nghiệm thu 2).
- GĐ3: `CẢNH BÁO RỦI RO`, tổng rủi ro, "đang chờ, vượt ngưỡng rủi ro".
- GĐ4: gửi tin thật, lỗi 4060, retry, tự tách tin, giới hạn tin/ngày; khởi động lại EA không báo trùng setup (nghiệm thu 3); chạy DryRun cả ngày không gây bão tin (nghiệm thu 8).
- GĐ5: vẽ rectangle/trendline trên chart và kiểm tra yếu tố "vùng vẽ tay" có trong lý do của setup.

# Backtest SignalEA bằng Python

Chạy lại **đúng logic tín hiệu của SignalEA** trên dữ liệu lịch sử, để có hàng trăm mẫu ngay thay vì chờ nhiều tuần chạy DryRun. Kết quả được ghi theo **cùng định dạng với nhật ký** (`journal_<login>.csv`), nên dùng chung script `tools/analyze_journal.py` để phân tích.

Chỉ dùng thư viện chuẩn của Python 3.10+, không cần cài thêm gì.

## 1. Lấy dữ liệu từ MT5

1. Chép `Scripts/ExportHistory.mq5` vào `MQL5/Scripts/`, biên dịch (F7) rồi kéo thả lên một chart bất kỳ.
2. Nhập các input:
   - `InpSymbols`: danh sách symbol cần test;
   - `InpYears`: số năm lịch sử cho H1 trở lên (mặc định 3);
   - `InpM1Days`: số ngày nến M1 (mặc định 180).
3. Script ghi vào `MQL5/Files/SignalEA/history/`:
   - `<SYM>_MN1|W1|D1|H4|H1|M1.csv`: dạng `time;open;high;low;close;spread`. `time` là giây Unix theo giờ server; `spread` tính bằng point.
   - `<SYM>_spec.csv`: tick size, tick value, contract, lot min/step/max, tiền tệ, path, kiểu tính margin, độ lệch giờ server.
4. Nếu số nến ít hơn mong đợi: vào **Tools → Options → Charts → Max bars in chart**, đặt "Unlimited", mở chart symbol đó để MT5 tải lịch sử, rồi chạy lại script.

> M1 dùng để mô phỏng chính xác lúc khớp lệnh và chạm SL/TP. Với khoảng thời gian không có M1, backtest tự dùng nến H1 (thô hơn, vì quy tắc "SL và TP cùng nến tính SL trước" áp dụng cho cả nến H1).

## 2. Chạy

```
cd backtest
python run_backtest.py --data-dir "C:\...\MQL5\Files\SignalEA\history"
python run_backtest.py --data-dir data --symbols XAUUSD,BTCUSD --start 2025-01-01 --end 2025-12-31 --out trades_2025.csv
python run_backtest.py --data-dir data --set min_score_other=6 --set enable_breakout=false --scenario C
```

| Tham số | Ý nghĩa |
|---|---|
| `--data-dir` | Thư mục dữ liệu xuất từ MT5 |
| `--symbols` | Danh sách symbol (mặc định: mọi symbol có file H1) |
| `--start`, `--end` | Khoảng thời gian, dạng YYYY-MM-DD theo giờ server |
| `--out` | File CSV kết quả (mặc định `backtest_trades.csv`) |
| `--set ten=gia_tri` | Đổi tham số chiến lược, dùng được nhiều lần. Tên tham số xem class `Params` trong `bt_strategy.py`; mặc định trùng input của EA |
| `--no-m1` | Chỉ dùng H1 để mô phỏng |
| `--scenario A/B/C` | Kịch bản thoát lệnh dùng cho bảng chi tiết |
| `--no-report` | Không in báo cáo |

Kết quả in ra gồm:
- Bộ đếm: số lượt phân tích, lý do bị loại (bias chưa đạt, không có vùng hội tụ, RR thấp, spread, vốn, tương quan, phơi nhiễm, top K, giới hạn ngày...), số setup theo symbol.
- Báo cáo của `analyze_journal.py`: tỷ lệ khớp; tỷ lệ thắng, kỳ vọng theo R kèm khoảng tin cậy 95%; profit factor; chuỗi thua dài nhất; drawdown; bảng tách theo tầng, nhóm tài sản, loại setup, hướng, điểm bias, symbol.

**Chạy thử khi chưa có dữ liệu thật:**
```
python make_sample_data.py --out sample_data
python run_backtest.py --data-dir sample_data
```
Dữ liệu giả lập là bước ngẫu nhiên, **kết quả trên đó không nói gì về EA**. Nó chỉ để kiểm tra bộ công cụ chạy được.

## 3. Mức độ giống EA

Chuyển nguyên logic từ mã MQL5:

| Phần | Nguồn |
|---|---|
| SMA / BB / RSI / ATR, giới hạn cửa sổ 320 nến | `Indicators.mqh` |
| Bias 3/4, trọng số, ngưỡng theo tầng | `Analysis.mqh` |
| Swing (fractal), vùng hội tụ, phá vỡ H4, SL/TP/RR | `Analysis.mqh` |
| Lọc lịch sử, spread ≤ 15% ATR(H1), lọc vốn (lot min với 1×ATR H4 và với SL thật) | `SignalEA.mq5`, `Signals.mqh` |
| 1 setup/symbol, cooldown, tương quan, phơi nhiễm tiền tệ, tổng rủi ro ("đang chờ"), ưu tiên báo ngay, top K, giới hạn tin/ngày | `Signals.mqh` |
| Vòng đời setup: vào vùng, hủy khi H4 đóng vượt SL, lỡ kèo, hết hạn, đạt mục tiêu | `Signals.mqh` |
| Mô phỏng kết quả: khớp tại `entry_ref`, cộng spread, SL trước khi cùng nến, 3 kịch bản A/B/C, MFE/MAE | `Journal.mqh` |

Không nhìn trước tương lai (look-ahead): mỗi lần phân tích tại giờ T chỉ dùng các nến **đã đóng** trước T, và swing chỉ được công nhận khi các nến bên phải nó đã đóng.

**Khác biệt đã biết so với EA chạy thật:**
- EA phân tích ở lần quét đầu tiên sau khi nến H1 đóng, với bid/ask lúc đó. Backtest dùng giá đóng cửa H1 và spread của nến. Với nhóm khám phá, EA thực tế có thể trễ tới khoảng 20 phút do quét xoay vòng.
- EA theo dõi setup mỗi 30 giây; backtest theo từng nến M1 (hoặc H1).
- Không có lọc tin tức (backtest không có dữ liệu lịch kinh tế), không có giới hạn Market Watch, không xét phiên giao dịch (có nến thì coi là đang giao dịch).
- Tick value lấy cố định tại lúc xuất dữ liệu. Với symbol có tiền tệ lợi nhuận khác USD, tick value thật thay đổi theo tỷ giá.
- Số dư cố định (`balance`, mặc định 1000), không cộng dồn lãi/lỗ.
- Chưa tính trượt giá.
- Mã MQL5 của EA chưa được biên dịch. "Giống EA" ở đây nghĩa là giống mã nguồn hiện tại. Khi EA chạy được, nên so vài kèo trong `journal_<login>.csv` thật với kèo cùng thời điểm trong backtest.

## 4. Dùng backtest đúng cách (tránh tự lừa mình)

1. **Chạy với tham số mặc định trước**, đây là thứ EA đang làm. Đừng chỉnh tham số trước khi xem kết quả gốc.
2. **Chia dữ liệu.** Ví dụ có 3 năm: dùng 2 năm đầu (`--start/--end`) để thử thay đổi. Năm cuối **chỉ chạy một lần** sau khi đã chọn xong cấu hình. Nếu kết quả năm cuối kém hẳn thì cấu hình đó đang khớp quá mức với dữ liệu cũ.
3. **Ít nhất 100 kèo khớp** trước khi tin con số, và nhìn **cận dưới khoảng tin cậy 95%** của kỳ vọng, không chỉ nhìn trung bình.
4. **Mỗi lần chỉ đổi một tham số** và ghi lại kết quả. Thử 50 cấu hình rồi chọn cấu hình đẹp nhất gần như chắc chắn sẽ cho kết quả tốt giả tạo.
5. Xem **bảng tách nhóm**: nếu một nhóm (ví dụ breakout, hoặc forex) liên tục âm, cân nhắc tắt nhóm đó thay vì chỉnh ngưỡng chung.
6. Spread trong dữ liệu là spread của nến; lúc tin tức hoặc phiên Á, spread thật có thể rộng hơn nhiều.

## 5. Tệp

| Tệp | Nội dung |
|---|---|
| `run_backtest.py` | Script chạy (CLI) |
| `bt_data.py` | Đọc CSV, chuỗi nến, giờ đóng nến |
| `bt_indicators.py` | Chỉ báo tính trước, fractal |
| `bt_strategy.py` | `Params` (tham số), bias, swing, vùng Entry, phá vỡ, SL/TP |
| `bt_engine.py` | Chạy theo từng giờ, các kiểm tra trước khi báo, vòng đời setup, mô phỏng kết quả, xuất CSV |
| `make_sample_data.py` | Sinh dữ liệu giả lập để chạy thử |
| `test_backtest.py` | 16 test (`python -m unittest -v test_backtest.py`) |
| `../Scripts/ExportHistory.mq5` | Script MT5 xuất dữ liệu |

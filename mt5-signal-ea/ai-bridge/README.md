# Cầu nối AI: SignalEA → Claude API → Telegram

Script Python đọc các sự kiện do SignalEA xuất ra (file JSON), gọi Claude để viết nhận định ngắn bằng tiếng Việt, rồi gửi nhận định đó lên Telegram ngay sau tin tín hiệu của EA.

- **Chỉ gọi API khi có `SETUP MỚI` hoặc `GIÁ VÀO VÙNG ENTRY`.** Setup "đang chờ, vượt ngưỡng rủi ro" không được gửi.
- **In số token sau mỗi lần gọi**, kèm chi phí ước tính và tổng trong ngày.
- **Giới hạn số lần gọi mỗi ngày** (mặc định 20; tính theo ngày GMT+7). Mọi lần gọi đều được tính, kể cả lần lỗi.
- Chỉ dùng dữ liệu JSON (không gửi ảnh chart). Không đặt lệnh.

## 1. Luồng dữ liệu

```
SignalEA (InpAiExport=true)
  └─ MQL5/Files/SignalEA/ai_queue/<id>-NEW_SETUP.json | <id>-ENTRY_TOUCHED.json
        │  (EA ghi file .tmp rồi đổi tên, nên script không bao giờ đọc file đang ghi dở)
signal_ai_bridge.py (quét mỗi 10 giây)
  ├─ kiểm tra JSON, tuổi sự kiện (bỏ qua nếu cũ > 120 phút), giới hạn lần gọi/ngày
  ├─ gọi Claude (claude-opus-5-5, effort medium) → in [TOKEN] ...
  ├─ gửi Telegram: "[XAUUSD] NHẬN ĐỊNH AI - SETUP SELL (chờ hồi) - Nhóm: Ưu tiên ..."
  └─ chuyển file sang ai_queue/done | failed | skipped
```

## 2. Cài đặt trên VPS Windows

1. Cài **Python 3.10+** từ python.org. Khi cài, tick "Add python.exe to PATH".
2. Chép thư mục `ai-bridge` lên VPS, ví dụ `C:\ai-bridge`.
3. Mở **Command Prompt** tại thư mục đó và chạy:
   ```
   pip install -r requirements.txt
   ```
4. Lấy **API key** tại console.anthropic.com → API Keys. Nên đặt hạn mức chi tiêu (spend limit) cho workspace.
5. Đặt biến môi trường một lần bằng `setx`, rồi **mở cửa sổ CMD mới** để biến có hiệu lực:
   ```
   setx ANTHROPIC_API_KEY "sk-ant-..."
   setx TELEGRAM_BOT_TOKEN "123456789:AA..."
   setx TELEGRAM_CHAT_ID "123456789"
   setx SIGNALEA_FILES_DIR "C:\Users\<bạn>\AppData\Roaming\MetaQuotes\Terminal\<ID>\MQL5\Files\SignalEA"
   ```
   Để lấy đúng `SIGNALEA_FILES_DIR`: trong MT5 chọn **File → Open Data Folder**, mở `MQL5\Files\SignalEA`, rồi copy đường dẫn trên thanh địa chỉ.
   Token Telegram và chat id dùng giống EA (README chính, mục 4).
6. Trong EA, đặt `InpAiExport=true` (nhóm input "13. Cầu nối AI"). Log EA sẽ có dòng `Cầu nối AI: xuất JSON vào ...`.

> ⚠️ **Không** ghi API key hay token vào file `.bat`, file `.py` hoặc commit lên Git. Ai có API key là có thể tiêu tiền trên tài khoản Anthropic của bạn.

## 3. Chạy

| Lệnh | Dùng khi |
|---|---|
| `run_bridge.bat` | Chạy bình thường (gọi Claude + gửi Telegram), quét liên tục |
| `python signal_ai_bridge.py --no-api --dry-run --once` | Kiểm tra luồng file: **không gọi API, không gửi Telegram**, chỉ in prompt |
| `python signal_ai_bridge.py --dry-run --once` | Gọi Claude thật nhưng chỉ in nhận định ra màn hình |
| `python -m unittest -v test_signal_ai_bridge.py` | Chạy kiểm thử (không gọi mạng) |

**Thử nhanh với dữ liệu mẫu**, chưa cần EA:
```
mkdir "%SIGNALEA_FILES_DIR%\ai_queue"
copy sample_event.json "%SIGNALEA_FILES_DIR%\ai_queue\XAUUSD-test-NEW_SETUP.json"
python signal_ai_bridge.py --dry-run --once
```
Lần này **có gọi API** (khoảng vài cent) và in nhận định ra màn hình, không gửi Telegram.

**Tự chạy khi VPS khởi động lại**: mở **Task Scheduler** → Create Task → Trigger "At log on" → Action "Start a program" → chọn `run_bridge.bat`, ô "Start in" điền thư mục `ai-bridge`.

## 4. Tham số

| Tham số | Biến môi trường | Mặc định | Ý nghĩa |
|---|---|---|---|
| `--files-dir` | `SIGNALEA_FILES_DIR` | (bắt buộc) | Thư mục `MQL5\Files\SignalEA` |
| `--model` | `AI_MODEL` | `claude-opus-5-5` | Model Claude |
| `--effort` | `AI_EFFORT` | `medium` | Mức suy nghĩ: low / medium / high / xhigh / max. Cao hơn thì kỹ hơn nhưng tốn token hơn |
| `--max-calls` | `AI_MAX_CALLS_PER_DAY` | 20 | Số lần gọi tối đa mỗi ngày |
| `--max-age` | | 120 | Bỏ qua sự kiện cũ hơn N phút (ví dụ khi script bị tắt một thời gian) |
| `--poll` | | 10 | Chu kỳ quét hàng đợi (giây) |
| `--tz` | | 7 | Múi giờ dùng để tính "ngày" cho giới hạn |
| `--no-fallback` | | (bật) | Tắt chế độ tự chuyển model khi bị từ chối (xem mục 5) |
| `--dry-run` | | | Không gửi Telegram |
| `--no-api` | | | Không gọi Claude |
| `--once` | | | Xử lý hàng đợi 1 lần rồi thoát |

## 5. Gọi Claude như thế nào

- **Model và mức suy nghĩ:** model mặc định `claude-opus-5-5`, `effort: medium`. Model này luôn suy nghĩ trước khi trả lời; `effort` điều chỉnh mức độ. `max_tokens` = 8000 (đã gồm phần suy nghĩ; bản nhận định thực tế chỉ vài trăm token).
- **Tự chuyển model khi bị từ chối:** request được gửi qua `client.beta.messages.create` với beta `server-side-fallback-2026-07-01` và `fallbacks="default"`. Nếu bộ lọc an toàn từ chối trả lời, API tự chạy lại trên model dự phòng trong cùng một request. Nếu vẫn bị từ chối (`stop_reason = refusal`), script không gửi gì lên Telegram và ghi log. Muốn tắt chế độ này thì dùng `--no-fallback`.
- **System prompt** yêu cầu Claude:
  - chỉ dựa vào dữ liệu JSON;
  - không khuyên tăng rủi ro;
  - viết văn bản thuần không Markdown, khoảng 1200 ký tự, gồm 4 đoạn: Nhận định / Điểm ủng hộ / Rủi ro cần để ý / Gợi ý xử lý.
- **Xử lý lỗi:**
  - API key sai hoặc thiếu quyền: **dừng script** (mã thoát 2), giữ nguyên file trong hàng đợi.
  - Request không hợp lệ (400/404): chuyển file sang `failed/`.
  - Lỗi mạng, 429, 5xx: SDK tự thử lại 2 lần; nếu vẫn lỗi, script thử lại ở các lượt quét sau, tối đa 3 lần, rồi chuyển file sang `failed/`.
- **Log token**, ghi ra màn hình và file `ai_bridge.log` (ví dụ minh họa):
  ```
  [TOKEN] XAUUSD-2026101409-SELL-PB | model claude-opus-5-5 | input 2104 | output 812 | cache đọc 0 | ghi cache 0 | ước tính $0.0247 | hôm nay 3/20 lần, 6210+2390 token, $0.0726 | request req_...
  ```
  Chi phí là **ước tính** theo giá niêm yết (Opus 5.5: $4 / 1 triệu token input, $20 / 1 triệu token output); số chính xác xem trên console.anthropic.com. Mỗi lần gọi gửi khoảng 2.000 token input; output (gồm phần suy nghĩ) thay đổi theo effort. Ước tính khoảng vài cent mỗi lần gọi, tức dưới 1 USD/ngày với giới hạn 20 lần (chưa đo thực tế; hãy theo dõi dòng `[TOKEN]` vài ngày đầu).
- **Không dùng prompt caching:** system prompt quá ngắn so với mức tối thiểu để được cache, nên `cache đọc` sẽ luôn bằng 0.

## 6. Tệp và thư mục

| Đường dẫn | Nội dung |
|---|---|
| `ai_queue/*.json` | Sự kiện chờ xử lý |
| `ai_queue/done/` | Đã gửi nhận định (tự xóa sau 7 ngày) |
| `ai_queue/failed/` | JSON lỗi, bị từ chối, hoặc lỗi API sau 3 lần thử |
| `ai_queue/skipped/` | Bỏ qua vì sự kiện quá cũ hoặc đã đạt giới hạn ngày |
| `ai_bridge_state.json` | Số lần gọi, token, chi phí trong ngày (qua ngày mới thì đặt lại) |
| `ai_bridge.log` (cạnh script) | Log chạy |

## 7. Định dạng JSON (`signalea.setup.v1`)

Xem `sample_event.json`. Các trường chính:
- `event` (`NEW_SETUP` / `ENTRY_TOUCHED`), `id`, `symbol`, `tier`, `tier_label`, `asset_group`, `digits`, `time_server`, `time_display`.
- `price`: `bid`, `ask`, `spread_atr_pct`.
- `setup`: `type` (pullback/breakout), `side`, `state`, `entry_low`, `entry_high`, `entry_ref`, `sl`, `tp1`, `tp2`, `rr1`, `rr2`, `invalidation`, `expiry_hours`, `reasons`, `confluence_count`, `created_server`.
- `bias`: `score` (có dấu: dương là tăng), `max`, `text`.
- `indicators`: theo từng khung MN1/W1/D1/H4/H1 → `bar_time`, `close`, `sma10/20/50/200`, `bb_up/mid/low`, `rsi`, `atr`, `bias`. Giá trị thiếu là `null`.
- `risk`: `account_currency`, `balance`, `lot`, `risk_money`, `risk_pct`, `risk_warning`, `min_lot_risk_pct`, `total_open_risk_money`, `total_open_risk_pct`, `max_total_risk_pct`.
- `news`: ghi chú tin mức cao (chuỗi rỗng nếu không có).

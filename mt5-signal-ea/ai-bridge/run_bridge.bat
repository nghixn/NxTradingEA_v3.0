@echo off
REM Chạy cầu nối SignalEA -> Claude -> Telegram trên Windows VPS.
REM KHÔNG ghi API key / token vào file này. Đặt 1 lần bằng lệnh setx (xem README.md):
REM   setx ANTHROPIC_API_KEY "sk-ant-..."
REM   setx TELEGRAM_BOT_TOKEN "123456789:AA..."
REM   setx TELEGRAM_CHAT_ID "123456789"
REM   setx SIGNALEA_FILES_DIR "C:\Users\<ban>\AppData\Roaming\MetaQuotes\Terminal\<ID>\MQL5\Files\SignalEA"
cd /d "%~dp0"
python signal_ai_bridge.py --max-calls 20 %*

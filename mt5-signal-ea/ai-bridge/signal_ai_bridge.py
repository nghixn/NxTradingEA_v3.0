#!/usr/bin/env python3
"""Cầu nối SignalEA -> Claude API -> Telegram.

EA (InpAiExport=true) ghi mỗi sự kiện SETUP MỚI / GIÁ VÀO VÙNG ENTRY thành 1 file JSON
trong MQL5/Files/SignalEA/ai_queue/. Script này đọc từng file, gọi Claude để bình luận,
in số token mỗi lần gọi, giới hạn số lần gọi mỗi ngày và gửi bình luận lên Telegram.

Không đặt lệnh, không đọc ảnh, chỉ dùng dữ liệu JSON do EA xuất ra.
"""
from __future__ import annotations

import argparse
import json
import logging
import os
import shutil
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass, field
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any, Callable, Optional

import anthropic

SCHEMA = "signalea.setup.v1"
ALLOWED_EVENTS = {"NEW_SETUP", "ENTRY_TOUCHED"}
DEFAULT_MODEL = "claude-opus-5-5"
# Giá USD / 1 triệu token (input, output) - chỉ để ước tính chi phí in ra log
PRICE_PER_MTOK = {
    "claude-opus-5-5": (4.00, 20.00),
    "claude-sonnet-5-5": (2.00, 10.00),
    "claude-haiku-5-5": (0.10, 0.50),
}
# Model hỗ trợ server-side fallback dạng "default" khi bị từ chối (refusal)
FALLBACK_MODELS = {"claude-opus-5-5", "claude-opus-5", "claude-fable-5-1", "claude-sonnet-5-5"}
FALLBACK_BETA = "server-side-fallback-2026-07-01"
MAX_TOKENS = 8000            # gồm cả token suy nghĩ; bình luận thực tế chỉ vài trăm token
TELEGRAM_MAX_CHARS = 3800    # Telegram giới hạn 4096
DISCLAIMER = "Chỉ là tham khảo, không phải lời khuyên đầu tư."

log = logging.getLogger("ai-bridge")

SYSTEM_PROMPT = """Bạn là trợ lý phân tích kỹ thuật cho một trader cá nhân giao dịch trên MetaTrader 5 (Exness).
Trader lướt sóng từ vài giờ đến vài ngày, tài khoản nhỏ khoảng 1000 USD, rủi ro mỗi lệnh khoảng 1,5% số dư.

Mỗi tin nhắn chứa một sự kiện JSON do Expert Advisor "SignalEA" xuất ra. Setup trong đó đã qua bộ lọc của EA:
bias đa khung (MN1, W1, D1, H4, H1), vùng Entry hội tụ SMA/swing, SL/TP theo swing, tính lot theo tick value.
- event = NEW_SETUP: setup vừa được báo, trader đang cân nhắc có đặt lệnh chờ hay không.
- event = ENTRY_TOUCHED: giá vừa chạm vùng Entry, trader cần quyết định ngay có vào lệnh hay không.

Nhiệm vụ: viết nhận định ngắn gọn giúp trader tự quyết định. Yêu cầu:
1. Chỉ dựa vào dữ liệu trong JSON. Không bịa giá, tin tức hay chỉ báo không có trong JSON. Thiếu dữ liệu thì nói rõ là thiếu.
2. Đánh giá chất lượng setup: các khung có đồng thuận không, vị trí giá so với SMA/Bollinger, RSI (quá mua/quá bán),
   vùng Entry và SL có hợp lý so với ATR không, RR, rủi ro tổng đang mở, tin tức sắp ra (nếu trường news có nội dung).
3. Nêu rõ điều gì sẽ làm setup mất hiệu lực và nên chờ xác nhận gì (ví dụ kiểu nến đóng cửa trên khung nào).
4. Không khuyên tăng lot hay rủi ro vượt mức trong JSON. Nếu risk_warning = true hoặc rủi ro tổng cao, nhắc trader thận trọng.
5. Viết tiếng Việt, văn bản thuần, KHÔNG dùng Markdown (không **, #, bảng, gạch đầu dòng lồng nhau) vì Telegram hiển thị nguyên ký tự.
6. Tối đa khoảng 1200 ký tự, gồm đúng 4 đoạn, mỗi đoạn bắt đầu bằng nhãn:
   Nhận định: (1-2 câu, có đánh giá chất lượng Mạnh / Trung bình / Yếu)
   Điểm ủng hộ:
   Rủi ro cần để ý:
   Gợi ý xử lý:
Không thêm lời chào hay câu miễn trừ trách nhiệm; script sẽ tự thêm."""


# ---------------------------------------------------------------------------
# Cấu hình
# ---------------------------------------------------------------------------
@dataclass
class Config:
    queue_dir: Path
    state_file: Path
    model: str = DEFAULT_MODEL
    effort: str = "medium"
    use_fallback: bool = True
    max_calls_per_day: int = 20
    max_event_age_min: int = 120
    max_attempts: int = 3
    poll_seconds: int = 10
    tz_offset_hours: float = 7.0
    telegram_token: str = ""
    telegram_chat_id: str = ""
    dry_run: bool = False        # không gửi Telegram, chỉ in ra
    no_api: bool = False         # không gọi Claude (kiểm tra luồng file)
    once: bool = False           # xử lý hàng đợi 1 lần rồi thoát
    keep_done_days: int = 7


def local_now(cfg: Config) -> datetime:
    return datetime.now(timezone.utc) + timedelta(hours=cfg.tz_offset_hours)


# ---------------------------------------------------------------------------
# Trạng thái theo ngày: số lần gọi, token, chi phí ước tính
# ---------------------------------------------------------------------------
@dataclass
class DailyState:
    day: str = ""
    calls: int = 0
    input_tokens: int = 0
    output_tokens: int = 0
    cost_usd: float = 0.0
    limit_notified: bool = False
    attempts: dict = field(default_factory=dict)   # file -> số lần lỗi có thể thử lại

    @classmethod
    def load(cls, path: Path) -> "DailyState":
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
            return cls(**{k: v for k, v in data.items() if k in cls.__dataclass_fields__})
        except FileNotFoundError:
            return cls()
        except (ValueError, TypeError) as exc:
            log.warning("File trạng thái %s lỗi (%s) - bắt đầu mới.", path, exc)
            return cls()

    def save(self, path: Path) -> None:
        tmp = path.with_suffix(path.suffix + ".tmp")
        tmp.write_text(json.dumps(self.__dict__, ensure_ascii=False, indent=1), encoding="utf-8")
        os.replace(tmp, path)

    def roll(self, today: str) -> None:
        if self.day != today:
            self.day = today
            self.calls = 0
            self.input_tokens = 0
            self.output_tokens = 0
            self.cost_usd = 0.0
            self.limit_notified = False


def estimate_cost(model: str, usage: dict) -> float:
    price_in, price_out = PRICE_PER_MTOK.get(model, PRICE_PER_MTOK[DEFAULT_MODEL])
    cache_read = usage.get("cache_read_input_tokens") or 0
    cache_write = usage.get("cache_creation_input_tokens") or 0
    return (usage.get("input_tokens", 0) * price_in
            + cache_write * price_in * 1.25
            + cache_read * price_in * 0.1
            + usage.get("output_tokens", 0) * price_out) / 1_000_000


# ---------------------------------------------------------------------------
# Kiểm tra JSON
# ---------------------------------------------------------------------------
class InvalidPayload(ValueError):
    pass


def validate_payload(payload: Any) -> dict:
    if not isinstance(payload, dict):
        raise InvalidPayload("JSON không phải object")
    if payload.get("schema") != SCHEMA:
        raise InvalidPayload(f"schema '{payload.get('schema')}' khác '{SCHEMA}'")
    if payload.get("event") not in ALLOWED_EVENTS:
        raise InvalidPayload(f"event '{payload.get('event')}' không được hỗ trợ")
    for key in ("id", "symbol", "setup", "bias", "risk"):
        if key not in payload:
            raise InvalidPayload(f"thiếu trường '{key}'")
    setup = payload["setup"]
    if not isinstance(setup, dict) or setup.get("side") not in ("buy", "sell"):
        raise InvalidPayload("setup.side phải là buy/sell")
    return payload


def file_age_minutes(path: Path) -> float:
    # dùng thời gian ghi file (giờ máy) để không phụ thuộc giờ server
    return (time.time() - path.stat().st_mtime) / 60.0


# ---------------------------------------------------------------------------
# Prompt + gọi Claude
# ---------------------------------------------------------------------------
def build_user_prompt(payload: dict) -> str:
    event_vi = "SETUP MỚI" if payload["event"] == "NEW_SETUP" else "GIÁ VÀO VÙNG ENTRY"
    return (
        f"Sự kiện: {event_vi} cho {payload['symbol']}.\n"
        "Dữ liệu JSON từ EA:\n"
        f"{json.dumps(payload, ensure_ascii=False, indent=1)}"
    )


@dataclass
class AiResult:
    text: str
    model: str
    stop_reason: str
    usage: dict
    request_id: str = ""


def usage_to_dict(usage: Any) -> dict:
    keys = ("input_tokens", "output_tokens", "cache_read_input_tokens", "cache_creation_input_tokens")
    return {k: (getattr(usage, k, 0) or 0) for k in keys}


def call_claude(client: Any, cfg: Config, payload: dict) -> AiResult:
    kwargs: dict = dict(
        model=cfg.model,
        max_tokens=MAX_TOKENS,
        system=SYSTEM_PROMPT,
        messages=[{"role": "user", "content": build_user_prompt(payload)}],
        output_config={"effort": cfg.effort},
    )
    if cfg.use_fallback and cfg.model in FALLBACK_MODELS:
        # bị từ chối (refusal) thì API tự chạy lại trên model dự phòng trong cùng request
        response = client.beta.messages.create(betas=[FALLBACK_BETA], fallbacks="default", **kwargs)
    else:
        response = client.messages.create(**kwargs)

    text = "\n".join(b.text for b in response.content if getattr(b, "type", "") == "text").strip()
    if response.stop_reason == "refusal":
        details = getattr(response, "stop_details", None)
        category = getattr(details, "category", None) if details else None
        text = ""
        log.warning("Claude từ chối trả lời (category=%s).", category)
    elif response.stop_reason == "max_tokens":
        log.warning("Bình luận bị cắt do chạm max_tokens=%d.", MAX_TOKENS)
    return AiResult(
        text=text,
        model=getattr(response, "model", cfg.model),
        stop_reason=response.stop_reason or "",
        usage=usage_to_dict(response.usage),
        request_id=getattr(response, "_request_id", "") or "",
    )


# ---------------------------------------------------------------------------
# Telegram (thư viện chuẩn, văn bản thuần, không parse_mode)
# ---------------------------------------------------------------------------
def split_message(text: str, limit: int = TELEGRAM_MAX_CHARS) -> list[str]:
    parts: list[str] = []
    cur = ""
    for line in text.split("\n"):
        while len(line) > limit:
            if cur:
                parts.append(cur)
                cur = ""
            parts.append(line[:limit])
            line = line[limit:]
        candidate = line if not cur else cur + "\n" + line
        if len(candidate) > limit:
            parts.append(cur)
            cur = line
        else:
            cur = candidate
    if cur:
        parts.append(cur)
    return parts


class TelegramSender:
    def __init__(self, token: str, chat_id: str, dry_run: bool):
        self.token = token.strip()
        self.chat_id = chat_id.strip()
        self.dry_run = dry_run or not self.token or not self.chat_id
        if not dry_run and self.dry_run:
            log.warning("Thiếu TELEGRAM_BOT_TOKEN / TELEGRAM_CHAT_ID - chỉ in tin ra màn hình.")

    def send(self, text: str) -> bool:
        ok = True
        for part in split_message(text):
            ok = self._send_part(part) and ok
            time.sleep(1.1)   # giãn cách, tôn trọng giới hạn tốc độ của Telegram
        return ok

    def _send_part(self, text: str) -> bool:
        if self.dry_run:
            print("----- [DRYRUN] Tin Telegram -----")
            print(text)
            return True
        url = f"https://api.telegram.org/bot{self.token}/sendMessage"
        body = urllib.parse.urlencode({
            "chat_id": self.chat_id,
            "text": text,
            "disable_web_page_preview": "true",
        }).encode("utf-8")
        delay = 5
        for attempt in range(1, 4):
            try:
                with urllib.request.urlopen(urllib.request.Request(url, data=body), timeout=15) as resp:
                    if resp.status == 200:
                        return True
            except urllib.error.HTTPError as exc:
                detail = exc.read().decode("utf-8", "replace")
                if exc.code == 429:
                    try:
                        delay = int(json.loads(detail).get("parameters", {}).get("retry_after", delay))
                    except ValueError:
                        pass
                elif exc.code in (400, 401, 403, 404):
                    # token/chat id sai: thử lại cũng vô ích (không in token ra log)
                    log.error("Telegram từ chối (HTTP %d): %s", exc.code, detail[:200])
                    return False
                log.warning("Telegram lỗi HTTP %d, thử lại lần %d sau %ds.", exc.code, attempt, delay)
            except (urllib.error.URLError, TimeoutError) as exc:
                log.warning("Telegram lỗi mạng (%s), thử lại lần %d sau %ds.", exc, attempt, delay)
            time.sleep(delay)
            delay *= 3
        return False


def format_telegram(payload: dict, result: AiResult) -> str:
    setup = payload.get("setup", {})
    side = str(setup.get("side", "")).upper()
    kind = "phá vỡ" if setup.get("type") == "breakout" else "chờ hồi"
    event_vi = "SETUP" if payload["event"] == "NEW_SETUP" else "GIÁ VÀO VÙNG ENTRY"
    tier = payload.get("tier_label") or payload.get("tier", "")
    u = result.usage
    return (
        f"[{payload['symbol']}] NHẬN ĐỊNH AI - {event_vi} {side} ({kind}) - Nhóm: {tier}\n"
        f"{result.text}\n"
        f"(AI: {result.model} | {u.get('input_tokens', 0)}+{u.get('output_tokens', 0)} token)\n"
        f"{DISCLAIMER}"
    )


# ---------------------------------------------------------------------------
# Xử lý hàng đợi
# ---------------------------------------------------------------------------
RETRYABLE_ERRORS = (anthropic.RateLimitError, anthropic.APIConnectionError, anthropic.InternalServerError)


class FatalApiError(RuntimeError):
    """Lỗi cấu hình (API key sai...) - dừng script thay vì đốt lượt gọi."""


def move_to(path: Path, sub: str) -> Path:
    dest_dir = path.parent / sub
    dest_dir.mkdir(exist_ok=True)
    dest = dest_dir / path.name
    if dest.exists():
        dest.unlink()
    shutil.move(str(path), str(dest))
    return dest


def process_file(path: Path, cfg: Config, state: DailyState, client: Any, tg: TelegramSender) -> str:
    """Trả về: done / skipped / failed / retry."""
    try:
        payload = validate_payload(json.loads(path.read_text(encoding="utf-8")))
    except (ValueError, InvalidPayload) as exc:
        log.error("%s: JSON không hợp lệ (%s) -> failed/", path.name, exc)
        move_to(path, "failed")
        return "failed"

    age = file_age_minutes(path)
    if age > cfg.max_event_age_min:
        log.info("%s: sự kiện đã cũ %.0f phút (> %d) -> skipped/", path.name, age, cfg.max_event_age_min)
        move_to(path, "skipped")
        return "skipped"

    if state.calls >= cfg.max_calls_per_day:
        log.warning("%s: đã đạt giới hạn %d lần gọi/ngày -> skipped/", path.name, cfg.max_calls_per_day)
        if not state.limit_notified:
            tg.send(f"[AI] Đã đạt giới hạn {cfg.max_calls_per_day} lần gọi Claude hôm nay - "
                    "các setup sau sẽ không có nhận định AI.")
            state.limit_notified = True
            state.save(cfg.state_file)
        move_to(path, "skipped")
        return "skipped"

    if cfg.no_api:
        print("----- [NO-API] Prompt sẽ gửi cho Claude -----")
        print(build_user_prompt(payload))
        move_to(path, "done")
        return "done"

    # tính lượt trước khi gọi: lỗi giữa chừng vẫn tính để không vượt giới hạn
    state.calls += 1
    state.save(cfg.state_file)
    try:
        result = call_claude(client, cfg, payload)
    except (anthropic.AuthenticationError, anthropic.PermissionDeniedError) as exc:
        raise FatalApiError(f"API key không hợp lệ hoặc thiếu quyền: {exc}") from exc
    except (anthropic.BadRequestError, anthropic.NotFoundError) as exc:
        log.error("%s: request bị từ chối (%s) -> failed/", path.name, exc)
        move_to(path, "failed")
        return "failed"
    except RETRYABLE_ERRORS as exc:
        n = state.attempts.get(path.name, 0) + 1
        state.attempts[path.name] = n
        state.save(cfg.state_file)
        if n >= cfg.max_attempts:
            log.error("%s: lỗi tạm thời lần %d (%s) -> failed/", path.name, n, exc)
            state.attempts.pop(path.name, None)
            state.save(cfg.state_file)
            move_to(path, "failed")
            return "failed"
        log.warning("%s: lỗi tạm thời lần %d/%d (%s) - thử lại lượt sau.", path.name, n, cfg.max_attempts, exc)
        return "retry"

    state.attempts.pop(path.name, None)
    cost = estimate_cost(result.model, result.usage)
    state.input_tokens += result.usage["input_tokens"]
    state.output_tokens += result.usage["output_tokens"]
    state.cost_usd += cost
    state.save(cfg.state_file)
    u = result.usage
    log.info("[TOKEN] %s | model %s | input %d | output %d | cache đọc %d | ghi cache %d | ước tính $%.4f "
             "| hôm nay %d/%d lần, %d+%d token, $%.4f | request %s",
             payload["id"], result.model, u["input_tokens"], u["output_tokens"],
             u["cache_read_input_tokens"], u["cache_creation_input_tokens"], cost,
             state.calls, cfg.max_calls_per_day, state.input_tokens, state.output_tokens,
             state.cost_usd, result.request_id or "-")

    if not result.text:
        log.warning("%s: không có nội dung bình luận (stop_reason=%s) -> failed/", path.name, result.stop_reason)
        move_to(path, "failed")
        return "failed"
    if not tg.send(format_telegram(payload, result)):
        log.error("%s: gửi Telegram lỗi - bình luận in dưới đây:\n%s", path.name, result.text)
    move_to(path, "done")
    return "done"


def prune_done(cfg: Config) -> None:
    done_dir = cfg.queue_dir / "done"
    if not done_dir.is_dir():
        return
    cutoff = time.time() - cfg.keep_done_days * 86400
    for f in done_dir.glob("*.json"):
        if f.stat().st_mtime < cutoff:
            f.unlink(missing_ok=True)


def run_once(cfg: Config, state: DailyState, client: Any, tg: TelegramSender) -> int:
    state.roll(local_now(cfg).strftime("%Y-%m-%d"))
    files = sorted(cfg.queue_dir.glob("*.json"), key=lambda p: p.stat().st_mtime)
    handled = 0
    for path in files:
        if process_file(path, cfg, state, client, tg) != "retry":
            handled += 1
    return handled


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------
def parse_args(argv: Optional[list[str]] = None) -> Config:
    p = argparse.ArgumentParser(description="Cầu nối SignalEA -> Claude API -> Telegram")
    p.add_argument("--files-dir", default=os.environ.get("SIGNALEA_FILES_DIR", ""),
                   help="Thư mục MQL5/Files/SignalEA (hoặc biến môi trường SIGNALEA_FILES_DIR)")
    p.add_argument("--model", default=os.environ.get("AI_MODEL", DEFAULT_MODEL))
    p.add_argument("--effort", default=os.environ.get("AI_EFFORT", "medium"),
                   choices=["low", "medium", "high", "xhigh", "max"])
    p.add_argument("--max-calls", type=int, default=int(os.environ.get("AI_MAX_CALLS_PER_DAY", "20")),
                   help="Số lần gọi Claude tối đa mỗi ngày")
    p.add_argument("--max-age", type=int, default=120, help="Bỏ qua sự kiện cũ hơn N phút")
    p.add_argument("--poll", type=int, default=10, help="Chu kỳ quét hàng đợi (giây)")
    p.add_argument("--tz", type=float, default=7.0, help="Múi giờ tính 'ngày' cho giới hạn (GMT+x)")
    p.add_argument("--no-fallback", action="store_true", help="Tắt server-side fallback khi bị từ chối")
    p.add_argument("--dry-run", action="store_true", help="Không gửi Telegram, chỉ in ra")
    p.add_argument("--no-api", action="store_true", help="Không gọi Claude, chỉ in prompt (kiểm tra luồng)")
    p.add_argument("--once", action="store_true", help="Xử lý hàng đợi 1 lần rồi thoát")
    a = p.parse_args(argv)
    if not a.files_dir:
        p.error("cần --files-dir hoặc SIGNALEA_FILES_DIR (đường dẫn tới MQL5/Files/SignalEA)")
    files_dir = Path(a.files_dir)
    cfg = Config(
        queue_dir=files_dir / "ai_queue",
        state_file=files_dir / "ai_bridge_state.json",
        model=a.model,
        effort=a.effort,
        use_fallback=not a.no_fallback,
        max_calls_per_day=a.max_calls,
        max_event_age_min=a.max_age,
        poll_seconds=max(2, a.poll),
        tz_offset_hours=a.tz,
        telegram_token=os.environ.get("TELEGRAM_BOT_TOKEN", ""),
        telegram_chat_id=os.environ.get("TELEGRAM_CHAT_ID", ""),
        dry_run=a.dry_run,
        no_api=a.no_api,
        once=a.once,
    )
    return cfg


def main(argv: Optional[list[str]] = None) -> int:
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s",
                        handlers=[logging.StreamHandler(sys.stdout),
                                  logging.FileHandler(Path(__file__).with_name("ai_bridge.log"), encoding="utf-8")])
    cfg = parse_args(argv)
    cfg.queue_dir.mkdir(parents=True, exist_ok=True)
    state = DailyState.load(cfg.state_file)
    # client đọc ANTHROPIC_API_KEY từ biến môi trường; không hard-code key
    client = None if cfg.no_api else anthropic.Anthropic(max_retries=2, timeout=120.0)
    tg = TelegramSender(cfg.telegram_token, cfg.telegram_chat_id, cfg.dry_run)
    log.info("Cầu nối AI chạy: hàng đợi %s | model %s | effort %s | fallback %s | tối đa %d lần/ngày%s",
             cfg.queue_dir, cfg.model, cfg.effort, "bật" if cfg.use_fallback else "tắt",
             cfg.max_calls_per_day, " | DRY-RUN" if tg.dry_run else "")
    try:
        while True:
            run_once(cfg, state, client, tg)
            prune_done(cfg)
            if cfg.once:
                return 0
            time.sleep(cfg.poll_seconds)
    except FatalApiError as exc:
        log.error("%s - dừng script. Kiểm tra biến môi trường ANTHROPIC_API_KEY.", exc)
        return 2
    except KeyboardInterrupt:
        log.info("Dừng theo yêu cầu.")
        return 0


if __name__ == "__main__":
    sys.exit(main())

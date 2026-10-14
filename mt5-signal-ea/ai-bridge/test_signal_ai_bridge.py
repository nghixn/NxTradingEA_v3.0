"""Kiểm thử cầu nối (không gọi API thật, không gửi Telegram thật).

Chạy: python -m unittest -v test_signal_ai_bridge.py
"""
import json
import os
import shutil
import tempfile
import time
import unittest
from pathlib import Path
from types import SimpleNamespace

import anthropic
import httpx2

import signal_ai_bridge as bridge

SAMPLE = Path(__file__).with_name("sample_event.json")


def fake_response(text="Nhận định: setup bán khá tốt (Trung bình).", stop_reason="end_turn"):
    return SimpleNamespace(
        content=[SimpleNamespace(type="thinking", thinking=""), SimpleNamespace(type="text", text=text)],
        stop_reason=stop_reason,
        stop_details=SimpleNamespace(category="cyber") if stop_reason == "refusal" else None,
        model="claude-opus-5-5",
        usage=SimpleNamespace(input_tokens=1500, output_tokens=300,
                              cache_read_input_tokens=0, cache_creation_input_tokens=None),
        _request_id="req_test",
    )


class FakeMessages:
    def __init__(self, outcomes):
        self.outcomes = list(outcomes)
        self.calls = []

    def create(self, **kwargs):
        self.calls.append(kwargs)
        out = self.outcomes.pop(0)
        if isinstance(out, Exception):
            raise out
        return out


class FakeClient:
    def __init__(self, outcomes):
        self.messages = FakeMessages(outcomes)
        self.beta = SimpleNamespace(messages=self.messages)


class FakeTelegram:
    def __init__(self):
        self.sent = []

    def send(self, text):
        self.sent.append(text)
        return True


def connection_error():
    return anthropic.APIConnectionError(request=httpx2.Request("POST", "https://api.anthropic.com/v1/messages"))


class BridgeTest(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.cfg = bridge.Config(queue_dir=self.tmp / "ai_queue", state_file=self.tmp / "state.json",
                                 max_calls_per_day=2)
        self.cfg.queue_dir.mkdir()
        self.state = bridge.DailyState()
        self.state.roll("2026-10-14")
        self.tg = FakeTelegram()

    def tearDown(self):
        shutil.rmtree(self.tmp)

    def put_event(self, name="ev1.json", **changes):
        data = json.loads(SAMPLE.read_text(encoding="utf-8"))
        data.update(changes)
        path = self.cfg.queue_dir / name
        path.write_text(json.dumps(data, ensure_ascii=False), encoding="utf-8")
        return path

    def test_success_sends_comment_and_counts_tokens(self):
        path = self.put_event()
        client = FakeClient([fake_response()])
        self.assertEqual(bridge.process_file(path, self.cfg, self.state, client, self.tg), "done")
        self.assertTrue((self.cfg.queue_dir / "done" / "ev1.json").exists())
        self.assertEqual(self.state.calls, 1)
        self.assertEqual(self.state.input_tokens, 1500)
        self.assertEqual(self.state.output_tokens, 300)
        self.assertAlmostEqual(self.state.cost_usd, (1500 * 4 + 300 * 20) / 1e6)
        msg = self.tg.sent[0]
        self.assertIn("[XAUUSD] NHẬN ĐỊNH AI - SETUP SELL (chờ hồi) - Nhóm: Ưu tiên", msg)
        self.assertIn("1500+300 token", msg)
        # model mặc định + fallback server-side
        call = client.messages.calls[0]
        self.assertEqual(call["model"], "claude-opus-5-5")
        self.assertEqual(call["fallbacks"], "default")
        self.assertEqual(call["betas"], [bridge.FALLBACK_BETA])
        self.assertEqual(call["output_config"], {"effort": "medium"})
        self.assertNotIn("thinking", call)
        self.assertIn('"symbol": "XAUUSD"', call["messages"][0]["content"])

    def test_no_fallback_uses_plain_messages(self):
        self.cfg.use_fallback = False
        path = self.put_event()
        client = FakeClient([fake_response()])
        bridge.process_file(path, self.cfg, self.state, client, self.tg)
        self.assertNotIn("fallbacks", client.messages.calls[0])

    def test_daily_limit_skips_without_calling(self):
        self.state.calls = 2
        path = self.put_event()
        client = FakeClient([])
        self.assertEqual(bridge.process_file(path, self.cfg, self.state, client, self.tg), "skipped")
        self.assertEqual(client.messages.calls, [])
        self.assertTrue((self.cfg.queue_dir / "skipped" / "ev1.json").exists())
        self.assertIn("giới hạn 2 lần", self.tg.sent[0])
        # chỉ báo giới hạn 1 lần/ngày
        path2 = self.put_event("ev2.json")
        bridge.process_file(path2, self.cfg, self.state, client, self.tg)
        self.assertEqual(len(self.tg.sent), 1)

    def test_day_roll_resets_counters(self):
        self.state.calls = 2
        self.state.cost_usd = 1.0
        self.state.roll("2026-10-15")
        self.assertEqual((self.state.calls, self.state.cost_usd), (0, 0.0))

    def test_invalid_json_goes_to_failed(self):
        path = self.put_event(schema="khac")
        client = FakeClient([])
        self.assertEqual(bridge.process_file(path, self.cfg, self.state, client, self.tg), "failed")
        self.assertEqual(self.state.calls, 0)

    def test_old_event_skipped(self):
        path = self.put_event()
        old = time.time() - 3 * 3600
        os.utime(path, (old, old))
        self.assertEqual(bridge.process_file(path, self.cfg, self.state, FakeClient([]), self.tg), "skipped")

    def test_retryable_error_then_failed(self):
        self.cfg.max_calls_per_day = 10
        path = self.put_event()
        client = FakeClient([connection_error(), connection_error(), connection_error()])
        self.assertEqual(bridge.process_file(path, self.cfg, self.state, client, self.tg), "retry")
        self.assertEqual(bridge.process_file(path, self.cfg, self.state, client, self.tg), "retry")
        self.assertEqual(bridge.process_file(path, self.cfg, self.state, client, self.tg), "failed")
        self.assertEqual(self.state.calls, 3)   # mỗi lần gọi đều tính vào giới hạn
        self.assertEqual(self.state.attempts, {})

    def test_refusal_not_sent(self):
        path = self.put_event()
        client = FakeClient([fake_response(text="", stop_reason="refusal")])
        self.assertEqual(bridge.process_file(path, self.cfg, self.state, client, self.tg), "failed")
        self.assertEqual(self.tg.sent, [])

    def test_auth_error_is_fatal(self):
        path = self.put_event()
        resp = httpx2.Response(401, request=httpx2.Request("POST", "https://api.anthropic.com/v1/messages"))
        client = FakeClient([anthropic.AuthenticationError("invalid x-api-key", response=resp, body=None)])
        with self.assertRaises(bridge.FatalApiError):
            bridge.process_file(path, self.cfg, self.state, client, self.tg)
        self.assertTrue(path.exists())   # giữ lại file để xử lý sau khi sửa key

    def test_state_persists(self):
        self.state.calls = 1
        self.state.save(self.cfg.state_file)
        loaded = bridge.DailyState.load(self.cfg.state_file)
        self.assertEqual((loaded.day, loaded.calls), ("2026-10-14", 1))

    def test_split_message(self):
        text = "\n".join(["dòng " + "x" * 50] * 200)
        parts = bridge.split_message(text, 500)
        self.assertTrue(all(len(p) <= 500 for p in parts))
        self.assertEqual("\n".join(parts), text)
        long_line = "y" * 1200
        self.assertEqual("".join(bridge.split_message(long_line, 500)), long_line)

    def test_entry_touched_label(self):
        data = json.loads(SAMPLE.read_text(encoding="utf-8"))
        data["event"] = "ENTRY_TOUCHED"
        result = bridge.AiResult(text="Nhận định: ...", model="claude-opus-5-5", stop_reason="end_turn",
                                 usage={"input_tokens": 1, "output_tokens": 2})
        self.assertIn("NHẬN ĐỊNH AI - GIÁ VÀO VÙNG ENTRY SELL", bridge.format_telegram(data, result))


if __name__ == "__main__":
    unittest.main()

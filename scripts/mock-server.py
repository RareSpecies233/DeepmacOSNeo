#!/usr/bin/env python3
"""DeepGlass 本地 mock 服务器：无需 API Key 即可联调 DeepSeekKit 与 UI。

只用 Python 标准库，端口默认 8787。

    python3 scripts/mock-server.py

接口：
  GET  /models                   -> {"data":[{"id":"deepseek-flash"}]}
  GET  /user/balance             -> {"is_available":true,"balance_infos":[...]}
  POST /anthropic/v1/files       -> multipart 上传，返回 Files API 文件对象
  DELETE /anthropic/v1/files/{id}-> 删除已上传文件
  POST /anthropic/v1/messages    -> 校验 Content-Type / stream=true 后输出完整 SSE 事件序列

POST /anthropic/v1/files 的校验（与真实服务端一致，便于联调时暴露协议错误）：
  - 必须带 x-api-key；
  - 必须带 anthropic-beta: files-api-2025-04-14；
  - multipart 字段顺序固定：purpose（可选，图片不传）在前，file 在后；
  - purpose 只接受 rich_layout_recognition / user_data。

事件序列（与真实服务端同形，帧间隔 0.03s）：
  message_start
  -> index 0: thinking 块（thinking_delta x3 + signature_delta）
  -> index 1: server_tool_use(search)
  -> index 2: web_search_tool_result（2 条结果）
  -> index 3: text 块（24 段 text_delta，含 1 个 citations_delta）
  -> message_delta(stop_reason=end_turn[, title])
  -> message_stop

curl 验证：
  curl -N -s http://127.0.0.1:8787/models
  curl -N -s -X POST http://127.0.0.1:8787/anthropic/v1/messages \
    -H 'Content-Type: application/json' -H 'x-api-key: mock' \
    -d '{"model":"deepseek-flash","stream":true,"messages":[],"thinking":{"type":"enabled"}}'
"""

from __future__ import annotations

import json
import os
import re
import sys
import time
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

HOST = "127.0.0.1"
PORT = int(os.environ.get("MOCK_PORT", "8787"))
FRAME_INTERVAL = 0.03

USAGE = {
    "input_tokens": 128,
    "cache_creation_input_tokens": 0,
    "cache_read_input_tokens": 0,
    "output_tokens": 0,
}
FINAL_USAGE = dict(USAGE, output_tokens=512)

SIGNATURE = "0123456789abcdef0123456789abcdef"
MESSAGE_ID = uuid.uuid4().hex
SEARCH_TOOL_ID = "srvtoolu_s_1_" + "0123456789abcdef0123456789abcdef"

SEARCH_RESULTS = [
    {
        "type": "web_search_result",
        "title": "DeepSeek 官方文档：联网搜索",
        "url": "https://example.com/a",
        "snippet": "开启联网搜索后，服务端会先规划检索再生成回答，并把命中的网页作为引用挂到正文。",
        "site_icon": "https://example.com/favicon-a.png",
        "site_name": "DeepSeek Docs",
        "encrypted_content": "ZW5jcnlwdGVkLWNvbnRlbnQtYQ==",
        "page_age": "2026-01-02T03:04:05Z",
    },
    {
        "type": "web_search_result",
        "title": "Liquid Glass 与 macOS 26 的设计语言",
        "url": "https://example.com/b",
        "snippet": "从材质、折射到层级，Liquid Glass 让窗口与控件获得真实的光学表现。",
        "site_icon": "https://example.com/favicon-b.png",
        "site_name": "Design Notes",
        "encrypted_content": "ZW5jcnlwdGVkLWNvbnRlbnQtYg==",
        "page_age": "2025-11-20T09:30:00Z",
    },
]

THINKING_CHUNKS = [
    "用户问的是联网搜索的展示方式，",
    "我先确认 DeepSeek Chat 的交互细节：",
    "思考块、搜索卡片、正文引用三段式。",
]

TEXT_CHUNKS = [
    "DeepSeek Chat 的联网搜索",
    "会在回答前先规划检索，",
    "由服务端直接执行 web_search，",
    "再把命中的网页作为来源",
    "挂到正文的对应位置。",
    "开启「智能搜索」后，",
    "模型会先给出思考过程，",
    "再调用 deepseek_web_search",
    "搜索多个关键词，",
    "搜索结果以卡片形式",
    "展示在回答上方，",
    "包括站点图标、标题、",
    "摘要与发布时间。",
    "正文中出现的引用",
    "会自动编号为 [1]、[2]，",
    "点击即可跳转到对应来源。",
    "如果开启阅读链接，",
    "客户端还会调用 deepseek_read_url",
    "抓取页面正文，",
    "把关键段落揉进回答，",
    "并在来源列表里标出",
    "本次实际阅读过的页面。",
    "整个过程流式下发，",
    "首字节通常在 1 秒内到达。",
]

CITATION_AFTER = 8  # 第 8 段之后插入引用

# GET /user/balance 的真实响应形状（BalanceStore 消费 is_available + balance_infos）
BALANCE = {
    "is_available": True,
    "balance_infos": [
        {
            "currency": "CNY",
            "total_balance": "110.00",
            "granted_balance": "10.00",
            "topped_up_balance": "100.00",
        }
    ],
}

# 已上传文件：file_id -> 记录（只在内存里，重启即清空）
FILES: dict[str, dict] = {}

FILENAME_RE = re.compile(r'filename="([^"]*)"')
NAME_RE = re.compile(r'name="([^"]*)"')


def message_file_ids(body: dict) -> list[str]:
    """取出消息里 image / document 块引用的 file_id（按出现顺序）。"""
    ids: list[str] = []
    for message in body.get("messages") or []:
        content = message.get("content")
        if not isinstance(content, list):
            continue
        for block in content:
            if not isinstance(block, dict) or block.get("type") not in ("image", "document"):
                continue
            source = block.get("source") or {}
            if source.get("type") == "file" and isinstance(source.get("file_id"), str):
                ids.append(source["file_id"])
    return ids


def parse_multipart(body: bytes, boundary: str) -> list[dict]:
    """按 boundary 切分 multipart/form-data，返回 name/filename/content_type/data。"""
    marker = ("--" + boundary).encode("utf-8")
    fields: list[dict] = []
    for section in body.split(marker):
        if not section or section.startswith(b"--"):
            continue
        # 每段以 CRLF 开头，正文末尾也有 CRLF；只裁掉这两处包装
        section = section.lstrip(b"\r\n")
        if not section:
            continue
        head, sep, data = section.partition(b"\r\n\r\n")
        if not sep:
            continue
        if data.endswith(b"\r\n"):
            data = data[:-2]
        headers: dict[str, str] = {}
        for line in head.split(b"\r\n"):
            key, colon, value = line.partition(b":")
            if colon:
                headers[key.strip().lower().decode("utf-8", "replace")] = value.strip().decode(
                    "utf-8", "replace"
                )
        disposition = headers.get("content-disposition", "")
        name_match = NAME_RE.search(disposition)
        if not name_match:
            continue
        filename_match = FILENAME_RE.search(disposition)
        fields.append(
            {
                "name": name_match.group(1),
                "filename": filename_match.group(1) if filename_match else None,
                "content_type": headers.get("content-type"),
                "data": data,
            }
        )
    return fields


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    server_version = "DeepGlassMock/1.0"

    def log_message(self, format: str, *args) -> None:  # noqa: A002 - 对齐基类签名
        sys.stderr.write("[mock] %s %s\n" % (self.address_string(), format % args))

    # ---------- 响应工具 ----------

    def send_json(self, status: int, payload: dict) -> None:
        body = json.dumps(payload, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Connection", "close")
        self.end_headers()
        self.close_connection = True
        self.wfile.write(body)

    # ---------- GET ----------

    def do_GET(self) -> None:  # noqa: N802 - 基类约定
        path = self.path.split("?", 1)[0]
        if path == "/models":
            self.send_json(200, {"data": [{"id": "deepseek-flash"}]})
            return
        if path == "/user/balance":
            self.send_json(200, BALANCE)
            return
        self.send_json(404, {"error": {"message": "not found"}})

    # ---------- POST ----------

    def do_POST(self) -> None:  # noqa: N802 - 基类约定
        path = self.path.split("?", 1)[0]
        if path == "/anthropic/v1/files":
            self.upload_file()
            return
        if path != "/anthropic/v1/messages":
            self.send_json(404, {"error": {"message": "not found"}})
            return

        content_type = self.headers.get("Content-Type", "")
        if "application/json" not in content_type.lower():
            self.send_json(
                415,
                {"error": {"message": "Content-Type must be application/json"}},
            )
            return

        length = int(self.headers.get("Content-Length") or 0)
        raw = self.rfile.read(length) if length > 0 else b"{}"
        try:
            body = json.loads(raw.decode("utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError):
            self.send_json(400, {"error": {"message": "invalid json body"}})
            return

        if body.get("stream") is not True:
            self.send_json(400, {"error": {"message": "stream must be true"}})
            return

        # 引用已上传文件时必须带 Files API beta，且 file_id 必须真实存在
        file_ids = message_file_ids(body)
        if file_ids:
            beta = self.headers.get("anthropic-beta") or ""
            if "files-api-2025-04-14" not in beta:
                self.send_json(
                    400,
                    {"error": {"message": "missing anthropic-beta: files-api-2025-04-14"}},
                )
                return
            missing = [file_id for file_id in file_ids if file_id not in FILES]
            if missing:
                self.send_json(
                    400,
                    {
                        "error": {
                            "message": "file_ids do not exist or are not created under your account: {}".format(
                                ", ".join(missing)
                            )
                        }
                    },
                )
                return
            self.log_message("file blocks: %s", ", ".join(file_ids))

        self.stream_message(body)

    # ---------- Files API ----------

    def upload_file(self) -> None:
        """POST /anthropic/v1/files：校验鉴权头、beta、multipart 与字段顺序。"""
        if not (self.headers.get("x-api-key") or "").strip():
            self.send_json(401, {"error": {"message": "missing x-api-key header"}})
            return
        beta = self.headers.get("anthropic-beta") or ""
        if "files-api-2025-04-14" not in beta:
            self.send_json(
                400,
                {"error": {"message": "missing anthropic-beta: files-api-2025-04-14"}},
            )
            return

        content_type = self.headers.get("Content-Type") or ""
        boundary = None
        for piece in content_type.split(";"):
            key, _, value = piece.strip().partition("=")
            if key.lower() == "boundary":
                boundary = value.strip().strip('"')
        if "multipart/form-data" not in content_type.lower() or not boundary:
            self.send_json(
                415,
                {"error": {"message": "Content-Type must be multipart/form-data with boundary"}},
            )
            return

        length = int(self.headers.get("Content-Length") or 0)
        if length <= 0:
            self.send_json(400, {"error": {"message": "empty body"}})
            return
        parts = parse_multipart(self.rfile.read(length), boundary)
        names = [part["name"] for part in parts]

        if names.count("file") != 1:
            self.send_json(400, {"error": {"message": "exactly one file field is required"}})
            return
        file_part = next(part for part in parts if part["name"] == "file")
        purpose_parts = [part for part in parts if part["name"] == "purpose"]
        purpose = (
            purpose_parts[0]["data"].decode("utf-8", "replace").strip()
            if purpose_parts
            else None
        )
        if purpose is not None and purpose not in ("rich_layout_recognition", "user_data"):
            self.send_json(400, {"error": {"message": "unsupported purpose: {}".format(purpose)}})
            return
        # 字段顺序固定：purpose 必须排在 file 之前
        if purpose_parts and names.index("purpose") > names.index("file"):
            self.send_json(
                400,
                {"error": {"message": "purpose must precede file in multipart body"}},
            )
            return

        filename = file_part["filename"] or "file"
        mime_type = file_part["content_type"] or "application/octet-stream"
        data = file_part["data"]
        file_id = "file-api-" + uuid.uuid4().hex[:24]
        record = {
            "id": file_id,
            "type": "file",
            "size_bytes": len(data),
            "created_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
            "filename": filename,
            "mime_type": mime_type,
            "purpose": purpose,
        }
        FILES[file_id] = record
        self.log_message(
            "uploaded %s (%s, %d bytes, purpose=%s)", file_id, filename, len(data), purpose
        )
        self.send_json(
            200,
            {key: record[key] for key in (
                "id", "type", "size_bytes", "created_at", "filename", "mime_type"
            )},
        )

    def delete_file(self, file_id: str) -> None:
        if not (self.headers.get("x-api-key") or "").strip():
            self.send_json(401, {"error": {"message": "missing x-api-key header"}})
            return
        if FILES.pop(file_id, None) is None:
            self.send_json(404, {"error": {"message": "file not found: {}".format(file_id)}})
            return
        self.log_message("deleted %s", file_id)
        self.send_json(200, {"id": file_id, "type": "file_deleted", "deleted": True})

    def do_DELETE(self) -> None:  # noqa: N802 - 基类约定
        path = self.path.split("?", 1)[0]
        prefix = "/anthropic/v1/files/"
        if path.startswith(prefix):
            self.delete_file(path[len(prefix):])
            return
        self.send_json(404, {"error": {"message": "not found"}})

    # ---------- SSE ----------

    def stream_message(self, body: dict) -> None:
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream; charset=utf-8")
        self.send_header("Cache-Control", "no-cache, no-transform")
        self.send_header("Connection", "close")
        self.send_header("X-DS-Request-Id", MESSAGE_ID)
        self.end_headers()
        self.close_connection = True

        model = body.get("model") or "deepseek-flash"
        wants_title = bool((body.get("title") or {}).get("enabled"))

        try:
            self.emit(
                "message_start",
                {
                    "type": "message_start",
                    "message": {
                        "id": MESSAGE_ID,
                        "model": model,
                        "usage": USAGE,
                    },
                },
            )

            # --- index 0: 思考 ---
            self.emit(
                "content_block_start",
                {
                    "type": "content_block_start",
                    "index": 0,
                    "content_block": {"type": "thinking", "thinking": "", "signature": ""},
                },
            )
            for chunk in THINKING_CHUNKS:
                self.emit(
                    "content_block_delta",
                    {
                        "type": "content_block_delta",
                        "index": 0,
                        "delta": {"type": "thinking_delta", "thinking": chunk},
                    },
                )
            self.emit(
                "content_block_delta",
                {
                    "type": "content_block_delta",
                    "index": 0,
                    "delta": {"type": "signature_delta", "signature": SIGNATURE},
                },
            )
            self.emit(
                "content_block_stop",
                {"type": "content_block_stop", "index": 0},
            )

            # --- index 1: 搜索工具调用（原子下发完整 input） ---
            self.emit(
                "content_block_start",
                {
                    "type": "content_block_start",
                    "index": 1,
                    "content_block": {
                        "type": "server_tool_use",
                        "id": SEARCH_TOOL_ID,
                        "name": "deepseek_web_search",
                        "input": {
                            "action": "search",
                            "queries": [
                                "DeepSeek Chat 联网搜索 引用",
                                "Liquid Glass macOS 26 设计",
                            ],
                        },
                        "caller": {"type": "direct"},
                        "kind": "search",
                    },
                },
            )
            self.emit(
                "content_block_stop",
                {"type": "content_block_stop", "index": 1},
            )

            # --- index 2: 搜索结果（2 条） ---
            self.emit(
                "content_block_start",
                {
                    "type": "content_block_start",
                    "index": 2,
                    "content_block": {
                        "type": "web_search_tool_result",
                        "tool_use_id": SEARCH_TOOL_ID,
                        "content": SEARCH_RESULTS,
                        "kind": "search",
                    },
                },
            )
            self.emit(
                "content_block_stop",
                {"type": "content_block_stop", "index": 2},
            )

            # --- index 3: 正文（24 段 + 1 个引用） ---
            self.emit(
                "content_block_start",
                {
                    "type": "content_block_start",
                    "index": 3,
                    "content_block": {"type": "text", "text": ""},
                },
            )
            for position, chunk in enumerate(TEXT_CHUNKS):
                self.emit(
                    "content_block_delta",
                    {
                        "type": "content_block_delta",
                        "index": 3,
                        "delta": {"type": "text_delta", "text": chunk},
                    },
                )
                if position == CITATION_AFTER - 1:
                    self.emit(
                        "content_block_delta",
                        {
                            "type": "content_block_delta",
                            "index": 3,
                            "delta": {
                                "type": "citations_delta",
                                "citation": {
                                    "type": "web_search_result_location",
                                    "url": SEARCH_RESULTS[0]["url"],
                                    "title": SEARCH_RESULTS[0]["title"],
                                    "cited_text": "".join(
                                        TEXT_CHUNKS[:CITATION_AFTER]
                                    ).strip(),
                                    "encrypted_index": "",
                                },
                            },
                        },
                    )
            self.emit(
                "content_block_stop",
                {"type": "content_block_stop", "index": 3},
            )

            # --- 收尾 ---
            delta: dict = {"stop_reason": "end_turn", "stop_sequence": None}
            if wants_title:
                delta["title"] = "联网搜索演示"
            self.emit(
                "message_delta",
                {"type": "message_delta", "delta": delta, "usage": FINAL_USAGE},
            )
            self.emit("message_stop", {"type": "message_stop"})
        except (BrokenPipeError, ConnectionResetError):
            # 客户端提前断开（例如取消生成）不是错误。
            self.log_message("client disconnected")
        finally:
            self.wfile.flush()

    def emit(self, event: str, payload: dict) -> None:
        frame = "event: {}\ndata: {}\n\n".format(
            event, json.dumps(payload, ensure_ascii=False, separators=(",", ":"))
        )
        self.wfile.write(frame.encode("utf-8"))
        self.wfile.flush()
        time.sleep(FRAME_INTERVAL)


def main() -> None:
    server = ThreadingHTTPServer((HOST, PORT), Handler)
    server.daemon_threads = True
    print(f"DeepGlass mock server listening on http://{HOST}:{PORT}", flush=True)
    print("  GET  /models", flush=True)
    print("  GET  /user/balance", flush=True)
    print("  POST /anthropic/v1/files", flush=True)
    print("  DELETE /anthropic/v1/files/{file_id}", flush=True)
    print("  POST /anthropic/v1/messages", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nmock server stopped", flush=True)
    finally:
        server.server_close()


if __name__ == "__main__":
    main()

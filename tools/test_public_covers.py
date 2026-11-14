#!/usr/bin/env python3
"""Run browser cover regressions against an isolated origin without CORS headers."""

import argparse
import base64
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import subprocess
from threading import Thread

PNG = base64.b64decode(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
)


class CoverHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path != "/cover.png":
            self.send_error(404)
            return
        self.send_response(200)
        self.send_header("Content-Type", "image/png")
        self.send_header("Content-Length", str(len(PNG)))
        self.end_headers()
        self.wfile.write(PNG)

    def log_message(self, *_args):
        pass


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--flutter", default="flutter")
    args = parser.parse_args()
    server = ThreadingHTTPServer(("127.0.0.1", 0), CoverHandler)
    worker = Thread(target=server.serve_forever, daemon=True)
    worker.start()
    url = f"http://127.0.0.1:{server.server_port}/cover.png"
    try:
        return subprocess.call(
            [
                args.flutter,
                "test",
                "--platform",
                "chrome",
                f"--dart-define=COVER_TEST_URL={url}",
                "test/widgets/book/public_book_cover_web_test.dart",
            ],
            cwd=Path(__file__).resolve().parents[1] / "app",
        )
    finally:
        server.shutdown()
        server.server_close()
        worker.join()


if __name__ == "__main__":
    raise SystemExit(main())

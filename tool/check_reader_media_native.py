#!/usr/bin/env python3
"""Run reader media checks against AVFoundation and WKWebView on macOS."""

import argparse
import http.server
from pathlib import Path
import re
import subprocess
import threading


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", type=int, default=8769)
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    video = (root / "packages/video_player_avfoundation/example/assets/Butterfly-209.mp4").read_bytes()

    class VideoHandler(http.server.BaseHTTPRequestHandler):
        def do_GET(self):
            if self.path != "/video.mp4":
                self.send_error(404)
                return
            requested = self.headers.get("Range")
            start, end = 0, len(video) - 1
            if requested:
                match = re.fullmatch(r"bytes=(\d+)-(\d*)", requested)
                if not match:
                    self.send_error(416)
                    return
                start = int(match[1])
                end = min(int(match[2]), end) if match[2] else end
                if start > end:
                    self.send_error(416)
                    return
            self.send_response(206 if requested else 200)
            self.send_header("Content-Type", "video/mp4")
            self.send_header("Accept-Ranges", "bytes")
            self.send_header("Content-Length", str(end - start + 1))
            if requested:
                self.send_header("Content-Range", f"bytes {start}-{end}/{len(video)}")
            self.end_headers()
            try:
                self.wfile.write(video[start:end + 1])
            except (BrokenPipeError, ConnectionResetError):
                pass

    with http.server.ThreadingHTTPServer(("127.0.0.1", args.port), VideoHandler) as server:
        worker = threading.Thread(target=server.serve_forever, daemon=True)
        worker.start()
        fixture = f"http://127.0.0.1:{server.server_port}/video.mp4"
        try:
            return subprocess.call(
                [
                    "flutter", "test", "--no-pub", "-d", "macos",
                    "integration_test/reader_media_activity_test.dart",
                    f"--dart-define=READER_MEDIA_FIXTURE={fixture}",
                    "--reporter", "expanded",
                ],
                cwd=root,
            )
        finally:
            server.shutdown()


if __name__ == "__main__":
    raise SystemExit(main())

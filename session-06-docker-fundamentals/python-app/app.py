"""Minimal Hello World web server using only the Python standard library."""
import os
import platform
import socket
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, HTTPServer

PORT = int(os.environ.get("PORT", "5000"))

PAGE = f"""<!DOCTYPE html>
<html>
<head><meta charset="utf-8"><title>Python Hello World</title></head>
<body style="font-family: sans-serif; text-align: center; margin-top: 15vh;">
  <h1>Hello World from Python!</h1>
  <p>Served by Python {platform.python_version()} (http.server) inside a Docker container.</p>
  <p>Container hostname: {socket.gethostname()}</p>
  <p><small>Session 06 - Vansh Srivastava (24bcs10567)</small></p>
</body>
</html>
""".encode()


class HelloHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(PAGE)))
        self.end_headers()
        self.wfile.write(PAGE)

    def log_message(self, fmt, *args):
        # Log to stdout so `docker logs` shows each request.
        print(f"{datetime.now(timezone.utc).isoformat()} {self.address_string()} {fmt % args}", flush=True)


if __name__ == "__main__":
    print(f"Python app listening on port {PORT}", flush=True)
    HTTPServer(("0.0.0.0", PORT), HelloHandler).serve_forever()

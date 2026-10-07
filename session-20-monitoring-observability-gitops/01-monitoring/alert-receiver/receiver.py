"""Minimal webhook receiver for Alertmanager.

Alertmanager POSTs a JSON document for every notification. This script prints
one compact JSON line per alert so the notifications show up in
`docker compose logs alert-receiver`. Standard library only.
"""
import json
from http.server import BaseHTTPRequestHandler, HTTPServer


class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        body = self.rfile.read(int(self.headers.get("Content-Length", 0)))
        payload = json.loads(body or b"{}")
        for alert in payload.get("alerts", []):
            print(json.dumps({
                "notification_status": payload.get("status"),
                "alertname": alert["labels"].get("alertname"),
                "severity": alert["labels"].get("severity"),
                "alert_status": alert.get("status"),
                "startsAt": alert.get("startsAt"),
                "endsAt": alert.get("endsAt"),
                "summary": alert.get("annotations", {}).get("summary"),
            }), flush=True)
        self.send_response(200)
        self.end_headers()

    def log_message(self, *args):  # silence the default access log
        pass


if __name__ == "__main__":
    print("alert-receiver listening on :5001", flush=True)
    HTTPServer(("0.0.0.0", 5001), Handler).serve_forever()

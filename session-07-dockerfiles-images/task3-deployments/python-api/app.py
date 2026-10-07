"""Small "quote of the day" API built with Flask and served by gunicorn."""
import os
import platform
import random
import socket

from flask import Flask, jsonify

app = Flask(__name__)
VARIANT = os.environ.get("IMAGE_VARIANT", "unknown")

QUOTES = [
    "It works on my machine. - so we ship the machine (Docker)",
    "Build once, run anywhere.",
    "Small images start faster, pull faster and have fewer CVEs.",
    "Each RUN, COPY and ADD creates a new image layer.",
]


@app.get("/")
def index():
    quote = random.choice(QUOTES)
    return f"""<!DOCTYPE html><html><head><meta charset="utf-8"><title>Python Quote API</title></head>
<body style="font-family: sans-serif; margin: 40px;">
<h1>Python (Flask + gunicorn) Quote API</h1>
<p>Image variant: <b>{VARIANT}</b> | Python {platform.python_version()} | container {socket.gethostname()}</p>
<blockquote>{quote}</blockquote>
<p>JSON: <code>/api/quote</code>, health: <code>/health</code></p>
<p><small>Session 07 Task 3 - Vansh Srivastava (24bcs10567)</small></p>
</body></html>"""


@app.get("/api/quote")
def quote():
    return jsonify(variant=VARIANT, quote=random.choice(QUOTES))


@app.get("/health")
def health():
    return jsonify(status="ok")

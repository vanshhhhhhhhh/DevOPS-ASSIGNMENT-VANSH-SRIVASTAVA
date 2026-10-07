"""Session 17 DevSecOps demo: a small notes API that is tested, scanned and gated before it ships."""

import os
import platform
import socket
import threading

from flask import Flask, jsonify, render_template, request

MAX_NOTE_LENGTH = 200

PIPELINE_STAGES = [
    "Code", "Build", "Unit test", "SAST", "SCA", "Secret scan", "Docker build",
    "Image scan", "Security gate", "Push image", "Deploy to Kubernetes",
]

SECURITY_HEADERS = {
    "X-Content-Type-Options": "nosniff",
    "X-Frame-Options": "DENY",
    "Referrer-Policy": "no-referrer",
    "Content-Security-Policy": "default-src 'self'; frame-ancestors 'none'",
}


def runtime_info():
    """What the running container looks like. The API key is only reported as present or absent."""
    return {
        "app": "s17-devsecops-demo",
        "version": os.environ.get("APP_VERSION", "dev"),
        "git_sha": os.environ.get("GIT_SHA", "local"),
        "python": platform.python_version(),
        "hostname": socket.gethostname(),
        "uid": os.getuid(),
        "root_fs_writable": os.access("/app", os.W_OK),
        "api_key_configured": bool(os.environ.get("DEMO_API_KEY")),
    }


def error(message, status):
    return jsonify(error=message), status


def create_app():
    app = Flask(__name__)
    app.config["MAX_CONTENT_LENGTH"] = 16 * 1024  # reject large request bodies early (HTTP 413)

    notes = []
    lock = threading.Lock()

    @app.after_request
    def add_security_headers(response):
        response.headers.update(SECURITY_HEADERS)
        return response

    @app.get("/")
    def index():
        return render_template("index.html", info=runtime_info(), stages=PIPELINE_STAGES)

    @app.get("/health")
    def health():
        return jsonify(status="ok")

    @app.get("/ready")
    def ready():
        return jsonify(status="ready")

    @app.get("/api/info")
    def info():
        return jsonify(runtime_info())

    @app.get("/api/notes")
    def list_notes():
        with lock:
            return jsonify(notes=list(notes))

    @app.post("/api/notes")
    def create_note():
        payload = request.get_json(silent=True)
        if not isinstance(payload, dict):
            return error("request body must be a JSON object", 400)
        text = payload.get("text")
        if not isinstance(text, str) or not text.strip():
            return error("'text' must be a non-empty string", 400)
        if len(text) > MAX_NOTE_LENGTH:
            return error(f"'text' must be at most {MAX_NOTE_LENGTH} characters", 400)
        with lock:
            note = {"id": len(notes) + 1, "text": text.strip()}
            notes.append(note)
        return jsonify(note), 201

    @app.get("/api/notes/<int:note_id>")
    def get_note(note_id):
        with lock:
            for note in notes:
                if note["id"] == note_id:
                    return jsonify(note)
        return error("note not found", 404)

    @app.errorhandler(404)
    def not_found(_exc):
        return error("not found", 404)

    @app.errorhandler(405)
    def method_not_allowed(_exc):
        return error("method not allowed", 405)

    @app.errorhandler(413)
    def too_large(_exc):
        return error("request body too large", 413)

    return app


app = create_app()

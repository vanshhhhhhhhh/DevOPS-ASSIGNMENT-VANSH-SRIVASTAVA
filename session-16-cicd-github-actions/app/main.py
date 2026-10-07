"""Session 16 CI/CD demo: a tiny calculator web service built and shipped by GitHub Actions."""

import os
import platform
import socket

from flask import Flask, jsonify, render_template, request

from app.calculator import OPERATIONS


def build_info():
    """Values injected at image build time (Dockerfile ARG -> ENV) by the CI pipeline."""
    return {
        "app": "s16-cicd-demo",
        "version": os.environ.get("APP_VERSION", "dev"),
        "git_sha": os.environ.get("GIT_SHA", "local"),
        "python": platform.python_version(),
        "hostname": socket.gethostname(),
    }


def create_app():
    app = Flask(__name__)

    @app.get("/")
    def index():
        return render_template("index.html", info=build_info(), operations=sorted(OPERATIONS))

    @app.get("/health")
    def health():
        return jsonify(status="ok")

    @app.get("/api/info")
    def info():
        return jsonify(build_info())

    @app.get("/api/calc")
    def calc():
        op = request.args.get("op", "")
        if op not in OPERATIONS:
            return jsonify(error=f"unknown op, use one of {sorted(OPERATIONS)}"), 400
        try:
            a = float(request.args["a"])
            b = float(request.args["b"])
        except (KeyError, ValueError):
            return jsonify(error="query parameters a and b must be numbers"), 400
        try:
            result = OPERATIONS[op](a, b)
        except ValueError as exc:
            return jsonify(error=str(exc)), 400
        return jsonify(op=op, a=a, b=b, result=result)

    return app


app = create_app()

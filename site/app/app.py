"""Meridian Logistics API: health check, contact form, and basic stats.

Runs under gunicorn as the meridian-app systemd service, reverse-proxied by
Nginx at /api/. Talks to MariaDB on the db VM using a least-privilege user
restricted to the web VM's IP (see lab/configs/mariadb/).
"""
import os
import time

import pymysql
from flask import Flask, jsonify, request

app = Flask(__name__)

DB_HOST = os.environ.get("MERIDIAN_DB_HOST", "db")
DB_USER = os.environ.get("MERIDIAN_DB_USER", "meridian_app")
DB_PASSWORD = os.environ.get("MERIDIAN_DB_PASSWORD", "")
DB_NAME = os.environ.get("MERIDIAN_DB_NAME", "meridian")

START_TIME = time.time()


def get_connection():
    return pymysql.connect(
        host=DB_HOST,
        user=DB_USER,
        password=DB_PASSWORD,
        database=DB_NAME,
        connect_timeout=5,
        autocommit=True,
    )


@app.get("/api/health")
def health():
    db_ok = True
    try:
        conn = get_connection()
        conn.close()
    except Exception:
        db_ok = False
    return jsonify(
        status="ok" if db_ok else "degraded",
        db_reachable=db_ok,
        uptime_seconds=round(time.time() - START_TIME, 1),
    ), (200 if db_ok else 503)


@app.post("/api/contact")
def contact():
    data = request.get_json(silent=True) or {}
    name = (data.get("name") or "").strip()
    email = (data.get("email") or "").strip()
    message = (data.get("message") or "").strip()

    if not name or not email or not message:
        return jsonify(error="name, email and message are all required"), 400

    try:
        conn = get_connection()
        with conn.cursor() as cur:
            cur.execute(
                "INSERT INTO contact_messages (name, email, message) VALUES (%s, %s, %s)",
                (name, email, message),
            )
        conn.close()
    except Exception as exc:
        return jsonify(error="could not store message", detail=str(exc)), 500

    return jsonify(status="received"), 201


@app.get("/api/stats")
def stats():
    try:
        conn = get_connection()
        with conn.cursor() as cur:
            cur.execute("SELECT COUNT(*) FROM contact_messages")
            (count,) = cur.fetchone()
        conn.close()
    except Exception as exc:
        return jsonify(error="could not read stats", detail=str(exc)), 500

    return jsonify(contact_messages=count, uptime_seconds=round(time.time() - START_TIME, 1))


if __name__ == "__main__":
    app.run(host="127.0.0.1", port=8000)

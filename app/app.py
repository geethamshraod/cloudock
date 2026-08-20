# from flask import Flask, jsonify
# from datetime import datetime, timezone

# app = Flask(__name__)

# # In-memory sample events (placeholder — M3 will likely swap this for Firestore)
# EVENTS = [
#     {"id": 1, "type": "login", "user": "admin", "severity": "info"},
#     {"id": 2, "type": "firewall_block", "source_ip": "203.0.113.42", "severity": "warning"},
#     {"id": 3, "type": "deploy", "service": "cloudock-webserver", "severity": "info"},
# ]


# @app.route("/")
# def dashboard():
#     return f"""
#     <html>
#       <head><title>cloudock Secure Dashboard</title></head>
#       <body style="font-family: sans-serif; margin: 40px;">
#         <h1>cloudock Secure Dashboard</h1>
#         <p>Status: <strong>running</strong></p>
#         <p>Server time (UTC): {datetime.now(timezone.utc).isoformat()}</p>
#         <ul>
#           <li><a href="/health">/health</a></li>
#           <li><a href="/events">/events</a></li>
#         </ul>
#       </body>
#     </html>
#     """


# @app.route("/health")
# def health():
#     return jsonify({
#         "status": "ok",
#         "service": "secure-dashboard",
#         "timestamp": datetime.now(timezone.utc).isoformat(),
#     })


# @app.route("/events")
# def events():
#     return jsonify(EVENTS)


# if __name__ == "__main__":
#     app.run(host="0.0.0.0", port=8080)

import importlib
import json
from datetime import datetime, timezone

from flask import Flask, jsonify, request
from google.cloud import firestore

app = Flask(__name__)


def _detect_project():
    """Discover the GCP project via Application Default Credentials.
    Returns None locally (no ADC context) instead of raising. Cloud Run
    does not actually set a GOOGLE_CLOUD_PROJECT env var, so this is the
    reliable way to get the project ID."""
    try:
        google_auth = importlib.import_module("google.auth")
        _, project = google_auth.default()
        return project
    except Exception:
        return None


PROJECT = _detect_project()

# ---------------------------------------------------------------------
# Firestore -- security events
# ---------------------------------------------------------------------
db = firestore.Client()  # uses cloud-run-sa credentials automatically in production


def write_event(event_type, severity, description):
    doc_ref = db.collection("security_events").document()
    doc_ref.set({
        "type": event_type,
        "severity": severity,
        "description": description,
        "timestamp": firestore.SERVER_TIMESTAMP,
        "source": "cloudock",
    })
    return doc_ref.id


# ---------------------------------------------------------------------
# Secret Manager -- app config, read once at startup (not per-request)
# ---------------------------------------------------------------------
def access_secret(secret_id):
    from google.cloud import secretmanager

    client = secretmanager.SecretManagerServiceClient()
    name = f"projects/{PROJECT}/secrets/{secret_id}/versions/latest"
    response = client.access_secret_version(request={"name": name})
    return json.loads(response.payload.data.decode("UTF-8"))


try:
    app_config = access_secret("app-config")
except Exception as e:
    # Fails fast on purpose -- logged explicitly so Cloud Run logs show
    # *why* it crash-looped, rather than a bare traceback. Common cause:
    # the secretAccessor binding on this specific secret hasn't
    # propagated yet -- wait a minute and retry.
    app.logger.error(f"Startup failed reading Secret Manager config 'app-config': {e}")
    raise


# ---------------------------------------------------------------------
# Routes
# ---------------------------------------------------------------------
@app.route("/")
def dashboard():
    return f"""
    <html>
      <head><title>cloudock Secure Dashboard</title></head>
      <body style="font-family: sans-serif; margin: 40px;">
        <h1>cloudock Secure Dashboard</h1>
        <p>Status: <strong>running</strong></p>
        <p>Config env: {app_config.get('env', 'unknown')}</p>
        <p>Server time (UTC): {datetime.now(timezone.utc).isoformat()}</p>
        <ul>
          <li><a href="/health">/health</a></li>
          <li><a href="/events">/events</a></li>
        </ul>
      </body>
    </html>
    """


@app.route("/health")
def health():
    return jsonify({
        "status": "ok",
        "service": "secure-dashboard",
        "timestamp": datetime.now(timezone.utc).isoformat(),
    })


@app.route("/events", methods=["GET"])
def get_events():
    docs = (
        db.collection("security_events")
        .order_by("timestamp", direction=firestore.Query.DESCENDING)
        .limit(50)
        .stream()
    )
    events = [
        {
            **doc.to_dict(),
            "timestamp": doc.to_dict()["timestamp"].isoformat()
            if doc.to_dict().get("timestamp") else None,
        }
        for doc in docs
    ]
    return jsonify(events)


@app.route("/events", methods=["POST"])
def create_event():
    data = request.get_json(silent=True) or {}
    event_type = data.get("type")
    severity = data.get("severity")
    description = data.get("description")

    if not all([event_type, severity, description]):
        return jsonify({"error": "type, severity, and description are required"}), 400

    event_id = write_event(event_type, severity, description)
    return jsonify({"id": event_id}), 201


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)
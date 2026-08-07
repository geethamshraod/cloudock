from flask import Flask, jsonify
from datetime import datetime, timezone

app = Flask(__name__)

# In-memory sample events (placeholder — M3 will likely swap this for Firestore)
EVENTS = [
    {"id": 1, "type": "login", "user": "admin", "severity": "info"},
    {"id": 2, "type": "firewall_block", "source_ip": "203.0.113.42", "severity": "warning"},
    {"id": 3, "type": "deploy", "service": "cloudock-webserver", "severity": "info"},
]


@app.route("/")
def dashboard():
    return f"""
    <html>
      <head><title>cloudock Secure Dashboard</title></head>
      <body style="font-family: sans-serif; margin: 40px;">
        <h1>cloudock Secure Dashboard</h1>
        <p>Status: <strong>running</strong></p>
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


@app.route("/events")
def events():
    return jsonify(EVENTS)


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)

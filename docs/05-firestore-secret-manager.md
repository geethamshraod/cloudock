# M4 — Firestore + Secret Manager

**Goal:** Persist security events in Firestore instead of the in-memory
placeholder from M3, and move app config out of code into Secret Manager —
both accessed through `cloud-run-sa` with roles scoped as tightly as
possible.

## 0. Firestore database (missing from the original plan)

```bash
gcloud firestore databases create --location=asia-southeast1 --type=firestore-native
```
**Why:** `firestore.googleapis.com` was enabled back in the original
environment setup, but enabling the API only makes Firestore *available* —
it doesn't create an actual database. `firestore.Client()` fails with
`NOT_FOUND` until one exists. This is a one-time, irreversible choice per
project (mode and location can't be changed after creation), so it's worth
doing deliberately here rather than letting it happen implicitly on first
use. Native mode chosen over Datastore mode since the app code uses the
Firestore-native query API (`order_by`, `.stream()`).

## Firestore integration

```bash
# requirements.txt
google-cloud-firestore==2.14.0
```
```python
from google.cloud import firestore
db = firestore.Client()

def write_event(event_type, severity, description):
    doc_ref = db.collection("security_events").document()
    doc_ref.set({
        "type": event_type, "severity": severity, "description": description,
        "timestamp": firestore.SERVER_TIMESTAMP, "source": "cloudock",
    })
    return doc_ref.id
```
**Why:** `firestore.Client()` at module load doesn't fail immediately even
without a database — it's a lazy connection, so the actual `NOT_FOUND`
only surfaces on the first real read/write. That's why step 0 matters:
without it, this code *looks* fine until the first request hits `/events`.

**GET /events** — reads real data instead of the M3 placeholder:
```python
docs = (db.collection("security_events")
        .order_by("timestamp", direction=firestore.Query.DESCENDING)
        .limit(50).stream())
events = [{**doc.to_dict(), "timestamp": doc.to_dict()["timestamp"].isoformat()
           if doc.to_dict().get("timestamp") else None} for doc in docs]
```

**POST /events** — not given in the original task text, written to match
`write_event()`'s signature:
```python
@app.route("/events", methods=["POST"])
def create_event():
    data = request.get_json(silent=True) or {}
    event_type, severity, description = data.get("type"), data.get("severity"), data.get("description")
    if not all([event_type, severity, description]):
        return jsonify({"error": "type, severity, and description are required"}), 400
    return jsonify({"id": write_event(event_type, severity, description)}), 201
```

**IAM:**
```bash
gcloud projects add-iam-policy-binding cloudock-503009 --member=serviceAccount:cloud-run-sa@cloudock-503009.iam.gserviceaccount.com --role=roles/datastore.user
```
**Why:** `datastore.user` (not `datastore.owner`) — read/write on data,
no ability to manage indexes, security rules, or delete the database
itself. Firestore IAM doesn't support scoping below project level (no
per-collection binding), so project-wide is as tight as this gets — unlike
the Secret Manager binding below, which can go narrower.

## Secret Manager

```bash
# requirements.txt
google-cloud-secret-manager==2.18.0
```
```bash
gcloud secrets create app-config --replication-policy=automatic
echo -n '{"env":"prod","version":"1.0","project":"cloudock"}' | gcloud secrets versions add app-config --data-file=-
```
**Windows/PowerShell note:** `echo -n` is a bash idiom — PowerShell's `echo` doesn't support `-n`, and piping to a native process's stdin this way can silently store an empty secret version rather than erroring loudly. On PowerShell, write to a file first instead of piping:
```powershell
$utf8NoBom = New-Object System.Text.UTF8Encoding $false
[System.IO.File]::WriteAllText("$PWD\app-config.json", '{"env":"prod","version":"1.0","project":"cloudock"}', $utf8NoBom)
gcloud secrets versions add app-config --data-file=app-config.json
Remove-Item app-config.json
```
Verify with `gcloud secrets versions access latest --secret=app-config` before redeploying — it should print the JSON back exactly, not come back blank.

```python
def access_secret(secret_id):
    from google.cloud import secretmanager
    client = secretmanager.SecretManagerServiceClient()
    name = f"projects/{PROJECT}/secrets/{secret_id}/versions/latest"
    response = client.access_secret_version(request={"name": name})
    return json.loads(response.payload.data.decode("UTF-8"))

app_config = access_secret("app-config")  # runs once at startup, not per-request
```
**Fixed from the original task text:** `PROJECT_ID = os.environ.get("GOOGLE_CLOUD_PROJECT")`
would silently be `None` — Cloud Run only auto-sets `K_SERVICE`,
`K_REVISION`, `K_CONFIGURATION`, and `PORT`, not `GOOGLE_CLOUD_PROJECT`.
Replaced with a small `_detect_project()` helper using
`google.auth.default()`, which works reliably both on Cloud Run and
locally (returns `None` locally instead of raising).

**Why read at startup, not per-request:** one API call at boot instead of
one per request — lower latency, far fewer Secret Manager calls. Trade-off,
recorded deliberately: this also means a bad/missing secret crashes the
container at startup rather than degrading one request. Wrapped in a
try/except purely for a clear log line before re-raising, so Cloud Run
logs show *why* it crash-looped instead of a bare traceback.

**IAM — scoped to one secret, not project-wide:**
```bash
gcloud secrets add-iam-policy-binding app-config --member=serviceAccount:cloud-run-sa@cloudock-503009.iam.gserviceaccount.com --role=roles/secretmanager.secretAccessor
```
**Why this one's tighter than the Firestore binding:** Secret Manager IAM
*does* support per-resource scoping — this binding only ever grants access
to `app-config` specifically, not every secret that might exist in the
project later. Worth noticing as the more precise sibling of the
`datastore.user` binding above.

**If the rebuilt image crash-loops right after this step:** IAM binding
propagation can take up to a minute or two. Wait and let Cloud Run retry
before assuming something's actually broken.

## Verify no hardcoded credentials

```powershell
Select-String -Path app\*.py, app\Dockerfile, app\requirements.txt -Pattern "password|secret_key|api_key|token" -CaseSensitive:$false
```
(PowerShell equivalent of the task's `grep -rn` — expect zero real
credential matches; the string `"secret_key"` in variable/route *names*
like `SecretManagerServiceClient` is fine, actual literal values are what
this is checking for.)

## Testing end-to-end

```powershell
$url = gcloud run services describe secure-dashboard --region=asia-southeast1 --format="get(status.url)"

curl.exe -X POST "$url/events" -H "Content-Type: application/json" -d '{"type":"login","severity":"low","description":"test event"}'
curl.exe "$url/events"
```
**Why POST then GET:** proves the full round trip — write reaches
Firestore, read reflects it back — rather than testing each direction in
isolation.

## Infrastructure reference

| Resource | Name | Details |
|---|---|---|
| Firestore database | `(default)` | Native mode, `asia-southeast1` |
| Firestore collection | `security_events` | written by `write_event()`, read by `GET /events` |
| Secret | `app-config` | `{"env":"prod","version":"1.0","project":"cloudock"}` |
| IAM — Firestore | `cloud-run-sa` → `roles/datastore.user` | project-wide (Firestore has no finer grain) |
| IAM — Secret Manager | `cloud-run-sa` → `roles/secretmanager.secretAccessor` | scoped to `app-config` only |
| Image | `secure-dashboard:v2` | pushed to `cloudock-apps` |

## Decision log
- Firestore database creation (Native mode, `asia-southeast1`) added as an
  explicit step — missing from the original task, and a one-time
  irreversible choice per project, worth making deliberately.
- Project ID detection standardized on a `_detect_project()` helper using
  `google.auth.default()`, replacing the `GOOGLE_CLOUD_PROJECT` env var
  the original Secret Manager code assumed — that variable is never
  actually set by Cloud Run.
- Secret read kept at startup (fail-fast) per the task's own instruction,
  with a log line added before the re-raise purely for diagnosability —
  behavior unchanged, just visible when it fails.

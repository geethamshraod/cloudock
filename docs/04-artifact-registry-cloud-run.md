# M3 — Artifact Registry + Cloud Run Deploy

**Goal:** Push the Flask dashboard image (built and locally tested on
July 29) to Artifact Registry, then deploy it to Cloud Run behind a
purpose-built service account — not the default compute SA.

## 1. Final local retest

```bash
docker build -t secure-dashboard:v1 .
docker run -p 8080:8080 secure-dashboard:v1
```
Verify in a browser: `localhost:8080`, `localhost:8080/health`,
`localhost:8080/events`. Then:
```bash
docker ps                    # find the container ID
docker stop <container_id>
```
**Why:** Re-testing locally right before pushing catches anything that
drifted since July 29 (dependency updates, local Docker changes) while
it's still cheap to fix — a failed Cloud Run deploy is a slower feedback
loop than a failed local run.

## 2. Artifact Registry repo

```bash
gcloud artifacts repositories create cloudock-apps --repository-format=docker --location=asia-southeast1 --description="cloudock container images"
```
**Why:** `artifactregistry.googleapis.com` was already enabled back in the
original environment setup — no new API to turn on here, just a repo
inside it. Docker format specifically, since that's what's being pushed;
Artifact Registry also supports npm/Maven/etc. repos, keeping this scoped
avoids mixing image and package storage in the same repo later.

## 3. Docker auth for Artifact Registry

```bash
gcloud auth configure-docker asia-southeast1-docker.pkg.dev
```
**Why:** This registers a credential helper so plain `docker push`/`pull`
against that specific regional Artifact Registry hostname authenticate
using your `gcloud` login, rather than needing a separate `docker login`
with a token you'd have to manage yourself.

## 4. Tag + push

```bash
docker tag secure-dashboard:v1 asia-southeast1-docker.pkg.dev/cloudock-503009/cloudock-apps/secure-dashboard:v1
docker push asia-southeast1-docker.pkg.dev/cloudock-503009/cloudock-apps/secure-dashboard:v1
```
**Why:** `docker tag` doesn't rebuild anything — it just adds a second
name (the full registry path) pointing at the same local image, which is
what `docker push` actually needs to know where to send it.


## 5. Cloud Run service account

```bash
gcloud iam service-accounts create cloudock-run-sa --display-name="Cloud Run Service Account"
```
**Why:** Same least-privilege principle as `cloudock-storage-writer` in
M2 — a purpose-built service account for exactly this service, rather
than letting the deployment fall back to the default compute service
account, which tends to carry broader project-level access than a single
dashboard app actually needs. This SA currently has no roles bound to it
at all — intentional for now, since the app doesn't call any other GCP
API yet; add roles later only if/when it actually needs to (e.g. reading
from the M2 storage bucket).

## 6. Deploy

```bash
gcloud run deploy cloudock-dashboard \
  --image=asia-southeast1-docker.pkg.dev/cloudock-503009/cloudock-apps/secure-dashboard:v1 \
  --platform=managed \
  --region=asia-southeast1 \
  --allow-unauthenticated \
  --min-instances=0 \
  --max-instances=5 \
  --service-account=cloudock-run-sa@cloudock-503009.iam.gserviceaccount.com \
  --port=8080
```
**Why:** `--allow-unauthenticated` is a deliberate choice, not a default
left on accident — this is a public-facing demo dashboard, same reasoning
as `cloudock-allow-http` being open in M2. `--min-instances=0` lets it
scale to zero when idle, in keeping with the $0 budget approach from day
one. `--port=8080` matches both the Dockerfile's `EXPOSE 8080` and the
Flask app's `app.run(host="0.0.0.0", port=8080)` — Cloud Run defaults to
8080 anyway, so this flag is redundant in practice but makes the
assumption explicit rather than implicit.

**If this errors with a permission/actAs message:** deploying *with* a
custom service account requires the deploying identity to have
`roles/iam.serviceAccountUser` on that SA. Unlikely to bite you on a
personal-account Owner setup, but if it does:
```bash
gcloud iam service-accounts add-iam-policy-binding cloudock-run-sa@cloudock-503009.iam.gserviceaccount.com --member="user:<your-email>" --role="roles/iam.serviceAccountUser"
```

## 7. Get the URL, test it

```bash
gcloud run services describe cloudock-dashboard --region=asia-southeast1 --format="get(status.url)"
```
Open the URL, then `<url>/health` and `<url>/events` — same three routes
verified locally in step 1, now over the public Cloud Run URL.

## 8. Verify the service account in the console

Cloud Run → `cloudock-dashboard` → **Security** tab → confirm
`service_account = cloudock-run-sa`, **not**
`<project-number>-compute@developer.gserviceaccount.com`.
**Why:** This is the actual proof the least-privilege setup from step 5
took effect — a deploy can silently fall back to the default compute SA
if the `--service-account` flag is mistyped or omitted, and everything
else in the deploy would still succeed and look fine.

## Infrastructure reference

| Resource | Name | Details |
|---|---|---|
| Artifact Registry repo | `cloudock-apps` | Docker format, `asia-southeast1` |
| Image | `secure-dashboard:v1` | pushed to `cloudock-apps` |
| Service account | `cloudock-run-sa` | no roles bound yet |
| Cloud Run service | `cloudock-dashboard` | `asia-southeast1`, public, min 0 / max 5 instances, port 8080 |

## Decision log
- Kept the image name `secure-dashboard` (app identity) while renaming
  the surrounding GCP resources to the `cloudock-` prefix (project
  infra) — same split applied to the M2 storage bucket name.
- `cloudock-run-sa` created with zero roles bound — deliberately minimal
  until the app actually needs to call another GCP service.
- Public access (`--allow-unauthenticated`) is intentional for this demo
  dashboard, recorded here so it doesn't read as an oversight later.

# Environment & Tooling Setup

This document records the initial environment setup for the **cloudock**
project: local Git/GitHub configuration and Google Cloud Platform (GCP) account,
CLI, and project setup completed before any infrastructure work began.

## 1. Version Control Setup

### 1.1 Git Identity
```bash
git config --global user.name "geethamshraod"
git config --global user.email "geethamshraodharbasth@gmail.com"
```

### 1.2 SSH Authentication
- Generated an `ed25519` SSH key pair for GitHub authentication (`ssh-keygen -t ed25519`).
- Public key added under GitHub → Settings → SSH and GPG Keys.
- Private key stays local only — never committed.

### 1.3 Repository Initialization
```bash
git init
git add .
git commit -m "init: project structure"
git remote add origin git@github.com:geethamshraod/cloudock.git
git push -u origin main
```

| Item | Value |
|---|---|
| Repository | `secure-cloud-ops` |
| Default branch | `main` |
| Remote | `git@github.com:<username>/secure-cloud-ops.git` |

## 2. GCP Account & Billing Safeguards

| Item | Value |
|---|---|
| Account type | Personal Gmail |
| Budget | $0 |
| Alert thresholds | 50%, 90%, 100% (email) |

> A $0 budget with alerts at 50/90/100% is a deliberate guardrail: any usage
> that starts generating cost — even on the free tier — triggers an alert

## 3. gcloud CLI

| Item | Value |
|---|---|
| Install guide | cloud.google.com/sdk/docs/install |
| OS | `Windows` |
| CLI version (`gcloud --version`) | `576.0.0` |

### Authentication
```bash
gcloud auth login                     # authenticates the CLI itself (browser-based)
gcloud auth application-default login # ADC — credentials picked up by SDKs/Terraform/client libraries
```

## 4. Project Setup

| Item | Value |
|---|---|
| Project ID | `cloudock-503009` |
| Set as default | `gcloud config set project cloudock-503009` |

## 5. APIs Enabled

```bash
gcloud services enable \
  compute.googleapis.com \
  run.googleapis.com \
  artifactregistry.googleapis.com \
  storage.googleapis.com \
  firestore.googleapis.com \
  secretmanager.googleapis.com
```

| API | Purpose |
|---|---|
| `compute.googleapis.com` | Compute Engine (VMs) |
| `run.googleapis.com` | Cloud Run (serverless containers) |
| `artifactregistry.googleapis.com` | Container / package image storage |
| `storage.googleapis.com` | Cloud Storage buckets |
| `firestore.googleapis.com` | Firestore NoSQL database |
| `secretmanager.googleapis.com` | Secret Manager for credentials/keys |

**Verification**
```bash
gcloud services list --enabled
```
Confirmed all 6 APIs above are listed as enabled.

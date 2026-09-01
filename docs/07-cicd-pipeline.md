# M6 — GitHub Actions CI/CD Pipeline

**Goal:** Every push and pull request against `main` is scanned
(Checkov for Terraform, Trivy for the container image) before anything
deploys; only a passing push to `main` reaches Cloud Run, authenticated
via Workload Identity Federation — no service account key ever stored
in GitHub.

## Pipeline structure — `.github/workflows/deploy.yml`

Two jobs:

- **`security-scan`** — runs on every push and pull request. Checks out
  the repo, authenticates to GCP via WIF, runs Checkov against
  `terraform/`, builds the Docker image, runs Trivy against it
  (`CRITICAL` severity, build fails on any finding), and — only on an
  actual push to `main` — pushes the scanned image to Artifact Registry.
- **`deploy`** — depends on `security-scan`, runs only on push to
  `main`. Authenticates independently (jobs run on separate runners;
  nothing carries over between them) and deploys the already-pushed
  image to Cloud Run.

```yaml
name: Secure Deploy Pipeline

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  security-scan:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      id-token: write

    steps:
      - uses: actions/checkout@v4

      - name: Authenticate to GCP (keyless via WIF)
        uses: google-github-actions/auth@v3
        with:
          workload_identity_provider: "projects/785831511320/locations/global/workloadIdentityPools/github-pool/providers/github-provider"
          service_account: "cloud-run-sa@cloudock-503009.iam.gserviceaccount.com"

      - name: Setup gcloud
        uses: google-github-actions/setup-gcloud@v2

      - name: Checkov IaC Security Scan
        uses: bridgecrewio/checkov-action@v12
        with:
          directory: terraform/
          soft_fail: false
          quiet: false

      - name: Build Docker image
        run: docker build -t secure-dashboard:${{ github.sha }} ./app

      - name: Trivy vulnerability scan
        uses: aquasecurity/trivy-action@v0.36.0
        with:
          image-ref: "secure-dashboard:${{ github.sha }}"
          exit-code: "1"
          severity: "CRITICAL"
          format: "table"
          trivyignores: ".trivyignore"

      - name: Configure Docker for Artifact Registry
        if: github.ref == 'refs/heads/main' && github.event_name == 'push'
        run: gcloud auth configure-docker asia-southeast1-docker.pkg.dev --quiet

      - name: Push to Artifact Registry
        if: github.ref == 'refs/heads/main' && github.event_name == 'push'
        run: |
          docker tag secure-dashboard:${{ github.sha }} asia-southeast1-docker.pkg.dev/cloudock-503009/secure-apps/secure-dashboard:${{ github.sha }}
          docker push asia-southeast1-docker.pkg.dev/cloudock-503009/secure-apps/secure-dashboard:${{ github.sha }}

  deploy:
    needs: security-scan
    if: github.ref == 'refs/heads/main' && github.event_name == 'push'
    runs-on: ubuntu-latest
    permissions:
      contents: read
      id-token: write

    steps:
      - name: Authenticate to GCP (keyless via WIF)
        uses: google-github-actions/auth@v3
        with:
          workload_identity_provider: "projects/785831511320/locations/global/workloadIdentityPools/github-pool/providers/github-provider"
          service_account: "cloud-run-sa@cloudock-503009.iam.gserviceaccount.com"

      - name: Setup gcloud
        uses: google-github-actions/setup-gcloud@v2

      - name: Deploy to Cloud Run
        run: gcloud run deploy secure-dashboard --image=asia-southeast1-docker.pkg.dev/cloudock-503009/secure-apps/secure-dashboard:${{ github.sha }} --region=asia-southeast1
```

Third-party actions are pinned to real version tags (`v12`, `v0.36.0`),
not mutable branches (`@master`) — `trivy-action` specifically has a
prior real supply-chain incident, which is why its maintainers moved to
signed version tags.

## Workload Identity Federation setup

```powershell
gcloud services enable iamcredentials.googleapis.com --project=cloudock-503009

gcloud iam workload-identity-pools create github-pool --location=global --project=cloudock-503009 --display-name="GitHub Actions Pool"

gcloud iam workload-identity-pools providers create-oidc github-provider `
  --location=global --workload-identity-pool=github-pool --project=cloudock-503009 `
  --issuer-uri="https://token.actions.githubusercontent.com" `
  --attribute-mapping="google.subject=assertion.sub,attribute.repository=assertion.repository,attribute.ref=assertion.ref" `
  --attribute-condition="assertion.repository == 'geethamshraod/cloudock'"

gcloud iam service-accounts add-iam-policy-binding cloud-run-sa@cloudock-503009.iam.gserviceaccount.com `
  --role="roles/iam.workloadIdentityUser" `
  --member="principalSet://iam.googleapis.com/projects/785831511320/locations/global/workloadIdentityPools/github-pool/attribute.repository/geethamshraod/cloudock"
```

## Branch protection

GitHub → repo → **Settings** → **Branches** → **Add branch protection
rule**:
- Branch name pattern: `main` (no quotes)
- Require a pull request before merging
- Require status checks to pass before merging → search and select
  `security-scan`

## Testing

```powershell
git checkout -b feature-test
# make a change
git commit -am "test: verify CI/CD pipeline"
git push -u origin feature-test
```
Open a PR into `main`, confirm `security-scan` runs and passes, merge,
confirm `deploy` runs, then verify:
```powershell
gcloud run services describe secure-dashboard --region=asia-southeast1 --format="get(status.latestReadyRevisionName)"
```

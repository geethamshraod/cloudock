# Terraform — cloudock Infrastructure as Code

**Supersedes:** `06-terraform-vpc-storage-compute.md` and
`07-terraform-cloudrun-monitoring-wif.md` (both merged into this file —
safe to remove from the repo once this is committed).

**Goal:** Express the entire cloudock environment — network, compute,
storage, application layer, observability, security policy, and CI/CD
identity — as version-controlled Infrastructure as Code, reconciled with
what's already running (built manually across M1–M4) rather than
replacing it.

**Region/zone/naming:** `asia-southeast1` / `asia-southeast1-b`
throughout. Resource names follow the project's real, confirmed naming —
see **Naming confidence**, below, before trusting any name for `import`.

---

## Folder structure

```
terraform/
├── .gitignore
├── README.md
├── variables.tf
├── backend.tf
├── main.tf
├── vpc.tf           -- network, subnets, firewall rules, NAT
├── storage.tf        -- Cloud Storage bucket + IAM binding
├── compute.tf         -- webserver VM, instance group, load balancer
├── cloudrun.tf        -- Artifact Registry, Cloud Run service + public access
├── iam.tf             -- service accounts, project-level IAM bindings
├── secrets.tf         -- Secret Manager secret + version + IAM binding
├── database.tf        -- Firestore database
├── monitoring.tf       -- uptime check + error-rate alert policy
├── armor.tf            -- Cloud Armor WAF policy (real rules)
└── wif.tf              -- Workload Identity Federation for GitHub Actions
```

---

## Prerequisites

**1. Terraform state bucket** — must exist before `terraform init`;
Terraform never creates its own backend bucket:
```powershell
gsutil mb -b on -l asia-southeast1 gs://cloudock-503009-tfstate
gsutil versioning set on gs://cloudock-503009-tfstate
```

**2. `terraform.tfvars`** (gitignored — never commit this file):
```hcl
project_id       = "cloudock-503009"
management_ip    = "<your current public IP>"
ssh_public_key   = "<contents of your .pub file>"
github_user      = "<your GitHub username>"
app_config_json  = "{\"env\":\"prod\",\"version\":\"1.0\",\"project\":\"cloudock\"}"
```
Without this, `terraform import`/`plan`/`apply` will interactively prompt
for every required variable, on every single command.

**Note on `backend.tf`:** its bucket name is a literal string
(`cloudock-503009-tfstate`), not `"${var.project_id}-tfstate"` — backend
blocks are evaluated before variables exist, so they can't reference them.

---

## The infrastructure, section by section

### Networking — `vpc.tf`
Custom-mode VPC (`cloudock-vpc`), public/private subnets, and a
default-deny/explicit-allow firewall posture: SSH restricted to one `/32`,
IAP tunnel range allowed separately (`35.235.240.0/20`), HTTPS+HTTP open
to the internet, the LB's health-check ranges (`130.211.0.0/22`,
`35.191.0.0/16`) allowed explicitly, and a catch-all deny at the lowest
priority. Cloud NAT gives the private subnet outbound-only internet
access. Two firewall rules here (`allow_iap_ssh`, `allow_lb_health_check`)
aren't in most task lists that produced this file — they're the same two
gaps that caused real SSH/health-check failures earlier in the project,
added here proactively instead of waiting to hit them again.

### Storage & Compute — `storage.tf`, `compute.tf`
A versioned, lifecycle-managed Cloud Storage bucket, written to by a
service account holding only `objectCreator` — never `objectAdmin`. A
public-subnet webserver VM behind a full HTTP Load Balancer: instance
group, health check, backend service, URL map, target proxy, forwarding
rule. Two resources were added beyond the original scope here too: a
dedicated `web_sa` service account (referenced by the VM but never
declared in the source task), and the `security_policy` attachment
linking the backend service to the Cloud Armor policy in `armor.tf` —
without that one line, the WAF policy exists but protects nothing.

### Application layer — `cloudrun.tf`, `iam.tf`, `secrets.tf`, `database.tf`
Artifact Registry repo (`secure-apps`) and the Cloud Run service
(`secure-dashboard`), running under `cloud-run-sa` — a dedicated identity,
not the default compute service account. `iam.tf` centralizes every
service account and project-level IAM grant in one place: `cloud-run-sa`
(Firestore access), `storage-writer` (bucket access). `secrets.tf` defines
both the `app-config` secret *and* an actual version of it — a secret
container with no version has no content, the same failure mode that
caused a startup crash-loop earlier in the project, just via Terraform
instead of a mistranslated shell command this time. `database.tf` points
at the real Firestore database, in `asia-southeast1` — matching where it
was actually created during that same incident, since Firestore location
is permanent once set.

**The one addition with real functional consequence:**
`google_cloud_run_v2_service_iam_member` in `cloudrun.tf`, granting
`allUsers` → `roles/run.invoker`. `ingress = "INGRESS_TRAFFIC_ALL"`
controls where traffic can originate, not who's allowed to invoke the
service — that's a separate binding, and without it this configuration
would recreate the exact "You don't have access" failure debugged several
sessions ago.

### Observability & security — `monitoring.tf`, `armor.tf`
An uptime check against `/health` from three global regions, and an
alert policy that fires on a sustained 5xx error rate — its notification
channel list defaults to empty, so it's silent until a real channel
(email, etc.) is created and supplied. `armor.tf` gives the Cloud Armor
policy actual teeth for the first time: rules blocking SQL injection,
XSS, RFI, LFI, RCE, and known scanner signatures, plus the required
default-allow rule at the lowest possible priority. M2's original policy
was created empty and explicitly flagged as unfinished at the time — this
is that follow-through.

### CI/CD foundation — `wif.tf`
A Workload Identity Federation pool and OIDC provider trusting GitHub
Actions' token issuer, plus the binding letting a GitHub Actions workflow
in this specific repo impersonate `cloud-run-sa` — all without a single
long-lived service account key ever existing in GitHub's secrets store.
`cloud-run-sa` also picks up three additional project roles here
(`run.admin`, `artifactregistry.writer`, `serviceAccountUser`) so it can
actually perform deployments once CI/CD is wired up.

---

## Fixes made to the original task text

| File | Issue found | Fix |
|---|---|---|
| `vpc.tf` | Two required firewall rules missing (IAP SSH, LB health-check ranges) | Added both, matching earlier real-world failures |
| `compute.tf` | Referenced an undeclared `web_sa`; no instance group; Armor policy never attached | Added `web_sa`, `google_compute_instance_group`, `security_policy` line |
| `storage.tf` | Referenced an undeclared SA; later duplicated under a different name in `iam.tf` | Consolidated into one SA, in `iam.tf`, under its literal name |
| `cloudrun.tf` | No public-access IAM binding; image tag `:latest` never pushed | Added `run.invoker` binding for `allUsers`; switched to `var.image_tag` |
| `database.tf` | `location_id = "us-central1"` | Corrected to `asia-southeast1` — matches the real, already-created database |
| `secrets.tf` | Secret container declared, no version/content | Added `google_secret_manager_secret_version`, sourced from a variable |
| `monitoring.tf` | Unescaped nested quotes in the alert filter string | Escaped — invalid HCL as originally written |
| `armor.tf` | Real rules created, but never attached to the backend service | Linked via `security_policy` in `compute.tf` |
| `wif.tf` | Hardcoded the pre-rename repo name `secure-cloud-ops` | Corrected to `var.github_repo` = `"cloudock"` |

---

## Naming confidence — verify before trusting for `import`

**Confirmed live**, direct terminal evidence: `secure-apps` (Artifact
Registry, `asia-southeast1`), `cloud-run-sa`, `secure-dashboard`,
`app-config` secret, Firestore `(default)` in `asia-southeast1`.

```powershell
gcloud iam service-accounts list --project=cloudock-503009
```
Update `iam.tf`'s `account_id` to match whichever actually exists before
importing it.

---

## Running it

```powershell
cd terraform
terraform init
terraform validate
terraform fmt
```
These couldn't be run in advance from this side — no network access to
HashiCorp's provider registry here. Every file was written and reviewed
by hand for referential correctness; running the real commands and
reporting the output is the actual verification step.

---

## M5 — Apply plan: import, not destroy

Two approaches exist for reconciling Terraform with infrastructure that
already exists. **Only import is safe to use here.** Destroying and
reapplying would permanently delete the real Firestore database —
erasing every `security_events` document created while testing `/events`
— along with the actual working, already-debugged deployment. That's
irreversible data loss, not a style choice.

**Step 1 — verify what's actually live:**
```powershell
gcloud compute networks list --project=cloudock-503009
gcloud compute networks subnets list --project=cloudock-503009
gcloud compute firewall-rules list --project=cloudock-503009
gcloud compute instances list --project=cloudock-503009
gcloud iam service-accounts list --project=cloudock-503009
gcloud artifacts repositories list --project=cloudock-503009 --location=asia-southeast1
gcloud run services list --project=cloudock-503009 --region=asia-southeast1
gcloud secrets list --project=cloudock-503009
gcloud firestore databases list --project=cloudock-503009
gcloud compute security-policies list --project=cloudock-503009
```

**Step 2 — `terraform plan` first anyway.** Read-only and safe. Anything
it proposes to "create" that also appears above needs `import`ing first;
anything genuinely new can just be applied directly.

**Step 3 — import every resource that already exists.** IAM-binding
resources (`*_iam_member`) don't need this — granting an already-granted
role is a safe no-op — so this list is only the primary resources:

**VPC and networking:**
```powershell
terraform import google_compute_network.vpc projects/cloudock-503009/global/networks/cloudock-vpc
terraform import google_compute_subnetwork.public projects/cloudock-503009/regions/asia-southeast1/subnetworks/cloudock-public-subnet
terraform import google_compute_subnetwork.private projects/cloudock-503009/regions/asia-southeast1/subnetworks/cloudock-private-subnet
terraform import google_compute_firewall.allow_ssh projects/cloudock-503009/global/firewalls/cloudock-allow-ssh
terraform import google_compute_firewall.allow_iap_ssh projects/cloudock-503009/global/firewalls/cloudock-allow-iap-ssh
terraform import google_compute_firewall.allow_https projects/cloudock-503009/global/firewalls/cloudock-allow-https
terraform import google_compute_firewall.allow_lb_health_check projects/cloudock-503009/global/firewalls/cloudock-allow-lb-health-check
terraform import google_compute_firewall.deny_all projects/cloudock-503009/global/firewalls/cloudock-deny-all-ingress
terraform import google_compute_router.nat_router projects/cloudock-503009/regions/asia-southeast1/routers/cloudock-nat-router
terraform import google_compute_router_nat.nat projects/cloudock-503009/regions/asia-southeast1/routers/cloudock-nat-router/cloudock-nat-gateway
```
`allow_https` here covers both 443 and 80 as one resource; the live setup
likely has them as two separate rules (`cloudock-allow-https`,
`cloudock-allow-http`). Expect `terraform plan` to show a widening diff
on this rule after import — expected, not an error, but worth deciding
deliberately whether to merge them this way or keep them separate.

**Compute and load balancer:**
```powershell
terraform import google_compute_instance.webserver projects/cloudock-503009/zones/asia-southeast1-b/instances/cloudock-webserver
terraform import google_compute_instance_group.web_ig projects/cloudock-503009/zones/asia-southeast1-b/instanceGroups/cloudock-web-ig
terraform import google_compute_health_check.http projects/cloudock-503009/global/healthChecks/cloudock-http-health-check
terraform import google_compute_backend_service.web_backend projects/cloudock-503009/global/backendServices/cloudock-web-backend
terraform import google_compute_url_map.web_map projects/cloudock-503009/global/urlMaps/cloudock-web-map
terraform import google_compute_target_http_proxy.http_proxy projects/cloudock-503009/global/targetHttpProxies/cloudock-http-proxy
terraform import google_compute_global_forwarding_rule.http_rule projects/cloudock-503009/global/forwardingRules/cloudock-http-rule
```
`google_service_account.web_sa` is new — not imported, `apply` creates it.

**Storage:**
```powershell
terraform import google_storage_bucket.security_assets cloudock-503009-security-assets
```

**Identity and application layer:**
```powershell
terraform import google_service_account.cloud_run_sa projects/cloudock-503009/serviceAccounts/cloud-run-sa@cloudock-503009.iam.gserviceaccount.com
terraform import google_artifact_registry_repository.secure_apps projects/cloudock-503009/locations/asia-southeast1/repositories/secure-apps
terraform import google_cloud_run_v2_service.dashboard projects/cloudock-503009/locations/asia-southeast1/services/secure-dashboard
terraform import google_secret_manager_secret.app_config projects/cloudock-503009/secrets/app-config
terraform import google_firestore_database.default 'projects/cloudock-503009/databases/(default)'
terraform import google_compute_security_policy.cloudock projects/cloudock-503009/global/securityPolicies/armor-policy
```
Quote the Firestore ID exactly as shown in PowerShell, so the parentheses
in `(default)` aren't parsed as anything special.

**Not imported — genuinely new:** `google_service_account.web_sa`, both
`google_iam_workload_identity_pool*` resources, and
`google_secret_manager_secret_version.app_config_v1` (adding one more
version is harmless even if it duplicates content already there).

**Step 4 — `terraform plan` again.** Should now show "no changes" for
everything just imported, plus "create" only for what's genuinely new
(monitoring, alerting, WIF, `web_sa`).

**Step 5 — `terraform apply`**, only once that plan looks right.

**After apply:**
```powershell
gcloud compute networks list --project=cloudock-503009
gcloud run services list --project=cloudock-503009 --region=asia-southeast1
```
Plus an actual browser/curl check of the Cloud Run URL.

---

## M6 — Workload Identity Federation

Once `wif.tf` is applied — via the flow above, or standalone first with
`terraform apply -target=google_iam_workload_identity_pool.github` — the
pool, provider, and every related IAM binding exist as one reviewable
unit, unlike M1–M4 where Terraform came after the manual setup.

Project number (only needed to hand-verify the `principalSet` string):
```powershell
gcloud projects describe cloudock-503009 --format="value(projectNumber)"
```

---

## Decision log
- Confirmed real resource names take precedence over earlier suggested
  `cloudock-` renamings wherever the two conflict — matching reality
  matters more than internal naming consistency for anything headed
  toward `import`.
- `cloud-run-sa` now carries both runtime permissions (Firestore, one
  secret) and CI/CD deployer permissions (`run.admin`,
  `artifactregistry.writer`, `serviceAccountUser`) — one identity
  spanning two trust boundaries. Implemented as specified; a dedicated
  CI/CD service account is the more isolated alternative if that becomes
  a concern later.
- Destroy/recreate rejected outright for this project's current state —
  real Firestore data and a working, already-debugged deployment are both
  at stake. Import only.

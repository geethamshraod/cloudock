# M2 — VM + Storage + Load Balancer

**Goal:** Public-facing nginx VM behind an HTTP Load Balancer with Cloud
Armor attached, plus a versioned/lifecycle-managed Cloud Storage bucket
accessed via a least-privilege service account.


## 1. Web server VM

```bash
gcloud compute instances create cloudock-webserver \
  --machine-type=e2-micro \
  --subnet=cloudock-public-subnet \
  --zone=asia-southeast1-b \
  --tags=cloudock-web-server \
  --image-family=debian-11 \
  --image-project=debian-cloud \
  --metadata=ssh-keys="user:$(cat ~/.ssh/id_ed25519.pub)"

gcloud compute ssh cloudock-webserver --zone=asia-southeast1-b
```
```bash
# inside the VM
sudo apt-get update && sudo apt-get install -y nginx && sudo systemctl enable nginx && sudo systemctl start nginx
exit
```
**Why:** `--metadata=ssh-keys=...` injects your public key directly —
password auth is never enabled, so there's no password to brute-force in
the first place. `--tags=cloudock-web-server` is what the two new firewall
rules below (and nothing else) will target — learned from M1 that an
untagged instance silently doesn't match tag-scoped rules, so this is
applied at creation this time, not discovered missing later.

## 2. Firewall — the two rules the original plan was missing

```bash
gcloud compute firewall-rules create cloudock-allow-http \
  --network=cloudock-vpc --action=allow --rules=tcp:80 \
  --source-ranges=0.0.0.0/0 --target-tags=cloudock-web-server

gcloud compute firewall-rules create cloudock-allow-lb-health-check \
  --network=cloudock-vpc --action=allow --rules=tcp:80 \
  --source-ranges=130.211.0.0/22,35.191.0.0/16 --target-tags=cloudock-web-server
```
**Why:** `cloudock-allow-http` opens the port nginx actually serves on to
the public internet — this is the intentionally-public part of the
project, matching the VM's placement in the public subnet.
`cloudock-allow-lb-health-check` is separate and easy to miss: Google's
health-check and L7 load-balancer probes come from two fixed IP ranges,
not from "the internet" as a whole — without this rule the backend never
passes its health check, regardless of whether the site works fine from a
browser.

**Verify (browser):** open `http://<webserver-external-ip>` — default
nginx page should load. Get the IP with:
```bash
gcloud compute instances describe cloudock-webserver --zone=asia-southeast1-b --format="get(networkInterfaces[0].accessConfigs[0].natIP)"
```

## 3. Cloud Storage bucket

```bash
gsutil mb -b on -l asia-southeast1 gs://cloudock-503009-security-assets
gsutil versioning set on gs://cloudock-503009-security-assets
```
```bash
# lifecycle.json
{"rule":[{"action":{"type":"Delete"},"condition":{"age":90}}]}
```
```bash
gsutil lifecycle set lifecycle.json gs://cloudock-503009-security-assets
```
**Why:** `-b on` turns on uniform bucket-level access at creation —
permissions are IAM-only from the start, rather than a mix of IAM and
legacy per-object ACLs, which is the simpler and more auditable model.
`-l asia-southeast1` keeps data in the same region as the rest of the
project rather than defaulting to a US multi-region. Versioning protects
against accidental overwrite/delete — old versions stay recoverable. The
90-day lifecycle rule auto-deletes objects past that age, which controls
storage cost but is worth a second look if this bucket is ever meant to
hold anything with a longer retention requirement (audit evidence, etc.)
— 90 days is a cost decision here, not a compliance one.


## 4. Least-privilege service account

```bash
gcloud iam service-accounts create cloudock-storage-writer --display-name="Storage Writer SA"

gcloud projects add-iam-policy-binding cloudock-503009 \
  --member=serviceAccount:cloudock-storage-writer@cloudock-503009.iam.gserviceaccount.com \
  --role=roles/storage.objectCreator
```
**Why:** `roles/storage.objectCreator` allows writing *new* objects only —
it cannot read, list, overwrite, or delete existing objects. That's
deliberately narrower than `objectAdmin`: a compromised credential for
this service account can add data but can't exfiltrate or destroy what's
already there. This is the same least-privilege principle as the SSH
firewall rule in M1, applied to IAM instead of network.

## 5. Load balancer backend

```bash
gcloud compute instance-groups unmanaged create cloudock-web-ig --zone=asia-southeast1-b
gcloud compute instance-groups unmanaged add-instances cloudock-web-ig --instances=cloudock-webserver --zone=asia-southeast1-b

gcloud compute health-checks create http cloudock-http-health-check --port=80

gcloud compute backend-services create cloudock-web-backend --health-checks=cloudock-http-health-check --global
gcloud compute backend-services add-backend cloudock-web-backend --instance-group=cloudock-web-ig --instance-group-zone=asia-southeast1-b --global
```
**Why:** An *unmanaged* instance group is used here because there's a
single, manually-created VM to register — no autoscaling or auto-healing
needed for a one-instance test setup. Worth flagging as a deliberate
simplification: a managed instance group (with an instance template) is
the production-pattern equivalent, and would be the natural upgrade if
this ever needs to scale past one VM. The health check's `--port=80`
matches what nginx actually listens on — this only works because of the
firewall rule added in step 2.

## 6. Cloud Armor

```bash
gcloud compute security-policies create cloudock-armor-policy --description="Cloud Armor policy"
gcloud compute backend-services update cloudock-web-backend --security-policy=cloudock-armor-policy --global
```
**Why:** Attaching the policy now establishes the enforcement point in the
request path. It doesn't do anything protective yet, though — a freshly
created policy only has the default rule (allow everything not otherwise
matched). Worth recording as a known gap, not an oversight: no rate
limiting, no geo-restriction, no OWASP rule set configured yet. Real rules
are a follow-up, not part of this session.

## 7. URL map, proxy, forwarding rule

```bash
gcloud compute url-maps create cloudock-web-map --default-service=cloudock-web-backend
gcloud compute target-http-proxies create cloudock-http-proxy --url-map=cloudock-web-map
gcloud compute forwarding-rules create cloudock-http-rule --global --target-http-proxy=cloudock-http-proxy --ports=80
```
**Why:** These three chain together the actual request path: forwarding
rule (the public IP + port) → target proxy (terminates HTTP) → URL map
(routing logic, here just "everything to one backend") → backend service
→ health-checked instance group.

## Verification

```bash
gcloud compute forwarding-rules list
gcloud compute backend-services get-health cloudock-web-backend --global
```
**Why:** The forwarding rule's IP is where you actually test in a browser.
`get-health` is the check worth running even if the browser test passes —
it confirms the health check specifically sees the backend as HEALTHY,
which is the thing that was silently broken before the firewall fix in
step 2. A page loading and a backend reporting healthy are both worth
confirming independently.

**Results:**
- nginx default page loads at the VM's own external IP
- `cloudock-web-backend` reports HEALTHY for `cloudock-webserver`
- nginx default page loads at the forwarding rule's IP (via the LB, not the VM directly)

## Infrastructure reference

| Resource | Name | Details |
|---|---|---|
| VM | `cloudock-webserver` | e2-micro, `cloudock-public-subnet`, tag `cloudock-web-server` |
| Firewall | `cloudock-allow-http` | tcp:80, `0.0.0.0/0`, tag `cloudock-web-server` |
| Firewall | `cloudock-allow-lb-health-check` | tcp:80, `130.211.0.0/22,35.191.0.0/16`, tag `cloudock-web-server` |
| Bucket | `cloudock-503009-security-assets` | uniform access, versioned, 90-day delete lifecycle, `asia-southeast1` |
| Service account | `cloudock-storage-writer` | `roles/storage.objectCreator` only |
| Instance group | `cloudock-web-ig` | unmanaged, `asia-southeast1-b` |
| Health check | `cloudock-http-health-check` | HTTP, port 80 |
| Backend service | `cloudock-web-backend` | global, health-checked |
| Cloud Armor policy | `cloudock-armor-policy` | attached, default rule only (no custom rules yet) |
| URL map | `cloudock-web-map` | default service → `cloudock-web-backend` |
| Target proxy | `cloudock-http-proxy` | HTTP |
| Forwarding rule | `cloudock-http-rule` | global, port 80 |

## Decision log
- Unmanaged instance group used deliberately for a single-VM setup —
  managed instance group + template is the natural next step if this
  scales past one instance.
- Cloud Armor policy attached with no custom rules yet — enforcement point
  exists, protection doesn't. Follow-up work, not forgotten.
- Storage lifecycle set to 90 days as a cost control, not a retention
  policy — revisit if this bucket ever needs to hold anything for longer.
- Both firewall gaps (HTTP port, LB health-check ranges) caught and fixed
  before running the plan, rather than discovered after a failed browser
  test or a stuck-UNHEALTHY backend.

# M7 — Cloud Monitoring, Cloud Armor, VPC Flow Logs, Security Command Center

**Goal:** Connect a real alert notification channel, confirm the Cloud
Armor WAF and VPC Flow Logs are genuinely active (not just present in
Terraform source), and complete a Security Command Center review.

**Status:** Monitoring, Cloud Armor, and VPC Flow Logs — complete and
verified. Security Command Center — API enabled, first scan pending;
see final section.

---

## Notification channel

Console: **Monitoring → Alerting → Notification Channels → Add → Email**
→ enter address → verify.

```powershell
gcloud beta monitoring channels list --project=cloudock-503009 --format="value(name)"
```

Add the returned ID to `terraform/terraform.tfvars`:
```hcl
notification_channel_id = ["projects/cloudock-503009/notificationChannels/18068433317058757510"]
```

```powershell
cd terraform
terraform apply -target="google_monitoring_alert_policy.error_rate"
cd ..
```

**Verify:**
```powershell
gcloud monitoring uptime list-configs --project=cloudock-503009
gcloud alpha monitoring policies list --project=cloudock-503009 --format="table(displayName,notificationChannels)"
```

**Confirmed:** `cloudock-uptime-check` active, checking `/health` on the
live Cloud Run host every 300s from USA/EUROPE/ASIA_PACIFIC.
`cloudock-error-rate-alert` bound to notification channel
`18068433317058757510`.

---

## Cloud Armor

```powershell
gcloud compute security-policies describe cloudock-armor-policy --project=cloudock-503009 --format="value(rules[].description)"
```
(`gcloud compute security-policies rules list` does not exist as a
command — `describe` on the policy itself is correct.)

**Confirmed — 8 rules present:** Block SQL injection, Block XSS, Block
RFI, Block LFI, Block RCE, Block scanners, Block Log4Shell
(CVE-2021-44228), Default allow.

**Test against the live load balancer IP:**
```powershell
gcloud compute forwarding-rules describe cloudock-http-rule --global --project=cloudock-503009 --format="get(IPAddress)"

curl -v "http://34.110.243.47/?id=1+OR+1=1"       # expect 403
curl -v "http://34.110.243.47/" -A "Nikto/2.1"     # expect 403
curl -v "http://34.110.243.47/" -A "Mozilla/5.0"   # expect 200
curl -v "http://34.110.243.47/?id=' OR 1=1 --"
curl -v "http://34.110.243.47/?q=<script>alert(1)</script>"
```

**View blocks in Cloud Logging:**
```
resource.type="http_load_balancer" AND httpRequest.status=403
```

**Additional hardening applied during verification:**
```powershell
gcloud compute backend-services update cloudock-web-backend --global --enable-logging --project=cloudock-503009
```
Not yet reflected in `compute.tf` — add `log_config { enable = true }`
to `google_compute_backend_service.web_backend` so a future
`terraform apply` doesn't silently revert it.

---

## VPC Flow Logs

```powershell
gcloud compute networks subnets describe cloudock-public-subnet --region=asia-southeast1
gcloud compute networks subnets describe cloudock-private-subnet --region=asia-southeast1
```

**Confirmed on both subnets:** `enableFlowLogs: true`,
`privateIpGoogleAccess: true`, full `logConfig` block
(`aggregationInterval: INTERVAL_5_SEC`, `flowSampling: 0.5`,
`metadata: INCLUDE_ALL_METADATA`).

**View entries in Cloud Logging:**
```
resource.type="gce_subnetwork" AND logName:"compute.googleapis.com/vpc_flows"
```

---

## Security Command Center 

```
https://console.cloud.google.com/security/command-center/overview?project=cloudock-503009
```

Activate the **Standard tier** (free, project-level — no organization
required for this personal-account project). Do not select
Premium/Enterprise.

**Current state:** the Findings tab returned 0 results after activation.
Root cause found while investigating —
`securitycenter.googleapis.com` was not actually enabled on the project:
```powershell
gcloud scc findings list projects/785831511320/sources/- --location=global --filter='state=\"ACTIVE\"'
```
prompted to enable the API, confirmed via:
```powershell
gcloud services enable securitycenter.googleapis.com --project=cloudock-503009
```
Re-running the findings list immediately after still returned
`Listed 0 items` — expected, since Security Health Analytics' first
scan had not yet completed at that point, not evidence of a
misconfiguration.

**Next steps, once resumed:**
```powershell
gcloud scc findings list projects/785831511320/sources/- --location=global --filter='state=\"ACTIVE\"'
```
Re-check the console **Settings** page to confirm the Security Health
Analytics module itself shows Enabled, not just the SCC service overall.
Allow time for the first full scan before treating an empty result as
final. Findings, once present, get reviewed by severity (Critical, then
High) and logged in `SECURITY_HARDENING.md` — filed separately once
real findings exist to record.

### After fix - Verify
```powershell
gcloud compute instances describe cloudock-webserver --zone=asia-southeast1-b --project=cloudock-503009 --format="get(networkInterfaces[0].accessConfigs)"
{'kind': 'compute#accessConfig', 'name': 'external-nat', 'natIP': '35.247.179.207', 'networkTier': 'PREMIUM', 'type': 'ONE_TO_ONE_NAT'} 
```
```powershell
curl -v "http://34.110.243.47/"
```
Site still loads — through the load balancer, exactly as intended.
```powershell
gcloud compute ssh cloudock-webserver --zone=asia-southeast1-b --tunnel-through-iap
```
Admin access still works — via IAP, no public IP required.
If the SSH doesnot work: (Troubleshooting)
```
gcloud compute instances describe cloudock-webserver --zone=asia-southeast1-b --project=cloudock-503009 --format="get(tags.items)"
gcloud compute firewall-rules describe cloudock-allow-iap-ssh --project=cloudock-503009 --format="get(targetTags,sourceRanges)"
ssh-access      35.235.240.0/20
gcloud compute instances add-tags cloudock-webserver --zone=asia-southeast1-b --project=cloudock-503009 --tags=ssh-access
gcloud compute instances reset cloudock-webserver --zone=asia-southeast1-b --project=cloudock-503009
gcloud compute ssh cloudock-webserver --zone=asia-southeast1-b --project=cloudock-503009 --tunnel-through-iap     
```
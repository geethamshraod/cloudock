# THREAT_MODEL.md — cloudock STRIDE Analysis

STRIDE threat model covering every major component of cloudock's
architecture. One row per applicable
threat category per component — not every component faces every STRIDE
category, only the ones genuinely relevant to it.

| Component | Threat | Control Implemented | Residual Risk |
|---|---|---|---|
| **VPC** | Spoofing | Firewall rules restrict source IPs — SSH scoped to one `/32`, LB health checks scoped to Google's fixed GFE ranges only | Low |
| **VPC** | Denial of Service | Cloud Armor adaptive protection sits in front of the load balancer | Low |
| **VPC** | Elevation of Privilege | `cloudock-deny-all-ingress` at priority 65534 — default-deny, explicit-allow posture; nothing reaches an unlisted port | Low |
| **Cloud Run** | Spoofing | Runs under dedicated `cloud-run-sa`, never the default compute service account | Low |
| **Cloud Run** | Information Disclosure | Secrets loaded from Secret Manager at startup — zero credentials in the container image or source code | Low |
| **Cloud Run** | Tampering | Trivy blocks any image with a CRITICAL-severity vulnerability before it can be pushed or deployed | Low |
| **Secret Manager** | Information Disclosure | `secretAccessor` bound to `cloud-run-sa` on the `app-config` secret specifically — not project-wide | Very Low |
| **Secret Manager** | Tampering | Secret versions are immutable and individually tracked; all access logged in Admin Activity logs | Very Low |
| **Firestore** | Tampering | `cloud-run-sa` holds `roles/datastore.user` (read/write) — not `roles/datastore.owner` | Low — `cloud-run-sa` cannot delete the database itself |
| **CI/CD (GitHub Actions)** | Software Integrity | Checkov blocks any Terraform change containing an unresolved insecure-configuration finding | Low |
| **CI/CD (GitHub Actions)** | Container Integrity | Trivy blocks any image build containing a CRITICAL CVE | Low |
| **CI/CD (GitHub Actions)** | Spoofing | Workload Identity Federation — no long-lived JSON key exists anywhere to steal | Low |
| **CI/CD (GitHub Actions)** | Elevation of Privilege | Branch protection requires a pull request and a passing `security-scan` status check before any merge to `main` | Medium — supply-chain risk remains for third-party open-source dependencies (Flask, google-cloud-* libraries, GitHub Actions themselves) |
| **Cloud Armor** | Denial of Service | Adaptive protection (ML-based anomaly detection) plus the 6 OWASP preconfigured rule sets (SQLi, XSS, RFI, LFI, RCE, scanner detection) | Medium — zero-day WAF bypass techniques remain possible against any signature-based WAF |
| **Cloud Armor** | Information Disclosure | WAF rules block injection and XSS payloads before they can be used for data exfiltration | Medium — same zero-day caveat as above |
| **Cloud Monitoring** | Repudiation | Admin Activity logs record every policy and configuration change automatically; cannot be disabled per-user | Low |
| **Artifact Registry** | Integrity | Trivy scans every image before push; Checkov scans the Terraform that provisions the registry itself | Low |

## Notes on scope

This model covers the components actually deployed in cloudock.
It does not cover: physical security of Google's infrastructure (out of
scope, GCP's shared responsibility), client-side browser security
(out of scope, user's own device), or the private subnet (currently
unused, reserved for future workloads — reassess when something is
actually deployed there).

**Medium-residual-risk items are the two worth tracking going forward**,
not the ones to treat as solved: open-source dependency supply-chain
risk (CI/CD) and WAF signature-bypass risk (Cloud Armor) are both
industry-wide, unsolved problems — mitigated here, not eliminated.

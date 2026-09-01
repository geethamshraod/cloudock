# SECURITY_HARDENING.md

Security Command Center findings reviewed for the cloudock project
(Standard tier, project-level activation, no cost).

| Finding name | Root cause | Fix applied | Date fixed | Residual risk |
|---|---|---|---|---|
| Public IP address (Misconfiguration, **High**) | `cloudock-webserver` had a directly-assigned external IP (`access_config` in `compute.tf`), in addition to being reachable through the load balancer — an unnecessary second path to the same instance that bypassed Cloud Armor entirely | Removed `access_config` from the VM's `network_interface`. Public access now goes exclusively through the load balancer (Cloud Armor WAF protected); SSH admin access continues via the existing IAP tunnel rule (`cloudock-allow-iap-ssh`), which never required a public IP; outbound internet access (package updates) is unaffected, since Cloud NAT already covers the whole VPC, not just the private subnet | 2026-08-24 | None identified — the load balancer remains the sole public entry point and was already the intended, WAF-protected access path; no functionality lost |

Scanned: 2026-08-23 to 2026-08-24 (Standard tier, Last 7 days). One
finding total, High severity, resolved same day. No Critical findings
present. 
<!--Re-check periodically as new resources are added — this table
should grow with each SCC pass, not be treated as a one-time exercise.-->

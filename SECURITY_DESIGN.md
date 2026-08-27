# SECURITY_DESIGN.md — cloudock Architectural Decisions

Every major security-relevant decision made across this project, the
reasoning behind it, and what was rejected instead. This is the "why,"
not the "what" — see `docs/06-terraform-infrastructure-as-code.md` and
`THREAT_MODEL.md` for implementation detail and threat coverage.

| # | Decision | Why chosen | Security benefit | Alternative considered | Why rejected |
|---|---|---|---|---|---|
| 1 | `min-instances=0` on Cloud Run | Cost — free at idle, no charge for capacity that isn't serving traffic | Reduced attack surface at idle — no running instance exists to attack when there's no traffic | `min-instances=1` (always running) | Cost with no offsetting security benefit for a dev/portfolio environment; an always-warm instance is strictly more exposed for zero added protection |
| 2 | Dedicated `cloud-run-sa` instead of the default compute service account | Least privilege | The default compute SA historically carries broad project-level access (Editor-equivalent in many default configurations) — a single compromise there means a full-project compromise | Default compute service account (do nothing, accept Cloud Run's default) | Too broad — one identity, one compromise, entire project affected; a dedicated SA with only the roles actually needed keeps the blast radius of any single compromise contained |
| 3 | Workload Identity Federation instead of a service account JSON key | Keyless authentication | No long-lived credential exists anywhere to leak, rotate, or forget about | Service account JSON key stored in a GitHub secret | Rejected — JSON keys can leak in logs, are easy to forget to rotate, and remain valid indefinitely once issued; WIF issues short-lived, automatically-expiring credentials per pipeline run instead |
| 4 | Secret Manager instead of environment variables | Zero credentials in code | Environment variables are visible in the Cloud Run console, in container logs, and in CI/CD run logs — none of which are meant to hold secrets | Hardcoded values in `app.py`, or plain environment variables | Rejected — credential leak risk in multiple places at once (console, logs, source control); Secret Manager centralizes access control and audit logging that env vars simply don't have |
| 5 | Cloud Armor on the Load Balancer, not on Cloud Run directly | WAF inspection happens before a request ever reaches application code | The load balancer evaluates every WAF rule and can reject malicious requests *before* Cloud Run spins up an instance to handle them | Cloud Run with `ingress=all` (direct public access, no WAF in front) | Rejected — no WAF protection at all; every request, malicious or not, would reach the application layer unfiltered |

## How to read this document

Each row is a genuine trade-off, not a default assumed to be correct.
Decision 1 in particular is a reminder that "more secure" and "more
available" aren't always the same axis — an idle attack surface of zero
is a real security property, not just a cost optimization that happened
to also help security.

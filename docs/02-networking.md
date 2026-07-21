Custom-mode VPC with public/private subnets, a default-deny firewall posture with explicit allow rules, and Cloud NAT for private-subnet egress — validated with a throwaway VM.
**Region:** `asia-southeast1`

## Network

```bash
gcloud compute networks create cloudock-vpc --subnet-mode=custom
```
**Why:** Custom mode instead of auto-mode. Auto-mode creates a subnet in *every* GCP region by default — unnecessary attack surface and clutter. Custom mode means every subnet that exists was deliberately created.

## Subnets

```bash
gcloud compute networks subnets create cloudock-public-subnet --network=cloudock-vpc --region=asia-southeast1 --range=10.0.1.0/24
gcloud compute networks subnets create cloudock-private-subnet --network=cloudock-vpc --region=asia-southeast1 --range=10.0.2.0/24
```
**Why:** Separating public- and private-facing resources into different subnets is the baseline segmentation pattern — a firewall rule or IAM policy targeting the private subnet can't accidentally apply to something meant to be internet-facing, and vice versa.

## Firewall rules

```bash
gcloud compute firewall-rules create cloudock-allow-ssh --network=cloudock-vpc --action=allow --rules=tcp:22 --source-ranges=<Own Public IP>/32 --target-tags=cloudock-ssh-access
gcloud compute firewall-rules create cloudock-allow-https --network=cloudock-vpc --action=allow --rules=tcp:443 --source-ranges=0.0.0.0/0
gcloud compute firewall-rules create cloudock-deny-all-ingress --network=cloudock-vpc --action=deny --rules=all --priority=65534 --direction=INGRESS
gcloud compute firewall-rules create cloudock-allow-iap-ssh --network=cloudock-vpc --action=allow --rules=tcp:22 --source-ranges=35.235.240.0/20 --target-tags=cloudock-ssh-access
```
**Why:**
- `cloudock-allow-ssh` is scoped to a single `/32` (current public IP) and requires the `cloudock-ssh-access` tag — SSH only works from one known location, and only to instances that explicitly opt in.
- `cloudock-allow-https` is deliberately open (`0.0.0.0/0`) for future public web traffic. Worth revisiting once something is actually listening on 443.
- `cloudock-deny-all-ingress` is the backstop. GCP firewalls have no implicit default-deny, so without this rule anything not explicitly blocked is reachable if a resource happens to expose a port. Priority 65534 (evaluated last) plus the allow rules above at the default priority
  1000 (evaluated first) gives "default deny, explicit allow."
- `cloudock-allow-iap-ssh` allows ingress from `35.235.240.0/20` — Google's
  fixed Identity-Aware Proxy range — on tcp:22, so `gcloud compute ssh` can
  tunnel in to a VM with no public IP.

## Cloud NAT

```bash
gcloud compute routers create cloudock-nat-router --network=cloudock-vpc --region=asia-southeast1
gcloud compute routers nats create cloudock-nat-gateway --router=cloudock-nat-router --region=asia-southeast1 --auto-allocate-nat-external-ips --nat-all-subnet-ip-ranges
```
**Why:** Cloud Router is a required control-plane object Cloud NAT attaches
to. The NAT gateway is what lets private-subnet instances (no external IP)
reach the internet for outbound needs — `apt-get update`, pulling images —
without ever being directly reachable *from* the internet.

## Validation

```bash
gcloud compute instances create test-vm --machine-type=e2-micro --subnet=cloudock-private-subnet --zone=asia-southeast1-b --no-address --tags=cloudock-ssh-access
gcloud compute ssh cloudock-test-vm --zone=asia-southeast1-b --tunnel-through-iap
sudo apt-get update
exit
gcloud compute instances delete cloudock-test-vm --zone=asia-southeast1-b --quiet
```
**Why:** `--no-address` gives this VM no public IP — the posture
private-subnet workloads should have. `--tags=cloudock-ssh-access` is new
this round — the original `test-vm` was never actually tagged, so neither
`allow-ssh` nor `allow-iap-ssh` (both scoped to `--target-tags`) would ever
have matched it regardless of source IP. Without this tag, SSH would fail
no matter how correct the firewall rules look on paper — worth catching
now, before it looks like a networking bug when it's actually a missing
tag. `--tunnel-through-iap` is passed explicitly rather than relying on
`gcloud`'s auto-fallback. A successful `apt-get update` from inside the VM
is the real proof Cloud NAT is working. The VM is deleted immediately
after — a disposable test fixture.

## Verification

```bash
gcloud compute networks describe cloudock-vpc
gcloud compute firewall-rules list --filter="network=cloudock-vpc"
gcloud compute routers nats list --router=cloudock-nat-router --region=asia-southeast1
```
**Why:** Checks the actual state in GCP against intent, rather than
trusting the setup commands succeeded just because the CLI returned no
error.

**Results:**
- `cloudock-vpc` confirmed, custom mode
- Exactly 4 firewall rules present: `cloudock-allow-ssh`, `cloudock-allow-https`, `cloudock-deny-all-ingress`, `cloudock-allow-iap-ssh`
- `cloudock-nat-gateway` shows in the NAT list for `cloudock-nat-router`
- `test-vm` actually reachable via SSH (confirms the `--tags` fix worked)

## Infrastructure reference

| Resource | Name | Details |
|---|---|---|
| VPC | `cloudock-vpc` | custom subnet mode |
| Subnet (public) | `cloudock-public-subnet` | `10.0.1.0/24`, `asia-southeast1` |
| Subnet (private) | `cloudock-private-subnet` | `10.0.2.0/24`, `asia-southeast1` |
| Firewall | `cloudock-allow-ssh` | tcp:22, source `<device-public-ip>/32`, tag `cloudock-ssh-access` |
| Firewall | `cloudock-allow-https` | tcp:443, source `0.0.0.0/0` |
| Firewall | `cloudock-deny-all-ingress` | all protocols, priority 65534, ingress |
| Firewall | `cloudock-allow-iap-ssh` | tcp:22, source `35.235.240.0/20`, tag `cloudock-ssh-access` |
| Router | `cloudock-nat-router` | `asia-southeast1` |
| NAT | `cloudock-nat-gateway` | auto-allocated IPs, all subnet ranges |

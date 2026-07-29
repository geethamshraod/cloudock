# M2 — VM + Storage + Load Balancer

**Goal:** Public-facing nginx VM behind an HTTP Load Balancer with Cloud
Armor attached, plus a versioned/lifecycle-managed Cloud Storage bucket
accessed via a least-privilege service account.
**Region/zone:** `asia-southeast1` / `asia-southeast1-b`, matching M1.

## 1. Web server VM

```bash
gcloud compute instances create cloudock-webserver \
  --machine-type=e2-micro \
  --subnet=cloudock-public-subnet \
  --zone=asia-southeast1-b \
  --tags=cloudock-web-server \
  --image-family=debian-11 \
  --image-project=debian-cloud \
  --metadata=ssh-keys="geethamshraodharbasth:$(cat ~/.ssh/id_ed25519.pub)"
```
**Why:** `--metadata=ssh-keys=...` injects your public key directly —
password auth is never enabled, so there's no password to brute-force in
the first place. `--tags=cloudock-web-server` attaches a network tag to 
the VM at creation time. This tag acts as an identifier for firewall rules. 
Any firewall rule configured with the target tag cloudock-web-server will 
apply to this VM. Adding the tag during creation ensures the VM immediately 
matches the required firewall rules instead of creating the instance first 
and later troubleshooting why network access is not working. `--subnet=cloudock-public-subnet` 
is because public subnet puts the VM closer to the internet whereas private subnet hides 
the VM and requires another way (Bastion Host) to access it.

```
WINDOWS COMPUTER
----------------
id_ed25519
(private key)

id_ed25519.pub
(public key)
    |
    |
    | VM creation command
    |
    v
GOOGLE CLOUD
------------
Creates VM

cloudock-webserver
    |
    |
    | installs public key
    |
    v
VM STORAGE
----------

/home/user/.ssh/authorized_keys

contains:
id_ed25519.pub
    |
    |
    | gcloud compute ssh
    |
    v
SSH LOGIN
----------

Windows proves:
"I have the private key"

VM checks:
"Does it match my public key?"
    |
    v
ACCESS GRANTED
    |
    v
Linux terminal opens
```

```bash
gcloud compute ssh cloudock-webserver --zone=asia-southeast1-b
```
```bash
# inside the VM
sudo apt-get update && sudo apt-get install -y nginx && sudo systemctl enable nginx && sudo systemctl start nginx
exit
```
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
`cloudock-allow-lb-health-check` allows Google Cloud Load Balancer health 
check probes to access the backend VM on TCP port 80. The health checks 
originate only from Google's fixed IP ranges (130.211.0.0/22 and 35.191.0.0/16),
so restricting the source ranges ensures that only trusted Google systems can 
perform these checks instead of allowing general internet access  — without this 
rule the backend never passes its health check, regardless of whether the site 
works fine from a browser.

**Verify (browser):** open `http://<webserver-external-ip>` — default
nginx page should load or obtain the IP with:
```bash
gcloud compute instances describe cloudock-webserver --zone=asia-southeast1-b --format="get(networkInterfaces[0].accessConfigs[0].natIP)"
```

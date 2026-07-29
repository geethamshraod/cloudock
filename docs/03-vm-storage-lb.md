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


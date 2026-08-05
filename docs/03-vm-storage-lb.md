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
## 3. Cloud Storage bucket

```bash
gsutil mb -b on -l asia-southeast1 gs://cloudock-503009-security-assets
gsutil versioning set on gs://cloudock-503009-security-assets
```
```bash
#creating lifecycle.json
nano lifecycle.json
{"rule":[{"action":{"type":"Delete"},"condition":{"age":90}}]}
```
##### Alternate creation of 90 day lifecycle policy
```
Open the Google Cloud Console.
Navigate to Cloud Storage → Buckets.
Select your bucket.
Open the Lifecycle tab (or Lifecycle rules, depending on the interface).
Click Add Rule.
Choose:
  Action: Delete object
  Condition: Age
  Age: 90 days
Save the rule.
```
```bash
gsutil lifecycle set lifecycle.json gs://cloudock-503009-security-assets
```
**Why:** The Cloud Storage bucket is created with Uniform Bucket-Level Access
`-b on` so that access is managed exclusively through IAM, eliminating legacy 
object-level ACLs and providing a simpler, more secure, and easier-to-audit 
permission model. Specifying the `asia-southeast1` region ensures that the bucket 
is located in the same region as the project's other resources, which helps 
reduce latency and supports data residency requirements. Versioning protects
against accidental overwrite/delete — old versions stay recoverable. The
90-day lifecycle rule auto-deletes objects past that age, which controls
storage cost but is worth a second look if this bucket is ever meant to
hold anything with a longer retention requirement (audit evidence, etc.)
— 90 days is a cost decision here, not a compliance one.
The `gsutil lifecycle set` operation reads the JSON configuration, validates its contents, and updates the bucket's lifecycle settings.

## 4. Least-privilege service account

```bash
gcloud iam service-accounts create cloudock-storage-writer --display-name="Storage Writer SA"

gcloud projects add-iam-policy-binding cloudock-503009 --member=serviceAccount:cloudock-storage-writer@cloudock-503009.iam.gserviceaccount.com --role=roles/storage.objectCreator
```
**Why:** The `gcloud projects add-iam-policy-binding` command updates 
the project's IAM policy by adding a new role binding. 
`--member=serviceAccount:cloudock-storage-writer@cloudock-503009.iam.gserviceaccount.com`
identifies the service account receiving the permission, and 
`--role=roles/storage.objectCreator` assigns the Storage Object Creator role.
`roles/storage.objectCreator` allows writing *new* objects only —
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
**Why:** We are utilizing an unmanaged instance group deliberately as a simplified, static binding mechanism to attach a single, manually provisioned VM to the global backend service. While sufficient for a one-instance test setup, this approach explicitly sacrifices standard cloud resilience. By relying on an unmanaged group rather than the production standard—a Managed Instance Group (MIG) paired with a securely configured instance template—we establish a critical single point of failure. The configured HTTP health check (listening on `--port=80`, matching our established firewall rules) will successfully detect a service outage and sever the routing path, but the environment fundamentally lacks the automation required to terminate a degraded instance and deploy a healthy replacement. Ultimately, this architecture demonstrates the raw routing mechanics but remains entirely unsuited for production workloads where autoscaling and auto-healing are mandatory.

## 6. Cloud Armor

```bash
gcloud compute security-policies create cloudock-armor-policy --description="Cloud Armor policy"
gcloud compute backend-services update cloudock-web-backend --security-policy=cloudock-armor-policy --global
```
**Why:** Attaching this policy establishes the foundational enforcement point directly within the global routing path of the backend service. However, this initial deployment functions strictly as architectural scaffolding. By default, a newly created policy executes an "allow all" rule, meaning it currently provides zero active protection. Until it is explicitly configured with essential Web Application Firewall (WAF) controls—such as rate limiting, geo-fencing, and OWASP Top 10 rule sets—the application perimeter remains entirely exposed to malicious traffic. This step wires the plumbing to intercept requests, but the environment remains fundamentally unsecured until the actual defensive rules are defined and applied.

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

## Resource View
<img width="2928" height="316" alt="cloudock_lb" src="https://github.com/user-attachments/assets/5594b9e2-09eb-48b6-9d8f-c5f1b8ef1607" />
<img width="1734" height="185" alt="image" src="https://github.com/user-attachments/assets/cf06ab79-a499-436b-810e-5a96135d38e3" />


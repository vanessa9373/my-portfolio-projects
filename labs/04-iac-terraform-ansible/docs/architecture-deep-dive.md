# Lab 04: Infrastructure as Code — Terraform + Ansible — Architecture Deep Dive

> **Architect:** Vanessa Awo  
> **Framework:** AWS Well-Architected Framework (6 Pillars)  
> **Scope:** Full IaC lifecycle — cloud provisioning (Terraform) + server configuration (Ansible) + zero-downtime deployment

---

## What This Framework Solves

Manual infrastructure has two failure modes: "it works on my machine" (configuration drift between environments) and "nobody knows why that works" (undocumented configuration decisions made by the original engineer). The Terraform + Ansible split addresses both — Terraform declares what infrastructure exists, Ansible declares how each server is configured, and both are version-controlled. Any environment can be reproduced identically from these files alone.

---

## The Tool Division of Responsibility

The key design principle is **the right tool for each layer**:

| Layer | Tool | Why |
|-------|------|-----|
| Cloud resources (what exists) | Terraform | Declarative, state tracking, plan before apply, multi-cloud |
| Server configuration (how it's set up) | Ansible | Agentless SSH, idempotent playbooks, large role library |
| Application deployment (what's running) | Ansible | Rolling strategy, health checks, environment-aware vars |

**Why not Terraform for server configuration?**  
Terraform's `remote-exec` and `file` provisioners can run scripts on servers, but they run only once (at resource creation) and don't provide idempotency. Running `terraform apply` a second time won't re-apply a configuration change. Ansible playbooks are idempotent — running them 100 times produces the same result as running them once. For configuration management (ongoing state, not one-time provisioning), Ansible is the correct tool.

**Why not Ansible for cloud resources?**  
Ansible AWS modules exist but lack state tracking. If you delete an EC2 instance created by Ansible and run the playbook again, Ansible creates a new one — it doesn't know the old one existed. Terraform maintains state: it knows what it created, what the current state is, and what changes are needed to reach the desired state. This is critical for infrastructure management.

---

## Step-by-Step: Terraform Provisioning

### Step 1 — Environment Separation with Terraform Workspaces

Each environment (dev, staging, prod) has its own Terraform state:

```
terraform/
├── modules/                  # Shared modules
│   ├── vpc/
│   ├── compute/
│   ├── eks/
│   └── database/
└── environments/
    ├── dev/
    │   ├── main.tf           # Calls shared modules with dev vars
    │   ├── backend.tf        # S3 state: bucket/dev/terraform.tfstate
    │   └── terraform.tfvars  # dev-specific values
    ├── staging/
    │   └── ...               # Same modules, staging vars
    └── prod/
        └── ...               # Same modules, prod vars
```

**Why per-environment state files (not workspaces)?**  
Terraform workspaces share the same backend configuration and simply prefix the state file name. A `terraform workspace select prod` mistake when you meant to run in dev is a low-friction path to production changes. Separate directories with separate backend configurations make the blast radius explicit: you must `cd terraform/environments/prod` to affect production — the working directory is the guardrail.

**Dev vs Production configuration difference example:**

```hcl
# dev/terraform.tfvars
instance_type      = "t3.micro"
desired_count      = 1
multi_az           = false
deletion_protection = false  # allow easy teardown

# prod/terraform.tfvars
instance_type      = "m5.large"
desired_count      = 4
multi_az           = true
deletion_protection = true
```

The same modules run in all environments with different parameters. This guarantees that the production infrastructure is a superset of what was tested in staging — not a manually configured variant that diverges over time.

### Step 2 — Terraform Output → Ansible Inventory Bridge

The critical integration between Terraform and Ansible is the inventory generation script:

```bash
# scripts/generate-inventory.sh

# Export Terraform outputs as JSON
cd terraform/environments/$ENV
terraform output -json > /tmp/tf_outputs.json

# Parse EC2 IPs and generate Ansible inventory format
python3 << EOF
import json

with open('/tmp/tf_outputs.json') as f:
    outputs = json.load(f)

# Extract IPs from Terraform output
web_ips = outputs['web_server_ips']['value']
db_ips = outputs['db_server_ips']['value']

# Write Ansible inventory
with open('ansible/inventory/hosts', 'w') as f:
    f.write('[webservers]\n')
    for ip in web_ips:
        f.write(f'{ip} ansible_user=ec2-user ansible_ssh_private_key_file=~/.ssh/deploy.pem\n')
    
    f.write('\n[databases]\n')
    for ip in db_ips:
        f.write(f'{ip} ansible_user=ec2-user ansible_ssh_private_key_file=~/.ssh/deploy.pem\n')
EOF
```

**Why generate inventory from Terraform outputs instead of static files?**  
Static inventory files go stale immediately. An Auto Scaling event replaces an EC2 instance with a new IP — the inventory file now points to a terminated instance, and Ansible cannot reach it. Generating inventory from Terraform outputs ensures the inventory always reflects current infrastructure state. This is the same principle as "infrastructure as code" applied to configuration management.

### Step 3 — EC2 Instance Provisioning

```hcl
# modules/compute/main.tf
resource "aws_instance" "web" {
  count         = var.desired_count
  ami           = data.aws_ami.amazon_linux.id
  instance_type = var.instance_type
  subnet_id     = var.private_subnet_ids[count.index % length(var.private_subnet_ids)]
  
  # IMDSv2 only — SSRF protection
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"  # IMDSv2
    http_put_response_hop_limit = 1
  }
  
  # Encrypted root volume
  root_block_device {
    encrypted   = true
    kms_key_id  = var.kms_key_arn
    volume_type = "gp3"
    volume_size = 20
  }
  
  tags = merge(var.tags, {
    Name        = "${var.project_name}-web-${count.index}"
    Environment = var.environment
  })
}
```

**Why `http_put_response_hop_limit = 1`?**  
The IMDS hop limit controls how many network hops the metadata token response can traverse. Setting it to 1 means the token response can only reach the originating container/process. A hop limit > 1 allows SSRF attacks where a compromised application on the instance makes a request to `169.254.169.254`, which gets forwarded to another service — allowing credential theft across container boundaries.

---

## Step-by-Step: Ansible Configuration

### Step 4 — Security Hardening Playbook

```yaml
# playbooks/security-hardening.yml
---
- name: Security hardening
  hosts: all
  become: true
  tasks:
    - name: Disable root SSH login
      lineinfile:
        path: /etc/ssh/sshd_config
        regexp: '^PermitRootLogin'
        line: 'PermitRootLogin no'
      notify: restart sshd

    - name: Disable password authentication
      lineinfile:
        path: /etc/ssh/sshd_config
        regexp: '^PasswordAuthentication'
        line: 'PasswordAuthentication no'
      notify: restart sshd

    - name: Configure firewall (allow only required ports)
      firewalld:
        port: "{{ item }}"
        permanent: true
        state: enabled
      loop:
        - "22/tcp"    # SSH (restrict to bastion CIDR via security group)
        - "80/tcp"    # HTTP
        - "443/tcp"   # HTTPS
        - "9100/tcp"  # Prometheus node exporter

    - name: Install and enable fail2ban
      package:
        name: fail2ban
        state: present
      notify: start fail2ban

    - name: Enable automatic security updates
      package:
        name: dnf-automatic
        state: present
    
    - name: Configure auto-updates to security only
      lineinfile:
        path: /etc/dnf/automatic.conf
        regexp: '^upgrade_type'
        line: 'upgrade_type = security'
```

**Why Ansible for hardening instead of an AMI (baked image)?**  
Custom AMIs require a pipeline to build, test, and publish. When a new security patch is released, a new AMI must be built and all instances replaced. Ansible playbooks can be re-run against running instances (`ansible-playbook --limit prod playbooks/security-hardening.yml`) to apply patches without instance replacement. Both approaches have merit; Ansible is more flexible for organizations without a mature AMI pipeline.

**Why `PasswordAuthentication no`?**  
Password-based SSH is brute-forceable. SSH key-based authentication requires the attacker to possess the private key — which is a qualitatively harder problem. Disabling passwords eliminates the brute-force attack surface entirely.

### Step 5 — Docker Installation Role

```yaml
# roles/docker/tasks/main.yml
---
- name: Add Docker repository
  yum_repository:
    name: docker-ce
    description: Docker CE Stable
    baseurl: "https://download.docker.com/linux/centos/$releasever/$basearch/stable"
    gpgcheck: yes
    gpgkey: "https://download.docker.com/linux/centos/gpg"

- name: Install Docker CE
  package:
    name:
      - docker-ce
      - docker-ce-cli
      - containerd.io
    state: present

- name: Start and enable Docker service
  service:
    name: docker
    state: started
    enabled: yes

- name: Add deploy user to docker group
  user:
    name: "{{ deploy_user }}"
    groups: docker
    append: yes

- name: Configure Docker daemon
  copy:
    content: |
      {
        "log-driver": "json-file",
        "log-opts": {
          "max-size": "10m",
          "max-file": "3"
        },
        "storage-driver": "overlay2",
        "live-restore": true
      }
    dest: /etc/docker/daemon.json
  notify: restart docker
```

**Why `live-restore: true` in Docker daemon config?**  
`live-restore` allows Docker containers to continue running when the Docker daemon restarts (for daemon upgrades or crashes). Without it, a Docker daemon restart would stop all running containers — a daemon update becomes a service outage.

**Why log rotation (`max-size: 10m, max-file: 3`)?**  
Without log rotation, Docker container logs accumulate indefinitely on the host disk. A verbose service logging 1MB/second fills a 20GB disk in 5.5 hours, causing the host to fail. The `10m × 3 files = 30MB maximum` per container prevents this.

### Step 6 — Zero-Downtime Rolling Deployment

```yaml
# playbooks/deploy-app.yml
---
- name: Rolling application deployment
  hosts: webservers
  serial: 1           # ← one server at a time
  max_fail_percentage: 0  # ← stop if any server fails
  
  tasks:
    - name: Remove from load balancer
      community.aws.elb_instance:
        instance_id: "{{ ansible_ec2_instance_id }}"
        ec2_elbs: "{{ load_balancer_name }}"
        state: absent
        wait: true
        wait_timeout: 60

    - name: Pull new Docker image
      community.docker.docker_image:
        name: "{{ ecr_registry }}/{{ app_name }}:{{ version }}"
        source: pull

    - name: Stop current container
      community.docker.docker_container:
        name: "{{ app_name }}"
        state: stopped

    - name: Start new container version
      community.docker.docker_container:
        name: "{{ app_name }}"
        image: "{{ ecr_registry }}/{{ app_name }}:{{ version }}"
        state: started
        restart_policy: unless-stopped
        ports:
          - "80:3000"

    - name: Wait for health check to pass
      uri:
        url: "http://localhost/health"
        return_content: yes
        status_code: 200
      register: health_check
      until: health_check.status == 200
      retries: 10
      delay: 5

    - name: Re-add to load balancer
      community.aws.elb_instance:
        instance_id: "{{ ansible_ec2_instance_id }}"
        ec2_elbs: "{{ load_balancer_name }}"
        state: present
        wait: true
```

**Why `serial: 1` instead of updating all servers simultaneously?**  
All-at-once deployment: all servers stop serving traffic simultaneously for the duration of the deployment. If the new version has a bug, all users are affected. With `serial: 1`, one server at a time is updated. If the health check fails on server 1, `max_fail_percentage: 0` stops the deployment — servers 2 and 3 continue running the old version. Users experience degraded capacity (1/3 servers offline during update) but no outage.

**Why wait for health check before re-adding to ALB?**  
Adding a server to the load balancer before the application is ready routes real user traffic to a starting application. The `until/retries/delay` block waits up to 50 seconds (10 retries × 5 seconds) for the health endpoint to return 200 before adding the server back. Only healthy servers serve traffic.

---

## AWS Well-Architected Framework Analysis

### Operational Excellence
- **Idempotent playbooks:** Run Ansible 100 times, get the same result — no drift accumulation
- **Environment promotion:** dev → staging → prod uses identical code with different variable files — no "works in staging, broken in prod" surprises
- **Automated inventory:** Inventory always reflects current EC2 state — no stale IP addresses

### Security
- **IMDSv2 enforced via Terraform:** All EC2 instances reject IMDSv1 — SSRF attacks cannot steal credentials
- **SSH hardened via Ansible:** Root login disabled, password auth disabled, fail2ban running — brute-force attack surface eliminated
- **Encrypted EBS:** Root volume encrypted at rest with KMS CMK — instance data protected at the storage layer

### Reliability
- **Rolling deployments with health checks:** Zero-downtime updates, automatic rollback if health check fails
- **Multi-AZ compute:** Instances spread across private subnets in multiple AZs
- **Firewall rules:** Only required ports open — reduce attack surface and prevent accidental exposure

### Performance Efficiency
- **Right-sized by environment:** `t3.micro` in dev, `m5.large` in prod — no over-provisioning in lower environments
- **gp3 EBS volumes:** 3,000 IOPS baseline at any volume size — no need to over-provision volume size for IOPS

### Cost Optimization
- **Development teardown:** `deletion_protection = false` in dev means environments can be torn down and re-created quickly — no idle resources
- **Per-environment sizing:** Dev doesn't pay for production instance types

### Sustainability
- **Auto security updates:** Automatic patching keeps instances current without manual maintenance cycles that require running old, inefficient software

---

## Key Architectural Insight

The Terraform + Ansible split is an application of the **separation of concerns** principle at the infrastructure layer. Terraform's value is in knowing the current state of infrastructure resources and computing a diff to reach the desired state — it's a convergence tool for cloud APIs. Ansible's value is in expressing "this server should look like this" and making it so, idempotently, regardless of current state. Forcing Terraform to do configuration management (via `remote-exec`) or Ansible to do resource lifecycle management produces inferior results from both tools. The integration point (Terraform outputs → Ansible inventory) is the seam where these responsibilities meet.

---

*Built by Vanessa Awo | [LinkedIn](https://linkedin.com/in/vanessajen) | [Portfolio](https://jenellavan.com)*

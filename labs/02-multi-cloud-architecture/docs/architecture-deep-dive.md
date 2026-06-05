# Lab 02: Multi-Cloud Hybrid Architecture — Architecture Deep Dive

> **Architect:** Vanessa Awo  
> **Framework:** AWS Well-Architected Framework + Azure Architecture Framework  
> **Scope:** Active-active cross-cloud architecture — AWS us-west-2 + Azure West US

---

## What This Architecture Solves

A single cloud provider dependency means a provider-wide outage takes down your entire platform. For financial services, provider outages translate directly to regulatory penalties, lost transactions, and customer attrition. The multi-cloud architecture doesn't just provide redundancy — it demonstrates SOC 2 business continuity controls and changes the risk model from "single-cloud SLA" to "both clouds fail simultaneously."

The probability of AWS and Azure experiencing simultaneous outages in the same geography is orders of magnitude lower than either individual provider failing.

---

## Step-by-Step: Architecture Walkthrough

### Step 1 — CIDR Planning (The Foundation Everything Else Depends On)

Before any resource is created, IP address ranges must be allocated with zero overlap between clouds.

```
AWS VPC:        10.0.0.0/16
  ├── Public:   10.0.1.0/24, 10.0.2.0/24
  └── Private:  10.0.10.0/24, 10.0.20.0/24

Azure VNet:     10.1.0.0/16
  ├── Public:   10.1.1.0/24, 10.1.2.0/24
  └── Private:  10.1.10.0/24, 10.1.20.0/24

On-premises:    192.168.0.0/16 (if applicable)
```

**Why this CIDR allocation is critical:**  
VPN routing works at the IP layer. If AWS uses `10.0.0.0/16` and Azure uses `10.0.0.0/16`, the VPN cannot determine which cloud a packet destined for `10.0.1.5` should route to — both match. The entire VPN connection fails silently. CIDR overlap is the #1 cause of failed multi-cloud VPN implementations.

The `/16` allocations give each cloud 65,534 IP addresses — sufficient for any foreseeable growth without requiring CIDR expansion (which would require re-IPing the entire cloud, a multi-week project).

### Step 2 — AWS Network (VPC + Transit Gateway)

Terraform creates the AWS VPC with Transit Gateway as the VPN termination point.

**Why Transit Gateway instead of Virtual Private Gateway?**  
A Virtual Private Gateway (VGW) attaches to a single VPC. As the architecture grows (adding a second workload VPC, a shared services VPC, a development VPC), each VPC needs its own VPN connection to Azure — and the number of connections grows as O(n). Transit Gateway is a regional router that all VPCs attach to. A single VPN connection from TGW reaches all attached VPCs. Adding a new VPC means one TGW attachment, not a new VPN tunnel.

**Transit Gateway VPN configuration:**
```
AWS Transit Gateway
└── VPN Attachment
    ├── Tunnel 1: BGP ASN 65001, pre-shared key
    └── Tunnel 2: BGP ASN 65001, pre-shared key (redundant)
```

**Why 2 VPN tunnels?**  
AWS always provisions VPN connections with 2 tunnels for redundancy. If the underlying hardware supporting Tunnel 1 fails, Tunnel 2 continues routing — no reconnection required. BGP (Border Gateway Protocol) routes automatically fail over between tunnels.

### Step 3 — Azure Network (VNet + VPN Gateway)

Terraform creates the Azure Virtual Network and VPN Gateway.

**Why Azure VPN Gateway takes 30–45 minutes to provision:**  
Azure VPN Gateway is a managed service that deploys redundant gateway VMs in the background. This is not a resource that can be pre-warmed — Azure physically provisions two active-active gateway instances for high availability. Plan this into the deployment timeline; Terraform will wait at the `azurerm_virtual_network_gateway` resource.

**VPN Gateway SKU decision:** `VpnGw2` (not `Basic`)
- `Basic`: no BGP support, no Zone Redundancy, limited bandwidth
- `VpnGw2`: BGP support, 1.25 Gbps throughput, Zone Redundant option

BGP support is required for dynamic routing — static routing would require manual route table updates whenever a new subnet is added to either cloud.

### Step 4 — IPsec VPN Connection

After both gateways are provisioned, Terraform establishes the VPN connection.

**IPsec/IKEv2 configuration:**
```
Phase 1 (IKE):  AES-256, SHA-256, DH Group 14 (2048-bit)
Phase 2 (IPsec): AES-256, SHA-256, PFS Group 14
Lifetime:        28800s (Phase 1), 3600s (Phase 2)
```

**Why IKEv2 over IKEv1?**  
IKEv2 is more efficient (fewer round trips for session establishment), supports MOBIKE (connection mobility — important for failover), has built-in dead peer detection, and handles asymmetric NAT better. AWS and Azure both prefer IKEv2. Only use IKEv1 when the remote end doesn't support v2.

**Verifying the connection:**
```bash
# AWS: Check tunnel status
aws ec2 describe-vpn-connections \
  --query 'VpnConnections[].VgwTelemetry[].Status'
# Expected: "UP" for both tunnels

# Azure: Check connection status
az network vpn-connection show \
  --name aws-vpn-connection -g multi-cloud-rg \
  --query connectionStatus
# Expected: "Connected"
```

### Step 5 — BGP Route Exchange

With the tunnel established, BGP sessions form and routes are exchanged dynamically.

```
AWS advertises:  10.0.0.0/16 to Azure
Azure advertises: 10.1.0.0/16 to AWS
```

**Why BGP instead of static routes?**  
Static routes require manual updates every time a subnet is added. With BGP, each cloud's router dynamically advertises its subnets. Adding a new subnet in AWS (e.g., `10.0.30.0/24` for a new application tier) automatically becomes reachable from Azure without any manual route table changes.

**BGP ASN assignment:**
- AWS TGW: ASN 64512 (private ASN range)
- Azure VPN GW: ASN 65515 (Azure default for VPN GW)
- These must be different — BGP loops prevention requires unique ASNs

### Step 6 — Route 53 Failover Routing

Route 53 manages the DNS entry for the application with health check-based failover.

```
app.example.com
├── PRIMARY record: AWS ALB DNS name (us-west-2)
│   └── Health check: HTTP GET /health every 30s, threshold: 3 failures
└── SECONDARY record: Azure App Gateway DNS name (West US)
    └── Failover: only active when PRIMARY health check fails
```

**DNS failover timing:**
1. Primary health check endpoint becomes unreachable
2. After 3 consecutive failures (30s × 3 = 90 seconds), Route 53 marks the endpoint unhealthy
3. Route 53 removes the primary record and serves the secondary record
4. TTL is 60 seconds — all resolvers worldwide switch to the Azure endpoint within 60 seconds
5. **Total failover time: < 2.5 minutes** from outage to DNS propagation

**Why TTL 60 seconds instead of lower?**  
TTL 1 second would mean every DNS query hits Route 53 (thousands of queries/minute = cost). TTL 60 seconds means DNS is cached for 60 seconds — during failover there's up to a 60-second window where some clients still have the old record. For an RTO of 15 minutes, 60-second TTL is correct. For an RTO of 30 seconds, you'd need TTL 10 seconds and accept the query cost.

### Step 7 — Active-Active EKS and AKS

Both clouds run independent copies of the full application stack.

**AWS side:**
- EKS cluster in private subnets
- ALB Ingress Controller for ingress
- RDS Aurora PostgreSQL Multi-AZ for data

**Azure side:**
- AKS cluster in private subnets
- Azure Application Gateway for ingress
- Azure SQL Database (geo-replicated) for data

**Data synchronization strategy:**  
This is the hardest part of multi-cloud. Options:
1. **Active-passive (chosen):** All writes go to AWS Aurora. Azure SQL receives async replication. RPO < 1 minute (replication lag). On failover, Azure becomes the write endpoint — potential conflict resolution needed for the replication lag window.
2. **Active-active with conflict resolution:** Both clouds accept writes. A CRD (Conflict-free Replicated Data type) or application-level merge strategy resolves conflicts. Much higher complexity.
3. **Stateless application, single database:** The application on both clouds reads/writes the same database (in the primary cloud). Eliminates data sync complexity but the database becomes a single point of failure.

The chosen approach (active-passive replication with failover capability) satisfies the < 1 minute RPO requirement while avoiding the complexity of bi-directional conflict resolution.

### Step 8 — Failover Test

```bash
# Simulate AWS outage: scale down the ECS service
aws ecs update-service \
  --cluster main \
  --service app \
  --desired-count 0

# Wait for health checks to fail (90s)
sleep 90

# Verify DNS switched to Azure
dig +short app.example.com
# Should return Azure App Gateway IP

# Restore AWS
aws ecs update-service \
  --cluster main \
  --service app \
  --desired-count 2
```

---

## AWS Well-Architected Framework Analysis

### Operational Excellence
- **Terraform for both clouds:** Single `terraform apply` provisions both AWS and Azure. Consistent variable naming (`project_name`, `cidr_block`) reduces cognitive load when switching providers
- **BGP dynamic routing:** No manual route table updates when subnets change
- **Documented CIDR plan:** Non-overlapping ranges documented in `docs/architecture-design.md` — critical for future subnet additions

### Security
- **IPsec/IKEv2 encryption:** All cross-cloud traffic encrypted — no data in transit in plaintext
- **Private subnets for compute:** EKS/AKS worker nodes have no internet-accessible IPs
- **Network Security Groups (Azure NSG):** Equivalent to AWS security groups, applied to subnets
- **Separate management accounts:** AWS and Azure managed via dedicated service accounts — no personal credentials in Terraform state

### Reliability
- **99.99% availability:** Two independent clouds — simultaneous failure probability is multiplicative (not additive)
- **RTO < 15 minutes:** DNS failover < 2.5 minutes + application warmup < 12.5 minutes
- **RPO < 1 minute:** Aurora async replication lag to Azure SQL < 60 seconds under normal conditions
- **Monthly DR drill:** Failover test scheduled monthly to verify RTO/RPO aren't drifting

### Performance Efficiency
- **VPN bandwidth:** VpnGw2 provides 1.25 Gbps — sufficient for cross-cloud synchronization traffic
- **Latency:** Within the same region pair (AWS us-west-2 ↔ Azure West US), latency is typically 15–25ms — acceptable for async replication
- **Route 53 latency-based routing:** Primary users routed to the closest cloud (AWS for West US users) rather than always hitting the primary cloud

### Cost Optimization
- **Active-passive (not active-active):** Running full workloads in two clouds simultaneously doubles compute costs. Active-passive means the secondary cloud (Azure) runs at reduced capacity (DR-only sizing) until failover, reducing cost
- **VPN costs:** AWS TGW attachment ~$36/month + data transfer ~$0.02/GB. Azure VPN Gateway ~$140/month. Total cross-cloud connectivity: ~$200/month
- **Unified cost tracking:** AWS and Azure costs tracked in separate billing accounts; CloudHealth or Azure Cost Management provides cross-cloud view

### Sustainability
- **Reduced over-provisioning:** Active-passive means the standby runs minimal capacity — less idle compute
- **BGP efficiency:** Dynamic routing eliminates redundant VPN tunnels that would otherwise be maintained for static routing

---

## Key Architectural Insight

The central challenge of multi-cloud is that each provider has different abstractions for equivalent concepts: AWS VPC ↔ Azure VNet, AWS EKS ↔ Azure AKS, AWS RDS ↔ Azure SQL Database. Terraform's provider model handles this — both clouds use the same HCL syntax and lifecycle model, but target different provider APIs. The discipline of using consistent module interfaces (`project_name`, `environment`, `cidr_block`) across providers is what makes multi-cloud Terraform maintainable. Without it, each cloud becomes its own silo.

---

*Built by Vanessa Awo | [LinkedIn](https://linkedin.com/in/vanessajen) | [Portfolio](https://jenellavan.com)*

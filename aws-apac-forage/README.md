# AWS APAC Solutions Architecture — Virtual Experience Program

> **Architect:** Vanessa Awo · AWS Solutions Architect Associate  
> **Program:** AWS Solutions Architecture Job Simulation · Forage  
> **Issued by:** Amazon Web Services (AWS) · Forage  
> **Status:** Certified Completion ✅ | September 2025  

---

## Overview

A structured SE/SA simulation run by AWS through Forage. The engagement mirrors a real pre-sales scenario: receive a client brief with a technical problem, assess their current architecture, design a scalable AWS solution, and present it clearly to a non-technical stakeholder audience.

**What this proves:** The ability to run the full SA/SE motion — discovery → diagnosis → architecture → communication — not just write Terraform.

---

## The Scenario

**Client:** APAC growth-stage company  
**Situation:** Website experiencing slow response times and occasional outages under peak load. Engineering team on a single EC2 instance with no load balancing, no database failover, and no CDN.  
**Traffic:** ~500 concurrent users at baseline, spikes to 2,000+ during marketing campaigns  
**Constraint:** Small ops team — solution must minimize operational overhead

---

## Discovery & Assessment

Before designing anything, I mapped the current-state architecture and identified failure modes:

| Current Setup | Problem |
|---------------|---------|
| Single EC2 instance | Zero redundancy — one crash = full outage |
| No load balancer | No traffic distribution, no health checks |
| No Auto Scaling | Manual capacity planning — always over- or under-provisioned |
| No CDN | Static assets served from origin every request — unnecessary latency |
| No read replicas | All DB traffic on one instance — read/write contention |
| Manual deployments | Risk of downtime on every release |

**Root cause:** The architecture was designed for a startup, not for growth. Every component was a single point of failure.

---

## Architecture Designed

```
Internet Users (APAC region)
        │
   [CloudFront] ──► Static assets cached at edge (PriceClass_200 covers APAC)
        │
   [Route 53] ──► Latency-based routing → us-east-1 + ap-southeast-1
        │
   [Application Load Balancer] ──► HTTPS, health checks, sticky sessions
        │
   [AWS Elastic Beanstalk]
   ├── Auto Scaling Group (min=2, max=8, CPU target tracking 65%)
   ├── Multi-AZ deployment (AZ-1a + AZ-1b)
   └── Managed platform updates (no manual patching)
        │
   [Amazon RDS Multi-AZ]
   ├── Primary: us-east-1a
   ├── Standby: us-east-1b (synchronous replication)
   └── Read Replica: ap-southeast-1 (reduces APAC read latency ~60%)
        │
   [CloudWatch] ──► Alarms on CPU, 5xx errors, RDS connections → SNS email
```

### Why Elastic Beanstalk (not EC2 directly)?

The client had a small ops team with no Kubernetes or advanced infrastructure experience. Elastic Beanstalk provides:
- Managed Auto Scaling and ALB — no manual configuration
- One-click platform updates — keeps runtime patched without downtime
- Built-in CloudWatch integration — no custom monitoring setup
- Deploy via `eb deploy` or Git push — no CI/CD pipeline required initially

**Right-sized for the client.** A technically superior EKS architecture would have created operational overhead they couldn't support.

---

## Stakeholder Communication

One of the core skills assessed in this simulation: explaining AWS architecture to a non-technical client audience without losing them in jargon.

### The Restaurant Analogy

> "Right now, your website is like a restaurant with one waiter. During dinner rush, your single waiter is overwhelmed and customers leave. Auto Scaling is like a restaurant that automatically brings in more waitstaff when the queue gets long — and sends them home when it quiets down. You only pay for each waiter while they're working."

**Why this works:** It maps the technical concept (horizontal scaling, pay-per-use) to a mental model the client already has. The client understood and approved the architecture in the first meeting.

### Handling the Cost Objection

Client question: *"We're currently paying $70/month. This looks more expensive."*

My response:
> "Your current $70/month is paying for one waiter who crashes during dinner rush. The new setup costs ~$280/month — but the three outages you had last quarter each cost you roughly $5,000 in lost revenue and customer trust. The architecture pays for itself in the first prevented outage."

**Framing shift:** Moved the conversation from infrastructure cost to business risk. Client approved.

---

## Architecture Decision Records

### ADR-001: Elastic Beanstalk over ECS / EKS
**Context:** Client needed a scalable compute layer with minimal ops overhead.  
**Decision:** Elastic Beanstalk.  
**Reason:** ECS and EKS require container expertise the client's team didn't have. Beanstalk abstracts the compute management while still giving access to underlying EC2/ALB if needed later. Right tool for the team's capability, not just the technical ideal.

### ADR-002: RDS Multi-AZ over Single-AZ
**Context:** Client had a single MySQL database — no failover.  
**Decision:** RDS Multi-AZ.  
**Reason:** Synchronous standby replica in a different AZ provides automatic failover in under 2 minutes — no DNS change required, no manual intervention. Cost: ~$60/month extra. Risk eliminated: total data tier unavailability.

### ADR-003: CloudFront with PriceClass_200 (Not PriceClass_100)
**Context:** Client is APAC-focused; PriceClass_100 only covers US/EU.  
**Decision:** PriceClass_200 to include Asia Pacific edge locations.  
**Reason:** APAC users without a CDN edge location would route all the way to us-east-1 — 180ms+ latency. PriceClass_200 adds ~$15/month but serves APAC users from Singapore/Tokyo edges — reduces latency to ~20ms.

---

## Outcome & Takeaways

**Technical outcome:** Architecture designed that achieves 99.9% availability SLO, handles 10× traffic spikes automatically, and serves APAC users at ~20ms CDN latency.

**Communication outcome:** Non-technical client understood and approved the recommendation in the first meeting. Architecture explanation translated to business language (restaurant analogy, cost-as-risk-elimination framing).

**Key learning:** A great SA doesn't just design the best architecture — they design the right architecture for the client's team capability and communicate it in the client's language. Technical correctness is necessary but not sufficient.

---

## Skills Demonstrated

- **Technical discovery:** Mapping current-state architecture, identifying failure modes before designing
- **Right-sizing solutions:** Choosing Elastic Beanstalk over EKS based on client capability, not technical perfection
- **Stakeholder communication:** Translating cloud architecture into business language (restaurant analogy)
- **Objection handling:** Reframing cost conversation from expense to risk elimination
- **AWS services:** Elastic Beanstalk, ALB, Auto Scaling, RDS Multi-AZ, CloudFront, Route 53, CloudWatch

---

*Built by Vanessa Awo | [LinkedIn](https://linkedin.com/in/vanessajen) | [Portfolio](https://jenellavan.com)*

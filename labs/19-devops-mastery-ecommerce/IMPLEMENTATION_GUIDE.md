# DevOps Mastery: Complete Implementation Guide

A hands-on, copy-paste-ready walkthrough for building a production-grade e-commerce platform across all 14 DevOps phases — from `git init` to a self-service developer portal.

> **How to use this guide:** Work through each phase top to bottom. Every command is numbered and copy-paste ready. Expected outputs are shown after each step so you can verify you are on track. Config files include inline comments explaining every line.
>
> For deeper explanations, trade-off discussions, and troubleshooting, see the phase-specific READMEs linked at the start of each section.

---

## Prerequisites & Environment Setup

### AWS Account

You need an AWS account with administrator access. The infrastructure provisioned in Phase 4+ will incur costs (~$15-25/day for the full stack).

### Tools to Install

```bash
# macOS (Homebrew)
brew install git node@20 python@3.11 terraform awscli kubectl helm \
  argocd kustomize gh docker --cask

# Verify everything is installed
git --version          # 2.40+
node --version         # v20.x.x
npm --version          # 10.x.x
python3 --version      # 3.11+
terraform --version    # 1.6+
aws --version          # 2.x
kubectl version --client  # 1.28+
helm version           # 3.x
argocd version --client   # 2.x
kustomize version      # 5.x
gh --version           # 2.x
docker --version       # 24+
```

### AWS Configuration

```bash
aws configure
# AWS Access Key ID: <your-key>
# AWS Secret Access Key: <your-secret>
# Default region name: us-east-1
# Default output format: json

# Verify access
aws sts get-caller-identity
# Expected: {"UserId":"...","Account":"123456789012","Arn":"arn:aws:iam::123456789012:user/..."}
```

### GitHub Repository

```bash
# Create the repository on GitHub
gh repo create ecommerce-platform --public --clone
cd ecommerce-platform
```

---

## Phase 1: Project Foundation & Version Control

**What you're building:** A monorepo with trunk-based development, conventional commits enforced via Husky/commitlint, and branch protection rules.

> [Phase 1 README](./phase-01-foundation/README.md) — detailed trade-offs and troubleshooting

### Step 1: Initialize the Monorepo

```bash
mkdir ecommerce-platform && cd ecommerce-platform
git init
```

### Step 2: Create the Directory Structure

```bash
# Service directories
mkdir -p services/{api-gateway,user-service,product-service,order-service,payment-service,notification-service}

# Infrastructure and CI/CD directories (used in later phases)
mkdir -p infrastructure/{modules,environments}
mkdir -p .github/workflows
```

### Step 3: Install Commitlint and Husky

```bash
npm init -y
npm install --save-dev @commitlint/cli @commitlint/config-conventional
npm install --save-dev husky
npx husky init
```

### Step 4: Configure the Commit Message Hook

```bash
echo 'npx --no -- commitlint --edit "$1"' > .husky/commit-msg
chmod +x .husky/commit-msg
```

### Step 5: Create the Commitlint Configuration

Create `.commitlintrc.js` at the repository root:

```javascript
module.exports = {
  extends: ['@commitlint/config-conventional'],
  rules: {
    // severity 2 = error (blocks commit)
    // 'always' = scope must be one of these values
    'scope-enum': [2, 'always', [
      'api-gateway',             // API Gateway service
      'user-service',            // User/Auth service
      'product-service',         // Product catalog service
      'order-service',           // Order management service
      'payment-service',         // Payment processing service
      'notification-service',    // Email/SMS notifications
      'infra',                   // Infrastructure/Terraform changes
      'ci',                      // CI/CD pipeline changes
      'docs'                     // Documentation changes
    ]],
    'type-enum': [2, 'always', [
      'feat', 'fix', 'docs', 'style', 'refactor',
      'perf', 'test', 'build', 'ci', 'chore'
    ]]
  }
};
```

### Step 6: Create the Initial Commit

```bash
git add .
git commit -m "chore(infra): initialize monorepo with commitlint and husky"
```

**Expected output:**

```
[main (root-commit) abc1234] chore(infra): initialize monorepo with commitlint and husky
 5 files changed, 42 insertions(+)
```

### Step 7: Verify Commit Validation

```bash
# This should FAIL
git commit --allow-empty -m "updated stuff"
# Expected: ✖ subject may not be empty, type may not be empty

# This should PASS
git commit --allow-empty -m "docs(docs): add project README"
# Expected: commit created successfully
```

### Step 8: Set Up Branch Protection (GitHub)

```bash
git remote add origin https://github.com/YOUR_ORG/ecommerce-platform.git
git push -u origin main
```

Then in GitHub: **Settings → Branches → Add rule** for `main`:
- Require a pull request before merging
- Require status checks to pass before merging
- Require linear history

### Verify Phase 1

- [ ] Invalid commit messages are rejected
- [ ] Valid conventional commits succeed
- [ ] All 10 types and 9 scopes are accepted
- [ ] `.commitlintrc.js` is committed

**Next:** With commit standards in place, Phase 2 builds the 6 microservices.

---

## Phase 2: Application Development (Microservices)

**What you're building:** Six microservices — API Gateway, User, Product, Order, Payment, and Notification — with database-per-service and RabbitMQ event-driven communication.

> [Phase 2 README](./phase-02-microservices/README.md) — architecture diagrams, service responsibilities, trade-offs

### Step 1: Set Up the API Gateway (Node.js/Express)

```bash
cd services/api-gateway
npm init -y
npm install express cors helmet morgan http-proxy-middleware express-rate-limit jsonwebtoken
```

### Step 2: Set Up the User Service (Node.js)

```bash
cd ../user-service
npm init -y
npm install express pg redis bcryptjs jsonwebtoken joi
npm install --save-dev jest supertest
```

### Step 3: Set Up the Product Service (Python/FastAPI)

```bash
cd ../product-service
python3 -m venv venv
source venv/bin/activate
pip install fastapi uvicorn sqlalchemy psycopg2-binary redis pydantic
```

### Step 4: Set Up the Order Service (Node.js)

```bash
cd ../order-service
npm init -y
npm install express pg amqplib uuid joi
```

### Step 5: Set Up the Payment Service (Node.js)

```bash
cd ../payment-service
npm init -y
npm install express pg amqplib uuid
```

### Step 6: Set Up the Notification Service (Python)

```bash
cd ../notification-service
python3 -m venv venv
source venv/bin/activate
pip install pika jinja2
```

### Step 7: Create the Docker Compose Development Environment

Create `docker-compose.dev.yml` in the project root:

```yaml
version: "3.9"

services:
  api-gateway:
    build: ./services/api-gateway
    ports:
      - "3000:3000"                        # External entry point
    environment:
      - NODE_ENV=development
      - USER_SERVICE_URL=http://user-service:3001       # Docker DNS service discovery
      - PRODUCT_SERVICE_URL=http://product-service:8000
      - ORDER_SERVICE_URL=http://order-service:3003
    depends_on:
      - user-service
      - product-service
      - order-service

  user-service:
    build: ./services/user-service
    ports:
      - "3001:3001"
    environment:
      - NODE_ENV=development
      - DATABASE_URL=postgresql://app:password@postgres-users:5432/users
      - REDIS_URL=redis://redis:6379
    depends_on:
      - postgres-users
      - redis

  product-service:
    build: ./services/product-service
    ports:
      - "8000:8000"
    environment:
      - DATABASE_URL=postgresql://app:password@postgres-products:5432/products
      - REDIS_URL=redis://redis:6379
    depends_on:
      - postgres-products
      - redis

  order-service:
    build: ./services/order-service
    ports:
      - "3003:3003"
    environment:
      - NODE_ENV=development
      - DATABASE_URL=postgresql://app:password@postgres-orders:5432/orders
      - RABBITMQ_URL=amqp://rabbitmq:5672
    depends_on:
      - postgres-orders
      - rabbitmq

  payment-service:
    build: ./services/payment-service
    ports:
      - "3004:3004"
    environment:
      - NODE_ENV=development
      - DATABASE_URL=postgresql://app:password@postgres-payments:5432/payments
      - RABBITMQ_URL=amqp://rabbitmq:5672
    depends_on:
      - postgres-payments
      - rabbitmq

  notification-service:
    build: ./services/notification-service
    environment:
      - RABBITMQ_URL=amqp://rabbitmq:5672
    depends_on:
      - rabbitmq

  # --- Database-per-service (4 separate PostgreSQL instances) ---
  postgres-users:
    image: postgres:16-alpine
    environment:
      POSTGRES_DB: users
      POSTGRES_USER: app
      POSTGRES_PASSWORD: password
    volumes:
      - pgdata-users:/var/lib/postgresql/data

  postgres-products:
    image: postgres:16-alpine
    environment:
      POSTGRES_DB: products
      POSTGRES_USER: app
      POSTGRES_PASSWORD: password
    volumes:
      - pgdata-products:/var/lib/postgresql/data

  postgres-orders:
    image: postgres:16-alpine
    environment:
      POSTGRES_DB: orders
      POSTGRES_USER: app
      POSTGRES_PASSWORD: password
    volumes:
      - pgdata-orders:/var/lib/postgresql/data

  postgres-payments:
    image: postgres:16-alpine
    environment:
      POSTGRES_DB: payments
      POSTGRES_USER: app
      POSTGRES_PASSWORD: password
    volumes:
      - pgdata-payments:/var/lib/postgresql/data

  # --- Shared infrastructure ---
  redis:
    image: redis:7-alpine
    ports:
      - "6379:6379"

  rabbitmq:
    image: rabbitmq:3-management-alpine
    ports:
      - "5672:5672"      # AMQP protocol
      - "15672:15672"    # Management UI

volumes:
  pgdata-users:
  pgdata-products:
  pgdata-orders:
  pgdata-payments:
```

### Step 8: Start Everything

```bash
docker compose -f docker-compose.dev.yml up -d
docker compose -f docker-compose.dev.yml ps
```

**Expected output:**

```
NAME                    STATUS    PORTS
api-gateway             Up        0.0.0.0:3000->3000/tcp
user-service            Up        0.0.0.0:3001->3001/tcp
product-service         Up        0.0.0.0:8000->8000/tcp
order-service           Up        0.0.0.0:3003->3003/tcp
payment-service         Up        0.0.0.0:3004->3004/tcp
notification-service    Up
postgres-users          Up        5432/tcp
postgres-products       Up        5432/tcp
postgres-orders         Up        5432/tcp
postgres-payments       Up        5432/tcp
redis                   Up        0.0.0.0:6379->6379/tcp
rabbitmq                Up        0.0.0.0:5672->5672/tcp, 0.0.0.0:15672->15672/tcp
```

### Step 9: Test the Services

```bash
curl http://localhost:3000/health    # API Gateway: {"status":"ok"}
curl http://localhost:3001/health    # User Service: {"status":"ok"}
curl http://localhost:8000/health    # Product Service: {"status":"ok"}
open http://localhost:15672          # RabbitMQ UI (guest/guest)
```

### Verify Phase 2

- [ ] All 12 containers are running
- [ ] Health endpoints respond for each service
- [ ] RabbitMQ management UI accessible at `http://localhost:15672`
- [ ] PostgreSQL instances accept connections: `docker compose exec postgres-users pg_isready`

**Next:** Phase 3 optimizes these images for production.

---

## Phase 3: Containerization

**What you're building:** Production-grade Docker images using multi-stage builds, distroless base images, non-root execution, and built-in health checks — achieving 80% smaller images.

> [Phase 3 README](./phase-03-containerization/README.md) — Dockerfile walkthrough, Python variant, troubleshooting

### Step 1: Create the Multi-Stage Dockerfile

Create a `Dockerfile` in each Node.js service directory (`services/api-gateway/`, `services/user-service/`, etc.):

```dockerfile
# Stage 1: Build — install dependencies and compile TypeScript
FROM node:20-alpine AS builder
WORKDIR /app
COPY package*.json ./
RUN npm ci --only=production          # Deterministic install from lockfile
COPY . .
RUN npm run build                      # Compile TypeScript to /app/dist

# Stage 2: Production — minimal runtime image
FROM gcr.io/distroless/nodejs20-debian12
WORKDIR /app
COPY --from=builder /app/dist ./dist
COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/package.json .

EXPOSE 3000

USER nonroot                           # UID 65534 — prevents privilege escalation

HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
  CMD ["node", "-e", "require('http').get('http://localhost:3000/health', (r) => { process.exit(r.statusCode === 200 ? 0 : 1) })"]

CMD ["dist/server.js"]
```

For Python services (`services/product-service/`, `services/notification-service/`):

```dockerfile
FROM python:3.11-slim AS builder
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY . .

FROM gcr.io/distroless/python3-debian12
WORKDIR /app
COPY --from=builder /usr/local/lib/python3.11/site-packages /usr/local/lib/python3.11/site-packages
COPY --from=builder /app .
ENV PYTHONPATH=/usr/local/lib/python3.11/site-packages
EXPOSE 8000
USER nonroot
CMD ["main.py"]
```

### Step 2: Create `.dockerignore`

Create in each service directory:

```
node_modules
npm-debug.log
.git
.gitignore
.env
coverage
tests
*.md
Dockerfile
docker-compose*.yml
```

### Step 3: Build and Verify

```bash
docker build -t user-service:latest services/user-service/
docker images user-service:latest
```

**Expected output:**

```
REPOSITORY      TAG       IMAGE ID       CREATED         SIZE
user-service    latest    abc123def456   10 seconds ago   178MB
```

### Step 4: Run and Test

```bash
docker run -d --name user-service-test \
  -p 3001:3000 \
  -e NODE_ENV=production \
  user-service:latest

curl http://localhost:3001/health
# Expected: {"status":"ok"}

# Verify non-root execution
docker top user-service-test
# Expected: UID 65534 (nonroot)

# Verify no shell access (distroless)
docker exec user-service-test sh 2>&1 || echo "No shell — distroless working correctly"

# Cleanup
docker rm -f user-service-test
```

### Verify Phase 3

- [ ] Image size under 200 MB
- [ ] Container runs as non-root (UID 65534)
- [ ] Health check passes: `docker inspect --format='{{.State.Health.Status}}' <container>`
- [ ] No shell access in distroless container
- [ ] Layer caching works (second build reuses `npm ci` layer)

**Next:** Phase 4 provisions the AWS infrastructure to host these containers.

---

## Phase 4: Infrastructure as Code

**What you're building:** The full AWS stack via Terraform — VPC (3 AZs), EKS with Bottlerocket nodes, Aurora PostgreSQL, ElastiCache Redis — with remote state in S3.

> [Phase 4 README](./phase-04-infrastructure-as-code/README.md) — architecture diagram, module walkthrough, troubleshooting

### Step 1: Set Up Remote State Backend

```bash
# Create S3 bucket for Terraform state
aws s3 mb s3://ecommerce-terraform-state-$(aws sts get-caller-identity --query Account --output text)

# Create DynamoDB table for state locking
aws dynamodb create-table \
  --table-name terraform-state-lock \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST
```

### Step 2: Create the VPC Module

Create `infrastructure/modules/vpc/main.tf`:

```hcl
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "${var.project}-${var.environment}"
  cidr = var.vpc_cidr                                # 10.0.0.0/16 — 65,536 IPs

  azs             = var.availability_zones            # 3 AZs for high availability
  private_subnets = var.private_subnet_cidrs          # EKS nodes, RDS, ElastiCache
  public_subnets  = var.public_subnet_cidrs           # Load balancers, NAT Gateways

  enable_nat_gateway     = true
  single_nat_gateway     = var.environment == "dev" ? true : false    # Save cost in dev
  one_nat_gateway_per_az = var.environment == "production" ? true : false  # HA in prod

  enable_dns_hostnames = true
  enable_dns_support   = true

  enable_s3_endpoint       = true                     # Free — keeps S3 traffic in VPC

  # Tags required for EKS to discover subnets
  public_subnet_tags = {
    "kubernetes.io/role/elb"                    = 1
    "kubernetes.io/cluster/${var.project}-${var.environment}" = "shared"
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb"           = 1
    "kubernetes.io/cluster/${var.project}-${var.environment}" = "shared"
    "karpenter.sh/discovery"                    = "${var.project}-${var.environment}"
  }

  tags = {
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}
```

### Step 3: Create the EKS Module

Create `infrastructure/modules/eks/main.tf`:

```hcl
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 19.0"

  cluster_name    = "${var.project}-${var.environment}"
  cluster_version = "1.28"

  vpc_id     = var.vpc_id
  subnet_ids = var.private_subnet_ids

  cluster_endpoint_public_access  = true
  cluster_endpoint_private_access = true

  eks_managed_node_groups = {
    general = {
      instance_types = ["m5.large"]                # 2 vCPU, 8 GB RAM
      min_size       = 2
      max_size       = 10
      desired_size   = 3
      ami_type       = "BOTTLEROCKET_x86_64"       # Security-focused, minimal OS

      labels = { role = "general" }
      tags   = { Environment = var.environment, ManagedBy = "terraform" }
    }

    spot = {
      instance_types = ["m5.large", "m5a.large", "m5.xlarge"]
      capacity_type  = "SPOT"                       # Up to 90% cheaper
      min_size       = 0
      max_size       = 20
      desired_size   = 2

      labels = { role = "spot", capacity = "spot" }
      taints = [{
        key    = "capacity"
        value  = "spot"
        effect = "NO_SCHEDULE"                      # Only spot-tolerant workloads
      }]
    }
  }

  cluster_addons = {
    coredns            = { most_recent = true }
    kube-proxy         = { most_recent = true }
    vpc-cni            = { most_recent = true }
    aws-ebs-csi-driver = { most_recent = true }
  }

  tags = { Project = var.project, Environment = var.environment, ManagedBy = "terraform" }
}
```

### Step 4: Create the RDS Module

Create `infrastructure/modules/rds/main.tf`:

```hcl
module "aurora" {
  source  = "terraform-aws-modules/rds-aurora/aws"
  version = "~> 8.0"

  name           = "${var.project}-${var.environment}"
  engine         = "aurora-postgresql"
  engine_version = "15.4"
  instance_class = var.environment == "production" ? "db.r6g.large" : "db.t4g.medium"
  instances = {
    writer = {}
    reader = {}                                       # Read replica in a different AZ
  }

  vpc_id               = var.vpc_id
  db_subnet_group_name = var.db_subnet_group_name
  security_group_rules = {
    vpc_ingress = {
      cidr_blocks = var.private_subnet_cidrs          # Only allow access from private subnets
    }
  }

  storage_encrypted   = true                          # At-rest encryption with KMS
  apply_immediately   = var.environment != "production"
  monitoring_interval = 60                            # Enhanced monitoring every 60s

  enabled_cloudwatch_logs_exports = ["postgresql"]

  backup_retention_period = var.environment == "production" ? 35 : 7   # 35 days in prod
  preferred_backup_window = "03:00-04:00"

  deletion_protection = var.environment == "production"               # Prevent accidents

  tags = { Project = var.project, Environment = var.environment, ManagedBy = "terraform" }
}
```

### Step 5: Create Production Variables

Create `infrastructure/environments/production.tfvars`:

```hcl
project     = "ecommerce"
environment = "production"
region      = "us-east-1"

vpc_cidr             = "10.0.0.0/16"
availability_zones   = ["us-east-1a", "us-east-1b", "us-east-1c"]
private_subnet_cidrs = ["10.0.10.0/24", "10.0.20.0/24", "10.0.30.0/24"]
public_subnet_cidrs  = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]

eks_node_instance_types = ["m5.large"]
eks_node_min_size       = 3
eks_node_max_size       = 20
eks_node_desired_size   = 5

rds_instance_class         = "db.r6g.large"
rds_backup_retention_days  = 35
rds_deletion_protection    = true

elasticache_node_type      = "cache.r6g.large"
elasticache_num_cache_nodes = 3
```

### Step 6: Initialize and Apply

```bash
cd infrastructure/environments

terraform init \
  -backend-config="bucket=ecommerce-terraform-state-ACCOUNT_ID" \
  -backend-config="key=production/terraform.tfstate" \
  -backend-config="region=us-east-1" \
  -backend-config="dynamodb_table=terraform-state-lock"

terraform plan -var-file=production.tfvars
terraform apply -var-file=production.tfvars
```

**Expected output:**

```
Apply complete! Resources: 47 added, 0 changed, 0 destroyed.

Outputs:
  vpc_id          = "vpc-0abc123def456"
  eks_cluster_name = "ecommerce-production"
  rds_endpoint    = "ecommerce-production.cluster-xyz.us-east-1.rds.amazonaws.com"
```

### Step 7: Configure kubectl

```bash
aws eks update-kubeconfig --name ecommerce-production --region us-east-1

kubectl get nodes
# Expected: 5 nodes in Ready state across 3 AZs
```

### Verify Phase 4

- [ ] `terraform plan` shows ~47 resources
- [ ] VPC created: `aws ec2 describe-vpcs --filters Name=tag:Name,Values=ecommerce-production`
- [ ] EKS cluster is ACTIVE: `aws eks describe-cluster --name ecommerce-production --query cluster.status`
- [ ] `kubectl get nodes` shows Ready nodes
- [ ] State file in S3: `aws s3 ls s3://ecommerce-terraform-state-ACCOUNT_ID/production/`

**Next:** Phase 5 creates CI/CD pipelines to build and deploy automatically.

---

## Phase 5: CI/CD Pipelines

**What you're building:** Monorepo-aware GitHub Actions with path-filtered builds, parallel lint/test/scan, Trivy container scanning, OIDC AWS auth, and environment-gated deployments.

> [Phase 5 README](./phase-05-cicd/README.md) — pipeline architecture, OIDC setup, troubleshooting

### Step 1: Set Up AWS OIDC for GitHub Actions

```bash
# Create OIDC identity provider (no static AWS credentials needed)
aws iam create-open-id-connect-provider \
  --url https://token.actions.githubusercontent.com \
  --client-id-list sts.amazonaws.com \
  --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1
```

### Step 2: Create the CI Pipeline

Create `.github/workflows/ci.yml`:

```yaml
name: CI Pipeline
on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

permissions:
  contents: read
  id-token: write                          # Required for OIDC AWS auth

jobs:
  detect-changes:
    runs-on: ubuntu-latest
    outputs:
      services: ${{ steps.filter.outputs.changes }}
    steps:
      - uses: actions/checkout@v4
      - uses: dorny/paths-filter@v2
        id: filter
        with:
          filters: |
            api-gateway: 'services/api-gateway/**'
            user-service: 'services/user-service/**'
            product-service: 'services/product-service/**'
            order-service: 'services/order-service/**'
            payment-service: 'services/payment-service/**'
            notification-service: 'services/notification-service/**'

  lint:
    needs: detect-changes
    if: needs.detect-changes.outputs.services != '[]'
    strategy:
      matrix:
        service: ${{ fromJson(needs.detect-changes.outputs.services) }}
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: 20
          cache: npm
          cache-dependency-path: services/${{ matrix.service }}/package-lock.json
      - run: cd services/${{ matrix.service }} && npm ci && npm run lint

  test:
    needs: detect-changes
    if: needs.detect-changes.outputs.services != '[]'
    strategy:
      matrix:
        service: ${{ fromJson(needs.detect-changes.outputs.services) }}
    runs-on: ubuntu-latest
    services:
      postgres:
        image: postgres:16-alpine
        env:
          POSTGRES_DB: test
          POSTGRES_USER: test
          POSTGRES_PASSWORD: test
        ports:
          - 5432:5432
      redis:
        image: redis:7-alpine
        ports:
          - 6379:6379
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: 20
      - run: cd services/${{ matrix.service }} && npm ci && npm test -- --coverage
      - uses: codecov/codecov-action@v3
        with:
          directory: services/${{ matrix.service }}/coverage

  build-and-scan:
    needs: [lint, test]
    if: github.ref == 'refs/heads/main'
    strategy:
      matrix:
        service: ${{ fromJson(needs.detect-changes.outputs.services) }}
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${{ secrets.AWS_ROLE_ARN }}
          aws-region: us-east-1
      - uses: aws-actions/amazon-ecr-login@v2
        id: ecr
      - name: Build Docker image
        run: |
          docker build -t ${{ steps.ecr.outputs.registry }}/${{ matrix.service }}:${{ github.sha }} \
            services/${{ matrix.service }}
      - name: Scan with Trivy
        uses: aquasecurity/trivy-action@master
        with:
          image-ref: ${{ steps.ecr.outputs.registry }}/${{ matrix.service }}:${{ github.sha }}
          format: table
          exit-code: 1                     # Fail build on vulnerabilities
          severity: CRITICAL,HIGH
      - name: Push to ECR
        run: |
          docker push ${{ steps.ecr.outputs.registry }}/${{ matrix.service }}:${{ github.sha }}
```

### Step 3: Create Helper Scripts

Create `scripts/version-bump.sh` and `scripts/release.sh`, then make them executable:

```bash
mkdir -p scripts
chmod +x scripts/version-bump.sh scripts/release.sh
```

### Step 4: Test Locally

```bash
# Check which services would be built
git diff --name-only main | grep "^services/" | cut -d/ -f2 | sort -u

# Run lint and test locally
cd services/user-service && npm run lint && npm test -- --coverage

# Build and scan locally
docker build -t user-service:test services/user-service/
docker run --rm aquasec/trivy image user-service:test --severity CRITICAL,HIGH
```

### Verify Phase 5

- [ ] CI triggers on push to main
- [ ] Path filtering works — changing only `user-service/` runs only user-service jobs
- [ ] Trivy blocks builds with CRITICAL/HIGH CVEs
- [ ] OIDC auth works (no static AWS credentials)
- [ ] Images are pushed to ECR with Git SHA tags

**Next:** Phase 6 creates Helm charts to deploy services on EKS.

---

## Phase 6: Kubernetes Orchestration

**What you're building:** A shared Helm chart for deploying all 6 microservices with HPA, PDB, health probes, IRSA, and per-environment values.

> [Phase 6 README](./phase-06-kubernetes/README.md) — Helm template walkthrough, probe design

### Step 1: Create the Helm Chart

```bash
mkdir -p helm/templates helm/values
```

Create `helm/Chart.yaml`:

```yaml
apiVersion: v2
name: ecommerce-service
description: A Helm chart for deploying e-commerce microservices on Kubernetes
type: application
version: 0.1.0
appVersion: "1.0.0"
keywords:
  - ecommerce
  - microservice
  - nodejs
home: https://github.com/org/ecommerce-gitops
sources:
  - https://github.com/org/ecommerce-gitops
maintainers:
  - name: platform-team
    email: platform@example.com
```

### Step 2: Create Production Values

Create `helm/values/production.yaml`:

```yaml
replicaCount: 3

image:
  repository: 123456789.dkr.ecr.us-east-1.amazonaws.com/user-service
  pullPolicy: IfNotPresent

serviceAccount:
  create: true
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::123456789:role/user-service-role  # IRSA

resources:
  requests:
    cpu: 250m
    memory: 256Mi
  limits:
    cpu: 500m
    memory: 512Mi

autoscaling:
  enabled: true
  minReplicas: 3
  maxReplicas: 20
  targetCPUUtilization: 70
  targetMemoryUtilization: 80

podDisruptionBudget:
  minAvailable: 2              # At least 2 pods always available during disruptions

probes:
  liveness:
    path: /health/live
    initialDelaySeconds: 10
    periodSeconds: 15
    failureThreshold: 3
  readiness:
    path: /health/ready
    initialDelaySeconds: 5
    periodSeconds: 10
    failureThreshold: 3
  startup:
    path: /health/live
    initialDelaySeconds: 0
    periodSeconds: 5
    failureThreshold: 30       # 30 x 5s = 150s max startup time

service:
  type: ClusterIP
  port: 3000

ingress:
  enabled: true
  className: istio
  hosts:
    - host: api.ecommerce.example.com
      paths:
        - path: /api/users
          pathType: Prefix

env:
  - name: NODE_ENV
    value: production
  - name: DATABASE_URL
    valueFrom:
      secretKeyRef:
        name: user-service-secrets
        key: database-url
  - name: REDIS_URL
    valueFrom:
      secretKeyRef:
        name: user-service-secrets
        key: redis-url

nodeSelector:
  role: general

affinity:
  podAntiAffinity:
    preferredDuringSchedulingIgnoredDuringExecution:
      - weight: 100
        podAffinityTerm:
          labelSelector:
            matchExpressions:
              - key: app
                operator: In
                values:
                  - user-service
          topologyKey: topology.kubernetes.io/zone   # Spread across AZs
```

### Step 3: Deploy with Helm

```bash
# Deploy user-service
helm upgrade --install user-service ./helm \
  -f helm/values/production.yaml \
  -n production --create-namespace

# Verify
kubectl get pods -n production
# Expected: 3 pods running for user-service

kubectl get hpa -n production
# Expected: HPA targeting 70% CPU

kubectl get pdb -n production
# Expected: PDB with minAvailable=2
```

### Verify Phase 6

- [ ] All 6 services deployed with 3 replicas each
- [ ] HPA configured for CPU and memory scaling
- [ ] PDB prevents disrupting more than 1 pod at a time
- [ ] Health probes pass (liveness, readiness, startup)
- [ ] Pods spread across AZs via anti-affinity

**Next:** Phase 7 sets up ArgoCD for GitOps-based continuous delivery.

---

## Phase 7: GitOps & Continuous Delivery

**What you're building:** ArgoCD managing all deployments via Git — Application-of-Apps pattern, Kustomize overlays, automated image tag updates.

> [Phase 7 README](./phase-07-gitops/README.md) — ArgoCD architecture, sync waves, Image Updater

### Step 1: Install ArgoCD

```bash
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Wait for ArgoCD to be ready
kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n argocd

# Get the initial admin password
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

### Step 2: Create the Kustomize Base

Create `kustomize/base/kustomization.yaml`:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - deployment.yaml
  - service.yaml
  - hpa.yaml
  - pdb.yaml

commonLabels:
  app.kubernetes.io/part-of: ecommerce
```

### Step 3: Create the Production Overlay

Create `kustomize/overlays/production/kustomization.yaml`:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: ecommerce-prod

resources:
  - ../../base

commonLabels:
  environment: production
  team: platform

commonAnnotations:
  app.kubernetes.io/managed-by: argocd

patches:
  - target:
      kind: Deployment
      name: ".*"
    patch: |
      apiVersion: apps/v1
      kind: Deployment
      metadata:
        name: placeholder
      spec:
        replicas: 3
        template:
          spec:
            containers:
              - name: ecommerce-service
                resources:
                  requests:
                    cpu: 250m
                    memory: 256Mi
                  limits:
                    cpu: 500m
                    memory: 512Mi

  - target:
      kind: HorizontalPodAutoscaler
      name: ".*"
    patch: |
      apiVersion: autoscaling/v2
      kind: HorizontalPodAutoscaler
      metadata:
        name: placeholder
      spec:
        minReplicas: 3
        maxReplicas: 20

  - target:
      kind: PodDisruptionBudget
      name: ".*"
    patch: |
      apiVersion: policy/v1
      kind: PodDisruptionBudget
      metadata:
        name: placeholder
      spec:
        minAvailable: 2
```

### Step 4: Create the ArgoCD Application

Create `argocd/application.yaml`:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: user-service
  namespace: argocd
  annotations:
    argocd-image-updater.argoproj.io/image-list: app=123456789.dkr.ecr.us-east-1.amazonaws.com/user-service
    argocd-image-updater.argoproj.io/app.update-strategy: semver
    argocd-image-updater.argoproj.io/write-back-method: git
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: ecommerce
  source:
    repoURL: https://github.com/org/ecommerce-gitops
    path: services/user-service/overlays/production
    targetRevision: main
  destination:
    server: https://kubernetes.default.svc
    namespace: production
  syncPolicy:
    automated:
      prune: true                          # Delete resources removed from Git
      selfHeal: true                       # Revert manual cluster changes
    syncOptions:
      - CreateNamespace=true
      - PrunePropagationPolicy=foreground
    retry:
      limit: 5
      backoff:
        duration: 5s
        factor: 2
        maxDuration: 3m
```

### Step 5: Apply and Verify

```bash
kubectl apply -f argocd/application.yaml

# Check sync status
argocd app get user-service
# Expected: Status: Synced, Health: Healthy

# Watch for changes
argocd app sync user-service
```

### Verify Phase 7

- [ ] ArgoCD UI accessible (port-forward: `kubectl port-forward svc/argocd-server -n argocd 8080:443`)
- [ ] Application shows as Synced and Healthy
- [ ] Changing a value in Git triggers automatic sync
- [ ] `selfHeal: true` reverts manual `kubectl` changes

**Next:** Phase 8 adds observability — metrics, logs, traces, and SLO dashboards.

---

## Phase 8: Observability & Monitoring

**What you're building:** Full observability stack — Prometheus for metrics with SLI/SLO rules, Grafana dashboards, Loki for log aggregation, and alerting via PagerDuty.

> [Phase 8 README](./phase-08-observability/README.md) — SLO design, dashboard JSON, Loki pipeline

### Step 1: Install the Prometheus Stack

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

helm install prometheus prometheus-community/kube-prometheus-stack \
  -n monitoring --create-namespace \
  --set grafana.enabled=true \
  --set alertmanager.enabled=true
```

### Step 2: Apply SLO Recording Rules

Create and apply `prometheus/slo-rules.yml`:

```yaml
groups:
  - name: slo-rules
    interval: 30s
    rules:
      # API Availability SLI — ratio of non-5xx requests
      - record: slo:api_availability:ratio_rate5m
        expr: |
          sum(rate(http_requests_total{status!~"5.."}[5m]))
          /
          sum(rate(http_requests_total[5m]))

      - record: slo:api_availability:ratio_rate1h
        expr: |
          sum(rate(http_requests_total{status!~"5.."}[1h]))
          /
          sum(rate(http_requests_total[1h]))

      # API Latency SLI — ratio of requests under 200ms
      - record: slo:api_latency:ratio_rate5m
        expr: |
          sum(rate(http_request_duration_seconds_bucket{le="0.2"}[5m]))
          /
          sum(rate(http_request_duration_seconds_count[5m]))

      # Error Budget Remaining (target: 99.95%)
      - record: slo:error_budget:remaining
        expr: |
          1 - (
            (1 - slo:api_availability:ratio_rate1h)
            /
            (1 - 0.9995)
          )

  - name: slo-alerts
    rules:
      - alert: SLOBurnRateHigh
        expr: slo:api_availability:ratio_rate5m < 0.999
        for: 5m
        labels:
          severity: critical
          team: platform
        annotations:
          summary: "API SLO burn rate is too high"
          description: "5-minute availability is {{ $value | humanizePercentage }}, SLO target is 99.95%"

      - alert: ErrorBudgetExhausted
        expr: slo:error_budget:remaining < 0.1
        for: 10m
        labels:
          severity: warning
          team: platform
        annotations:
          summary: "Error budget is nearly exhausted"
          description: "Only {{ $value | humanizePercentage }} of error budget remaining"

      - alert: HighLatency
        expr: slo:api_latency:ratio_rate5m < 0.95
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "API latency SLO at risk"
          description: "Only {{ $value | humanizePercentage }} of requests are under 200ms"
```

```bash
kubectl apply -f prometheus/slo-rules.yml -n monitoring
```

### Step 3: Install Loki for Log Aggregation

```bash
helm repo add grafana https://grafana.github.io/helm-charts

helm install loki grafana/loki-stack \
  -n monitoring \
  --set loki.persistence.enabled=true \
  --set promtail.enabled=true
```

### Step 4: Import Grafana Dashboard

The SLO overview dashboard (`grafana/dashboards/slo-overview.json`) provides 5 panels:
1. **SLO Burn Rate** — Multi-window burn rate for availability
2. **Error Budget Remaining** — Gauge showing remaining budget
3. **Request Rate** — Throughput by status code class (2xx/4xx/5xx)
4. **P99 Latency** — 99th percentile with 200ms SLO target line
5. **5xx Error Rate** — Server error ratio

Import via Grafana UI: **Dashboards → Import → Upload JSON**

### Verify Phase 8

```bash
# Prometheus is scraping targets
kubectl port-forward svc/prometheus-kube-prometheus-prometheus -n monitoring 9090:9090
# Visit http://localhost:9090/targets — all targets should be UP

# Grafana is accessible
kubectl port-forward svc/prometheus-grafana -n monitoring 3000:80
# Visit http://localhost:3000 (admin / prom-operator)

# SLO rules are loaded
curl -s http://localhost:9090/api/v1/rules | jq '.data.groups[].name'
# Expected: "slo-rules", "slo-alerts"
```

- [ ] Prometheus targets are all UP
- [ ] SLO recording rules produce values
- [ ] Grafana SLO dashboard renders correctly
- [ ] Loki receives logs from all pods

**Next:** Phase 9 adds security — admission policies, secrets management, network policies.

---

## Phase 9: Security & Compliance

**What you're building:** OPA/Gatekeeper admission policies, HashiCorp Vault for dynamic secrets, Kubernetes Network Policies for zero-trust networking.

> [Phase 9 README](./phase-09-security/README.md) — Rego policies, Vault HA setup, RBAC design

### Step 1: Install OPA Gatekeeper

```bash
kubectl apply -f https://raw.githubusercontent.com/open-policy-agent/gatekeeper/release-3.14/deploy/gatekeeper.yaml

# Wait for Gatekeeper to be ready
kubectl wait --for=condition=available --timeout=300s deployment/gatekeeper-controller-manager -n gatekeeper-system
```

### Step 2: Apply the Non-Root Container Policy

Create and apply `gatekeeper/require-nonroot.yaml`:

```yaml
apiVersion: templates.gatekeeper.sh/v1
kind: ConstraintTemplate
metadata:
  name: k8srequirenonroot
spec:
  crd:
    spec:
      names:
        kind: K8sRequireNonRoot
      validation:
        openAPIV3Schema:
          type: object
          properties:
            exemptImages:
              type: array
              items:
                type: string
  targets:
    - target: admission.k8s.gatekeeper.sh
      rego: |
        package k8srequirenonroot

        violation[{"msg": msg}] {
          container := input.review.object.spec.containers[_]
          not is_exempt(container.image)
          has_root_access(container)
          msg := sprintf("Container '%v' must not run as root", [container.name])
        }

        has_root_access(container) {
          not container.securityContext.runAsNonRoot
        }

        has_root_access(container) {
          container.securityContext.runAsUser == 0
        }

        is_exempt(image) {
          exempt := input.parameters.exemptImages[_]
          glob.match(exempt, [], image)
        }
---
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sRequireNonRoot
metadata:
  name: require-non-root-containers
spec:
  match:
    kinds:
      - apiGroups: [""]
        kinds: ["Pod"]
    namespaces: ["production", "staging"]
  parameters:
    exemptImages:
      - "istio/proxyv2:*"
      - "docker.io/istio/proxyv2:*"
```

```bash
kubectl apply -f gatekeeper/require-nonroot.yaml

# Test: this should be DENIED
kubectl run test-root --image=nginx --restart=Never -n production 2>&1
# Expected: Error from server: admission webhook denied the request: Container 'test-root' must not run as root
```

### Step 3: Install HashiCorp Vault

```bash
helm repo add hashicorp https://helm.releases.hashicorp.com
helm install vault hashicorp/vault \
  -n vault --create-namespace \
  --set server.ha.enabled=true \
  --set server.ha.replicas=3
```

### Step 4: Apply Network Policies

Create and apply `network-policies/user-service.yaml`:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: user-service
  namespace: production
spec:
  podSelector:
    matchLabels:
      app: user-service
  policyTypes:
    - Ingress
    - Egress
  ingress:
    - from:                                # Only API Gateway can reach user-service
        - podSelector:
            matchLabels:
              app: api-gateway
      ports:
        - protocol: TCP
          port: 3001
    - from:                                # Prometheus can scrape metrics
        - namespaceSelector:
            matchLabels:
              name: monitoring
          podSelector:
            matchLabels:
              app: prometheus
      ports:
        - protocol: TCP
          port: 9090
  egress:
    - to:                                  # DNS resolution
        - namespaceSelector: {}
          podSelector:
            matchLabels:
              k8s-app: kube-dns
      ports:
        - protocol: UDP
          port: 53
    - to:                                  # PostgreSQL (in VPC)
        - ipBlock:
            cidr: 10.0.0.0/16
      ports:
        - protocol: TCP
          port: 5432
    - to:                                  # Redis (in VPC)
        - ipBlock:
            cidr: 10.0.0.0/16
      ports:
        - protocol: TCP
          port: 6379
    - to:                                  # RabbitMQ
        - podSelector:
            matchLabels:
              app: rabbitmq
      ports:
        - protocol: TCP
          port: 5672
```

```bash
kubectl apply -f network-policies/user-service.yaml
```

### Verify Phase 9

- [ ] Root containers are rejected in production/staging namespaces
- [ ] Vault pods are running in HA mode (3 replicas)
- [ ] Network policies block unauthorized traffic
- [ ] User-service can reach PostgreSQL, Redis, RabbitMQ
- [ ] User-service rejects traffic from anything other than api-gateway

**Next:** Phase 10 introduces chaos engineering to validate resilience.

---

## Phase 10: Chaos Engineering & Resilience

**What you're building:** Litmus Chaos experiments (pod kill, network latency) and AWS FIS experiments (AZ failure) with automated health probes.

> [Phase 10 README](./phase-10-chaos/README.md) — hypothesis framework, game day structure

### Step 1: Install Litmus Chaos

```bash
helm repo add litmuschaos https://litmuschaos.github.io/litmus-helm/
helm install litmus litmuschaos/litmus \
  -n litmus --create-namespace \
  --set portal.frontend.service.type=ClusterIP

# Install generic experiments
kubectl apply -f https://hub.litmuschaos.io/api/chaos/3.0.0?file=charts/generic/experiments.yaml -n production
```

### Step 2: Run a Pod Kill Experiment

Create and apply `litmus/pod-kill.yaml`:

```yaml
apiVersion: litmuschaos.io/v1alpha1
kind: ChaosEngine
metadata:
  name: order-service-chaos
  namespace: production
spec:
  appinfo:
    appns: production
    applabel: app=order-service
    appkind: deployment
  engineState: active
  chaosServiceAccount: litmus-admin
  monitoring: true
  jobCleanUpPolicy: retain
  experiments:
    - name: pod-delete
      spec:
        components:
          env:
            - name: TOTAL_CHAOS_DURATION
              value: "30"                  # Run for 30 seconds
            - name: CHAOS_INTERVAL
              value: "10"                  # Kill a pod every 10 seconds
            - name: FORCE
              value: "false"
            - name: PODS_AFFECTED_PERC
              value: "50"                  # Affect 50% of pods
        probe:
          - name: check-api-availability
            type: httpProbe
            httpProbe/inputs:
              url: http://api-gateway.production.svc:3000/health
              method:
                get:
                  criteria: ==
                  responseCode: "200"
            mode: Continuous               # Check throughout the experiment
            runProperties:
              probeTimeout: 5
              interval: 5
              retry: 3
```

```bash
kubectl apply -f litmus/pod-kill.yaml

# Watch the experiment
kubectl get chaosresult -n production -w
# Expected: experimentStatus.verdict = "Pass" (API remained available during chaos)
```

### Step 3: Create an AWS FIS AZ Failure Experiment

```bash
# Create the experiment template from the JSON definition
aws fis create-experiment-template \
  --cli-input-json file://aws-fis/az-failure-experiment.json

# Run the experiment (review the template first!)
aws fis start-experiment --experiment-template-id EXT_ID
```

### Verify Phase 10

- [ ] Pod kill experiment completes with verdict "Pass"
- [ ] API Gateway remains available during pod deletion
- [ ] FIS experiment template created
- [ ] CloudWatch stop conditions are configured for safety

**Next:** Phase 11 adds Istio service mesh for mTLS, canary deployments, and traffic management.

---

## Phase 11: Service Mesh & Advanced Networking

**What you're building:** Istio service mesh with strict mTLS, weighted traffic routing, canary deployments via Flagger, and circuit breaking.

> [Phase 11 README](./phase-11-service-mesh/README.md) — Istio architecture, Flagger configuration

### Step 1: Install Istio

```bash
istioctl install --set profile=production -y

# Enable sidecar injection for the production namespace
kubectl label namespace production istio-injection=enabled

# Restart pods to inject sidecars
kubectl rollout restart deployment -n production

# Verify sidecars
kubectl get pods -n production -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.containers[*].name}{"\n"}{end}'
# Expected: each pod should have an "istio-proxy" container
```

### Step 2: Enable Strict mTLS

Apply `istio/peer-authentication.yaml`:

```yaml
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: default
  namespace: production
spec:
  mtls:
    mode: STRICT                           # All traffic must be mTLS-encrypted
```

```bash
kubectl apply -f istio/peer-authentication.yaml

# Verify mTLS is enforced
istioctl x describe pod <user-service-pod-name> -n production
# Expected: "mTLS: STRICT"
```

### Step 3: Install Flagger for Canary Deployments

```bash
helm repo add flagger https://flagger.app
helm install flagger flagger/flagger \
  -n istio-system \
  --set meshProvider=istio \
  --set metricsServer=http://prometheus-kube-prometheus-prometheus.monitoring:9090
```

### Step 4: Create a Canary Release

The canary configuration (`canary/canary-release.yaml`) defines:
- **VirtualService** — Routes traffic 90% stable / 10% canary
- **DestinationRule** — Defines stable/canary subsets with circuit breaking
- **Flagger Canary** — Automates progressive delivery with 10% step increments up to 50%, with metrics gates (99% success rate, <500ms p99 latency)

```bash
kubectl apply -f canary/canary-release.yaml

# Watch the canary progress
kubectl get canary -n ecommerce-prod -w
# Expected: Status progresses through Initializing → Progressing → Succeeded
```

### Verify Phase 11

- [ ] All pods have Istio sidecar proxies
- [ ] mTLS is STRICT for the production namespace
- [ ] Canary deployments shift traffic progressively
- [ ] Circuit breaking ejects unhealthy endpoints
- [ ] Flagger rolls back automatically on metric failures

**Next:** Phase 12 sets up multi-region disaster recovery.

---

## Phase 12: Multi-Region & Disaster Recovery

**What you're building:** Active-passive multi-region setup — Route 53 failover, Aurora Global Database, Velero backups — with RPO < 1 min and RTO < 5 min.

> [Phase 12 README](./phase-12-multi-region/README.md) — failover runbook, DR drill procedure

### Step 1: Deploy Secondary Region Infrastructure

```bash
# Apply Terraform for the secondary region (eu-west-1)
cd infrastructure/environments
terraform workspace new eu-west-1
terraform apply -var-file=secondary.tfvars
```

### Step 2: Configure Route 53 Failover

Create `terraform/route53.tf`:

```hcl
resource "aws_route53_health_check" "primary" {
  fqdn              = "api.us-east-1.ecommerce.example.com"
  port              = 443
  type              = "HTTPS"
  resource_path     = "/health"
  failure_threshold = 3             # 3 consecutive failures = unhealthy
  request_interval  = 10            # Check every 10 seconds

  tags = { Name = "primary-health-check", Environment = "production" }
}

resource "aws_route53_health_check" "secondary" {
  fqdn              = "api.eu-west-1.ecommerce.example.com"
  port              = 443
  type              = "HTTPS"
  resource_path     = "/health"
  failure_threshold = 3
  request_interval  = 10

  tags = { Name = "secondary-health-check", Environment = "production" }
}

resource "aws_route53_record" "api_primary" {
  zone_id = var.zone_id
  name    = "api.ecommerce.example.com"
  type    = "A"

  failover_routing_policy { type = "PRIMARY" }

  alias {
    name                   = var.primary_alb_dns
    zone_id                = var.primary_alb_zone_id
    evaluate_target_health = true
  }

  set_identifier  = "primary"
  health_check_id = aws_route53_health_check.primary.id
}

resource "aws_route53_record" "api_secondary" {
  zone_id = var.zone_id
  name    = "api.ecommerce.example.com"
  type    = "A"

  failover_routing_policy { type = "SECONDARY" }

  alias {
    name                   = var.secondary_alb_dns
    zone_id                = var.secondary_alb_zone_id
    evaluate_target_health = true
  }

  set_identifier  = "secondary"
  health_check_id = aws_route53_health_check.secondary.id
}
```

```bash
terraform apply
```

### Step 3: Install Velero for Backup

```bash
velero install \
  --provider aws \
  --plugins velero/velero-plugin-for-aws:v1.8.0 \
  --bucket ecommerce-velero-backups \
  --backup-location-config region=us-east-1 \
  --snapshot-location-config region=us-east-1

# Create a scheduled backup (every 6 hours)
velero schedule create production-backup \
  --schedule="0 */6 * * *" \
  --include-namespaces production \
  --ttl 720h
```

### Step 4: Test Failover

```bash
# Simulate primary failure (manually fail the health check)
# Route 53 will automatically failover to secondary in ~30 seconds

# Verify DNS resolution points to secondary
dig api.ecommerce.example.com
# Expected: A record pointing to eu-west-1 ALB
```

### Verify Phase 12

- [ ] Route 53 health checks are healthy for both regions
- [ ] DNS failover triggers within 30 seconds
- [ ] Aurora Global Database replicates to secondary region
- [ ] Velero backups run on schedule
- [ ] Restore from backup succeeds

**Next:** Phase 13 adds FinOps — cost allocation, autoscaling optimization, and budget alerts.

---

## Phase 13: FinOps & Cost Optimization

**What you're building:** Karpenter for intelligent node provisioning with Spot preference, Kubecost for cost allocation and anomaly detection, ResourceQuotas and LimitRanges for guardrails.

> [Phase 13 README](./phase-13-finops/README.md) — Spot strategy, right-sizing, cost reports

### Step 1: Install Karpenter

```bash
helm repo add karpenter https://charts.karpenter.sh/
helm install karpenter karpenter/karpenter \
  -n karpenter --create-namespace \
  --set settings.aws.clusterName=ecommerce-production \
  --set settings.aws.clusterEndpoint=$(aws eks describe-cluster --name ecommerce-production --query cluster.endpoint --output text)
```

### Step 2: Create the Karpenter Provisioner

Apply `karpenter/provisioner.yaml`:

```yaml
apiVersion: karpenter.sh/v1alpha5
kind: Provisioner
metadata:
  name: default
spec:
  requirements:
    - key: karpenter.sh/capacity-type
      operator: In
      values: ["spot", "on-demand"]        # Prefer Spot (up to 90% cheaper)
    - key: node.kubernetes.io/instance-type
      operator: In
      values:
        - m5.large
        - m5.xlarge
        - m5a.large
        - m5a.xlarge
        - m6i.large
        - m6i.xlarge
    - key: topology.kubernetes.io/zone
      operator: In
      values: ["us-east-1a", "us-east-1b", "us-east-1c"]
  limits:
    resources:
      cpu: "100"                           # Max 100 vCPU across all nodes
      memory: 400Gi
  providerRef:
    name: default
  consolidation:
    enabled: true                          # Automatically consolidate underutilized nodes
  ttlSecondsAfterEmpty: 30                 # Remove empty nodes after 30 seconds
  ttlSecondsUntilExpired: 2592000          # Replace nodes every 30 days
---
apiVersion: karpenter.k8s.aws/v1alpha1
kind: AWSNodeTemplate
metadata:
  name: default
spec:
  subnetSelector:
    karpenter.sh/discovery: ecommerce-production
  securityGroupSelector:
    karpenter.sh/discovery: ecommerce-production
  amiFamily: Bottlerocket
  blockDeviceMappings:
    - deviceName: /dev/xvda
      ebs:
        volumeSize: 50Gi
        volumeType: gp3
        encrypted: true
  tags:
    Project: ecommerce
    ManagedBy: karpenter
```

```bash
kubectl apply -f karpenter/provisioner.yaml
```

### Step 3: Install Kubecost

```bash
helm repo add kubecost https://kubecost.github.io/cost-analyzer/
helm install kubecost kubecost/cost-analyzer \
  -n kubecost --create-namespace \
  --set kubecostToken="YOUR_TOKEN"
```

### Step 4: Apply ResourceQuota and LimitRange

The `kubecost/cost-allocation.yaml` includes:
- **ResourceQuota** — Limits the production namespace to 40 CPU / 80Gi memory requests
- **LimitRange** — Sets default container resources (100m CPU / 128Mi memory requests)
- **Kubecost AlertPolicy** — Anomaly detection for cost spikes (>20% increase), idle cost thresholds, and budget overruns

```bash
kubectl apply -f kubecost/cost-allocation.yaml
```

### Verify Phase 13

```bash
# Karpenter is provisioning nodes
kubectl get nodes -l karpenter.sh/provisioner-name=default
# Expected: Nodes provisioned with Spot capacity type

# Kubecost dashboard
kubectl port-forward svc/kubecost-cost-analyzer -n kubecost 9090:9090
# Visit http://localhost:9090

# ResourceQuota is enforced
kubectl describe resourcequota ecommerce-prod-quota -n ecommerce-prod
```

- [ ] Karpenter provisions Spot instances when possible
- [ ] Node consolidation removes underutilized nodes
- [ ] Kubecost shows cost per namespace and service
- [ ] ResourceQuota prevents over-provisioning
- [ ] Cost alerts fire on anomalies

**Next:** Phase 14 builds the internal developer platform for self-service.

---

## Phase 14: Platform Engineering & Developer Portal

**What you're building:** Backstage developer portal with golden path templates for new service scaffolding, Crossplane compositions for self-service databases — enabling 5-minute new service setup.

> [Phase 14 README](./phase-14-platform-engineering/README.md) — Backstage setup, Crossplane compositions

### Step 1: Install Backstage

```bash
npx @backstage/create-app@latest
cd backstage
yarn install
yarn dev
```

### Step 2: Create the New Microservice Template

The template (`backstage/templates/new-microservice.yaml`) scaffolds a production-ready service in 5 minutes:

```yaml
apiVersion: scaffolder.backstage.io/v1beta3
kind: Template
metadata:
  name: new-microservice
  title: Create a New Microservice
  description: |
    Scaffold a production-ready microservice with CI/CD pipeline,
    Helm chart, Dockerfile, observability, and ArgoCD deployment.
  tags: [nodejs, python, microservice, recommended]
spec:
  owner: platform-team
  type: service
  parameters:
    - title: Service Details
      required: [name, description, owner]
      properties:
        name:
          title: Service Name
          type: string
          pattern: "^[a-z][a-z0-9-]*$"
        description:
          title: Description
          type: string
        owner:
          title: Owner Team
          type: string
          ui:field: OwnerPicker
          ui:options:
            allowedKinds: [Group]
    - title: Technical Configuration
      properties:
        language:
          title: Language
          type: string
          enum: [nodejs, python]
          enumNames: ["Node.js (Express)", "Python (FastAPI)"]
          default: nodejs
        database:
          title: Database
          type: string
          enum: [postgresql, none]
          enumNames: ["PostgreSQL (Aurora)", "None"]
          default: postgresql
        messaging:
          title: Message Queue
          type: string
          enum: [rabbitmq, none]
          default: none
        cache:
          title: Cache
          type: string
          enum: [redis, none]
          default: none
  steps:
    - id: fetch-template
      name: Fetch Base Template
      action: fetch:template
      input:
        url: ./skeleton/${{ parameters.language }}
        values:
          name: ${{ parameters.name }}
          description: ${{ parameters.description }}
          owner: ${{ parameters.owner }}
          database: ${{ parameters.database }}
          messaging: ${{ parameters.messaging }}
          cache: ${{ parameters.cache }}
    - id: publish
      name: Publish to GitHub
      action: publish:github
      input:
        repoUrl: github.com?owner=org&repo=${{ parameters.name }}
        description: ${{ parameters.description }}
        defaultBranch: main
        protectDefaultBranch: true
    - id: create-argocd-app
      name: Create ArgoCD Application
      action: argocd:create-resources
      input:
        appName: ${{ parameters.name }}
        argoInstance: production
        namespace: production
        path: deploy/overlays/production
    - id: register
      name: Register in Catalog
      action: catalog:register
      input:
        repoContentsUrl: ${{ steps.publish.output.repoContentsUrl }}
        catalogInfoPath: /catalog-info.yaml
  output:
    links:
      - title: Repository
        url: ${{ steps.publish.output.remoteUrl }}
      - title: ArgoCD Application
        url: https://argocd.example.com/applications/${{ parameters.name }}
      - title: Open in catalog
        icon: catalog
        entityRef: ${{ steps.register.output.entityRef }}
```

### Step 3: Install Crossplane for Self-Service Infrastructure

```bash
helm repo add crossplane-stable https://charts.crossplane.io/stable
helm install crossplane crossplane-stable/crossplane \
  -n crossplane-system --create-namespace

# Install the AWS provider
kubectl apply -f - <<EOF
apiVersion: pkg.crossplane.io/v1
kind: Provider
metadata:
  name: provider-aws
spec:
  package: xpkg.upbound.io/upbound/provider-aws:v0.40.0
EOF
```

### Step 4: Create the Database Composition

Apply `crossplane/database-composition.yaml`:

```yaml
apiVersion: apiextensions.crossplane.io/v1
kind: CompositeResourceDefinition
metadata:
  name: xdatabases.platform.ecommerce.example.com
spec:
  group: platform.ecommerce.example.com
  names:
    kind: XDatabase
    plural: xdatabases
  claimNames:
    kind: Database
    plural: databases
  versions:
    - name: v1alpha1
      served: true
      referenceable: true
      schema:
        openAPIV3Schema:
          type: object
          properties:
            spec:
              type: object
              properties:
                parameters:
                  type: object
                  properties:
                    size:
                      type: string
                      enum: [small, medium, large]
                      default: small
                    engine:
                      type: string
                      enum: [postgresql]
                      default: postgresql
                  required: [size]
              required: [parameters]
---
apiVersion: apiextensions.crossplane.io/v1
kind: Composition
metadata:
  name: database-postgresql
  labels:
    provider: aws
    engine: postgresql
spec:
  compositeTypeRef:
    apiVersion: platform.ecommerce.example.com/v1alpha1
    kind: XDatabase
  resources:
    - name: rds-instance
      base:
        apiVersion: rds.aws.upbound.io/v1beta1
        kind: Instance
        spec:
          forProvider:
            region: us-east-1
            engine: aurora-postgresql
            engineVersion: "15.4"
            storageEncrypted: true
            autoMinorVersionUpgrade: true
            backupRetentionPeriod: 7
            deletionProtection: true
          providerConfigRef:
            name: aws-provider
      patches:
        - type: FromCompositeFieldPath
          fromFieldPath: spec.parameters.size
          toFieldPath: spec.forProvider.instanceClass
          transforms:
            - type: map
              map:
                small: db.t4g.medium       # Dev/test
                medium: db.r6g.large       # Production
                large: db.r6g.xlarge       # High-performance
```

```bash
kubectl apply -f crossplane/database-composition.yaml
```

### Step 5: Developers Can Now Self-Service

```bash
# A developer requests a database — no Terraform, no tickets
kubectl apply -f - <<EOF
apiVersion: platform.ecommerce.example.com/v1alpha1
kind: Database
metadata:
  name: my-service-db
  namespace: production
spec:
  parameters:
    size: small
    engine: postgresql
EOF

# Watch Crossplane provision the RDS instance
kubectl get database my-service-db -n production -w
# Expected: READY=True after 10-15 minutes
```

### Verify Phase 14

- [ ] Backstage portal is accessible
- [ ] New microservice template creates a repo, Helm chart, ArgoCD app, and catalog entry
- [ ] Crossplane Database claim provisions an Aurora instance
- [ ] Self-service setup takes < 5 minutes

---

## Quick Reference

### Common Commands Cheat Sheet

```bash
# ── Cluster Access ──
aws eks update-kubeconfig --name ecommerce-production --region us-east-1
kubectl config current-context
kubectl get nodes -o wide

# ── Service Status ──
kubectl get pods -n production
kubectl get svc -n production
kubectl top pods -n production

# ── ArgoCD ──
argocd app list
argocd app sync user-service
argocd app diff user-service

# ── Helm ──
helm list -n production
helm upgrade --install user-service ./helm -f helm/values/production.yaml -n production
helm rollback user-service 1 -n production

# ── Observability ──
kubectl port-forward svc/prometheus-grafana -n monitoring 3000:80           # Grafana
kubectl port-forward svc/prometheus-kube-prometheus-prometheus -n monitoring 9090:9090  # Prometheus
kubectl logs -l app=user-service -n production --tail=100 -f               # Logs

# ── Troubleshooting ──
kubectl describe pod <pod-name> -n production
kubectl logs <pod-name> -n production -c istio-proxy                       # Sidecar logs
kubectl get events -n production --sort-by='.lastTimestamp'

# ── Infrastructure ──
cd infrastructure/environments
terraform plan -var-file=production.tfvars
terraform apply -var-file=production.tfvars
terraform output

# ── Security ──
kubectl get constrainttemplates                                            # Gatekeeper policies
kubectl get networkpolicies -n production                                  # Network policies
kubectl exec -it vault-0 -n vault -- vault status                          # Vault status

# ── Cost ──
kubectl get provisioners                                                   # Karpenter
kubectl describe resourcequota -n ecommerce-prod                           # Resource quotas
kubectl port-forward svc/kubecost-cost-analyzer -n kubecost 9090:9090      # Kubecost

# ── Chaos ──
kubectl get chaosengine -n production                                      # Litmus experiments
kubectl get chaosresult -n production                                      # Experiment results

# ── Docker Compose (local dev) ──
docker compose -f docker-compose.dev.yml up -d
docker compose -f docker-compose.dev.yml ps
docker compose -f docker-compose.dev.yml logs -f user-service
docker compose -f docker-compose.dev.yml down
```

### Architecture Summary

```
Phase 1  → Git + commitlint + Husky
Phase 2  → 6 microservices + Docker Compose
Phase 3  → Multi-stage Dockerfile + distroless
Phase 4  → Terraform → VPC + EKS + Aurora + Redis
Phase 5  → GitHub Actions CI/CD + Trivy + OIDC
Phase 6  → Helm charts + HPA + PDB + probes
Phase 7  → ArgoCD + Kustomize + Image Updater
Phase 8  → Prometheus + Grafana + Loki + SLO rules
Phase 9  → Gatekeeper + Vault + Network Policies
Phase 10 → Litmus Chaos + AWS FIS
Phase 11 → Istio mTLS + Flagger canary
Phase 12 → Route 53 failover + Aurora Global + Velero
Phase 13 → Karpenter + Kubecost + ResourceQuotas
Phase 14 → Backstage + Crossplane self-service
```

### Key Metrics

| Metric | Target |
|--------|--------|
| Deployment frequency | 20+ deploys/day |
| Pipeline time | < 8 minutes |
| Availability SLO | 99.95% |
| mTLS coverage | 100% |
| Critical CVEs | 0 |
| Cost reduction | 40% |
| RPO / RTO | < 1 min / < 5 min |
| New service setup | 5 minutes (self-service) |

# EKS + Karpenter POC (x86 + Graviton, Spot-first)

Terraform that stands up a production-shaped **Amazon EKS** cluster in a
**dedicated VPC** and runs **Karpenter** for autoscaling, with NodePools that
provision **both x86 (amd64) and AWS Graviton (arm64)** instances, preferring
**Spot** with automatic **On-Demand** fallback.

- **Kubernetes:** 1.36 (latest on EKS as of June 2026)
- **Karpenter:** v1 (`NodePool` / `EC2NodeClass`)
- **Region:** `eu-west-1` (override with `var.region`)
- **Compute model:** a tiny on-demand managed node group bootstraps the cluster;
  Karpenter provisions everything else.

---

## Architecture

```
                          ┌─────────────────────────────────────────────┐
                          │              Dedicated VPC (/16)            │
                          │   3 AZs · per-AZ NAT · public+private nets  │
                          │                                             │
   ┌──────────┐   API     │   ┌──────────────┐     ┌───────────────────┐│
   │  kubectl │──────────►│   │ EKS control  │     │  Bootstrap MNG    ││
   │  / TF    │  (access  │   │   plane 1.36 │     │  2x on-demand x86 ││
   └──────────┘  entries) │   └──────┬───────┘     │  Karpenter+CoreDNS││
                          │          │             └───────────────────┘│
                          │          │ schedules                        │
                          │   ┌──────▼─────────────────────────────────┐│
                          │   │           Karpenter (v1)               ││
                          │   │  EC2NodeClass: AL2023, discovery tags  ││
                          │   │  NodePool amd64  │  NodePool arm64     ││
                          │   │  spot→on-demand  │  spot→on-demand     ││
                          │   └──────┬───────────────────┬─────────────┘│
                          │     launches            launches            │
                          │   ┌──────▼──────┐      ┌──────▼──────┐      │
                          │   │ x86 nodes   │      │ Graviton    │      │
                          │   │ (c/m/r 6+)  │      │ nodes (*g)  │      │
                          │   └─────────────┘      └─────────────┘      │
                          └─────────────────────────────────────────────┘
```

### File layout

| Path | Purpose |
|------|---------|
| `bootstrap/` | One-time module that creates the S3 state bucket (local state). |
| `vpc.tf` | Dedicated VPC, 3 AZs, per-AZ NAT, Karpenter subnet discovery tags. |
| `eks.tf` | EKS 1.36, access-entry auth, core add-ons, bootstrap managed node group. |
| `karpenter.tf` | Karpenter IAM/SQS/Pod-Identity (module) + Helm releases (CRDs + controller). |
| `nodepools.tf` | Deploys the `EC2NodeClass` + per-arch `NodePool`s (spot-first) via a local Helm chart. |
| `charts/karpenter-resources/` | Local Helm chart templating the Karpenter custom resources. |
| `examples/` | Developer-facing demo deployments (x86 / Graviton / multi-arch). |
| `providers.tf` `versions.tf` `variables.tf` `outputs.tf` | Wiring. |

---

## Prerequisites

- Terraform **>= 1.10** (for native S3 state locking)
- AWS CLI v2, authenticated to the target (test) account with permissions to
  create VPC/EKS/IAM/EC2 resources
- `kubectl` and `helm` available locally
- Service-linked roles for EKS / Spot exist in the account (created automatically
  on first use in most accounts)

---

## Usage

### 1. Create the state bucket (once)

```bash
cd bootstrap
terraform init
terraform apply -var="bucket_name=opsfleet-poc-tfstate-<ACCOUNT_ID>"
terraform output backend_config        # copy these values
```

### 2. Configure the backend

```bash
cd ..
cp backend.hcl.example backend.hcl     # paste the values from step 1
cp terraform.tfvars.example terraform.tfvars   # optional: tweak vars
```

> Using a named AWS CLI profile? Set `aws_profile = "your-profile"` in
> `terraform.tfvars` (or `-var aws_profile=...`). It is applied to both the AWS
> provider and the in-cluster `aws eks get-token` auth. Leave it unset to use
> the default credential chain (env vars / default profile).

### 3. Deploy the cluster

```bash
terraform init -backend-config=backend.hcl
terraform apply
```

`apply` takes ~15–20 min (most of it the EKS control plane). When it finishes:

```bash
$(terraform output -raw configure_kubectl)   # aws eks update-kubeconfig ...
# The karpenter.sh/nodepool column shows which pool a node belongs to;
# the bootstrap node shows role=bootstrap.
kubectl get nodes -L kubernetes.io/arch,karpenter.sh/capacity-type,karpenter.sh/nodepool,role
kubectl get nodepools,ec2nodeclasses
```

You should see the bootstrap node(s) and the Karpenter resources `Ready`. The
bootstrap node is tainted `dedicated=system`, so when you deploy the example
apps below, Karpenter launches separate nodes for them.

---

## Developer guide: run a pod on x86 or Graviton

A developer only needs **one line** - a `nodeSelector` on `kubernetes.io/arch`.
Karpenter watches for unschedulable pods, matches the right NodePool, and
launches a node on demand.

### Graviton (arm64)

```bash
kubectl apply -f examples/deployment-arm64.yaml
```

### x86 (amd64)

```bash
kubectl apply -f examples/deployment-amd64.yaml
```

### Let Karpenter choose the cheapest (multi-arch)

```bash
kubectl apply -f examples/deployment-multiarch.yaml
```

### Verify which architecture each pod landed on

```bash
kubectl get pods -o wide
# Map pods to node architecture:
kubectl get nodes -L kubernetes.io/arch,node.kubernetes.io/instance-type,karpenter.sh/capacity-type,karpenter.sh/nodepool
```

The minimal pattern inside any manifest:

```yaml
spec:
  nodeSelector:
    kubernetes.io/arch: arm64   # or amd64
```

> Tip: this same selector works for Pods, Deployments, StatefulSets, Jobs, etc.
> For multi-arch container images, no app changes are required to move a
> workload onto Graviton - only the selector.

---

## Cleanup

```bash
# Remove workloads first so Karpenter scales nodes back down.
kubectl delete -f examples/ --ignore-not-found

terraform destroy

# The state bucket is protected by prevent_destroy; remove that block in
# bootstrap/main.tf first if you really want to delete it, then:
#   cd bootstrap && terraform destroy
```

---

## Design decisions & rationale

### Why these choices
- **Community modules (`terraform-aws-modules/{vpc,eks}`)** - battle-tested,
  secure defaults, and the official Karpenter submodule wires up IAM, the SQS
  interruption queue, and Pod Identity correctly. Versions are pinned.
- **Access entries (API auth), not `aws-auth` ConfigMap** - the modern EKS auth
  mode; the Terraform runner gets cluster-admin via an access entry.
- **Bootstrap managed node group (tainted system-only)** - Karpenter can't run
  on nodes it hasn't created yet. A small on-demand group hosts Karpenter +
  CoreDNS; everything else is Karpenter-managed. (Fargate was rejected: x86-only
  and no DaemonSets, awkward for a Graviton showcase.) The group carries a
  `dedicated=system:NoSchedule` taint so **only system components run there** -
  Karpenter and CoreDNS get a matching toleration; the DaemonSet add-ons (VPC
  CNI, kube-proxy, pod-identity-agent) already tolerate all taints. Application
  pods have no toleration, so they can't land on the bootstrap nodes and instead
  force Karpenter to provision dedicated capacity. This cleanly separates
  "system" from "application" compute (and makes the amd64 NodePool actually
  provision nodes, rather than app pods piggy-backing on the bootstrap group).
- **Per-arch NodePools** - explicit and demonstrative; each arch gets its own
  limits/labels. A single multi-arch pool also works and is slightly less code.
- **Spot-first with On-Demand fallback** - both capacity types are allowed in
  each pool, so Karpenter uses price-capacity-optimized Spot and falls back to
  On-Demand when Spot is unavailable. **Requires the EC2 Spot service-linked
  role** (`spot.tf`); without it Karpenter silently runs everything On-Demand.
- **Node naming reflects the pool** - each pool has its own `EC2NodeClass`
  tagging instances `Name=<cluster>-karpenter-<arch>` (visible in the EC2
  console); in `kubectl`, the built-in `karpenter.sh/nodepool` label (`amd64` /
  `arm64`) and the bootstrap `role=bootstrap` label identify the group.
- **Modern instance families only** (`c/m/r`, generation > 5) - good
  price/performance and broad Spot availability across both architectures.
- **Per-AZ NAT + private subnets** - production-shaped HA. For a pure
  cost-optimized POC, set `single_nat_gateway = true` in `vpc.tf`.
- **S3 backend with native locking** (`use_lockfile`) - no DynamoDB table needed
  on Terraform >= 1.10.

### Test vs production sizing

To keep test runs cheap, the defaults are deliberately minimal. Bump these for
a production-shaped deployment:

Most of the gap is **just variable overrides** - see
`terraform.tfvars.production.example`:

| Variable | TEST default | Production suggestion |
|---|---|---|
| `bootstrap_instance_types` | `["t3.medium"]` | larger + multiple, e.g. `["m7i.large","m7g.large","m6i.large"]` |
| `bootstrap_scaling` | `1 / 1 / 2` | `3 / 3 / 6` (one node per AZ) |
| `karpenter_controller_cpu` / `_memory` | `500m` / `512Mi` | `1` / `1Gi` (Karpenter docs) |
| `nodepool_cpu_limit` / `nodepool_memory_limit` | `16` / `64Gi` | size to expected peak |
| `cluster_endpoint_public_access` (+ `_cidrs`) | `true` / `0.0.0.0/0` | `false` (private) or tightly restricted |

A few prod items are **code-level** (not variables) - illustrated in the
`*.production.example` overlay files:

- **`eks.production.example`** - control-plane logging (`enabled_log_types`),
  extra add-ons (metrics-server, EBS CSI, VPC CNI prefix delegation), HA CoreDNS.
- **`vpc.production.example`** - VPC flow logs + VPC endpoints (S3/ECR/STS/logs)
  to take traffic off the NAT gateways.

> The base `vpc.tf` is already prod-shaped (per-AZ NAT). For a cheaper *non-prod*
> environment, set `single_nat_gateway = true` in `vpc.tf` to save ~$75/mo.

### Pod Identity vs IRSA (workload identity)

This POC uses **EKS Pod Identity** for the Karpenter controller.

| | IRSA | **EKS Pod Identity (used here)** |
|---|------|------|
| Mechanism | Per-cluster OIDC provider + IAM trust policy on the SA `sub` | Pod Identity agent + an EKS association `(cluster, ns, SA) → role` |
| Trust policy | Verbose; role reuse across clusters is painful | Single `pods.eks.amazonaws.com` principal; roles reuse cleanly |
| Terraform UX | OIDC provider + hand-rolled trust JSON | `create_pod_identity_association = true` |
| Constraint | Works on Fargate | Needs the agent DaemonSet (not Fargate - irrelevant here) |

**Why Pod Identity:** less IAM boilerplate, scales across clusters, AWS's
strategic direction, and natively supported by the Karpenter module.

**Cloud-agnostic nuance:** neither mechanism is portable - both are AWS-specific
glue. But IRSA's *pattern* (a projected **OIDC token** exchanged for cloud
credentials) is exactly what **GKE Workload Identity Federation** and **Azure
Workload Identity** also do, so IRSA is conceptually closer to a cross-cloud
model. We chose Pod Identity for AWS cleanliness; switching to IRSA later only
changes the IAM wiring, not the developer-facing contract (pods get creds via an
annotated ServiceAccount, never static keys). To switch: set
`create_pod_identity_association = false`, enable the cluster OIDC provider, and
configure the Karpenter chart's `serviceAccount.annotations` with the role ARN.

### Cloud-agnostic notes (stated future goal)

- The stack is organized by concern (`vpc` / `eks` / `karpenter` / `nodepools`)
  so the AWS-specific pieces are isolated and swappable per cloud. We
  deliberately did **not** over-wrap the community modules in bespoke local
  modules - premature abstraction for a single-cloud POC.
- The **developer contract is already portable**: `kubernetes.io/arch`
  selectors, standard labels/taints, and multi-arch images work identically on
  GKE/AKS.
- **Karpenter is AWS-specific** (the `EC2NodeClass` CRD). There is no
  GCP/Azure provider for it today. The portable equivalents elsewhere are the
  Cluster Autoscaler or Cluster API. If true multi-cloud node autoscaling
  becomes a requirement, that's the abstraction boundary to plan around.

---

## Caveats / things to verify before "real" use

- **Versions are pinned to current majors** (AWS provider `~> 6.0`, EKS module
  `~> 21.0`, VPC module `~> 6.0`, Karpenter `1.13.0`). Confirm the latest patch
  versions against their docs/releases. Note the Karpenter ↔ Kubernetes
  compatibility matrix: K8s 1.36 requires Karpenter >= 1.12.
- **Public API endpoint is open (`0.0.0.0/0`)** for easy grading. Restrict
  `cluster_endpoint_public_access_cidrs` (or disable public access) for anything
  real.
- **Spot service-linked role:** `create_spot_service_linked_role = true` creates
  `AWSServiceRoleForEC2Spot`. If the role already exists in your account, apply
  fails with "has been taken" - set the variable to `false` (or
  `terraform import aws_iam_service_linked_role.spot[0] <arn>`). If nodes still
  come up On-Demand after the role exists, check your Spot vCPU quota or widen
  the NodePool instance families.
- **Single-state convenience trade-off:** the helm provider is configured from
  `module.eks` outputs. This is the common community pattern and works for a
  fresh `apply`, but HashiCorp recommends splitting cluster and in-cluster
  resources into separate states for production. (The Karpenter CRs are
  delivered via a local Helm chart.) For destroy, delete workloads first (see
  Cleanup) so Karpenter scales in before the cluster goes away.
- This is a **POC**: no logging/monitoring stack, no PDBs, no network policies,
  no quotas. Production hardening (control-plane logs to CloudWatch, GuardDuty,
  OPA/Kyverno, PDBs, resource quotas) is intentionally out of scope.
- Run `terraform fmt -recursive` and `terraform validate` before committing.

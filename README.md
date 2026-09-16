# Phoenix Capstone — TaskApp on Kubernetes

A production-style deployment of **TaskApp** on a real, multi-node **K3s Kubernetes cluster** running on AWS EC2.

The project extends the original Docker/Portainer deployment into a Kubernetes environment with multi-node scheduling, persistent PostgreSQL storage, horizontal scaling, TLS, GitOps deployment with Argo CD, PodDisruptionBudgets, NetworkPolicy, zero-downtime rolling updates, and live worker-node failover.

## Project Overview

TaskApp consists of:

* React/Nginx frontend
* Flask backend
* PostgreSQL database

The application is deployed across three AWS EC2 instances:

```text
Control plane: ip-172-31-1-100
Worker 1:      ip-172-31-1-169
Worker 2:      ip-172-31-1-215
```

All three nodes run K3s.

The live application is available over HTTPS at:

https://taskapp.3.238.205.127.nip.io

## Architecture

```text
                           Internet
                               |
                               | HTTPS
                               v
              taskapp.3.238.205.127.nip.io
                               |
                               v
                    +----------------------+
                    | K3s Traefik Ingress  |
                    | Let's Encrypt TLS    |
                    +----------+-----------+
                               |
                    +----------+----------+
                    |                     |
                  "/"                   "/api"
                    |                     |
                    v                     v
             Frontend Service       Backend Service
                    |                     |
              +-----+-----+         +-----+-----+
              |           |         |           |
              v           v         v           v
          Frontend    Frontend   Backend     Backend
             Pod         Pod        Pod         Pod
                    \               /
                     \             /
                      +-----------+
                            |
                            v
                     PostgreSQL Service
                            |
                            v
                       postgres-0
                            |
                            v
                           PVC
```

### Request flow

1. A client resolves the `nip.io` hostname.
2. HTTPS traffic reaches the K3s Traefik Ingress.
3. cert-manager manages the Let's Encrypt certificate.
4. Requests to `/` are routed to the frontend Service.
5. Requests to `/api` are routed to the backend Service.
6. The backend connects to PostgreSQL through the `postgres` Service.
7. PostgreSQL stores application data on a persistent volume.

## Kubernetes Components

### Application

| Component             | Kubernetes resource         | Configuration                              |
| --------------------- | --------------------------- | ------------------------------------------ |
| Frontend              | Deployment                  | 2 replicas                                 |
| Backend               | Deployment                  | 2+ replicas with HPA                       |
| PostgreSQL            | StatefulSet                 | Persistent storage                         |
| Migration             | Job                         | Separate from running application replicas |
| Frontend networking   | Service                     | ClusterIP                                  |
| Backend networking    | Service                     | ClusterIP                                  |
| PostgreSQL networking | Headless Service            | ClusterIP                                  |
| External routing      | Ingress                     | Traefik                                    |
| TLS                   | Certificate / ClusterIssuer | Let's Encrypt                              |

### Core Kubernetes capabilities

The deployment includes:

* Dedicated `taskapp` namespace.
* Kubernetes Secret for sensitive backend values.
* PostgreSQL StatefulSet with persistent storage through a PVC.
* Backend and frontend Deployments with multiple replicas.
* `topologySpreadConstraints` to distribute replicas across nodes.
* Dedicated migration Job rather than running migrations in application replicas.
* Liveness, readiness and startup probes where supported by the workloads.
* CPU and memory resource requests and limits.
* Rolling updates with `maxUnavailable: 0`.
* Pinned container image tags rather than `:latest`.
* Traefik Ingress with publicly trusted Let's Encrypt TLS.
* K3s multi-node scheduling and automatic Pod rescheduling.

## Advanced Kubernetes Features

Three Advanced requirements were implemented.

### 1. Horizontal Pod Autoscaler

The backend uses an HPA to scale according to CPU utilization.

The configured range is:

```text
Minimum replicas: 2
Maximum replicas: 4
Target CPU:       70%
```

The HPA was demonstrated under load and the backend scaled beyond its initial replica count.

Evidence:

```text
docs/EVIDENCE/hpa-scale.png
```

### 2. PodDisruptionBudget and graceful shutdown

Backend and frontend workloads have PodDisruptionBudgets with:

```text
minAvailable: 1
```

The Deployments also use graceful termination settings and multiple replicas so voluntary disruptions can occur without taking the application completely offline.

Evidence of the live worker-drain test:

```text
docs/EVIDENCE/failover.png
```

### 3. NetworkPolicy

The `taskapp` namespace uses Kubernetes NetworkPolicy resources with a default-deny policy and explicit traffic allowances.

The policies permit only the application flows that are required:

```text
Traefik       → Frontend
Traefik       → Backend
Frontend      → Backend
Backend       → PostgreSQL
Migration Job → PostgreSQL
TaskApp       → CoreDNS
Traefik       → cert-manager HTTP-01 solver
```

NetworkPolicy resources are managed through GitOps.

Evidence:

```text
docs/EVIDENCE/networkpolicy-argocd.png
```

## GitOps with Argo CD

Argo CD manages the final application state.

The Git repository is:

```text
https://github.com/Programmedartemis/capstone-phoenix
```

The application manifests are stored under:

```text
manifests/
```

Argo CD watches the `main` branch and automatically reconciles the desired state.

The Argo CD Application is configured with automated synchronization, pruning and self-healing.

The final cluster state was verified as:

```text
SYNC STATUS   HEALTH STATUS
Synced        Healthy
```

Evidence:

```text
docs/EVIDENCE/argocd-synced.png
```

## High Availability and Failover

The cluster contains one K3s control plane and two workers.

Backend and frontend replicas are distributed across different nodes. During the live failover test, worker `ip-172-31-1-169` was drained:

```bash
sudo k3s kubectl drain ip-172-31-1-169 \
  --ignore-daemonsets \
  --delete-emptydir-data
```

The application Pods were rescheduled onto a healthy worker while the application continued responding.

After the test, the worker was returned to service:

```bash
sudo k3s kubectl uncordon ip-172-31-1-169
```

All three nodes returned to `Ready`.

Evidence:

```text
docs/EVIDENCE/failover.png
```

## Persistence

PostgreSQL runs as a StatefulSet and uses a PersistentVolumeClaim.

The project tested persistence by deleting the PostgreSQL Pod and verifying that the stored test data remained available after the Pod was recreated.

Evidence:

```text
docs/EVIDENCE/pvc-persist.log
```

## Zero-Downtime Deployment

The backend and frontend Deployments use:

```yaml
strategy:
  type: RollingUpdate
  rollingUpdate:
    maxUnavailable: 0
```

A rolling update was performed while continuously checking the application health endpoint. HTTP 200 responses continued throughout the deployment.

Evidence:

```text
docs/EVIDENCE/zero-downtime.log
```

## TLS and Live Application

TLS is provided by cert-manager and Let's Encrypt through the K3s Traefik Ingress.

Live application:

https://taskapp.3.238.205.127.nip.io

Evidence:

```text
docs/EVIDENCE/tls-valid.png
docs/EVIDENCE/live-app-https.png
```

## Evidence

The main project evidence is stored in:

```text
docs/EVIDENCE/
```

| Evidence                   | Purpose                                       |
| -------------------------- | --------------------------------------------- |
| `nodes-ready.png`          | Three-node Kubernetes cluster                 |
| `pods-spread.png`          | Backend/frontend replicas spread across nodes |
| `tls-valid.png`            | Valid public TLS certificate                  |
| `live-app-https.png`       | Application running over HTTPS                |
| `pvc-persist.log`          | PostgreSQL persistence after Pod deletion     |
| `zero-downtime.log`        | Continuous HTTP 200 responses during rollout  |
| `hpa-scale.png`            | HPA scaling demonstration                     |
| `argocd-synced.png`        | Argo CD Synced + Healthy                      |
| `failover.png`             | Worker drain and Pod rescheduling             |
| `networkpolicy-argocd.png` | NetworkPolicy and Argo CD evidence            |

Additional supporting evidence is also retained in the directory.

## Repository Structure

```text
capstone-phoenix/
├── docs/
│   ├── ARCHITECTURE.md
│   ├── RUNBOOK.md
│   ├── COST.md
│   └── EVIDENCE/
├── gitops/
├── infra/
│   ├── terraform/
│   └── ansible/
├── manifests/
│   ├── backend.yaml
│   ├── frontend.yaml
│   ├── postgres.yaml
│   ├── migration-job.yaml
│   ├── hpa.yaml
│   ├── ingress.yaml
│   ├── pdb.yaml
│   └── networkpolicy.yaml
├── .gitignore
├── README.md
└── STRUCTURE.md
```

## Security and Git Hygiene

The project follows the capstone security constraints:

* No `:latest` images.
* Kubernetes API port `6443` is not open to the public internet.
* SSH access is restricted to the administrator's public IP.
* Sensitive values are stored in Kubernetes Secrets rather than committed as plaintext.
* Terraform state is stored remotely.
* `.gitignore` excludes Terraform state, kubeconfig and environment files.
* The final application state is managed by Argo CD rather than maintained through repeated manual `kubectl apply` commands.
* The cluster uses a non-root Ubuntu SSH account rather than root SSH access.

## Documentation

Detailed operational documentation is available in:

```text
docs/ARCHITECTURE.md
docs/RUNBOOK.md
docs/COST.md
```

`ARCHITECTURE.md` documents the topology, request flow, Kubernetes design decisions and single-server assumptions that were addressed.

`RUNBOOK.md` provides provisioning, deployment, scaling, rollback and failure-recovery procedures.

`COST.md` provides an estimated monthly AWS infrastructure cost and cost-reduction approach.

## Key Technologies

```text
AWS EC2
Terraform
Ansible
K3s
Kubernetes
Traefik
cert-manager
Let's Encrypt
PostgreSQL
Docker / GHCR
Argo CD
HPA
PodDisruptionBudget
NetworkPolicy
Git / GitHub
```

## Repository

GitHub:

https://github.com/Programmedartemis/capstone-phoenix

## Project Outcome

This project demonstrates the transition from a single-server container deployment to a real multi-node Kubernetes environment with:

* persistent application storage
* multiple application replicas
* automated scaling
* controlled rolling deployments
* HTTPS
* GitOps reconciliation
* network isolation
* workload disruption protection
* worker-node failover and recovery
* documented operational procedures

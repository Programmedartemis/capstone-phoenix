# Phoenix Capstone Architecture

## 1. Topology diagram

```text
                              Internet
                                  |
                                  | HTTPS
                                  v
                     taskapp.3.238.205.127.nip.io
                                  |
                                  v
                     +-------------------------+
                     | k3s Traefik Ingress     |
                     | TLS / Let's Encrypt     |
                     +-----------+-------------+
                                 |
                    +------------+------------+
                    |                         |
                 "/"                       "/api"
                    |                         |
                    v                         v
          +------------------+      +------------------+
          | Frontend Service |      | Backend Service  |
          +--------+---------+      +--------+---------+
                   |                         |
             +-----+-----+             +-----+-----+
             |           |             |           |
             v           v             v           v
        Frontend      Frontend     Backend      Backend
          Pod           Pod          Pod          Pod
        control       worker-1     control      worker-2
          plane                    plane

                                      |
                                      | PostgreSQL
                                      v
                             +----------------+
                             | Postgres       |
                             | StatefulSet    |
                             | postgres-0     |
                             +-------+--------+
                                     |
                                     v
                              PersistentVolume
                                  / PVC
```

### Current cluster nodes

| Node              | Role          | Private IP     | Instance       |
| ----------------- | ------------- | -------------- | -------------- |
| `ip-172-31-1-100` | Control plane | `172.31.1.100` | AWS `t3.micro` |
| `ip-172-31-1-169` | Worker        | `172.31.1.169` | AWS `t3.micro` |
| `ip-172-31-1-215` | Worker        | `172.31.1.215` | AWS `t3.micro` |

Region: `us-east-1`

The control plane currently exposes the public application through HTTPS on port 443. Kubernetes API access on port 6443 is restricted and is not exposed to the world.

## 2. Node & network

The cluster contains one K3s control-plane node and two separate worker nodes. All three nodes run Ubuntu and K3s.

TaskApp workloads are placed across the nodes using Kubernetes scheduling constraints. Backend and frontend Deployments each run two replicas and use `topologySpreadConstraints` so replicas are distributed across different nodes.

The AWS security group allows:

* TCP 22 only from the administrator's allowed public IP.
* TCP 80 and 443 from the internet for the application and ACME HTTP validation.
* Internal Kubernetes/node traffic between the cluster nodes as required.

TCP 6443 is not open to `0.0.0.0/0`. Kubernetes API access is therefore not publicly exposed.

The application uses the same-origin design rather than separate frontend and API hostnames:

```text
https://taskapp.3.238.205.127.nip.io/
https://taskapp.3.238.205.127.nip.io/api/...
```

This keeps browser traffic on one HTTPS hostname while the Ingress routes `/api` to the backend Service.

## 3. Request flow

A browser resolves `taskapp.3.238.205.127.nip.io` and connects over HTTPS to the public application endpoint. The K3s Traefik Ingress receives the request and uses the Let's Encrypt certificate managed by cert-manager to terminate TLS. Requests for `/` are routed to the frontend Service, which distributes traffic to the frontend Pods. Requests under `/api` are routed to the backend Service, which distributes traffic across the backend replicas. The backend connects to the `postgres` Service on port 5432, which targets the PostgreSQL StatefulSet. PostgreSQL stores its data on a Kubernetes PersistentVolume backed by the cluster's local storage provisioner.

## 4. The single-server assumptions fixed

| Single-server assumption                                 | Why it breaks in a cluster                                                               | Kubernetes mechanism used                                                                        |
| -------------------------------------------------------- | ---------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------ |
| Migrations run during application startup                | Two or more backend replicas can run `alembic upgrade head` at the same time             | A separate Kubernetes migration Job runs before/alongside application deployment                 |
| A host-local named volume is enough                      | A Pod may restart on another node and lose local container state                         | PostgreSQL StatefulSet + PVC provides persistent storage                                         |
| Host ports provide the public entry point                | Multiple replicas and multiple nodes cannot safely own the same host port                | Kubernetes Services + Traefik Ingress provide one front door                                     |
| One process restarting is enough for recovery            | A failed Pod needs to be recreated automatically                                         | Deployments and StatefulSets provide controller-based self-healing                               |
| A deployment can briefly remove capacity                 | Removing an old replica first can cause dropped requests                                 | `RollingUpdate` with `maxUnavailable: 0`                                                         |
| Two replicas can be placed anywhere                      | Both replicas could land on the same node and fail together                              | `topologySpreadConstraints` across Kubernetes hostnames                                          |
| Secrets can live in a local `.env` file                  | Cluster workloads need centrally managed credentials without committing passwords to Git | Kubernetes Secret supplied out-of-band and referenced by the backend                             |
| A single machine drain is dangerous                      | Evicting Pods could interrupt the application                                            | PodDisruptionBudgets, multiple replicas, graceful termination, readiness probes and rescheduling |
| Manual `kubectl apply` is the final deployment mechanism | Manual changes can drift from the repository                                             | Argo CD continuously reconciles the Git repository                                               |

## 5. Choices & trade-offs

### Raw YAML vs Helm vs Kustomize

Raw Kubernetes YAML was selected because this capstone is primarily demonstrating Kubernetes fundamentals and GitOps. The manifests are explicit and easy to inspect during assessment. Helm or Kustomize would provide better reuse for larger environments, but would add abstraction that is not necessary for this project.

### Ingress-nginx vs K3s Traefik

The cluster uses the Traefik Ingress controller that ships with K3s. Traefik was selected because it is already integrated into the K3s distribution, reducing the number of additional components that need to be installed and maintained. It provides the HTTP/HTTPS routing required by TaskApp and works with cert-manager for automated Let's Encrypt TLS certificates.

Using the built-in Traefik controller also keeps the architecture lightweight and avoids running a separate ingress-nginx installation for this capstone. The trade-off is that the project is more closely aligned with the K3s ecosystem, whereas ingress-nginx may be preferred in environments where nginx-specific configuration or an existing organizational standard is required.

### Secrets approach

Sensitive values such as database credentials and the application's `SECRET_KEY` are stored in a Kubernetes Secret created out-of-band. The plaintext secret is not committed to the Git repository. The backend Deployment references the Secret using `secretKeyRef`.

### GitOps

Argo CD is installed in the `argocd` namespace. The `taskapp` Argo CD Application points to:

```text
https://github.com/Programmedartemis/capstone-phoenix.git
```

and the `manifests/` directory on the `main` branch.

Automated synchronization is enabled with:

```yaml
automated:
  prune: true
  selfHeal: true
```

The live TaskApp application has been verified as `Synced` and `Healthy`.

### NetworkPolicy

NetworkPolicy is implemented in the `taskapp` namespace using Kubernetes NetworkPolicy resources enforced by the K3s networking stack. A default-deny policy restricts unsolicited ingress and egress, while additional policies explicitly allow the traffic required by the application:

* Traefik → frontend
* Traefik/frontend → backend
* backend and migration Job → PostgreSQL
* TaskApp workloads → CoreDNS
* Traefik → cert-manager HTTP-01 solver when required

This provides namespace-level traffic isolation while allowing the required application, database, DNS, and certificate-validation flows.

### Resource hardening

Resource hardening was evaluated as an Advanced option but was not included in the final deployed configuration. The backend image already runs as a non-root `appuser`, while the existing frontend image uses an Nginx master process running as root. Because the frontend image source is not part of this repository, forcing `runAsNonRoot` could break the working application. The project therefore does not claim resource hardening as one of its completed Advanced features.

### Selected Advanced features

The three Advanced features implemented for the distinction requirement are:

1. **Horizontal Pod Autoscaler (HPA)** — the backend automatically scales between two and four replicas based on CPU utilization and was demonstrated under load.
2. **PodDisruptionBudget and graceful shutdown** — backend and frontend workloads have PodDisruptionBudgets, multiple replicas, readiness checks, and graceful termination settings to support safe node disruption and rolling operations.
3. **NetworkPolicy** — namespace traffic is default-denied and explicitly permitted only for the required frontend, backend, PostgreSQL, DNS, ingress, migration, and certificate-validation paths.

## 6. Resilience and operational evidence

The deployed cluster was tested for:

* Multi-node scheduling across three K3s nodes.
* TLS using a publicly trusted Let's Encrypt certificate.
* PostgreSQL data persistence after deleting and recreating `postgres-0`.
* Backend HPA scaling from two to four replicas under CPU load.
* Zero-downtime backend rollout with continuous HTTP 200 health responses.
* Worker-node drain and Pod rescheduling while the application continued responding.
* PodDisruptionBudgets for backend and frontend workloads.
- NetworkPolicy traffic isolation was configured and managed through GitOps.

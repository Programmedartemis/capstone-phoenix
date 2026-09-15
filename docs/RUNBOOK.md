# Phoenix Capstone Runbook

## 1. Provision from zero

### 1.1 Provision AWS infrastructure

From the project root:

```bash
cd infra/terraform
terraform init
terraform validate
terraform plan
terraform apply
```

Review the plan before confirming the apply.

After provisioning, retrieve the Terraform outputs:

```bash
terraform output
```

The outputs provide the public IP addresses required for SSH access and the private addresses used by the Kubernetes cluster.

Do not commit Terraform state files:

```text
*.tfstate
*.tfstate.*
```

### 1.2 Configure the Ansible inventory

Update:

```text
infra/ansible/inventory
```

with the current control-plane and worker IP addresses from Terraform.

Run the Ansible playbook:

```bash
cd ../ansible
ansible-playbook -i inventory site.yml
```

This configures the Ubuntu nodes and installs/configures K3s.

### 1.3 Verify the Kubernetes cluster

Connect to the control-plane node:

```bash
ssh -i ~/.ssh/phoenix-capstone ubuntu@<CONTROL_PLANE_PUBLIC_IP>
```

Verify the cluster:

```bash
sudo k3s kubectl get nodes
```

Expected result:

```text
control-plane   Ready
worker-1        Ready
worker-2        Ready
```

### 1.4 Install the platform components

The cluster uses K3s Traefik as the ingress controller.

Install cert-manager using the project manifests or the documented cert-manager installation method, then verify:

```bash
sudo k3s kubectl get pods -n cert-manager
```

Verify the metrics server:

```bash
sudo k3s kubectl get deployment metrics-server -n kube-system
```

Install Argo CD:

```bash
sudo k3s kubectl create namespace argocd
sudo k3s kubectl apply -n argocd \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/v2.10.0/manifests/install.yaml
```

Verify:

```bash
sudo k3s kubectl get pods -n argocd
```

All Argo CD components should reach `Running`.

### 1.5 Create the Argo CD Application

The desired TaskApp state is stored in:

```text
gitops/taskapp-application.yaml
```

The Application points to:

```text
https://github.com/Programmedartemis/capstone-phoenix.git
```

and:

```text
path: manifests
targetRevision: main
```

The initial Application resource may be created once with:

```bash
sudo k3s kubectl apply -f /home/ubuntu/taskapp-application.yaml
```

After that, Argo CD owns the application manifests. Do not use manual `kubectl apply` to maintain the final application state.

Verify:

```bash
sudo k3s kubectl get application taskapp -n argocd
```

Expected:

```text
SYNC STATUS   HEALTH STATUS
Synced        Healthy
```

---

## 2. Day-2 operations

### 2.1 Scale a tier

The preferred method is to change the desired state in Git and allow Argo CD to reconcile it.

For example, change the backend replica count in:

```text
manifests/backend.yaml
```

Commit and push:

```bash
git add manifests/backend.yaml
git commit -m "Scale backend replicas"
git push origin main
```

Then verify:

```bash
sudo k3s kubectl get pods -n taskapp -l app=backend -o wide
```

For temporary troubleshooting only, Kubernetes can be inspected directly. Permanent application changes should be committed to Git so Argo CD remains the source of truth.

### 2.2 Roll back a bad deployment

First inspect the Deployment:

```bash
sudo k3s kubectl rollout history deployment/backend -n taskapp
```

For an emergency rollback:

```bash
sudo k3s kubectl rollout undo deployment/backend -n taskapp
```

Verify:

```bash
sudo k3s kubectl rollout status deployment/backend -n taskapp
```

Then determine the correct Git revision and update the repository so that Git and the cluster return to the same desired state.

### 2.3 Run a new migration safely

Migrations are handled by the dedicated migration Job rather than by each running backend replica.

Inspect the current Job:

```bash
sudo k3s kubectl get jobs -n taskapp
```

Inspect migration output:

```bash
sudo k3s kubectl logs job/backend-migration -n taskapp
```

For a new application release, update the image tag in Git and allow Argo CD to deploy the change. Confirm that the migration Job completes before considering the deployment successful:

```bash
sudo k3s kubectl get jobs -n taskapp
```

Expected:

```text
COMPLETIONS
1/1
```

### 2.4 Rotate a secret

The backend credentials are stored in the Kubernetes Secret:

```text
backend-secret
```

Inspect the Secret metadata without displaying its contents:

```bash
sudo k3s kubectl get secret backend-secret -n taskapp
```

Create/update the Secret out-of-band with the new values, then restart the backend Deployment so new Pods receive the updated environment:

```bash
sudo k3s kubectl rollout restart deployment/backend -n taskapp
```

Verify:

```bash
sudo k3s kubectl rollout status deployment/backend -n taskapp
```

Never commit plaintext passwords or secret keys to Git.

---

## 3. Failure recovery

### 3.1 Worker node dies or is drained

Kubernetes automatically reschedules eligible Deployment Pods onto healthy nodes.

To intentionally drain a worker for maintenance:

```bash
sudo k3s kubectl drain <NODE_NAME> \
  --ignore-daemonsets \
  --delete-emptydir-data
```

Check the rescheduled application Pods:

```bash
sudo k3s kubectl get pods -n taskapp -o wide
```

Confirm the application remains healthy:

```bash
curl -s https://taskapp.3.238.205.127.nip.io/api/health
```

Expected:

```json
{"database":"connected","status":"healthy"}
```

After maintenance, return the node to scheduling:

```bash
sudo k3s kubectl uncordon <NODE_NAME>
```

Verify:

```bash
sudo k3s kubectl get nodes
```

Expected state:

```text
Ready
```

The live failover demonstration used:

```text
ip-172-31-1-169
```

and the TaskApp frontend/backend Pods were rescheduled successfully while health checks continued returning HTTP 200.

### 3.2 Backend Pod crashloops

Inspect the Pods:

```bash
sudo k3s kubectl get pods -n taskapp -l app=backend
```

Inspect the failing Pod:

```bash
sudo k3s kubectl describe pod <POD_NAME> -n taskapp
```

Inspect current logs:

```bash
sudo k3s kubectl logs <POD_NAME> -n taskapp
```

If the container restarted, inspect the previous container:

```bash
sudo k3s kubectl logs <POD_NAME> -n taskapp --previous
```

Inspect recent events:

```bash
sudo k3s kubectl get events -n taskapp --sort-by=.lastTimestamp
```

After correcting the Git-managed configuration or image, allow Argo CD to reconcile the Deployment and verify:

```bash
sudo k3s kubectl rollout status deployment/backend -n taskapp
```

### 3.3 Bad migration

First inspect the migration Job:

```bash
sudo k3s kubectl get jobs -n taskapp
sudo k3s kubectl logs job/backend-migration -n taskapp
```

Do not repeatedly run migrations from individual backend replicas.

If the migration must be corrected, restore the application to the last known-good Git revision and allow Argo CD to reconcile it.

For database-level recovery, use the PostgreSQL backup/restore procedure documented for the environment. No automated backup system is part of this capstone configuration.

### 3.4 PostgreSQL Pod is rescheduled

Check the StatefulSet and Pod:

```bash
sudo k3s kubectl get statefulset postgres -n taskapp
sudo k3s kubectl get pod postgres-0 -n taskapp -o wide
```

Check the PVC:

```bash
sudo k3s kubectl get pvc -n taskapp
```

After the Pod becomes `Running`, verify database connectivity:

```bash
sudo k3s kubectl exec -n taskapp postgres-0 -- \
  psql -U taskapp -d taskapp -c "SELECT 1;"
```

For the persistence test used in this project, verify the test record:

```bash
sudo k3s kubectl exec -n taskapp postgres-0 -- \
  psql -U taskapp -d taskapp -c "SELECT * FROM pvc_test;"
```

The `phoenix-pvc-test` record remained available after deleting and recreating `postgres-0`, demonstrating persistence through the PVC.

---

## 4. Argo CD operations

Check application status:

```bash
sudo k3s kubectl get application taskapp -n argocd
```

Inspect the resources tracked by Argo CD:

```bash
sudo k3s kubectl -n argocd get application taskapp \
  -o jsonpath='{range .status.resources[*]}{.kind}{"\t"}{.name}{"\t"}{.status}{"\n"}{end}'
```

The final application state should show:

```text
Synced
Healthy
```

For normal changes:

```bash
git add .
git commit -m "Describe the change"
git push origin main
```

Then allow Argo CD automated synchronization and self-healing to reconcile the cluster.

---

## 5. Evidence produced for the capstone

The project evidence directory contains demonstrations for:

```text
docs/EVIDENCE/
```

Important evidence includes:

* `nodes-ready.png` — multi-node cluster
* `pods-spread.png` — workload distribution
* `tls-valid.png` — valid public TLS certificate
* `live-app-https.png` — live application over HTTPS
* `pvc-persist.log` — PostgreSQL data survives Pod deletion
* `zero-downtime.log` — uninterrupted HTTP 200 responses during rollout
* `hpa-scale.png` — HPA scaling under load
* `argocd-synced.png` — Argo CD Synced + Healthy
* `failover.png` — live worker drain and workload rescheduling

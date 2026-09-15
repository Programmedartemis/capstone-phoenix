# Phoenix Capstone Cost

## Monthly itemized cost

The Phoenix Capstone runs in AWS `us-east-1` using three `t3.micro` EC2 instances: one control plane and two workers. The figures below are estimated On-Demand costs for a 30-day month running continuously. Actual billing can differ because of AWS Free Tier eligibility, taxes, data transfer, usage, and account-specific pricing.

| Item                          | Specification                         | Qty |    Estimated $/mo |
| ----------------------------- | ------------------------------------- | --: | ----------------: |
| Control-plane VM              | EC2 `t3.micro`                        |   1 |             $7.59 |
| Worker VMs                    | EC2 `t3.micro`                        |   2 |            $15.18 |
| Public IPv4 addresses         | One per EC2 instance                  |   3 |            $10.95 |
| Block storage                 | 20 GiB gp3 per EC2 instance           |   3 |             $4.80 |
| S3 Terraform state            | Small state bucket, low usage         |   1 |            ~$0.01 |
| DynamoDB Terraform lock table | On-demand, very low usage             |   1 |            ~$0.01 |
| DNS/domain                    | nip.io                                |   1 |                $0 |
| Load balancer                 | None; K3s Traefik runs on the cluster |   — |                $0 |
| **Estimated total**           |                                       |     | **~$38.54/month** |

The EC2 estimate uses the current `t3.micro` On-Demand price of $0.0104/hour in US East (N. Virginia).

The gp3 estimate uses $0.08 per GB-month. The three 20 GiB volumes therefore represent approximately 60 GiB of provisioned storage, or $4.80/month.

AWS currently charges $0.005 per hour for each in-use public IPv4 address. Three continuously running public IPv4 addresses therefore represent approximately $10.95/month.

The S3 and DynamoDB amounts are expected to remain very small for this capstone because the Terraform state and lock table contain little data and experience very little request traffic. S3 Standard storage in US East is approximately $0.023/GB-month, while DynamoDB on-demand charges according to the requests consumed.

These figures exclude applicable taxes, unusual data-transfer usage, and any AWS Free Tier credits.

## Compared to the single-server Compose + Portainer deployment

A comparable single-server deployment using one `t3.micro`, one 20 GiB gp3 volume, and one public IPv4 address would be approximately:

```text
EC2:       ~$7.59/month
IPv4:      ~$3.65/month
EBS:       ~$1.60/month
--------------------------------
Estimate:  ~$12.84/month
```

The three-node Kubernetes cluster therefore costs roughly three times as much in basic compute, public IPv4, and block-storage resources.

The additional cost buys capabilities that a single-server Compose deployment does not provide as cleanly: multiple Kubernetes nodes, workload scheduling across nodes, automatic Pod rescheduling, horizontal scaling, rolling updates with `maxUnavailable: 0`, persistent storage through a StatefulSet and PVC, PodDisruptionBudgets, and GitOps reconciliation through Argo CD.

The extra cost is justified when availability, controlled deployments, workload recovery, and cluster-level orchestration matter. It is not justified for a very small application where a single machine can tolerate downtime and the priority is the lowest possible monthly infrastructure cost.

## How I would halve this cost

For a learning or low-traffic environment, I would first avoid running all three nodes continuously. Development and demonstration environments can be stopped when not in use, while production-like demonstrations can be brought up only when required. I would also minimize public IPv4 usage where the architecture permits IPv6, and right-size storage and compute according to actual workload. For a continuously running production environment, sustained workloads could be evaluated for reserved pricing, but that introduces a commitment that is unnecessary for this short-lived capstone. The biggest saving for this project would come from reducing always-on infrastructure rather than adding more managed services.

## Cost-control notes

* The project intentionally uses K3s rather than a managed Kubernetes control plane, avoiding an additional managed-control-plane charge.
* The project uses Traefik on the existing nodes instead of provisioning a separate AWS load balancer.
* The project uses `nip.io` for the demonstration hostname, so no paid domain registration is included.
* Terraform state uses S3 and a DynamoDB lock table; these are small, low-traffic resources.
* The PostgreSQL PVC uses the cluster's existing node storage setup rather than a separately provisioned managed database.
* No bonus infrastructure such as managed PostgreSQL, automated backups to additional object storage, or observability SaaS services is included.

The figures in this document are estimates rather than a substitute for the AWS billing console or AWS Pricing Calculator. AWS notes that calculator estimates depend on the usage assumptions supplied.

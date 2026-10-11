# DevOps Assignment

**Name:** Vansh Srivastava
**Enrollment No.:** 24bcs10567
**GitHub:** [vanshhhhhhhhh](https://github.com/vanshhhhhhhhh)

[![Session 16 - CI/CD Pipeline](https://github.com/vanshhhhhhhhh/DevOPS-ASSIGNMENT-VANSH-SRIVASTAVA/actions/workflows/session-16-cicd.yml/badge.svg)](https://github.com/vanshhhhhhhhh/DevOPS-ASSIGNMENT-VANSH-SRIVASTAVA/actions/workflows/session-16-cicd.yml)
[![Session 17 - DevSecOps Pipeline](https://github.com/vanshhhhhhhhh/DevOPS-ASSIGNMENT-VANSH-SRIVASTAVA/actions/workflows/session-17-devsecops.yml/badge.svg)](https://github.com/vanshhhhhhhhh/DevOPS-ASSIGNMENT-VANSH-SRIVASTAVA/actions/workflows/session-17-devsecops.yml)
[![Final Project - CI/CD](https://github.com/vanshhhhhhhhh/DevOPS-ASSIGNMENT-VANSH-SRIVASTAVA/actions/workflows/final-project.yml/badge.svg)](https://github.com/vanshhhhhhhhh/DevOPS-ASSIGNMENT-VANSH-SRIVASTAVA/actions/workflows/final-project.yml)

My solutions to the DevOps homework (Sessions 01 to 21). The tasks come from the course's "DevOps Homework" document, and the starter files from the instructor's repo [Nency-Ravaliya/devops-heros](https://github.com/Nency-Ravaliya/devops-heros). Every session has its own folder. Each folder's README covers the tasks in the order of the brief: the files, the commands I ran, the real output, and what I observed.

## Sessions

| Session | Topic | Folder |
| --- | --- | --- |
| 01 & 02 | Linux fundamentals: soft vs hard links, adduser vs useradd, journalctl, command cheat sheet | [session-01-02-linux-fundamentals](session-01-02-linux-fundamentals/) |
| 03 | Shell scripting: system information script | [session-03-shell-scripting](session-03-shell-scripting/) |
| 04 | Networking fundamentals: commands, outputs and notes | [session-04-networking-fundamentals](session-04-networking-fundamentals/) |
| 05 | Git and GitHub: `commit -a -m` vs `commit -m`, cherry-pick | [session-05-git-github](session-05-git-github/) |
| 06 | Docker fundamentals: Hello World in Node.js, Python, Java, Apache, React, Nginx | [session-06-docker-fundamentals](session-06-docker-fundamentals/) |
| 07 | Dockerfiles and images: multi-stage builds, single vs multi-stage image sizes | [session-07-dockerfiles-images](session-07-dockerfiles-images/) |
| 08 | Docker networking and volumes: multi-network app, host network, bind mount, overlay | [session-08-docker-networking-volumes](session-08-docker-networking-volumes/) |
| 09 | Kubernetes fundamentals: Minikube, architecture, Kubernetes Basics tutorial | [session-09-kubernetes-fundamentals](session-09-kubernetes-fundamentals/) |
| 10 | Pods, ReplicaSets and Deployments: 4 deployment strategies, Pod lifecycle | [session-10-k8s-pods-replicasets-deployments](session-10-k8s-pods-replicasets-deployments/) |
| 11 | Kubernetes Services: 5 Service types, object comparison, FQDN, CoreDNS | [session-11-kubernetes-services](session-11-kubernetes-services/) |
| 12 | Ingress, ConfigMaps and Secrets, Ingress vs Ingress Controller, troubleshooting | [session-12-ingress-configmaps-secrets](session-12-ingress-configmaps-secrets/) |
| 13 | Storage, HPA and probes: volumes, HPA under load, mini project | [session-13-storage-hpa-probes](session-13-storage-hpa-probes/) |
| 14 | Kubernetes troubleshooting: kubectl toolkit, common failures, mini project | [session-14-kubernetes-troubleshooting](session-14-kubernetes-troubleshooting/) |
| 15 | Helm: all core commands, install/upgrade/rollback workflow, mini project | [session-15-helm](session-15-helm/) |
| 16 | CI/CD with GitHub Actions: build, test, artifacts, secrets, GHCR, deploy to kind | [session-16-cicd-github-actions](session-16-cicd-github-actions/) |
| 17 | DevSecOps: SAST, SCA, secret scanning, image scanning, security gate, hardened deploy | [session-17-devsecops](session-17-devsecops/) |
| 18 | Terraform and IaC: S3 demo, AWS services notes (IAM, EC2, S3, VPC, DynamoDB/RDS) | [session-18-terraform-iac](session-18-terraform-iac/) |
| 19 | Cloud and Terraform in action: VPC, subnets, SG, EC2 and S3 end to end | [session-19-terraform-project](session-19-terraform-project/) |
| 20 | Monitoring, observability and GitOps: Prometheus, Grafana, alerts, Argo CD | [session-20-monitoring-observability-gitops](session-20-monitoring-observability-gitops/) |
| 21 | Final DevOps project and troubleshooting challenge | [final-devops-project](final-devops-project/) |

The GitHub Actions workflows live in [.github/workflows](.github/workflows/), since that is the only place GitHub runs them from. Each workflow has a `paths:` filter, so it only runs when its own session folder changes.

## Environment

- macOS on Apple Silicon (arm64)
- Docker via Colima
- Minikube v1.39 running Kubernetes v1.37 (containerd), with the ingress and metrics-server add-ons
- Helm 4, Terraform, kubectl
- GitHub Actions on GitHub-hosted runners

Notes that apply to several sessions:

- **AWS on LocalStack:** the AWS sessions (18, 19 and the Terraform part of 21) run against [LocalStack](https://github.com/localstack/localstack) 4.14.0 instead of a paid AWS account. Each Terraform project has a `use_localstack` variable, so pointing it at real AWS is a tfvars change.
- **Docker Hub rate limits:** while I worked, Docker Hub refused anonymous pulls with `429 Too Many Requests`. Where that happened I pulled the same official images from the AWS ECR Public mirror (`public.ecr.aws/docker/library/...`). The affected READMEs show the error and say which image was swapped.
- **Real output only:** every output block was captured from a real run. Screenshots are real browser captures of the running apps and dashboards. Anything that could not be run on a single laptop (for example a multi-host overlay network, or RDS on LocalStack Community) is marked as documented only.

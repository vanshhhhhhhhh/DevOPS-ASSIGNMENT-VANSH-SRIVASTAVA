# Security gates (DevSecOps)

Configuration for the security checks that run in the CI pipeline
(`.github/workflows/final-project.yml` at the repo root) and locally with the
same Docker images. A gate fails the pipeline; a report is only uploaded as an artifact.

| Gate | Tool | What it checks | Fails the build when | Config |
|------|------|----------------|----------------------|--------|
| SAST | Bandit 1.9.4 | Python source in `application/backend/app` | any finding of medium or high severity | `bandit.yaml` |
| SAST | Semgrep 1.179.0 | Python, JavaScript, Dockerfiles, Kubernetes YAML (`p/python`, `p/javascript`, `p/dockerfile`, `p/kubernetes`) | any finding (`--error`) | `../.semgrepignore` |
| SCA | pip-audit 2.10.1 | `application/backend/requirements.txt` against PyPI advisories | any known vulnerability | - |
| SCA | npm audit | `application/frontend/package-lock.json` | high or critical advisory | - |
| SCA + secrets | Trivy 0.75.0 `fs` | lock files (including dev dependencies) and secret patterns in `application/` | fixable HIGH/CRITICAL CVE or a secret | `trivy.yaml`, `.trivyignore` |
| Secrets | gitleaks 8.30.1 `dir` | every file in `final-devops-project/` (default rules + a custom PostgreSQL-URL rule) | any leak | `.gitleaks.toml` |
| Container | Trivy 0.75.0 `image` | OS packages and Python packages inside both images | fixable HIGH/CRITICAL CVE | `trivy.yaml`, `.trivyignore` |
| IaC (report) | Trivy 0.75.0 `config` | Dockerfiles, Kubernetes manifests, Helm chart, Terraform | never (report only) | - |

Notes:

- **Why "fixable" only for the Trivy gates** (`ignore-unfixed: true`): the Debian base image always
  carries some HIGH CVEs that Debian has not patched yet. Nothing can be done about those in this
  repo, so blocking on them would block every build. They still appear in the full JSON report.
  Fixable ones are removed by rebuilding (`apt-get upgrade` / `apk upgrade` in the Dockerfiles)
  or by bumping the dependency.
- **Accepted risks** go into `.trivyignore`, one ID per line with a reason and a review date.
  It is empty: nothing is accepted.
- **gitleaks is scoped to this folder** because other session folders in the repo contain
  deliberately fake secrets used in earlier demos. The custom rule `postgres-url-with-password`
  catches connection strings with an inline password; only the documented demo value
  `demo-password-123`, gitleaks' own `REDACTED` marker (it appears in README output) and
  `${VAR}` / `{{ }}` placeholders are allowed.
- **Semgrep ignores `troubleshooting/`**: those manifests are broken on purpose for the
  troubleshooting lab and are never deployed by the pipeline.
- The IaC scan reports two `AWS-0104` (security group egress to 0.0.0.0/0 on 443) and one
  `AWS-0132` (S3 encrypted with AES256 instead of a customer-managed KMS key). Both are
  accepted for the LocalStack lab; on real AWS, egress would go through VPC endpoints / a NAT
  allow-list and the bucket would use a KMS key.

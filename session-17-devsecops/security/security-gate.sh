#!/usr/bin/env bash
# Security gate for the Session 17 pipeline.
#
# The scanners only FIND problems and write JSON reports. This script is the policy that DECIDES:
# it reads the reports and exits non-zero when a blocking finding is present, which stops the
# pipeline before the image is pushed or deployed.
#
# Usage: security/security-gate.sh <reports-dir> [sast] [sca] [secrets] [image]
#        With no check names every check runs (that is what the "Security gate" job does).
#
# Policy                    report            blocks when
#   SAST     Bandit         bandit.json       an issue has severity MEDIUM or HIGH
#            Semgrep        semgrep.json      a finding is above INFO/LOW (ERROR, WARNING, ...)
#   SCA      pip-audit      pip-audit.json    any dependency has a known vulnerability (counted once per advisory ID)
#            Trivy fs       trivy-fs.json     a dependency vulnerability is HIGH or CRITICAL
#   IaC      Trivy fs       trivy-fs.json     a Dockerfile/Kubernetes misconfiguration is HIGH or CRITICAL
#   Secrets  gitleaks       gitleaks.json     any secret is found
#   Image    Trivy image    trivy-image.json  any CRITICAL, or a HIGH that has a fixed version
# A missing or unreadable report fails the gate too (fail closed).
set -euo pipefail

REPORTS="${1:?usage: security-gate.sh <reports-dir> [sast] [sca] [secrets] [image]}"
shift
CHECKS="${*:-sast sca secrets image}"

failed=0
details=""
table="| Check | Report | Findings | Blocking | Result |
|---|---|---:|---:|---|"

# evaluate <label> <report> <jq: all findings> <jq: blocking findings> <jq: one line per blocking finding>
evaluate() {
  local label="$1" report="$2" total_q="$3" block_q="$4" detail_q="$5"
  local file="$REPORTS/$report" total blocking result
  if [ ! -s "$file" ] || ! jq empty "$file" >/dev/null 2>&1; then
    total="-"
    blocking="-"
    result="FAIL (report missing)"
    failed=1
  else
    total="$(jq "[$total_q] | length" "$file")"
    blocking="$(jq "[$block_q] | length" "$file")"
    if [ "$blocking" -gt 0 ]; then
      result="FAIL"
      failed=1
      details="${details}
${label}:
$(jq -r "$block_q | $detail_q" "$file" | head -n 20 | sed 's/^/  - /')"
    else
      result="PASS"
    fi
  fi
  table="${table}
| ${label} | ${report} | ${total} | ${blocking} | ${result} |"
}

TRIVY_VULNS='.Results[]? | .Vulnerabilities[]?'
TRIVY_VULN_LINE='"\(.Severity) \(.VulnerabilityID) \(.PkgName) \(.InstalledVersion) (fixed: \(.FixedVersion // "none"))"'

for check in $CHECKS; do
  case "$check" in
    sast)
      evaluate "SAST: Bandit" bandit.json \
        '.results[]' \
        '.results[] | select(.issue_severity == "MEDIUM" or .issue_severity == "HIGH")' \
        '"\(.issue_severity) \(.test_id) \(.filename):\(.line_number) \(.issue_text)"'
      evaluate "SAST: Semgrep" semgrep.json \
        '.results[]' \
        '.results[] | select(.extra.severity as $s | ["INFO", "LOW"] | index($s) | not)' \
        '"\(.extra.severity) \(.check_id) \(.path):\(.start.line)"'
      ;;
    sca)
      evaluate "SCA: pip-audit" pip-audit.json \
        '.dependencies[] | (.vulns // []) | unique_by(.id)[]' \
        '.dependencies[] | . as $d | (.vulns // []) | unique_by(.id)[] | {name: $d.name, version: $d.version, id: .id, fix: .fix_versions}' \
        '"\(.id) \(.name) \(.version) (fixed: \(.fix | join(", ")))"'
      evaluate "SCA: Trivy fs (dependencies)" trivy-fs.json \
        "$TRIVY_VULNS" \
        "$TRIVY_VULNS | select(.Severity == \"HIGH\" or .Severity == \"CRITICAL\")" \
        "$TRIVY_VULN_LINE"
      evaluate "IaC: Trivy fs (misconfig)" trivy-fs.json \
        '.Results[]? | .Misconfigurations[]? | select(.Status == "FAIL")' \
        '.Results[]? | .Target as $t | .Misconfigurations[]? | select(.Status == "FAIL" and (.Severity == "HIGH" or .Severity == "CRITICAL")) | .Target = $t' \
        '"\(.Severity) \(.ID) \(.Target): \(.Title)"'
      ;;
    secrets)
      evaluate "Secrets: gitleaks" gitleaks.json \
        '.[]' \
        '.[]' \
        '"\(.RuleID) \(.File):\(.StartLine)"'
      ;;
    image)
      evaluate "Image: Trivy" trivy-image.json \
        "$TRIVY_VULNS" \
        "$TRIVY_VULNS | select(.Severity == \"CRITICAL\" or (.Severity == \"HIGH\" and (.FixedVersion // \"\") != \"\"))" \
        "$TRIVY_VULN_LINE"
      ;;
    *)
      echo "unknown check: $check (use sast, sca, secrets, image)" >&2
      exit 2
      ;;
  esac
done

if [ "$failed" -eq 0 ]; then verdict="PASSED"; else verdict="FAILED"; fi

echo "$table"
if [ -n "$details" ]; then
  echo
  echo "Blocking findings:${details}"
fi
echo
echo "Security gate (${CHECKS}): ${verdict}"

if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  {
    echo "### Security gate (${CHECKS}): ${verdict}"
    echo
    echo "$table"
    if [ -n "$details" ]; then
      echo
      echo '```'
      echo "Blocking findings:${details}"
      echo '```'
    fi
  } >> "$GITHUB_STEP_SUMMARY"
fi

exit "$failed"

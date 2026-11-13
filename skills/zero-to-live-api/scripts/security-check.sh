#!/usr/bin/env bash
# ==============================================================================
# Script: security-check.sh
# Purpose: Pre-deployment security & hygiene scanner for zero-to-live-api
# Security: Zero telemetry, read-only static analysis, local execution only
# ==============================================================================

set -euo pipefail

VIOLATIONS=0
WARNINGS=0

echo "=========================================================="
echo "  [zero-to-live-api] Security & Hardening Audit"
echo "=========================================================="

# Check 1: Git-tracked environment files (.env)
echo ">> [1/4] Checking for committed .env files..."
if command -v git >/dev/null 2>&1 && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  TRACKED_ENV_FILES=$(git ls-files '.env*' ':!.env.example' ':!.env.template' 2>/dev/null || true)
  if [ -n "${TRACKED_ENV_FILES}" ]; then
    echo "::error:: Security Violation: Sensitive environment file(s) tracked by git:"
    echo "${TRACKED_ENV_FILES}"
    echo "Remediation: Run 'git rm --cached <file>' and ensure '.env*' is in '.gitignore'."
    VIOLATIONS=$((VIOLATIONS + 1))
  else
    echo "  [PASS] No secret .env files tracked by git."
  fi
else
  # If not a git repo yet, check if .env exists while .gitignore is missing or doesn't list .env
  if ls .env .env.local .env.production 2>/dev/null 1>&2; then
    if [ ! -f ".gitignore" ] || ! grep -q "\.env" ".gitignore" 2>/dev/null; then
      echo "::warning:: Found .env files on disk but '.gitignore' is missing or does not exclude '.env*'."
      echo "Remediation: Add '.env*' to .gitignore immediately."
      WARNINGS=$((WARNINGS + 1))
    else
      echo "  [PASS] .env files present and shielded by .gitignore."
    fi
  else
    echo "  [PASS] No exposed .env files found."
  fi
fi

# Check 2: Hardcoded secrets and private keys in source code
echo ">> [2/4] Scanning codebase for hardcoded secrets & credentials..."
SECRET_PATTERNS=(
  "AKIA[0-9A-Z]{16}"                              # AWS Access Key ID
  "sk-[a-zA-Z0-9]{20,}"                            # OpenAI / Stripe secret key prefix
  "ghp_[a-zA-Z0-9]{36}"                           # GitHub Personal Access Token
  "github_pat_[a-zA-Z0-9_]{40,}"                  # Fine-grained GitHub token
  "-----BEGIN (RSA |EC |DSA |OPENSSH )?PRIVATE KEY-----" # Raw private keys
  "(api_key|apiKey|secret_key|secretKey|jwt_secret|JWT_SECRET)[[:space:]]*=[[:space:]]*[\"'][a-zA-Z0-9_\-\.]{16,}[\"']" # Hardcoded secret strings
)

EXCLUDE_ARGS=(
  "--exclude-dir=node_modules"
  "--exclude-dir=.git"
  "--exclude-dir=.next"
  "--exclude-dir=dist"
  "--exclude-dir=.turbo"
  "--exclude-dir=.data"
  "--exclude=package-lock.json"
  "--exclude=pnpm-lock.yaml"
  "--exclude=bun.lockb"
  "--exclude=security-check.sh"
)

FOUND_SECRETS=0
for pattern in "${SECRET_PATTERNS[@]}"; do
  # Run grep across repository root
  MATCHES=$(grep -rnE "${EXCLUDE_ARGS[@]}" "${pattern}" . 2>/dev/null || true)
  if [ -n "${MATCHES}" ]; then
    echo "::error:: Potential hardcoded secret matched pattern '${pattern}':"
    echo "${MATCHES}" | head -n 5
    FOUND_SECRETS=$((FOUND_SECRETS + 1))
  fi
done

if [ "${FOUND_SECRETS}" -gt 0 ]; then
  echo "Remediation: Move all hardcoded secrets to process.env and document in .env.example."
  VIOLATIONS=$((VIOLATIONS + FOUND_SECRETS))
else
  echo "  [PASS] Zero hardcoded secrets detected in source files."
fi

# Check 3: Input validation enforcement on mutation routes
echo ">> [3/4] Verifying Zod schema validation on POST/PUT/PATCH routes..."
MUTATION_FILES=$(grep -rnE "${EXCLUDE_ARGS[@]}" "(\.post\(|\.put\(|\.patch\(|export async function (POST|PUT|PATCH))" . 2>/dev/null || true)

if [ -n "${MUTATION_FILES}" ]; then
  UNVALIDATED_ROUTES=0
  # For each matched source file, check if Zod / validator is referenced
  FILE_LIST=$(echo "${MUTATION_FILES}" | cut -d: -f1 | sort -u)
  for file in ${FILE_LIST}; do
    # Skip test scripts or node_modules
    if [[ "${file}" == *"node_modules"* ]] || [[ "${file}" == *"scripts/"* ]] || [[ "${file}" == *"dist/"* ]]; then
      continue
    fi
    if ! grep -qE "(z\.|zValidator|safeParse|parse\(|validateBody)" "${file}" 2>/dev/null; then
      echo "::error:: Route file '${file}' defines mutation endpoints without detected Zod input validation."
      UNVALIDATED_ROUTES=$((UNVALIDATED_ROUTES + 1))
    fi
  done

  if [ "${UNVALIDATED_ROUTES}" -gt 0 ]; then
    echo "Remediation: Wrap request body parsing with Zod schema validation (e.g. zValidator('json', schema) or schema.safeParse(body))."
    VIOLATIONS=$((VIOLATIONS + UNVALIDATED_ROUTES))
  else
    echo "  [PASS] Mutation endpoints enforce schema validation."
  fi
else
  echo "  [INFO] No mutation routes found or project structure pending scaffold."
fi

# Check 4: Insecure Wildcard CORS with Credentials
echo ">> [4/4] Auditing CORS configuration..."
CORS_WILDCARD=$(grep -rnE "${EXCLUDE_ARGS[@]}" "(origin:[[:space:]]*['\"]\*{1}['\"]|allow-origin:[[:space:]]*\*)" . 2>/dev/null || true)
CREDENTIALS_ENABLED=$(grep -rnE "${EXCLUDE_ARGS[@]}" "(credentials:[[:space:]]*true|allow-credentials:[[:space:]]*true)" . 2>/dev/null || true)

if [ -n "${CORS_WILDCARD}" ] && [ -n "${CREDENTIALS_ENABLED}" ]; then
  echo "::error:: Insecure CORS Policy Detected: Wildcard origin '*' is combined with 'credentials: true'."
  echo "Browsers reject credentials with wildcard origins, and it exposes endpoints to cross-site request forgery."
  echo "Remediation: Restrict origin to explicit allowed domain or dynamic whitelist function."
  VIOLATIONS=$((VIOLATIONS + 1))
else
  echo "  [PASS] CORS policies conform to secure origin rules."
fi

echo "=========================================================="
echo "  Audit Summary"
echo "  Violations: ${VIOLATIONS} | Warnings: ${WARNINGS}"
echo "=========================================================="

if [ "${VIOLATIONS}" -gt 0 ]; then
  echo "::error:: Security audit FAILED. Address violations above before shipping."
  exit 1
fi

echo "Security audit PASSED with zero critical vulnerabilities."
exit 0

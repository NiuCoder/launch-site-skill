#!/usr/bin/env bash
# Read-only launch preflight. Changes nothing, prints no secret values.
#
#   bash preflight.sh [--domain example.com] [--project DIR] [--manifest site.yaml]
#
# Exit 1 when any check FAILs. Optional: CLOUDFLARE_API_TOKEN for zone status.
set -u

DOMAIN=""
PROJECT="."
MANIFEST=""
while [ $# -gt 0 ]; do
  case "$1" in
    --domain) DOMAIN="${2:-}"; shift 2 ;;
    --domain=*) DOMAIN="${1#*=}"; shift ;;
    --project) PROJECT="${2:-}"; shift 2 ;;
    --project=*) PROJECT="${1#*=}"; shift ;;
    --manifest) MANIFEST="${2:-}"; shift 2 ;;
    --manifest=*) MANIFEST="${1#*=}"; shift ;;
    -h|--help) sed -n '2,7p' "$0"; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

cd "$PROJECT" || { echo "cannot cd to $PROJECT" >&2; exit 2; }
[ -n "$MANIFEST" ] || MANIFEST="site.yaml"

PASS=0; WARN=0; FAIL=0
pass() { PASS=$((PASS+1)); printf '  PASS  %s\n' "$*"; }
warn() { WARN=$((WARN+1)); printf '  WARN  %s\n' "$*"; }
fail() { FAIL=$((FAIL+1)); printf '  FAIL  %s\n' "$*"; }
info() { printf '  ....  %s\n' "$*"; }
section() { printf '\n== %s\n' "$*"; }
have() { command -v "$1" >/dev/null 2>&1; }

# Print a top-level field of a JSONC file (comments stripped outside strings).
jsonc_get() { # file expr   expr is JS on the parsed object `c`
  node -e '
    const fs = require("fs");
    const src = fs.readFileSync(process.argv[1], "utf8");
    let out = "", i = 0, inStr = false, q = "";
    while (i < src.length) {
      const ch = src[i], nx = src[i + 1];
      if (inStr) { out += ch; if (ch === "\\") { out += nx; i += 2; continue; } if (ch === q) inStr = false; i++; continue; }
      if (ch === "\"" || ch === "\x27") { inStr = true; q = ch; out += ch; i++; continue; }
      if (ch === "/" && nx === "/") { while (i < src.length && src[i] !== "\n") i++; continue; }
      if (ch === "/" && nx === "*") { i = src.indexOf("*/", i + 2); i = i < 0 ? src.length : i + 2; continue; }
      out += ch; i++;
    }
    out = out.replace(/,(\s*[}\]])/g, "$1");
    const c = JSON.parse(out);
    const v = (new Function("c", "return (" + process.argv[2] + ")"))(c);
    if (v !== undefined && v !== null) console.log(typeof v === "string" ? v : JSON.stringify(v));
  ' "$1" "$2" 2>/dev/null
}

# ---------------------------------------------------------------- tools
section "Tools"
for t in git node curl; do
  if have "$t"; then pass "$t found"; else fail "$t not found"; fi
done
if have pnpm; then pass "pnpm $(pnpm -v 2>/dev/null)"; else warn "pnpm not found (npm/yarn projects are fine)"; fi
have dig || warn "dig not found; DNS checks skipped"

if [ -f wrangler.jsonc ] || ls wrangler*.json* >/dev/null 2>&1; then
  if WHO=$(npx --no-install wrangler whoami 2>&1); then
    if printf '%s' "$WHO" | grep -qi "not authenticated\|You are not logged in"; then
      fail "wrangler not logged in — user runs: npx wrangler login  (matrix A1)"
    else
      pass "wrangler logged in"
    fi
  else
    warn "wrangler whoami failed (not installed locally?): $(printf '%s' "$WHO" | head -1)"
  fi
fi

# ---------------------------------------------------------------- project type
section "Project type"
if [ -f scripts/site-config.ts ] && [ -f scripts/init-rbac.ts ]; then
  pass "ShipAny template with site:config + rbac:init → references/shipany-template.md"
  grep -q '"cf:deploy"' package.json 2>/dev/null && pass "cf:deploy script present" || warn "no cf:deploy script"
elif [ -f scripts/init-rbac.ts ]; then
  warn "ShipAny template without site:config — fill Admin → Settings by hand, or upgrade the template"
elif ls wrangler*.json* >/dev/null 2>&1; then
  info "Cloudflare Workers project (not ShipAny) — Cloudflare phases apply, data steps are project-specific"
else
  info "no wrangler config — non-Workers project; replace phase 3 with your platform's deploy"
fi

# ---------------------------------------------------------------- secrets hygiene
section "Secrets hygiene (names only)"
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  TRACKED=$(git ls-files | grep -E '(\.pem|\.key|\.p12)$|(^|/)\.secrets/|(^|/)\.env(\.[A-Za-z0-9_-]+)*$' | grep -vE '\.env\.example$|\.env\.sample$|\.env\.template$' || true)
  if [ -n "$TRACKED" ]; then
    fail "secret-like files are tracked by git:"; printf '        %s\n' $TRACKED
  else
    pass "no secret-like files tracked"
  fi
  for probe in .env.production .env.local .secrets/probe probe.pem; do
    if git check-ignore -q "$probe" 2>/dev/null; then pass "$probe would be ignored"; else warn "$probe is NOT git-ignored"; fi
  done
else
  warn "not a git repository; skipped tracked-file checks"
fi

# ---------------------------------------------------------------- manifest
section "Manifest ($MANIFEST)"
if [ -f "$MANIFEST" ]; then
  pass "$MANIFEST exists"
  MDIR=$(dirname "$MANIFEST")
  MBODY="$(mktemp)"; sed -E 's/(^|[[:space:]])#.*$//' "$MANIFEST" > "$MBODY"   # drop YAML comments
  # Inline secrets: secret-looking key with a scalar value that is not a reference.
  INLINE=$(grep -nE '^[[:space:]]*[A-Za-z0-9_]*(secret|private_key|api_key|password|token)[A-Za-z0-9_]*:[[:space:]]*[^[:space:]{#]' "$MBODY" | grep -vE ':[[:space:]]*(true|false|""|'"''"')[[:space:]]*(#.*)?$' | cut -d: -f1 || true)
  if [ -n "$INLINE" ]; then
    fail "possible inline secret on line(s): $(echo $INLINE | tr ' ' ',') — use { file: } or { env: }"
  else
    pass "no inline secrets"
  fi
  REFS=$(grep -oE '\{[[:space:]]*file:[[:space:]]*[^[:space:]}]+' "$MBODY" | sed -E 's/.*file:[[:space:]]*//' | sort -u)
  for f in $REFS; do
    p="$MDIR/$f"
    if [ ! -e "$p" ]; then warn "file ref missing: $f (still to fetch from a dashboard?)"; continue; fi
    if git check-ignore -q "$p" 2>/dev/null; then pass "file ref $f exists and is ignored"; else fail "file ref $f is NOT git-ignored"; fi
  done
  ENVS=$(grep -oE '\{[[:space:]]*env:[[:space:]]*[A-Z0-9_]+' "$MBODY" | sed -E 's/.*env:[[:space:]]*//' | sort -u)
  for v in $ENVS; do
    found=""
    for ef in .env.production.local .env.production; do
      [ -f "$ef" ] && grep -qE "^$v=" "$ef" && found="$ef"
    done
    if [ -n "$found" ] || [ -n "$(printenv "$v" 2>/dev/null)" ]; then pass "env ref $v is set${found:+ ($found)}"; else warn "env ref $v not set in .env.production[.local] or shell"; fi
  done
  [ -n "$DOMAIN" ] || DOMAIN=$(grep -E '^[[:space:]]+domain:' "$MANIFEST" | head -1 | sed -E 's/.*domain:[[:space:]]*//; s/[[:space:]]*#.*//; s/["'"'"']//g')
else
  warn "no $MANIFEST — copy assets/site.example.yaml and fill it in with the user"
fi

# ---------------------------------------------------------------- wrangler configs
section "Wrangler configs"
APP_URLS=""
for wf in wrangler.production.jsonc wrangler.jsonc wrangler.test.jsonc wrangler.toml; do
  [ -f "$wf" ] || continue
  case "$wf" in *.toml) info "$wf present (TOML not parsed)"; continue ;; esac
  NAME=$(jsonc_get "$wf" 'c.name')
  URL=$(jsonc_get "$wf" '(c.vars||{}).VITE_APP_URL')
  ROUTES=$(jsonc_get "$wf" '(c.routes||[]).map(r=>typeof r==="string"?r:r.pattern).join(" ")')
  D1=$(jsonc_get "$wf" '(c.d1_databases||[]).map(d=>d.database_name+(/^[0-9a-f-]{36}$/.test(d.database_id||"")?"":"(placeholder id)")).join(" ")')
  R2=$(jsonc_get "$wf" '(c.r2_buckets||[]).map(b=>b.binding+"="+b.bucket_name).join(" ")')
  info "$wf: name=${NAME:-?} url=${URL:-–} routes=[${ROUTES:-}] d1=[${D1:-}] r2=[${R2:-}]"
  case "$D1" in *placeholder*) warn "$wf has a placeholder D1 database_id" ;; esac
  [ "$wf" = wrangler.test.jsonc ] || APP_URLS="$APP_URLS $URL"
done
if [ -f .env.production ]; then
  ENV_URL=$(grep -E '^VITE_APP_URL=' .env.production | head -1 | cut -d= -f2- | tr -d '"'"'"'')
  info ".env.production VITE_APP_URL=${ENV_URL:-–}"
  case "$ENV_URL" in *localhost*|*127.0.0.1*) fail ".env.production VITE_APP_URL points to localhost (pitfall L6)" ;; esac
  for u in $APP_URLS; do
    [ -n "$ENV_URL" ] && [ "$u" != "$ENV_URL" ] && warn "wrangler VITE_APP_URL $u differs from .env.production $ENV_URL"
  done
fi
if [ -n "$DOMAIN" ]; then
  for u in $APP_URLS $([ -n "${ENV_URL:-}" ] && echo "$ENV_URL"); do
    case "$u" in "https://$DOMAIN"|"https://$DOMAIN/") ;; *) warn "app URL $u is not https://$DOMAIN" ;; esac
  done
fi

# ---------------------------------------------------------------- DNS / zone
if [ -n "$DOMAIN" ]; then
  section "Domain $DOMAIN"
  if have dig; then
    NS=$(dig +short NS "$DOMAIN" 2>/dev/null | tr '\n' ' ')
    if [ -z "$NS" ]; then fail "no NS records (domain not registered or not delegated)"
    elif printf '%s' "$NS" | grep -qi 'cloudflare'; then pass "NS on Cloudflare: $NS"
    else warn "NS not on Cloudflare yet: $NS (matrix B3/B4)"; fi
    A=$(dig +short A "$DOMAIN" 2>/dev/null | tr '\n' ' ')
    case "$A" in 198.18.*|198.19.*) warn "A records are in 198.18.0.0/15 — a local proxy (fake-IP DNS) is answering; check DNS with: dig @1.1.1.1 $DOMAIN" ;; esac
    info "apex A: ${A:-none}  (old proxied A records block Worker custom domains — pitfall C1)"
    info "www: $(dig +short www."$DOMAIN" 2>/dev/null | tr '\n' ' ')"
    MX=$(dig +short MX "$DOMAIN" 2>/dev/null | tr '\n' ' ')
    info "MX: ${MX:-none}  (keep MX/SPF/DKIM when cleaning records)"
  fi
  if [ -n "${CLOUDFLARE_API_TOKEN:-}" ]; then
    Z=$(curl -sS -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" "https://api.cloudflare.com/client/v4/zones?name=$DOMAIN" 2>/dev/null)
    ST=$(printf '%s' "$Z" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{const r=JSON.parse(s).result[0];console.log(r?r.status:"absent")}catch{console.log("error")}})')
    case "$ST" in active) pass "zone status active" ;; absent) fail "zone not in this Cloudflare account (matrix B2)" ;; *) warn "zone status: $ST" ;; esac
  else
    info "CLOUDFLARE_API_TOKEN not set; zone status not checked"
  fi
  CODE=$(curl -sS -o /dev/null -w '%{http_code}' -A 'Mozilla/5.0 (launch-site preflight)' --max-time 15 "https://$DOMAIN/" 2>/dev/null || echo 000)
  info "https://$DOMAIN/ → HTTP $CODE"
fi

printf '\n%d PASS, %d WARN, %d FAIL\n' "$PASS" "$WARN" "$FAIL"
[ "$FAIL" -eq 0 ]

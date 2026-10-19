#!/usr/bin/env bash
# Post-deploy HTTP smoke test. GET/HEAD requests only.
#
#   bash smoke.sh https://example.com [--private /api/x]... [--retired /old]... [--max-pages 50]
#
# Checks home, robots, every sitemap URL (SEO tags), www/http redirects,
# security headers, private endpoints refused, retired paths gone.
# Exit 1 when any check FAILs.
set -u

BASE=""
PRIVATE=""
RETIRED=""
MAX=50
while [ $# -gt 0 ]; do
  case "$1" in
    --private) PRIVATE="$PRIVATE ${2:-}"; shift 2 ;;
    --private=*) PRIVATE="$PRIVATE ${1#*=}"; shift ;;
    --retired) RETIRED="$RETIRED ${2:-}"; shift 2 ;;
    --retired=*) RETIRED="$RETIRED ${1#*=}"; shift ;;
    --max-pages) MAX="${2:-50}"; shift 2 ;;
    --max-pages=*) MAX="${1#*=}"; shift ;;
    -h|--help) sed -n '2,9p' "$0"; exit 0 ;;
    http*://*) BASE="${1%/}"; shift ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done
[ -n "$BASE" ] || { echo "usage: smoke.sh https://example.com [...]" >&2; exit 2; }

HOST=$(printf '%s' "$BASE" | sed -E 's#^https?://##; s#/.*##')
APEX=${HOST#www.}
UA='Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) launch-site-smoke'
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

PASS=0; WARN=0; FAIL=0
pass() { PASS=$((PASS+1)); printf '  PASS  %s\n' "$*"; }
warn() { WARN=$((WARN+1)); printf '  WARN  %s\n' "$*"; }
fail() { FAIL=$((FAIL+1)); printf '  FAIL  %s\n' "$*"; }
section() { printf '\n== %s\n' "$*"; }

fetch() { # url outfile → prints http code
  curl -sS -L --max-redirs 0 -A "$UA" --max-time 30 -o "$2" -D "$2.h" -w '%{http_code}' "$1" 2>/dev/null || echo 000
}
status_only() { # url → "code redirect_url"
  curl -sS -A "$UA" --max-time 20 -o /dev/null -w '%{http_code} %{redirect_url}' "$1" 2>/dev/null || echo "000 "
}
header() { # headerfile name → value
  grep -i "^$2:" "$1" 2>/dev/null | tail -1 | cut -d: -f2- | tr -d '\r' | sed 's/^ *//'
}
# Extract from HTML with perl (portable on macOS).
html_field() { # file field
  case "$2" in
    title) perl -0777 -ne 'if (/<title[^>]*>(.*?)<\/title>/is) { $t=$1; $t=~s/\s+/ /g; print $t }' "$1" ;;
    description) perl -0777 -ne 'while (/<meta\b[^>]*>/gis) { $m=$&; if ($m=~/name=["\x27]description["\x27]/i && $m=~/content=["\x27]([^"\x27]*)/i) { print $1; last } }' "$1" ;;
    canonical) perl -0777 -ne 'while (/<link\b[^>]*>/gis) { $m=$&; if ($m=~/rel=["\x27]canonical["\x27]/i && $m=~/href=["\x27]([^"\x27]*)/i) { print $1; last } }' "$1" ;;
    ogimage) perl -0777 -ne 'while (/<meta\b[^>]*>/gis) { $m=$&; if ($m=~/property=["\x27]og:image["\x27]/i && $m=~/content=["\x27]([^"\x27]*)/i) { print $1; last } }' "$1" ;;
    robots) perl -0777 -ne 'while (/<meta\b[^>]*>/gis) { $m=$&; if ($m=~/name=["\x27]robots["\x27]/i && $m=~/content=["\x27]([^"\x27]*)/i) { print $1; last } }' "$1" ;;
    h1count) perl -0777 -ne '$n=()=/<h1\b/gi; print $n' "$1" ;;
    firstheading) perl -0777 -ne 'if (/<h([1-6])\b/i) { print $1 }' "$1" ;;
  esac
}
norm() { printf '%s' "$1" | sed -E 's#/+$##'; }

# ---------------------------------------------------------------- basics
section "Basics ($BASE)"
C=$(fetch "$BASE/" "$TMP/home"); [ "$C" = 200 ] && pass "/ → 200" || fail "/ → $C"
C=$(fetch "$BASE/robots.txt" "$TMP/robots")
if [ "$C" = 200 ]; then
  pass "/robots.txt → 200"
  grep -qi '^sitemap:' "$TMP/robots" && pass "robots.txt declares a Sitemap" || warn "robots.txt has no Sitemap: line"
  grep -qiE '^disallow:[[:space:]]*/[[:space:]]*$' "$TMP/robots" && fail "robots.txt disallows the whole site"
else
  fail "/robots.txt → $C"
fi

SITEMAP=$(grep -i '^sitemap:' "$TMP/robots" 2>/dev/null | head -1 | cut -d: -f2- | tr -d '\r ' )
[ -n "$SITEMAP" ] || SITEMAP="$BASE/sitemap.xml"
C=$(fetch "$SITEMAP" "$TMP/sm")
URLS=""
if [ "$C" = 200 ]; then
  pass "sitemap $SITEMAP → 200"
  if grep -qi '<sitemapindex' "$TMP/sm"; then
    for child in $(perl -0777 -ne 'print "$1\n" while /<loc>\s*(.*?)\s*<\/loc>/gis' "$TMP/sm"); do
      fetch "$child" "$TMP/smc" >/dev/null
      URLS="$URLS $(perl -0777 -ne 'print "$1\n" while /<loc>\s*(.*?)\s*<\/loc>/gis' "$TMP/smc")"
    done
  else
    URLS=$(perl -0777 -ne 'print "$1\n" while /<loc>\s*(.*?)\s*<\/loc>/gis' "$TMP/sm")
  fi
  N=$(printf '%s\n' $URLS | grep -c . || true)
  [ "$N" -gt 0 ] && pass "sitemap lists $N URLs" || fail "sitemap has no <loc> entries"
  OFF=$(printf '%s\n' $URLS | grep -v "^https://$HOST\(/\|$\)" || true)
  [ -z "$OFF" ] && pass "all sitemap URLs are on https://$HOST" || fail "sitemap URLs on another host: $(printf '%s ' $OFF | cut -c1-200)"
else
  fail "sitemap $SITEMAP → $C"
fi
[ -n "$URLS" ] || URLS="$BASE/"

# ---------------------------------------------------------------- pages
section "Pages (SEO tags, up to $MAX)"
: > "$TMP/titles"
i=0
for u in $URLS; do
  i=$((i+1)); [ "$i" -le "$MAX" ] || { warn "stopped after $MAX pages (--max-pages)"; break; }
  f="$TMP/p$i"
  C=$(fetch "$u" "$f")
  path=${u#https://$HOST}; [ -n "$path" ] || path=/
  if [ "$C" != 200 ]; then fail "$path → $C"; continue; fi
  problems=""
  T=$(html_field "$f" title); [ -n "$T" ] && printf '%s\t%s\n' "$T" "$path" >> "$TMP/titles" || problems="$problems no-title"
  [ -n "$(html_field "$f" description)" ] || problems="$problems no-description"
  CAN=$(html_field "$f" canonical)
  if [ -z "$CAN" ]; then problems="$problems no-canonical"
  elif [ "$(norm "$CAN")" != "$(norm "$u")" ]; then problems="$problems canonical=$CAN"; fi
  H1=$(html_field "$f" h1count); [ "$H1" = 1 ] || problems="$problems h1x${H1:-0}"
  FH=$(html_field "$f" firstheading); [ -z "$FH" ] || [ "$FH" = 1 ] || problems="$problems first-heading-h$FH"
  [ -n "$(html_field "$f" ogimage)" ] || problems="$problems no-og:image"
  R="$(html_field "$f" robots) $(header "$f.h" x-robots-tag)"
  printf '%s' "$R" | grep -qi noindex && problems="$problems noindex"
  if [ -z "$problems" ]; then pass "$path"; else fail "$path:$problems"; fi
done
DUP=$(cut -f1 "$TMP/titles" | sort | uniq -d)
[ -z "$DUP" ] && pass "titles are unique" || fail "duplicate titles: $(printf '%s' "$DUP" | head -3 | tr '\n' '|')"

# ---------------------------------------------------------------- redirects
section "Redirects"
read -r C L <<EOF
$(status_only "https://www.$APEX/__smoke?x=1")
EOF
case "$C" in
  301|308) [ "$L" = "https://$APEX/__smoke?x=1" ] && pass "www → apex keeps path+query ($C)" || fail "www redirect goes to $L" ;;
  000) warn "www.$APEX not reachable" ;;
  *) warn "www.$APEX/__smoke → $C (no redirect to apex?)" ;;
esac
read -r C L <<EOF
$(status_only "http://$HOST/")
EOF
case "$C" in 301|302|307|308) case "$L" in https://*) pass "http → https ($C)" ;; *) fail "http redirects to $L" ;; esac ;; *) fail "http://$HOST/ → $C (no https redirect)" ;; esac

# ---------------------------------------------------------------- headers
section "Security headers (/)"
H="$TMP/home.h"
[ -n "$(header "$H" strict-transport-security)" ] && pass "HSTS" || warn "no Strict-Transport-Security"
header "$H" x-content-type-options | grep -qi nosniff && pass "nosniff" || warn "no X-Content-Type-Options: nosniff"
if [ -n "$(header "$H" x-frame-options)" ] || header "$H" content-security-policy | grep -qi frame-ancestors; then pass "clickjacking protection"; else warn "no X-Frame-Options / frame-ancestors"; fi

# ---------------------------------------------------------------- private / retired
if [ -n "$(echo $PRIVATE)" ]; then
  section "Private endpoints (signed out)"
  for p in $PRIVATE; do
    C=$(fetch "$BASE$p" "$TMP/priv")
    case "$C" in
      401|403) pass "$p → $C" ;;
      200) if grep -qiE '"code"[[:space:]]*:[[:space:]]*-?[1-9]|unauthori[sz]ed|forbidden' "$TMP/priv"; then warn "$p → 200 with an error envelope (check it is a refusal)"; else fail "$p → 200 without auth"; fi ;;
      *) warn "$p → $C" ;;
    esac
  done
fi
if [ -n "$(echo $RETIRED)" ]; then
  section "Retired paths (and case/encoding variants — pitfall C7)"
  for p in $RETIRED; do
    upper=$(printf '%s' "$p" | tr '[:lower:]' '[:upper:]')
    first=$(printf '%s' "$p" | sed -E 's#^/##' | cut -c1)
    hex=$(printf '%s' "$first" | od -An -tx1 | tr -d ' \n')
    enc="/%$hex$(printf '%s' "$p" | sed -E 's#^/.##')"
    for v in "$p" "$upper" "$enc" "$p/"; do
      read -r C L <<EOF
$(status_only "$BASE$v")
EOF
      case "$C" in 404|410|400) pass "$v → $C" ;; 301|308) pass "$v → $C $L" ;; *) fail "$v → $C" ;; esac
    done
  done
fi

printf '\n%d PASS, %d WARN, %d FAIL\n' "$PASS" "$WARN" "$FAIL"
[ "$FAIL" -eq 0 ]

#!/usr/bin/env bash
# Is Aurora's documentation readable by an AGENT?
#
# An agent fetches URLs over plain HTTP. It does not run JavaScript. Everything it needs
# must be in the raw response body. This script probes exactly that, and nothing else —
# a site can look perfect in a browser and score zero here.
#
# Repeatable acceptance test for aurorainfra/inference-roadmap#185.
#
#   tests/docs-agent-readiness.sh                      # default hosts
#   DOCS_HOST=https://docs.aurorainfra.ai tests/docs-agent-readiness.sh
#
# Exit 0 = an agent can use these docs. Non-zero = it cannot.
set -uo pipefail

DOCS_HOST="${DOCS_HOST:-https://docs.aur.lu}"
ALT_HOST="${ALT_HOST:-https://docs.aurorainfra.ai}"
SPEC_URL="${SPEC_URL:-https://docs.aur.lu/portal-api-spec.json}"
# Real doc paths that must return DISTINCT content.
PATHS=("${DOCS_PATHS:-/docs/portal-api /docs/portal-api/portal-api-overview /docs/inference}")
BOGUS="/docs/__no_such_page_$$"

PASS=0; FAIL=0
ok()  { printf '  \033[32mPASS\033[0m  %s\n' "$1"; PASS=$((PASS+1)); }
bad() { printf '  \033[31mFAIL\033[0m  %s\n' "$1"; FAIL=$((FAIL+1)); }
sec() { printf '\n\033[1m%s\033[0m\n' "$1"; }
fetch() { curl -sS -L --max-time 25 "$1" 2>/dev/null; }
code()  { curl -sS -L -o /dev/null -w '%{http_code}' --max-time 25 "$1" 2>/dev/null || echo 000; }
ctype() { curl -sS -L -o /dev/null -w '%{content_type}' --max-time 25 "$1" 2>/dev/null; }

echo "Agent-readability probe — plain HTTP, no JavaScript"
echo "  primary: $DOCS_HOST"
echo "  alt:     $ALT_HOST"

# 1 ── Hostnames resolve ──────────────────────────────────────────────────────
sec "1. Hostnames resolve"
for h in "$DOCS_HOST" "$ALT_HOST"; do
  host=$(printf '%s' "$h" | sed -E 's#^https?://##; s#/.*##')
  if [ -n "$(dig +short "$host" 2>/dev/null)" ]; then ok "$host resolves"
  else bad "$host does NOT resolve (no DNS record — an agent cannot reach it at all)"; fi
done

# 2 ── Pages return distinct content (catches the SPA catch-all) ──────────────
sec "2. Each page returns its own content (not one shared shell)"
TMPD=$(mktemp -d); i=0; declare -a HASHES=()
for p in ${PATHS[0]}; do
  i=$((i+1)); fetch "$DOCS_HOST$p" > "$TMPD/p$i"
  HASHES+=("$(shasum "$TMPD/p$i" | cut -d' ' -f1)")
done
fetch "$DOCS_HOST$BOGUS" > "$TMPD/bogus"
BOGUS_HASH=$(shasum "$TMPD/bogus" | cut -d' ' -f1)

UNIQ=$(printf '%s\n' "${HASHES[@]}" | sort -u | wc -l | tr -d ' ')
if [ "$UNIQ" -eq "${#HASHES[@]}" ]; then ok "all ${#HASHES[@]} doc pages return distinct bodies"
else bad "only $UNIQ distinct body/bodies across ${#HASHES[@]} pages — server is returning one shared shell"; fi

if printf '%s\n' "${HASHES[@]}" | grep -q "$BOGUS_HASH"; then
  bad "a real page is byte-identical to a nonexistent page — catch-all confirmed"
else ok "real pages differ from a nonexistent path"; fi

# 3 ── Nonexistent paths 404 ──────────────────────────────────────────────────
sec "3. Unknown paths return 404"
BC=$(code "$DOCS_HOST$BOGUS")
[ "$BC" = "404" ] && ok "bogus path returns 404" \
                  || bad "bogus path returns $BC (an agent cannot tell a typo from a real page)"

# 4 ── Content present without JavaScript ────────────────────────────────────
sec "4. Content is in the HTML, not behind JavaScript"
for p in ${PATHS[0]}; do
  BODY=$(fetch "$DOCS_HOST$p")
  TEXT=$(printf '%s' "$BODY" | sed -E 's/<(script|style)[^>]*>.*<\/(script|style)>//g; s/<[^>]+>//g' | tr -s ' \n' ' ')
  WORDS=$(printf '%s' "$TEXT" | wc -w | tr -d ' ')
  if [ "$WORDS" -ge 50 ]; then ok "$p has $WORDS words of text without JS"
  else bad "$p has only $WORDS words without JS (JS-rendered; invisible to an agent)"; fi
done

# 5 ── robots.txt ────────────────────────────────────────────────────────────
sec "5. robots.txt is a real robots file"
RB=$(fetch "$DOCS_HOST/robots.txt"); RT=$(ctype "$DOCS_HOST/robots.txt")
if printf '%s' "$RB" | grep -qiE '^(user-agent|disallow|allow|sitemap)'; then
  ok "robots.txt contains robots directives"
else
  bad "robots.txt returns no directives (content-type: ${RT:-unknown}) — it is serving the HTML shell"
fi

# 6 ── sitemap.xml is real and not placeholder-hosted ────────────────────────
sec "6. sitemap.xml exists and points at the real host"
SM=$(fetch "$DOCS_HOST/sitemap.xml")
if printf '%s' "$SM" | grep -q '<urlset'; then
  ok "sitemap.xml is valid XML"
  TOTAL=$(printf '%s' "$SM" | grep -o '<loc>' | wc -l | tr -d ' ')
  BADU=$(printf '%s' "$SM" | grep -o '<loc>[^<]*</loc>' | grep -c 'example\.com' || true)
  [ "${BADU:-0}" -eq 0 ] && ok "all $TOTAL sitemap URLs point at a real host" \
    || bad "$BADU of $TOTAL sitemap URLs point at example.com (docusaurus.config 'url' is unset)"
else
  bad "sitemap.xml is missing or not XML"
fi

# 7 ── canonical / og:url not placeholder ────────────────────────────────────
sec "7. Page metadata is not the framework default"
HOME=$(fetch "$DOCS_HOST/")
if printf '%s' "$HOME" | grep -qi 'example\.com'; then
  bad "homepage metadata still contains example.com (canonical/og:url are placeholders)"
else
  ok "homepage metadata contains no example.com placeholder"
fi

# 8 ── The thing that already works — guard it ───────────────────────────────
sec "8. Regression guard: raw OpenAPI spec stays agent-fetchable"
SC=$(code "$SPEC_URL"); SB=$(fetch "$SPEC_URL")
SPEC_INFO=$(printf '%s' "$SB" | python3 -c "
import json,sys
try:
    d=json.load(sys.stdin)
    v=d.get('swagger') or d.get('openapi')
    if not v: print('NOVERSION'); sys.exit()
    print(f\"OK {v} {len(d.get('paths',{}))}\")
except Exception as e:
    print('NOTJSON')
" 2>/dev/null || echo NOTJSON)
case "$SC:$SPEC_INFO" in
  200:OK*) ok "spec returns 200, valid JSON (swagger/openapi $(echo "$SPEC_INFO" | cut -d' ' -f2), $(echo "$SPEC_INFO" | cut -d' ' -f3) paths)" ;;
  200:*)   bad "spec returns 200 but is not parseable JSON ($SPEC_INFO) — likely the SPA shell" ;;
  *)       bad "spec not fetchable (HTTP $SC) — this was the one artifact that worked" ;;
esac

rm -rf "$TMPD"
printf '\n\033[1mResult:\033[0m %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] || { echo "An agent cannot reliably use these docs. See aurorainfra/inference-roadmap#185."; exit 1; }

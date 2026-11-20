#!/usr/bin/env bash
# deploy/azure-frontend.sh: the website (frontend/) on Azure Static Web Apps.
# Run after deploy/azure.sh and deploy/github-setup.sh. Safe to rerun.
#
#   bash deploy/azure-frontend.sh
#   DRY_RUN=1 bash deploy/azure-frontend.sh
#
# It:
#   - creates Static Web App <app>-web (Free plan) in group <app>, WITHOUT a
#     GitHub link (GitHub Actions uploads the built site; nothing is stored
#     in GitHub). Its region (eastasia) is only where its settings live: the
#     site itself is served from Azure's global edge.
#   - writes STATIC_WEB_APP_NAME, WEBSITE_URL and the website build setting
#     WEB_ENV_VITE_API_URL (= BACKEND_URL) into deploy/azure-deploy.conf
#   - prints the git command that publishes the config file (on first setup
#     this is the one push that starts both deploys)
#
# CORS: backend/main.py allows every origin (allow_origins=["*"]), so the new
# website address needs no backend setting and azure.sh needn't be rerun.
set -euo pipefail
. "$(cd "$(dirname "$0")" && pwd)/lib.sh"

need az
need jq
need git
load_conf

SWA_NAME="$APP-web"
SWA_LOCATION=eastasia

[ "$DRY_RUN" = 1 ] && say "DRY RUN: nothing will be changed"
say "Project $APP: website $SWA_NAME (Azure Static Web Apps, Free)"

acct="$(az account show --subscription "$SUB" -o json 2>/dev/null)" \
  || die "can't use subscription $SUB. Run 'az login' and check you have access."
info "signed in as $(printf '%s' "$acct" | jq -r '.user.name // "?"') to '$(printf '%s' "$acct" | jq -r '.name // "?"')'"

# ---------------------------------------------------------------------------
# What the earlier scripts made
# ---------------------------------------------------------------------------
say "Checking deploy/azure.sh and deploy/github-setup.sh ran"
if [ "$(az_ group exists --name "$RG" 2>/dev/null)" != true ]; then
  [ "$DRY_RUN" = 1 ] || die "resource group $RG doesn't exist yet: run bash deploy/azure.sh first"
  info "(dry run) group $RG doesn't exist yet"
fi
BACKEND_URL="$(conf_get BACKEND_URL)"
case "$BACKEND_URL" in
  https://*) info "backend: $BACKEND_URL" ;;
  "") [ "$DRY_RUN" = 1 ] || die "BACKEND_URL is empty in $CONF_REL: run bash deploy/azure.sh first"
      BACKEND_URL="<BACKEND_URL from deploy/azure.sh>" ;;
  *) die "BACKEND_URL in $CONF_REL ('$BACKEND_URL') must start with https://" ;;
esac
[ -n "$(conf_get AZURE_CLIENT_ID)" ] || [ "$DRY_RUN" = 1 ] \
  || warn "AZURE_CLIENT_ID is empty in $CONF_REL: run bash deploy/github-setup.sh too, or GitHub can't deploy"

# ---------------------------------------------------------------------------
# Static Web App (this project's group only)
# ---------------------------------------------------------------------------
say "Static Web App $SWA_NAME"
SWA_JSON=""
swa_exists() { SWA_JSON="$(az_ staticwebapp show --name "$SWA_NAME" --resource-group "$RG" -o json 2>/dev/null)" && [ -n "$SWA_JSON" ]; }
swa_create() { run az_ staticwebapp create --name "$SWA_NAME" --resource-group "$RG" --location "$SWA_LOCATION" --sku Free --tags "project=$APP" -o none; }
ensure "static web app $SWA_NAME" swa_exists swa_create
swa_exists || true
HOST="$(printf '%s' "${SWA_JSON:-}" | jq -r '.defaultHostname // empty' 2>/dev/null || true)"
sku="$(printf '%s' "${SWA_JSON:-}" | jq -r '.sku.name // empty' 2>/dev/null || true)"
[ -z "$sku" ] || [ "$sku" = Free ] || warn "$SWA_NAME is on the '$sku' plan, not Free (not changing it)"
repo_link="$(printf '%s' "${SWA_JSON:-}" | jq -r '.repositoryUrl // empty' 2>/dev/null || true)"
[ -z "$repo_link" ] || warn "$SWA_NAME is linked to $repo_link; GitHub Actions here uploads the site itself, the link isn't needed"

# ---------------------------------------------------------------------------
# Record results: address and website build settings
# ---------------------------------------------------------------------------
say "Results"
conf_set STATIC_WEB_APP_NAME "$SWA_NAME"
if [ -n "$HOST" ]; then conf_set WEBSITE_URL "https://$HOST"; fi
# The only build setting: the backend address the website calls. Public by
# nature (it is in the browser's JavaScript). No other value from .env.azure
# is copied: every setting there is a server-side API key.
case "$BACKEND_URL" in https://*) conf_set WEB_ENV_VITE_API_URL "${BACKEND_URL%/}" ;; esac
if [ "$DRY_RUN" = 0 ] && [ -z "$(conf_get WEB_ENV_VITE_API_URL)" ]; then
  warn "WEB_ENV_VITE_API_URL is empty in $CONF_REL; the website workflow stops until it is set"
fi

if [ -n "$HOST" ]; then info "website: https://$HOST"; else info "website: (address known after it is created)"; fi
info "backend: $BACKEND_URL"
info "CORS: the backend allows every origin (backend/main.py), so nothing to change there."

if [ "$DRY_RUN" = 1 ]; then
  say "Dry run finished: nothing was changed."
else
  say "Done. Pushing the config file starts both deploys (GitHub Actions: 'Deploy to Azure' and 'Deploy website to Azure')."
  print_publish_line "Azure: deploy settings for Rep-Tell"
fi

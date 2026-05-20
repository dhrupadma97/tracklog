#!/bin/bash

# ============================================================
# TrackLog — GitHub Pages Automated Setup Script
# ============================================================
# This script automates:
#   1. Enabling GitHub Pages (source: GitHub Actions)
#   2. Adding all required GitHub Secrets
#   3. Triggering the first deployment workflow
#
# Requirements: GitHub CLI (gh) must be installed and logged in.
# Install: https://cli.github.com/
# Login:   gh auth login
# ============================================================

set -e

# ── Colours ──────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Colour

echo ""
echo -e "${CYAN}${BOLD}╔══════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}${BOLD}║   TrackLog — GitHub Pages Setup Automation   ║${NC}"
echo -e "${CYAN}${BOLD}╚══════════════════════════════════════════════╝${NC}"
echo ""

# ── Check GitHub CLI is installed ────────────────────────────
if ! command -v gh &> /dev/null; then
  echo -e "${RED}✗ GitHub CLI (gh) is not installed.${NC}"
  echo -e "  Install it from: ${CYAN}https://cli.github.com/${NC}"
  echo -e "  Then run: ${YELLOW}gh auth login${NC}"
  exit 1
fi

# ── Check user is authenticated ──────────────────────────────
if ! gh auth status &> /dev/null; then
  echo -e "${RED}✗ You are not logged in to GitHub CLI.${NC}"
  echo -e "  Run: ${YELLOW}gh auth login${NC} and try again."
  exit 1
fi

echo -e "${GREEN}✓ GitHub CLI detected and authenticated.${NC}"
echo ""

# ── Detect repo (owner/name) ─────────────────────────────────
REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || true)

if [ -z "$REPO" ]; then
  echo -e "${YELLOW}Could not auto-detect repository.${NC}"
  read -rp "Enter your GitHub repo (e.g. username/tracklog): " REPO
fi

echo -e "Repository: ${CYAN}${BOLD}$REPO${NC}"
echo ""

# ── Collect secret values ─────────────────────────────────────
echo -e "${BOLD}Enter your secret values below.${NC}"
echo -e "${YELLOW}(Press Enter to skip a secret — it won't be overwritten if it already exists)${NC}"
echo ""

read -rp "SUPABASE_URL         : " SUPABASE_URL
read -rp "SUPABASE_ANON_KEY    : " SUPABASE_ANON_KEY
read -rp "GOOGLE_WEB_CLIENT_ID : " GOOGLE_WEB_CLIENT_ID
read -rp "GOOGLE_MAPS_API_KEY  : " GOOGLE_MAPS_API_KEY
read -rp "RESEND_API_KEY       : " RESEND_API_KEY

echo ""

# ── Set GitHub Secrets ────────────────────────────────────────
echo -e "${BOLD}Step 1/3 — Setting GitHub Secrets...${NC}"

set_secret() {
  local name="$1"
  local value="$2"
  if [ -n "$value" ]; then
    echo "$value" | gh secret set "$name" --repo "$REPO" --body -
    echo -e "  ${GREEN}✓ $name set${NC}"
  else
    echo -e "  ${YELLOW}⚠ $name skipped (empty)${NC}"
  fi
}

set_secret "SUPABASE_URL"         "$SUPABASE_URL"
set_secret "SUPABASE_ANON_KEY"    "$SUPABASE_ANON_KEY"
set_secret "GOOGLE_WEB_CLIENT_ID" "$GOOGLE_WEB_CLIENT_ID"
set_secret "GOOGLE_MAPS_API_KEY"  "$GOOGLE_MAPS_API_KEY"
set_secret "RESEND_API_KEY"       "$RESEND_API_KEY"

echo ""

# ── Enable GitHub Pages (source: GitHub Actions) ──────────────
echo -e "${BOLD}Step 2/3 — Enabling GitHub Pages...${NC}"

HTTP_STATUS=$(gh api \
  --method POST \
  -H "Accept: application/vnd.github+json" \
  "/repos/$REPO/pages" \
  -f "build_type=workflow" \
  --silent \
  -w "%{http_code}" \
  -o /dev/null 2>/dev/null || true)

if [ "$HTTP_STATUS" = "201" ] || [ "$HTTP_STATUS" = "409" ]; then
  # 409 = already enabled — that's fine
  echo -e "  ${GREEN}✓ GitHub Pages enabled (source: GitHub Actions)${NC}"
else
  # Try PATCH in case it already exists but needs updating
  gh api \
    --method PUT \
    -H "Accept: application/vnd.github+json" \
    "/repos/$REPO/pages" \
    -f "build_type=workflow" \
    --silent 2>/dev/null || true
  echo -e "  ${GREEN}✓ GitHub Pages configured (source: GitHub Actions)${NC}"
fi

echo ""

# ── Trigger the deployment workflow ──────────────────────────
echo -e "${BOLD}Step 3/3 — Triggering first deployment...${NC}"

if gh workflow run "Deploy TrackLog to GitHub Pages" --repo "$REPO" 2>/dev/null; then
  echo -e "  ${GREEN}✓ Workflow triggered successfully${NC}"
else
  # Fallback: trigger by workflow file name
  if gh workflow run "deploy.yml" --repo "$REPO" 2>/dev/null; then
    echo -e "  ${GREEN}✓ Workflow triggered successfully${NC}"
  else
    echo -e "  ${YELLOW}⚠ Could not trigger workflow automatically.${NC}"
    echo -e "    Push any commit to 'main' to start the first deployment."
  fi
fi

echo ""

# ── Summary ───────────────────────────────────────────────────
REPO_NAME=$(echo "$REPO" | cut -d'/' -f2)
OWNER=$(echo "$REPO" | cut -d'/' -f1)

echo -e "${CYAN}${BOLD}╔══════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}${BOLD}║                  All Done! 🎉                ║${NC}"
echo -e "${CYAN}${BOLD}╚══════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  ${BOLD}Monitor deployment:${NC}"
echo -e "  ${CYAN}https://github.com/$REPO/actions${NC}"
echo ""
echo -e "  ${BOLD}Your app will be live at:${NC}"
echo -e "  ${CYAN}https://${OWNER}.github.io/${REPO_NAME}/${NC}"
echo ""
echo -e "  ${YELLOW}Note: First deployment takes ~3–5 minutes.${NC}"
echo ""

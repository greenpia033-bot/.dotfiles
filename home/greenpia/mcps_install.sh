#!/usr/bin/env bash
set -e

echo "== Installing Codex MCPs =="

# Context7
codex mcp add context7 -- \
    npx -y @upstash/context7-mcp

# Filesystem
codex mcp add filesystem -- \
    npx -y @modelcontextprotocol/server-filesystem /

# Playwright
codex mcp add playwright -- \
    npx -y @playwright/mcp

# Sequential Thinking
codex mcp add sequential-thinking -- \
    npx -y @modelcontextprotocol/server-sequential-thinking

# Git
#codex mcp add git -- \
#    npx -y @modelcontextprotocol/server-git

# Chrome DevTools
codex mcp add chrome -- \
    npx -y chrome-devtools-mcp@latest

# Docker（可选）
codex mcp add docker -- \
    npx -y docker-mcp

echo
echo "Installing Codebase Memory..."
curl -fsSL https://raw.githubusercontent.com/DeusData/codebase-memory-mcp/main/install.sh | bash

echo
echo "Done."
echo
codex mcp list

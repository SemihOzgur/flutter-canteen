#!/bin/bash

set -euo pipefail

echo "================================"
echo " CANTEEN SCOPE AUDIT"
echo "================================"

echo ""
echo "==> Current branch"
git branch --show-current

echo ""
echo "==> Git status"
git status --short

echo ""
echo "==> Changed files"
git diff --name-only

echo ""
echo "==> Diff stat"
git diff --stat

echo ""
echo "==> Diff check"
git diff --check

echo ""
echo "==> Untracked files"
git ls-files --others --exclude-standard

echo ""
echo "================================"
echo " AUDIT COMPLETE"
echo "================================"
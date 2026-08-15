#!/bin/bash

set -euo pipefail

echo "================================"
echo " CANTEEN VERIFY"
echo "================================"

echo ""
echo "==> Git status"
git status --short

echo ""
echo "==> Format"
dart format --set-exit-if-changed .

echo ""
echo "==> Analyze"
flutter analyze

echo ""
echo "==> Tests"
flutter test

echo ""
echo "==> Diff check"
git diff --check

echo ""
echo "==> Diff stat"
git diff --stat

echo ""
echo "================================"
echo " VERIFY PASSED"
echo "================================"
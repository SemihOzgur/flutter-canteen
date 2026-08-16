#!/bin/bash

set -euo pipefail

echo "================================"
echo " CANTEEN TEST PIPELINE"
echo "================================"

echo ""
echo "==> Formatting check"
dart format --set-exit-if-changed .

echo ""
echo "==> Flutter analyze"
flutter analyze

echo ""
echo "==> Flutter tests"
flutter test

echo ""
echo "================================"
echo " TEST PIPELINE PASSED"
echo "================================"
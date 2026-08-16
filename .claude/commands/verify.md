# VERIFY

Tam kalite kontrolü çalıştır.

```bash
.claude/scripts/verify.sh
```

Bu script sırasıyla şunları çalıştırır:

```text
git status --short
dart format --set-exit-if-changed .
flutter analyze
flutter test
git diff --check
git diff --stat
```

Herhangi bir adım başarısız olursa script durur.

Başarısızlık durumunda:

```text
FAIL → ROOT CAUSE → FIX → RETEST
```

Teknik hataları otomatik düzelt.

Business kararı gerekiyorsa DUR.

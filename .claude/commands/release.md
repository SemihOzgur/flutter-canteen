# RELEASE

Release öncesi kalite kapısını çalıştır.

Kontrol:

1. git status
2. branch
3. docs consistency
4. flutter analyze
5. dart format
6. flutter test
7. integration tests
8. database checks
9. regression review
10. scope audit
11. git diff

4–6 ve 11 için:

```bash
.claude/scripts/verify.sh
```

10 ve 11 için:

```bash
.claude/scripts/audit.sh
```

Merge/push/release operasyonunu kullanıcı açıkça istemediyse yapma.
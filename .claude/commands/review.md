# REVIEW

Bağımsız code review yap.

Kontrol:

- correctness
- architecture
- business invariants
- persistence
- security
- performance
- tests
- regression
- scope

İlk review'dan sonra ikinci pass yap.

CRITICAL/HIGH bulursan implementer'a geri dön.

Kapsam kontrolü için:

```bash
.claude/scripts/audit.sh
```

Ayrıntılı review protokolü: `.claude/agents/reviewer.md`

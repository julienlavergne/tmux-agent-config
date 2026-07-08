# Common Engineering Rules

## Code Quality (always)

- KISS: simplest solution that works; no premature optimisation
- DRY: extract repeated logic; introduce abstractions only when repetition is real
- YAGNI: no speculative features or abstractions
- Files: 200–400 lines typical, 800 max; organise by feature/domain, not by type
- Functions: <50 lines, one responsibility
- Nesting: max 4 levels — use early returns instead
- Errors: handle explicitly at every level; never silently swallow
- Immutability: prefer returning new values over mutating in place
- Input validation: validate all external data at system boundaries; fail fast

## Security (mandatory before every commit)

- [ ] No hardcoded secrets (API keys, tokens, passwords)
- [ ] All user inputs validated and sanitised
- [ ] Parameterised queries — no string-concatenated SQL
- [ ] Authentication and authorisation verified
- [ ] Error messages do not leak internal details (paths, stack traces, DB errors)
- If a security issue is found: STOP, fix CRITICAL before continuing, rotate any exposed secrets

## Testing

- TDD: write the test first (RED), minimal impl (GREEN), refactor (IMPROVE)
- 80%+ line coverage; focus on business logic
- Mocks for external systems only — never mock internal modules
- AAA structure: Arrange → Act → Assert
- Test names describe behaviour: `rejects_order_when_insufficient_stock`

## Git

Commit format: `<type>: <description>` — types: feat, fix, refactor, docs, test, chore, perf, ci

## Code Review

Block on CRITICAL (security vulnerability, data loss). Warn on HIGH (bug, quality). Inform on MEDIUM (maintainability).

Mandatory review when touching: auth/authorisation, user input handling, DB queries, file system ops, external API calls, cryptographic code.

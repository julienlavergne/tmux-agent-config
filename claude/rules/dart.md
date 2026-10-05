---
paths:
  - "**/*.dart"
  - "**/pubspec.yaml"
  - "**/analysis_options.yaml"
---
# Dart / Flutter Rules

## Formatting & Analysis

- `dart format` on all `.dart` files; enforce in CI: `dart format --set-exit-if-changed .`
- `dart analyze --fatal-infos`; no warnings suppressed without justification
- Line length: 80 chars; trailing commas on multi-line args for cleaner diffs

## Naming

- `camelCase`: variables, parameters, named constructors
- `PascalCase`: classes, enums, typedefs, extensions
- `snake_case`: file names, library names
- `SCREAMING_SNAKE_CASE`: top-level `const`
- Prefix private members with `_`
- Extension names describe the type: `StringExtensions`, not `MyHelpers`

## Immutability

- `final` for local variables; `const` for compile-time constants
- `const` constructors wherever all fields are `final`
- Return `List.unmodifiable` / `Map.unmodifiable` from public APIs
- `copyWith()` for state mutations in immutable state classes

## Null Safety

- Avoid `!` (bang operator) — prefer `?.`, `??`, pattern matching, or early-return null guards
- Reserve `!` only where a null value is a programming error and crashing is correct
- Avoid `late` unless initialisation before first use is guaranteed
- Use `required` for constructor parameters that must always be provided

```dart
// BAD
final name = user!.name;

// GOOD
final name = user?.name ?? 'Unknown';
// or Dart 3 pattern matching
final name = switch (user) {
  User(:final name) => name,
  null => 'Unknown',
};
```

## Sealed Types & Pattern Matching (Dart 3+)

```dart
sealed class AsyncState<T> { const AsyncState(); }
final class Loading<T> extends AsyncState<T> { const Loading(); }
final class Success<T> extends AsyncState<T> { const Success(this.data); final T data; }
final class Failure<T> extends AsyncState<T> { const Failure(this.error); final Object error; }

// Always exhaustive — no default/wildcard
return switch (state) {
  Loading() => const CircularProgressIndicator(),
  Success(:final data) => DataWidget(data),
  Failure(:final error) => ErrorWidget(error.toString()),
};
```

## Error Handling

- Specify exception types in `on` clauses — no bare `catch (e)`
- Never catch `Error` subtypes (programming bugs, should crash)
- Use `Result`-style types or sealed classes for recoverable errors

## Async

- Always `await` Futures or use `unawaited()` for intentional fire-and-forget
- Never mark a function `async` if it never `await`s
- Check `context.mounted` before using `BuildContext` after any `await` (Flutter 3.7+)

## Imports

- `package:` imports throughout — no relative `../` for cross-feature code
- Order: `dart:` → external `package:` → internal `package:` (same package)

## Architecture (Clean)

```
lib/
├── domain/        # Pure Dart — no Flutter, no external packages
│   ├── entities/
│   ├── repositories/   # Abstract interfaces
│   └── usecases/
├── data/          # Implements domain interfaces
│   ├── datasources/
│   ├── models/    # DTOs with fromJson/toJson
│   └── repositories/
└── presentation/  # Flutter widgets + state management
```

- Domain must not import `package:flutter` or any data-layer package
- Presentation calls use cases, not repositories directly

## State Management

Prefer BLoC/Cubit or Riverpod. Use `bloc_test` and `ProviderContainer` for unit tests respectively. Fakes over mocks for complex dependencies.

## Security

- No hardcoded secrets; use `--dart-define-from-file` for compile-time config
- Runtime secrets: `flutter_secure_storage` (Keychain/EncryptedSharedPreferences)
- HTTPS only; set timeouts on all HTTP clients
- Validate deep link URLs before navigation
- Never log sensitive data (`print(token)`)
- Release builds: `--obfuscate --split-debug-info`
- Android: `android:exported="false"` on components not requiring external access
- WebView: `JavaScriptMode.disabled` unless explicitly required; validate all navigation requests

## Testing

| Type | Tool | Location |
|------|------|----------|
| Unit | `dart:test` | `test/unit/` |
| Widget | `flutter_test` | `test/widget/` |
| Golden | `flutter_test` | `test/golden/` |
| Integration | `integration_test` | `integration_test/` |

- All state transitions must have tests: loading→success, loading→error, retry
- `flutter test --coverage`; target 80%+ on domain + state managers
- Run `flutter test --update-goldens` only for intentional visual changes

PostToolUse hooks to configure: `dart format $CLAUDE_FILE_PATHS`, `dart analyze`

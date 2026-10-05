---
paths:
  - "**/*.rs"
  - "**/Cargo.toml"
  - "**/Cargo.lock"
---
# Rust Rules

## Formatting & Linting

- `cargo fmt` before every commit; `cargo clippy -- -D warnings` (warnings = errors)
- 4-space indent, 100-char line width (rustfmt defaults)

## Naming

- `snake_case`: functions, methods, variables, modules, crates
- `PascalCase`: types, traits, enums, type parameters
- `SCREAMING_SNAKE_CASE`: constants and statics
- Lifetimes: short lowercase (`'a`); descriptive for complex cases (`'input`)

## Ownership & Borrowing

- Borrow (`&T`) by default; take ownership only when you need to store or consume
- Accept `&str` over `String`, `&[T]` over `Vec<T>` in function parameters
- Use `impl Into<String>` for constructors that need to own a `String`
- Never clone to satisfy the borrow checker — understand the root cause first

## Immutability

- `let` by default; `let mut` only when mutation is required
- Use `Cow<'_, T>` when a function may or may not need to allocate

## Error Handling

- `Result<T, E>` + `?` for propagation — no `unwrap()` in production code
- Libraries: typed errors with `thiserror`
- Applications: flexible context with `anyhow` + `.with_context(|| ...)?`
- Reserve `unwrap()` / `expect()` for tests and truly unreachable states

```rust
// Library error
#[derive(Debug, thiserror::Error)]
pub enum ConfigError {
    #[error("failed to read config: {0}")]
    Io(#[from] std::io::Error),
}

// Application error
fn load(path: &str) -> anyhow::Result<Config> {
    let s = std::fs::read_to_string(path)
        .with_context(|| format!("failed to read {path}"))?;
    toml::from_str(&s).with_context(|| format!("failed to parse {path}"))
}
```

## Iterators & Loops

- Iterator chains for transformations; `for` loops for complex control flow with early returns
- Prefer `.filter().map().collect()` over manual push loops

## Module Organisation

Organise by domain, not by type:
```
src/
├── auth/mod.rs, token.rs, middleware.rs
├── orders/mod.rs, model.rs, service.rs
└── db/mod.rs, pool.rs
```

## Visibility

- Default to private; `pub(crate)` for internal sharing; `pub` only for the crate's public API

## Unsafe

- Minimise `unsafe`; every block requires a `// SAFETY:` comment explaining all invariants
- Never use `unsafe` to bypass the borrow checker for convenience

## Patterns

**Repository trait:**
```rust
pub trait OrderRepository: Send + Sync {
    fn find_by_id(&self, id: u64) -> Result<Option<Order>, StorageError>;
    fn save(&self, order: &Order) -> Result<Order, StorageError>;
}
```

**Newtype for type safety:**
```rust
struct UserId(u64);
struct OrderId(u64);
```

**Enum state machine — make illegal states unrepresentable:**
```rust
enum ConnectionState {
    Disconnected,
    Connecting { attempt: u32 },
    Connected { session_id: String },
}
// Always match exhaustively — no wildcard `_` for business-critical enums
```

## Security

- Secrets via `std::env::var("KEY").context("KEY must be set")`; never hardcode
- Parameterised queries only (sqlx `.bind()`); never format user input into SQL
- Parse, don't validate: convert unstructured data to typed structs at the boundary
- `cargo audit` for CVEs; `cargo deny check` for license compliance
- Minimise `unsafe`; audit all `unsafe` during review

## Testing

- Unit tests: `#[cfg(test)]` modules in the same file
- Integration tests: `tests/` directory (each file = separate binary)
- Benchmarks: `benches/` with Criterion
- Use `rstest` for parameterised tests, `proptest` for property-based, `mockall` for mocks
- `#[tokio::test]` for async tests
- Coverage: `cargo llvm-cov --fail-under-lines 80`
- Test names: `creates_user_with_valid_email`, `rejects_order_when_insufficient_stock`

PostToolUse hooks to configure: `cargo fmt`, `cargo clippy`, `cargo check`

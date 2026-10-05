---
paths:
  - "**/*.cpp"
  - "**/*.hpp"
  - "**/*.cc"
  - "**/*.hh"
  - "**/*.cxx"
  - "**/*.h"
  - "**/CMakeLists.txt"
---
# C++ Rules

## Standard & Formatting

- Target C++17 minimum; prefer C++20/23 features where available
- `clang-format` enforced — run `clang-format -i <file>` before committing; no style debates
- `clang-tidy` for static analysis; treat warnings as errors in CI

## Naming

- Types/Classes: `PascalCase`
- Functions/Methods: `snake_case` (follow project convention)
- Constants: `kPascalCase` or `UPPER_SNAKE_CASE`
- Namespaces: `lowercase`
- Member variables: `snake_case_` (trailing underscore)

## Resource Management (RAII)

- No manual `new`/`delete` — use smart pointers
- `std::unique_ptr` for exclusive ownership; `std::shared_ptr` only when shared ownership is genuinely needed
- `std::make_unique` / `std::make_shared` over raw `new`
- Rule of Zero: prefer classes needing no custom destructor/copy/move
- Rule of Five: if you define any of the five special members, define all five

```cpp
class FileHandle {
public:
    explicit FileHandle(const std::string& path) : file_(std::fopen(path.c_str(), "r")) {}
    ~FileHandle() { if (file_) std::fclose(file_); }
    FileHandle(const FileHandle&) = delete;
    FileHandle& operator=(const FileHandle&) = delete;
private:
    std::FILE* file_;
};
```

## Modern C++

- `auto` when type is obvious from context
- `constexpr` for compile-time constants
- Structured bindings: `auto [key, value] = map_entry;`
- Pass small/trivial types by value; large types by `const&`; return by value (RVO/NRVO)

## Error Handling

- Exceptions for truly exceptional conditions
- `std::optional` for values that may not exist
- `std::expected` (C++23) or result types for expected failures

## Security

- `std::string` over `char*`; `std::array`/`std::vector` over C-style arrays
- `.at()` for bounds-checked access when safety matters
- Never `strcpy`, `strcat`, `sprintf` — use `std::string` or `fmt::format`
- Always initialise variables; avoid signed integer overflow
- `reinterpret_cast` only when absolutely necessary and documented
- Run sanitizers in CI: `cmake -DCMAKE_CXX_FLAGS="-fsanitize=address,undefined" ..`
- `cppcheck --enable=all src/` for additional analysis

## Testing

- Framework: GoogleTest (gtest/gmock) with CMake/CTest
- `cmake --build build && ctest --test-dir build --output-on-failure`
- Always run tests with sanitizers in CI
- Coverage: `--coverage` flag + lcov

PostToolUse hooks to configure: `clang-format -i`, `clang-tidy`, `cmake --build`

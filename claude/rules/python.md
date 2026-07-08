---
paths:
  - "**/*.py"
  - "**/*.pyi"
  - "**/pyproject.toml"
  - "**/tox.ini"
---
# Python Rules

## Formatting & Linting

- `ruff` for linting and formatting (replaces black + isort + flake8)
- `mypy` or `pyright` for type checking
- Follow PEP 8; type annotations on all function signatures

## Immutability

```python
from dataclasses import dataclass

@dataclass(frozen=True)
class User:
    name: str
    email: str

from typing import NamedTuple

class Point(NamedTuple):
    x: float
    y: float
```

## Patterns

**Protocol (duck typing without inheritance):**
```python
from typing import Protocol

class Repository(Protocol):
    def find_by_id(self, id: str) -> dict | None: ...
    def save(self, entity: dict) -> dict: ...
```

**Dataclass as DTO:**
```python
@dataclass
class CreateUserRequest:
    name: str
    email: str
    age: int | None = None
```

- Use context managers (`with`) for resource management
- Use generators for lazy evaluation and memory-efficient iteration

## Security

- Secrets via `os.environ["KEY"]` (raises `KeyError` if missing); never hardcode
- Use `bandit -r src/` for static security analysis
- Never pass user input directly into SQL; use parameterised queries

```python
import os
from dotenv import load_dotenv
load_dotenv()
api_key = os.environ["API_KEY"]
```

## Testing

- Framework: `pytest`
- Coverage: `pytest --cov=src --cov-report=term-missing` (target 80%+)
- Use `pytest.mark.unit` / `pytest.mark.integration` for categorisation
- Mocks for external systems only — never mock internal modules

PostToolUse hooks to configure: `ruff check --fix`, `mypy`; warn on `print()` in edited files

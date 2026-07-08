# User Environment

## System
- WSL2 Ubuntu on a Windows 11 desktop, always-on, located at home.
- Remote VSCode is commonly attached to workspaces from a laptop.

## Networking & Access
- This machine has SSH access to the user's laptop; the laptop also has SSH access back here.
- Full internet access is available. Allowed to read online docs, download from official distribution channels, or install from GitHub **with user approval**.
- Docker containers can be run and exposed externally for remote access from the laptop.

## Session Management
Claude itself runs inside a tmux session — no need to wrap individual commands, tools, or subagents in tmux. If the user asks to spawn a new Claude session, launch it as a separate process in its own tmux window or session.

### Background Session Naming Convention
All sessions must follow the format: `<device>-<foldername>-<agent>`
- `<device>`: `desktop` or `laptop` depending on hostname
- `<foldername>`: lowercase basename of the working directory (e.g. `home`, `telmara`)
- `<agent>`: `claude` or `copilot` depending on agent

Examples: `desktop-home-claude`, `desktop-game-copilot`, `laptop-home-claude`

Always start sessions with both `--name <name>` and `--remote-control <name>` so the Remote Control title (visible on Android) matches the session name visible in FleetView.

## Worktrees
Use `isolation: "worktree"` when spawning Agent tool calls for parallel or independent tasks.

## Languages & Stack
Primary languages and runtimes in use: Rust, Python, C++, Flutter, Docker.

## Project Layout
Projects live in `~/workspace/<project-name>/`. Each directory is an independent git repository hosted on github.com. Repositories contain only source code — no vendored dependencies, compiled artifacts, or runtime tools. Dependencies and environments are managed externally (tox/uv for Python, Cargo for Rust, etc.) and are never committed.

## Tooling Conventions
- **Python**: use `tox` + `uv` for dependency management and virtual environments. Do not use pip/venv directly.
- **Task runner**: use `just` to define and run project commands. Check the `justfile` before writing ad-hoc shell invocations.
- **Git & GitHub**: use `git` and the `gh` CLI. Repositories are hosted on github.com.

## Feature Development Philosophy

When asked to implement a feature, unless explicitly stated otherwise, always means a well-designed, tested, and fully integrated result — never a workaround, quick fix, or dirty solution. Quality takes priority over speed. The end result must look as if the feature was there from the beginning.

### Multi-Agent Workflow

Feature requests follow this agent pipeline, looping until all agents are satisfied (maximum 2 reviewer-triggered loops; beyond that, surface remaining issues to the user).

**Context handoff**: each agent writes its output to a file (e.g. `design.md`, test files) and the next agent receives the file path — never inline the previous output into the prompt.

1. **Architect / Designer** (`opus` class model)
   - Explores the codebase first using graphify (`graphify query/path/explain` if `graphify-out/graph.json` exists, otherwise build it with `/graphify .` first): identifies existing patterns, reuse opportunities, inter-module dependencies, and potential conflicts.
   - Designs the feature as a natural extension of the existing codebase.
   - Per-workspace design instructions take precedence when they exist.
   - Produces a clear interface with no circular dependencies, no code duplication, no feature creep, no spaghetti code, and high testability.
   - Output: `design.md` containing the interface design **and** a file-level implementation plan (which files/functions to create or modify, and in what order).
   - **The design must be approved by the user before any implementation begins.**

2. **Test Agent** (`sonnet` class model) — starts after design approval
   - Receives: path to `design.md`.
   - Writes or extends tests to cover the feature — tests are red at this stage.
   - Speciality: testability from a unit and component test perspective.
   - Avoids trivial unit tests; focuses on testing complete flows.
   - Mocks **only** external systems and dependencies — never internal modules.
   - Tests must be simple to write without large mock scaffolding.
   - Feeds back to the Architect if the design proves inconvenient to test; restarts from step 1.

3. **Developer** (`sonnet` class model) — starts after Test Agent completes
   - Receives: path to `design.md` and the test file paths.
   - Implements the planned changes following the design and implementation plan exactly.
   - Makes no structural or architectural decisions — escalates any ambiguity to the Architect.
   - Speciality: code conventions, language idioms, and modern practices.
   - Runs the tests; they must be green. If not: design issues go back to the Architect, test issues go back to the Test Agent.

4. **Reviewer** (`opus` class model)
   - Invokes the `/code-review` skill on the final diff.
   - Surfaces findings (security issues, secret leaks, anti-patterns, outdated practices) to the relevant agent and triggers another loop if needed.
   - If the loop count reaches 2, surfaces remaining findings to the user instead of looping again.

## Permissions
- Docker: available on the current user, no sudo needed.
- `sudo`: full rights are available but **require explicit user approval before each use**.

@RTK.md

## Codebase Navigation

When exploring or reasoning about a codebase, prefer the knowledge graph over manual grepping and file reading:

- **If `graphify-out/graph.json` exists in the project**: use `graphify query "<question>"`, `graphify path "<A>" "<B>"`, and `graphify explain "<concept>"` as the primary navigation tools. Do not grep or read files to answer structural questions the graph can already answer.
- **If the graph does not exist and significant exploration is needed** (e.g. understanding a new project, starting the Architect step): run `/graphify .` first to build it, then query it.
- **After code changes**: use `/graphify . --update` rather than rebuilding from scratch.

The `/graphify` skill (`~/.claude/skills/graphify/SKILL.md`) drives the full build pipeline. Invoke it when the user types `/graphify` or when building the graph for the first time.

# bigjsonl — Agent Instructions

## Project Overview

**bigjsonl** is a standalone, viewer-only tool for inspecting large JSONL (JSON Lines) files. It displays each line as its own syntax-highlighted document, making it easy to rapidly scan and read through files that are too large to comfortably open in a general-purpose editor or JSON viewer.

- **Language:** Swift
- **Package manager:** Swift Package Manager (SwiftPM)
- **Structure:** Single Swift Package with three targets — `BigJSONLCore` (shared library), `bigjsonl-cli` (CLI tool), `BigJSONLApp` (SwiftUI app)
- **CLI framework:** [`swift-argument-parser`](https://github.com/apple/swift-argument-parser)
- **Docs:** `docs/PROJECT_VISION.md` (vision), `docs/ARCHITECTURE.md` (design)

Read both `docs/PROJECT_VISION.md` and `docs/ARCHITECTURE.md` at the start of every major session to keep design decisions fresh.

---

## Core Workflow: Changelog-First Development

Every significant change must produce exactly **one git commit** and exactly **one CHANGELOG entry**. Do not batch unrelated changes into a single commit. Do not make commits without updating the changelog.

### Step-by-step process

1. **Understand the task** — read the relevant docs, explore the codebase
2. **Make changes** — edit files, create files, run `swift build` and `swift test`
3. **Update `CHANGELOG.md`** — add an entry under `[Unreleased]` describing *what* changed and *why* (see format below)
4. **Stage and commit** — `git add` the changed files, commit with a message that matches the changelog entry title
5. **Push when ready** — `git push` if applicable

### Commit message convention

```
<type>: <brief description>

[optional body with motivation or tradeoffs]
```

Types:
| Type | When to use |
|------|-------------|
| `feat` | New feature, capability, or public API addition |
| `fix` | Bug fix or behavior correction |
| `docs` | Documentation changes only (PROJECT_VISION.md, AGENTS.md, etc.) |
| `chore` | Tooling, config, CI, repo maintenance (Package.swift, .gitignore, etc.) |
| `refactor` | Code change that is neither a fix nor a feature |
| `test` | Adding or updating tests |

Examples:
```
feat: build line-offset index with lazy incremental scanning

docs: update PROJECT_VISION.md with SwiftUI + CLI architecture

fix: handle carriage returns in JSONL lines on macOS
```

---

## CHANGELOG.md Format

The file follows [Keep a Changelog](https://keepachangelog.com/) conventions.

### Structure

```markdown
# Changelog

## [Unreleased]

### Added
- New features and capabilities.

### Changed
- Changes to existing functionality.

### Fixed
- Bug fixes.

### Removed
- Removed features or dependencies.

## [0.1.0] — 2026-06-15

### Added
- Initial project structure and design docs.
- ...

[0.1.0]: https://github.com/rajibsingh/bigjsonl/releases/tag/v0.1.0
```

### Rules

- Every entry is a **one-line summary** followed by a **linked reference** when tied to a specific issue or decision.
- If the change has a related GitHub issue, append `([#N](issue-url))`.
- Every release section links to the GitHub compare URL at the bottom.
- The `[Unreleased]` section is always at the top — entries accumulate here until release time.

---

## Change Philosophy

This project values **minimal, precise changes** over sweeping rewrites.

- **Prefer small, targeted edits** — change only what the feature or fix requires, nothing more. Resist the urge to refactor unrelated code, rename variables for consistency, or "clean up" areas you weren't asked to touch.
- **One feature, one change.** If the request is "build a line-offset index," build the index — don't also restructure the file-reading pipeline, reformat the syntax highlighting, or rewrite the CLI argument definitions.
- **If a change feels too large, pause.** Can it be broken into smaller independent steps? Each step gets its own commit and changelog entry.
- **Default is to leave working code alone.** "It works, don't touch it" is a valid reason to leave something unchanged. Don't optimize or restructure code that isn't part of the task.
- **If you genuinely need to refactor** to make the feature possible (e.g., extracting a shared helper that both old and new code will use), that's different — but flag it in the commit message body and changelog entry as a separate concern.

When in doubt, ask: *"What is the smallest set of file changes that satisfies this request?"*

---

## Versioning

We use [SemVer](https://semver.org/) starting at `0.1.0`:

- **0.x** — MVP stage, breaking changes expected
- Minor bump for new features
- Patch bump for fixes

When cutting a release:
1. Rename `[Unreleased]` to the new version and add the date
2. Create a new empty `[Unreleased]` section above it
3. Tag the commit: `git tag v0.x.x && git push --tags`
4. Add the compare link at the bottom

---

## Git Hygiene

- **One commit per logical change.** If you're fixing a bug and adding a feature, that's two commits.
- **Commit messages are changelog entries.** The commit title should match the changelog entry text (or be very close).
- **Rebase locally if needed** — keep history clean before pushing.
- **Work on feature branches** for anything that takes more than one session (`git checkout -b feat/my-thing`).

---

## Swift Package Conventions

### Project structure

```
bigjsonl/
├── Sources/
│   ├── BigJSONLCore/       ← shared library (line-offset index, file IO, grep/rg, JSON parsing, syntax tokens)
│   ├── bigjsonl-cli/       ← CLI tool entry point (swift-argument-parser)
│   └── BigJSONLApp/        ← SwiftUI app entry point
├── Tests/
│   ├── BigJSONLCoreTests/  ← unit tests for the core library
│   └── BigJSONLAppTests/   ← UI tests (if applicable)
├── Package.swift
├── CHANGELOG.md
├── AGENTS.md
└── docs/
    └── PROJECT_VISION.md
```

### Building and testing

```bash
# Build everything
swift build

# Build a specific target
swift build --target BigJSONLCore

# Run tests
swift test

# Run a specific test
swift test --filter LineOffsetIndexTests

# Build the CLI for release
swift build -c release --target bigjsonl-cli
```

### Code style

- Follow [Swift API Design Guidelines](https://www.swift.org/documentation/api-design-guidelines/).
- Use `// MARK:` comments to organize files by logical sections.
- All public API in `BigJSONLCore` should have doc comments (`///`).
- Prefer value types (`struct`) over reference types (`class`) unless shared mutable state is required.
- Use `Result<T, Error>` or `throws` for error handling in the core library — the UI layer decides how to present errors.

### Dependency management

- Keep dependencies minimal. The core library should have **zero external dependencies** to keep the package lightweight and fast to build.
- The CLI target depends on `swift-argument-parser` (Apple-maintained, essentially standard library).
- The SwiftUI app target depends only on system frameworks (SwiftUI, AppKit).
- Before adding any third-party dependency, ask: "Can I achieve this with ~50 lines of Foundation/stdlib code?" If yes, write it inline.

---

## Living Documentation

`docs/PROJECT_VISION.md` and `docs/ARCHITECTURE.md` are not static — they evolve with the codebase.

### Read first, then update

At the start of each major session, read both docs to recontextualize:
- `docs/PROJECT_VISION.md` — why this project exists, what problem it solves
- `docs/ARCHITECTURE.md` — how the system is structured, key design decisions

After making any significant code change, **update the relevant doc** to reflect it:
- **Architecture changes** (new target, different file-IO strategy, different search mechanism) → update `docs/ARCHITECTURE.md`. Update the component descriptions, data flow, or design decisions log.
- **Scope or priority changes** (a deferred feature is now being built, a new platform is targeted) → update `docs/PROJECT_VISION.md`. Reflect the change in the open questions or design principles.
- **Small implementation details** (different CLI flag name, different token representation) → no docs update needed unless it contradicts a stated design decision.

### Rules

- Every commit that changes code should be preceded (or accompanied) by a docs update if the code changes the architecture or vision.
- Changelog entries for docs updates use the `docs` type. Example: `docs: update ARCHITECTURE.md with lazy indexing design`.
- If the change contradicts a previous design decision, call that out explicitly in both the doc update and the commit message.
- The AGENTS.md itself can also need updates — if you find yourself repeating instructions to yourself, fold them into AGENTS.md.

---

## First-Time Setup

When starting a new project directory or beginning a fresh session:

1. Initialize `CHANGELOG.md` with the initial release entry for any existing work
2. Create initial `git commit` if none exists (e.g., `chore: initialize project structure`)
3. Cross-reference the first commit SHA in the changelog if helpful
4. Run `swift build` once to verify the package compiles

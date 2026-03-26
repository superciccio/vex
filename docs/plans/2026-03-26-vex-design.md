# vex — a test runner for humans and LLMs

## What

A CLI test runner that reads `.test.md` files — Markdown documents where headings are test names and fenced code blocks are actions and expectations. Output is minimal for humans, structured JSON for LLMs.

## Why

Existing test frameworks produce output designed for one audience. vex targets both:
- Humans get clean, contextual failure reports with zero noise from passing tests
- LLMs get structured JSON with enough context (command, variables, file location, neighboring tests) to propose fixes

The test format is Markdown — humans already know it, LLMs generate and consume it natively, and test files double as readable documentation.

## Architecture

```
vex CLI
├── Markdown Parser     → reads .test.md files into test suites
├── Variable Engine     → resolves {{vars}} from frontmatter + env
├── Shell Backend       → executes `run` blocks via shell
├── Assertion Engine    → compares actual vs expected
└── Reporter            → human (default) or JSON output
```

Future backends (Playwright, pytest, etc.) would slot in alongside the shell backend. The Markdown format is backend-agnostic — action block types (`run`, `navigate`, `click`, `fill`) determine which backend handles them.

## Test file format

A `.test.md` file is a Markdown document with optional YAML frontmatter:

```markdown
---
base_url: http://localhost:8080
timeout: 5s
---

# Suite Name

## test name
​```run
curl -s {{base_url}}/items
​```
​```expect
[]
​```
```

### Structure

- `#` heading = suite name
- `##` heading = test name
- Fenced code blocks = actions and assertions

### Action blocks

| Block tag | Meaning |
|-----------|---------|
| `run` | Execute a shell command |
| `run as:name` | Execute and capture output as `{{name}}` (post-MVP) |

### Assertion blocks

| Block tag | Meaning |
|-----------|---------|
| `expect` | Stdout must match exactly |
| `expect.status` | Exit code must match |
| `expect.stderr` | Stderr must match exactly |
| `expect.contains` | Stdout must contain substring |

### Variables

- `{{var}}` in any block is replaced before execution
- Sources (in priority order):
  1. Captured variables from `run as:name` (post-MVP)
  2. Frontmatter key-value pairs
  3. Environment variables (`{{ENV_VAR}}`)

## Output

### Human mode (default)

Passing tests are silent. Only failures shown:

```
$ vex run tests/api.test.md

✗ Items API > create fails without body
  ┄ expected status: 400
  ┄ actual status:   0
  ┄ stdout:
  ┄   {"error":"bad request"}
  ┄ at: tests/api.test.md:22

4 passed, 1 failed
```

### JSON mode (`--output json`)

One JSON object per line (JSONL):

```json
{
  "file": "tests/api.test.md",
  "suite": "Items API",
  "test": "create fails without body",
  "status": "fail",
  "line": 22,
  "description": "## create fails without body",
  "command": "curl -s http://localhost:8080/items -X POST",
  "assertions": [
    {"type": "status", "expected": "400", "actual": "0"}
  ],
  "stdout": "{\"error\":\"bad request\"}",
  "stderr": "",
  "duration_ms": 12,
  "variables": {"base_url": "http://localhost:8080"},
  "context": {
    "prev_test": "create an item",
    "next_test": "delete returns 404 for missing"
  }
}
```

### Filtering

- `--failures-only` — only emit failing tests (applies to both human and JSON mode)
- Default: all tests emitted in JSON mode, only failures in human mode

## CLI interface

```
vex run <path>              run tests in file or directory
vex run tests/              run all .test.md files in directory
vex run tests/api.test.md   run a single file

Options:
  --output human            minimal failure report (default)
  --output json             JSONL to stdout
  --failures-only           only output failing tests
```

## Project structure

```
andcaml/
├── dune-project
├── bin/
│   ├── dune
│   └── main.ml              vex CLI entry point
├── lib/
│   ├── dune
│   ├── frontmatter.ml       YAML frontmatter parser
│   ├── markdown.ml           .test.md parser → test suite
│   ├── types.ml              shared types (suite, test, assertion, result)
│   ├── variables.ml          {{var}} substitution engine
│   ├── runner.ml             shell backend — execute run blocks
│   ├── assertions.ml         compare actual vs expected
│   ├── report_human.ml       human-readable output
│   └── report_json.ml        JSONL output
├── dogfood/
│   ├── server/
│   │   ├── dune
│   │   └── main.ml           simple in-memory CRUD HTTP server
│   └── tests/
│       └── items.test.md     vex tests for the CRUD server
└── docs/
    └── plans/
        └── 2026-03-26-vex-design.md
```

## Dogfood: CRUD server

A minimal HTTP server in OCaml with in-memory storage:

```
GET    /items       → list all items as JSON array
POST   /items       → create item, return with generated id
GET    /items/:id   → get one item or 404
DELETE /items/:id   → delete item or 404
```

No database, no persistence, no framework. Just enough to have a real target for vex tests.

## MVP scope (v0.1)

Included:
- Parse `.test.md` files (frontmatter + fenced blocks)
- `run` blocks (shell backend)
- `expect`, `expect.status`, `expect.stderr`, `expect.contains` assertions
- `{{var}}` substitution from frontmatter + environment variables
- Human output (default) + JSON output (`--output json`)
- `--failures-only` flag
- Dogfood CRUD server + test file

Not yet:
- `run as:name` (captured variables between steps)
- `***` wildcards in expectations
- Playwright or other backends
- `--output both`
- Timeout support
- Directory scanning (single file only in v0.1)

## Tech decisions

- **OCaml** — host language, the whole point is learning it
- **No external deps for MVP** — parse markdown and frontmatter ourselves. Good OCaml practice, avoids dependency complexity
- **dune** — build system
- **In-memory CRUD server** — use `Unix` module for raw TCP, or a lightweight HTTP library (decide during implementation)

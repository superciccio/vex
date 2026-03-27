# vex

A literate API test runner. Write tests as Markdown, assert with a built-in expression language. No external runtimes needed.

```
$ vex run tests/api.test.md
3 passed

$ vex run tests/api.test.md --output json
{"file":"tests/api.test.md","suite":"Users","test":"get by id","status":"pass",...}
```

## Why vex?

- **Tests are documentation.** A `.test.md` file reads like a spec in your editor and runs as a test suite in CI.
- **No runtime dependencies.** Assertions use a built-in mini-ML evaluator — no Python, Node, or anything else on the PATH.
- **LLM-friendly.** JSON output mode gives structured results that LLMs can reason about. `vex learn` generates assertions automatically.
- **Curl-native.** Auto-captures HTTP headers from curl commands for assertion.

## Install

### Binary (recommended)

Download from [Releases](https://github.com/superciccio/vex/releases):

```bash
# Linux (x86_64)
curl -L -o vex https://github.com/superciccio/vex/releases/latest/download/vex-linux-x86_64
chmod +x vex
sudo mv vex /usr/local/bin/

# macOS (Apple Silicon)
curl -L -o vex https://github.com/superciccio/vex/releases/latest/download/vex-macos-arm64
chmod +x vex
sudo mv vex /usr/local/bin/
```

### From source

Requires OCaml (>= 4.14) and opam:

```bash
git clone https://github.com/superciccio/vex.git
cd vex
opam install . --deps-only
dune build
dune install      # installs `vex` to your PATH
```

## Quick start

Create `tests/hello.test.md`:

````markdown
# Hello API

## returns a greeting
> **run**
```bash
curl -s https://httpbin.org/get?greeting=hello
```
> **assert**
```ocaml
assert (vex.status = 0);
assert (args.greeting = "hello");
assert (url |> starts_with "https://")
```
````

Run it:

```
$ vex run tests/hello.test.md
1 passed
```

## Writing tests

A `.test.md` file is plain Markdown with a specific structure:

````
# Suite Name              <- level-1 heading = test suite
## Test Name              <- level-2 heading = individual test

> **run**                 <- command to execute
```bash
curl -s https://api.example.com/items
```

> **assert**              <- assertions (mini-ML)
```ocaml
assert (vex.status = 0);
assert (items |> length > 0);
assert (items.[0].name |> is_string)
```
````

### Assertion types

| Label | What it does |
|-------|-------------|
| `> **assert**` | Mini-ML expression block (recommended) |
| `> **expect** \`exact\`` | stdout must match exactly |
| `> **expect** \`contains\`` | stdout must contain substring |
| `> **expect** \`status\`` | exit code must match |
| `> **expect** \`stderr\`` | stderr must match exactly |
| `> **assert** \`script\`` | Run an external script (Python, bash, etc.) |

You can mix multiple assertion blocks per test.

### Variables

Define variables in YAML frontmatter:

````markdown
---
base_url: https://api.example.com
api_key: my-key
---

# My API

## list items
> **run**
```bash
curl -s {{base_url}}/items -H 'Authorization: {{api_key}}'
```
````

Variables resolve in this order (highest priority first):

1. Test file frontmatter
2. Nearest `vex.yaml` (in the test's directory)
3. `vex.yaml` files up the directory tree
4. Environment variables

This means you can put shared config in a `vex.yaml` next to your tests:

```yaml
# tests/vex.yaml
api_url: https://petstore3.swagger.io/api/v3
api_key: special-key
```

## The mini-ML assertion language

Assert blocks use a small expression language purpose-built for API testing. JSON response fields are auto-spread into scope — you access them directly by name.

### Environment

Every assert block gets:

| Binding | Type | What it is |
|---------|------|-----------|
| `vex.status` | int | Process exit code (0 = success for curl) |
| `vex.stdout` | string | Raw stdout |
| `vex.stderr` | string | Raw stderr |
| `vex.headers` | headers | HTTP response headers (curl only, auto-captured) |
| *top-level JSON keys* | any | Auto-spread from stdout. `{"name":"vex"}` gives you `name` directly |
| `items` | list | If stdout is a JSON array, it's bound to `items` |

### Syntax

```ocaml
(* Assertions -- all are checked, failures don't short-circuit *)
assert (vex.status = 0);
assert (name = "vex");

(* Let bindings scope over everything that follows *)
let first = data.animes.[0] in
assert (first.name |> is_string);
assert (first.score > 7.0);

(* Comparisons: = <> > < >= <= *)
assert (count >= 1);
assert (status <> "error");

(* Pipe operator *)
assert (items |> length > 0);
assert (url |> starts_with "https://");
assert (message |> contains "success");

(* Negation *)
assert (not (status = "deleted"));

(* Lambdas with each/any *)
items |> each (fun item ->
  assert (item.id |> is_int);
  assert (item.name |> is_string)
);

items |> any (fun item ->
  item.status = "active"
);

(* Shape matching -- validates structure of nested objects *)
assert (user |> matches_shape {
  id: int,
  name: string,
  email: string,
  address: { city: string, zip: string },
  tags: [string],
  deleted_at: string?
});

(* Nullable types: string? int? number? bool? any? *)
assert (optional_field |> matches_shape string?);

(* Comments *)
(* this is a comment *)
```

### Builtins

| Function | Works on | Example |
|----------|----------|---------|
| `length` | list, string | `items \|> length = 3` |
| `contains` | string | `name \|> contains "vex"` |
| `starts_with` | string | `url \|> starts_with "https://"` |
| `ends_with` | string | `path \|> ends_with ".json"` |
| `matches` | string | `id \|> matches "^[a-f0-9]+$"` |
| `is_string` | any | `name \|> is_string` |
| `is_int` | any | `count \|> is_int` |
| `is_float` | any | `score \|> is_float` |
| `is_bool` | any | `active \|> is_bool` |
| `is_null` | any | `deleted_at \|> is_null` |
| `is_list` | any | `tags \|> is_list` |
| `is_object` | any | `meta \|> is_object` |
| `each` | list | `items \|> each (fun x -> assert (x.id \|> is_int))` |
| `any` | list | `items \|> any (fun x -> x.active = true)` |
| `matches_shape` | any | `user \|> matches_shape { name: string }` |

### Headers

For curl commands, vex automatically captures HTTP response headers. Access them via `vex.headers` with normalized names (lowercased, hyphens become underscores):

```ocaml
assert (vex.headers.content_type |> contains "application/json");
assert (vex.headers.cache_control = "no-cache")
```

### Shape matching

`matches_shape` validates the structure of a value against a type descriptor. It checks **all** fields and **all** list elements, collecting every mismatch:

```ocaml
(* Primitive shapes *)
string  int  number  bool  any

(* Nullable -- matches the type OR null *)
string?  int?

(* Object -- all listed fields must be present and match *)
{ name: string, age: int }

(* List -- every element must match the inner shape *)
[string]                        (* list of strings *)
[{ id: int, name: string }]    (* list of objects *)

(* Nested *)
{
  user: { name: string, email: string },
  posts: [{ title: string, tags: [string] }]
}
```

When a shape check fails, you get detailed error paths:

```
  user |> matches_shape {...}:
    .email: expected string, got null
    .posts.[2].title: expected string, got int
```

## Output formats

### Human (default)

Only shows failures. Passing tests are silent.

```
$ vex run tests/api.test.md

  ✗ Pet endpoints > get pet by id
    status = "available": expected true, got false
    at: tests/petstore/pets.test.md:18

2 passed, 1 failed
```

### JSON

One JSON object per line (JSONL). Includes everything an LLM needs to diagnose failures:

```
$ vex run tests/api.test.md --output json
```

```json
{
  "file": "tests/api.test.md",
  "suite": "Pet endpoints",
  "test": "get pet by id",
  "status": "fail",
  "line": 18,
  "command": "curl -s 'https://petstore3.swagger.io/api/v3/pet/1'",
  "assertions": [{"type": "expr", "passed": false, "actual": "..."}],
  "stdout": "{\"id\":1,\"name\":\"doggie\",\"status\":\"sold\"}",
  "exit_code": 0,
  "duration_ms": 230,
  "variables": {"api_url": "https://petstore3.swagger.io/api/v3"},
  "context": {"prev_test": "find pets by status", "next_test": "create a pet"}
}
```

## Learn mode

Don't want to write assertions by hand? Let vex do it:

```
$ vex learn tests/api.test.md
learned: tests/api.test.md
```

This runs every test that doesn't have assertions yet, analyzes the response, and inserts a mini-ML assert block with shape checks and type validations. Review and edit the generated assertions — they're a starting point, not gospel.

## CLI reference

```
vex run <file.test.md>       Run tests
vex learn <file.test.md>     Auto-generate assertions for tests without them

Options:
  --output human             Failures only, for humans (default)
  --output json              JSONL, for LLMs and CI
  --failures-only            Only include failing tests in output
  --help                     Show help
```

## Real-world example

Testing a GraphQL API (from `dogfood/tests/shikimori.test.md`):

````markdown
---
api_url: https://shikimori.one/api/graphql
---

# Shikimori GraphQL API

## search anime by name
> **run**
```bash
curl -s '{{api_url}}' \
  -H 'Content-Type: application/json' \
  -d '{"query":"{ animes(search: \"bakemono\", limit: 1) { id name score genres { name kind } } }"}'
```
> **assert**
```ocaml
assert (vex.status = 0);
assert (data.animes |> length > 0);
let first = data.animes.[0] in
assert (first |> matches_shape {
  id: string,
  name: string,
  score: number,
  genres: [{ name: string, kind: string }]
});
assert (first.score > 0.0)
```
````

## License

MIT

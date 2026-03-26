# Mini-ML Evaluator for vex assert blocks

## Vision

Vex is a literate testing notebook. Markdown cells for narrative, shell cells
for execution, OCaml-flavored cells for assertions. The mini-ML evaluator is the
engine that runs assert blocks natively inside vex — no external interpreters.

## Design principles

- Markdown stays stupidly simple: headings, prose, fenced blocks
- All assertion logic lives in the mini-ML cells
- Old assertion types (exact, contains, status, stderr) become mini-ML expressions
- `matches_shape` is the centerpiece — one structural check replaces 170+ lines
- Error output is dual: human-readable + JSONL for LLMs
- Vex is curl-native: headers captured automatically

## Language grammar

Two syntactic categories: expressions (compute values) and shapes (describe structure).

```
expr :=
  | ident                          -- x, status, stdout
  | expr.field                     -- data.animes
  | expr.[n]                       -- data.animes.[0]
  | expr |> expr                   -- pipe
  | expr op expr                   -- =, <>, >, <, >=, <=
  | fun ident -> expr              -- lambda, only inside each/any
  | let ident = expr in expr       -- binding
  | assert (expr)                  -- assertion
  | f expr                         -- function application
  | "literal" | 123 | 1.5 | true  -- literals
  | not expr                       -- negation

shape :=
  | string | int | number | bool | any   -- primitive types
  | string? | int? | ...                  -- nullable variants
  | { field: shape, ... }                 -- object shape
  | [shape]                               -- list where every element matches

op := = | <> | > | < | >= | <=
```

No if/else, no match, no recursive functions, no user-defined functions
(except lambdas in each/any).

## AST types

```ocaml
type value =
  | VNull
  | VBool of bool
  | VInt of int
  | VFloat of float
  | VString of string
  | VList of value list
  | VObject of (string * value) list
  | VHeaders of (string * string) list

type shape =
  | SString | SInt | SNumber | SBool | SAny
  | SNullable of shape
  | SObject of (string * shape) list
  | SList of shape

type expr =
  | Lit of value
  | Var of string
  | Dot of expr * string
  | Index of expr * int
  | Pipe of expr * expr
  | BinOp of op * expr * expr
  | Not of expr
  | App of string * expr
  | Lambda of string * expr
  | Let of string * expr * expr
  | Assert of expr
  | ShapeCheck of expr * shape

and op = Eq | Neq | Gt | Lt | Gte | Lte
```

## Tokens

```ocaml
type token =
  | IDENT of string
  | INT of int
  | FLOAT of float
  | STRING of string
  | TRUE | FALSE
  | LET | IN | FUN | ASSERT | NOT
  | DOT | LBRACKET | RBRACKET
  | LPAREN | RPAREN
  | LBRACE | RBRACE
  | COLON | COMMA
  | PIPE_GT
  | EQ | NEQ | GT | LT | GTE | LTE
  | ARROW
  | SEMI
  | QUESTION
  | EOF
```

## Parser

Hand-rolled recursive descent. Precedence levels (lowest to highest):

1. let / assert (statement-level)
2. |> (pipe, left-associative)
3. =, <>, >, <, >=, <=
4. not
5. function application (f x)
6. dot access, index access (.field, .[n])
7. atoms (literals, idents, parens, shape literals)

## Stdlib

Comparisons: =, <>, >, <, >=, <=
Type checks: is_string, is_int, is_float, is_bool, is_null, is_list, is_object
String: contains, starts_with, ends_with, matches, length
List: length, each, any
Shape: matches_shape
Control: let...in, assert, |>, not

## Evaluation model

Tree-walk interpreter: eval : env -> expr -> (value, error) result

### Initial environment

Vex runs curl, captures stdout, stderr, exit code, headers (via -D tempfile).
Then builds env:

| Name       | Type     | Source                          |
|------------|----------|---------------------------------|
| stdout     | string   | raw stdout                      |
| stderr     | string   | raw stderr                      |
| status     | int      | exit code                       |
| headers    | map      | parsed from curl -D tempfile    |
| ...spread  | varies   | all top-level JSON keys from stdout |

If stdout is {"data": {"animes": [...]}, "errors": null}, env gets
data and errors as top-level bindings.

### Assert behavior

Asserts don't stop on first failure — all asserts in a block are evaluated,
all failures collected and reported at once.

### matches_shape behavior

Walks value and shape together recursively. Collects all mismatches with
dot-path, expected type, got type. Reports everything at once.

## Error reporting

### Human output

```
FAIL  search anime by name (shikimori.test.md:7)

  ✗ assert (status = 0)
    got: 1

  ✗ assert (data.animes.[0].score > 5.0)
    got: 3.2

  ✗ data.animes.[0] |> matches_shape {...}
    .episodes: expected int, got string
    .airedOn.day: missing field
    .genres.[0].kind: expected string, got null
```

### JSONL output

```json
{"test":"search anime by name","file":"shikimori.test.md","line":7,"passed":false,"assertions":[
  {"expr":"status = 0","passed":false,"expected":"0","got":"1","kind":"comparison"},
  {"expr":"data.animes.[0].score > 5.0","passed":false,"expected":">5.0","got":"3.2","kind":"comparison"},
  {"expr":"matches_shape","passed":false,"kind":"shape","mismatches":[
    {"path":".episodes","expected":"int","got":"string"},
    {"path":".airedOn.day","expected":"field present","got":"missing"},
    {"path":".genres.[0].kind","expected":"string","got":"null"}
  ]}
]}
```

## Integration with existing vex

### types.ml — simplify assertion kinds

```ocaml
type assertion_kind =
  | Expr                   (* mini-ML assert block *)
  | Script of string       (* legacy external script *)
```

Drop Exact, Contains, Status, Stderr.

### markdown.ml

- Bare `> **assert**` → Expr block (new evaluator)
- `> **assert** \`python\`` / `> **assert** \`script\`` → Script (legacy)
- Old-style expect blocks kept for backwards compat

### runner.ml — new branch

```ocaml
| Types.Expr ->
  let env = build_env stdout stderr exit_code headers in
  Eval.run env a.expected
```

### learn.ml — emit mini-ML instead of Python

generate_script becomes generate_miniml. Infers shape from response,
emits matches_shape literal. Output is 10-20 lines instead of 170.

### New files

```
lib/
  mini_lexer.ml     -- string -> token list
  mini_parser.ml    -- token list -> expr list
  eval.ml           -- env -> expr list -> result list
  shape.ml          -- shape matching + shape inference for learn
```

## Curl integration

Vex is curl-native. The runner:

1. Detects curl commands in run blocks
2. Automatically appends -D <tempfile> to capture headers
3. Parses header file into (name, value) pairs
4. Binds as `headers` in eval env
5. Normalizes header names to lowercase + underscore (content-type → content_type)

Non-curl commands: headers is an empty map, everything else works the same.

## Example: shikimori test after migration

```markdown
---
api_url: https://shikimori.one/api/graphql
---

# Shikimori GraphQL API

## search anime by name
> **run**
```bash
curl -s '{{api_url}}' -H 'Content-Type: application/json' \
  --data-binary '{"query":"{ animes(search: \"bakemono\", limit: 1) { id name score kind genres { id name kind } studios { id name } } }"}'
```

> **assert**
```ocaml
assert (status = 0);
assert (headers.content_type |> contains "application/json");
let first = data.animes.[0] in
assert (first.name |> is_string);
assert (first.score > 0.0);
assert (first |> matches_shape {
  id: string, name: string, score: number,
  kind: string,
  genres: [{ id: string, name: string, kind: string }],
  studios: [{ id: string, name: string }]
})
```
```

## Build order

1. Lexer + parser + eval (core evaluator, test with inline strings)
2. Shape matching (matches_shape + shape inference)
3. Curl header capture (runner changes)
4. Integration (wire into runner.ml, markdown.ml, types.ml)
5. Learn rewrite (emit mini-ML instead of Python)
6. Migrate dogfood tests

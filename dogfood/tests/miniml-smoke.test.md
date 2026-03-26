# Mini-ML evaluator smoke test

## echo json and check shape
> **run**
```bash
echo '{"name":"vex","version":1,"tags":["test","ocaml"],"meta":{"author":"andrea","active":true}}'
```
> **assert**
```ocaml
assert (status = 0);
assert (name = "vex");
assert (version = 1);
assert (tags |> length = 2);
assert (meta.author = "andrea");
assert (meta.active = true);
assert (meta |> matches_shape { author: string, active: bool })
```

## check string builtins
> **run**
```bash
echo '{"url":"https://example.com/api","message":"hello world"}'
```
> **assert**
```ocaml
assert (url |> starts_with "https://");
assert (url |> contains "example");
assert (message |> ends_with "world")
```

## let bindings work
> **run**
```bash
echo '{"items":[{"id":1,"name":"first"},{"id":2,"name":"second"}]}'
```
> **assert**
```ocaml
let first = items.[0] in
assert (first.id = 1);
assert (first.name = "first");
assert (items |> length = 2);
assert (items.[1].name = "second")
```

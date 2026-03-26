# Store endpoints

## get inventory
> **run**
```bash
curl -s '{{api_url}}/store/inventory' -H 'api_key: {{api_key}}'
```
> **assert**
```ocaml
assert (vex.status = 0);
assert (vex.stdout |> is_string)
```

## place an order
> **run**
```bash
curl -s -X POST '{{api_url}}/store/order' -H 'Content-Type: application/json' -d '{"petId":1,"quantity":1,"status":"placed","complete":false}'
```
> **assert**
```ocaml
assert (vex.status = 0);
assert (id |> is_int);
assert (petId = 1);
assert (quantity = 1);
assert (complete = false)
```

## get order by id
> **run**
```bash
curl -s '{{api_url}}/store/order/1'
```
> **assert**
```ocaml
assert (vex.status = 0);
assert (id |> is_int);
assert (petId |> is_int)
```

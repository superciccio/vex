# Pet endpoints

## find pets by status
> **run**
```bash
curl -s '{{api_url}}/pet/findByStatus?status=available' -H 'api_key: {{api_key}}'
```
> **assert**
```ocaml
assert (vex.status = 0);
assert (items |> length > 0);
assert (items.[0] |> matches_shape {
  id: int, name: string, photoUrls: [string], status: string
})
```

## get pet by id
> **run**
```bash
curl -s '{{api_url}}/pet/1' -H 'api_key: {{api_key}}'
```
> **assert**
```ocaml
assert (vex.status = 0);
assert (id |> is_int);
assert (name |> is_string);
assert (photoUrls |> is_list);
assert (status = "available")
```

## create a pet
> **run**
```bash
curl -s -X POST '{{api_url}}/pet' -H 'api_key: {{api_key}}' -H 'Content-Type: application/json' -d '{"name":"vex-test-dog","photoUrls":["http://example.com/dog.jpg"],"status":"available"}'
```
> **assert**
```ocaml
assert (vex.status = 0);
assert (id |> is_int);
assert (name = "vex-test-dog");
assert (photoUrls.[0] |> contains "dog.jpg");
assert (status = "available")
```

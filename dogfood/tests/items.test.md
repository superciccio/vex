---
base_url: http://localhost:8080
---

# Items CRUD

## list is empty initially

> **run** `shell`
```bash
curl -s {{base_url}}/items
```
> **expect** `exact`
```json
[]
```

## create an item

> **run** `shell`
```bash
curl -s -X POST {{base_url}}/items -d '{"name":"learn ocaml"}'
```
> **expect** `contains`
```
"id"
```
> **expect** `contains`
```
"name"
```

## list has one item after create

> **run** `shell`
```bash
curl -s {{base_url}}/items
```
> **expect** `contains`
```
learn ocaml
```

## get item by id

> **run** `shell`
```bash
curl -s {{base_url}}/items/1
```
> **expect** `contains`
```json
"id":1
```

## delete item

> **run** `shell`
```bash
curl -s -X DELETE {{base_url}}/items/1
```
> **expect** `contains`
```
"deleted"
```

## deleted item returns not found

> **run** `shell`
```bash
curl -s {{base_url}}/items/1
```
> **expect** `exact`
```json
{"error":"not found"}
```

## list is empty after delete

> **run** `shell`
```bash
curl -s {{base_url}}/items
```
> **expect** `exact`
```json
[]
```

## create and validate structure with python

> **run** `shell`
```bash
curl -s -X POST {{base_url}}/items -d '{"name":"vex test","priority":42}'
```
> **assert** `script`
```python
import json, os

data = json.loads(os.environ["VEX_STDOUT"])

assert "id" in data, "response must have an id"
assert isinstance(data["id"], int), "id must be an integer"
assert data["name"] == "vex test", f"name should be 'vex test', got '{data['name']}'"
assert data["priority"] == 42, f"priority should be 42, got {data['priority']}"
```

---
base_url: http://localhost:8080
---

# Learn Demo

## list items
> **run** `shell`
```bash
curl -s {{base_url}}/items
```
> **assert** `script`
```python
import json, os

assert int(os.environ["VEX_STATUS"]) == 0, "expected exit code 0"

data = json.loads(os.environ["VEX_STDOUT"])

assert isinstance(data, list), "data should be array"
# length was: 0
```

## create an item
> **run** `shell`
```bash
curl -s -X POST {{base_url}}/items -d '{"name":"learned item","priority":7,"active":true}'
```
> **assert** `script`
```python
import json, os

assert int(os.environ["VEX_STATUS"]) == 0, "expected exit code 0"

data = json.loads(os.environ["VEX_STDOUT"])

assert isinstance(data, dict), "data should be object"
assert "id" in data, "missing field: id"
assert isinstance(data["id"], int), "id should be integer"
assert "name" in data, "missing field: name"
assert isinstance(data["name"], str), "data.name should be string"
# value was: "learned item"
assert "priority" in data, "missing field: priority"
assert isinstance(data["priority"], int), "data.priority should be integer"
# value was: 7
assert "active" in data, "missing field: active"
assert data["active"] == True, "data.active should be True"
```

## get the created item
> **run** `shell`
```bash
curl -s {{base_url}}/items/1
```
> **assert** `script`
```python
import json, os

assert int(os.environ["VEX_STATUS"]) == 0, "expected exit code 0"

data = json.loads(os.environ["VEX_STDOUT"])

assert isinstance(data, dict), "data should be object"
assert "id" in data, "missing field: id"
assert isinstance(data["id"], int), "id should be integer"
assert "name" in data, "missing field: name"
assert isinstance(data["name"], str), "data.name should be string"
# value was: "learned item"
assert "priority" in data, "missing field: priority"
assert isinstance(data["priority"], int), "data.priority should be integer"
# value was: 7
assert "active" in data, "missing field: active"
assert data["active"] == True, "data.active should be True"
```


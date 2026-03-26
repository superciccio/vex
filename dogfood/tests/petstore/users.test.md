# User endpoints

## create a user
> **run**
```bash
curl -s -X POST '{{api_url}}/user' -H 'Content-Type: application/json' -d '{"username":"vextest","firstName":"Vex","lastName":"Test","email":"vex@test.com","password":"test123","phone":"555-0100","userStatus":1}'
```
> **assert**
```ocaml
assert (vex.status = 0)
```

## get user by username
> **run**
```bash
curl -s '{{api_url}}/user/vextest'
```
> **assert**
```ocaml
assert (vex.status = 0);
assert (username = "vextest");
assert (firstName = "Vex");
assert (email = "vex@test.com")
```

## login
> **run**
```bash
curl -s '{{api_url}}/user/login?username=vextest&password=test123'
```
> **assert**
```ocaml
assert (vex.status = 0);
assert (vex.stdout |> is_string)
```

## delete user
> **run**
```bash
curl -s -X DELETE '{{api_url}}/user/vextest' -H 'api_key: {{api_key}}'
```
> **assert**
```ocaml
assert (vex.status = 0)
```

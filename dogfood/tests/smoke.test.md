---
greeting: hello world
---

# Basic commands

## echo works
```run
echo "hello world"
```
```expect
hello world
```

## exit code is captured
```run
test 1 -eq 2
```
```expect.status
1
```

## variable substitution works
```run
echo "{{greeting}}"
```
```expect
hello world
```

## contains assertion
```run
echo "the quick brown fox jumps over the lazy dog"
```
```expect.contains
brown fox
```

## failing test for demo
```run
echo "actual output"
```
```expect
something else
```

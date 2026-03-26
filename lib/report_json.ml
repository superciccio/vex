(* JSON (JSONL) output reporter.
   One JSON object per line per test. *)

let escape_json_string s =
  let buf = Buffer.create (String.length s) in
  String.iter (fun c ->
    match c with
    | '"' -> Buffer.add_string buf "\\\""
    | '\\' -> Buffer.add_string buf "\\\\"
    | '\n' -> Buffer.add_string buf "\\n"
    | '\t' -> Buffer.add_string buf "\\t"
    | '\r' -> Buffer.add_string buf "\\r"
    | c when Char.code c < 0x20 ->
      Buffer.add_string buf (Printf.sprintf "\\u%04x" (Char.code c))
    | c -> Buffer.add_char buf c
  ) s;
  Buffer.contents buf

let json_string s = Printf.sprintf "\"%s\"" (escape_json_string s)

let assertion_kind_to_string = function
  | Types.Exact -> "exact"
  | Types.Status -> "status"
  | Types.Stderr -> "stderr"
  | Types.Contains -> "contains"
  | Types.Script lang -> Printf.sprintf "script:%s" lang
  | Types.Expr -> "expr"

let option_to_json = function
  | None -> "null"
  | Some s -> json_string s

let print_result (r : Types.test_result) =
  let assertions_json = List.map (fun (ar : Types.assertion_result) ->
    Printf.sprintf "{\"type\":%s,\"expected\":%s,\"actual\":%s,\"passed\":%s}"
      (json_string (assertion_kind_to_string ar.assertion.kind))
      (json_string ar.assertion.expected)
      (json_string ar.actual)
      (if ar.passed then "true" else "false")
  ) r.assertion_results in
  let vars_json = List.map (fun (k, v) ->
    Printf.sprintf "%s:%s" (json_string k) (json_string v)
  ) r.variables_used in
  Printf.printf "{\"file\":%s,\"suite\":%s,\"test\":%s,\"status\":%s,\"line\":%d,\"description\":%s,\"command\":%s,\"assertions\":[%s],\"stdout\":%s,\"stderr\":%s,\"exit_code\":%d,\"duration_ms\":%d,\"variables\":{%s},\"context\":{\"prev_test\":%s,\"next_test\":%s}}\n"
    (json_string r.file_path)
    (json_string r.suite_name)
    (json_string r.test.name)
    (json_string (if r.passed then "pass" else "fail"))
    r.test.line
    (json_string (Printf.sprintf "## %s" r.test.name))
    (json_string r.command_expanded)
    (String.concat "," assertions_json)
    (json_string r.stdout)
    (json_string r.stderr)
    r.exit_code
    r.duration_ms
    (String.concat "," vars_json)
    (option_to_json r.prev_test)
    (option_to_json r.next_test)

let print_results results ~failures_only =
  let to_print = if failures_only
    then List.filter (fun (r : Types.test_result) -> not r.passed) results
    else results
  in
  List.iter print_result to_print;
  let has_failure = List.exists (fun (r : Types.test_result) -> not r.passed) results in
  if has_failure then 1 else 0

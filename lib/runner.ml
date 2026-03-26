(* Shell backend: execute run blocks and check assertions *)

(* Read and remove a temp file *)
let read_temp path =
  let content = In_channel.with_open_text path In_channel.input_all in
  Sys.remove path;
  String.trim content

(* Check if a command starts with curl *)
let is_curl_command cmd =
  let trimmed = String.trim cmd in
  String.length trimmed >= 4 && String.sub trimmed 0 4 = "curl"

(* Parse HTTP headers from curl -D output into (name, value) pairs.
   Header names are lowercased and hyphens replaced with underscores. *)
let parse_headers raw =
  let lines = String.split_on_char '\n' raw in
  List.filter_map (fun line ->
    let line = String.trim line in
    (* Skip status line (HTTP/1.1 200 OK) and empty lines *)
    if line = "" || (String.length line >= 4 && String.sub line 0 4 = "HTTP") then
      None
    else
      match String.index_opt line ':' with
      | None -> None
      | Some i ->
        let name = String.sub line 0 i in
        let value = String.trim (String.sub line (i + 1) (String.length line - i - 1)) in
        (* Normalize: Content-Type -> content_type *)
        let norm = String.lowercase_ascii name in
        let norm = String.map (fun c -> if c = '-' then '_' else c) norm in
        Some (norm, value)
  ) lines

(* Run a shell command, capture stdout, stderr, exit code, and headers.
   For curl commands, automatically injects -D to capture response headers. *)
let exec_command command =
  let stdout_file = Filename.temp_file "vex" "stdout" in
  let stderr_file = Filename.temp_file "vex" "stderr" in
  let header_file = Filename.temp_file "vex" "headers" in
  (* For curl commands, inject -D <headerfile> to capture headers *)
  let actual_cmd =
    if is_curl_command command then
      (* Insert -D <file> right after "curl" *)
      let trimmed = String.trim command in
      "curl -D " ^ Filename.quote header_file ^ " " ^
      String.sub trimmed 4 (String.length trimmed - 4)
    else
      command
  in
  let full_cmd = Printf.sprintf "%s >%s 2>%s"
    actual_cmd
    (Filename.quote stdout_file)
    (Filename.quote stderr_file)
  in
  let exit_code = Sys.command full_cmd in
  let stdout = read_temp stdout_file in
  let stderr = read_temp stderr_file in
  let headers =
    if Sys.file_exists header_file then begin
      let raw = read_temp header_file in
      parse_headers raw
    end else
      []
  in
  (stdout, stderr, exit_code, headers)

(* Run a script assertion: write script to temp file, inject response
   data as env vars, run with the specified interpreter *)
let run_script_assertion lang script stdout stderr exit_code =
  (* Pick interpreter from the fence language *)
  let interpreter = match lang with
    | "python" | "python3" -> "python3"
    | "bash" | "sh" -> "bash"
    | "node" | "javascript" | "js" -> "node"
    | "ruby" | "rb" -> "ruby"
    | other -> other
  in
  (* Pick file extension *)
  let ext = match lang with
    | "python" | "python3" -> ".py"
    | "bash" | "sh" -> ".sh"
    | "node" | "javascript" | "js" -> ".js"
    | "ruby" | "rb" -> ".rb"
    | _ -> ".tmp"
  in
  let script_file = Filename.temp_file "vex_script" ext in
  let stderr_file = Filename.temp_file "vex_script" "stderr" in
  Out_channel.with_open_text script_file (fun oc -> output_string oc script);
  (* Run with env vars injected *)
  let cmd = Printf.sprintf "VEX_STDOUT=%s VEX_STDERR=%s VEX_STATUS=%d %s %s 2>%s"
    (Filename.quote stdout)
    (Filename.quote stderr)
    exit_code
    interpreter
    (Filename.quote script_file)
    (Filename.quote stderr_file)
  in
  let script_exit = Sys.command cmd in
  let script_stderr =
    let content = In_channel.with_open_text stderr_file In_channel.input_all in
    Sys.remove stderr_file;
    String.trim content
  in
  Sys.remove script_file;
  (* exit 0 = pass, anything else = fail *)
  let passed = script_exit = 0 in
  let actual = if passed then "script passed"
    else if script_stderr <> "" then script_stderr
    else Printf.sprintf "script exited with code %d" script_exit
  in
  (passed, actual)

(* Build evaluation environment for mini-ML assert blocks.
   Builtins live under the "vex" namespace to avoid collisions
   with JSON keys (e.g. a response with "status": "available"). *)
let build_eval_env stdout stderr exit_code headers =
  let vex_obj = Eval_types.VObject [
    ("status", Eval_types.VInt exit_code);
    ("stdout", Eval_types.VString stdout);
    ("stderr", Eval_types.VString stderr);
    ("headers", Eval_types.VHeaders headers);
  ] in
  let base = [("vex", vex_obj)] in
  (* Try to parse stdout as JSON and spread top-level keys *)
  match Yojson.Safe.from_string stdout with
  | json ->
    let value = Eval_types.of_yojson json in
    (match value with
     | Eval_types.VObject fields -> base @ fields
     | Eval_types.VList _ -> ("items", value) :: base
     | _ -> base)
  | exception _ -> base

(* Check one assertion against actual results *)
let check_assertion stdout stderr exit_code headers (a : Types.assertion) : Types.assertion_result =
  match a.kind with
  | Types.Exact ->
    { assertion = a; passed = stdout = a.expected; actual = stdout }
  | Types.Status ->
    let expected_code = int_of_string (String.trim a.expected) in
    { assertion = a; passed = exit_code = expected_code;
      actual = string_of_int exit_code }
  | Types.Stderr ->
    { assertion = a; passed = stderr = a.expected; actual = stderr }
  | Types.Contains ->
    let found =
      let hay = stdout and needle = a.expected in
      let hlen = String.length hay and nlen = String.length needle in
      if nlen = 0 then true
      else if nlen > hlen then false
      else
        let found = ref false in
        for i = 0 to hlen - nlen do
          if not !found && String.sub hay i nlen = needle then
            found := true
        done;
        !found
    in
    { assertion = a; passed = found; actual = stdout }
  | Types.Script lang ->
    let passed, actual = run_script_assertion lang a.expected stdout stderr exit_code in
    { assertion = a; passed; actual }
  | Types.Expr ->
    let env = build_eval_env stdout stderr exit_code headers in
    let result = Eval.run env a.expected in
    if result.passed then
      { assertion = a; passed = true; actual = "all assertions passed" }
    else
      (* Format failures into a readable string *)
      let details = List.map (fun (f : Eval.failure) ->
        match f.detail with
        | Eval.Comparison { expected; got } ->
          Printf.sprintf "  %s: expected %s, got %s" f.expr_src expected got
        | Eval.ShapeMismatch errors ->
          let mismatches = List.map (fun (e : Eval.shape_error) ->
            Printf.sprintf "    %s: expected %s, got %s" e.path e.expected e.got
          ) errors in
          Printf.sprintf "  %s:\n%s" f.expr_src (String.concat "\n" mismatches)
      ) result.failures in
      { assertion = a; passed = false;
        actual = String.concat "\n" details }

(* Run a single test *)
let run_test vars (suite_name : string) (file_path : string)
    ~prev_test ~next_test (test : Types.test) : Types.test_result =
  let command_expanded = Variables.substitute vars test.command in
  let t0 = Unix.gettimeofday () in
  let stdout, stderr, exit_code, headers = exec_command command_expanded in
  let t1 = Unix.gettimeofday () in
  let duration_ms = int_of_float ((t1 -. t0) *. 1000.0) in
  let assertion_results = List.map (fun a ->
    let a = Types.{ a with expected = Variables.substitute vars a.expected } in
    check_assertion stdout stderr exit_code headers a
  ) test.assertions in
  let passed = List.for_all (fun (r : Types.assertion_result) -> r.passed) assertion_results in
  Types.{
    test;
    suite_name;
    file_path;
    passed;
    stdout;
    stderr;
    exit_code;
    duration_ms;
    assertion_results;
    command_expanded;
    variables_used = vars;
    prev_test;
    next_test;
  }

(* Run all tests in a test file *)
let run_file (tf : Types.test_file) : Types.test_result list =
  let all_tests = List.concat_map (fun (suite : Types.suite) ->
    List.map (fun t -> (suite.name, t)) suite.tests
  ) tf.suites in
  let arr = Array.of_list all_tests in
  let len = Array.length arr in
  List.init len (fun i ->
    let suite_name, test = arr.(i) in
    let prev_test = if i > 0 then Some (snd arr.(i - 1)).Types.name else None in
    let next_test = if i + 1 < len then Some (snd arr.(i + 1)).Types.name else None in
    run_test tf.variables suite_name tf.path ~prev_test ~next_test test
  )

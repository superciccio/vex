(* vex learn — run commands, analyze responses, generate assertions.

   Analyzes JSON responses to infer:
   - Field presence and types
   - Stable values (strings, bools) vs likely-dynamic (ids, timestamps)
   - Array element structure
   - Nested objects

   Generates Python assertion scripts that validate structure. *)

(* Heuristics for detecting dynamic values *)
let looks_like_id key =
  let k = String.lowercase_ascii key in
  k = "id" || (String.length k > 3 &&
  String.sub k (String.length k - 3) 3 = "_id")

let looks_like_timestamp key =
  let k = String.lowercase_ascii key in
  List.exists (fun suffix ->
    let slen = String.length suffix in
    String.length k >= slen && String.sub k (String.length k - slen) slen = suffix
  ) ["_at"; "_date"; "_time"; "timestamp"; "created"; "updated"]

let looks_like_url value =
  String.length value > 8 &&
  (String.sub value 0 8 = "https://" || String.sub value 0 7 = "http://")

(* Indent a string by n spaces *)
let indent n s =
  let prefix = String.make n ' ' in
  prefix ^ s

(* Python-safe path for assertion messages — use simple label *)
let label_of_path path =
  (* Replace brackets with dots for readable messages *)
  let buf = Buffer.create (String.length path) in
  String.iter (fun c ->
    match c with
    | '[' -> Buffer.add_char buf '.'
    | ']' | '"' -> ()
    | _ -> Buffer.add_char buf c
  ) path;
  Buffer.contents buf

(* Generate assertion lines for a JSON value at a given path *)
let rec generate_assertions path value depth =
  let label = label_of_path path in
  match value with
  | `Null ->
    [indent depth (Printf.sprintf "assert %s is None, \"%s should be null\"" path label)]
  | `Bool b ->
    [indent depth (Printf.sprintf "assert %s == %s, \"%s should be %s\"" path (if b then "True" else "False") label (if b then "True" else "False"))]
  | `Int n ->
    [indent depth (Printf.sprintf "assert isinstance(%s, int), \"%s should be integer\"" path label);
     indent depth (Printf.sprintf "# value was: %d" n)]
  | `Intlit s ->
    [indent depth (Printf.sprintf "assert isinstance(%s, int), \"%s should be integer\"" path label);
     indent depth (Printf.sprintf "# value was: %s" s)]
  | `Float f ->
    [indent depth (Printf.sprintf "assert isinstance(%s, (int, float)), \"%s should be numeric\"" path label);
     indent depth (Printf.sprintf "# value was: %g" f)]
  | `String s ->
    if looks_like_url s then
      [indent depth (Printf.sprintf "assert isinstance(%s, str), \"%s should be string\"" path label);
       indent depth (Printf.sprintf "assert %s.startswith(\"http\"), \"%s should be a URL\"" path label);
       indent depth (Printf.sprintf "# value was: %s" (if String.length s > 60 then String.sub s 0 60 ^ "..." else s))]
    else if String.length s > 100 then
      [indent depth (Printf.sprintf "assert isinstance(%s, str), \"%s should be string\"" path label);
       indent depth (Printf.sprintf "assert len(%s) > 0, \"%s should not be empty\"" path label)]
    else
      [indent depth (Printf.sprintf "assert isinstance(%s, str), \"%s should be string\"" path label);
       indent depth (Printf.sprintf "# value was: \"%s\"" s)]
  | `List items ->
    let lines = [indent depth (Printf.sprintf "assert isinstance(%s, list), \"%s should be array\"" path label);
                 indent depth (Printf.sprintf "# length was: %d" (List.length items))] in
    (match items with
     | first :: _ ->
       let lines = lines @ [indent depth (Printf.sprintf "if len(%s) > 0:" path)] in
       lines @ generate_assertions (Printf.sprintf "%s[0]" path) first (depth + 4)
     | [] -> lines)
  | `Assoc fields ->
    let lines = [indent depth (Printf.sprintf "assert isinstance(%s, dict), \"%s should be object\"" path label)] in
    List.fold_left (fun acc (key, value) ->
      let field_path = Printf.sprintf "%s[\"%s\"]" path key in
      let presence = indent depth (Printf.sprintf "assert \"%s\" in %s, \"missing field: %s\"" key path key) in
      let field_lines =
        if looks_like_id key then
          (* IDs are dynamic — check presence and infer actual type, don't assume int *)
          presence :: generate_assertions field_path value depth
        else if looks_like_timestamp key then
          [presence;
           indent depth (Printf.sprintf "assert isinstance(%s, str), \"%s should be string\"" field_path key)]
        else
          presence :: generate_assertions field_path value depth
      in
      acc @ field_lines
    ) lines fields

(* Generate a complete Python assertion script from a response *)
let generate_script stdout exit_code =
  let lines = ["import json, os"; ""] in
  let lines = lines @ [Printf.sprintf "assert int(os.environ[\"VEX_STATUS\"]) == %d, \"expected exit code %d\"" exit_code exit_code; ""] in
  match Yojson.Safe.from_string stdout with
  | json ->
    let lines = lines @ ["data = json.loads(os.environ[\"VEX_STDOUT\"])"; ""] in
    let assertion_lines = generate_assertions "data" json 0 in
    lines @ assertion_lines
  | exception _ ->
    let trimmed = String.trim stdout in
    if trimmed = "" then
      lines @ ["# Response was empty";
               "assert os.environ[\"VEX_STDOUT\"].strip() == \"\", \"expected empty response\""]
    else
      let escaped = String.concat "\\n" (String.split_on_char '\n' trimmed) in
      lines @ [Printf.sprintf "# Response (not JSON): %s"
                 (if String.length escaped > 80 then String.sub escaped 0 80 ^ "..." else escaped);
               "stdout = os.environ[\"VEX_STDOUT\"].strip()";
               "assert len(stdout) > 0, \"expected non-empty response\""]

(* Check if a test already has assertions *)
let has_assertions (test : Types.test) =
  test.assertions <> []

(* Run learn mode: read file, find tests without assertions,
   run their commands, generate assert blocks, rewrite the file.

   Strategy: walk the file line by line, when we reach the end of
   a run block for a test that needs learning, insert the assert block. *)
let learn_file (tf : Types.test_file) =
  let content = In_channel.with_open_text tf.path In_channel.input_all in
  let lines = String.split_on_char '\n' content in

  (* Build a set of test names that need assertions *)
  let needs_learning = List.concat_map (fun (suite : Types.suite) ->
    List.filter_map (fun (test : Types.test) ->
      if has_assertions test then None
      else Some test.name
    ) suite.tests
  ) tf.suites in

  (* Run commands for tests that need learning, build a map of name -> script *)
  let learned_scripts = List.concat_map (fun (suite : Types.suite) ->
    List.filter_map (fun (test : Types.test) ->
      if has_assertions test then None
      else begin
        let command = Variables.substitute tf.variables test.command in
        let stdout, _stderr, exit_code, _headers = Runner.exec_command command in
        let script = Shape.generate_miniml stdout exit_code in
        Some (test.name, script)
      end
    ) suite.tests
  ) tf.suites in

  (* Now walk the file and insert assert blocks after run blocks *)
  let output = Buffer.create (String.length content + 1024) in
  let current_test = ref "" in
  let in_block = ref false in
  let just_closed_run = ref false in

  List.iter (fun line ->
    let trimmed = String.trim line in

    if !in_block then begin
      Buffer.add_string output line;
      Buffer.add_char output '\n';
      if String.length trimmed >= 3 && String.sub trimmed 0 3 = "```" then begin
        in_block := false;
        (* Check if this was a run block for a test that needs learning *)
        if !just_closed_run && List.mem_assoc !current_test learned_scripts then begin
          let script = List.assoc !current_test learned_scripts in
          Buffer.add_string output "> **assert**\n";
          Buffer.add_string output "```ocaml\n";
          Buffer.add_string output script;
          Buffer.add_char output '\n';
          Buffer.add_string output "```\n";
        end;
        just_closed_run := false
      end
    end else begin
      (* Check for test heading *)
      if String.length trimmed >= 4 && String.sub trimmed 0 3 = "## " then begin
        current_test := String.trim (String.sub trimmed 3 (String.length trimmed - 3))
      end;

      (* Check for fenced block start *)
      if String.length trimmed >= 3 && String.sub trimmed 0 3 = "```" && trimmed <> "```" then begin
        in_block := true;
        (* Check if this is a run block (either via label or fence tag) *)
        let is_run = List.mem !current_test needs_learning in
        just_closed_run := is_run
      end;

      Buffer.add_string output line;
      Buffer.add_char output '\n'
    end
  ) lines;

  (* Remove trailing extra newline if original didn't have one *)
  let result = Buffer.contents output in
  if String.length content > 0 && content.[String.length content - 1] <> '\n' then
    String.sub result 0 (String.length result - 1)
  else
    result

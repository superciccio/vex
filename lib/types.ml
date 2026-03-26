(* Core types for vex *)

(* What kind of assertion to check *)
type assertion_kind =
  | Exact       (* expect: stdout must match exactly *)
  | Status      (* expect.status: exit code must match *)
  | Stderr      (* expect.stderr: stderr must match exactly *)
  | Contains    (* expect.contains: stdout must contain substring *)
  | Script of string  (* assert script: run code in given language (python, bash, etc.) *)
  | Expr        (* assert: mini-ML expression block *)

(* A single assertion: what we expect and how to check it *)
type assertion = {
  kind : assertion_kind;
  expected : string;
}

(* A single test: a name, a command to run, and assertions to check *)
type test = {
  name : string;
  line : int;
  command : string;
  assertions : assertion list;
}

(* A suite of tests grouped under a heading *)
type suite = {
  name : string;
  tests : test list;
}

(* A parsed .test.md file *)
type test_file = {
  path : string;
  variables : (string * string) list;
  suites : suite list;
}

(* Result of running one assertion *)
type assertion_result = {
  assertion : assertion;
  passed : bool;
  actual : string;
}

(* Result of running one test *)
type test_result = {
  test : test;
  suite_name : string;
  file_path : string;
  passed : bool;
  stdout : string;
  stderr : string;
  exit_code : int;
  duration_ms : int;
  assertion_results : assertion_result list;
  command_expanded : string;
  variables_used : (string * string) list;
  prev_test : string option;
  next_test : string option;
}

(* Output format selection *)
type output_format =
  | Human
  | Json

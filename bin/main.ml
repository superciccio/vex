(* vex — a test runner for humans and LLMs *)

let usage = {|vex — test runner for humans and LLMs

Usage:
  vex run <file.test.md>     Run tests in a file
  vex learn <file.test.md>   Run commands and auto-generate assertions

Options:
  --output human             Minimal failure report (default)
  --output json              JSONL to stdout
  --failures-only            Only output failing tests
  --help                     Show this message
|}

type command =
  | Run
  | Learn

type config = {
  command : command;
  file : string;
  output : Vex.Types.output_format;
  failures_only : bool;
}

let parse_args () =
  let args = Array.to_list Sys.argv |> List.tl in
  let output = ref Vex.Types.Human in
  let failures_only = ref false in
  let file = ref "" in
  let command = ref Run in
  let show_help = ref false in
  let rec parse = function
    | [] -> ()
    | "--help" :: _ -> show_help := true
    | "--output" :: "json" :: rest -> output := Vex.Types.Json; parse rest
    | "--output" :: "human" :: rest -> output := Vex.Types.Human; parse rest
    | "--output" :: _ :: _ -> failwith "Unknown output format (use 'human' or 'json')"
    | "--failures-only" :: rest -> failures_only := true; parse rest
    | "run" :: path :: rest -> command := Run; file := path; parse rest
    | "learn" :: path :: rest -> command := Learn; file := path; parse rest
    | unknown :: _ -> failwith (Printf.sprintf "Unknown argument: %s" unknown)
  in
  parse args;
  if !show_help then (print_string usage; exit 0);
  if !file = "" then (print_string usage; exit 1);
  { command = !command; file = !file; output = !output; failures_only = !failures_only }

let () =
  let config = parse_args () in
  match config.command with
  | Run ->
    let test_file = Vex.Markdown.parse config.file in
    let results = Vex.Runner.run_file test_file in
    let exit_code = match config.output with
      | Vex.Types.Human -> Vex.Report_human.print_results results ~failures_only:config.failures_only
      | Vex.Types.Json -> Vex.Report_json.print_results results ~failures_only:config.failures_only
    in
    exit exit_code
  | Learn ->
    let test_file = Vex.Markdown.parse config.file in
    let updated = Vex.Learn.learn_file test_file in
    Out_channel.with_open_text config.file (fun oc ->
      output_string oc updated
    );
    Printf.printf "learned: %s\n" config.file

(* Human-readable output reporter.
   Passing tests are silent. Only failures shown. *)

let assertion_kind_to_string = function
  | Types.Exact -> "stdout"
  | Types.Status -> "status"
  | Types.Stderr -> "stderr"
  | Types.Contains -> "stdout contains"
  | Types.Script lang -> Printf.sprintf "script (%s)" lang

let print_results results ~failures_only =
  let failed = List.filter (fun (r : Types.test_result) -> not r.passed) results in
  let passed_count = List.length results - List.length failed in
  let failed_count = List.length failed in

  (* Print failures *)
  List.iter (fun (r : Types.test_result) ->
    Printf.printf "\n\xe2\x9c\x97 %s > %s\n" r.suite_name r.test.name;
    List.iter (fun (ar : Types.assertion_result) ->
      if not ar.passed then begin
        match ar.assertion.kind with
        | Types.Script lang ->
          Printf.printf "  \xe2\x94\x84 %s script failed: %s\n" lang ar.actual
        | _ ->
          let kind_str = assertion_kind_to_string ar.assertion.kind in
          Printf.printf "  \xe2\x94\x84 expected %s: %s\n" kind_str ar.assertion.expected;
          Printf.printf "  \xe2\x94\x84 actual %s:   %s\n" kind_str ar.actual
      end
    ) r.assertion_results;
    Printf.printf "  \xe2\x94\x84 at: %s:%d\n" r.file_path r.test.line
  ) failed;

  if not failures_only then begin
    (* Summary *)
    Printf.printf "\n";
    if failed_count = 0 then
      Printf.printf "%d passed\n" passed_count
    else
      Printf.printf "%d passed, %d failed\n" passed_count failed_count
  end;

  (* Return exit code *)
  if failed_count > 0 then 1 else 0

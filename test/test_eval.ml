(* Quick smoke test for the mini-ML evaluator *)

let () =
  let vex_obj = Vex.Eval_types.VObject [
    ("status", Vex.Eval_types.VInt 0);
    ("stdout", Vex.Eval_types.VString "{\"data\":{\"animes\":[{\"id\":\"1\",\"name\":\"Test\",\"score\":7.5,\"genres\":[{\"name\":\"Action\",\"kind\":\"genre\"},{\"name\":\"Comedy\",\"kind\":\"genre\"}]}]}}");
    ("stderr", Vex.Eval_types.VString "");
    ("headers", Vex.Eval_types.VHeaders [("content_type", "application/json")]);
  ] in
  let env : Vex.Eval.env = [
    ("vex", vex_obj);
    ("data", Vex.Eval_types.of_yojson (Yojson.Safe.from_string "{\"animes\":[{\"id\":\"1\",\"name\":\"Test\",\"score\":7.5,\"genres\":[{\"name\":\"Action\",\"kind\":\"genre\"},{\"name\":\"Comedy\",\"kind\":\"genre\"}]}]}"));
  ] in

  (* Test 1: basic assertions *)
  let result = Vex.Eval.run env {|
    assert (vex.status = 0);
    assert (data.animes.[0].name = "Test");
    assert (data.animes.[0].score > 5.0)
  |} in
  Printf.printf "Test 1 (basic): passed=%b, asserts=%d, failures=%d\n"
    result.passed result.total_asserts (List.length result.failures);

  (* Test 2: let binding + pipe *)
  let result = Vex.Eval.run env {|
    let first = data.animes.[0] in
    assert (first.name |> is_string);
    assert (first.id |> is_string);
    assert (first.genres |> length = 2)
  |} in
  Printf.printf "Test 2 (let+pipe): passed=%b, asserts=%d, failures=%d\n"
    result.passed result.total_asserts (List.length result.failures);
  List.iter (fun (f : Vex.Eval.failure) ->
    Printf.printf "  FAIL: %s\n" f.expr_src;
    match f.detail with
    | Vex.Eval.Comparison { expected; got } ->
      Printf.printf "    expected: %s, got: %s\n" expected got
    | _ -> ()
  ) result.failures;

  (* Test 3: matches_shape *)
  let result = Vex.Eval.run env {|
    assert (data.animes.[0] |> matches_shape {
      id: string,
      name: string,
      score: number,
      genres: [{ name: string, kind: string }]
    })
  |} in
  Printf.printf "Test 3 (shape): passed=%b, asserts=%d, failures=%d\n"
    result.passed result.total_asserts (List.length result.failures);

  (* Test 4: intentional failure *)
  let result = Vex.Eval.run env {|
    assert (vex.status = 1);
    assert (data.animes.[0].score > 9.0)
  |} in
  Printf.printf "Test 4 (failures): passed=%b, asserts=%d, failures=%d\n"
    result.passed result.total_asserts (List.length result.failures);
  List.iter (fun (f : Vex.Eval.failure) ->
    Printf.printf "  FAIL: %s\n" f.expr_src;
    match f.detail with
    | Vex.Eval.Comparison { expected; got } ->
      Printf.printf "    expected: %s, got: %s\n" expected got
    | Vex.Eval.ShapeMismatch errors ->
      List.iter (fun (e : Vex.Eval.shape_error) ->
        Printf.printf "    %s: expected %s, got %s\n" e.path e.expected e.got
      ) errors
  ) result.failures;

  (* Test 5: string builtins *)
  let result = Vex.Eval.run env {|
    assert (data.animes.[0].name |> starts_with "Te");
    assert (data.animes.[0].name |> ends_with "st");
    assert (data.animes.[0].name |> contains "es")
  |} in
  Printf.printf "Test 5 (strings): passed=%b, asserts=%d, failures=%d\n"
    result.passed result.total_asserts (List.length result.failures);

  (* Test 6: each *)
  let result = Vex.Eval.run env {|
    data.animes.[0].genres |> each (fun g ->
      assert (g.name |> is_string);
      assert (g.kind = "genre")
    )
  |} in
  Printf.printf "Test 6 (each): passed=%b, asserts=%d, failures=%d\n"
    result.passed result.total_asserts (List.length result.failures);

  (* Test 7: headers *)
  let result = Vex.Eval.run env {|
    assert (vex.headers.content_type |> contains "application/json")
  |} in
  Printf.printf "Test 7 (headers): passed=%b, asserts=%d, failures=%d\n"
    result.passed result.total_asserts (List.length result.failures);

  (* Test 8: shape inference — generate mini-ML from JSON *)
  let json_str = {|{"data":{"animes":[{"id":"1","name":"Test","score":7.5,"genres":[{"name":"Action","kind":"genre"}],"airedOn":{"year":2009,"month":8},"english":null}]}}|} in
  let generated = Vex.Shape.generate_miniml json_str 0 in
  Printf.printf "Test 8 (shape inference):\n%s\n\n" generated;

  (* Verify the generated code actually evaluates *)
  let env8 : Vex.Eval.env =
    let json = Yojson.Safe.from_string json_str in
    let value = Vex.Eval_types.of_yojson json in
    let vex8 = Vex.Eval_types.VObject [
      ("status", Vex.Eval_types.VInt 0);
      ("stdout", Vex.Eval_types.VString json_str);
      ("stderr", Vex.Eval_types.VString "");
      ("headers", Vex.Eval_types.VHeaders []);
    ] in
    match value with
    | Vex.Eval_types.VObject fields -> ("vex", vex8) :: fields
    | _ -> [("vex", vex8)]
  in
  let result = Vex.Eval.run env8 generated in
  Printf.printf "Test 8 (roundtrip): passed=%b, asserts=%d, failures=%d\n"
    result.passed result.total_asserts (List.length result.failures);
  List.iter (fun (f : Vex.Eval.failure) ->
    Printf.printf "  FAIL: %s\n" f.expr_src;
    match f.detail with
    | Vex.Eval.Comparison { expected; got } ->
      Printf.printf "    expected: %s, got: %s\n" expected got
    | Vex.Eval.ShapeMismatch errors ->
      List.iter (fun (e : Vex.Eval.shape_error) ->
        Printf.printf "    %s: expected %s, got %s\n" e.path e.expected e.got
      ) errors
  ) result.failures;

  (* Test 9: header parsing *)
  let raw_headers = "HTTP/2 200 \r\ncontent-type: application/json\r\nx-request-id: abc-123\r\ncache-control: no-cache\r\n\r\n" in
  let headers = Vex.Runner.parse_headers raw_headers in
  let ok = List.length headers = 3
    && List.assoc "content_type" headers = "application/json"
    && List.assoc "x_request_id" headers = "abc-123"
    && List.assoc "cache_control" headers = "no-cache"
  in
  Printf.printf "Test 9 (header parsing): passed=%b (%d headers)\n" ok (List.length headers);

  (* ── Regression tests for bug fixes ── *)

  (* Test 10: parenthesized comparisons — Bug 1 *)
  let result = Vex.Eval.run env {|
    assert (not (vex.status = 1));
    assert ((data.animes.[0].score > 5.0))
  |} in
  Printf.printf "Test 10 (paren comparison): passed=%b, asserts=%d, failures=%d\n"
    result.passed result.total_asserts (List.length result.failures);
  List.iter (fun (f : Vex.Eval.failure) ->
    Printf.printf "  FAIL: %s\n" f.expr_src
  ) result.failures;

  (* Test 11: negative numbers — Bug 2 *)
  let result = Vex.Eval.run env {|
    assert (data.animes.[0].score > -1.0);
    assert (-5 < 0);
    assert (-3 <> 3)
  |} in
  Printf.printf "Test 11 (negative numbers): passed=%b, asserts=%d, failures=%d\n"
    result.passed result.total_asserts (List.length result.failures);
  List.iter (fun (f : Vex.Eval.failure) ->
    Printf.printf "  FAIL: %s\n" f.expr_src
  ) result.failures;

  (* Test 12: shape check validates ALL list elements — Bug 3 *)
  let env12 : Vex.Eval.env =
    let json = Yojson.Safe.from_string {|{"items":[{"x":1},{"x":"bad"},{"x":3}]}|} in
    let value = Vex.Eval_types.of_yojson json in
    match value with
    | Vex.Eval_types.VObject fields -> fields
    | _ -> []
  in
  let result = Vex.Eval.run env12 {|
    assert (items |> matches_shape [{ x: int }])
  |} in
  Printf.printf "Test 12 (shape all elements): passed=%b (should be false), failures=%d\n"
    result.passed (List.length result.failures);
  List.iter (fun (f : Vex.Eval.failure) ->
    match f.detail with
    | Vex.Eval.ShapeMismatch errors ->
      List.iter (fun (e : Vex.Eval.shape_error) ->
        Printf.printf "  mismatch at %s: expected %s, got %s\n" e.path e.expected e.got
      ) errors
    | _ -> ()
  ) result.failures;

  (* Test 13: VObject equality — Bug 4 *)
  let env13 : Vex.Eval.env =
    let json = Yojson.Safe.from_string {|{"a":{"x":1,"y":2},"b":{"x":1,"y":2},"c":{"x":1,"y":3}}|} in
    let value = Vex.Eval_types.of_yojson json in
    match value with
    | Vex.Eval_types.VObject fields -> fields
    | _ -> []
  in
  let result = Vex.Eval.run env13 {|
    assert (a = b);
    assert (a <> c)
  |} in
  Printf.printf "Test 13 (object equality): passed=%b, asserts=%d, failures=%d\n"
    result.passed result.total_asserts (List.length result.failures);
  List.iter (fun (f : Vex.Eval.failure) ->
    Printf.printf "  FAIL: %s\n" f.expr_src
  ) result.failures;

  (* Test 14: empty list with each — Bug 5 *)
  let env14 : Vex.Eval.env =
    let json = Yojson.Safe.from_string {|{"items":[]}|} in
    let value = Vex.Eval_types.of_yojson json in
    match value with
    | Vex.Eval_types.VObject fields -> fields
    | _ -> []
  in
  let result = Vex.Eval.run env14 {|
    items |> each (fun x ->
      assert (x |> is_string)
    )
  |} in
  Printf.printf "Test 14 (empty each): passed=%b (should be false), failures=%d\n"
    result.passed (List.length result.failures);
  List.iter (fun (f : Vex.Eval.failure) ->
    match f.detail with
    | Vex.Eval.Comparison { expected; got } ->
      Printf.printf "  %s: expected %s, got %s\n" f.expr_src expected got
    | _ -> ()
  ) result.failures;

  (* Test 15: learn mode generates "items" not "stdout" for top-level arrays — Bug 8 *)
  let array_json = {|[{"id":1},{"id":2}]|} in
  let generated = Vex.Shape.generate_miniml array_json 0 in
  let str_contains hay needle =
    let hlen = String.length hay and nlen = String.length needle in
    let found = ref false in
    for i = 0 to hlen - nlen do
      if not !found && String.sub hay i nlen = needle then found := true
    done;
    !found
  in
  let has_items = str_contains generated "items" in
  let has_stdout = str_contains generated "stdout" in
  Printf.printf "Test 15 (learn array binding): uses 'items'=%b, uses 'stdout'=%b (should be true,false)\n"
    has_items has_stdout;

  Printf.printf "\nDone.\n"

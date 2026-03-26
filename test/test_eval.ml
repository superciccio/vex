(* Quick smoke test for the mini-ML evaluator *)

let () =
  let env : Vex.Eval.env = [
    ("status", Vex.Eval_types.VInt 0);
    ("stdout", Vex.Eval_types.VString "{\"data\":{\"animes\":[{\"id\":\"1\",\"name\":\"Test\",\"score\":7.5,\"genres\":[{\"name\":\"Action\",\"kind\":\"genre\"},{\"name\":\"Comedy\",\"kind\":\"genre\"}]}]}}");
    ("stderr", Vex.Eval_types.VString "");
    ("headers", Vex.Eval_types.VHeaders [("content_type", "application/json")]);
    ("data", Vex.Eval_types.of_yojson (Yojson.Safe.from_string "{\"animes\":[{\"id\":\"1\",\"name\":\"Test\",\"score\":7.5,\"genres\":[{\"name\":\"Action\",\"kind\":\"genre\"},{\"name\":\"Comedy\",\"kind\":\"genre\"}]}]}"));
  ] in

  (* Test 1: basic assertions *)
  let result = Vex.Eval.run env {|
    assert (status = 0);
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
    assert (status = 1);
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
    assert (headers.content_type |> contains "application/json")
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
    match value with
    | Vex.Eval_types.VObject fields ->
      [("status", Vex.Eval_types.VInt 0);
       ("stdout", Vex.Eval_types.VString json_str);
       ("stderr", Vex.Eval_types.VString "");
       ("headers", Vex.Eval_types.VHeaders [])]
      @ fields
    | _ -> []
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

  Printf.printf "\nDone.\n"

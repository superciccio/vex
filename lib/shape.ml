(* Shape inference and pretty-printing for the mini-ML evaluator.

   Given a JSON value (Yojson), infer a shape descriptor.
   Given a shape descriptor, pretty-print it as mini-ML source. *)

open Mini_parser

(* Infer a shape from a runtime value *)
let rec infer value =
  match value with
  | Eval_types.VNull -> SNullable SAny
  | Eval_types.VBool _ -> SBool
  | Eval_types.VInt _ -> SInt
  | Eval_types.VFloat _ -> SNumber
  | Eval_types.VString _ -> SString
  | Eval_types.VHeaders _ -> SAny
  | Eval_types.VList items ->
    (match items with
     | [] -> SList SAny
     | first :: _ -> SList (infer first))
  | Eval_types.VObject fields ->
    SObject (List.map (fun (k, v) -> (k, infer v)) fields)

(* Pretty-print a shape as mini-ML source *)
let rec pp_shape indent shape =
  match shape with
  | SString -> "string"
  | SInt -> "int"
  | SNumber -> "number"
  | SBool -> "bool"
  | SAny -> "any"
  | SNullable inner -> pp_shape indent inner ^ "?"
  | SList inner ->
    "[" ^ pp_shape indent inner ^ "]"
  | SObject fields ->
    if is_simple_object fields then
      pp_object_inline fields
    else
      pp_object_multiline indent fields

and is_simple_object fields =
  (* Inline if few fields and all are primitive *)
  List.length fields <= 4 &&
  List.for_all (fun (_, s) ->
    match s with
    | SString | SInt | SNumber | SBool | SAny
    | SNullable (SString | SInt | SNumber | SBool | SAny) -> true
    | _ -> false
  ) fields

and pp_object_inline fields =
  let pairs = List.map (fun (k, s) ->
    Printf.sprintf "%s: %s" k (pp_shape "" s)
  ) fields in
  "{ " ^ String.concat ", " pairs ^ " }"

and pp_object_multiline indent fields =
  let inner_indent = indent ^ "  " in
  let pairs = List.map (fun (k, s) ->
    Printf.sprintf "%s%s: %s" inner_indent k (pp_shape inner_indent s)
  ) fields in
  "{\n" ^ String.concat ",\n" pairs ^ "\n" ^ indent ^ "}"

(* Generate a complete mini-ML assert block from a response.
   This is what `vex learn` emits instead of Python. *)
let generate_miniml stdout exit_code =
  let lines = ref [] in
  let add s = lines := s :: !lines in

  add (Printf.sprintf "assert (vex.status = %d);" exit_code);

  (match Yojson.Safe.from_string stdout with
   | json ->
     let value = Eval_types.of_yojson json in
     (match value with
      | Eval_types.VObject top_fields ->
        (* For each top-level key, generate a shape check *)
        List.iter (fun (key, v) ->
          let shape = infer v in
          let shape_src = pp_shape "" shape in
          (* For simple values, emit direct assertion *)
          (match v with
           | Eval_types.VNull ->
             add (Printf.sprintf "assert (%s |> is_null);" key)
           | Eval_types.VBool b ->
             add (Printf.sprintf "assert (%s = %s);" key (if b then "true" else "false"))
           | Eval_types.VString s when String.length s <= 80 ->
             add (Printf.sprintf "(* value: \"%s\" *)" s);
             add (Printf.sprintf "assert (%s |> is_string);" key)
           | Eval_types.VInt n ->
             add (Printf.sprintf "(* value: %d *)" n);
             add (Printf.sprintf "assert (%s |> is_int);" key)
           | Eval_types.VFloat f ->
             add (Printf.sprintf "(* value: %g *)" f);
             add (Printf.sprintf "assert (%s |> is_float);" key)
           | Eval_types.VList items ->
             add (Printf.sprintf "(* length: %d *)" (List.length items));
             add (Printf.sprintf "assert (%s |> matches_shape %s);" key shape_src)
           | Eval_types.VObject _ ->
             add (Printf.sprintf "assert (%s |> matches_shape %s);" key shape_src)
           | _ ->
             add (Printf.sprintf "assert (%s |> matches_shape %s);" key shape_src))
        ) top_fields
      | Eval_types.VList items ->
        (* Top-level array — runner binds this to "items" *)
        let shape = infer value in
        let shape_src = pp_shape "" shape in
        add (Printf.sprintf "(* length: %d *)" (List.length items));
        add (Printf.sprintf "assert (items |> matches_shape %s);" shape_src)
      | _ ->
        (* Primitive top-level value *)
        add (Printf.sprintf "assert (stdout |> is_string);"))
   | exception _ ->
     let trimmed = String.trim stdout in
     if trimmed = "" then
       add "assert (stdout = \"\");"
     else begin
       add "(* response is not JSON *)";
       add "assert (stdout |> is_string);"
     end);

  String.concat "\n" (List.rev !lines)

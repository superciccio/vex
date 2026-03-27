(* Evaluator for the mini-ML assertion language.

   Tree-walk interpreter. Evaluates expressions against an environment
   of bindings. Collects all assertion failures rather than stopping
   at the first one. *)

open Eval_types
open Mini_parser

(* A single assertion failure *)
type failure = {
  expr_src : string;    (* source text of the failed expression *)
  detail : failure_detail;
}

and failure_detail =
  | Comparison of { expected : string; got : string }
  | ShapeMismatch of shape_error list

and shape_error = {
  path : string;
  expected : string;
  got : string;
}

(* Evaluation environment *)
type env = (string * value) list

(* Result of evaluating an assert block *)
type eval_result = {
  passed : bool;
  failures : failure list;
  total_asserts : int;
}

exception Eval_error of string

let eval_error msg = raise (Eval_error msg)

(* Pretty-print an expression for error messages (simplified) *)
let rec show_expr = function
  | Lit v -> show_value v
  | Var s -> s
  | Dot (e, f) -> Printf.sprintf "%s.%s" (show_expr e) f
  | Index (e, n) -> Printf.sprintf "%s.[%d]" (show_expr e) n
  | Pipe (l, r) -> Printf.sprintf "%s |> %s" (show_expr l) (show_expr r)
  | BinOp (op, l, r) ->
    let op_str = match op with
      | Eq -> "=" | Neq -> "<>" | Gt -> ">" | Lt -> "<"
      | Gte -> ">=" | Lte -> "<="
    in
    Printf.sprintf "%s %s %s" (show_expr l) op_str (show_expr r)
  | Not e -> Printf.sprintf "not %s" (show_expr e)
  | App (f, arg) -> Printf.sprintf "%s %s" f (show_expr arg)
  | Lambda (p, _) -> Printf.sprintf "(fun %s -> ...)" p
  | Let (name, _, _) -> Printf.sprintf "let %s = ..." name
  | Assert e -> Printf.sprintf "assert (%s)" (show_expr e)
  | ShapeCheck (e, _) -> Printf.sprintf "%s |> matches_shape {...}" (show_expr e)
  | Block _ -> "{ ... }"

(* Lookup a name in the environment *)
let lookup env name =
  match List.assoc_opt name env with
  | Some v -> v
  | None -> eval_error (Printf.sprintf "unbound variable: %s" name)

(* Numeric coercion for comparisons *)
let to_float = function
  | VInt n -> float_of_int n
  | VFloat f -> f
  | v -> eval_error (Printf.sprintf "expected number, got %s" (type_name v))

let is_numeric = function
  | VInt _ | VFloat _ -> true
  | _ -> false

(* String operations *)
let to_string = function
  | VString s -> s
  | v -> eval_error (Printf.sprintf "expected string, got %s" (type_name v))

let string_contains haystack needle =
  let hlen = String.length haystack and nlen = String.length needle in
  if nlen = 0 then true
  else if nlen > hlen then false
  else
    let found = ref false in
    for i = 0 to hlen - nlen do
      if not !found && String.sub haystack i nlen = needle then
        found := true
    done;
    !found

(* Shape matching — returns list of all mismatches *)
let rec check_shape path value shape =
  match shape, value with
  | SAny, _ -> []
  | SNullable _, VNull -> []
  | SNullable inner, _ -> check_shape path value inner
  | SString, VString _ -> []
  | SString, _ -> [{ path; expected = "string"; got = type_name value }]
  | SInt, VInt _ -> []
  | SInt, _ -> [{ path; expected = "int"; got = type_name value }]
  | SNumber, VInt _ | SNumber, VFloat _ -> []
  | SNumber, _ -> [{ path; expected = "number"; got = type_name value }]
  | SBool, VBool _ -> []
  | SBool, _ -> [{ path; expected = "bool"; got = type_name value }]
  | SObject field_shapes, VObject fields ->
    List.concat_map (fun (name, s) ->
      let field_path = if path = "" then name else path ^ "." ^ name in
      match List.assoc_opt name fields with
      | None -> [{ path = field_path; expected = "field present"; got = "missing" }]
      | Some v -> check_shape field_path v s
    ) field_shapes
  | SObject _, _ ->
    [{ path; expected = "object"; got = type_name value }]
  | SList elem_shape, VList items ->
    if items = [] then []
    else
      (* Check all elements, not just the first *)
      List.concat (List.mapi (fun i item ->
        let item_path = Printf.sprintf "%s.[%d]" path i in
        check_shape item_path item elem_shape
      ) items)
  | SList _, _ ->
    [{ path; expected = "list"; got = type_name value }]

(* Evaluate a builtin function *)
let eval_builtin name arg =
  match name with
  | "is_string" -> VBool (match arg with VString _ -> true | _ -> false)
  | "is_int" -> VBool (match arg with VInt _ -> true | _ -> false)
  | "is_float" -> VBool (match arg with VFloat _ -> true | _ -> false)
  | "is_bool" -> VBool (match arg with VBool _ -> true | _ -> false)
  | "is_null" -> VBool (match arg with VNull -> true | _ -> false)
  | "is_list" -> VBool (match arg with VList _ -> true | _ -> false)
  | "is_object" -> VBool (match arg with VObject _ -> true | _ -> false)
  | "length" ->
    (match arg with
     | VList items -> VInt (List.length items)
     | VString s -> VInt (String.length s)
     | _ -> eval_error (Printf.sprintf "length: expected list or string, got %s" (type_name arg)))
  | _ -> eval_error (Printf.sprintf "unknown builtin: %s" name)

(* Evaluate a string builtin that takes a second argument (via pipe) *)
let eval_string_builtin name arg param =
  let s = to_string arg in
  match name with
  | "contains" ->
    let needle = to_string param in
    VBool (string_contains s needle)
  | "starts_with" ->
    let prefix = to_string param in
    let plen = String.length prefix in
    VBool (String.length s >= plen && String.sub s 0 plen = prefix)
  | "ends_with" ->
    let suffix = to_string param in
    let slen = String.length suffix and len = String.length s in
    VBool (len >= slen && String.sub s (len - slen) slen = suffix)
  | "matches" ->
    let pattern = to_string param in
    (* Shell out to grep for regex — avoids re library dependency *)
    let tmp = Filename.temp_file "vex_match" ".txt" in
    Out_channel.with_open_text tmp (fun oc -> output_string oc s);
    Fun.protect ~finally:(fun () -> if Sys.file_exists tmp then Sys.remove tmp) (fun () ->
      let cmd = Printf.sprintf "grep -qP %s %s" (Filename.quote pattern) (Filename.quote tmp) in
      let result = Sys.command cmd in
      VBool (result = 0))
  | _ -> eval_error (Printf.sprintf "unknown string builtin: %s" name)

(* Main eval function *)
let rec eval env expr =
  match expr with
  | Lit v -> v
  | Var name -> lookup env name

  | Dot (e, field) ->
    let v = eval env e in
    (match v with
     | VObject fields ->
       (match List.assoc_opt field fields with
        | Some fv -> fv
        | None -> eval_error (Printf.sprintf "missing field: %s" field))
     | VHeaders pairs ->
       (* Normalize: content-type -> content_type *)
       let norm_field = String.map (fun c -> if c = '-' then '_' else c)
         (String.lowercase_ascii field) in
       (match List.assoc_opt norm_field pairs with
        | Some v -> VString v
        | None -> eval_error (Printf.sprintf "missing header: %s" field))
     | _ -> eval_error (Printf.sprintf "cannot access .%s on %s" field (type_name v)))

  | Index (e, n) ->
    let v = eval env e in
    (match v with
     | VList items ->
       if n < List.length items then List.nth items n
       else eval_error (Printf.sprintf "index %d out of bounds (length %d)" n (List.length items))
     | _ -> eval_error (Printf.sprintf "cannot index %s" (type_name v)))

  | BinOp (op, l, r) ->
    let lv = eval env l and rv = eval env r in
    eval_binop op lv rv

  | Not e ->
    let v = eval env e in
    (match v with
     | VBool b -> VBool (not b)
     | _ -> eval_error (Printf.sprintf "not: expected bool, got %s" (type_name v)))

  | App (name, arg) ->
    let argv = eval env arg in
    eval_builtin name argv

  | Pipe (lhs, rhs) ->
    let lv = eval env lhs in
    eval_pipe env lv rhs

  | Lambda _ ->
    eval_error "lambda cannot be evaluated standalone — use with each/any"

  | Let (name, value_expr, body) ->
    let v = eval env value_expr in
    eval ((name, v) :: env) body

  | Assert _ ->
    (* Handled at the statement level in run, not here *)
    eval_error "assert should be handled at statement level"

  | ShapeCheck (e, shape) ->
    let v = eval env e in
    let errors = check_shape "" v shape in
    VBool (errors = [])

  | Block _ ->
    eval_error "block should be handled at statement level"

and eval_binop op lv rv =
  match op with
  | Eq -> VBool (value_eq lv rv)
  | Neq -> VBool (not (value_eq lv rv))
  | Gt | Lt | Gte | Lte ->
    if is_numeric lv && is_numeric rv then
      let lf = to_float lv and rf = to_float rv in
      let result = match op with
        | Gt -> lf > rf | Lt -> lf < rf
        | Gte -> lf >= rf | Lte -> lf <= rf
        | _ -> false
      in
      VBool result
    else
      let ls = to_string lv and rs = to_string rv in
      let result = match op with
        | Gt -> ls > rs | Lt -> ls < rs
        | Gte -> ls >= rs | Lte -> ls <= rs
        | _ -> false
      in
      VBool result

and value_eq a b =
  match a, b with
  | VNull, VNull -> true
  | VBool a, VBool b -> a = b
  | VInt a, VInt b -> a = b
  | VFloat a, VFloat b -> a = b
  | VInt a, VFloat b -> float_of_int a = b
  | VFloat a, VInt b -> a = float_of_int b
  | VString a, VString b -> a = b
  | VList a, VList b ->
    List.length a = List.length b &&
    List.for_all2 value_eq a b
  | VObject a, VObject b ->
    List.length a = List.length b &&
    List.for_all2 (fun (k1, v1) (k2, v2) -> k1 = k2 && value_eq v1 v2) a b
  | VHeaders a, VHeaders b ->
    List.length a = List.length b &&
    List.for_all2 (fun (k1, v1) (k2, v2) -> k1 = k2 && v1 = v2) a b
  | _ -> false

and eval_pipe env value rhs =
  match rhs with
  | Var name -> eval_builtin name value
  | App (name, arg) ->
    (* Two-arg builtins via pipe: value |> contains "foo" *)
    let param = eval env arg in
    (match name with
     | "contains" | "starts_with" | "ends_with" | "matches" ->
       eval_string_builtin name value param
     | "each" | "any" ->
       (* each/any with lambdas are handled as special cases in run_stmts *)
       eval_error (Printf.sprintf "%s: must be used at statement level with a lambda" name)
     | _ -> eval_error (Printf.sprintf "cannot pipe to: %s" name))
  | Pipe (inner, rest) ->
    (* Chained pipe *)
    let mid = eval_pipe env value inner in
    eval_pipe env mid rest
  | _ -> eval_error "invalid pipe target"

(* Run each/any with a Lambda expression (called from run, not eval) *)
let rec eval_each_lambda env items param_name body failures_ref asserts_ref =
  List.iteri (fun _i item ->
    let inner_env = (param_name, item) :: env in
    run_stmts inner_env [body] failures_ref asserts_ref
  ) items

and eval_any_lambda env items param_name body =
  List.exists (fun item ->
    let inner_env = (param_name, item) :: env in
    try
      let v = eval inner_env body in
      (match v with VBool b -> b | _ -> false)
    with Eval_error _ -> false
  ) items

(* Run a list of statements, collecting failures *)
and run_stmts env stmts failures_ref asserts_ref =
  List.iter (fun stmt ->
    match stmt with
    | Assert (ShapeCheck (e, shape)) ->
      (* Special case: assert(x |> matches_shape {...}) gets detailed reporting *)
      incr asserts_ref;
      (try
        let v = eval env e in
        let errors = check_shape "" v shape in
        if errors <> [] then
          failures_ref := {
            expr_src = show_expr (ShapeCheck (e, shape));
            detail = ShapeMismatch errors;
          } :: !failures_ref
      with Eval_error msg ->
        failures_ref := {
          expr_src = show_expr (ShapeCheck (e, shape));
          detail = Comparison { expected = "success"; got = msg };
        } :: !failures_ref)

    | Assert e ->
      incr asserts_ref;
      (try
        let v = eval env e in
        (match v with
         | VBool true -> ()
         | VBool false ->
           failures_ref := {
             expr_src = show_expr e;
             detail = Comparison { expected = "true"; got = "false" };
           } :: !failures_ref
         | _ ->
           failures_ref := {
             expr_src = show_expr e;
             detail = Comparison {
               expected = "bool";
               got = Printf.sprintf "%s (%s)" (type_name v) (show_value v)
             };
           } :: !failures_ref)
      with Eval_error msg ->
        failures_ref := {
          expr_src = show_expr e;
          detail = Comparison { expected = "success"; got = msg };
        } :: !failures_ref)

    | ShapeCheck (e, shape) ->
      incr asserts_ref;
      (try
        let v = eval env e in
        let errors = check_shape "" v shape in
        if errors <> [] then
          failures_ref := {
            expr_src = show_expr (ShapeCheck (e, shape));
            detail = ShapeMismatch errors;
          } :: !failures_ref
      with Eval_error msg ->
        failures_ref := {
          expr_src = show_expr (ShapeCheck (e, shape));
          detail = Comparison { expected = "success"; got = msg };
        } :: !failures_ref)

    | Let (name, value_expr, Block stmts) ->
      (try
        let v = eval env value_expr in
        let inner_env = (name, v) :: env in
        run_stmts inner_env stmts failures_ref asserts_ref
      with Eval_error msg ->
        failures_ref := {
          expr_src = Printf.sprintf "let %s = ..." name;
          detail = Comparison { expected = "success"; got = msg };
        } :: !failures_ref)

    | Let (name, value_expr, body) ->
      (try
        let v = eval env value_expr in
        let inner_env = (name, v) :: env in
        run_stmts inner_env [body] failures_ref asserts_ref
      with Eval_error msg ->
        failures_ref := {
          expr_src = Printf.sprintf "let %s = ..." name;
          detail = Comparison { expected = "success"; got = msg };
        } :: !failures_ref)

    | Block stmts ->
      run_stmts env stmts failures_ref asserts_ref

    | Pipe (lhs, App ("each", Lambda (param, body))) ->
      (* Special handling: expr |> each (fun x -> ...) *)
      (try
        let v = eval env lhs in
        match v with
        | VList items ->
          if items = [] then begin
            incr asserts_ref;
            failures_ref := {
              expr_src = show_expr stmt;
              detail = Comparison {
                expected = "non-empty list";
                got = "empty list (each had nothing to iterate)"
              };
            } :: !failures_ref
          end else
          eval_each_lambda env items param body failures_ref asserts_ref
        | _ ->
          failures_ref := {
            expr_src = show_expr stmt;
            detail = Comparison {
              expected = "list";
              got = type_name v
            };
          } :: !failures_ref
      with Eval_error msg ->
        failures_ref := {
          expr_src = show_expr stmt;
          detail = Comparison { expected = "success"; got = msg };
        } :: !failures_ref)

    | Pipe (lhs, App ("any", Lambda (param, body))) ->
      incr asserts_ref;
      (try
        let v = eval env lhs in
        match v with
        | VList items ->
          let found = eval_any_lambda env items param body in
          if not found then
            failures_ref := {
              expr_src = show_expr stmt;
              detail = Comparison {
                expected = "at least one match";
                got = "none matched"
              };
            } :: !failures_ref
        | _ ->
          failures_ref := {
            expr_src = show_expr stmt;
            detail = Comparison {
              expected = "list";
              got = type_name v
            };
          } :: !failures_ref
      with Eval_error msg ->
        failures_ref := {
          expr_src = show_expr stmt;
          detail = Comparison { expected = "success"; got = msg };
        } :: !failures_ref)

    | e ->
      (* Any other expression at statement level — evaluate for side effects *)
      (try ignore (eval env e)
       with Eval_error msg ->
         failures_ref := {
           expr_src = show_expr e;
           detail = Comparison { expected = "success"; got = msg };
         } :: !failures_ref)
  ) stmts

(* Main entry point: parse and evaluate an assert block *)
let run env source =
  let tokens = Mini_lexer.tokenize source in
  let stmts = Mini_parser.parse tokens in
  let failures = ref [] in
  let total = ref 0 in
  run_stmts env stmts failures total;
  let failures = List.rev !failures in
  { passed = failures = []; failures; total_asserts = !total }

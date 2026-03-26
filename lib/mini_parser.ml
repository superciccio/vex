(* Parser for the mini-ML assertion language.

   Recursive descent. Consumes a token list, produces an expr list
   (one per statement in the assert block).

   Precedence (lowest to highest):
   1. let / assert (statement-level)
   2. |> pipe (left-associative)
   3. = <> > < >= <= (comparison)
   4. not (prefix)
   5. function application (f x)
   6. dot/index access (.field .[n])
   7. atoms (literals, idents, parens, shapes) *)

open Mini_lexer

(* AST types *)

type op = Eq | Neq | Gt | Lt | Gte | Lte

type shape =
  | SString | SInt | SNumber | SBool | SAny
  | SNullable of shape
  | SObject of (string * shape) list
  | SList of shape

type expr =
  | Lit of Eval_types.value
  | Var of string
  | Dot of expr * string
  | Index of expr * int
  | Pipe of expr * expr
  | BinOp of op * expr * expr
  | Not of expr
  | App of string * expr
  | Lambda of string * expr
  | Let of string * expr * expr
  | Assert of expr
  | ShapeCheck of expr * shape
  | Block of expr list

(* Parser state: a mutable position into the token array *)
type parser_state = {
  tokens : token array;
  mutable pos : int;
}

type parse_error = { error_pos : int; msg : string }
exception Parse_error of parse_error

let error ps msg =
  raise (Parse_error { error_pos = ps.pos; msg })

let peek ps =
  if ps.pos < Array.length ps.tokens then ps.tokens.(ps.pos)
  else EOF

let advance ps =
  let tok = peek ps in
  ps.pos <- ps.pos + 1;
  tok

let expect ps expected =
  let tok = advance ps in
  if tok <> expected then
    error ps (Printf.sprintf "expected %s, got %s"
      (show_token expected) (show_token tok))

(* Shape parsing — { field: type, ... } or primitive type names *)
let rec parse_shape ps =
  match peek ps with
  | LBRACE ->
    ignore (advance ps);
    let fields = parse_shape_fields ps in
    expect ps RBRACE;
    SObject fields
  | DOT_LBRACKET ->
    ignore (advance ps);
    let inner = parse_shape ps in
    expect ps RBRACKET;
    SList inner
  | IDENT "string" -> ignore (advance ps); maybe_nullable ps SString
  | IDENT "int" -> ignore (advance ps); maybe_nullable ps SInt
  | IDENT "number" -> ignore (advance ps); maybe_nullable ps SNumber
  | IDENT "bool" -> ignore (advance ps); maybe_nullable ps SBool
  | IDENT "any" -> ignore (advance ps); maybe_nullable ps SAny
  | _ -> error ps "expected shape type"

and maybe_nullable ps shape =
  match peek ps with
  | QUESTION -> ignore (advance ps); SNullable shape
  | _ -> shape

and parse_shape_fields ps =
  match peek ps with
  | RBRACE -> []
  | _ ->
    let field = parse_shape_field ps in
    match peek ps with
    | COMMA ->
      ignore (advance ps);
      (* Allow trailing comma *)
      (match peek ps with
       | RBRACE -> [field]
       | _ -> field :: parse_shape_fields ps)
    | _ -> [field]

and parse_shape_field ps =
  match advance ps with
  | IDENT name ->
    expect ps COLON;
    let shape = parse_shape ps in
    (name, shape)
  | _ -> error ps "expected field name in shape"

(* Expression parsing — recursive descent by precedence *)

(* Statement level: let, assert, or expr followed by ; *)
let rec parse_stmt ps =
  match peek ps with
  | LET -> parse_let ps
  | ASSERT -> parse_assert ps
  | _ ->
    let e = parse_comparison ps in
    (* Consume optional semicolon *)
    (match peek ps with SEMI -> ignore (advance ps) | _ -> ());
    e

and parse_let ps =
  ignore (advance ps); (* consume LET *)
  let name = match advance ps with
    | IDENT s -> s
    | _ -> error ps "expected identifier after let"
  in
  expect ps EQ;
  let value = parse_comparison ps in
  expect ps IN;
  (* Let scopes over ALL remaining statements in the block, not just one.
     This is friendlier than ML's single-expression body. *)
  let body = parse_stmts_until_end ps in
  Let (name, value, body)

(* Parse remaining statements as a Block for let...in body *)
and parse_stmts_until_end ps =
  let stmts = ref [] in
  while peek ps <> EOF && peek ps <> RPAREN do
    stmts := parse_stmt ps :: !stmts
  done;
  match List.rev !stmts with
  | [] -> Lit Eval_types.VNull
  | [single] -> single
  | many -> Block many

and parse_assert ps =
  ignore (advance ps); (* consume ASSERT *)
  expect ps LPAREN;
  let e = parse_comparison ps in
  expect ps RPAREN;
  (* Consume optional semicolon *)
  (match peek ps with SEMI -> ignore (advance ps) | _ -> ());
  Assert e

(* Pipe: left-associative, binds tighter than comparison *)
and parse_pipe ps =
  let lhs = parse_not ps in
  parse_pipe_rest ps lhs

and parse_pipe_rest ps lhs =
  match peek ps with
  | PIPE_GT ->
    ignore (advance ps);
    let rhs = parse_not ps in
    (* Pipe: lhs |> f  becomes App(f, lhs)
       or:   lhs |> f x  stays as Pipe for later eval
       Special case: lhs |> matches_shape { ... } *)
    let result = match rhs with
      | Var "matches_shape" ->
        let shape = parse_shape ps in
        ShapeCheck (lhs, shape)
      | Var fname -> App (fname, lhs)
      | App (fname, arg) ->
        (* lhs |> f arg  →  we need to handle this as f(arg, lhs) or similar.
           For now: each/any take a lambda, so lhs |> each (fun x -> ...)
           becomes App2 effectively. We'll handle in eval. *)
        Pipe (lhs, App (fname, arg))
      | _ -> Pipe (lhs, rhs)
    in
    parse_pipe_rest ps result
  | _ -> lhs

(* Comparison operators — lower precedence than pipe *)
and parse_comparison ps =
  let lhs = parse_pipe ps in
  match peek ps with
  | EQ -> ignore (advance ps); BinOp (Eq, lhs, parse_pipe ps)
  | NEQ -> ignore (advance ps); BinOp (Neq, lhs, parse_pipe ps)
  | GT -> ignore (advance ps); BinOp (Gt, lhs, parse_pipe ps)
  | LT -> ignore (advance ps); BinOp (Lt, lhs, parse_pipe ps)
  | GTE -> ignore (advance ps); BinOp (Gte, lhs, parse_pipe ps)
  | LTE -> ignore (advance ps); BinOp (Lte, lhs, parse_pipe ps)
  | _ -> lhs

(* not prefix *)
and parse_not ps =
  match peek ps with
  | NOT ->
    ignore (advance ps);
    let e = parse_app ps in
    Not e
  | _ -> parse_app ps

(* Function application: f x (only for known builtins, not general) *)
and parse_app ps =
  let e = parse_access ps in
  (* If e is a Var that's a known function, try to parse an argument *)
  match e with
  | Var name when is_builtin name ->
    (match peek ps with
     | LPAREN | IDENT _ | INT _ | FLOAT _ | STRING _ | TRUE | FALSE ->
       let arg = parse_access ps in
       App (name, arg)
     | _ -> e)
  | _ -> e

and is_builtin = function
  | "is_string" | "is_int" | "is_float" | "is_bool" | "is_null"
  | "is_list" | "is_object"
  | "contains" | "starts_with" | "ends_with" | "matches"
  | "length" | "each" | "any" -> true
  | _ -> false

(* Dot access and index access *)
and parse_access ps =
  let e = parse_atom ps in
  parse_access_rest ps e

and parse_access_rest ps lhs =
  match peek ps with
  | DOT ->
    ignore (advance ps);
    let field = match advance ps with
      | IDENT s -> s
      | _ -> error ps "expected field name after ."
    in
    parse_access_rest ps (Dot (lhs, field))
  | DOT_LBRACKET ->
    ignore (advance ps);
    let idx = match advance ps with
      | INT n -> n
      | _ -> error ps "expected integer index"
    in
    expect ps RBRACKET;
    parse_access_rest ps (Index (lhs, idx))
  | _ -> lhs

(* Atoms: literals, identifiers, parenthesized expressions, lambdas *)
and parse_atom ps =
  match peek ps with
  | INT n -> ignore (advance ps); Lit (Eval_types.VInt n)
  | FLOAT f -> ignore (advance ps); Lit (Eval_types.VFloat f)
  | STRING s -> ignore (advance ps); Lit (Eval_types.VString s)
  | TRUE -> ignore (advance ps); Lit (Eval_types.VBool true)
  | FALSE -> ignore (advance ps); Lit (Eval_types.VBool false)
  | IDENT s -> ignore (advance ps); Var s
  | FUN -> parse_lambda ps
  | LPAREN ->
    ignore (advance ps);
    let e = parse_pipe ps in
    expect ps RPAREN;
    e
  | tok -> error ps (Printf.sprintf "unexpected token: %s" (show_token tok))

and parse_lambda ps =
  ignore (advance ps); (* consume FUN *)
  let param = match advance ps with
    | IDENT s -> s
    | _ -> error ps "expected parameter name after fun"
  in
  expect ps ARROW;
  (* Lambda body consumes all statements until closing paren or EOF *)
  let stmts = ref [] in
  while peek ps <> EOF && peek ps <> RPAREN do
    stmts := parse_stmt ps :: !stmts
  done;
  let body = match List.rev !stmts with
    | [] -> Lit Eval_types.VNull
    | [single] -> single
    | many -> Block many
  in
  Lambda (param, body)

(* Parse a full assert block: sequence of statements *)
let parse tokens =
  let ps = { tokens = Array.of_list tokens; pos = 0 } in
  let stmts = ref [] in
  while peek ps <> EOF do
    stmts := parse_stmt ps :: !stmts
  done;
  List.rev !stmts

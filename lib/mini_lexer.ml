(* Lexer for the mini-ML assertion language.

   Converts a string into a token list. Hand-rolled, single-pass,
   character-by-character. Supports OCaml-style comments (* ... *). *)

type token =
  | IDENT of string
  | INT of int
  | FLOAT of float
  | STRING of string
  | TRUE | FALSE
  | LET | IN | FUN | ASSERT | NOT
  | DOT
  | LBRACKET      (* [ — list shape syntax *)
  | DOT_LBRACKET  (* .[ — array index access *)
  | RBRACKET
  | LPAREN | RPAREN
  | LBRACE | RBRACE
  | COLON | COMMA
  | PIPE_GT       (* |> *)
  | EQ            (* = *)
  | NEQ           (* <> *)
  | GT            (* > *)
  | LT            (* < *)
  | GTE           (* >= *)
  | LTE           (* <= *)
  | ARROW         (* -> *)
  | SEMI          (* ; *)
  | QUESTION      (* ? *)
  | EOF

let show_token = function
  | IDENT s -> Printf.sprintf "IDENT(%s)" s
  | INT n -> Printf.sprintf "INT(%d)" n
  | FLOAT f -> Printf.sprintf "FLOAT(%g)" f
  | STRING s -> Printf.sprintf "STRING(%S)" s
  | TRUE -> "TRUE" | FALSE -> "FALSE"
  | LET -> "LET" | IN -> "IN" | FUN -> "FUN"
  | ASSERT -> "ASSERT" | NOT -> "NOT"
  | DOT -> "DOT" | LBRACKET -> "LBRACKET" | DOT_LBRACKET -> "DOT_LBRACKET" | RBRACKET -> "RBRACKET"
  | LPAREN -> "LPAREN" | RPAREN -> "RPAREN"
  | LBRACE -> "LBRACE" | RBRACE -> "RBRACE"
  | COLON -> "COLON" | COMMA -> "COMMA"
  | PIPE_GT -> "PIPE_GT"
  | EQ -> "EQ" | NEQ -> "NEQ"
  | GT -> "GT" | LT -> "LT" | GTE -> "GTE" | LTE -> "LTE"
  | ARROW -> "ARROW" | SEMI -> "SEMI" | QUESTION -> "QUESTION"
  | EOF -> "EOF"

type lex_error = { pos : int; msg : string }

exception Lex_error of lex_error

let error pos msg = raise (Lex_error { pos; msg })

(* Classify characters *)
let is_digit c = c >= '0' && c <= '9'
let is_alpha c = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
let is_ident_start c = is_alpha c || c = '_'
let is_ident_char c = is_alpha c || is_digit c || c = '_'
let is_whitespace c = c = ' ' || c = '\t' || c = '\n' || c = '\r'

(* Keywords *)
let keyword_of_string = function
  | "let" -> Some LET
  | "in" -> Some IN
  | "fun" -> Some FUN
  | "assert" -> Some ASSERT
  | "not" -> Some NOT
  | "true" -> Some TRUE
  | "false" -> Some FALSE
  | _ -> None

let tokenize src =
  let len = String.length src in
  let pos = ref 0 in
  let tokens = ref [] in

  let _peek () = if !pos < len then Some src.[!pos] else None in
  let advance () = incr pos in
  let current () = src.[!pos] in

  (* Skip whitespace *)
  let skip_ws () =
    while !pos < len && is_whitespace (current ()) do advance () done
  in

  (* Skip OCaml-style comments: (* ... *), nested *)
  let skip_comment () =
    let start = !pos in
    advance (); advance (); (* skip opening paren-star *)
    let depth = ref 1 in
    while !depth > 0 do
      if !pos >= len then
        error start "unterminated comment";
      if !pos + 1 < len && current () = '(' && src.[!pos + 1] = '*' then begin
        incr depth; advance (); advance ()
      end else if !pos + 1 < len && current () = '*' && src.[!pos + 1] = ')' then begin
        decr depth; advance (); advance ()
      end else
        advance ()
    done
  in

  (* Read a string literal *)
  let read_string () =
    let start = !pos in
    advance (); (* skip opening quote *)
    let buf = Buffer.create 32 in
    while !pos < len && current () <> '"' do
      if current () = '\\' then begin
        advance ();
        if !pos >= len then error start "unterminated string";
        (match current () with
         | 'n' -> Buffer.add_char buf '\n'
         | 't' -> Buffer.add_char buf '\t'
         | '\\' -> Buffer.add_char buf '\\'
         | '"' -> Buffer.add_char buf '"'
         | c -> Buffer.add_char buf '\\'; Buffer.add_char buf c);
        advance ()
      end else begin
        Buffer.add_char buf (current ());
        advance ()
      end
    done;
    if !pos >= len then error start "unterminated string";
    advance (); (* skip closing quote *)
    STRING (Buffer.contents buf)
  in

  (* Read a number: int or float *)
  let read_number () =
    let start = !pos in
    let buf = Buffer.create 16 in
    (* Optional minus is handled as unary op, not here *)
    while !pos < len && is_digit (current ()) do
      Buffer.add_char buf (current ());
      advance ()
    done;
    if !pos < len && current () = '.' &&
       (* Don't consume dot if it's followed by an ident (field access)
          or a bracket (index access) *)
       (let next = if !pos + 1 < len then Some src.[!pos + 1] else None in
        match next with
        | Some c -> is_digit c
        | None -> false) then begin
      Buffer.add_char buf '.';
      advance ();
      while !pos < len && is_digit (current ()) do
        Buffer.add_char buf (current ());
        advance ()
      done;
      FLOAT (float_of_string (Buffer.contents buf))
    end else
      let s = Buffer.contents buf in
      (match int_of_string_opt s with
       | Some n -> INT n
       | None -> error start (Printf.sprintf "invalid number: %s" s))
  in

  (* Read an identifier or keyword *)
  let read_ident () =
    let buf = Buffer.create 16 in
    while !pos < len && is_ident_char (current ()) do
      Buffer.add_char buf (current ());
      advance ()
    done;
    let s = Buffer.contents buf in
    match keyword_of_string s with
    | Some tok -> tok
    | None -> IDENT s
  in

  (* Main loop *)
  let rec scan () =
    skip_ws ();
    if !pos >= len then
      tokens := EOF :: !tokens
    else begin
      (* Check for comment *)
      if !pos + 1 < len && current () = '(' && src.[!pos + 1] = '*' then begin
        skip_comment ();
        scan ()
      end else begin
        let tok = match current () with
          | '"' -> read_string ()
          | c when is_digit c -> read_number ()
          | c when is_ident_start c -> read_ident ()
          | '.' ->
            if !pos + 1 < len && src.[!pos + 1] = '[' then begin
              advance (); advance (); DOT_LBRACKET
            end else begin
              advance (); DOT
            end
          | '[' -> advance (); LBRACKET
          | ']' -> advance (); RBRACKET
          | '(' -> advance (); LPAREN
          | ')' -> advance (); RPAREN
          | '{' -> advance (); LBRACE
          | '}' -> advance (); RBRACE
          | ':' -> advance (); COLON
          | ',' -> advance (); COMMA
          | ';' -> advance (); SEMI
          | '?' -> advance (); QUESTION
          | '|' ->
            advance ();
            if !pos < len && current () = '>' then begin
              advance (); PIPE_GT
            end else
              error (!pos - 1) "expected > after |"
          | '=' -> advance (); EQ
          | '<' ->
            advance ();
            if !pos < len && current () = '>' then begin
              advance (); NEQ
            end else if !pos < len && current () = '=' then begin
              advance (); LTE
            end else
              LT
          | '>' ->
            advance ();
            if !pos < len && current () = '=' then begin
              advance (); GTE
            end else
              GT
          | '-' ->
            if !pos + 1 < len && src.[!pos + 1] = '>' then begin
              advance (); advance (); ARROW
            end else if !pos + 1 < len && is_digit src.[!pos + 1] then begin
              (* Negative number literal: -123, -3.14 *)
              advance (); (* skip the minus *)
              let num_tok = read_number () in
              (match num_tok with
               | INT n -> INT (-n)
               | FLOAT f -> FLOAT (-.f)
               | _ -> num_tok)
            end else
              error !pos "unexpected character: -"
          | c -> error !pos (Printf.sprintf "unexpected character: %c" c)
        in
        tokens := tok :: !tokens;
        scan ()
      end
    end
  in

  scan ();
  List.rev !tokens

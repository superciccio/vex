(* Runtime value types for the mini-ML evaluator *)

type value =
  | VNull
  | VBool of bool
  | VInt of int
  | VFloat of float
  | VString of string
  | VList of value list
  | VObject of (string * value) list
  | VHeaders of (string * string) list

(* Pretty-print a value for error messages *)
let show_value = function
  | VNull -> "null"
  | VBool b -> if b then "true" else "false"
  | VInt n -> string_of_int n
  | VFloat f -> Printf.sprintf "%g" f
  | VString s ->
    if String.length s > 60 then
      Printf.sprintf "\"%s...\"" (String.sub s 0 57)
    else
      Printf.sprintf "\"%s\"" s
  | VList items ->
    Printf.sprintf "[...] (%d items)" (List.length items)
  | VObject fields ->
    let keys = List.map fst fields in
    let shown = match keys with
      | [] -> "{}"
      | _ ->
        let preview = List.filteri (fun i _ -> i < 4) keys in
        let s = String.concat ", " preview in
        if List.length keys > 4 then Printf.sprintf "{%s, ...}" s
        else Printf.sprintf "{%s}" s
    in
    shown
  | VHeaders pairs ->
    Printf.sprintf "headers (%d entries)" (List.length pairs)

let type_name = function
  | VNull -> "null"
  | VBool _ -> "bool"
  | VInt _ -> "int"
  | VFloat _ -> "float"
  | VString _ -> "string"
  | VList _ -> "list"
  | VObject _ -> "object"
  | VHeaders _ -> "headers"

(* Convert Yojson to our value type *)
let rec of_yojson = function
  | `Null -> VNull
  | `Bool b -> VBool b
  | `Int n -> VInt n
  | `Intlit s ->
    (match int_of_string_opt s with
     | Some n -> VInt n
     | None ->
       (* Large integers that don't fit in OCaml int — store as float *)
       match float_of_string_opt s with
       | Some f -> VFloat f
       | None -> VString s)
  | `Float f -> VFloat f
  | `String s -> VString s
  | `List items -> VList (List.map of_yojson items)
  | `Assoc fields -> VObject (List.map (fun (k, v) -> (k, of_yojson v)) fields)

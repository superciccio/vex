(* Simple YAML frontmatter parser.
   Only handles flat key: value pairs — no nesting, no arrays.
   Good enough for vex variables. *)

let parse content =
  (* Check if content starts with --- *)
  let lines = String.split_on_char '\n' content in
  match lines with
  | "---" :: rest ->
    (* Find the closing --- *)
    let rec collect acc = function
      | [] -> (List.rev acc, [])  (* no closing ---, treat all as frontmatter *)
      | "---" :: remaining -> (List.rev acc, remaining)
      | line :: remaining -> collect (line :: acc) remaining
    in
    let yaml_lines, body_lines = collect [] rest in
    (* Parse each line as "key: value" *)
    let vars = List.filter_map (fun line ->
      match String.index_opt line ':' with
      | None -> None
      | Some i ->
        let key = String.trim (String.sub line 0 i) in
        let value = String.trim (String.sub line (i + 1) (String.length line - i - 1)) in
        if key = "" then None else Some (key, value)
    ) yaml_lines in
    (vars, String.concat "\n" body_lines)
  | _ ->
    (* No frontmatter *)
    ([], content)

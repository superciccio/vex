(* Variable substitution engine.
   Replaces {{var}} with values from the variable map or environment. *)

let substitute vars text =
  let buf = Buffer.create (String.length text) in
  let len = String.length text in
  let pos = ref 0 in
  while !pos < len do
    if !pos + 1 < len && text.[!pos] = '{' && text.[!pos + 1] = '{' then begin
      (* Found {{ — look for closing }} *)
      let start = !pos + 2 in
      match String.index_from_opt text start '}' with
      | Some i when i + 1 < len && text.[i + 1] = '}' ->
        let var_name = String.trim (String.sub text start (i - start)) in
        (* Look up: first in vars, then in environment *)
        let value =
          match List.assoc_opt var_name vars with
          | Some v -> v
          | None ->
            match Sys.getenv_opt var_name with
            | Some v -> v
            | None -> failwith (Printf.sprintf "Undefined variable: {{%s}}" var_name)
        in
        Buffer.add_string buf value;
        pos := i + 2
      | _ ->
        (* No closing }}, treat as literal *)
        Buffer.add_char buf '{';
        incr pos
    end else begin
      Buffer.add_char buf text.[!pos];
      incr pos
    end
  done;
  Buffer.contents buf

(* vex.yaml discovery and variable merging.

   Walk up from a test file's directory, collecting vex.yaml files.
   Merge variables: closest vex.yaml wins, test file frontmatter wins over all. *)

(* Parse a vex.yaml file — same format as frontmatter: key: value lines *)
let parse_yaml path =
  let content = In_channel.with_open_text path In_channel.input_all in
  let lines = String.split_on_char '\n' content in
  List.filter_map (fun line ->
    let trimmed = String.trim line in
    (* Skip empty lines and comments *)
    if trimmed = "" || (String.length trimmed > 0 && trimmed.[0] = '#') then
      None
    else
      match String.index_opt trimmed ':' with
      | None -> None
      | Some i ->
        let key = String.trim (String.sub trimmed 0 i) in
        let value = String.trim (String.sub trimmed (i + 1) (String.length trimmed - i - 1)) in
        if key = "" then None else Some (key, value)
  ) lines

(* Find all vex.yaml files from dir up to filesystem root.
   Returns list ordered from nearest (highest priority) to farthest. *)
let find_yaml_chain dir =
  let rec walk current acc =
    let candidate = Filename.concat current "vex.yaml" in
    let acc = if Sys.file_exists candidate then candidate :: acc else acc in
    let parent = Filename.dirname current in
    if parent = current then
      (* Reached root *)
      List.rev acc
    else
      walk parent acc
  in
  (* walk returns farthest-first, rev makes it nearest-first *)
  List.rev (walk dir [])

(* Merge variable lists. Later entries override earlier ones. *)
let merge_vars base override =
  let merged = List.filter (fun (k, _) ->
    not (List.mem_assoc k override)
  ) base in
  merged @ override

(* Resolve all variables for a test file:
   env vars < farthest vex.yaml < ... < nearest vex.yaml < frontmatter *)
let resolve_vars test_file_path frontmatter_vars =
  let dir = Filename.dirname (
    if Filename.is_relative test_file_path then
      Filename.concat (Sys.getcwd ()) test_file_path
    else
      test_file_path
  ) in
  let yaml_chain = find_yaml_chain dir in
  (* Start with vars from farthest vex.yaml, layer closer ones on top *)
  let yaml_vars = List.fold_left (fun acc path ->
    let vars = parse_yaml path in
    merge_vars acc vars
  ) [] yaml_chain in
  (* Frontmatter wins over everything *)
  merge_vars yaml_vars frontmatter_vars

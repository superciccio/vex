(* Parse a .test.md file into a test_file structure.

   Format supports two styles:

   Style 1 (original): code block tag IS the action type
     ```run
     curl -s http://example.com
     ```
     ```expect
     hello
     ```

   Style 2 (rich): blockquote label before code block
     > **run** `shell`
     ```bash
     curl -s http://example.com
     ```
     > **expect** `exact`
     ```json
     hello
     ```

   Style 2 gives you syntax highlighting in VS Code for free.
   Both styles can be mixed in the same file. *)

type block = {
  tag : string;         (* vex action: "run", "expect", "assert.script", etc. *)
  fence_lang : string;  (* code fence language: "bash", "python", "json", etc. *)
  content : string;
  block_line : int;
}

(* Extract vex action from a blockquote label line.
   Parses: "> **run**" "> **run** `shell`"
           "> **expect** `exact`" "> **expect** `contains`"
   Returns the vex tag: "run", "expect", "expect.status", etc. *)
let parse_label line =
  let trimmed = String.trim line in
  if String.length trimmed >= 2 && trimmed.[0] = '>' then begin
    let after_gt = String.trim (String.sub trimmed 1 (String.length trimmed - 1)) in
    (* Extract the bold word: **word** *)
    if String.length after_gt >= 5
       && String.sub after_gt 0 2 = "**" then begin
      match String.index_from_opt after_gt 2 '*' with
      | Some i when i + 1 < String.length after_gt && after_gt.[i + 1] = '*' ->
        let action = String.sub after_gt 2 (i - 2) in
        (* Extract optional backtick qualifier: `qualifier` *)
        let rest = String.trim (String.sub after_gt (i + 2) (String.length after_gt - i - 2)) in
        let qualifier =
          if String.length rest >= 3 && rest.[0] = '`' then
            match String.index_from_opt rest 1 '`' with
            | Some j -> Some (String.sub rest 1 (j - 1))
            | None -> None
          else None
        in
        (* Build the vex tag *)
        (match action, qualifier with
         | "run", _ -> Some "run"
         | "expect", Some "exact" -> Some "expect"
         | "expect", Some "contains" -> Some "expect.contains"
         | "expect", Some "status" -> Some "expect.status"
         | "expect", Some "stderr" -> Some "expect.stderr"
         | "expect", None -> Some "expect"
         | "assert", Some "script" -> Some "assert.script"
         | "assert", None -> Some "assert.script"
         | _ -> None)
      | _ -> None
    end else None
  end else None

(* Parse fenced blocks and headings from markdown body *)
let parse_body body =
  let lines = String.split_on_char '\n' body in
  let current_suite = ref "" in
  let current_test = ref "" in
  let current_test_line = ref 0 in
  let current_blocks : block list ref = ref [] in
  let in_block = ref false in
  let block_tag = ref "" in
  let block_fence_lang = ref "" in
  let block_start_line = ref 0 in
  let block_buf = Buffer.create 256 in
  let pending_label = ref None in

  let suites : (string * Types.test list) list ref = ref [] in
  let tests_acc : Types.test list ref = ref [] in

  let flush_test () =
    if !current_test <> "" && !current_blocks <> [] then begin
      let blocks = List.rev !current_blocks in
      let command = List.fold_left (fun acc (b : block) ->
        if String.length b.tag >= 3 && String.sub b.tag 0 3 = "run" then
          b.content
        else acc
      ) "" blocks in
      let assertions = List.filter_map (fun (b : block) ->
        let tag = b.tag in
        if tag = "expect" then
          Some Types.{ kind = Exact; expected = b.content }
        else if tag = "expect.status" then
          Some Types.{ kind = Status; expected = b.content }
        else if tag = "expect.stderr" then
          Some Types.{ kind = Stderr; expected = b.content }
        else if tag = "expect.contains" then
          Some Types.{ kind = Contains; expected = b.content }
        else if tag = "assert.script" then
          Some Types.{ kind = Script b.fence_lang; expected = b.content }
        else
          None
      ) blocks in
      if command <> "" then
        tests_acc := { Types.name = !current_test;
                       line = !current_test_line;
                       command;
                       assertions } :: !tests_acc
    end;
    current_test := "";
    current_blocks := []
  in

  let flush_suite () =
    flush_test ();
    if !current_suite <> "" && !tests_acc <> [] then
      suites := (!current_suite, List.rev !tests_acc) :: !suites;
    tests_acc := []
  in

  let line_num = ref 0 in
  List.iter (fun line ->
    incr line_num;
    if !in_block then begin
      if String.length line >= 3 && String.sub line 0 3 = "```" then begin
        in_block := false;
        let content = Buffer.contents block_buf in
        let content = if content <> "" && content.[String.length content - 1] = '\n'
          then String.sub content 0 (String.length content - 1)
          else content in
        current_blocks := { tag = !block_tag; fence_lang = !block_fence_lang; content; block_line = !block_start_line } :: !current_blocks
      end else begin
        Buffer.add_string block_buf line;
        Buffer.add_char block_buf '\n'
      end
    end else begin
      let trimmed = String.trim line in
      (* Check if this line is a blockquote label *)
      match parse_label trimmed with
      | Some label ->
        pending_label := Some label
      | None ->
        if String.length trimmed >= 3 && String.sub trimmed 0 3 = "```" && trimmed <> "```" then begin
          in_block := true;
          (* If there's a pending label from a blockquote, use that as the tag.
             Otherwise fall back to the code fence tag (original style). *)
          let fence_tag = String.trim (String.sub trimmed 3 (String.length trimmed - 3)) in
          block_fence_lang := fence_tag;
          block_tag := (match !pending_label with
            | Some label -> label
            | None -> fence_tag);
          pending_label := None;
          block_start_line := !line_num;
          Buffer.clear block_buf
        end else if String.length trimmed >= 4 && String.sub trimmed 0 3 = "## " then begin
          pending_label := None;
          flush_test ();
          current_test := String.trim (String.sub trimmed 3 (String.length trimmed - 3));
          current_test_line := !line_num
        end else if String.length trimmed >= 2 && trimmed.[0] = '#' && trimmed.[1] = ' ' then begin
          pending_label := None;
          flush_suite ();
          current_suite := String.trim (String.sub trimmed 2 (String.length trimmed - 2))
        end else
          pending_label := None
    end
  ) lines;

  flush_suite ();
  List.rev !suites

let parse path =
  let content = In_channel.with_open_text path In_channel.input_all in
  let (variables, body) = Frontmatter.parse content in
  let suite_pairs = parse_body body in
  let suites = List.map (fun (name, tests) ->
    Types.{ name; tests }
  ) suite_pairs in
  Types.{ path; variables; suites }

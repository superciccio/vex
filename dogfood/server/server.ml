(* Dogfood CRUD server — in-memory item store *)

let next_id = ref 1
let items : (int * Yojson.Safe.t) list ref = ref []

let json_headers = ["Content-Type", "application/json"]

let item_to_json (id, data) =
  match data with
  | `Assoc fields -> `Assoc (("id", `Int id) :: fields)
  | _ -> `Assoc [("id", `Int id); ("data", data)]

let respond_json ?(status=200) body =
  Tiny_httpd.Response.make_raw ~code:status
    ~headers:json_headers
    (Yojson.Safe.to_string body)

let handle_list _req =
  let json = `List (List.map item_to_json !items) in
  respond_json json

let handle_get _req id =
  match List.assoc_opt id !items with
  | Some data -> respond_json (item_to_json (id, data))
  | None -> respond_json ~status:404 (`Assoc [("error", `String "not found")])

let handle_create req =
  let body = Tiny_httpd.Request.body req in
  (match Yojson.Safe.from_string body with
   | data ->
     let id = !next_id in
     incr next_id;
     items := (id, data) :: !items;
     respond_json ~status:201 (item_to_json (id, data))
   | exception _ ->
     respond_json ~status:400 (`Assoc [("error", `String "invalid JSON")]))

let handle_delete _req id =
  if List.mem_assoc id !items then begin
    items := List.remove_assoc id !items;
    respond_json (`Assoc [("deleted", `Int id)])
  end else
    respond_json ~status:404 (`Assoc [("error", `String "not found")])

let () =
  let port = try int_of_string (Sys.getenv "PORT") with _ -> 8080 in
  let server = Tiny_httpd.create ~port () in

  Tiny_httpd.add_route_handler server
    Tiny_httpd.Route.(exact "items" @/ return)
    (fun req ->
       match Tiny_httpd.Request.meth req with
       | `GET -> handle_list req
       | `POST -> handle_create req
       | _ -> respond_json ~status:405 (`Assoc [("error", `String "method not allowed")]));

  Tiny_httpd.add_route_handler server
    Tiny_httpd.Route.(exact "items" @/ int @/ return)
    (fun id req ->
       match Tiny_httpd.Request.meth req with
       | `GET -> handle_get req id
       | `DELETE -> handle_delete req id
       | _ -> respond_json ~status:405 (`Assoc [("error", `String "method not allowed")]));

  Printf.printf "dogfood server on http://localhost:%d\n%!" port;
  match Tiny_httpd.run server with
  | Ok () -> ()
  | Error e -> Printf.eprintf "Server error: %s\n" (Printexc.to_string e); exit 1

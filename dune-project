(lang dune 3.0)
(name vex)
(generate_opam_files true)

(package
 (name vex)
 (synopsis "A literate API test runner for humans and LLMs")
 (description
  "Write API tests as Markdown. Assert with a built-in mini-ML language. No external runtimes needed.")
 (depends
  (ocaml (>= 4.14))
  (dune (>= 3.0))
  yojson)
 (license MIT))

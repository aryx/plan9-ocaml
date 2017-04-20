exception Exn1 of string
exception Exn2 of string

let bar x =
  if true
  then raise (Exn1 "bar")
  else 1

let foo x = 
  bar x

let test () =
  let x = 1+1 in
  let s = Printf.sprintf "hello world %d\n" x in
  print_string s;
  (try 
    let x = foo 42 in
    print_string (Printf.sprintf "res = %d" x);
  with Exn1 s ->
    print_string (Printf.sprintf "exn1 = %s" s);
  );

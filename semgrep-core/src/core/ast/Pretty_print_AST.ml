(* Emma Jin
 *
 * Copyright (C) 2020 r2c
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public License
 * version 2.1 as published by the Free Software Foundation, with the
 * special exception on linking described in file license.txt.
 *
 * This library is distributed in the hope that it will be useful, but
 * WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the file
 * license.txt for more details.
 *)
open Common
open AST_generic
module F = Format
module G = AST_generic
module PI = Parse_info

(*****************************************************************************)
(* Prelude *)
(*****************************************************************************)
(* Pretty print AST generic code (can also be a semgrep pattern).
 *
 * This will be useful for the pattern-from-code synthesizing project but
 * also for correct autofixing.
 *
 * TODO: Pretty printing library to use:
 *  - OCaml Format lib? see pfff/commons/OCaml.string_of_v for an example
 *  - Martin's easy-format?
 *  - Wadler's pretty-printer combinators?
 *)

(*****************************************************************************)
(* Types *)
(*****************************************************************************)
type env = { (*mvars : Metavariable.bindings;*) lang : Lang.t }

(*****************************************************************************)
(* Helpers *)
(*****************************************************************************)
let todo any =
  pr2 (show_any any);
  "*TODO*"

let ident (s, _) = s

let ident_or_dynamic = function
  | EN (Id (x, _idinfo)) -> ident x
  | EN _
  | EDynamic _
  | EPattern _
  | OtherEntity _ ->
      raise Todo

let opt f = function
  | None -> ""
  | Some x -> f x

(* pad: note that Parse_info.str_of_info does not raise an exn anymore
 * on fake tokens. It instead returns the fake token string
 *)
let token default tok =
  try Parse_info.str_of_info tok with
  | Parse_info.NoTokenLocation _ -> default

let print_type t =
  match t.t with
  | TyN (Id (id, _)) -> ident id
  | _ -> todo (T t)

let print_bool env = function
  | true -> (
      match env.lang with
      | Lang.Dart
      | Lang.Julia ->
          raise Todo
      | Lang.Python
      | Lang.Python2
      | Lang.Python3 ->
          "True"
      | Lang.Elixir
      | Lang.Java
      | Lang.Go
      | Lang.C
      | Lang.Cpp
      | Lang.Js
      | Lang.Json
      | Lang.Yaml
      | Lang.Ocaml
      | Lang.Ruby
      | Lang.Ts
      | Lang.Vue
      | Lang.Csharp
      | Lang.Php
      | Lang.Hack
      | Lang.Kotlin
      | Lang.Lua
      | Lang.Bash
      | Lang.Dockerfile
      | Lang.Rust
      | Lang.Scala
      | Lang.Solidity
      | Lang.Swift
      | Lang.Html
      | Lang.Hcl ->
          "true"
      | Lang.R -> "TRUE")
  | false -> (
      match env.lang with
      | Lang.Dart
      | Lang.Julia ->
          raise Todo
      | Lang.Python
      | Lang.Python2
      | Lang.Python3 ->
          "False"
      | Lang.Elixir
      | Lang.Java
      | Lang.Go
      | Lang.C
      | Lang.Cpp
      | Lang.Json
      | Lang.Yaml
      | Lang.Js
      | Lang.Ocaml
      | Lang.Ruby
      | Lang.Ts
      | Lang.Csharp
      | Lang.Vue
      | Lang.Php
      | Lang.Hack
      | Lang.Kotlin
      | Lang.Lua
      | Lang.Bash
      | Lang.Dockerfile
      | Lang.Rust
      | Lang.Scala
      | Lang.Solidity
      | Lang.Swift
      | Lang.Html
      | Lang.Hcl ->
          "false"
      | Lang.R -> "FALSE")

let arithop env (op, tok) =
  match op with
  | Plus -> "+"
  | Minus -> "-"
  | Mult -> "*"
  | Div -> "/"
  | Mod -> "%"
  | Pow -> "**"
  | Eq -> (
      match env.lang with
      | Lang.Ocaml -> "="
      | _ -> "==")
  | Lt -> "<"
  | LtE -> "<="
  | Gt -> ">"
  | GtE -> ">="
  | NotEq -> "!="
  | _ -> todo (E (IdSpecial (Op op, tok) |> G.e))

(*
      | Pow | FloorDiv | MatMult (* Python *)
      | LSL | LSR | ASR (* L = logic, A = Arithmetic, SL = shift left *)
      | BitOr | BitXor | BitAnd | BitNot (* unary *) | BitClear (* Go *)
      (* todo? rewrite in CondExpr? have special behavior *)
      | And | Or (* also shortcut operator *) | Xor (* PHP*) | Not (* unary *)
      | NotEq     (* less: could be desugared to Not Eq *)
      | PhysEq (* '==' in OCaml, '===' in JS/... *)
      | NotPhysEq (* less: could be desugared to Not PhysEq *)
      | Lt | LtE | Gt | GtE  (* less: could be desugared to Or (Eq Lt) *)
      | Cmp (* <=>, PHP *)
      (* todo: not really an arithmetic operator, maybe rename the type *)
      | Concat (* '.' PHP *) *)

(*****************************************************************************)
(* Pretty printer *)
(*****************************************************************************)

(* statements *)

let rec stmt env level st =
  match st.s with
  | ExprStmt (e, tok) -> F.sprintf "%s%s" (expr env e) (token "" tok)
  | Block x -> block env x level
  | If (tok, e, s, sopt) -> if_stmt env level (token "if" tok, e, s, sopt)
  | While (tok, e, s) -> while_stmt env level (tok, e, s)
  | DoWhile (_tok, s, e) -> do_while stmt env level (s, e)
  | For (tok, hdr, s) -> for_stmt env level (tok, hdr, s)
  | Return (tok, eopt, sc) -> return env (tok, eopt) sc
  | DefStmt def -> def_stmt env def
  | Break (tok, lbl, sc) -> break env (tok, lbl) sc
  | Continue (tok, lbl, sc) -> continue env (tok, lbl) sc
  | _ -> todo (S st)

and block env (t1, ss, t2) level =
  let rec indent = function
    | 0 -> ""
    | n -> "    " ^ indent (n - 1)
  in
  let rec show_statements env = function
    | [] -> ""
    | [ x ] -> F.sprintf "%s%s" (indent level) (stmt env level x)
    | x :: xs ->
        F.sprintf "%s%s\n%s" (indent level) (stmt env level x)
          (show_statements env xs)
  in
  let get_boundary t =
    let t_str = token "" t in
    match t_str with
    | "" -> ""
    | "{" -> "\n" ^ indent (level - 1) ^ "{\n"
    | "}" -> "\n" ^ indent (level - 1) ^ "}\n"
    | _ -> t_str
  in
  if level > 0 then
    F.sprintf "%s%s%s" (get_boundary t1) (show_statements env ss)
      (get_boundary t2)
  else show_statements env ss

and if_stmt env level (tok, e, s, sopt) =
  let rec indent = function
    | 0 -> ""
    | n -> "    " ^ indent (n - 1)
  in
  let no_paren_cond = F.sprintf "%s %s" in
  (* if cond *)
  let paren_cond = F.sprintf "%s (%s)" in
  (* if cond *)
  let colon_body = F.sprintf "%s:\n%s\n" in
  (* (if cond) body *)
  let bracket_body = F.sprintf "%s %s" (* (if cond) body *) in
  let format_cond, elseif_str, format_block =
    match env.lang with
    | Lang.Dart
    | Lang.Julia
    | Lang.Elixir
    | Lang.Bash
    | Lang.Dockerfile
    | Lang.Ruby
    | Lang.Ocaml
    | Lang.Scala
    | Lang.Solidity
    | Lang.Php
    | Lang.Hack
    | Lang.Yaml
    | Lang.Html
    | Lang.Hcl ->
        raise Todo
    | Lang.Python
    | Lang.Python2
    | Lang.Python3 ->
        (no_paren_cond, "elif", colon_body)
    | Lang.Java
    | Lang.Go
    | Lang.C
    | Lang.Cpp
    | Lang.Csharp
    | Lang.Json
    | Lang.Js
    | Lang.Ts
    | Lang.Vue
    | Lang.Kotlin
    | Lang.Rust
    | Lang.R
    (* Swift does not require parentheses around the condition, but it does
     * permit them. *)
    | Lang.Swift ->
        (paren_cond, "else if", bracket_body)
    | Lang.Lua -> (paren_cond, "elseif", bracket_body)
  in
  let e_str = format_cond tok (condition env e) in
  let s_str = stmt env (level + 1) s in
  let if_stmt_prt = format_block e_str s_str in
  match sopt with
  | None -> if_stmt_prt
  | Some { s = If (_, e', s', sopt'); _ } ->
      F.sprintf "%s%s" if_stmt_prt
        (if_stmt env level (indent level ^ elseif_str, e', s', sopt'))
  | Some { s = Block (_, [ { s = If (_, e', s', sopt'); _ } ], _); _ } ->
      F.sprintf "%s%s" if_stmt_prt
        (if_stmt env level (indent level ^ elseif_str, e', s', sopt'))
  | Some body ->
      F.sprintf "%s%s" if_stmt_prt
        (format_block (indent level ^ "else") (stmt env (level + 1) body))

and condition env x =
  match x with
  | Cond e -> expr env e
  | OtherCond _ -> raise Todo

and while_stmt env level (tok, e, s) =
  let ocaml_while = F.sprintf "%s %s do\n%s\ndone" in
  let python_while = F.sprintf "%s %s:\n%s" in
  let go_while = F.sprintf "%s %s %s" in
  let c_while = F.sprintf "%s (%s) %s" in
  let ruby_while = F.sprintf "%s %s\n %s\nend" in
  let while_format =
    match env.lang with
    | Lang.Dart
    | Lang.Julia
    | Lang.Elixir
    | Lang.Bash
    | Lang.Php
    | Lang.Dockerfile
    | Lang.Hack
    | Lang.Lua
    | Lang.Yaml
    | Lang.Scala
    | Lang.Solidity
    | Lang.Swift
    | Lang.Html
    | Lang.Hcl ->
        raise Todo
    | Lang.Python
    | Lang.Python2
    | Lang.Python3 ->
        python_while
    | Lang.Java
    | Lang.C
    | Lang.Cpp
    | Lang.Csharp
    | Lang.Kotlin
    | Lang.Json
    | Lang.Js
    | Lang.Ts
    | Lang.Vue
    | Lang.Rust
    | Lang.R ->
        c_while
    | Lang.Go -> go_while
    | Lang.Ruby -> ruby_while
    | Lang.Ocaml -> ocaml_while
  in
  while_format (token "while" tok) (condition env e) (stmt env (level + 1) s)

and do_while stmt env level (s, e) =
  let c_do_while = F.sprintf "do %s\nwhile(%s)" in
  let do_while_format =
    match env.lang with
    | Lang.Dart
    | Lang.Julia
    | Lang.Elixir
    | Lang.Bash
    | Lang.Php
    | Lang.Dockerfile
    | Lang.Hack
    | Lang.Lua
    | Lang.Yaml
    | Lang.Scala
    | Lang.Solidity
    | Lang.Swift
    | Lang.Html
    | Lang.Hcl ->
        raise Todo
    | Lang.Java
    | Lang.C
    | Lang.Cpp
    | Lang.Csharp
    | Lang.Kotlin
    | Lang.Js
    | Lang.Ts
    | Lang.Vue ->
        c_do_while
    | Lang.Python
    | Lang.Python2
    | Lang.Python3
    | Lang.Go
    | Lang.Json
    | Lang.Ocaml
    | Lang.Rust
    | Lang.R ->
        failwith "impossible; no do while"
    | Lang.Ruby -> failwith "ruby is so weird (here, do while loop)"
  in
  do_while_format (stmt env (level + 1) s) (expr env e)

and for_stmt env level (for_tok, hdr, s) =
  let for_format =
    match env.lang with
    | Lang.Dart
    | Lang.Julia
    | Lang.Elixir
    | Lang.Bash
    | Lang.Php
    | Lang.Html
    | Lang.Dockerfile
    | Lang.Hack
    | Lang.Lua
    | Lang.Yaml
    | Lang.Scala
    | Lang.Solidity
    | Lang.Hcl ->
        raise Todo
    | Lang.Java
    | Lang.C
    | Lang.Cpp
    | Lang.Csharp
    | Lang.Kotlin
    | Lang.Js
    | Lang.Ts
    | Lang.Vue
    | Lang.Rust
    | Lang.R
    | Lang.Swift ->
        F.sprintf "%s (%s) %s"
    | Lang.Go -> F.sprintf "%s %s %s"
    | Lang.Python
    | Lang.Python2
    | Lang.Python3 ->
        F.sprintf "%s %s:\n%s"
    | Lang.Ruby -> F.sprintf "%s %s\ndo %s\nend"
    | Lang.Json
    | Lang.Ocaml ->
        failwith "JSON/OCaml has for loops????"
  in
  let show_init = function
    | ForInitVar (ent, var_def) ->
        F.sprintf "%s%s%s"
          (opt (fun x -> print_type x ^ " ") var_def.vtype)
          (ident_or_dynamic ent.name)
          (opt (fun x -> " = " ^ expr env x) var_def.vinit)
    | ForInitExpr e_init -> expr env e_init
  in
  let rec show_init_list = function
    | [] -> ""
    | [ x ] -> show_init x
    | x :: xs -> show_init x ^ ", " ^ show_init_list xs
  in
  let opt_expr = opt (fun x -> expr env x) in
  let hdr_str =
    let for_each (pat, tok, e) =
      F.sprintf "%s %s %s" (pattern env pat) (token "in" tok) (expr env e)
    in
    let multi_for_each = function
      | FE fe -> for_each fe
      | FECond (fe, _, e) -> F.sprintf "%s if %s" (for_each fe) (expr env e)
      | FEllipsis _ -> "..."
    in
    match hdr with
    | ForClassic (init, cond, next) ->
        F.sprintf "%s; %s; %s" (show_init_list init) (opt_expr cond)
          (opt_expr next)
    | ForEach (pat, tok, e) -> for_each (pat, tok, e)
    | MultiForEach fors -> String.concat ";" (Common.map multi_for_each fors)
    | ForEllipsis tok -> token "..." tok
    | ForIn (init, exprs) ->
        F.sprintf "%s %s %s" (show_init_list init) "in"
          (String.concat "," (Common.map (fun e -> expr env e) exprs))
  in
  let body_str = stmt env (level + 1) s in
  for_format (token "for" for_tok) hdr_str body_str

and def_stmt env (entity, def_kind) =
  let var_def (ent, def) =
    let no_val, with_val =
      match env.lang with
      | Lang.Dart
      | Lang.Julia
      | Lang.Elixir
      | Lang.Bash
      | Lang.Php
      | Lang.Dockerfile
      | Lang.Hack
      | Lang.Lua
      | Lang.Yaml
      | Lang.Scala
      | Lang.Solidity
      | Lang.Swift
      | Lang.Html
      | Lang.Hcl ->
          raise Todo
      | Lang.Java
      | Lang.C
      | Lang.Cpp
      | Lang.Csharp
      | Lang.Kotlin ->
          ( (fun typ id _e -> F.sprintf "%s %s;" typ id),
            fun typ id e -> F.sprintf "%s %s = %s;" typ id e )
      | Lang.Js
      | Lang.Ts
      | Lang.Vue ->
          ( (fun _typ id _e -> F.sprintf "var %s;" id),
            fun _typ id e -> F.sprintf "var %s = %s;" id e )
      | Lang.Go ->
          ( (fun typ id _e -> F.sprintf "var %s %s" id typ),
            fun typ id e -> F.sprintf "var %s %s = %s" id typ e )
          (* will have extra space if no type *)
      | Lang.Python
      | Lang.Python2
      | Lang.Python3
      | Lang.Ruby ->
          ( (fun _typ id _e -> F.sprintf "%s" id),
            fun _typ id e -> F.sprintf "%s = %s" id e )
      | Lang.Rust ->
          ( (fun typ id _e -> F.sprintf "let %s: %s" id typ),
            fun typ id e -> F.sprintf "let %s: %s = %s" id typ e )
          (* will have extra space if no type *)
      | Lang.R ->
          ( (fun _typ id _e -> F.sprintf "%s" id),
            fun _typ id e -> F.sprintf "%s <- %s" id e )
      | Lang.Json
      | Lang.Ocaml ->
          failwith "I think JSON/OCaml have no variable definitions"
    in
    let typ, id =
      match ent.name with
      | EN (Id (_, { id_type = { contents = Some t }; _ })) ->
          (print_type t, ident_or_dynamic ent.name)
      | _ -> ("", ident_or_dynamic ent.name)
    in
    match def.vinit with
    | None -> no_val typ id ""
    | Some e -> with_val typ id (expr env e)
  in
  match def_kind with
  | VarDef def -> var_def (entity, def)
  | _ -> todo (S (DefStmt (entity, def_kind) |> G.s))

and return env (tok, eopt) _sc =
  let to_return =
    match eopt with
    | None -> ""
    | Some e -> expr env e
  in
  match env.lang with
  | Lang.Dart
  | Lang.Julia
  | Lang.Elixir
  | Lang.Bash
  | Lang.Php
  | Lang.Dockerfile
  | Lang.Hack
  | Lang.Yaml
  | Lang.Scala
  | Lang.Solidity
  | Lang.Html
  | Lang.Hcl ->
      raise Todo
  | Lang.Java
  | Lang.C
  | Lang.Cpp
  | Lang.Csharp
  | Lang.Kotlin
  | Lang.Rust ->
      F.sprintf "%s %s;" (token "return" tok) to_return
  | Lang.Python
  | Lang.Python2
  | Lang.Python3
  | Lang.Go
  | Lang.Ruby
  | Lang.Ocaml
  | Lang.Json
  | Lang.Js
  | Lang.Swift
  | Lang.Ts
  | Lang.Vue
  | Lang.Lua ->
      F.sprintf "%s %s" (token "return" tok) to_return
  | Lang.R -> F.sprintf "%s(%s)" (token "return" tok) to_return

and break env (tok, lbl) _sc =
  let lbl_str =
    match lbl with
    | LNone -> ""
    | LId l -> F.sprintf " %s" (ident l)
    | LInt (n, _) -> F.sprintf " %d" n
    | LDynamic e -> F.sprintf " %s" (expr env e)
  in
  match env.lang with
  | Lang.Dart
  | Lang.Julia
  | Lang.Elixir
  | Lang.Bash
  | Lang.Php
  | Lang.Dockerfile
  | Lang.Hack
  | Lang.Yaml
  | Lang.Scala
  | Lang.Solidity
  | Lang.Html
  | Lang.Hcl ->
      raise Todo
  | Lang.Java
  | Lang.C
  | Lang.Cpp
  | Lang.Csharp
  | Lang.Kotlin
  | Lang.Rust ->
      F.sprintf "%s%s;" (token "break" tok) lbl_str
  | Lang.Python
  | Lang.Python2
  | Lang.Python3
  | Lang.Go
  | Lang.Ruby
  | Lang.Ocaml
  | Lang.Json
  | Lang.Js
  | Lang.Ts
  | Lang.Vue
  | Lang.Lua
  | Lang.R
  | Lang.Swift ->
      F.sprintf "%s%s" (token "break" tok) lbl_str

and continue env (tok, lbl) _sc =
  let lbl_str =
    match lbl with
    | LNone -> ""
    | LId l -> F.sprintf " %s" (ident l)
    | LInt (n, _) -> F.sprintf " %d" n
    | LDynamic e -> F.sprintf " %s" (expr env e)
  in
  match env.lang with
  | Lang.Dart
  | Lang.Julia
  | Lang.Elixir
  | Lang.Bash
  | Lang.Php
  | Lang.Dockerfile
  | Lang.Hack
  | Lang.Yaml
  | Lang.Scala
  | Lang.Solidity
  | Lang.Html
  | Lang.Hcl ->
      raise Todo
  | Lang.Java
  | Lang.C
  | Lang.Cpp
  | Lang.Csharp
  | Lang.Kotlin
  | Lang.Lua
  | Lang.Rust ->
      F.sprintf "%s%s;" (token "continue" tok) lbl_str
  | Lang.Python
  | Lang.Python2
  | Lang.Python3
  | Lang.Go
  | Lang.Ruby
  | Lang.Ocaml
  | Lang.Json
  | Lang.Js
  | Lang.Swift
  | Lang.Ts
  | Lang.Vue ->
      F.sprintf "%s%s" (token "continue" tok) lbl_str
  | Lang.R -> F.sprintf "%s%s" (token "next" tok) lbl_str

(* expressions *)
and expr env e =
  match e.e with
  | N (Id ((s, _), idinfo)) -> id env (s, idinfo)
  | N (IdQualified qualified_info) -> id_qualified env qualified_info
  | IdSpecial (sp, tok) -> special env (sp, tok)
  | Call (e1, e2) -> call env (e1, e2)
  | New (_, t, es) -> new_call env (t, es)
  | L x -> literal env x
  | Container (Tuple, (_, es, _)) -> F.sprintf "(%s)" (tuple env es)
  | ArrayAccess (e1, (_, e2, _)) ->
      F.sprintf "%s[%s]" (expr env e1) (expr env e2)
  | Assign (e1, tok, e2) ->
      F.sprintf "%s %s %s" (expr env e1) (token "=" tok) (expr env e2)
  | AssignOp (e1, op, e2) ->
      F.sprintf "%s %s= %s" (expr env e1) (arithop env op) (expr env e2)
  | SliceAccess (e, (_, (o1, o2, o3), _)) -> slice_access env e (o1, o2) o3
  | DotAccess (e, tok, fi) -> dot_access env (e, tok, fi)
  | Ellipsis _ -> "..."
  | Conditional (e1, e2, e3) -> cond env (e1, e2, e3)
  | OtherExpr (categ, anys) -> other env (categ, anys)
  | TypedMetavar (id, _, typ) -> tyvar env (id, typ)
  | _x -> todo (E e)

and id env (s, { id_resolved; _ }) =
  match !id_resolved with
  | Some (ImportedEntity ents, _) -> dotted_access env ents
  | Some (ImportedModule (DottedName ents), _) -> dotted_access env ents
  | _ -> s

(* TODO: look at name_top too *)
and id_qualified env { name_last = id, _toptTODO; name_middle; name_top; _ } =
  (match name_top with
  | None -> ""
  | Some _t -> "::")
  ^
  match name_middle with
  | Some (QDots dot_ids) ->
      (* TODO: do not do fst, look also at type qualification *)
      F.sprintf "%s.%s" (dotted_access env (Common.map fst dot_ids)) (ident id)
  | Some (QExpr (e, _t)) -> expr env e ^ "::"
  | None -> ident id

and special env = function
  | This, _ -> "this"
  | Op op, tok -> arithop env (op, tok)
  | IncrDecr _, _ -> "" (* should be captured in the call *)
  | sp, tok -> todo (E (IdSpecial (sp, tok) |> G.e))

and new_call env (t, (_, es, _)) =
  let s1 = print_type t in
  F.sprintf "new %s(%s)" s1 (arguments env es)

and call env (e, (_, es, _)) =
  let s1 = expr env e in
  match (e.e, es) with
  | IdSpecial (Op In, _), [ e1; e2 ] ->
      F.sprintf "%s in %s" (argument env e1) (argument env e2)
  | IdSpecial (Op NotIn, _), [ e1; e2 ] ->
      F.sprintf "%s not in %s" (argument env e1) (argument env e2)
  | IdSpecial (Op _, _), [ x; y ] ->
      F.sprintf "%s %s %s" (argument env x) s1 (argument env y)
  | IdSpecial (IncrDecr (i_d, pre_post), _), [ x ] -> (
      let op_str =
        match i_d with
        | Incr -> "++"
        | Decr -> "--"
      in
      match pre_post with
      | Prefix -> F.sprintf "%s%s" op_str (argument env x)
      | Postfix -> F.sprintf "%s%s" (argument env x) op_str)
  | _ -> F.sprintf "%s(%s)" s1 (arguments env es)

and literal env l =
  match l with
  | Bool (b, _) -> print_bool env b
  | Int (_, t) -> PI.str_of_info t
  | Float (_, t) -> PI.str_of_info t
  | Char (s, _) -> F.sprintf "'%s'" s
  | String (s, _) -> (
      match env.lang with
      | Lang.Dart
      | Lang.Julia
      | Lang.Elixir
      | Lang.Bash
      | Lang.Php
      | Lang.Dockerfile
      | Lang.Hack
      | Lang.Yaml
      | Lang.Scala
      | Lang.Solidity
      | Lang.Html
      | Lang.Hcl ->
          raise Todo
      | Lang.Python
      | Lang.Python2
      | Lang.Python3 ->
          "'" ^ s ^ "'"
      | Lang.Java
      | Lang.Go
      | Lang.C
      | Lang.Cpp
      | Lang.Csharp
      | Lang.Kotlin
      | Lang.Json
      | Lang.Js
      | Lang.Vue
      | Lang.Ocaml
      | Lang.Ruby
      | Lang.Ts
      | Lang.Lua
      | Lang.Rust
      | Lang.R
      | Lang.Swift ->
          "\"" ^ s ^ "\"")
  | x -> todo (E (L x |> G.e))

and arguments env xs =
  match xs with
  | [] -> ""
  | [ x ] -> argument env x
  | x :: y :: xs -> argument env x ^ ", " ^ arguments env (y :: xs)

and argument env = function
  | Arg e -> expr env e
  | ArgType t -> print_type t
  | ArgKwd (id, e) -> F.sprintf "%s=%s" (ident id) (expr env e)
  | ArgKwdOptional (id, e) -> F.sprintf "%s=?%s" (ident id) (expr env e)
  | x -> todo (Ar x)

and tuple env = function
  | [] -> ""
  | [ x ] -> expr env x
  | x :: y :: xs -> expr env x ^ ", " ^ tuple env (y :: xs)

and dotted_access env = function
  | [] -> ""
  | [ x ] -> ident x
  | x :: y :: xs -> ident x ^ "." ^ dotted_access env (y :: xs)

and slice_access env e (o1, o2) = function
  | None -> F.sprintf "%s[%s:%s]" (expr env e) (option env o1) (option env o2)
  | Some e1 ->
      F.sprintf "%s[%s:%s:%s]" (expr env e) (option env o1) (option env o2)
        (expr env e1)

and option env = function
  | None -> ""
  | Some e -> expr env e

and other _env (op, anys) =
  match (op, anys) with
  | _ -> todo (E (OtherExpr (op, anys) |> G.e))

and dot_access env (e, _tok, fi) =
  F.sprintf "%s.%s" (expr env e) (field_ident env fi)

and field_ident env fi =
  match fi with
  | FN (Id (id, _idinfo)) -> ident id
  | FN (IdQualified qualified_info) -> id_qualified env qualified_info
  | FDynamic e -> expr env e

and tyvar env (id, typ) =
  match env.lang with
  | Lang.Java -> F.sprintf "(%s %s)" (print_type typ) (ident id)
  | Lang.Go -> F.sprintf "(%s : %s)" (ident id) (print_type typ)
  | _ -> failwith "Not implemented for this language"

and cond env (e1, e2, e3) =
  let s1 = expr env e1 in
  let s2 = expr env e2 in
  let s3 = expr env e3 in
  match env.lang with
  | Lang.Python -> F.sprintf "%s if %s else %s" s2 s1 s3
  | Lang.Ocaml -> F.sprintf "if %s then %s else %s" s1 s2 s3
  | Lang.Java -> F.sprintf "%s ? %s : %s" s1 s2 s3
  | _ -> todo (E (Conditional (e1, e2, e3) |> G.e))

(* patterns *)
and pattern env = function
  | PatLiteral l -> literal env l
  | PatId (id, _id_info) -> ident id
  | x -> todo (P x)

let ctype = function
  | G.Cbool -> "bool"
  | G.Cint -> "int"
  | G.Cstr -> "str"
  | G.Cany -> "???"

let svalue env = function
  | G.NotCst -> "TOP"
  | G.Sym e -> Printf.sprintf "sym(%s)" (expr env e)
  | G.Cst t -> Printf.sprintf "cst(%s)" (ctype t)
  | G.Lit l -> Printf.sprintf "lit(%s)" (literal env l)

(*****************************************************************************)
(* Entry points *)
(*****************************************************************************)

let expr_to_string lang (*mvars*) e =
  let env = { lang (*mvars*) } in
  expr env e

let stmt_to_string lang (*mvars*) s =
  let env = { lang (*mvars*) } in
  stmt env 0 s

let arguments_to_string lang x =
  let env = { lang } in
  arguments env x

let svalue_to_string lang c =
  let env = { lang (* mvars = [] *) } in
  svalue env c

module R = Rule
module RM = Range_with_metavars
module G = AST_generic
module MV = Metavariable
module PM = Pattern_match
module RP = Report

type selector = {
  mvar : MV.mvar;
  pattern : AST_generic.any;
  pid : int;
  pstr : string R.wrap;
}
[@@deriving show]

type sformula =
  | Leaf of Xpattern.t * R.inside option
  | And of Rule.tok * sformula_and
  | Or of Rule.tok * sformula list
  (* There are restrictions on where a Not can appear in a formula. It
   * should always be inside an And to be intersected with "positive" formula.
   *)
  | Not of Rule.tok * sformula

and sformula_and = {
  selector_opt : selector option;
  positives : sformula list;
  negatives : (Rule.tok * sformula) list;
  conditionals : (Rule.tok * R.metavar_cond) list;
  focus : (Rule.tok * MV.mvar) list;
}
[@@deriving show]

(*****************************************************************************)
(* Selecting methods *)
(*****************************************************************************)

let selector_equal s1 s2 = s1.mvar = s2.mvar

(*****************************************************************************)
(* Converter *)
(*****************************************************************************)

let selector_from_formula f =
  match f with
  | Leaf ({ pat = Sem (pattern, _); pid; pstr }, None) -> (
      match pattern with
      | G.E { e = G.N (G.Id ((mvar, _), _)); _ } when MV.is_metavar_name mvar ->
          Some { mvar; pattern; pid; pstr }
      | _ -> None)
  | _ -> None

let formula_to_sformula formula =
  let rec remove_selectors (selector, acc) formulas =
    match formulas with
    | [] -> (selector, acc)
    | x :: xs ->
        let selector, acc =
          match (selector, selector_from_formula x) with
          | None, None -> (None, x :: acc)
          | Some s, None -> (Some s, x :: acc)
          | None, Some s -> (Some s, acc)
          | Some s1, Some s2 when selector_equal s1 s2 -> (Some s1, acc)
          | Some s1, Some _s2 ->
              (* patterns:
               * ...
               * - pattern: $X
               * - pattern: $Y
               *)
              (* TODO: Should we fail here or just reported as a warning? This
               * is something to catch with the meta-checker. *)
              (Some s1, x :: acc)
        in
        remove_selectors (selector, acc) xs
  in
  let rec formula_to_sformula formula =
    (* Visit formula and convert *)
    match formula with
    | R.P (p, inside) -> Leaf (p, inside)
    | R.And (tok, { conjuncts = fs; conditions = conds; focus }) ->
        And (tok, convert_and_formulas fs conds focus)
    | R.Or (tok, fs) -> Or (tok, Common.map formula_to_sformula fs)
    | R.Not (tok, f) -> Not (tok, formula_to_sformula f)
  and convert_and_formulas fs conditionals focus =
    let pos, neg = Rule.split_and fs in
    let pos = Common.map formula_to_sformula pos in
    let neg = Common.map (fun (t, f) -> (t, formula_to_sformula f)) neg in
    let sel, pos =
      (* We only want a selector if there is something to select from. *)
      match remove_selectors (None, []) pos with
      | _, [] -> (None, pos)
      | sel, pos -> (sel, pos)
    in
    {
      selector_opt = sel;
      positives = pos;
      negatives = neg;
      conditionals;
      focus;
    }
  in
  formula_to_sformula formula

(*****************************************************************************)
(* Visitor *)
(*****************************************************************************)
(* currently used in Match_rules.ml to extract patterns *)
let rec visit_sformula f formula =
  match formula with
  | Leaf (p, i) -> f p i
  | Not (_, x) -> visit_sformula f x
  | Or (_, xs) -> xs |> List.iter (visit_sformula f)
  | And (_, fand) ->
      fand.positives |> List.iter (visit_sformula f);
      fand.negatives |> List.iter (fun (_tk, x) -> visit_sformula f x)

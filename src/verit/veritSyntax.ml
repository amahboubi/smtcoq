(**************************************************************************)
(*                                                                        *)
(*     SMTCoq                                                             *)
(*     Copyright (C) 2011 - 2019                                          *)
(*                                                                        *)
(*     See file "AUTHORS" for the list of authors                         *)
(*                                                                        *)
(*   This file is distributed under the terms of the CeCILL-C licence     *)
(*                                                                        *)
(**************************************************************************)


open SmtAtom
open SmtForm
open SmtCertif
open SmtTrace


(*** Syntax of veriT proof traces ***)

exception Sat

type typ = | Inpu | Deep | True | Fals | Andp | Andn | Orp | Orn | Xorp1 | Xorp2 | Xorn1 | Xorn2 | Impp | Impn1 | Impn2 | Equp1 | Equp2 | Equn1 | Equn2 | Itep1 | Itep2 | Iten1 | Iten2 | Eqre | Eqtr | Eqco | Eqcp | Dlge | Lage | Lata | Dlde | Lade | Fins | Eins | Skea | Skaa | Qnts | Qntm | Reso | Weak | And | Nor | Or | Nand | Xor1 | Xor2 | Nxor1 | Nxor2 | Imp | Nimp1 | Nimp2 | Equ1 | Equ2 | Nequ1 | Nequ2 | Ite1 | Ite2 | Nite1 | Nite2 | Tpal | Tlap | Tple | Tpne | Tpde | Tpsa | Tpie | Tpma | Tpbr | Tpbe | Tpsc | Tppp | Tpqt | Tpqs | Tpsk | Subp | Flat | Hole | Bbva | Bbconst | Bbeq | Bbdis | Bbop | Bbadd | Bbmul | Bbult | Bbslt | Bbnot | Bbneg | Bbconc | Bbextr | Bbzext | Bbsext | Bbshl | Bbshr | Row1 | Row2 | Exte



(* About equality *)

let get_eq l =
  match Form.pform l with
  | Fatom ha ->
     (match Atom.atom ha with
      | Abop (BO_eq _,a,b) -> (a,b)
      | _ -> failwith "VeritSyntax.get_eq: equality was expected")
  | _ -> failwith "VeritSyntax.get_eq: equality was expected"

let get_at l =
  match Form.pform l with
  | Fatom ha -> ha
  | _ -> failwith "VeritSyntax.get_eq: equality was expected"

let is_eq l =
  match Form.pform l with
  | Fatom ha ->
     (match Atom.atom ha with
      | Abop (BO_eq _,_,_) -> true
      | _ -> false)
  | _ -> failwith "VeritSyntax.get_eq: atom was expected"


(* Transitivity *)

let rec list_find_remove p = function
    [] -> raise Not_found
  | h::t -> if p h
            then h, t
            else let (a, rest) = list_find_remove p t in
                 a, h::rest

let rec process_trans a b prem res =
  if List.length prem = 0 then (
    assert (Atom.equal a b);
    List.rev res
  ) else
    let ((l,(c,c')),prem) =
      (* Search if there is a trivial reflexivity premice *)
      try list_find_remove (fun (l,(a',b')) -> ((Atom.equal a' b) && (Atom.equal b' b))) prem
      (* If not, search for the equality [l:c = c'] s.t. [c = b] or [c' = b] *)
      with | Not_found -> list_find_remove (fun (l,(a',b')) -> ((Atom.equal a' b) || (Atom.equal b' b))) prem in
    let c = if Atom.equal c b then c' else c in
    process_trans a c prem (l::res)


let mkTrans p =
  let (concl,prem) = List.partition Form.is_pos p in
  match concl with
  |[c] ->
    let a,b = get_eq c in
    let prem_val = List.map (fun l -> (l,get_eq l)) prem in
    let cert = (process_trans a b prem_val []) in
    Other (EqTr (c,cert))
  |_ -> failwith "VeritSyntax.mkTrans: no conclusion or more than one conclusion in transitivity"


(* Congruence *)

let rec process_congr a_args b_args prem res =
  match a_args,b_args with
  | a::a_args,b::b_args ->
     (* if a = b *)
     (* then process_congr a_args b_args prem (None::res) *)
     (* else *)
     let (l,(a',b')) = List.find (fun (l,(a',b')) -> ((Atom.equal a a') && (Atom.equal b b'))||((Atom.equal a b') && (Atom.equal b a'))) prem in
     process_congr a_args b_args prem ((Some l)::res)
  | [],[] -> List.rev res
  | _ -> failwith "VeritSyntax.process_congr: incorrect number of arguments in function application"


let mkCongr p =
  let (concl,prem) = List.partition Form.is_pos p in
  match concl with
  |[c] ->
    let a,b = get_eq c in
    let prem_val = List.map (fun l -> (l,get_eq l)) prem in
    (match Atom.atom a, Atom.atom b with
     | Abop(aop,a1,a2), Abop(bop,b1,b2) when (aop = bop) ->
        let a_args = [a1;a2] in
        let b_args = [b1;b2] in
        let cert = process_congr a_args b_args prem_val [] in
        Other (EqCgr (c,cert))
     | Auop (aop,a), Auop (bop,b) when (aop = bop) ->
        let a_args = [a] in
        let b_args = [b] in
        let cert = process_congr a_args b_args prem_val [] in
        Other (EqCgr (c,cert))
     | Aapp (a_f,a_args), Aapp (b_f,b_args) ->
        if indexed_op_index a_f = indexed_op_index b_f then
          let cert = process_congr (Array.to_list a_args) (Array.to_list b_args) prem_val [] in
          Other (EqCgr (c,cert))
        else failwith "VeritSyntax.mkCongr: left function is different from right fucntion"
     | _, _ -> failwith "VeritSyntax.mkCongr: atoms are not applications")
  |_ -> failwith "VeritSyntax.mkCongr: no conclusion or more than one conclusion in congruence"


let mkCongrPred p =
  let (concl,prem) = List.partition Form.is_pos p in
  let (prem,prem_P) = List.partition is_eq prem in
  match concl with
  |[c] ->
    (match prem_P with
     |[p_p] ->
       let prem_val = List.map (fun l -> (l,get_eq l)) prem in
       (match Atom.atom (get_at c), Atom.atom (get_at p_p) with
        | Abop(aop,a1,a2), Abop(bop,b1,b2) when (aop = bop) ->
           let a_args = [a1;a2] in
           let b_args = [b1;b2] in
           let cert = process_congr a_args b_args prem_val [] in
           Other (EqCgrP (p_p,c,cert))
        | Aapp (a_f,a_args), Aapp (b_f,b_args) ->
           if indexed_op_index a_f = indexed_op_index b_f then
             let cert = process_congr (Array.to_list a_args) (Array.to_list b_args) prem_val [] in
             Other (EqCgrP (p_p,c,cert))
           else failwith "VeritSyntax.mkCongrPred: unmatching predicates"
        | _ -> failwith "VeritSyntax.mkCongrPred : not pred app")
     |_ ->  failwith "VeritSyntax.mkCongr: no or more than one predicate app premise in congruence")
  |[] ->  failwith "VeritSyntax.mkCongrPred: no conclusion in congruence"
  |_ -> failwith "VeritSyntax.mkCongrPred: more than one conclusion in congruence"


(* Linear arithmetic *)

let mkMicromega cl =
  let _tbl, _f, cert = Lia.build_lia_certif cl in
  let c =
    match cert with
    | None -> failwith "VeritSyntax.mkMicromega: micromega can't solve this"
    | Some c -> c in
  Other (LiaMicromega (cl,c))


let mkSplArith orig cl =
  let res =
    match cl with
    | res::nil -> res
    | _ -> failwith "VeritSyntax.mkSplArith: wrong number of literals in the resulting clause" in
  try
    let orig' =
      match orig.value with
      | Some [orig'] -> orig'
      | _ -> failwith "VeritSyntax.mkSplArith: wrong number of literals in the premise clause" in
    let _tbl, _f, cert = Lia.build_lia_certif [Form.neg orig';res] in
    let c =
      match cert with
      | None -> failwith "VeritSyntax.mkSplArith: micromega can't solve this"
      | Some c -> c in
    Other (SplArith (orig,res,c))
  with
  | _ -> Other (ImmFlatten (orig, res))


(* Elimination of operators *)

let mkDistinctElim old value =
  let rec find_res l1 l2 =
    match l1,l2 with
    | t1::q1,t2::q2 -> if t1 == t2 then find_res q1 q2 else t2
    | _, _ -> assert false in
  let l1 = match old.value with
    | Some l -> l
    | None -> assert false in
  Other (SplDistinctElim (old,find_res l1 value))


(* Clause difference (wrt to their sets of literals) *)

(* let clause_diff c1 c2 =
 *   let r =
 *     List.filter (fun t1 -> not (List.exists (SmtAtom.Form.equal t1) c2)) c1
 *   in
 *   Format.eprintf "[";
 *   List.iter (Format.eprintf " %a ,\n" SmtAtom.(Form.to_smt Atom.to_smt)) c1;
 *   Format.eprintf "] -- [";
 *   List.iter (Format.eprintf " %a ,\n" SmtAtom.(Form.to_smt Atom.to_smt)) c2;
 *   Format.eprintf "] ==\n [";
 *   List.iter (Format.eprintf " %a ,\n" SmtAtom.(Form.to_smt Atom.to_smt)) r;
 *   Format.eprintf "] @.";
 *   r *)


(* The state of the veriT pre-processor:
   - clauses_tbl : the clauses associated to the ids in the veriT certificate
   - ref_cl_tbl : maps solver integers to id integers
   - to_add_list : the terms to add in the deep embedding (for quantifiers)
   - solver_tbl : the terms associated to names in the veriT certificate
   - hlets_tbl
   - smt_state : the state of all preprocessors
 *)

type clauses_tbl = (int,Form.t clause) Hashtbl.t
type ref_cl_tbl = (int, int) Hashtbl.t
type to_add_list = (int * SmtAtom.Form.t list) list ref
type solver_tbl = (int, (bool * Form.atom_form_lit)) Hashtbl.t
type hlets_tbl = (string, Form.atom_form_lit) Hashtbl.t
type smt_state = State.smt_state

type verit_state =
  { clauses_tbl : clauses_tbl;
    ref_cl_tbl : ref_cl_tbl;
    to_add_list : to_add_list;
    solver_tbl : solver_tbl;
    hlets_tbl : hlets_tbl;
    smt_state : smt_state
  }

let get_smt_state st = st.smt_state

let get_type_tbl st = State.get_type_tbl (get_smt_state st)
let get_op_tbl st = State.get_op_tbl (get_smt_state st)
let get_atom_tbl_to_add st = State.get_atom_tbl_to_add (get_smt_state st)
let get_form_tbl_to_add st = State.get_form_tbl_to_add (get_smt_state st)
let get_atom_tbl_no_add st = State.get_atom_tbl_no_add (get_smt_state st)
let get_form_tbl_no_add st = State.get_form_tbl_no_add (get_smt_state st)
let get_trace_state st = State.get_trace_state (get_smt_state st)

let create_verit_state () : verit_state =
  { clauses_tbl = Hashtbl.create 17;
    ref_cl_tbl = Hashtbl.create 17;
    to_add_list = ref [];
    solver_tbl = Hashtbl.create 17;
    hlets_tbl = Hashtbl.create 17;
    smt_state = State.create_smt_state ()
  }


(* Generating clauses *)

let get_clause id st =
  let clauses = st.clauses_tbl in
  try Hashtbl.find clauses id
  with | Not_found -> failwith ("VeritSyntax.get_clause : clause number "^(string_of_int id)^" not found\n")
let add_clause id cl st =
  let clauses = st.clauses_tbl in
  Hashtbl.add clauses id cl


(* <ref_cl> maps solver integers to id integers. *)
let get_ref i st =
  let ref_cl = st.ref_cl_tbl in
  Hashtbl.find ref_cl i
let add_ref i j st =
  let ref_cl = st.ref_cl_tbl in
  Hashtbl.add ref_cl i j

(* Recognizing and modifying clauses depending on a forall_inst clause. *)

let rec fins_lemma (ids_params:int list) (st:verit_state) : SmtAtom.Form.t SmtCertif.clause =
  match ids_params with
    [] -> raise Not_found
  | h :: t ->
     let cl_target = repr (get_clause h st) in
     match cl_target.kind with
         Other (Forall_inst (lemma, _)) -> lemma
       | _ -> fins_lemma t st

let find_remove_lemma (lemma:SmtAtom.Form.t SmtCertif.clause) (ids_params:int list) (st:verit_state) : int * int list =
  let eq_lemma h =
    let cl = get_clause h st in
    eq_clause lemma cl
  in
  list_find_remove eq_lemma ids_params

(* Removes the lemma in a list of ids containing an instance of this lemma *)
let rec merge (ids_params:int list) (st:verit_state) : int list =
  try let lemma = fins_lemma ids_params st in
      let (_, rest) = find_remove_lemma lemma ids_params st in
      merge rest st
  with Not_found -> ids_params

let mk_clause (id,typ,value,ids_params) st =
  let kind =
    match typ with
      (* Roots *)
      | Inpu -> Root
      (* Cnf conversion *)
      | True -> Other SmtCertif.True
      | Fals -> Other False
      | Andn | Orp | Impp | Xorp1 | Xorn1 | Equp1 | Equn1 | Itep1 | Iten1 ->
        (match value with
          | l::_ -> Other (BuildDef l)
          | _ -> assert false)
      | Xorp2 | Xorn2 | Equp2 | Equn2 | Itep2 | Iten2 ->
        (match value with
          | l::_ -> Other (BuildDef2 l)
          | _ -> assert false)
      | Orn | Andp ->
        (match value,ids_params with
          | l::_, [p] -> Other (BuildProj (l,p))
          | _ -> assert false)
      | Impn1 ->
        (match value with
          | l::_ -> Other (BuildProj (l,0))
          | _ -> assert false)
      | Impn2 ->
        (match value with
          | l::_ -> Other (BuildProj (l,1))
          | _ -> assert false)
      | Nand | Imp | Xor1 | Nxor1 | Equ2 | Nequ2 | Ite1 | Nite1 ->
        (match ids_params with
          | [id] ->
             let cl = get_clause id st in
             Other (ImmBuildDef cl)
          | _ -> assert false)
      | Or ->
         (match ids_params with
            | [id_target] ->
               let cl_target = get_clause id_target st in
               begin match cl_target.kind with
                 | Other (Forall_inst _) -> Same cl_target
                 | _ -> Other (ImmBuildDef cl_target) end
            | _ -> assert false)
      | Xor2 | Nxor2 | Equ1 | Nequ1 | Ite2 | Nite2 ->
        (match ids_params with
          | [id] -> Other (ImmBuildDef2 (get_clause id st))
          | _ -> assert false)
      | And | Nor ->
        (match ids_params with
          | [id;p] -> Other (ImmBuildProj (get_clause id st,p))
          | _ -> assert false)
      | Nimp1 ->
        (match ids_params with
          | [id] -> Other (ImmBuildProj (get_clause id st,0))
          | _ -> assert false)
      | Nimp2 ->
        (match ids_params with
          | [id] -> Other (ImmBuildProj (get_clause id st,1))
          | _ -> assert false)
      (* Equality *)
      | Eqre -> mkTrans value
      | Eqtr -> mkTrans value
      | Eqco -> mkCongr value
      | Eqcp -> mkCongrPred value
      (* Linear integer arithmetic *)
      | Dlge | Lage | Lata -> mkMicromega value
      | Lade               -> mkMicromega value (* TODO: utiliser un solveur plus simple *)
      | Dlde ->
        (match value with
          | l::_ -> Other (LiaDiseq l)
          | _ -> assert false)
      (* Resolution *)
      | Reso ->
         let ids_params = merge ids_params st in
         (match ids_params with
            | cl1::cl2::q ->
               let res = {rc1 = get_clause cl1 st; rc2 = get_clause cl2 st; rtail = List.map (fun h -> get_clause h st) q} in
               Res res
            | [fins_id] -> Same (get_clause fins_id st)
            | [] -> assert false)
      (* Clause weakening *)
      | Weak ->
        (match ids_params with
         | [id] -> (* Other (Weaken (get_clause id state, value)) *)
           let cid = get_clause id st in
           (match cid.value with
           | None -> Other (Weaken (cid, value))
           | Some c -> Other (Weaken (cid, value))
            (* need to add c, otherwise dosen't terminate or returns false,
               we would like instead: clause_diff value c *)
           )
          | _ -> assert false)
      (* Simplifications *)
      | Tpal ->
        (match ids_params with
          | id::_ -> Same (get_clause id st)
          | _ -> assert false)
      | Tple ->
        (match ids_params with
          | id::_ -> Same (get_clause id st)
          | _ -> assert false)
      | Tpde ->
        (match ids_params with
          | id::_ -> mkDistinctElim (get_clause id st) value
          | _ -> assert false)
      | Tpsa | Tlap ->
        (match ids_params with
          | id::_ -> mkSplArith (get_clause id st) value
          | _ -> assert false)
      | Flat ->
        (match ids_params, value with
         | id::_, f :: _ -> Other (ImmFlatten(get_clause id st, f))
         | _ -> assert false)
      (* Bit blasting *)
      | Bbva ->
         (match value with
           | [f] -> Other (BBVar f)
           | _ -> assert false)
      | Bbconst ->
         (match value with
           | [f] -> Other (BBConst f)
           | _ -> assert false)
      | Bbeq ->
         (match ids_params, value with
           | [id1;id2], [f] -> Other (BBEq (get_clause id1 st, get_clause id2 st, f))
           | _, _ -> assert false)
      | Bbdis ->
         (match value with
           | [f] -> Other (BBDiseq f)
           | __ -> assert false)
      | Bbop ->
         (match ids_params, value with
           | [id1;id2], [f] -> Other (BBOp (get_clause id1 st, get_clause id2 st, f))
           | _, _ -> assert false)
      | Bbadd ->
         (match ids_params, value with
           | [id1;id2], [f] -> Other (BBAdd (get_clause id1 st, get_clause id2 st, f))
           | _, _ -> assert false)
      | Bbmul ->
         (match ids_params, value with
           | [id1;id2], [f] -> Other (BBMul (get_clause id1 st, get_clause id2 st, f))
           | _, _ -> assert false)
      | Bbult ->
         (match ids_params, value with
           | [id1;id2], [f] -> Other (BBUlt (get_clause id1 st, get_clause id2 st, f))
           | _, _ -> assert false)
      | Bbslt ->
         (match ids_params, value with
           | [id1;id2], [f] -> Other (BBSlt (get_clause id1 st, get_clause id2 st, f))
           | _, _ -> assert false)
      | Bbconc ->
         (match ids_params, value with
           | [id1;id2], [f] ->
             Other (BBConc (get_clause id1 st, get_clause id2 st, f))
           | _, _ -> assert false)
      | Bbextr ->
         (match ids_params, value with
           | [id], [f] -> Other (BBExtr (get_clause id st, f))
           | _, _ -> assert false)
      | Bbzext ->
         (match ids_params, value with
           | [id], [f] -> Other (BBZextn (get_clause id st, f))
           | _, _ -> assert false)
      | Bbsext ->
         (match ids_params, value with
           | [id], [f] -> Other (BBSextn (get_clause id st, f))
           | _, _ -> assert false)
      | Bbshl ->
         (match ids_params, value with
           | [id1;id2], [f] -> Other (BBShl (get_clause id1 st, get_clause id2 st, f))
           | _, _ -> assert false)
      | Bbshr ->
         (match ids_params, value with
           | [id1;id2], [f] -> Other (BBShr (get_clause id1 st, get_clause id2 st, f))
           | _, _ -> assert false)
      | Bbnot ->
         (match ids_params, value with
           | [id], [f] -> Other (BBNot (get_clause id st, f))
           | _, _ -> assert false)
      | Bbneg ->
         (match ids_params, value with
           | [id], [f] -> Other (BBNeg (get_clause id st, f))
           | _, _ -> assert false)

      | Row1 ->
         (match value with
           | [f] -> Other (RowEq f)
           | _ -> assert false)

      | Exte ->
         (match value with
           | [f] -> Other (Ext f)
           | _ -> assert false)

      | Row2 -> Other (RowNeq value)

      (* Holes in proofs *)
      | Hole -> Other (SmtCertif.Hole (List.map (fun h -> get_clause h st) ids_params, value))

      (* Quantifier instanciation *)
      | Fins ->
         begin match value, ids_params with
           | [inst], [ref_th] ->
              let cl_th = get_clause ref_th st in
              Other (Forall_inst (repr cl_th, inst))
           | _ -> failwith "unexpected form of forall_inst" end
      | Tpbr ->
         begin match ids_params with
           | [id] ->
              Same (get_clause id st)
           | _ -> failwith "unexpected form of tmp_betared" end
      | Tpqt ->
         begin match ids_params with
           | [id] ->
              Same (get_clause id st)
           | _ -> failwith "unexpected form of tmp_qnt_tidy" end

      (* Not implemented *)
      | Deep -> failwith "VeritSyntax.ml: rule deep_res not implemented yet"
      | Eins -> failwith "VeritSyntax.ml: rule exists_inst not implemented yet"
      | Skea -> failwith "VeritSyntax.ml: rule skolem_ex_ax not implemented yet"
      | Skaa -> failwith "VeritSyntax.ml: rule skolem_all_ax not implemented yet"
      | Qnts -> failwith "VeritSyntax.ml: rule qnt_simplify_ax not implemented yet"
      | Qntm -> failwith "VeritSyntax.ml: rule qnt_merge_ax not implemented yet"
      | Tpne -> failwith "VeritSyntax.ml: rule tmp_nary_elim not implemented yet"
      | Tpie -> failwith "VeritSyntax.ml: rule tmp_ite_elim not implemented yet"
      | Tpma -> failwith "VeritSyntax.ml: rule tmp_macrosubst not implemented yet"
      | Tpbe -> failwith "VeritSyntax.ml: rule tmp_bfun_elim not implemented yet"
      | Tpsc -> failwith "VeritSyntax.ml: rule tmp_sk_connector not implemented yet"
      | Tppp -> failwith "VeritSyntax.ml: rule tmp_pm_process not implemented yet"
      | Tpqs -> failwith "VeritSyntax.ml: rule tmp_qnt_simplify not implemented yet"
      | Tpsk -> failwith "VeritSyntax.ml: rule tmp_skolemize not implemented yet"
      | Subp -> failwith "VeritSyntax.ml: rule subproof not implemented yet"
  in
  let cl =
    (* TODO: change this into flatten when necessary *)
    if SmtTrace.isRoot kind then SmtTrace.mkRootV (get_trace_state st) value
    else SmtTrace.mk_scertif (get_trace_state st) kind (Some value) in
  add_clause id cl st;
  if id > 1 then SmtTrace.link (get_clause (id-1) st) cl;
  id


let mk_clause cl st =
  try mk_clause cl st
  with Failure f ->
    Structures.error ("SMTCoq was not able to check the certificate \
                       for the following reason.\n"^f)

let apply_dec f (decl, a) = decl, f a

let rec list_dec = function
  | [] -> true, []
  | (decl_h, h) :: t ->
     let decl_t, l_t = list_dec t in
     decl_h && decl_t, h :: l_t

let apply_dec_atom (f:?declare:bool -> SmtAtom.hatom -> SmtAtom.hatom) = function
  | decl, Form.Atom h -> decl, Form.Atom (f ~declare:decl h)
  | _ -> assert false

let apply_bdec_atom (f:?declare:bool -> SmtAtom.Atom.t -> SmtAtom.Atom.t -> SmtAtom.Atom.t) o1 o2 =
  match o1, o2 with
  | (decl1, Form.Atom h1), (decl2, Form.Atom h2) ->
     let decl = decl1 && decl2 in
     decl, Form.Atom (f ~declare:decl h1 h2)
  | _ -> assert false

let apply_tdec_atom (f:?declare:bool -> SmtAtom.Atom.t -> SmtAtom.Atom.t -> SmtAtom.Atom.t -> SmtAtom.Atom.t) o1 o2 o3 =
  match o1, o2, o3 with
  | (decl1, Form.Atom h1), (decl2, Form.Atom h2), (decl3, Form.Atom h3) ->
     let decl = decl1 && decl2 && decl3 in
     decl, Form.Atom (f ~declare:decl h1 h2 h3)
  | _ -> assert false


let get_solver id st =
  let solver = st.solver_tbl in
  try Hashtbl.find solver id
  with | Not_found -> failwith ("VeritSyntax.get_solver : solver variable number "^(string_of_int id)^" not found\n")
let add_solver id cl st =
  let solver = st.solver_tbl in
  Hashtbl.add solver id cl

(* Finding the index of a root in <lsmt> modulo the <re_hash> function.
   This function is used by SmtTrace.order_roots *)
let init_index lsmt re_hash =
  let form_index_init_rank : (int, int) Hashtbl.t = Hashtbl.create 20 in
  let add = Hashtbl.add form_index_init_rank in
  let find = Hashtbl.find form_index_init_rank in
  let rec walk rank = function
    | [] -> ()
    | h::t -> add (Form.to_lit (re_hash h)) rank;
              walk (rank+1) t in
  walk 1 lsmt;
  fun hf -> let re_hf = re_hash hf in
            try find (Form.to_lit re_hf)
            with Not_found ->
              let oc = open_out "/tmp/input_not_found.log" in
              let fmt = Format.formatter_of_out_channel oc in
              List.iter (fun h -> Format.fprintf fmt "%a\n" (Form.to_smt ~debug:true) (re_hash h)) lsmt;
              Format.fprintf fmt "\n%a\n@." (Form.to_smt ~debug:true) re_hf;
              flush oc; close_out oc;
              failwith "not found: log available"

let qf_to_add lr =
  let is_forall l = match Form.pform l with
    | Fapp (Fforall _, _) -> true
    | _ -> false in
  let rec qf_lemmas = function
    | [] -> []
    | ({value = Some [l]} as r)::t when not (is_forall l) ->
       (Other (Qf_lemma (r, l)), r.value, r) :: qf_lemmas t
    | _::t -> qf_lemmas t in
  qf_lemmas lr


(* Let bindings *)
let get_hlet s st =
  let hlets = st.hlets_tbl in
  Hashtbl.find hlets s
let add_hlet s l st =
  let hlets = st.hlets_tbl in
  Hashtbl.add hlets s l


(* Local state memorizing quantified variables when parsing *one* quantified clause *)
type qvar_tbl = (string, SmtBtype.btype) Hashtbl.t
type quant_state = qvar_tbl
let create_quant_state () : quant_state = Hashtbl.create 17

let find_opt_qvar s qst =
  let qvars = qst in
  try Some (Hashtbl.find qvars s)
  with Not_found -> None
let add_qvar s bt qst =
  let qvars = qst in
  Hashtbl.add qvars s bt

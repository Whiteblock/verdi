Require Import Verdi.Verdi.

Require Import Cheerios.Cheerios.

Import DeserializerNotations.

Set Implicit Arguments.

Section Log.
  Context {orig_base_params : BaseParams}.
  Context {orig_multi_params : MultiParams orig_base_params}.
  Context {orig_failure_params : FailureParams orig_multi_params}.

  Context {data_serializer : Serializer data}.
  Context {name_serializer : Serializer name}.
  Context {msg_serializer : Serializer msg}.
  Context {input_serializer : Serializer input}.

  Variable snapshot_interval : nat.

  Definition entry : Type := input + (name * msg).

  Inductive log_files :=
  | Count
  | Snapshot
  | Log.

  Definition log_files_eq_dec : forall x y : log_files, {x = y} + {x <> y}.
    decide equality.
  Defined.

  Record log_state :=
    mk_log_state { log_num_entries : nat ;
                   log_data : data }.

  Definition log_net_handlers dst src m st : list (disk_op log_files) *
                                             list output *
                                             log_state *
                                             list (name * msg)  :=
    let '(out, data, ps) := net_handlers dst src m (log_data st) in
    let n := log_num_entries st in
    if S n =? snapshot_interval
    then ([Delete Log; Write Snapshot (serialize data); Write Count (serialize 0)],
          out,
          mk_log_state 0 data,
          ps)
    else ([Append Log (serialize (inr (src , m) : entry)); Write Count (serialize (S n))],
          out,
          mk_log_state (S n) data,
          ps).

  Definition log_input_handlers h inp st : list (disk_op log_files) *
                                           list output *
                                           log_state *
                                           list (name * msg) :=
    let '(out, data, ps) := input_handlers h inp (log_data st) in
    let n := log_num_entries st in
    if S n =? snapshot_interval
    then ([Delete Log; Write Snapshot (serialize data); Write Count (serialize 0)],
          out,
          mk_log_state 0 data,
          ps)
    else ([Append Log (serialize (inl inp : entry)); Write Count (serialize (S n))],
          out,
          mk_log_state (S n) data,
          ps).

  Instance log_base_params : BaseParams :=
    {
      data := log_state ;
      input := input ;
      output := output
    }.

  Instance log_multi_params : DiskOpMultiParams log_base_params :=
    {
      do_name := name;
      file_name := log_files;
      do_name_eq_dec := name_eq_dec;
      do_msg := msg;
      do_msg_eq_dec := msg_eq_dec;
      file_name_eq_dec := log_files_eq_dec;
      do_nodes := nodes;
      do_all_names_nodes := all_names_nodes;
      do_no_dup_nodes := no_dup_nodes;
      do_net_handlers := log_net_handlers;
      do_input_handlers := log_input_handlers
    }.

  (* doesn't fail silently *)
  Definition channel_to_log (channel : file_name -> option IOStreamWriter.in_channel) :
    option (nat * list entry * @data orig_base_params) :=
    match channel Count, channel Log, channel Snapshot with
    | Some s1, Some s2, Some s3 =>
      match from_channel deserialize s1 with
      | Some n  =>
        match from_channel (list_deserialize_rec _ _ n) s2 with
        | Some es =>
          match from_channel deserialize s3 with
          | Some snap => Some (n, es, snap)
          | None => None
          end
        | None => None
        end
      | None => None
      end
    | _, _, _ => None
    end.

  Definition apply_entry h d e :=
    match e with
     | inl inp => let '(_, d', _) := input_handlers h inp d in d'
     | inr (src, m) => let '(_, d', _) := net_handlers h src m d in d'
    end.

  Definition apply_log h (d : @data orig_base_params) (entries : list entry) : @data orig_base_params :=
    fold_left (apply_entry h) entries d.

  Definition do_log_reboot (h : do_name) (w : log_files -> option IOStreamWriter.in_channel) :
    data * list (disk_op log_files) :=
    let d := match channel_to_log w with
             | Some (n, es, d) =>
               reboot (apply_log h d es)
             | None => init_handlers h
             end in
    (mk_log_state 0 d,
     [Delete Log; Write Snapshot (serialize d); Write Count (serialize 0)]).

  Instance log_failure_params : DiskOpFailureParams log_multi_params :=
    { do_reboot := do_log_reboot }.
End Log.

Hint Extern 5 (@BaseParams) => apply log_base_params : typeclass_instances.
Hint Extern 5 (@DiskOpMultiParams _) => apply log_multi_params : typeclass_instances.
Hint Extern 5 (@DiskOpFailureParams _ _) => apply log_failure_params : typeclass_instances.

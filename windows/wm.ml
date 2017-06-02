open Common

module Unix1 = Unix
module Unix2 = ThreadUnix

module I = Display
module W = Window
module FS = Fileserver

(*****************************************************************************)
(* Cursors *)
(*****************************************************************************)

(* less? move those cursor functions in cursors.ml? *)

(* less: a rio_cursor? with lastcursor opti? and force parameter? *)
let window_cursor w pt mouse =
  let cursoropt = 
    (* less: if img is nil? if screenr is 0? *)
    match Windows.window_at_point pt with
    | Some w2 when w2  == w -> w.W.mouse_cursor
    | _ -> None
  in
  (* less: if menuing? or use corner_cursor() so no need this global? *)
  (* less: if holding *)
  match cursoropt with
  | Some x -> Mouse.set_cursor mouse x
  | None -> Mouse.reset_cursor mouse


let corner_cursor w pt mouse =
  if Window.pt_on_frame pt w
  then Mouse.set_cursor mouse (Cursors.which_corner_cursor w.W.screenr pt)

let corner_cursor_or_window_cursor w pt mouse =
  if Window.pt_on_frame pt w
  then Mouse.set_cursor mouse (Cursors.which_corner_cursor w.W.screenr pt)
  else window_cursor w pt mouse


(*****************************************************************************)
(* Border *)
(*****************************************************************************)

let draw_border w status =
  let img = w.W.img in
  (* less: if holding? *)
  let color = 
    match status with
    | W.Selected   -> !Globals.title_color
    | W.Unselected -> !Globals.title_color_light
  in
  Polygon.border img img.I.r Window.frame_border color Point.zero

let repaint_border w =
  (* todo: update cols *)
  (* todo: if mouse not opened *)
  match Globals.win () with
  | Some w2 when w2 == w -> 
    draw_border w W.Selected
    (* less: wsetcursor again? *)
  | _ -> 
    draw_border w W.Unselected

(* old: was called wcurrent *)
let set_current_and_repaint_borders wopt mouse =
  (* less: if wkeyboard *)
  let old = !Globals.current in
  Globals.current := wopt;
  (match old, wopt with
  | Some w2, Some w when not (w2 == w) ->
    (* less: could do directly: draw_border w2 W.Unseleted *)
    (* bugfix: was doing repaint_border w, hmm *)
    repaint_border w2
  | _ -> ()
  );
  wopt |> Common.if_some (fun w ->
    (* less: could do directly: draw_border w W.Seleted *)
    repaint_border w;
    (* TODO: do that in caller? so no need pass mouse? *)
    (*window_cursor w ptTODO mouse;*)
    (* todo: wakeup? why? *)
    ()
  )

(*****************************************************************************)
(* Wm *)
(*****************************************************************************)

let top_win w mouse =
  if w.W.topped = !Window.topped_counter
  then ()
  else begin
    Layer.put_to_top w.W.img;
    set_current_and_repaint_borders (Some w) mouse;
    Image.flush w.W.img;

    incr Window.topped_counter;
    w.W.topped <- !Window.topped_counter;
  end

let (threads_window_thread_func: (Window.t -> unit) ref) = ref (fun _ ->
  failwith "threads_window_thread_func undefined"
)

(* less: hideit, pid (but 0, or if != 0 -> use another func), scrolling *)
let new_win img cmd argv pwd_opt mouse fs =

  (* A new Window.t *)

  (* less: cpid channel? no need I think because no procexec *)
  (* less: scrollit *)
  let w = Window.alloc img in
  (* less: wscrdraw here? *)

  (* simpler: draw_border w Window.Selected;
   * but done already later in set_current_and_repaint_borders
   *)

  (* A new window thread *)

  Hashtbl.add Globals.windows w.W.id w;
  let _win_thread = Thread.create !threads_window_thread_func w in

  (* less: if not hideit *)
  set_current_and_repaint_borders (Some w) mouse;
  Image.flush img;

  (* A new window process *)

  pwd_opt |> Common.if_some (fun str -> w.W.pwd <- str);

  Thread.critical_section := true;
  let res = Unix.fork () in
  (match res with
  | -1 -> failwith "fork returned -1"
  | 0 ->
    (* child *)
    Unix1.chdir w.W.pwd;
    (* todo: close on exec *)
    (* less: rfork for copy of namespace/fd/env, but ape fork does that? *)
    
    (*/* close server end so mount won't hang if exiting */*)
    Unix1.close fs.FS.server_fd;
    Plan9.mount fs.FS.clients_fd (-1) "/mnt/wsys" Plan9.MRepl (spf "%d" w.W.id);
    Plan9.bind "/mnt/wsys" "/dev" Plan9.MBefore;

    (* less: wclose for ref counting *)
    (* todo: reassign STDIN/STDOUT *)
    (* less: notify nil *)
    Unix2.execv cmd argv;
    failwith "exec failed"

  | pid -> 
    (* parent *)
    Thread.critical_section := false;
    w.W.pid <- pid;

    (* old: was in wsetpid() *)
    w.W.label <- spf "rc %d" pid;
    (* less: notefd *)

    let winname = spf "window.%d" w.W.id in
    Draw_ipc.name_image w.W.img winname;
    (* less: namecount and retry again if already used *)
       
  )



let close_win w =
  w.W.deleted <- true;
  (match Globals.win () with
  | Some w2 when w == w2 ->
    Globals.current := None;
    (* less: window_cursor  ?*)
  | _ -> ()
  );
  (* less: if wkeyboard *)
  Hashtbl.remove Globals.hidden w.W.id;
  Hashtbl.remove Globals.windows w.W.id;
  Layer.free w.W.img;
  w.W.img <- Image.fake_image;
  ()

let hide_win w mouse =
  if Hashtbl.mem Globals.hidden w.W.id
  (* less: return -1? can happen if window thread take too much time
   * to respond to the Reshape command?
   *)
  then raise (Impossible "window already hidden");
  let old_layer = w.W.img in
  let display = old_layer.I.display in
  (* this is an image! not a layer, so it will not be visible on screen *)
  let img = 
    Image.alloc display w.W.screenr old_layer.I.chans false Color.white in
  (* less: return 0 or 1 if can or can not allocate? *)
  Hashtbl.add Globals.hidden w.W.id w;
  let cmd = W.Reshape (img, mouse) in
  Event.send w.W.chan_cmd cmd |> Event.sync;
  ()

let unhide_win w desktop mouse =
  let old_img = w.W.img in
  let layer = Layer.alloc desktop old_img.I.r Color.white in
  Hashtbl.remove Globals.hidden w.W.id;
  let cmd = W.Reshape (layer, mouse) in
  Event.send w.W.chan_cmd cmd |> Event.sync;
  ()


(* less: move boolean parameter, useless opti test dx/dy below catch it *)
let resize_win w new_img =
  let old_img = w.W.img in
  let old_r = old_img.I.r in
  let new_r = new_img.I.r in
  if Rectangle.dx old_r = Rectangle.dx new_r && 
     Rectangle.dy old_r = Rectangle.dy new_r
  then Draw.draw new_img new_r old_img None old_r.Rectangle.min;
  (* a layer or image, so when hiding this should make disappear the window *)
  Image.free old_img;
  (* less: screenr set in caller, but could do it here *)
  w.W.img <- new_img;
  (* todo: wsetname *)

  (* todo: textual window update *)
  draw_border w W.Selected;
  incr Window.topped_counter;
  w.W.topped <- !Window.topped_counter;

  (* todo: w.W.resized <- true *)
  (* todo: mouse counter ++ so transmit resize event *)
  ()

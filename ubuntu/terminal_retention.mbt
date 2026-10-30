///|
extern "C" fn native_terminal_retention_enable(host : Int32) -> Int32 = "gpui_terminal_retention_enable"

///|
extern "C" fn native_dispatch_retained(host : Int32, timeout : Int32) -> Int32 = "gpui_dispatch_retained"

///|
/// Pump native callbacks without consuming records. Busy leaves the host and
/// callback queue unchanged when the retained FIFO already has an owner.
pub fn Host::dispatch_retained(
  self : Host,
  timeout_ms : Int32,
) -> Result[Unit, @diagnostics.FrameworkError] {
  outcome(native_dispatch_retained(self.token, timeout_ms), "dispatch_retained")
}

///|
#borrow(fields, text)
extern "C" fn native_terminal_preview_receipt(
  host : Int32,
  fields : FixedArray[Double],
  field_capacity : Int32,
  text : Bytes,
  text_capacity : Int32,
) -> Int32 = "gpui_terminal_preview_receipt"

///|
extern "C" fn native_terminal_preview_handoff(
  host : Int32,
  receipt : Int32,
  window : Int32,
  epoch : Int32,
  watermark : Int32,
) -> Int32 = "gpui_terminal_preview_handoff"

///|
/// A copied snapshot of a preview that became unresolved at a native
/// lifecycle boundary. It is not a Commit, Cancel, record ACK, or evidence of
/// model application. The original editing owner must remain alive separately.
pub struct TerminalPreviewReceipt {
  priv host : Host
  priv id : Int32
  priv window : @platform.WindowId
  priv epoch : Int32
  priv watermark : Int32
  priv seat : Int64
  priv proxy_generation : Int32
  priv preview : String
  priv cursor_bytes : Int32?
}

///|
pub fn TerminalPreviewReceipt::window(
  self : TerminalPreviewReceipt,
) -> @platform.WindowId {
  self.window
}

///|
pub fn TerminalPreviewReceipt::epoch(self : TerminalPreviewReceipt) -> Int32 {
  self.epoch
}

///|
pub fn TerminalPreviewReceipt::watermark(
  self : TerminalPreviewReceipt,
) -> Int32 {
  self.watermark
}

///|
pub fn TerminalPreviewReceipt::preview(self : TerminalPreviewReceipt) -> String {
  self.preview
}

///|
pub fn TerminalPreviewReceipt::cursor_bytes(
  self : TerminalPreviewReceipt,
) -> Int32? {
  self.cursor_bytes
}

///|
pub fn TerminalPreviewReceipt::seat(self : TerminalPreviewReceipt) -> Int64 {
  self.seat
}

///|
pub fn TerminalPreviewReceipt::proxy_generation(
  self : TerminalPreviewReceipt,
) -> Int32 {
  self.proxy_generation
}

///|
/// Opt in before any native text or direct-keyboard session. A Busy result
/// means the caller must first drain the native FIFO. This experimental mode
/// does not itself retain records already taken out of the host queue.
pub fn Host::enable_terminal_retention(
  self : Host,
) -> Result[Unit, @diagnostics.FrameworkError] {
  outcome(
    native_terminal_retention_enable(self.token),
    "enable_terminal_retention",
  )
}

///|
/// Copy the host's pending preview receipt without consuming it. Multiple
/// copies describe the same single bounded obligation and can be handed off
/// successfully at most once.
pub fn Host::terminal_preview_receipt(
  self : Host,
) -> Result[TerminalPreviewReceipt?, @diagnostics.FrameworkError] {
  let operation = "terminal_preview_receipt"
  let fields = FixedArray::make(9, 0.0)
  let payload = FixedArray::make(IME_MAX_BYTES, (0).to_byte())
  let bytes = payload.unsafe_reinterpret_as_bytes()
  let status = native_terminal_preview_receipt(
    self.token,
    fields,
    fields.length(),
    bytes,
    bytes.length(),
  )
  if status < 0 {
    return Err(backend_error(-status, operation))
  }
  if status == 0 {
    return Ok(None)
  }
  if status != 1 ||
    !exact_i32(fields[0]) ||
    fields[0] <= 0.0 ||
    !exact_i32(fields[1]) ||
    fields[1] <= 0.0 ||
    !exact_i32(fields[2]) ||
    fields[2] <= 0.0 ||
    !exact_i32(fields[3]) ||
    fields[3] <= 0.0 ||
    fields[4].is_nan() ||
    fields[4].is_inf() ||
    fields[4] < 1.0 ||
    fields[4] > 4294967295.0 ||
    fields[4].to_int64().to_double() != fields[4] ||
    !exact_i32(fields[5]) ||
    fields[5] <= 0.0 ||
    !exact_i32(fields[6]) ||
    fields[6] < 0.0 ||
    fields[6] > IME_MAX_BYTES.to_double() ||
    !editor_flag(fields[7]) ||
    !exact_i32(fields[8]) ||
    (fields[7] == 0.0 && fields[8] != 0.0) {
    return Err(editor_decode_error(operation, "invalid terminal receipt"))
  }
  let text = match
    editor_decode_string(bytes, 0, fields[6].to_int(), operation) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  Ok(
    Some({
      host: self,
      id: fields[0].to_int(),
      window: @platform.WindowId::new(fields[1].to_int64()),
      epoch: fields[2].to_int(),
      watermark: fields[3].to_int(),
      seat: fields[4].to_int64(),
      proxy_generation: fields[5].to_int(),
      preview: text,
      cursor_bytes: if fields[7] == 1.0 {
        Some(fields[8].to_int())
      } else {
        None
      },
    }),
  )
}

///|
/// Declare that the original owner has retained this unresolved snapshot.
/// The caller must verify its root/field binding generation and retain the
/// actual editing session and any removed records before calling this method.
/// Window/epoch arguments must identify that same owner. This handoff does not
/// apply a record or prove that the model, scene, or IME has reached quiescence.
pub fn TerminalPreviewReceipt::handoff(
  self : TerminalPreviewReceipt,
  owner_window : @platform.WindowId,
  owner_epoch : Int32,
) -> Result[Unit, @diagnostics.FrameworkError] {
  let operation = "terminal_preview_handoff"
  if owner_window != self.window || owner_epoch != self.epoch {
    return Err(backend_error(4, operation))
  }
  outcome(
    native_terminal_preview_handoff(
      self.host.token,
      self.id,
      self.window.value().to_int(),
      self.epoch,
      self.watermark,
    ),
    operation,
  )
}

///|
#borrow(fields, payload, metadata)
extern "C" fn native_peek_retained_editor(
  abi : Int32,
  host : Int32,
  fields : FixedArray[Double],
  field_capacity : Int32,
  payload : Bytes,
  payload_capacity : Int32,
  metadata : FixedArray[Int32],
  metadata_capacity : Int32,
) -> Int32 = "gpui_peek_retained_editor"

///|
extern "C" fn native_ack_retained_editor(
  host : Int32,
  window : Int32,
  sequence : Int32,
) -> Int32 = "gpui_ack_retained_editor"

///|
/// A borrowed position in the bounded native FIFO. The host owns the actual
/// record until `ack` succeeds; repeated peeks return the same position.
/// A stale record still belongs to its captured owner, and must never be
/// applied to a replacement owner just because its window is now active.
pub struct RetainedEditorRecord {
  priv host : Host
  priv window : @platform.WindowId
  priv sequence : Int32
  priv event : EditorEvent?
  priv raw_fields : FixedArray[Double]
  priv stale : Bool
  priv direct_epoch : Int32
  priv composition_epoch : Int32
  priv revoked : Bool
  priv direct_origin : Bool
}

///|
pub fn RetainedEditorRecord::window(
  self : RetainedEditorRecord,
) -> @platform.WindowId {
  self.window
}

///|
pub fn RetainedEditorRecord::sequence(self : RetainedEditorRecord) -> Int32 {
  self.sequence
}

///|
pub fn RetainedEditorRecord::event(self : RetainedEditorRecord) -> EditorEvent? {
  self.event
}

///|
/// Inspect a captured native field, including for unmapped ordinary records.
/// The returned scalar is copied; the underlying fields are never mutable.
pub fn RetainedEditorRecord::raw_field(
  self : RetainedEditorRecord,
  index : Int32,
) -> Double? {
  if index < 0 || index >= self.raw_fields.length() {
    None
  } else {
    Some(self.raw_fields[index])
  }
}

///|
pub fn RetainedEditorRecord::is_stale(self : RetainedEditorRecord) -> Bool {
  self.stale
}

///|
pub fn RetainedEditorRecord::direct_epoch(self : RetainedEditorRecord) -> Int32 {
  self.direct_epoch
}

///|
pub fn RetainedEditorRecord::composition_epoch(
  self : RetainedEditorRecord,
) -> Int32 {
  self.composition_epoch
}

///|
pub fn RetainedEditorRecord::is_revoked(self : RetainedEditorRecord) -> Bool {
  self.revoked
}

///|
pub fn RetainedEditorRecord::is_direct_origin(
  self : RetainedEditorRecord,
) -> Bool {
  self.direct_origin
}

///|
/// Read the FIFO head without dispatching or consuming it. `event() == None`
/// identifies an unmapped native record; it remains owned until explicitly
/// handled and acknowledged. Buffer/decoder errors also leave the head intact.
pub fn Host::peek_retained_editor(
  self : Host,
) -> Result[RetainedEditorRecord?, @diagnostics.FrameworkError] {
  let operation = "peek_retained_editor"
  let fields = FixedArray::make(EDITOR_EVENT_FIELDS, 0.0)
  let payload = FixedArray::make(EDITOR_MAX_PAYLOAD, (0).to_byte())
  let bytes = payload.unsafe_reinterpret_as_bytes()
  let metadata = FixedArray::make(5, 0)
  let status = native_peek_retained_editor(
    EDITOR_ABI,
    self.token,
    fields,
    fields.length(),
    bytes,
    bytes.length(),
    metadata,
    metadata.length(),
  )
  if status < 0 {
    return Err(backend_error(-status, operation))
  }
  if status == 0 {
    return Ok(None)
  }
  if status != 1 ||
    !exact_i32(fields[1]) ||
    fields[1] <= 0.0 ||
    !exact_i32(fields[2]) ||
    fields[2] <= 0.0 ||
    (metadata[0] != 0 && metadata[0] != 1) ||
    metadata[1] < 0 ||
    metadata[2] < 0 ||
    (metadata[3] != 0 && metadata[3] != 1) ||
    (metadata[4] != 0 && metadata[4] != 1) {
    return Err(editor_decode_error(operation, "invalid retained record"))
  }
  let event = match decode_editor_event(fields, bytes, operation) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  Ok(
    Some({
      host: self,
      window: @platform.WindowId::new(fields[1].to_int64()),
      sequence: fields[2].to_int(),
      event,
      raw_fields: fields,
      stale: metadata[0] != 0,
      direct_epoch: metadata[1],
      composition_epoch: metadata[2],
      revoked: metadata[3] != 0,
      direct_origin: metadata[4] != 0,
    }),
  )
}

///|
/// Acknowledge this exact FIFO head only after its original owner has applied
/// the record to TextSession, delivered all resulting actions to the shared
/// model, and retained any remaining publication work. If processing is
/// suspended, the caller must first retain the original owner, binding,
/// session, record, and application stage as one resumable state. For nontext
/// records the caller must perform or retain the explicit terminal policy.
/// Native dequeue alone is never sufficient. Stale, foreign, duplicate, and
/// out-of-order acknowledgements fail.
pub fn RetainedEditorRecord::ack(
  self : RetainedEditorRecord,
) -> Result[Unit, @diagnostics.FrameworkError] {
  outcome(
    native_ack_retained_editor(
      self.host.token,
      self.window.value().to_int(),
      self.sequence,
    ),
    "ack_retained_editor",
  )
}

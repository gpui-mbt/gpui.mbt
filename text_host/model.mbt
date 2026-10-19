///|
/// Caller-owned state sent to a host when a native text session starts or moves.
/// The committed document is the authoritative value; `preedit` is display-only
/// and never implies that the host committed it.
pub struct TextInputState {
  priv document : @text.TextDocument
  priv caret : @primitives.Rect
  priv preedit : TextPreedit?
}

///|
/// A visible composition preview supplied by the owner. The host paints this
/// value but must not commit it without a later `TextInputEventKind::Commit`.
pub(all) struct TextPreedit {
  text : String
  selection : @text.TextSelection
}

///|
pub fn TextPreedit::new(
  text : String,
  selection : @text.TextSelection,
) -> TextPreedit {
  { text, selection, }
}

///|
pub fn TextPreedit::text(self : TextPreedit) -> String {
  self.text
}

///|
pub fn TextPreedit::selection(self : TextPreedit) -> @text.TextSelection {
  self.selection
}

///|
pub fn TextInputState::new(
  document : @text.TextDocument,
  caret : @primitives.Rect,
) -> TextInputState {
  { document, caret, preedit: None, }
}

///|
pub fn TextInputState::with_preedit(
  self : TextInputState,
  preedit : TextPreedit?,
) -> TextInputState {
  { document: self.document, caret: self.caret, preedit, }
}

///|
pub fn TextInputState::document(self : TextInputState) -> @text.TextDocument {
  self.document
}

///|
pub fn TextInputState::caret(self : TextInputState) -> @primitives.Rect {
  self.caret
}

///|
pub fn TextInputState::preedit(self : TextInputState) -> TextPreedit? {
  self.preedit
}

///|
/// One ordered host-to-framework text-input observation. `window`, `sequence`
/// and `epoch` identify the exact session; stale values must be rejected by the
/// consumer before they reach a document.
pub(all) struct TextInputEvent {
  window : @platform.WindowId
  sequence : Int64
  epoch : UInt64
  kind : TextInputEventKind
}

///|
/// A host text observation. `Preedit` and `Commit` carry UTF-16 cursor/selection
/// offsets, matching the portable text/document contract.
pub(all) enum TextInputEventKind {
  Preedit(text~ : String, cursor~ : Int32)
  Commit(text~ : String)
  Cancel
  Geometry(caret~ : @primitives.Rect, candidate~ : @primitives.Rect?)
  FocusLost
}

///|
pub fn TextInputEvent::new(
  window : @platform.WindowId,
  sequence : Int64,
  epoch : UInt64,
  kind : TextInputEventKind,
) -> TextInputEvent {
  { window, sequence, epoch, kind, }
}

///|
pub fn TextInputEvent::window(self : TextInputEvent) -> @platform.WindowId {
  self.window
}

///|
pub fn TextInputEvent::sequence(self : TextInputEvent) -> Int64 {
  self.sequence
}

///|
pub fn TextInputEvent::epoch(self : TextInputEvent) -> UInt64 {
  self.epoch
}

///|
pub fn TextInputEvent::kind(self : TextInputEvent) -> TextInputEventKind {
  self.kind
}

///|
/// Optional host transport for native text sessions. It is separate from
/// `platform.Backend` so a host can support windowing without claiming text or
/// IME support. A host that does not implement this trait returns the existing
/// `UnsupportedCapability` error from its `Backend` implementation.
pub(open) trait TextInputHost {
  /// Start one session for an owned window/root and return its positive epoch.
  fn begin_text_input(Self, @platform.WindowId, UInt64) -> Result[
    UInt64,
    @diagnostics.FrameworkError,
  ]

  /// Replace the owner state and return the current epoch. A replacement may
  /// advance the epoch; callers must not reuse an older value.
  fn update_text_input(Self, UInt64, TextInputState) -> Result[
    UInt64,
    @diagnostics.FrameworkError,
  ]

  /// Cancel the active composition and request a replacement epoch.
  fn cancel_text_input(Self, UInt64) -> Result[
    Unit,
    @diagnostics.FrameworkError,
  ]

  /// Revoke the session. Repeated or stale epochs are rejected by the host.
  fn end_text_input(Self, UInt64) -> Result[Unit, @diagnostics.FrameworkError]

  /// Drain one ordered observation. A timeout is not an error.
  fn next_text_input(Self, timeout_ms? : Int32) -> Result[
    TextInputEvent?,
    @diagnostics.FrameworkError,
  ]
}

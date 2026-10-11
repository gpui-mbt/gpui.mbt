///|
/// One admitted content edit. The documents retain their directional
/// selections, while layout and presentation state stay with the field.
priv struct FieldHistoryEntry {
  before : @text.TextDocument
  after : @text.TextDocument
}

///|
/// Adjacent edits may extend only the currently open run of the same kind.
priv enum FieldHistoryGroupKind {
  Typing
  Backspace
  ForwardDelete
} derive(Eq)

///|
/// Immutable bounded history. These arrays are never returned, and every
/// transition that changes a stack first makes detached copies.
priv struct FieldHistory {
  undo : Array[FieldHistoryEntry]
  redo : Array[FieldHistoryEntry]
  payload_bytes : Int
  open_group : FieldHistoryGroupKind?
}

///|
const MAX_FIELD_HISTORY_ENTRIES : Int = 64

///|
const MAX_FIELD_HISTORY_PAYLOAD_BYTES : Int = 65536

///|
fn FieldHistory::empty() -> FieldHistory {
  { undo: [], redo: [], payload_bytes: 0, open_group: None, }
}

///|
/// End a typing/deletion run without changing retained edits or byte charge.
fn FieldHistory::close_group(self : FieldHistory) -> FieldHistory {
  { ..self, open_group: None, }
}

///|
fn FieldHistory::can_undo(self : FieldHistory) -> Bool {
  self.undo.length() > 0
}

///|
fn FieldHistory::can_redo(self : FieldHistory) -> Bool {
  self.redo.length() > 0
}

///|
fn FieldHistory::undo_entry(self : FieldHistory) -> FieldHistoryEntry? {
  if self.undo.length() == 0 {
    None
  } else {
    Some(self.undo[self.undo.length() - 1])
  }
}

///|
fn FieldHistory::redo_entry(self : FieldHistory) -> FieldHistoryEntry? {
  if self.redo.length() == 0 {
    None
  } else {
    Some(self.redo[self.redo.length() - 1])
  }
}

///|
fn field_history_entry_payload_bytes(
  entry : FieldHistoryEntry,
) -> Result[Int, TextFieldError] {
  let before_bytes = match entry.before.utf8_length() {
    Ok(value) if value <= MAX_FIELD_UTF8_BYTES => value
    _ => return Err(TextTooLarge)
  }
  let after_bytes = match entry.after.utf8_length() {
    Ok(value) if value <= MAX_FIELD_UTF8_BYTES => value
    _ => return Err(TextTooLarge)
  }
  // The document limit keeps each operand small, but still check before
  // adding so this remains safe if either limit changes later.
  if after_bytes > MAX_FIELD_HISTORY_PAYLOAD_BYTES - before_bytes {
    return Err(TextTooLarge)
  }
  Ok(before_bytes + after_bytes)
}

///|
fn field_history_undo_payload_bytes(
  entries : Array[FieldHistoryEntry],
) -> Result[Int, TextFieldError] {
  let mut total = 0
  for entry in entries {
    let entry_bytes = match field_history_entry_payload_bytes(entry) {
      Ok(value) => value
      Err(error) => return Err(error)
    }
    if total > MAX_FIELD_HISTORY_PAYLOAD_BYTES ||
      entry_bytes > MAX_FIELD_HISTORY_PAYLOAD_BYTES - total {
      return Err(TextTooLarge)
    }
    total += entry_bytes
  }
  Ok(total)
}

///|
fn field_history_group_eligible(
  kind : FieldHistoryGroupKind?,
  before : @text.TextDocument,
  after : @text.TextDocument,
) -> Bool {
  match kind {
    Some(Typing) => after.selection().is_collapsed()
    Some(Backspace) | Some(ForwardDelete) =>
      before.selection().is_collapsed() && after.selection().is_collapsed()
    None => false
  }
}

///|
fn FieldHistory::move_undo(self : FieldHistory) -> FieldHistory {
  let undo_count = self.undo.length()
  let redo_count = self.redo.length()
  if undo_count == 0 ||
    undo_count > MAX_FIELD_HISTORY_ENTRIES ||
    redo_count > MAX_FIELD_HISTORY_ENTRIES ||
    undo_count > MAX_FIELD_HISTORY_ENTRIES - redo_count ||
    redo_count >= MAX_FIELD_HISTORY_ENTRIES {
    return self
  }
  let undo = self.undo.copy()
  let redo = self.redo.copy()
  let entry = undo.remove(undo.length() - 1)
  redo.push(entry)
  { undo, redo, payload_bytes: self.payload_bytes, open_group: None, }
}

///|
fn FieldHistory::move_redo(self : FieldHistory) -> FieldHistory {
  let undo_count = self.undo.length()
  let redo_count = self.redo.length()
  if redo_count == 0 ||
    undo_count > MAX_FIELD_HISTORY_ENTRIES ||
    redo_count > MAX_FIELD_HISTORY_ENTRIES ||
    undo_count > MAX_FIELD_HISTORY_ENTRIES - redo_count ||
    undo_count >= MAX_FIELD_HISTORY_ENTRIES {
    return self
  }
  let undo = self.undo.copy()
  let redo = self.redo.copy()
  let entry = redo.remove(redo.length() - 1)
  undo.push(entry)
  { undo, redo, payload_bytes: self.payload_bytes, open_group: None, }
}

///|
/// Record a standalone successful content change. Equal text retains both
/// stacks and their snapshots while closing any coalescing run.
fn FieldHistory::record(
  self : FieldHistory,
  before : @text.TextDocument,
  after : @text.TextDocument,
) -> Result[FieldHistory, TextFieldError] {
  self.record_with_group(before, after, None)
}

///|
/// Record a successful adjacent typing or deletion edit. The explicit kind
/// prevents endpoint equality alone from reopening a closed or different run.
fn FieldHistory::record_group(
  self : FieldHistory,
  before : @text.TextDocument,
  after : @text.TextDocument,
  kind : FieldHistoryGroupKind,
) -> Result[FieldHistory, TextFieldError] {
  self.record_with_group(before, after, Some(kind))
}

///|
fn FieldHistory::record_with_group(
  self : FieldHistory,
  before : @text.TextDocument,
  after : @text.TextDocument,
  kind : FieldHistoryGroupKind?,
) -> Result[FieldHistory, TextFieldError] {
  match validate_field_text(before) {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  match validate_field_text(after) {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  if before.text() == after.text() {
    return Ok(self.close_group())
  }

  let eligible = field_history_group_eligible(kind, before, after)
  let can_extend = match (self.open_group, kind, self.undo_entry()) {
    (Some(open), Some(next), Some(previous)) if open == next &&
      eligible &&
      self.redo.length() == 0 &&
      previous.after == before &&
      after.selection().is_collapsed() => true
    _ => false
  }
  if can_extend {
    let previous = self.undo[self.undo.length() - 1]
    let merged = { before: previous.before, after, }
    let merged_bytes = match field_history_entry_payload_bytes(merged) {
      Ok(value) => value
      Err(error) => return Err(error)
    }
    if merged_bytes > MAX_FIELD_HISTORY_PAYLOAD_BYTES {
      return Err(TextTooLarge)
    }

    // The merged group replaces its newest entry. Charge only the merged
    // endpoints, then evict oldest whole groups if the bounded payload needs
    // room. Every check completes before the detached stack is built.
    let prefix_count = self.undo.length() - 1
    let mut kept_count = prefix_count
    let mut kept_bytes = 0
    for index in 0..<prefix_count {
      let entry_bytes = match
        field_history_entry_payload_bytes(self.undo[index]) {
        Ok(value) => value
        Err(error) => return Err(error)
      }
      if kept_bytes > MAX_FIELD_HISTORY_PAYLOAD_BYTES ||
        entry_bytes > MAX_FIELD_HISTORY_PAYLOAD_BYTES - kept_bytes {
        return Err(TextTooLarge)
      }
      kept_bytes += entry_bytes
    }
    let mut first_kept = 0
    while kept_count > 0 &&
          (
            kept_count + 1 > MAX_FIELD_HISTORY_ENTRIES ||
            merged_bytes > MAX_FIELD_HISTORY_PAYLOAD_BYTES - kept_bytes
          ) {
      let oldest_bytes = match
        field_history_entry_payload_bytes(self.undo[first_kept]) {
        Ok(value) => value
        Err(error) => return Err(error)
      }
      if oldest_bytes > kept_bytes {
        return Err(TextTooLarge)
      }
      kept_bytes -= oldest_bytes
      kept_count -= 1
      first_kept += 1
    }
    if kept_count + 1 > MAX_FIELD_HISTORY_ENTRIES ||
      merged_bytes > MAX_FIELD_HISTORY_PAYLOAD_BYTES - kept_bytes {
      return Err(TextTooLarge)
    }
    let undo = []
    for index in first_kept..<prefix_count {
      undo.push(self.undo[index])
    }
    undo.push(merged)
    return Ok({
      undo,
      redo: [],
      payload_bytes: kept_bytes + merged_bytes,
      open_group: kind,
    })
  }

  let entry = { before, after, }
  let entry_bytes = match field_history_entry_payload_bytes(entry) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  if entry_bytes > MAX_FIELD_HISTORY_PAYLOAD_BYTES {
    return Err(TextTooLarge)
  }

  // A new edit invalidates redo. Recompute retained undo charge before
  // deciding the exact number of whole oldest entries to evict.
  let retained_bytes = match field_history_undo_payload_bytes(self.undo) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let mut kept_count = self.undo.length()
  let mut kept_bytes = retained_bytes
  let mut first_kept = 0
  while kept_count > 0 &&
        (
          kept_count >= MAX_FIELD_HISTORY_ENTRIES ||
          entry_bytes > MAX_FIELD_HISTORY_PAYLOAD_BYTES - kept_bytes
        ) {
    let oldest_bytes = match
      field_history_entry_payload_bytes(self.undo[first_kept]) {
      Ok(value) => value
      Err(error) => return Err(error)
    }
    if oldest_bytes > kept_bytes {
      return Err(TextTooLarge)
    }
    kept_bytes -= oldest_bytes
    kept_count -= 1
    first_kept += 1
  }
  if kept_count >= MAX_FIELD_HISTORY_ENTRIES ||
    entry_bytes > MAX_FIELD_HISTORY_PAYLOAD_BYTES - kept_bytes {
    return Err(TextTooLarge)
  }

  // All count and byte checks precede array growth. Build an independent
  // stack so previously returned snapshots remain unchanged.
  let undo = []
  for index in first_kept..<self.undo.length() {
    undo.push(self.undo[index])
  }
  undo.push(entry)
  let open_group = if eligible { kind } else { None }
  Ok({ undo, redo: [], payload_bytes: kept_bytes + entry_bytes, open_group, })
}

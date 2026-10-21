///|
/// A copied macOS projection for one custom Button AX element.
///
/// This carries attributes only. The MoonBit owner retains the semantic
/// `NodeId` and `ActionRequest`; AppKit receives a revocable transport token.
pub struct ButtonAccessibilitySnapshot {
  name : String
  bounds : @primitives.Rect
  enabled : Bool
  loading : Bool
  focused : Bool
  activations : Int32
}

///|
pub fn ButtonAccessibilitySnapshot::new(
  name : String,
  bounds : @primitives.Rect,
  enabled : Bool,
  loading : Bool,
  focused : Bool,
  activations : Int32,
) -> ButtonAccessibilitySnapshot {
  { name, bounds, enabled, loading, focused, activations, }
}

///|
struct MacAXButtonPayload {
  version : Int32
  role : String
  name : String
  left : Double
  top : Double
  width : Double
  height : Double
  enabled : Bool
  loading : Bool
  focused : Bool
  activations : Int32
  actions : Array[String]
} derive(ToJson)

///|
pub extend MacAXButtonPayload with ToJson::{to_json}

///|
fn macos_ax_payload(snapshot : ButtonAccessibilitySnapshot) -> Bytes {
  let size = snapshot.bounds.size()
  let value = MacAXButtonPayload::{
    version: 1,
    role: "button",
    name: snapshot.name,
    left: snapshot.bounds.left(),
    top: snapshot.bounds.top(),
    width: size.width(),
    height: size.height(),
    enabled: snapshot.enabled,
    loading: snapshot.loading,
    focused: snapshot.focused,
    activations: snapshot.activations,
    actions: ["Invoke"],
  }
  @utf8.encode(@json.to_json(value).stringify())
}

///|
/// Publish the copied Button attributes to AppKit and return their current
/// revocable transport binding. Pass zero to create a new binding; pass the
/// existing binding to update attributes for the same live semantic node.
pub fn Host::publish_button_accessibility(
  self : Host,
  window : @platform.WindowId,
  existing_binding : Int64,
  snapshot : ButtonAccessibilitySnapshot,
) -> Result[Int64, @diagnostics.FrameworkError] {
  match self.check() {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  let bytes = macos_ax_payload(snapshot)
  let output : FixedArray[Int64] = FixedArray::make(1, Int64::from_int(0))
  let result = accessibility_publish(
    window.value(),
    existing_binding,
    bytes,
    bytes.length(),
    output,
  )
  match status(result, "publish_button_accessibility") {
    Err(error) => Err(error)
    Ok(_) =>
      if output[0] > 0 {
        Ok(output[0])
      } else {
        Err(error(@diagnostics.NativeFailure, "publish_button_accessibility"))
      }
  }
}

///|
/// Revoke the current native Button element and discard requests queued for its
/// binding. A zero binding revokes any current element for this window.
pub fn Host::revoke_button_accessibility(
  self : Host,
  window : @platform.WindowId,
  binding : Int64,
) -> Result[Unit, @diagnostics.FrameworkError] {
  match self.check() {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  status(
    accessibility_revoke(window.value(), binding),
    "revoke_button_accessibility",
  )
}

///|
/// Take one native semantic request. The result is only the opaque transport
/// token; the caller must map it to its retained full NodeId request and ask
/// the live fixture to validate and dispatch that request immediately.
pub fn Host::take_button_accessibility_request(
  self : Host,
  window : @platform.WindowId,
) -> Result[Int64?, @diagnostics.FrameworkError] {
  match self.check() {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  let output : FixedArray[Int64] = FixedArray::make(1, Int64::from_int(0))
  match accessibility_take_request(window.value(), output) {
    0 => Ok(None)
    1 =>
      if output[0] > 0 {
        Ok(Some(output[0]))
      } else {
        Err(
          error(@diagnostics.NativeFailure, "take_button_accessibility_request"),
        )
      }
    result =>
      match status(result, "take_button_accessibility_request") {
        Err(error) => Err(error)
        Ok(_) =>
          Err(
            error(
              @diagnostics.NativeFailure,
              "take_button_accessibility_request",
            ),
          )
      }
  }
}

///|
/// A copied macOS projection for one custom TextField AX element.
///
/// The value and selection are the committed field state at publish time.
/// `selection_offset` and `selection_length` are UTF-16 code units, matching
/// `@text.TextDocument`. AppKit receives a revocable transport token, not the
/// MoonBit field identity.
pub struct TextFieldAccessibilitySnapshot {
  label : String
  value : String
  bounds : @primitives.Rect
  focused : Bool
  editable : Bool
  selection_offset : Int32
  selection_length : Int32
}

///|
pub fn TextFieldAccessibilitySnapshot::new(
  label : String,
  value : String,
  bounds : @primitives.Rect,
  focused : Bool,
  editable : Bool,
  selection_offset : Int32,
  selection_length : Int32,
) -> TextFieldAccessibilitySnapshot {
  {
    label,
    value,
    bounds,
    focused,
    editable,
    selection_offset,
    selection_length,
  }
}

///|
struct MacAXTextFieldPayload {
  version : Int32
  role : String
  label : String
  value : String
  left : Double
  top : Double
  width : Double
  height : Double
  focused : Bool
  editable : Bool
  selection_start : Int32
  selection_length : Int32
} derive(ToJson)

///|
pub extend MacAXTextFieldPayload with ToJson::{to_json}

///|
fn macos_ax_field_payload(snapshot : TextFieldAccessibilitySnapshot) -> Bytes {
  let size = snapshot.bounds.size()
  let value = MacAXTextFieldPayload::{
    version: 1,
    role: "text_field",
    label: snapshot.label,
    value: snapshot.value,
    left: snapshot.bounds.left(),
    top: snapshot.bounds.top(),
    width: size.width(),
    height: size.height(),
    focused: snapshot.focused,
    editable: snapshot.editable,
    selection_start: snapshot.selection_offset,
    selection_length: snapshot.selection_length,
  }
  @utf8.encode(@json.to_json(value).stringify())
}

///|
/// Publish the copied TextField attributes to AppKit and return their current
/// revocable transport binding. Pass zero to create a new binding; pass the
/// existing binding to update the same live semantic node. A negative or
/// out-of-range UTF-16 selection is rejected before any native call.
pub fn Host::publish_text_field_accessibility(
  self : Host,
  window : @platform.WindowId,
  existing_binding : Int64,
  snapshot : TextFieldAccessibilitySnapshot,
) -> Result[Int64, @diagnostics.FrameworkError] {
  match self.check() {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  if snapshot.selection_offset < 0 ||
    snapshot.selection_length < 0 ||
    snapshot.selection_offset + snapshot.selection_length >
    snapshot.value.length() {
    return Err(
      error(@diagnostics.InvalidInput, "publish_text_field_accessibility"),
    )
  }
  let bytes = macos_ax_field_payload(snapshot)
  let output : FixedArray[Int64] = FixedArray::make(1, Int64::from_int(0))
  let result = accessibility_publish_field(
    window.value(),
    existing_binding,
    bytes,
    bytes.length(),
    output,
  )
  match status(result, "publish_text_field_accessibility") {
    Err(error) => Err(error)
    Ok(_) =>
      if output[0] > 0 {
        Ok(output[0])
      } else {
        Err(
          error(@diagnostics.NativeFailure, "publish_text_field_accessibility"),
        )
      }
  }
}

///|
/// Revoke the current native TextField element. A zero binding revokes any
/// current field element for this window.
pub fn Host::revoke_text_field_accessibility(
  self : Host,
  window : @platform.WindowId,
  binding : Int64,
) -> Result[Unit, @diagnostics.FrameworkError] {
  match self.check() {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  status(
    accessibility_revoke_field(window.value(), binding),
    "revoke_text_field_accessibility",
  )
}

///|
/// A copied macOS projection for one modal Dialog AX element.
///
/// The title and frame describe the open dialog. The application still owns
/// dismissal, initial focus and the dialog lifecycle; AppKit receives only a
/// revocable transport token and copied attributes.
pub struct DialogAccessibilitySnapshot {
  title : String
  bounds : @primitives.Rect
  focused : Bool
}

///|
pub fn DialogAccessibilitySnapshot::new(
  title : String,
  bounds : @primitives.Rect,
  focused : Bool,
) -> DialogAccessibilitySnapshot {
  { title, bounds, focused, }
}

///|
struct MacAXDialogPayload {
  version : Int32
  role : String
  title : String
  left : Double
  top : Double
  width : Double
  height : Double
  focused : Bool
} derive(ToJson)

///|
pub extend MacAXDialogPayload with ToJson::{to_json}

///|
fn macos_ax_dialog_payload(snapshot : DialogAccessibilitySnapshot) -> Bytes {
  let size = snapshot.bounds.size()
  let value = MacAXDialogPayload::{
    version: 1,
    role: "dialog",
    title: snapshot.title,
    left: snapshot.bounds.left(),
    top: snapshot.bounds.top(),
    width: size.width(),
    height: size.height(),
    focused: snapshot.focused,
  }
  @utf8.encode(@json.to_json(value).stringify())
}

///|
/// Publish the copied Dialog attributes to AppKit and return their current
/// revocable transport binding. Pass zero to create a new binding; pass the
/// existing binding to update the same live dialog. An empty or oversized
/// title is rejected before any native call, and a window exposes at most one
/// dialog element at a time.
pub fn Host::publish_dialog_accessibility(
  self : Host,
  window : @platform.WindowId,
  existing_binding : Int64,
  snapshot : DialogAccessibilitySnapshot,
) -> Result[Int64, @diagnostics.FrameworkError] {
  match self.check() {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  if snapshot.title.trim().is_empty() || snapshot.title.length() > 4096 {
    return Err(error(@diagnostics.InvalidInput, "publish_dialog_accessibility"))
  }
  let bytes = macos_ax_dialog_payload(snapshot)
  let output : FixedArray[Int64] = FixedArray::make(1, Int64::from_int(0))
  let result = accessibility_publish_dialog(
    window.value(),
    existing_binding,
    bytes,
    bytes.length(),
    output,
  )
  match status(result, "publish_dialog_accessibility") {
    Err(error) => Err(error)
    Ok(_) =>
      if output[0] > 0 {
        Ok(output[0])
      } else {
        Err(error(@diagnostics.NativeFailure, "publish_dialog_accessibility"))
      }
  }
}

///|
/// Revoke the current native Dialog element. A zero binding revokes any current
/// dialog element for this window.
pub fn Host::revoke_dialog_accessibility(
  self : Host,
  window : @platform.WindowId,
  binding : Int64,
) -> Result[Unit, @diagnostics.FrameworkError] {
  match self.check() {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  status(
    accessibility_revoke_dialog(window.value(), binding),
    "revoke_dialog_accessibility",
  )
}

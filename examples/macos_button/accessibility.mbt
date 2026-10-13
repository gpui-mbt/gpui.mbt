///|
/// The complete shared identity stays in MoonBit beside the transport token.
struct MacButtonAXNode {
  node_id : @accessibility.NodeId
  request : @accessibility.ActionRequest
  role : @accessibility.AccessibilityRole
  name : String
  bounds : @primitives.Rect
  enabled : Bool
  loading : Bool
  focused : Bool
}

///|
struct MacButtonAXBinding {
  node : MacButtonAXNode
  transport_token : Int64
  activations : Int
}

///|
/// Project exactly the fixture's existing Button node. No caller-owned key is
/// used as AX identity or as action authority.
fn mac_button_accessibility_node(
  demo : @fixture.ButtonDemo,
) -> MacButtonAXNode? {
  let snapshot = match demo.accessibility_source() {
    Ok((_, value)) => value
    Err(_) => return None
  }
  let nodes = snapshot.nodes()
  let mut result : MacButtonAXNode? = None
  for node in nodes {
    let actions = node.supported_actions()
    if node.role() == @accessibility.Button &&
      node.name() == "Run action" &&
      actions.length() == 1 &&
      actions[0] == @accessibility.Invoke {
      result = Some({
        node_id: node.id(),
        request: @accessibility.ActionRequest::new(
          node.id(),
          @accessibility.Invoke,
        ),
        role: node.role(),
        name: node.name(),
        bounds: node.bounds(),
        enabled: node.is_enabled(),
        loading: node.is_loading(),
        focused: node.is_focused(),
      })
    }
  }
  result
}

///|
fn mac_button_ax_requires_new_binding(
  previous : MacButtonAXNode,
  current : MacButtonAXNode,
) -> Bool {
  previous.node_id != current.node_id ||
  previous.bounds != current.bounds ||
  previous.enabled != current.enabled ||
  previous.loading != current.loading
}

///|
fn mac_button_ax_matches(
  previous : MacButtonAXNode,
  previous_activations : Int,
  current : MacButtonAXNode,
  current_activations : Int,
) -> Bool {
  previous.node_id == current.node_id &&
  previous.role == current.role &&
  previous.name == current.name &&
  previous.bounds == current.bounds &&
  previous.enabled == current.enabled &&
  previous.loading == current.loading &&
  previous.focused == current.focused &&
  previous_activations == current_activations
}

///|
fn mac_button_ax_snapshot(
  node : MacButtonAXNode,
  activations : Int,
) -> @macos.ButtonAccessibilitySnapshot {
  @macos.ButtonAccessibilitySnapshot::new(
    node.name,
    node.bounds,
    node.enabled,
    node.loading,
    node.focused,
    activations,
  )
}

///|
/// Do not expose stale fixture nodes while the host session is suspended or
/// closing; the native binding stays absent until a live viewport exists.
fn mac_button_ax_current_node(session : MacButtonSession) -> MacButtonAXNode? {
  if session.is_presentable() && mac_button_session_is_current(session) {
    mac_button_accessibility_node(session.demo())
  } else {
    None
  }
}

///|
fn mac_button_stale_session_error(
  operation : String,
) -> @diagnostics.FrameworkError {
  @diagnostics.FrameworkError::new(
    @diagnostics.StaleHandle,
    operation,
    subsystem="macos-button",
    backend="appkit-metal",
    message="stale Button session cannot update the current owner",
  )
}

///|
/// Reconcile AppKit's element with the latest committed fixture snapshot.
/// Generation, bounds, enabled, and loading changes revoke the old binding and
/// all requests queued for it. Focus and owner-side activation count update on
/// the same live element.
fn MacButtonSession::sync_accessibility(
  self : MacButtonSession,
  host : @macos.Host,
  window : @platform.WindowId,
) -> Result[MacButtonSession, @diagnostics.FrameworkError] {
  if !mac_button_session_is_current(self) {
    return Err(mac_button_stale_session_error("sync_button_accessibility"))
  }
  let current = mac_button_ax_current_node(self)
  match (self.accessibility_binding, current) {
    (None, None) => Ok(self)
    (Some(binding), None) => {
      let next = mac_button_session_advance(self)
      match host.revoke_button_accessibility(window, binding.transport_token) {
        Err(error) => return Err(error)
        Ok(_) => ()
      }
      Ok({ ..next, accessibility_binding: None, })
    }
    (None, Some(node)) => {
      let next = mac_button_session_advance(self)
      let transport_token = match
        host.publish_button_accessibility(
          window,
          0,
          mac_button_ax_snapshot(node, self.demo.activations()),
        ) {
        Ok(value) => value
        Err(error) => return Err(error)
      }
      Ok({
        ..next,
        accessibility_binding: Some({
          node,
          transport_token,
          activations: self.demo.activations(),
        }),
      })
    }
    (Some(binding), Some(node)) => {
      if mac_button_ax_matches(
          binding.node,
          binding.activations,
          node,
          self.demo.activations(),
        ) {
        return Ok(self)
      }
      let next = mac_button_session_advance(self)
      let previous_token : Int64 = if mac_button_ax_requires_new_binding(
          binding.node,
          node,
        ) {
        match
          host.revoke_button_accessibility(window, binding.transport_token) {
          Err(error) => return Err(error)
          Ok(_) => Int64::from_int(0)
        }
      } else {
        binding.transport_token
      }
      let transport_token = match
        host.publish_button_accessibility(
          window,
          previous_token,
          mac_button_ax_snapshot(node, self.demo.activations()),
        ) {
        Ok(value) => value
        Err(error) => return Err(error)
      }
      Ok({
        ..next,
        accessibility_binding: Some({
          node,
          transport_token,
          activations: self.demo.activations(),
        }),
      })
    }
  }
}

///|
fn MacButtonSession::revoke_accessibility(
  self : MacButtonSession,
  host : @macos.Host,
  window : @platform.WindowId,
) -> Result[MacButtonSession, @diagnostics.FrameworkError] {
  if !mac_button_session_is_current(self) {
    return Err(mac_button_stale_session_error("revoke_button_accessibility"))
  }
  match self.accessibility_binding {
    None => Ok(self)
    Some(binding) => {
      let next = mac_button_session_advance(self)
      match host.revoke_button_accessibility(window, binding.transport_token) {
        Err(error) => Err(error)
        Ok(_) => Ok({ ..next, accessibility_binding: None, })
      }
    }
  }
}

///|
/// Resolve one transport token back to the retained full ActionRequest and
/// dispatch it through the fixture's current-state owner path.
fn MacButtonSession::dispatch_accessibility_token(
  self : MacButtonSession,
  transport_token : Int64,
) -> (MacButtonSession, Bool) {
  if !mac_button_session_is_current(self) {
    return (self, false)
  }
  match self.accessibility_binding {
    Some(binding) if binding.transport_token == transport_token =>
      match self.demo.dispatch_accessibility_request(binding.node.request) {
        Ok(demo) => (mac_button_session_advance({ ..self, demo, }), true)
        Err(_) => (self, false)
      }
    _ => (self, false)
  }
}

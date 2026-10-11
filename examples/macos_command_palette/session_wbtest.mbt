///|
fn mac_palette_test_key(
  key : @primitives.Key,
  modifiers? : @primitives.Modifiers = @primitives.Modifiers::none(),
  repeat? : Bool = false,
) -> @primitives.InputEvent {
  @primitives.KeyPressed(key~, modifiers~, repeat~)
}

///|
fn mac_palette_test_session() -> MacPaletteSession? raise {
  match @macos_text.require_grayscale_raster() {
    Ok(_) =>
      Some(
        MacPaletteSession::new(MAC_PALETTE_WIDTH, MAC_PALETTE_HEIGHT, 2.0).unwrap(),
      )
    Err(@macos_text.UnsupportedPlatform) =>
      match MacPaletteSession::new(MAC_PALETTE_WIDTH, MAC_PALETTE_HEIGHT, 2.0) {
        Err(error) => {
          assert_eq(error.code().label(), "unsupported_capability")
          assert_eq(error.operation(), "palette_text")
          None
        }
        Ok(_) => fail("palette session started without CoreText")
      }
    Err(_) => abort("CoreText grayscale raster unavailable on this host")
  }
}

///|
fn mac_palette_test_open(
  session : MacPaletteSession,
) -> Result[Bool, @diagnostics.FrameworkError] {
  session.handle_input(
    mac_palette_test_key(
      @primitives.Character("k"),
      modifiers=@primitives.Modifiers::new(
        shift=false,
        control=false,
        alt=false,
        meta=true,
      ),
    ),
  )
}

///|
test "macOS palette reuses bounded filtering, navigation, activation, and focus" {
  let session = match mac_palette_test_session() {
    Some(value) => value
    None => return
  }
  assert_true(mac_palette_test_open(session).unwrap())
  assert_true(session.is_open())
  assert_eq(session.epoch(), 1)
  assert_eq(session.tree.val.focused(), Some(2))
  let typed = session
    .handle_input(mac_palette_test_key(@primitives.Character("S")))
    .unwrap()
  assert_true(typed)
  assert_eq(session.palette.picker().query(), "s")
  assert_eq(session.palette.picker().match_count(), 10)
  let moved = session
    .handle_input(mac_palette_test_key(@primitives.ArrowDown))
    .unwrap()
  assert_true(moved)
  assert_eq(
    session.palette.picker().active_command().unwrap().id(),
    "palette.toggle_sidebar",
  )
  let activated = session
    .handle_input(mac_palette_test_key(@primitives.Enter))
    .unwrap()
  assert_true(activated)
  assert_false(session.is_open())
  assert_eq(session.actions.val, 1)
  assert_eq(session.last_action.val, "palette.toggle_sidebar")
  assert_eq(session.tree.val.focused(), Some(9))
  let enter_release = session
    .handle_input(
      @primitives.KeyReleased(
        key=@primitives.Enter,
        modifiers=@primitives.Modifiers::none(),
      ),
    )
    .unwrap()
  assert_true(enter_release)
  assert_eq(session.background_keys.val, 0)
  let fresh_enter_background_key = session
    .handle_input(mac_palette_test_key(@primitives.Character("z")))
    .unwrap()
  assert_false(fresh_enter_background_key)
  assert_eq(session.background_keys.val, 1)
  assert_true(mac_palette_test_open(session).unwrap())
  assert_eq(session.epoch(), 2)
  assert_eq(session.palette.picker().query(), "")
  let cancelled = session
    .handle_input(mac_palette_test_key(@primitives.Escape))
    .unwrap()
  assert_true(cancelled)
  assert_false(session.is_open())
  assert_eq(session.actions.val, 1)
  let escape_release = session
    .handle_input(
      @primitives.KeyReleased(
        key=@primitives.Escape,
        modifiers=@primitives.Modifiers::none(),
      ),
    )
    .unwrap()
  assert_true(escape_release)
  let fresh_escape_background_key = session
    .handle_input(mac_palette_test_key(@primitives.Character("x")))
    .unwrap()
  assert_false(fresh_escape_background_key)
  assert_eq(session.background_keys.val, 2)
  assert_true(mac_palette_test_open(session).unwrap())
  assert_eq(session.epoch(), 3)
  assert_eq(session.palette.picker().query(), "")
}

///|
test "macOS palette consumes non-ASCII and modified search keys without editing" {
  let session = match mac_palette_test_session() {
    Some(value) => value
    None => return
  }
  assert_true(mac_palette_test_open(session).unwrap())
  let non_ascii = session
    .handle_input(mac_palette_test_key(@primitives.Character("あ")))
    .unwrap()
  assert_true(non_ascii)
  let command_modified = session
    .handle_input(
      mac_palette_test_key(
        @primitives.Character("x"),
        modifiers=@primitives.Modifiers::new(
          shift=false,
          control=false,
          alt=false,
          meta=true,
        ),
      ),
    )
    .unwrap()
  assert_true(command_modified)
  assert_eq(session.palette.picker().query(), "")
  assert_eq(session.palette.picker().match_count(), 13)
}

///|
test "closed opener release is consumed before background routing" {
  let session = match mac_palette_test_session() {
    Some(value) => value
    None => return
  }
  let released = session
    .handle_input(
      @primitives.KeyReleased(
        key=@primitives.Character("k"),
        modifiers=@primitives.Modifiers::new(
          shift=false,
          control=false,
          alt=false,
          meta=true,
        ),
      ),
    )
    .unwrap()
  assert_true(released)
  assert_eq(session.background_keys.val, 0)
}

///|
test "shift-command-K remains available to the background app" {
  let session = match mac_palette_test_session() {
    Some(value) => value
    None => return
  }
  let opened = session
    .handle_input(
      mac_palette_test_key(
        @primitives.Character("K"),
        modifiers=@primitives.Modifiers::new(
          shift=true,
          control=false,
          alt=false,
          meta=true,
        ),
      ),
    )
    .unwrap()
  assert_false(opened)
  assert_false(session.is_open())
  assert_eq(session.background_keys.val, 1)
}

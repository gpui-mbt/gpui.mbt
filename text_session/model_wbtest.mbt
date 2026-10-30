///|
fn private_measure(
  document : @text.TextDocument,
) -> Result[@text_layout.TextMeasurement, @text_field.TextFieldError] {
  let carets = []
  for offset in 0..<=document.utf16_length() {
    let rect = @primitives.Rect::new(offset.to_double() * 8.0, 0.0, 0.0, 16.0).unwrap()
    carets.push(
      @text_layout.CaretGeometry::new(offset, true, rect, rect).unwrap(),
    )
  }
  let rect = @primitives.Rect::new(
    0.0,
    0.0,
    document.utf16_length().to_double() * 8.0,
    16.0,
  ).unwrap()
  Ok(
    @text_layout.TextMeasurement::new(document, rect, rect, 12.0, 1, 0, carets).unwrap(),
  )
}

///|
fn private_owner() -> TextSession {
  let field = @text_field.TextField::new(
      19UL,
      @primitives.Rect::new(0.0, 0.0, 100.0, 36.0).unwrap(),
      10.0,
      @text.TextDocument::new("abc").unwrap(),
      private_measure,
      (_, _) => Ok(()),
    )
    .unwrap()
    .with_focus(true)
    .unwrap()
  TextSession::new(@platform.WindowId::new(1L), 7UL, field).unwrap()
}

///|
test "bounds preparation is rejected reentrantly and poisons outer publish" {
  let session = private_owner()
  let before = session.snapshot()
  let target = session.target().unwrap()
  let nested_rejected = [false]
  let result = session.apply_batch(
    target,
    [PreviewUtf8("X", 1, 1)],
    fn(document) {
      nested_rejected[0] = session.prepare_bounds(
          target,
          @primitives.Rect::new(0.0, 0.0, 140.0, 36.0).unwrap(),
        )
        is Err(Reentrant)
      private_measure(document)
    },
    (_, _) => Ok(()),
  )
  assert_true(nested_rejected[0])
  assert_true(result is Err(Reentrant))
  let after = session.snapshot()
  assert_true(after.field().document() == before.field().document())
  assert_true(after.field().bounds() == before.field().bounds())
  assert_eq(after.published_revision(), before.published_revision())
  assert_eq(after.delivery_watermark(), before.delivery_watermark())
}

///|
test "private incarnation shared probe is stable symmetric and restores markers" {
  let first = identity()
  let shared = first
  let second = identity()
  for _ in 0..<100 {
    assert_true(same_identity(first, shared))
    assert_true(same_identity(shared, first))
    assert_false(same_identity(first, second))
    assert_false(same_identity(second, shared))
    assert_false(first.marker.val)
    assert_false(shared.marker.val)
    assert_false(second.marker.val)
  }
}

///|
test "each private incarnation independently rejects a forged same number binding" {
  let session = private_owner()
  let target = session.target().unwrap()
  let calls = [0]
  let measure = fn(document) {
    calls[0] += 1
    private_measure(document)
  }
  for
    stale in [
      { ..target, window_instance: identity(), },
      { ..target, root_instance: identity(), },
      { ..target, field_instance: identity(), },
    ] {
    assert_true(
      session.apply_batch(stale, [PreviewUtf8("X", 1, 1)], measure, (_, _) => {
        Ok(())
      })
      is Err(StaleBinding),
    )
  }
  assert_true(
    session.apply_batch(
      { ..target, owner: identity(), },
      [PreviewUtf8("X", 1, 1)],
      measure,
      (_, _) => Ok(()),
    )
    is Err(ForeignOwner),
  )
  assert_true(
    session.apply_batch(
      { ..target, revision: 1UL, },
      [PreviewUtf8("X", 1, 1)],
      measure,
      (_, _) => Ok(()),
    )
    is Err(StaleRevision),
  )
  assert_true(
    session.apply_batch(
      { ..target, session: 2UL, },
      [PreviewUtf8("X", 1, 1)],
      measure,
      (_, _) => Ok(()),
    )
    is Err(StaleSession),
  )
  assert_true(
    session.apply_batch(
      { ..target, sequence: 2UL, },
      [PreviewUtf8("X", 1, 1)],
      measure,
      (_, _) => Ok(()),
    )
    is Err(OutOfOrder),
  )
  assert_true(
    session.apply_batch(
      { ..target, sequence: 0UL, },
      [PreviewUtf8("X", 1, 1)],
      measure,
      (_, _) => Ok(()),
    )
    is Err(Replay),
  )
  assert_eq(calls[0], 0)
}

///|
test "checked session published document and delivery counters never wrap" {
  assert_true(advance(MAX_COUNTER) is Err(Exhausted))
  assert_eq(advance(MAX_COUNTER - 1UL).unwrap(), MAX_COUNTER)
  let calls = [0]
  let measure = fn(document) {
    calls[0] += 1
    private_measure(document)
  }
  let session = private_owner()
  session.state.val = { ..session.state.val, revision: MAX_COUNTER, }
  let target = session.target().unwrap()
  assert_true(
    session.apply_batch(target, [PreviewUtf8("X", 1, 1)], measure, (_, _) => {
      Ok(())
    })
    is Err(Exhausted),
  )
  assert_true(session.request_end(target, Blur) is Err(Exhausted))
  assert_eq(session.snapshot().published_revision(), MAX_COUNTER)
  assert_eq(calls[0], 0)
  // Closing remains possible after any counter is exhausted.
  session.close().unwrap()
  assert_true(session.snapshot().is_closed())
  let session = private_owner()
  session.state.val = { ..session.state.val, session: MAX_COUNTER, }
  assert_true(session.rearm() is Err(Exhausted))
  assert_true(
    session.rebind(@platform.WindowId::new(1L), 7UL, session.snapshot().field())
    is Err(Exhausted),
  )
  assert_eq(session.snapshot().session_id(), MAX_COUNTER)
  let session = private_owner()
  session.state.val = { ..session.state.val, sequence: MAX_COUNTER, }
  assert_true(session.target() is Err(Exhausted))
  let session = private_owner()
  session.state.val = { ..session.state.val, document_revision: MAX_COUNTER, }
  let target = session.target().unwrap()
  assert_true(
    session.apply_batch(
      target,
      [PreviewUtf8("X", 1, 1), Commit("Y")],
      measure,
      (_, _) => Ok(()),
    )
    is Err(Exhausted),
  )
  assert_eq(session.snapshot().committed_document_revision(), MAX_COUNTER)
  assert_eq(session.snapshot().published_revision(), 0UL)
  assert_eq(session.snapshot().delivery_watermark(), 0UL)
  assert_eq(session.snapshot().field().document().text(), "abc")
  assert_false(session.snapshot().field().is_composing())
}

///|
test "pending nonce rejects a same target forged completion before providers" {
  let session = private_owner()
  let pending = session.request_end(session.target().unwrap(), Blur).unwrap()
  let forged = { ..pending, identity: identity(), }
  let calls = [0]
  assert_true(
    session.complete_blur(
      forged,
      ObservedEnd::Cancelled,
      fn(document) {
        calls[0] += 1
        private_measure(document)
      },
      (_, _) => Ok(()),
    )
    is Err(InvalidPending),
  )
  assert_eq(calls[0], 0)
  assert_true(session.snapshot().has_pending_end())
  let _ = session
    .complete_blur(pending, ObservedEnd::Cancelled, private_measure, (_, _) => {
      Ok(())
    })
    .unwrap()
}

///|
test "publication incarnation recheck rejects invalidation even without guard poison" {
  let session = private_owner()
  let before = session.state.val
  let target = session.target().unwrap()
  let result = session.apply_batch(
    target,
    [PreviewUtf8("X", 1, 1)],
    fn(document) {
      // White-box fault injection exercises the final publication fence. Public
      // lifecycle methods cannot do this: they reject through the shared guard.
      session.state.val = { ..session.state.val, publication: identity(), }
      private_measure(document)
    },
    (_, _) => Ok(()),
  )
  assert_true(result is Err(Reentrant))
  assert_eq(session.snapshot().published_revision(), before.revision)
  assert_eq(session.snapshot().delivery_watermark(), before.sequence)
  assert_eq(session.snapshot().field().document().text(), "abc")
}

///|
test "end session and revision exhaustion preserves pending authority before providers" {
  for counter in [0, 1] {
    let session = private_owner()
    let pending = session.request_end(session.target().unwrap(), Blur).unwrap()
    session.state.val = if counter == 0 {
      { ..session.state.val, session: MAX_COUNTER, }
    } else {
      { ..session.state.val, revision: MAX_COUNTER, }
    }
    // Keep the synthetic private pending target current so the test reaches
    // overflow validation instead of (correctly) failing the freshness check.
    let target = capture_target(session.state.val).unwrap()
    let pending = { ..pending, target, }
    session.state.val = { ..session.state.val, pending: Some(pending), }
    let calls = [0]
    assert_true(
      session.complete_blur(
        pending,
        ObservedEnd::Cancelled,
        fn(document) {
          calls[0] += 1
          private_measure(document)
        },
        (_, _) => Ok(()),
      )
      is Err(Exhausted),
    )
    assert_eq(calls[0], 0)
    assert_true(session.snapshot().has_pending_end())
    assert_true(session.snapshot().field().is_focused())
    assert_eq(session.snapshot().delivery_watermark(), 0UL)
  }
}

///|
test "exact receipt rejects every independently changed identity and counter" {
  let session = private_owner()
  let target = session.target().unwrap()
  let receipt = session
    .apply_batch(target, [PreviewUtf8("X", 1, 1)], private_measure, (_, _) => {
      Ok(())
    })
    .unwrap()
  assert_true(receipt.acknowledges(target))
  for
    other in [
      { ..target, owner: identity(), },
      { ..target, window_instance: identity(), },
      { ..target, root_instance: identity(), },
      { ..target, field_instance: identity(), },
      { ..target, window: @platform.WindowId::new(2L), },
      { ..target, root_id: 8UL, },
      { ..target, field_id: 20UL, },
      { ..target, session: 2UL, },
      { ..target, revision: 1UL, },
      { ..target, sequence: 2UL, },
    ] {
    assert_false(receipt.acknowledges(other))
  }
}

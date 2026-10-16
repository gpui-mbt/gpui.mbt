///|
// Bounded source/API contracts. Dynamic bindings, predicates and shared_handlees are
// tested here; they are not claims established by the upstream example video.
fn session_tree() -> @element.ElementTree {
  unwrap_tree([
    @element.ElementNode::new(1, None, element_rect(0, 0, 200, 100)),
    @element.ElementNode::new(2, Some(1), element_rect(0, 0, 50, 50)),
    @element.ElementNode::new(3, Some(1), element_rect(100, 0, 80, 80)),
    @element.ElementNode::new(4, Some(3), element_rect(120, 20, 40, 40)),
  ])
}

///|
fn session_down(
  x : Double,
  y : Double,
  button~ : @primitives.MouseButton = @primitives.Primary,
) -> @primitives.InputEvent {
  @primitives.PointerButtonPressed(
    position=element_point(x, y),
    button~,
    modifiers=@primitives.Modifiers::none(),
  )
}

///|
fn session_move(x : Double, y : Double) -> @primitives.InputEvent {
  @primitives.PointerMoved(position=element_point(x, y))
}

///|
fn session_up(
  x : Double,
  y : Double,
  button~ : @primitives.MouseButton = @primitives.Primary,
) -> @primitives.InputEvent {
  @primitives.PointerButtonReleased(
    position=element_point(x, y),
    button~,
    modifiers=@primitives.Modifiers::none(),
  )
}

///|
fn[T] session_ok(
  result : Result[@element.DragDispatchOutcome[T], @element.DragDispatchError],
) -> @element.DragDispatchOutcome[T] {
  match result {
    Ok(value) => value
    Err(_) => abort("valid session dispatch failed")
  }
}

///|
fn session_started(active : Bool) -> @element.DragSession[String] {
  let session = @element.DragSession::new()
  let sources = [@element.DragSource::new(2, "payload")]
  let _ = session_ok(
    session.dispatch(session_tree(), session_down(10, 10), sources, []),
  )
  if active {
    let _ = session_ok(
      session.dispatch(session_tree(), session_move(13, 10), sources, []),
    )
  }
  session
}

///|
test "session admits primary only on a registered current pointer route" {
  let tree = session_tree()
  let session : @element.DragSession[String] = @element.DragSession::new()
  let sources = [@element.DragSource::new(2, "value")]
  for
    event in [
      session_move(10, 10),
      session_up(10, 10),
      session_down(-1, 0),
      session_down(70, 10),
      session_down(10, 10, button=@primitives.Secondary),
    ] {
    let outcome = session_ok(session.dispatch(tree, event, sources, []))
    assert_true(outcome is @element.Unchanged)
    assert_true(!outcome.state_changed() && !outcome.was_stopped())
    assert_true(session.snapshot() is @element.Idle)
  }
  assert_true(
    session_ok(session.dispatch(tree, session_down(10, 10), [], []))
    is @element.Unchanged,
  )
  let admitted = session_ok(
    session.dispatch(tree, session_down(10, 10), sources, []),
  )
  assert_true(admitted is @element.Admitted)
  assert_true(admitted.state_changed() && !admitted.was_stopped())
  assert_true(
    session.snapshot() is @element.Pending(source=2, origin~) &&
    origin == element_point(10, 10),
  )
}

///|
test "session strict threshold stays pending at zero one and two and activates beyond" {
  let tree = session_tree()
  let sources = [@element.DragSource::new(2, "value")]
  for
    point in [
      element_point(10, 10),
      element_point(11, 10),
      element_point(12, 10),
      element_point(8, 10),
      element_point(10, 12),
      element_point(10, 8),
      element_point(11, 11),
    ] {
    let session = session_started(false)
    let before = session.snapshot()
    let outcome = session_ok(
      session.dispatch(
        tree,
        @primitives.PointerMoved(position=point),
        sources,
        [],
      ),
    )
    assert_true(outcome is @element.Unchanged)
    assert_true(session.snapshot() == before)
  }
  for
    point in [
      element_point(12.00001, 10),
      element_point(7.99999, 10),
      element_point(10, 12.00001),
      element_point(10, 7.99999),
      element_point(11.5, 11.5),
      element_point(8.5, 8.5),
    ] {
    let session = session_started(false)
    let outcome = session_ok(
      session.dispatch(
        tree,
        @primitives.PointerMoved(position=point),
        sources,
        [],
      ),
    )
    assert_true(outcome is @element.Activated)
    assert_true(outcome.state_changed() && outcome.was_stopped())
    assert_true(
      session.snapshot() is @element.Active(position~, ..) && position == point,
    )
  }
}

///|
test "session release never activates and every released button clears" {
  for
    button in [
      @primitives.Primary,
      @primitives.Secondary,
      @primitives.Middle,
      @primitives.Back,
      @primitives.Forward,
    ] {
    let session = session_started(false)
    let outcome = session_ok(
      session.dispatch(
        session_tree(),
        session_up(130, 30, button~),
        [@element.DragSource::new(2, "late")],
        [@element.DropTarget::new(4)],
      ),
    )
    assert_true(outcome is @element.Cancelled)
    assert_true(!outcome.was_stopped())
    assert_true(session.snapshot() is @element.Idle)
    let active = session_started(true)
    assert_true(
      session_ok(
        active.dispatch(session_tree(), session_up(130, 30, button~), [], [
          @element.DropTarget::new(4),
        ]),
      )
      is @element.Dropped(4, "payload"),
    )
    assert_true(active.snapshot() is @element.Idle)
  }
}

///|
test "session active stays active at origin and ignores repeated primary secondary down" {
  let tree = session_tree()
  let sources = [
    @element.DragSource::new(2, "new"),
    @element.DragSource::new(3, "other"),
  ]
  for active in [false, true] {
    let session = session_started(active)
    let before = session.snapshot()
    for button in [@primitives.Primary, @primitives.Secondary] {
      assert_true(
        session_ok(
          session.dispatch(tree, session_down(110, 10, button~), sources, []),
        )
        is @element.Unchanged,
      )
      assert_true(session.snapshot() == before)
    }
  }
  let session = session_started(true)
  let moved = session_ok(session.dispatch(tree, session_move(10, 10), [], []))
  assert_true(moved is @element.Moved)
  assert_true(moved.state_changed() && !moved.was_stopped())
  assert_true(
    session.snapshot()
    is @element.Active(source=2, position~, payload="payload", ..) &&
    position == element_point(10, 10),
  )
  assert_true(
    session_ok(session.dispatch(tree, session_move(10, 10), [], []))
    is @element.Unchanged,
  )
}

///|
test "session resolves current activation value and bounds then freezes them" {
  let session : @element.DragSession[String] = @element.DragSession::new()
  let _ = session_ok(
    session.dispatch(
      session_tree(),
      session_down(10, 10),
      [@element.DragSource::new(2, "A")],
      [],
    ),
  )
  let changed = unwrap_tree([
    @element.ElementNode::new(1, None, element_rect(0, 0, 200, 100)),
    @element.ElementNode::new(2, Some(1), element_rect(5, 7, 40, 40)).with_pointer_events(
      false,
    ),
    @element.ElementNode::new(3, Some(1), element_rect(100, 0, 80, 80)),
  ])
  assert_true(
    session_ok(
      session.dispatch(
        changed,
        session_move(14, 15),
        [@element.DragSource::new(2, "B")],
        [],
      ),
    )
    is @element.Activated,
  )
  let active = session.snapshot()
  assert_true(
    active
    is @element.Active(
      source=2,
      payload="B",
      origin~,
      position~,
      cursor_offset~
    ) &&
    origin == element_point(10, 10) &&
    position == element_point(14, 15) &&
    cursor_offset == element_point(9, 8),
  )
  let _ = session_ok(
    session.dispatch(
      session_tree(),
      session_move(130, 30),
      [@element.DragSource::new(2, "C")],
      [],
    ),
  )
  assert_true(
    session.snapshot() is @element.Active(payload="B", cursor_offset~, ..) &&
    cursor_offset == element_point(9, 8),
  )
  assert_true(
    session_ok(
      session.dispatch(
        session_tree(),
        session_up(130, 30),
        [@element.DragSource::new(2, "C")],
        [@element.DropTarget::new(4)],
      ),
    )
    is @element.Dropped(4, "B"),
  )
  assert_true(
    active is @element.Active(payload="B", position~, ..) &&
    position == element_point(14, 15),
  )
}

///|
struct SessionPayload {
  color : Int32
  logical_position : @primitives.Point
} derive(Eq)

///|
test "session typed payload is distinct from preview offset and pointer position" {
  let payload = SessionPayload::{
    color: 7,
    logical_position: element_point(900, 800),
  }
  let session : @element.DragSession[SessionPayload] = @element.DragSession::new()
  let sources = [@element.DragSource::new(2, payload)]
  let _ = session_ok(
    session.dispatch(session_tree(), session_down(6, 8), sources, []),
  )
  let _ = session_ok(
    session.dispatch(session_tree(), session_move(9, 8), sources, []),
  )
  assert_true(
    session.snapshot() is @element.Active(payload=retained, cursor_offset~, ..) &&
    retained == payload &&
    cursor_offset == element_point(9, 8),
  )
  let outcome = session_ok(
    session.dispatch(session_tree(), session_up(130, 30), [], [
      @element.DropTarget::new(4, can_drop=value => value.color == 7),
    ]),
  )
  assert_true(outcome is @element.Dropped(4, retained) && retained == payload)
}

///|
test "session pending missing binding stays pending and missing node cancels" {
  let session = session_started(false)
  let before = session.snapshot()
  assert_true(
    session_ok(session.dispatch(session_tree(), session_move(30, 30), [], []))
    is @element.Unchanged,
  )
  assert_true(session.snapshot() == before)
  assert_true(
    session_ok(
      session.dispatch(
        session_tree(),
        session_move(30, 30),
        [@element.DragSource::new(2, "late")],
        [],
      ),
    )
    is @element.Activated,
  )
  assert_true(session.snapshot() is @element.Active(payload="late", ..))
  let removed = match session_tree().without_subtree(2) {
    Ok(tree) => tree
    Err(_) => abort("remove failed")
  }
  let pending = session_started(false)
  let old = pending.snapshot()
  assert_true(
    pending.dispatch(
      removed,
      session_move(30, 30),
      [@element.DragSource::new(2, "stale")],
      [],
    )
    is Err(@element.UnknownSourceBinding(2)),
  )
  assert_true(pending.snapshot() == old)
  assert_true(
    session_ok(pending.dispatch(removed, session_move(30, 30), [], []))
    is @element.Cancelled,
  )
  assert_true(pending.snapshot() is @element.Idle)
  assert_true(
    session_ok(session.dispatch(removed, session_move(130, 30), [], []))
    is @element.Moved,
  )
  assert_true(
    session_ok(
      session.dispatch(removed, session_up(130, 30), [], [
        @element.DropTarget::new(4),
      ]),
    )
    is @element.Dropped(4, "late"),
  )
}

///|
test "session aliases share one shot consumption while detached snapshots and independent sessions do not" {
  let session = session_started(true)
  let shared_handle = session
  let old = session.snapshot()
  let independent = session_started(true)
  let targets = [@element.DropTarget::new(4)]
  let accepted = session_ok(
    shared_handle.dispatch(session_tree(), session_up(130, 30), [], targets),
  )
  assert_true(accepted is @element.Dropped(4, "payload"))
  assert_true(accepted.state_changed() && accepted.was_stopped())
  assert_true(session.snapshot() is @element.Idle)
  assert_true(
    session_ok(
      session.dispatch(session_tree(), session_up(130, 30), [], targets),
    )
    is @element.Unchanged,
  )
  assert_true(old is @element.Active(payload="payload", ..))
  assert_true(independent.snapshot() is @element.Active(..))
  assert_true(!session.cancel())
  assert_true(independent.cancel())
  assert_true(!independent.cancel())
  assert_true(independent.snapshot() is @element.Idle)
}

///|
test "session explicit lifecycle cancel prevents reused numeric ID from resuming old press" {
  let session = session_started(false)
  assert_true(session.cancel())
  let sources = [@element.DragSource::new(2, "replacement")]
  assert_true(
    session_ok(
      session.dispatch(session_tree(), session_move(30, 30), sources, []),
    )
    is @element.Unchanged,
  )
  let _ = session_ok(
    session.dispatch(session_tree(), session_down(10, 10), sources, []),
  )
  let _ = session_ok(
    session.dispatch(session_tree(), session_move(13, 10), sources, []),
  )
  assert_true(session.snapshot() is @element.Active(payload="replacement", ..))
}

///|
test "session target rejection consumes before predicate with no ancestor retry" {
  let session = session_started(true)
  let shared_handle = session
  let child_calls = Ref(0)
  let parent_calls = Ref(0)
  let saw_idle = Ref(false)
  let reentry_guarded = Ref(false)
  let targets = [
    @element.DropTarget::new(3, can_drop=_ => {
      parent_calls.val += 1
      true
    }),
    @element.DropTarget::new(4, can_drop=value => {
      child_calls.val += 1
      saw_idle.val = value == "payload" &&
        shared_handle.snapshot() is @element.Idle
      reentry_guarded.val = shared_handle.dispatch(
          session_tree(),
          session_down(10, 10),
          [@element.DragSource::new(2, "nested")],
          [],
        )
        is Err(@element.ReentrantDispatch)
      false
    }),
  ]
  let rejected = session_ok(
    session.dispatch(session_tree(), session_up(130, 30), [], targets),
  )
  assert_true(rejected is @element.Rejected(4))
  assert_true(rejected.state_changed() && !rejected.was_stopped())
  assert_true(saw_idle.val && reentry_guarded.val)
  assert_eq(child_calls.val, 1)
  assert_eq(parent_calls.val, 0)
  assert_true(session.snapshot() is @element.Idle)
  assert_true(
    session_ok(
      shared_handle.dispatch(session_tree(), session_up(130, 30), [], targets),
    )
    is @element.Unchanged,
  )
  assert_eq(child_calls.val, 1)
  assert_true(
    session_ok(
      shared_handle.dispatch(
        session_tree(),
        session_down(10, 10),
        [@element.DragSource::new(2, "after")],
        [],
      ),
    )
    is @element.Admitted,
  )
}

///|
test "session accepted predicate sees idle and cannot deliver or admit reentrantly" {
  let session = session_started(true)
  let saw_idle = Ref(false)
  let guarded = Ref(false)
  let targets = [
    @element.DropTarget::new(4, can_drop=_ => {
      saw_idle.val = session.snapshot() is @element.Idle
      guarded.val = session.dispatch(session_tree(), session_up(130, 30), [], [])
        is Err(@element.ReentrantDispatch)
      true
    }),
  ]
  assert_true(
    session_ok(
      session.dispatch(session_tree(), session_up(130, 30), [], targets),
    )
    is @element.Dropped(4, "payload"),
  )
  assert_true(saw_idle.val && guarded.val)
  assert_true(session.snapshot() is @element.Idle)
}

///|
test "session routing skips unregistered child but not a matched rejecting child" {
  let tree = session_tree()
  let session = session_started(true)
  assert_true(
    session_ok(
      session.dispatch(tree, session_up(130, 30), [], [
        @element.DropTarget::new(3),
      ]),
    )
    is @element.Dropped(3, "payload"),
  )
  let source : @element.DragSession[String] = @element.DragSession::new()
  assert_true(
    session_ok(
      source.dispatch(
        tree,
        session_down(130, 30),
        [@element.DragSource::new(3, "ancestor")],
        [],
      ),
    )
    is @element.Admitted,
  )
  assert_true(source.snapshot() is @element.Pending(source=3, ..))
}

///|
test "session uses topmost route and ignores disabled preview hitboxes" {
  let tree = unwrap_tree([
    @element.ElementNode::new(1, None, element_rect(0, 0, 200, 100)),
    @element.ElementNode::new(2, Some(1), element_rect(0, 0, 50, 50)),
    @element.ElementNode::new(3, Some(1), element_rect(100, 0, 80, 80)),
    @element.ElementNode::new(4, Some(1), element_rect(100, 0, 80, 80)),
    @element.ElementNode::new(5, Some(1), element_rect(0, 0, 200, 100)).with_pointer_events(
      false,
    ),
  ])
  let covered = session_started(true)
  assert_true(
    session_ok(
      covered.dispatch(tree, session_up(130, 30), [], [
        @element.DropTarget::new(3),
      ]),
    )
    is @element.Cancelled,
  )
  let top = session_started(true)
  assert_true(
    session_ok(
      top.dispatch(tree, session_up(130, 30), [], [
        @element.DropTarget::new(3),
        @element.DropTarget::new(4),
        @element.DropTarget::new(5),
      ]),
    )
    is @element.Dropped(4, "payload"),
  )
}

///|
test "session ancestors require own enabled bounds even when child extends outside" {
  for enabled in [true, false] {
    let tree = unwrap_tree([
      @element.ElementNode::new(1, None, element_rect(0, 0, 200, 100)),
      @element.ElementNode::new(2, Some(1), element_rect(0, 0, 50, 50)),
      @element.ElementNode::new(3, Some(1), element_rect(100, 0, 10, 10)).with_pointer_events(
        enabled,
      ),
      @element.ElementNode::new(4, Some(3), element_rect(100, 0, 80, 80)),
    ])
    let outside = session_started(true)
    assert_true(
      session_ok(
        outside.dispatch(tree, session_up(130, 30), [], [
          @element.DropTarget::new(3),
        ]),
      )
      is @element.Cancelled,
    )
    let source : @element.DragSession[String] = @element.DragSession::new()
    assert_true(
      session_ok(
        source.dispatch(
          tree,
          session_down(130, 30),
          [@element.DragSource::new(3, "ancestor")],
          [],
        ),
      )
      is @element.Unchanged,
    )
    if !enabled {
      assert_true(
        session_ok(
          source.dispatch(
            tree,
            session_down(105, 5),
            [@element.DragSource::new(3, "disabled")],
            [],
          ),
        )
        is @element.Unchanged,
      )
      let disabled = session_started(true)
      assert_true(
        session_ok(
          disabled.dispatch(tree, session_up(105, 5), [], [
            @element.DropTarget::new(3),
          ]),
        )
        is @element.Cancelled,
      )
    }
  }
}

///|
test "session pointer bounds are half open and outside release clears" {
  for point in [element_point(100, 0), element_point(179.999, 79.999)] {
    let session = session_started(true)
    assert_true(
      session_ok(
        session.dispatch(
          session_tree(),
          @primitives.PointerButtonReleased(
            position=point,
            button=@primitives.Primary,
            modifiers=@primitives.Modifiers::none(),
          ),
          [],
          [@element.DropTarget::new(3)],
        ),
      )
      is @element.Dropped(3, "payload"),
    )
  }
  for
    point in [
      element_point(180, 40),
      element_point(150, 80),
      element_point(99.999, 40),
      element_point(150, -0.001),
      element_point(500, 500),
    ] {
    let session = session_started(true)
    assert_true(
      session_ok(
        session.dispatch(
          session_tree(),
          @primitives.PointerButtonReleased(
            position=point,
            button=@primitives.Primary,
            modifiers=@primitives.Modifiers::none(),
          ),
          [],
          [@element.DropTarget::new(3)],
        ),
      )
      is @element.Cancelled,
    )
    assert_true(session.snapshot() is @element.Idle)
  }
  for event in [session_down(50, 10), session_down(10, 50)] {
    let session : @element.DragSession[String] = @element.DragSession::new()
    assert_true(
      session_ok(
        session.dispatch(
          session_tree(),
          event,
          [@element.DragSource::new(2, "edge")],
          [],
        ),
      )
      is @element.Unchanged,
    )
  }
}

///|
test "session admission and drop obey all ancestor scroll clips" {
  let tree = viewport_prepaint(viewport_nested(20, 30, 10), 100, 100).tree()
  let sources = [@element.DragSource::new(5, "clipped")]
  for
    point in [
      element_point(80, 30),
      element_point(10, 70),
      element_point(-0.001, 30),
      element_point(10, 100),
    ] {
    let session : @element.DragSession[String] = @element.DragSession::new()
    assert_true(
      session_ok(
        session.dispatch(
          tree,
          @primitives.PointerButtonPressed(
            position=point,
            button=@primitives.Primary,
            modifiers=@primitives.Modifiers::none(),
          ),
          sources,
          [],
        ),
      )
      is @element.Unchanged,
    )
    let active = session_started(true)
    assert_true(
      session_ok(
        active.dispatch(
          tree,
          @primitives.PointerButtonReleased(
            position=point,
            button=@primitives.Primary,
            modifiers=@primitives.Modifiers::none(),
          ),
          [],
          [@element.DropTarget::new(5)],
        ),
      )
      is @element.Cancelled,
    )
  }
  let session : @element.DragSession[String] = @element.DragSession::new()
  assert_true(
    session_ok(session.dispatch(tree, session_down(0, 20), sources, []))
    is @element.Admitted,
  )
  let _ = session_ok(session.dispatch(tree, session_move(3, 20), sources, []))
  assert_true(
    session_ok(
      session.dispatch(tree, session_up(79.999, 69.999), sources, [
        @element.DropTarget::new(5),
      ]),
    )
    is @element.Dropped(5, "clipped"),
  )
}

///|
test "session validates entire registries atomically in idle pending and active" {
  let calls = Ref(0)
  let valid_target = @element.DropTarget::new(4, can_drop=_ => {
    calls.val += 1
    true
  })
  for phase in [0, 1, 2] {
    let session : @element.DragSession[String] = if phase == 0 {
      @element.DragSession::new()
    } else {
      session_started(phase == 2)
    }
    let shared_handle = session
    let before = session.snapshot()
    let bad_sources = [
      [@element.DragSource::new(2, "A"), @element.DragSource::new(2, "B")],
      [
        @element.DragSource::new(2, "A"),
        @element.DragSource::new(999, "off route"),
      ],
    ]
    for sources in bad_sources {
      let result = session.dispatch(
        session_tree(),
        session_up(130, 30),
        sources,
        [valid_target],
      )
      assert_true(
        result is Err(@element.DuplicateSourceBinding(2)) ||
        result is Err(@element.UnknownSourceBinding(999)),
      )
      assert_true(
        session.snapshot() == before && shared_handle.snapshot() == before,
      )
      assert_eq(calls.val, 0)
    }
    for
      targets in [
        [valid_target, @element.DropTarget::new(4)],
        [valid_target, @element.DropTarget::new(999)],
      ] {
      let result = session.dispatch(
        session_tree(),
        session_up(130, 30),
        [],
        targets,
      )
      assert_true(
        result is Err(@element.DuplicateTargetBinding(4)) ||
        result is Err(@element.UnknownTargetBinding(999)),
      )
      assert_true(
        session.snapshot() == before && shared_handle.snapshot() == before,
      )
      assert_eq(calls.val, 0)
    }
    for event in [session_down(10, 10), session_move(50, 50)] {
      assert_true(
        session.dispatch(session_tree(), event, [], [
          @element.DropTarget::new(999),
        ])
        is Err(@element.UnknownTargetBinding(999)),
      )
      assert_true(session.snapshot() == before)
    }
  }
}

///|
test "session malformed release retains active state until corrected retry or explicit cancel" {
  let session = session_started(true)
  let before = session.snapshot()
  assert_true(
    session.dispatch(session_tree(), session_up(130, 30), [], [
      @element.DropTarget::new(999),
    ])
    is Err(@element.UnknownTargetBinding(999)),
  )
  assert_true(session.snapshot() == before)
  assert_true(
    session_ok(
      session.dispatch(session_tree(), session_up(130, 30), [], [
        @element.DropTarget::new(4),
      ]),
    )
    is @element.Dropped(4, "payload"),
  )
  let second = session_started(true)
  assert_true(
    second.dispatch(session_tree(), session_up(130, 30), [], [
      @element.DropTarget::new(999),
    ])
    is Err(@element.UnknownTargetBinding(999)),
  )
  assert_true(second.cancel())
  assert_true(second.snapshot() is @element.Idle)
}

///|
test "session permits same ID across lists and live disabled zero area bindings" {
  let tree = unwrap_tree([
    @element.ElementNode::new(1, None, element_rect(0, 0, 100, 100)),
    @element.ElementNode::new(2, Some(1), element_rect(0, 0, 50, 50)),
    @element.ElementNode::new(3, Some(1), element_rect(0, 0, 0, 0)).with_pointer_events(
      false,
    ),
  ])
  let session : @element.DragSession[String] = @element.DragSession::new()
  let sources = [
    @element.DragSource::new(2, "both"),
    @element.DragSource::new(3, "zero"),
  ]
  let targets = [@element.DropTarget::new(2), @element.DropTarget::new(3)]
  assert_true(
    session_ok(session.dispatch(tree, session_down(10, 10), sources, targets))
    is @element.Admitted,
  )
  assert_true(
    session_ok(session.dispatch(tree, session_move(13, 10), sources, targets))
    is @element.Activated,
  )
  assert_true(
    session_ok(session.dispatch(tree, session_up(13, 10), sources, targets))
    is @element.Dropped(2, "both"),
  )
}

///|
test "session exact cursor offset overflow on either axis is atomic and retryable" {
  for vertical in [false, true] {
    let session = session_started(false)
    let shared_handle = session
    let before = session.snapshot()
    let bound = if vertical {
      element_rect(0, -1.0e308, 50, 1.0e307)
    } else {
      element_rect(-1.0e308, 0, 1.0e307, 50)
    }
    let tree = unwrap_tree([@element.ElementNode::new(2, None, bound)])
    let point = if vertical {
      element_point(10, 1.0e308)
    } else {
      element_point(1.0e308, 10)
    }
    assert_true(
      session.dispatch(
        tree,
        @primitives.PointerMoved(position=point),
        [@element.DragSource::new(2, "overflow")],
        [],
      )
      is Err(@element.CursorOffsetOverflow(2)),
    )
    assert_true(
      session.snapshot() == before && shared_handle.snapshot() == before,
    )
    assert_true(
      session_ok(
        session.dispatch(
          session_tree(),
          session_move(13, 10),
          [@element.DragSource::new(2, "retry")],
          [],
        ),
      )
      is @element.Activated,
    )
    assert_true(
      session.snapshot()
      is @element.Active(payload="retry", position~, cursor_offset~, ..) &&
      position == element_point(13, 10) &&
      cursor_offset == element_point(13, 10),
    )
  }
}

///|
test "session finite extreme threshold classification retains only exact representable offsets" {
  let tree = unwrap_tree([
    @element.ElementNode::new(
      2,
      None,
      element_rect(-1.0e308, -1.0e308, 1.0e307, 1.0e307),
    ),
  ])
  let sources = [@element.DragSource::new(2, "extreme")]
  let session : @element.DragSession[String] = @element.DragSession::new()
  let _ = session_ok(
    session.dispatch(tree, session_down(-1.0e308, -1.0e308), sources, []),
  )
  let before = session.snapshot()
  assert_true(
    session.dispatch(tree, session_move(1.0e308, 1.0e308), sources, [])
    is Err(@element.CursorOffsetOverflow(2)),
  )
  assert_true(session.snapshot() == before)
  assert_true(
    session_ok(session.dispatch(tree, session_move(0, 0), sources, []))
    is @element.Activated,
  )
  assert_true(
    session.snapshot() is @element.Active(cursor_offset~, ..) &&
    cursor_offset == element_point(1.0e308, 1.0e308),
  )
  let _ = session_ok(
    session.dispatch(
      tree,
      session_move(@double.max_value, @double.max_value),
      [],
      [],
    ),
  )
  assert_true(
    session.snapshot() is @element.Active(position~, cursor_offset~, ..) &&
    position == element_point(@double.max_value, @double.max_value) &&
    cursor_offset == element_point(1.0e308, 1.0e308),
  )
}

///|
test "session snapshots retain shallow typed references without sharing session state" {
  let payload = Ref(7)
  let session : @element.DragSession[Ref[Int32]] = @element.DragSession::new()
  let sources = [@element.DragSource::new(2, payload)]
  let _ = session_ok(
    session.dispatch(session_tree(), session_down(10, 10), sources, []),
  )
  let _ = session_ok(
    session.dispatch(session_tree(), session_move(13, 10), sources, []),
  )
  let snapshot = session.snapshot()
  payload.val = 8
  assert_true(
    snapshot is @element.Active(payload=retained, ..) && retained.val == 8,
  )
  assert_true(session.cancel())
  assert_true(session.snapshot() is @element.Idle)
  assert_true(
    snapshot is @element.Active(payload=retained, ..) && retained.val == 8,
  )
}

///|
test "session structurally snapshots bindings and validates before any predicate" {
  let session = session_started(true)
  let sources = [@element.DragSource::new(2, "current")]
  let targets : Array[@element.DropTarget[String]] = []
  targets.push(
    @element.DropTarget::new(4, can_drop=_ => {
      sources[0] = @element.DragSource::new(999, "mutated")
      targets.clear()
      true
    }),
  )
  assert_true(
    session_ok(
      session.dispatch(session_tree(), session_up(130, 30), sources, targets),
    )
    is @element.Dropped(4, "payload"),
  )
  assert_true(session.snapshot() is @element.Idle)
  assert_eq(targets.length(), 0)
}

///|
test "session keyboard scroll and Escape do not invent cancellation or activation" {
  let session = session_started(false)
  let before = session.snapshot()
  let events = [
    @primitives.KeyPressed(
      key=@primitives.Escape,
      modifiers=@primitives.Modifiers::none(),
      repeat=false,
    ),
    @primitives.KeyReleased(
      key=@primitives.Escape,
      modifiers=@primitives.Modifiers::none(),
    ),
    @primitives.TextInput(text="text"),
    @primitives.Scroll(
      position=element_point(130, 30),
      delta=element_point(10, 10),
      modifiers=@primitives.Modifiers::none(),
    ),
  ]
  for event in events {
    assert_true(
      session_ok(session.dispatch(session_tree(), event, [], []))
      is @element.Unchanged,
    )
    assert_true(session.snapshot() == before)
  }
}

///|
test "session registry errors are deterministic and current payload arrays do not freeze on press" {
  let session : @element.DragSession[String] = @element.DragSession::new()
  let tree = session_tree()
  assert_true(
    session.dispatch(
      tree,
      session_down(10, 10),
      [@element.DragSource::new(2, "A"), @element.DragSource::new(2, "B")],
      [],
    )
    is Err(@element.DuplicateSourceBinding(2)),
  )
  assert_true(
    session.dispatch(
      tree,
      session_down(10, 10),
      [@element.DragSource::new(999, "unknown")],
      [],
    )
    is Err(@element.UnknownSourceBinding(999)),
  )
  assert_true(
    session.dispatch(tree, session_down(10, 10), [], [
      @element.DropTarget::new(3),
      @element.DropTarget::new(3),
    ])
    is Err(@element.DuplicateTargetBinding(3)),
  )
  assert_true(
    session.dispatch(tree, session_down(10, 10), [], [
      @element.DropTarget::new(999),
    ])
    is Err(@element.UnknownTargetBinding(999)),
  )
  let sources = [@element.DragSource::new(2, "A")]
  let _ = session_ok(session.dispatch(tree, session_down(10, 10), sources, []))
  sources[0] = @element.DragSource::new(2, "B")
  let _ = session_ok(session.dispatch(tree, session_move(13, 10), sources, []))
  sources[0] = @element.DragSource::new(2, "C")
  assert_true(
    session_ok(
      session.dispatch(tree, session_up(130, 30), sources, [
        @element.DropTarget::new(4),
      ]),
    )
    is @element.Dropped(4, "B"),
  )
}

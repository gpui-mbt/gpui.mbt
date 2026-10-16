///|
test "all 29 measured inputs agree with the published upstream coordinates" {
  assert_eq(presets.length(), 29)
  for preset in presets {
    assert_true(
      delta(bounds(resolve(preset.config)), preset.upstream) <= 0.0001,
    )
  }
}

///|
test "capped grow and minimum shrink retain the measured before-fix differences" {
  let grow = presets[0]
  assert_eq(grow.before[2][2], 50.0)
  assert_eq(bounds(resolve(grow.config))[2][2], 70.0)
  let shrink = presets[13]
  assert_eq(shrink.before[2][2], 20.0)
  assert_eq(bounds(resolve(shrink.config))[2][2], 10.0)
}

///|
test "edits do not mutate a preset and reset restores comparison eligibility" {
  let model = Playground::new()
  assert_true(model.change("grow", 1, 2.0))
  assert_true(model.config != presets[0].config)
  assert_eq(presets[0].config.children[1].grow, 1.0)
  assert_true(model.select(0))
  assert_true(model.config == presets[0].config)
}

///|
test "invalid or reversed edits leave the last valid state intact" {
  let model = Playground::new()
  let initial = model.snapshot()
  for
    (field, index, value) in [
      ("minimum", 0, 31.0),
      ("grow", 2, 1.0),
      ("grow", -1, 1.0),
      ("extent", -1, 0.0),
      ("gap", -1, -1.0),
      ("basis", 0, 201.0),
      ("grow", 0, 5.0),
      ("shrink", 0, 0.0 / 0.0),
      ("gap", -1, 1.0 / 0.0),
      ("direction", -1, 0.5),
      ("justify", -1, 4.0),
      ("wrap", -1, 3.0),
      ("cross", -1, 0.0),
      ("cross", -1, 101.0),
      ("unknown", 0, 1.0),
    ] {
    assert_true(!model.change(field, index, value))
    assert_eq(model.snapshot(), initial)
  }
  assert_true(!model.select(-1))
  assert_true(!model.select(29 + projected_presets.length()))
  assert_eq(model.snapshot(), initial)
}

///|
test "gap direction and zero max change actual engine geometry" {
  let model = Playground::new()
  assert_true(model.change("gap", -1, 8.0))
  assert_eq(bounds(resolve(model.config))[2][0], 38.0)
  assert_true(model.change("direction", -1, 1.0))
  assert_eq(bounds(resolve(model.config))[2][1], 38.0)
  assert_true(model.change("maximum", 0, 0.0))
  assert_eq(bounds(resolve(model.config))[1][3], 0.0)
  assert_true(model.change("maximum", 0, -1.0))
  assert_eq(bounds(resolve(model.config))[1][3], 46.0)
}

///|
test "space-between uses saved main origins and invalidates on edit" {
  for i in [0, 1, 2] {
    let record = projected_presets[i]
    let model = Playground::new()
    assert_true(model.select(presets.length() + i))
    let measured = projected_origins(
      bounds(resolve(model.config)),
      model.config.column,
      record.projection,
    )
    assert_true(origin_delta(measured, record.recorded) <= 0.0001)
    assert_true(model.snapshot().contains("\"status\":\"match\""))
    assert_true(model.change("gap", -1, 9.0))
    assert_true(model.snapshot().contains("\"status\":\"unmeasured\""))
    assert_true(model.change("gap", -1, 8.0))
    assert_true(model.snapshot().contains("\"status\":\"match\""))
  }
}

///|
test "wrap projections do not claim all bounds are measured" {
  for i in [3, 4] {
    let record = projected_presets[i]
    let model = Playground::new()
    assert_true(model.select(presets.length() + i))
    assert_true(origin_delta(
      projected_origins(bounds(resolve(model.config)), model.config.column, 1),
      record.recorded,
    ) <= 0.0001)
    assert_true(model.snapshot().contains("\"projection\":\"line-origins\""))
    assert_true(model.snapshot().contains("\"status\":\"match\""))
    assert_true(model.change("wrap", -1, 2.0))
    assert_true(model.snapshot().contains("\"status\":\"unmeasured\""))
    let reversed = bounds(resolve(model.config))
    assert_true(reversed[1][1] > reversed[2][1])
    assert_true(model.change("wrap", -1, 1.0))
    assert_true(model.snapshot().contains("\"status\":\"match\""))
  }
}

///|
test "cross extent and wrap modes reach the real two-child layout engine" {
  let model = Playground::new()
  assert_true(model.change("grow", 0, 0.0))
  assert_true(model.change("grow", 1, 0.0))
  assert_true(model.change("basis", 0, 30.0))
  assert_true(model.change("basis", 1, 30.0))
  assert_true(model.change("extent", -1, 50.0))
  assert_true(model.change("cross", -1, 30.0))
  assert_true(model.change("gap", -1, 8.0))
  assert_true(model.change("wrap", -1, 1.0))
  let wrapped = bounds(resolve(model.config))
  assert_eq(wrapped[2][0], 0.0)
  assert_true(wrapped[2][1] > wrapped[1][1])
  assert_true(model.change("wrap", -1, 2.0))
  let reverse = bounds(resolve(model.config))
  assert_true(reverse[1][1] > reverse[2][1])
  assert_true(model.change("wrap", -1, 0.0))
  let flat = bounds(resolve(model.config))
  assert_eq(flat[2][1], 0.0)
}

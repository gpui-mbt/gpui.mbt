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
      ("justify", -1, 3.0),
      ("unknown", 0, 1.0),
    ] {
    assert_true(!model.change(field, index, value))
    assert_eq(model.snapshot(), initial)
  }
  assert_true(!model.select(-1))
  assert_true(!model.select(29))
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

///|
test "device distributed compatibility guards preserve raw large and fallback paths" {
  assert_eq(
    device_distributed_starts([12.0], 142, 14, 6, SpaceAround, true),
    None,
  )
  assert_eq(
    device_distributed_starts([12.0, 20.0], 38, 14, 6, SpaceAround, true),
    None,
  )
  assert_eq(
    device_distributed_starts([12.0, 20.0], 30, 14, 6, SpaceAround, true),
    None,
  )
  assert_eq(
    device_distributed_starts([12.0, 20.0], 142, 14, 6, Center, true),
    None,
  )
  assert_eq(
    device_distributed_starts([12.0, 20.0], 1.0e200, 14, 6, SpaceAround, true),
    None,
  )
  assert_eq(
    device_distributed_starts([12.0, 20.0], 142, 1.0e200, 6, SpaceAround, true),
    None,
  )
  assert_eq(
    device_distributed_starts([12.0, 20.0], 142, 14, 1.0e200, SpaceAround, true),
    None,
  )
  assert_eq(
    device_distributed_starts([12.0, 1.0e200], 142, 14, 6, SpaceAround, true),
    None,
  )
  assert_eq(
    device_distributed_starts(
      [16777216.0, 1],
      16777216,
      0,
      6,
      SpaceAround,
      true,
    ),
    None,
  )
}

///|
test "distributed compatibility falls back when f32 far edge snaps differently" {
  assert_eq(
    device_distributed_starts(
      [3.0, 5, 20, 10, 0, 10, 1],
      82,
      2,
      1,
      SpaceAround,
      true,
    ),
    None,
  )
}

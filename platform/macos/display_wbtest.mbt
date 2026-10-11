///|
fn valid_display_records() -> FixedArray[Double] {
  let records = FixedArray::make(
    DISPLAY_SNAPSHOT_CAPACITY * DISPLAY_INFO_FIELDS,
    0.0,
  )
  records[0] = -1440.0
  records[1] = 0.0
  records[2] = 1440.0
  records[3] = 900.0
  records[4] = -1440.0
  records[5] = 23.0
  records[6] = 1440.0
  records[7] = 877.0
  records[8] = 2.0
  records[9] = 2880.0
  records[10] = 1800.0
  records[11] = 59.94
  records[12] = 1.0
  records[13] = 1.0
  records
}

///|
test "macOS display snapshots decode copied screen and mode metadata" {
  let records = valid_display_records()
  let displays = match decode_display_snapshot(records, 1) {
    Ok(value) => value
    Err(_) => fail("valid display metadata rejected")
  }
  assert_eq(displays.length(), 1)
  assert_eq(displays[0].frame_x_points, -1440.0)
  assert_eq(displays[0].frame_width_points, 1440.0)
  assert_eq(displays[0].visible_y_points, 23.0)
  assert_eq(displays[0].backing_scale_factor, 2.0)
  assert_eq(displays[0].mode_width_px, 2880)
  assert_eq(displays[0].mode_height_px, 1800)
  assert_eq(displays[0].refresh_rate_hz, Some(59.94))
  assert_true(displays[0].is_primary && displays[0].is_window_monitor)

  records[11] = 0.0
  assert_eq(displays[0].refresh_rate_hz, Some(59.94))
  let updated = match decode_display_snapshot(records, 1) {
    Ok(value) => value
    Err(_) => fail("unreported refresh rate rejected")
  }
  assert_eq(updated[0].refresh_rate_hz, None)
  assert_eq(
    match decode_display_snapshot(records, 0) {
      Ok(value) => value.length()
      Err(_) => fail("empty display list rejected")
    },
    0,
  )
}

///|
test "macOS display snapshot decoder rejects malformed records and flags" {
  let fractional_mode = valid_display_records()
  fractional_mode[9] = 2880.5
  match decode_display_snapshot(fractional_mode, 1) {
    Err(error) => {
      assert_eq(error.code().label(), "conversion_failed")
      assert_eq(error.subsystem(), Some("display"))
    }
    Ok(_) => fail("fractional pixel mode accepted")
  }

  let invalid_scale = valid_display_records()
  invalid_scale[8] = 0.0
  assert_true(decode_display_snapshot(invalid_scale, 1) is Err(_))

  let unavailable_dimensions = valid_display_records()
  unavailable_dimensions[10] = 0.0
  assert_true(decode_display_snapshot(unavailable_dimensions, 1) is Err(_))

  let invalid_refresh = valid_display_records()
  invalid_refresh[11] = -1.0
  assert_true(decode_display_snapshot(invalid_refresh, 1) is Err(_))

  let non_boolean = valid_display_records()
  non_boolean[12] = 2.0
  assert_true(decode_display_snapshot(non_boolean, 1) is Err(_))

  let duplicate_primary = valid_display_records()
  for field = 0; field < DISPLAY_INFO_FIELDS; field = field + 1 {
    duplicate_primary[DISPLAY_INFO_FIELDS + field] = duplicate_primary[field]
  }
  match decode_display_snapshot(duplicate_primary, 2) {
    Err(error) => assert_eq(error.code().label(), "conversion_failed")
    Ok(_) => fail("duplicate primary display accepted")
  }

  match decode_display_snapshot(FixedArray::make(DISPLAY_INFO_FIELDS, 0.0), 0) {
    Err(error) => assert_eq(error.code().label(), "conversion_failed")
    Ok(_) => fail("incorrect record-buffer length accepted")
  }
  match
    decode_display_snapshot(
      FixedArray::make(DISPLAY_SNAPSHOT_CAPACITY * DISPLAY_INFO_FIELDS, 0.0),
      DISPLAY_SNAPSHOT_CAPACITY + 1,
    ) {
    Err(error) => assert_eq(error.code().label(), "conversion_failed")
    Ok(_) => fail("display count overflow accepted")
  }
}

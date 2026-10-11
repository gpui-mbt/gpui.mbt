///|
fn valid_display_records() -> FixedArray[Double] {
  let records = FixedArray::make(
    DISPLAY_SNAPSHOT_CAPACITY * DISPLAY_INFO_FIELDS,
    0.0,
  )
  records[0] = -1920.0
  records[1] = 0.0
  records[2] = 1920.0
  records[3] = 1080.0
  records[4] = -1920.0
  records[5] = 0.0
  records[6] = 1920.0
  records[7] = 1040.0
  records[8] = 1.0
  records[9] = 1.0
  records[10] = 1.0
  records[11] = 144.0
  records[12] = 144.0
  records[13] = 1.0
  records[14] = 1920.0
  records[15] = 1080.0
  records[16] = 60.0
  records[17] = 0.0
  records
}

///|
test "Windows display snapshot decoder copies bounded physical-pixel records" {
  let records = valid_display_records()
  let displays = match decode_display_snapshot(records, 1) {
    Ok(value) => value
    Err(_) => fail("valid monitor metadata rejected")
  }
  assert_eq(displays.length(), 1)
  assert_eq(displays[0].bounds_left_px, -1920)
  assert_eq(displays[0].bounds_width_px, 1920)
  assert_eq(displays[0].work_area_height_px, 1040)
  assert_true(displays[0].is_primary && displays[0].is_window_monitor)
  assert_true(displays[0].has_effective_dpi)
  assert_eq(displays[0].effective_dpi_x, 144)
  assert_true(displays[0].has_current_mode)
  assert_eq(displays[0].mode_width_px, 1920)
  assert_eq(displays[0].refresh_rate_hz, 60)
  assert_eq(displays[0].orientation_degrees, 0)

  records[11] = 192.0
  assert_eq(displays[0].effective_dpi_x, 144)
  let updated = match decode_display_snapshot(records, 1) {
    Ok(value) => value
    Err(_) => fail("updated monitor metadata rejected")
  }
  assert_eq(updated[0].effective_dpi_x, 192)
  assert_eq(
    match decode_display_snapshot(records, 0) {
      Ok(value) => value.length()
      Err(_) => fail("empty monitor list rejected")
    },
    0,
  )
}

///|
test "Windows display snapshot decoder rejects malformed monitor records" {
  let fractional = valid_display_records()
  fractional[11] = 120.5
  match decode_display_snapshot(fractional, 1) {
    Err(error) => assert_eq(error.code().label(), "conversion_failed")
    Ok(_) => fail("fractional DPI accepted")
  }

  let bad_bool = valid_display_records()
  bad_bool[8] = 2.0
  match decode_display_snapshot(bad_bool, 1) {
    Err(error) => assert_eq(error.code().label(), "conversion_failed")
    Ok(_) => fail("non-boolean primary flag accepted")
  }

  let absent_dpi = valid_display_records()
  absent_dpi[10] = 0.0
  match decode_display_snapshot(absent_dpi, 1) {
    Err(error) => assert_eq(error.code().label(), "conversion_failed")
    Ok(_) => fail("DPI values without availability flag accepted")
  }

  let bad_mode = valid_display_records()
  bad_mode[13] = 0.0
  match decode_display_snapshot(bad_mode, 1) {
    Err(error) => assert_eq(error.code().label(), "conversion_failed")
    Ok(_) => fail("mode dimensions without current-mode flag accepted")
  }

  let bad_orientation = valid_display_records()
  bad_orientation[17] = 45.0
  match decode_display_snapshot(bad_orientation, 1) {
    Err(error) => assert_eq(error.code().label(), "conversion_failed")
    Ok(_) => fail("unsupported orientation accepted")
  }

  let duplicate_primary = valid_display_records()
  for field = 0; field < DISPLAY_INFO_FIELDS; field = field + 1 {
    duplicate_primary[DISPLAY_INFO_FIELDS + field] = duplicate_primary[field]
  }
  match decode_display_snapshot(duplicate_primary, 2) {
    Err(error) => assert_eq(error.code().label(), "conversion_failed")
    Ok(_) => fail("duplicate primary monitors accepted")
  }

  match decode_display_snapshot(FixedArray::make(DISPLAY_INFO_FIELDS, 0.0), 0) {
    Err(error) => assert_eq(error.code().label(), "conversion_failed")
    Ok(_) => fail("incorrect record buffer length accepted")
  }
}

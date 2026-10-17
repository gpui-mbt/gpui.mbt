///|
fn palette_sentinel_color(slot : Int32) -> @primitives.Color {
  @primitives.Color::rgba(slot * 17, slot * 11, slot * 7, slot * 23).unwrap()
}

///|
fn palette_sentinel() -> ButtonPaintPalette {
  ButtonPaintPalette::new(
    normal_border=palette_sentinel_color(0),
    focused_border=palette_sentinel_color(1),
    disabled_border=palette_sentinel_color(2),
    normal_fill=palette_sentinel_color(3),
    hovered_fill=palette_sentinel_color(4),
    pressed_fill=palette_sentinel_color(5),
    loading_fill=palette_sentinel_color(6),
    disabled_fill=palette_sentinel_color(7),
    enabled_foreground=palette_sentinel_color(8),
    disabled_foreground=palette_sentinel_color(9),
  )
}

///|
fn palette_expected_items(
  bounds : @primitives.Rect,
  inset : Double,
  border : Int32,
  fill : Int32,
  foreground : Int32,
) -> Array[@scene.SceneItem] {
  let fill_bounds = @primitives.Rect::new(
    bounds.left() + inset,
    bounds.top() + inset,
    bounds.size().width() - 2.0 * inset,
    bounds.size().height() - 2.0 * inset,
  ).unwrap()
  let text_bounds = @primitives.Rect::new(
    bounds.left() + inset + 8.0,
    bounds.top() + inset + 2.0,
    bounds.size().width() - 2.0 * inset - 16.0,
    bounds.size().height() - 2.0 * inset - 4.0,
  ).unwrap()
  [
    @scene.QuadItem(
      id=100UL,
      bounds~,
      color=palette_sentinel_color(border),
      transform=@scene.AffineTransform::identity(),
      opacity=1.0,
      clip_chain_id=None,
    ),
    @scene.QuadItem(
      id=101UL,
      bounds=fill_bounds,
      color=palette_sentinel_color(fill),
      transform=@scene.AffineTransform::identity(),
      opacity=1.0,
      clip_chain_id=None,
    ),
    @scene.TextItem(
      id=102UL,
      bounds=text_bounds,
      text="Save",
      font_size=16.0,
      color=palette_sentinel_color(foreground),
      transform=@scene.AffineTransform::identity(),
      opacity=1.0,
      clip_chain_id=None,
    ),
  ]
}

///|
test "sentinel roles alpha and full geometry cover every overlapping state" {
  // Fixed slot oracle indexed by disabled/focused/loading/hovered/pointer-held bits.
  // This is intentionally independent of the production branch structure.
  let expected = [
    (0, 3, 8, 1.0),
    (2, 7, 9, 1.0),
    (1, 3, 8, 2.0),
    (2, 7, 9, 2.0),
    (0, 6, 8, 1.0),
    (2, 7, 9, 1.0),
    (1, 6, 8, 2.0),
    (2, 7, 9, 2.0),
    (0, 4, 8, 1.0),
    (2, 7, 9, 1.0),
    (1, 4, 8, 2.0),
    (2, 7, 9, 2.0),
    (0, 6, 8, 1.0),
    (2, 7, 9, 1.0),
    (1, 6, 8, 2.0),
    (2, 7, 9, 2.0),
    (0, 5, 8, 1.0),
    (2, 7, 9, 1.0),
    (1, 5, 8, 2.0),
    (2, 7, 9, 2.0),
    (0, 6, 8, 1.0),
    (2, 7, 9, 1.0),
    (1, 6, 8, 2.0),
    (2, 7, 9, 2.0),
    (0, 5, 8, 1.0),
    (2, 7, 9, 1.0),
    (1, 5, 8, 2.0),
    (2, 7, 9, 2.0),
    (0, 6, 8, 1.0),
    (2, 7, 9, 1.0),
    (1, 6, 8, 2.0),
    (2, 7, 9, 2.0),
  ]
  let palette = palette_sentinel()
  for mask in 0..<32 {
    let (border, fill, foreground, inset) = expected[mask]
    for
      bounds in [
        @primitives.Rect::new(20.0, 30.0, 160.0, 40.0).unwrap(),
        @primitives.Rect::new(-2.5, 0.25, 24.0, 24.0).unwrap(),
        @primitives.Rect::new(0.125, -7.75, 89.5, 31.25).unwrap(),
      ] {
      let button = { ..palette_fixture_button(mask), bounds, }
      assert_eq(
        palette_fixture_json(
          button.paint_items_with_palette(100UL, palette).unwrap(),
        ),
        palette_fixture_json(
          palette_expected_items(bounds, inset, border, fill, foreground),
        ),
      )
      // Keyboard arming must select the same pressed role even without pointer arming.
      for key in [@primitives.Enter, @primitives.Space] {
        let held = { ..button, armed_key: Some(key), }
        let keyboard_fill = if (mask & 1) != 0 {
          7
        } else if (mask & 4) != 0 {
          6
        } else {
          5
        }
        assert_eq(
          palette_fixture_json(
            held.paint_items_with_palette(100UL, palette).unwrap(),
          ),
          palette_fixture_json(
            palette_expected_items(
              bounds, inset, border, keyboard_fill, foreground,
            ),
          ),
        )
      }
    }
  }
}

///|
test "palette does not change simultaneous-invalid error precedence" {
  let long_label = String::make(65_537, 'x')
  let invalid = {
    ..palette_fixture_button(0),
    bounds: @primitives.Rect::new(0.0, 0.0, 23.0, 24.0).unwrap(),
    label: long_label,
  }
  for palette in [ButtonPaintPalette::standard(), palette_sentinel()] {
    for id in [0UL, 18446744073709551613UL, 18446744073709551615UL] {
      assert_true(
        invalid.paint_items_with_palette(id, palette) is Err(InvalidItemId),
      )
      assert_true(invalid.paint_items(id) is Err(InvalidItemId))
    }
    for id in [1UL, 18446744073709551612UL] {
      assert_true(
        invalid.paint_items_with_palette(id, palette) is Err(InvalidBounds),
      )
      assert_true(invalid.paint_items(id) is Err(InvalidBounds))
      let valid_bounds = {
        ..invalid,
        bounds: palette_fixture_button(0).bounds,
      }
      assert_true(
        valid_bounds.paint_items_with_palette(id, palette)
        is Err(SceneFailure(_)),
      )
      assert_true(valid_bounds.paint_items(id) is Err(SceneFailure(_)))
    }
  }
}

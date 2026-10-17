///|
// Full pre-palette scene fixtures, verified against public main 1638967.
fn palette_fixture_button(mask : Int32) -> Button {
  {
    id: 17UL,
    bounds: @primitives.Rect::new(20.0, 30.0, 160.0, 40.0).unwrap(),
    label: "Save",
    enabled: (mask & 1) == 0,
    focused: (mask & 2) != 0,
    loading: (mask & 4) != 0,
    hovered: (mask & 8) != 0,
    armed_pointer: (mask & 16) != 0,
    armed_key: None,
  }
}

///|
fn palette_fixture_json(items : Array[@scene.SceneItem]) -> String {
  @scene.SceneSnapshot::new(
    @primitives.Rect::new(0.0, 0.0, 240.0, 120.0).unwrap(),
    1.0,
    [],
    [],
    items,
  )
  .unwrap()
  .canonical_json()
}

///|
test "frozen legacy palette scene mask 0" {
  let expected = "{\"schema_version\":1,\"viewport\":{\"x\":0,\"y\":0,\"width\":240,\"height\":120},\"scale\":1,\"resources\":[],\"clip_chains\":[],\"items\":[{\"kind\":\"quad\",\"id\":100,\"bounds\":{\"x\":20,\"y\":30,\"width\":160,\"height\":40},\"color\":{\"red\":102,\"green\":126,\"blue\":150,\"alpha\":255},\"transform\":{\"a\":1,\"b\":0,\"c\":0,\"d\":1,\"tx\":0,\"ty\":0},\"opacity\":1,\"clip_chain_id\":null},{\"kind\":\"quad\",\"id\":101,\"bounds\":{\"x\":21,\"y\":31,\"width\":158,\"height\":38},\"color\":{\"red\":42,\"green\":71,\"blue\":101,\"alpha\":255},\"transform\":{\"a\":1,\"b\":0,\"c\":0,\"d\":1,\"tx\":0,\"ty\":0},\"opacity\":1,\"clip_chain_id\":null},{\"kind\":\"text\",\"id\":102,\"bounds\":{\"x\":29,\"y\":33,\"width\":142,\"height\":34},\"text\":\"Save\",\"font_size\":16,\"color\":{\"red\":242,\"green\":246,\"blue\":250,\"alpha\":255},\"transform\":{\"a\":1,\"b\":0,\"c\":0,\"d\":1,\"tx\":0,\"ty\":0},\"opacity\":1,\"clip_chain_id\":null}]}"
  let button = palette_fixture_button(0)
  assert_eq(palette_fixture_json(button.paint_items(100UL).unwrap()), expected)
  assert_eq(
    palette_fixture_json(
      button
      .paint_items_with_palette(100UL, ButtonPaintPalette::standard())
      .unwrap(),
    ),
    expected,
  )
}

///|
test "frozen legacy palette scene mask 2" {
  let expected = "{\"schema_version\":1,\"viewport\":{\"x\":0,\"y\":0,\"width\":240,\"height\":120},\"scale\":1,\"resources\":[],\"clip_chains\":[],\"items\":[{\"kind\":\"quad\",\"id\":100,\"bounds\":{\"x\":20,\"y\":30,\"width\":160,\"height\":40},\"color\":{\"red\":98,\"green\":170,\"blue\":255,\"alpha\":255},\"transform\":{\"a\":1,\"b\":0,\"c\":0,\"d\":1,\"tx\":0,\"ty\":0},\"opacity\":1,\"clip_chain_id\":null},{\"kind\":\"quad\",\"id\":101,\"bounds\":{\"x\":22,\"y\":32,\"width\":156,\"height\":36},\"color\":{\"red\":42,\"green\":71,\"blue\":101,\"alpha\":255},\"transform\":{\"a\":1,\"b\":0,\"c\":0,\"d\":1,\"tx\":0,\"ty\":0},\"opacity\":1,\"clip_chain_id\":null},{\"kind\":\"text\",\"id\":102,\"bounds\":{\"x\":30,\"y\":34,\"width\":140,\"height\":32},\"text\":\"Save\",\"font_size\":16,\"color\":{\"red\":242,\"green\":246,\"blue\":250,\"alpha\":255},\"transform\":{\"a\":1,\"b\":0,\"c\":0,\"d\":1,\"tx\":0,\"ty\":0},\"opacity\":1,\"clip_chain_id\":null}]}"
  let button = palette_fixture_button(2)
  assert_eq(palette_fixture_json(button.paint_items(100UL).unwrap()), expected)
  assert_eq(
    palette_fixture_json(
      button
      .paint_items_with_palette(100UL, ButtonPaintPalette::standard())
      .unwrap(),
    ),
    expected,
  )
}

///|
test "frozen legacy palette scene mask 8" {
  let expected = "{\"schema_version\":1,\"viewport\":{\"x\":0,\"y\":0,\"width\":240,\"height\":120},\"scale\":1,\"resources\":[],\"clip_chains\":[],\"items\":[{\"kind\":\"quad\",\"id\":100,\"bounds\":{\"x\":20,\"y\":30,\"width\":160,\"height\":40},\"color\":{\"red\":102,\"green\":126,\"blue\":150,\"alpha\":255},\"transform\":{\"a\":1,\"b\":0,\"c\":0,\"d\":1,\"tx\":0,\"ty\":0},\"opacity\":1,\"clip_chain_id\":null},{\"kind\":\"quad\",\"id\":101,\"bounds\":{\"x\":21,\"y\":31,\"width\":158,\"height\":38},\"color\":{\"red\":48,\"green\":91,\"blue\":137,\"alpha\":255},\"transform\":{\"a\":1,\"b\":0,\"c\":0,\"d\":1,\"tx\":0,\"ty\":0},\"opacity\":1,\"clip_chain_id\":null},{\"kind\":\"text\",\"id\":102,\"bounds\":{\"x\":29,\"y\":33,\"width\":142,\"height\":34},\"text\":\"Save\",\"font_size\":16,\"color\":{\"red\":242,\"green\":246,\"blue\":250,\"alpha\":255},\"transform\":{\"a\":1,\"b\":0,\"c\":0,\"d\":1,\"tx\":0,\"ty\":0},\"opacity\":1,\"clip_chain_id\":null}]}"
  let button = palette_fixture_button(8)
  assert_eq(palette_fixture_json(button.paint_items(100UL).unwrap()), expected)
  assert_eq(
    palette_fixture_json(
      button
      .paint_items_with_palette(100UL, ButtonPaintPalette::standard())
      .unwrap(),
    ),
    expected,
  )
}

///|
test "frozen legacy palette scene mask 16" {
  let expected = "{\"schema_version\":1,\"viewport\":{\"x\":0,\"y\":0,\"width\":240,\"height\":120},\"scale\":1,\"resources\":[],\"clip_chains\":[],\"items\":[{\"kind\":\"quad\",\"id\":100,\"bounds\":{\"x\":20,\"y\":30,\"width\":160,\"height\":40},\"color\":{\"red\":102,\"green\":126,\"blue\":150,\"alpha\":255},\"transform\":{\"a\":1,\"b\":0,\"c\":0,\"d\":1,\"tx\":0,\"ty\":0},\"opacity\":1,\"clip_chain_id\":null},{\"kind\":\"quad\",\"id\":101,\"bounds\":{\"x\":21,\"y\":31,\"width\":158,\"height\":38},\"color\":{\"red\":35,\"green\":77,\"blue\":119,\"alpha\":255},\"transform\":{\"a\":1,\"b\":0,\"c\":0,\"d\":1,\"tx\":0,\"ty\":0},\"opacity\":1,\"clip_chain_id\":null},{\"kind\":\"text\",\"id\":102,\"bounds\":{\"x\":29,\"y\":33,\"width\":142,\"height\":34},\"text\":\"Save\",\"font_size\":16,\"color\":{\"red\":242,\"green\":246,\"blue\":250,\"alpha\":255},\"transform\":{\"a\":1,\"b\":0,\"c\":0,\"d\":1,\"tx\":0,\"ty\":0},\"opacity\":1,\"clip_chain_id\":null}]}"
  let button = palette_fixture_button(16)
  assert_eq(palette_fixture_json(button.paint_items(100UL).unwrap()), expected)
  assert_eq(
    palette_fixture_json(
      button
      .paint_items_with_palette(100UL, ButtonPaintPalette::standard())
      .unwrap(),
    ),
    expected,
  )
}

///|
test "frozen legacy palette scene mask 4" {
  let expected = "{\"schema_version\":1,\"viewport\":{\"x\":0,\"y\":0,\"width\":240,\"height\":120},\"scale\":1,\"resources\":[],\"clip_chains\":[],\"items\":[{\"kind\":\"quad\",\"id\":100,\"bounds\":{\"x\":20,\"y\":30,\"width\":160,\"height\":40},\"color\":{\"red\":102,\"green\":126,\"blue\":150,\"alpha\":255},\"transform\":{\"a\":1,\"b\":0,\"c\":0,\"d\":1,\"tx\":0,\"ty\":0},\"opacity\":1,\"clip_chain_id\":null},{\"kind\":\"quad\",\"id\":101,\"bounds\":{\"x\":21,\"y\":31,\"width\":158,\"height\":38},\"color\":{\"red\":55,\"green\":70,\"blue\":88,\"alpha\":255},\"transform\":{\"a\":1,\"b\":0,\"c\":0,\"d\":1,\"tx\":0,\"ty\":0},\"opacity\":1,\"clip_chain_id\":null},{\"kind\":\"text\",\"id\":102,\"bounds\":{\"x\":29,\"y\":33,\"width\":142,\"height\":34},\"text\":\"Save\",\"font_size\":16,\"color\":{\"red\":242,\"green\":246,\"blue\":250,\"alpha\":255},\"transform\":{\"a\":1,\"b\":0,\"c\":0,\"d\":1,\"tx\":0,\"ty\":0},\"opacity\":1,\"clip_chain_id\":null}]}"
  let button = palette_fixture_button(4)
  assert_eq(palette_fixture_json(button.paint_items(100UL).unwrap()), expected)
  assert_eq(
    palette_fixture_json(
      button
      .paint_items_with_palette(100UL, ButtonPaintPalette::standard())
      .unwrap(),
    ),
    expected,
  )
}

///|
test "frozen legacy palette scene mask 1" {
  let expected = "{\"schema_version\":1,\"viewport\":{\"x\":0,\"y\":0,\"width\":240,\"height\":120},\"scale\":1,\"resources\":[],\"clip_chains\":[],\"items\":[{\"kind\":\"quad\",\"id\":100,\"bounds\":{\"x\":20,\"y\":30,\"width\":160,\"height\":40},\"color\":{\"red\":100,\"green\":106,\"blue\":114,\"alpha\":255},\"transform\":{\"a\":1,\"b\":0,\"c\":0,\"d\":1,\"tx\":0,\"ty\":0},\"opacity\":1,\"clip_chain_id\":null},{\"kind\":\"quad\",\"id\":101,\"bounds\":{\"x\":21,\"y\":31,\"width\":158,\"height\":38},\"color\":{\"red\":47,\"green\":52,\"blue\":60,\"alpha\":255},\"transform\":{\"a\":1,\"b\":0,\"c\":0,\"d\":1,\"tx\":0,\"ty\":0},\"opacity\":1,\"clip_chain_id\":null},{\"kind\":\"text\",\"id\":102,\"bounds\":{\"x\":29,\"y\":33,\"width\":142,\"height\":34},\"text\":\"Save\",\"font_size\":16,\"color\":{\"red\":166,\"green\":171,\"blue\":178,\"alpha\":255},\"transform\":{\"a\":1,\"b\":0,\"c\":0,\"d\":1,\"tx\":0,\"ty\":0},\"opacity\":1,\"clip_chain_id\":null}]}"
  let button = palette_fixture_button(1)
  assert_eq(palette_fixture_json(button.paint_items(100UL).unwrap()), expected)
  assert_eq(
    palette_fixture_json(
      button
      .paint_items_with_palette(100UL, ButtonPaintPalette::standard())
      .unwrap(),
    ),
    expected,
  )
}

///|
test "frozen legacy palette scene mask 6" {
  let expected = "{\"schema_version\":1,\"viewport\":{\"x\":0,\"y\":0,\"width\":240,\"height\":120},\"scale\":1,\"resources\":[],\"clip_chains\":[],\"items\":[{\"kind\":\"quad\",\"id\":100,\"bounds\":{\"x\":20,\"y\":30,\"width\":160,\"height\":40},\"color\":{\"red\":98,\"green\":170,\"blue\":255,\"alpha\":255},\"transform\":{\"a\":1,\"b\":0,\"c\":0,\"d\":1,\"tx\":0,\"ty\":0},\"opacity\":1,\"clip_chain_id\":null},{\"kind\":\"quad\",\"id\":101,\"bounds\":{\"x\":22,\"y\":32,\"width\":156,\"height\":36},\"color\":{\"red\":55,\"green\":70,\"blue\":88,\"alpha\":255},\"transform\":{\"a\":1,\"b\":0,\"c\":0,\"d\":1,\"tx\":0,\"ty\":0},\"opacity\":1,\"clip_chain_id\":null},{\"kind\":\"text\",\"id\":102,\"bounds\":{\"x\":30,\"y\":34,\"width\":140,\"height\":32},\"text\":\"Save\",\"font_size\":16,\"color\":{\"red\":242,\"green\":246,\"blue\":250,\"alpha\":255},\"transform\":{\"a\":1,\"b\":0,\"c\":0,\"d\":1,\"tx\":0,\"ty\":0},\"opacity\":1,\"clip_chain_id\":null}]}"
  let button = palette_fixture_button(6)
  assert_eq(palette_fixture_json(button.paint_items(100UL).unwrap()), expected)
  assert_eq(
    palette_fixture_json(
      button
      .paint_items_with_palette(100UL, ButtonPaintPalette::standard())
      .unwrap(),
    ),
    expected,
  )
}

///|
test "frozen legacy palette scene mask 31" {
  let expected = "{\"schema_version\":1,\"viewport\":{\"x\":0,\"y\":0,\"width\":240,\"height\":120},\"scale\":1,\"resources\":[],\"clip_chains\":[],\"items\":[{\"kind\":\"quad\",\"id\":100,\"bounds\":{\"x\":20,\"y\":30,\"width\":160,\"height\":40},\"color\":{\"red\":100,\"green\":106,\"blue\":114,\"alpha\":255},\"transform\":{\"a\":1,\"b\":0,\"c\":0,\"d\":1,\"tx\":0,\"ty\":0},\"opacity\":1,\"clip_chain_id\":null},{\"kind\":\"quad\",\"id\":101,\"bounds\":{\"x\":22,\"y\":32,\"width\":156,\"height\":36},\"color\":{\"red\":47,\"green\":52,\"blue\":60,\"alpha\":255},\"transform\":{\"a\":1,\"b\":0,\"c\":0,\"d\":1,\"tx\":0,\"ty\":0},\"opacity\":1,\"clip_chain_id\":null},{\"kind\":\"text\",\"id\":102,\"bounds\":{\"x\":30,\"y\":34,\"width\":140,\"height\":32},\"text\":\"Save\",\"font_size\":16,\"color\":{\"red\":166,\"green\":171,\"blue\":178,\"alpha\":255},\"transform\":{\"a\":1,\"b\":0,\"c\":0,\"d\":1,\"tx\":0,\"ty\":0},\"opacity\":1,\"clip_chain_id\":null}]}"
  let button = palette_fixture_button(31)
  assert_eq(palette_fixture_json(button.paint_items(100UL).unwrap()), expected)
  assert_eq(
    palette_fixture_json(
      button
      .paint_items_with_palette(100UL, ButtonPaintPalette::standard())
      .unwrap(),
    ),
    expected,
  )
}

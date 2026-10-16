///|
let playground : @layout_playground.Playground = @layout_playground.Playground::new()

///|
#export_name("gpui_layout_select")
pub fn select(index : Int32) -> Bool {
  playground.select(index)
}

///|
#export_name("gpui_layout_change")
pub fn change(field : String, index : Int32, value : Double) -> Bool {
  playground.change(field, index, value)
}

///|
#export_name("gpui_layout_snapshot")
pub fn snapshot() -> String {
  playground.snapshot()
}

///|
#export_name("gpui_layout_presets")
pub fn presets() -> String {
  @layout_playground.preset_ids()
}

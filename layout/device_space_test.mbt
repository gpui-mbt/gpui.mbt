///|
priv struct DeviceSpaceProfile {
  reverse : Bool
  width : Double
  height : Double
  children : Array[(Double, Double)]
  basis : Array[@layout.FlexBasis]
  grow : Array[Double]
  shrink : Array[Double]
  minimum : Array[Double]
  align : @layout.AlignItems
  align_self : Array[@layout.AlignSelf]
  justify : @layout.JustifyContent
  wrap : @layout.FlexWrap
  content : @layout.AlignContent
  gaps : (Double, Double)
  expected_device : Array[(Double, Double, Double, Double)]
}

///|
// Exact device-pixel rectangles from pinned GPUI 5a5fbe7. The same authored
// cases are retained in gpui-conformance's percentage-basis corpus.
fn device_space_profiles() -> Array[DeviceSpaceProfile] {
  [
    {
      reverse: false,
      width: 181.0,
      height: 109.0,
      children: [(31.0, 13.0), (43.0, 21.0), (27.0, 17.0)],
      basis: [
        @layout.FlexBasis::auto(),
        @layout.FlexBasis::auto(),
        @layout.FlexBasis::auto(),
      ],
      grow: [1.0, 2.0, 0.0],
      shrink: [1.0, 1.0, 1.0],
      minimum: [0.0, 0.0, 0.0],
      align: @layout.AlignItems::center(),
      align_self: [
        @layout.AlignSelf::auto(),
        @layout.AlignSelf::auto(),
        @layout.AlignSelf::auto(),
      ],
      justify: @layout.JustifyContent::flex_end(),
      wrap: @layout.FlexWrap::no_wrap(),
      content: @layout.AlignContent::start(),
      gaps: (6.0, 9.0),
      expected_device: [
        (0.0, 0.0, 271.0, 163.0),
        (19.0, 68.0, 70.0, 19.0),
        (98.0, 62.0, 113.0, 31.0),
        (220.0, 65.0, 40.0, 25.0),
      ],
    },
    {
      reverse: true,
      width: 181.0,
      height: 109.0,
      children: [(31.0, 13.0), (43.0, 21.0), (27.0, 17.0)],
      basis: [
        @layout.FlexBasis::points(0.0).unwrap(),
        @layout.FlexBasis::points(36.0).unwrap(),
        @layout.FlexBasis::points(57.0).unwrap(),
      ],
      grow: [0.0, 1.0, 2.0],
      shrink: [1.0, 0.5, 2.0],
      minimum: [0.0, 0.0, 0.0],
      align: @layout.AlignItems::start(),
      align_self: [
        @layout.AlignSelf::start(),
        @layout.AlignSelf::center(),
        @layout.AlignSelf::end(),
      ],
      justify: @layout.JustifyContent::flex_start(),
      wrap: @layout.FlexWrap::no_wrap(),
      content: @layout.AlignContent::start(),
      gaps: (6.0, 9.0),
      expected_device: [
        (0.0, 0.0, 271.0, 163.0),
        (260.0, 5.0, 0.0, 19.0),
        (169.0, 62.0, 82.0, 31.0),
        (19.0, 125.0, 141.0, 25.0),
      ],
    },
    {
      reverse: true,
      width: 149.0,
      height: 109.0,
      children: [(70.0, 13.0), (45.0, 21.0), (28.0, 17.0)],
      basis: [
        @layout.FlexBasis::percent(0.75).unwrap(),
        @layout.FlexBasis::percent(0.5).unwrap(),
        @layout.FlexBasis::points(36.0).unwrap(),
      ],
      grow: [0.0, 0.0, 0.0],
      shrink: [1.0, 2.0, 0.5],
      minimum: [8.0, 12.0, 10.0],
      align: @layout.AlignItems::start(),
      align_self: [
        @layout.AlignSelf::center(),
        @layout.AlignSelf::end(),
        @layout.AlignSelf::start(),
      ],
      justify: @layout.JustifyContent::flex_start(),
      wrap: @layout.FlexWrap::no_wrap(),
      content: @layout.AlignContent::start(),
      gaps: (6.0, 9.0),
      expected_device: [
        (0.0, 0.0, 223.0, 163.0),
        (115.0, 68.0, 97.0, 19.0),
        (73.0, 119.0, 33.0, 31.0),
        (19.0, 5.0, 45.0, 25.0),
      ],
    },
    {
      reverse: true,
      width: 149.0,
      height: 125.0,
      children: [(25.0, 15.0), (29.0, 21.0), (31.0, 17.0)],
      basis: [
        @layout.FlexBasis::percent(0.5).unwrap(),
        @layout.FlexBasis::percent(0.5).unwrap(),
        @layout.FlexBasis::percent(0.25).unwrap(),
      ],
      grow: [0.0, 0.0, 0.0],
      shrink: [0.0, 0.0, 0.0],
      minimum: [0.0, 0.0, 0.0],
      align: @layout.AlignItems::center(),
      align_self: [
        @layout.AlignSelf::auto(),
        @layout.AlignSelf::auto(),
        @layout.AlignSelf::auto(),
      ],
      justify: @layout.JustifyContent::flex_start(),
      wrap: @layout.FlexWrap::wrap(),
      content: @layout.AlignContent::space_between(),
      gaps: (8.0, 11.0),
      expected_device: [
        (0.0, 0.0, 223.0, 187.0),
        (116.0, 5.0, 96.0, 22.0),
        (116.0, 143.0, 96.0, 31.0),
        (55.0, 146.0, 49.0, 25.0),
      ],
    },
    {
      reverse: true,
      width: 149.0,
      height: 125.0,
      children: [(21.0, 15.0), (35.0, 21.0), (27.0, 17.0)],
      basis: [
        @layout.FlexBasis::percent(0.625).unwrap(),
        @layout.FlexBasis::percent(0.375).unwrap(),
        @layout.FlexBasis::percent(0.5).unwrap(),
      ],
      grow: [0.0, 0.0, 0.0],
      shrink: [0.0, 0.0, 0.0],
      minimum: [0.0, 0.0, 0.0],
      align: @layout.AlignItems::start(),
      align_self: [
        @layout.AlignSelf::flex_start(),
        @layout.AlignSelf::flex_end(),
        @layout.AlignSelf::center(),
      ],
      justify: @layout.JustifyContent::flex_start(),
      wrap: @layout.FlexWrap::wrap_reverse(),
      content: @layout.AlignContent::center(),
      gaps: (7.0, 13.0),
      expected_device: [
        (0.0, 0.0, 223.0, 187.0),
        (92.0, 104.0, 120.0, 22.0),
        (140.0, 54.0, 72.0, 31.0),
        (33.0, 57.0, 97.0, 25.0),
      ],
    },
  ]
}

///|
test "device-space layout preserves exact half edges in both axes and tree paths" {
  for profile in device_space_profiles() {
    for column in [false, true] {
      let direction = if column {
        if profile.reverse {
          @layout.FlowDirection::column_reverse()
        } else {
          @layout.FlowDirection::column()
        }
      } else if profile.reverse {
        @layout.FlowDirection::row_reverse()
      } else {
        @layout.FlowDirection::row()
      }
      let width = if column { profile.height } else { profile.width }
      let height = if column { profile.width } else { profile.height }
      let style = @layout.FlexTreeStyle::new(direction)
        .with_insets(
          if column {
            tree_insets(11, 7, 5, 3)
          } else {
            tree_insets(3, 5, 7, 11)
          },
          if column {
            tree_insets(2, 2, 3, 1)
          } else {
            tree_insets(1, 3, 2, 2)
          },
        )
        .with_gap_x(if column { profile.gaps.1 } else { profile.gaps.0 })
        .unwrap()
        .with_gap_y(if column { profile.gaps.0 } else { profile.gaps.1 })
        .unwrap()
        .with_align(profile.align)
        .with_justify(profile.justify)
        .with_wrap(profile.wrap)
        .with_align_content(profile.content)
      let pure_nodes : Array[@layout.FlexTreeNode] = []
      let mixed_nodes : Array[@layout.MixedTreeNode] = []
      for i, dimensions in profile.children {
        let item = @layout.FlexItem::new(
            (i + 2).to_uint64(),
            tree_points(dimensions.0),
            tree_points(dimensions.1),
            tree_size(
              if column {
                dimensions.1
              } else {
                dimensions.0
              },
              if column {
                dimensions.0
              } else {
                dimensions.1
              },
            ),
          )
          .with_flex_basis(profile.basis[i])
          .with_flex(profile.grow[i], profile.shrink[i])
          .unwrap()
          .with_main_limits(profile.minimum[i], None)
          .unwrap()
          .with_align_self(profile.align_self[i])
        pure_nodes.push(@layout.FlexTreeNode::new(item, 1))
        mixed_nodes.push(
          @layout.MixedTreeNode::new(@layout.FlexChild(item), 1, None),
        )
      }
      let pure = @layout.layout_flex_root_box_with_device_scale(
        1,
        tree_size(width, height),
        style,
        pure_nodes,
        1.5,
      ).unwrap()
      let mixed = @layout.layout_mixed_tree_at(
        1,
        @primitives.Rect::new(0, 0, width, height).unwrap(),
        @layout.FlexStyle(style),
        mixed_nodes,
        Some(1.5),
      ).unwrap()
      for result in [pure, mixed] {
        for i, expected in profile.expected_device {
          let bounds = if i == 0 {
            result.root_bounds()
          } else {
            result.items()[i - 1].bounds()
          }
          let (x, y, w, h) = if column {
            (expected.1, expected.0, expected.3, expected.2)
          } else {
            expected
          }
          assert_eq(
            (
              bounds.left(),
              bounds.top(),
              bounds.size().width(),
              bounds.size().height(),
            ),
            (x / 1.5, y / 1.5, w / 1.5, h / 1.5),
          )
        }
      }
    }
  }
}

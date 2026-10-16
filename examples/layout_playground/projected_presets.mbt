///|
// Limited upstream origin projections; unrecorded bounds are deliberately absent.
let projected_presets : Array[ProjectedPreset] = [
  {
    id: "justify-between-row-gap",
    config: {
      extent: 100.0,
      cross: 30.0,
      column: false,
      gap: 8.0,
      wrap: 0,
      justify: 3,
      children: [
        { basis: 20.0, grow: 0.0, shrink: 0.0, minimum: 0.0, maximum: None, },
        { basis: 20.0, grow: 0.0, shrink: 0.0, minimum: 0.0, maximum: None, },
      ],
    },
    projection: 0,
    recorded: [0.0, 80.0],
    document: "JUSTIFY_BETWEEN_RESULTS.md",
  },
  {
    id: "justify-between-column-gap",
    config: {
      extent: 100.0,
      cross: 30.0,
      column: true,
      gap: 8.0,
      wrap: 0,
      justify: 3,
      children: [
        { basis: 20.0, grow: 0.0, shrink: 0.0, minimum: 0.0, maximum: None, },
        { basis: 20.0, grow: 0.0, shrink: 0.0, minimum: 0.0, maximum: None, },
      ],
    },
    projection: 0,
    recorded: [0.0, 80.0],
    document: "JUSTIFY_BETWEEN_RESULTS.md",
  },
  {
    id: "justify-between-negative-overflow-fallback",
    config: {
      extent: 100.0,
      cross: 30.0,
      column: false,
      gap: 8.0,
      wrap: 0,
      justify: 3,
      children: [
        { basis: 60.0, grow: 0.0, shrink: 0.0, minimum: 0.0, maximum: None, },
        { basis: 60.0, grow: 0.0, shrink: 0.0, minimum: 0.0, maximum: None, },
      ],
    },
    projection: 0,
    recorded: [0.0, 68.0],
    document: "JUSTIFY_BETWEEN_RESULTS.md",
  },
  {
    id: "wrap-decimal-exact-fit",
    config: {
      extent: 100.3,
      cross: 20.0,
      column: false,
      gap: 0.0,
      wrap: 1,
      justify: 0,
      children: [
        { basis: 50.1, grow: 0.0, shrink: 0.0, minimum: 0.0, maximum: None, },
        { basis: 50.2, grow: 0.0, shrink: 0.0, minimum: 0.0, maximum: None, },
      ],
    },
    projection: 1,
    recorded: [0.0, 0.0],
    document: "FLEX_WRAP_RESULTS.md",
  },
  {
    id: "wrap-decimal-overflow-above-fit",
    config: {
      extent: 100.3,
      cross: 20.0,
      column: false,
      gap: 0.0,
      wrap: 1,
      justify: 0,
      children: [
        { basis: 50.1, grow: 0.0, shrink: 0.0, minimum: 0.0, maximum: None, },
        { basis: 50.8, grow: 0.0, shrink: 0.0, minimum: 0.0, maximum: None, },
      ],
    },
    projection: 1,
    recorded: [0.0, 10.0],
    document: "FLEX_WRAP_RESULTS.md",
  }
]

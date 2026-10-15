///|
// Generated from evidence.json; hand edits would sever the published-record binding.
let presets : Array[Preset] = [
  {
    id: "limits-grow-max-first",
    config: {
      extent: 100.0,
      column: false,
      gap: 0.0,
      justify: 0,
      children: [
        {
          basis: 20.0,
          grow: 1.0,
          shrink: 1.0,
          minimum: 0.0,
          maximum: Some(30.0),
        },
        { basis: 20.0, grow: 1.0, shrink: 1.0, minimum: 0.0, maximum: None, },
      ],
    },
    upstream: [
      [0.0, 0.0, 100.0, 20.0],
      [0.0, 0.0, 30.0, 10.0],
      [30.0, 0.0, 70.0, 10.0],
    ],
    before: [
      [0.0, 0.0, 100.0, 20.0],
      [0.0, 0.0, 30.0, 10.0],
      [30.0, 0.0, 50.0, 10.0],
    ],
  },
  {
    id: "limits-grow-max-column",
    config: {
      extent: 100.0,
      column: true,
      gap: 0.0,
      justify: 0,
      children: [
        {
          basis: 20.0,
          grow: 1.0,
          shrink: 1.0,
          minimum: 0.0,
          maximum: Some(30.0),
        },
        { basis: 20.0, grow: 1.0, shrink: 1.0, minimum: 0.0, maximum: None, },
      ],
    },
    upstream: [
      [0.0, 0.0, 20.0, 100.0],
      [0.0, 0.0, 10.0, 30.0],
      [0.0, 30.0, 10.0, 70.0],
    ],
    before: [
      [0.0, 0.0, 20.0, 100.0],
      [0.0, 0.0, 10.0, 30.0],
      [0.0, 30.0, 10.0, 50.0],
    ],
  },
  {
    id: "limits-grow-max-second",
    config: {
      extent: 100.0,
      column: false,
      gap: 0.0,
      justify: 0,
      children: [
        { basis: 20.0, grow: 1.0, shrink: 1.0, minimum: 0.0, maximum: None, },
        {
          basis: 20.0,
          grow: 1.0,
          shrink: 1.0,
          minimum: 0.0,
          maximum: Some(30.0),
        },
      ],
    },
    upstream: [
      [0.0, 0.0, 100.0, 20.0],
      [0.0, 0.0, 70.0, 10.0],
      [70.0, 0.0, 30.0, 10.0],
    ],
    before: [
      [0.0, 0.0, 100.0, 20.0],
      [0.0, 0.0, 50.0, 10.0],
      [50.0, 0.0, 30.0, 10.0],
    ],
  },
  {
    id: "limits-grow-max-both-control",
    config: {
      extent: 100.0,
      column: false,
      gap: 0.0,
      justify: 0,
      children: [
        {
          basis: 20.0,
          grow: 1.0,
          shrink: 1.0,
          minimum: 0.0,
          maximum: Some(30.0),
        },
        {
          basis: 20.0,
          grow: 1.0,
          shrink: 1.0,
          minimum: 0.0,
          maximum: Some(40.0),
        },
      ],
    },
    upstream: [
      [0.0, 0.0, 100.0, 20.0],
      [0.0, 0.0, 30.0, 10.0],
      [30.0, 0.0, 40.0, 10.0],
    ],
    before: [
      [0.0, 0.0, 100.0, 20.0],
      [0.0, 0.0, 30.0, 10.0],
      [30.0, 0.0, 40.0, 10.0],
    ],
  },
  {
    id: "limits-grow-max-center",
    config: {
      extent: 100.0,
      column: false,
      gap: 0.0,
      justify: 1,
      children: [
        {
          basis: 20.0,
          grow: 1.0,
          shrink: 1.0,
          minimum: 0.0,
          maximum: Some(30.0),
        },
        { basis: 20.0, grow: 1.0, shrink: 1.0, minimum: 0.0, maximum: None, },
      ],
    },
    upstream: [
      [0.0, 0.0, 100.0, 20.0],
      [0.0, 0.0, 30.0, 10.0],
      [30.0, 0.0, 70.0, 10.0],
    ],
    before: [
      [0.0, 0.0, 100.0, 20.0],
      [10.0, 0.0, 30.0, 10.0],
      [40.0, 0.0, 50.0, 10.0],
    ],
  },
  {
    id: "limits-grow-max-end",
    config: {
      extent: 100.0,
      column: false,
      gap: 0.0,
      justify: 2,
      children: [
        {
          basis: 20.0,
          grow: 1.0,
          shrink: 1.0,
          minimum: 0.0,
          maximum: Some(30.0),
        },
        { basis: 20.0, grow: 1.0, shrink: 1.0, minimum: 0.0, maximum: None, },
      ],
    },
    upstream: [
      [0.0, 0.0, 100.0, 20.0],
      [0.0, 0.0, 30.0, 10.0],
      [30.0, 0.0, 70.0, 10.0],
    ],
    before: [
      [0.0, 0.0, 100.0, 20.0],
      [20.0, 0.0, 30.0, 10.0],
      [50.0, 0.0, 50.0, 10.0],
    ],
  },
  {
    id: "limits-grow-max-gap",
    config: {
      extent: 108.0,
      column: false,
      gap: 8.0,
      justify: 0,
      children: [
        {
          basis: 20.0,
          grow: 1.0,
          shrink: 1.0,
          minimum: 0.0,
          maximum: Some(30.0),
        },
        { basis: 20.0, grow: 1.0, shrink: 1.0, minimum: 0.0, maximum: None, },
      ],
    },
    upstream: [
      [0.0, 0.0, 108.0, 20.0],
      [0.0, 0.0, 30.0, 10.0],
      [38.0, 0.0, 70.0, 10.0],
    ],
    before: [
      [0.0, 0.0, 108.0, 20.0],
      [0.0, 0.0, 30.0, 10.0],
      [38.0, 0.0, 50.0, 10.0],
    ],
  },
  {
    id: "limits-grow-max-unequal-factors",
    config: {
      extent: 100.0,
      column: false,
      gap: 0.0,
      justify: 0,
      children: [
        {
          basis: 20.0,
          grow: 0.5,
          shrink: 1.0,
          minimum: 0.0,
          maximum: Some(30.0),
        },
        { basis: 20.0, grow: 1.5, shrink: 1.0, minimum: 0.0, maximum: None, },
      ],
    },
    upstream: [
      [0.0, 0.0, 100.0, 20.0],
      [0.0, 0.0, 30.0, 10.0],
      [30.0, 0.0, 70.0, 10.0],
    ],
    before: [
      [0.0, 0.0, 100.0, 20.0],
      [0.0, 0.0, 30.0, 10.0],
      [30.0, 0.0, 65.0, 10.0],
    ],
  },
  {
    id: "limits-partial-grow-clamp-control",
    config: {
      extent: 100.0,
      column: false,
      gap: 0.0,
      justify: 0,
      children: [
        {
          basis: 20.0,
          grow: 0.25,
          shrink: 1.0,
          minimum: 0.0,
          maximum: Some(30.0),
        },
        { basis: 20.0, grow: 0.25, shrink: 1.0, minimum: 0.0, maximum: None, },
      ],
    },
    upstream: [
      [0.0, 0.0, 100.0, 20.0],
      [0.0, 0.0, 30.0, 10.0],
      [30.0, 0.0, 35.0, 10.0],
    ],
    before: [
      [0.0, 0.0, 100.0, 20.0],
      [0.0, 0.0, 30.0, 10.0],
      [30.0, 0.0, 35.0, 10.0],
    ],
  },
  {
    id: "limits-remaining-grow-below-one-control",
    config: {
      extent: 100.0,
      column: false,
      gap: 0.0,
      justify: 0,
      children: [
        {
          basis: 20.0,
          grow: 0.5,
          shrink: 1.0,
          minimum: 0.0,
          maximum: Some(30.0),
        },
        { basis: 20.0, grow: 0.5, shrink: 1.0, minimum: 0.0, maximum: None, },
      ],
    },
    upstream: [
      [0.0, 0.0, 100.0, 20.0],
      [0.0, 0.0, 30.0, 10.0],
      [30.0, 0.0, 50.0, 10.0],
    ],
    before: [
      [0.0, 0.0, 100.0, 20.0],
      [0.0, 0.0, 30.0, 10.0],
      [30.0, 0.0, 50.0, 10.0],
    ],
  },
  {
    id: "limits-grow-max-below-basis",
    config: {
      extent: 100.0,
      column: false,
      gap: 0.0,
      justify: 0,
      children: [
        {
          basis: 40.0,
          grow: 1.0,
          shrink: 1.0,
          minimum: 0.0,
          maximum: Some(30.0),
        },
        { basis: 20.0, grow: 1.0, shrink: 1.0, minimum: 0.0, maximum: None, },
      ],
    },
    upstream: [
      [0.0, 0.0, 100.0, 20.0],
      [0.0, 0.0, 30.0, 10.0],
      [30.0, 0.0, 70.0, 10.0],
    ],
    before: [
      [0.0, 0.0, 100.0, 20.0],
      [0.0, 0.0, 30.0, 10.0],
      [30.0, 0.0, 40.0, 10.0],
    ],
  },
  {
    id: "limits-zero-grow-max",
    config: {
      extent: 100.0,
      column: false,
      gap: 0.0,
      justify: 0,
      children: [
        {
          basis: 20.0,
          grow: 0.0,
          shrink: 1.0,
          minimum: 0.0,
          maximum: Some(10.0),
        },
        { basis: 20.0, grow: 1.0, shrink: 1.0, minimum: 0.0, maximum: None, },
      ],
    },
    upstream: [
      [0.0, 0.0, 100.0, 20.0],
      [0.0, 0.0, 10.0, 10.0],
      [10.0, 0.0, 90.0, 10.0],
    ],
    before: [
      [0.0, 0.0, 100.0, 20.0],
      [0.0, 0.0, 10.0, 10.0],
      [10.0, 0.0, 80.0, 10.0],
    ],
  },
  {
    id: "limits-raw-exact-fit-max",
    config: {
      extent: 80.0,
      column: false,
      gap: 0.0,
      justify: 0,
      children: [
        {
          basis: 40.0,
          grow: 1.0,
          shrink: 1.0,
          minimum: 0.0,
          maximum: Some(30.0),
        },
        { basis: 40.0, grow: 1.0, shrink: 1.0, minimum: 0.0, maximum: None, },
      ],
    },
    upstream: [
      [0.0, 0.0, 80.0, 20.0],
      [0.0, 0.0, 30.0, 10.0],
      [30.0, 0.0, 50.0, 10.0],
    ],
    before: [
      [0.0, 0.0, 80.0, 20.0],
      [0.0, 0.0, 30.0, 10.0],
      [30.0, 0.0, 40.0, 10.0],
    ],
  },
  {
    id: "limits-shrink-min-first",
    config: {
      extent: 40.0,
      column: false,
      gap: 0.0,
      justify: 0,
      children: [
        { basis: 40.0, grow: 0.0, shrink: 1.0, minimum: 30.0, maximum: None, },
        { basis: 40.0, grow: 0.0, shrink: 1.0, minimum: 0.0, maximum: None, },
      ],
    },
    upstream: [
      [0.0, 0.0, 40.0, 20.0],
      [0.0, 0.0, 30.0, 10.0],
      [30.0, 0.0, 10.0, 10.0],
    ],
    before: [
      [0.0, 0.0, 40.0, 20.0],
      [0.0, 0.0, 30.0, 10.0],
      [30.0, 0.0, 20.0, 10.0],
    ],
  },
  {
    id: "limits-shrink-min-column",
    config: {
      extent: 40.0,
      column: true,
      gap: 0.0,
      justify: 0,
      children: [
        { basis: 40.0, grow: 0.0, shrink: 1.0, minimum: 30.0, maximum: None, },
        { basis: 40.0, grow: 0.0, shrink: 1.0, minimum: 0.0, maximum: None, },
      ],
    },
    upstream: [
      [0.0, 0.0, 20.0, 40.0],
      [0.0, 0.0, 10.0, 30.0],
      [0.0, 30.0, 10.0, 10.0],
    ],
    before: [
      [0.0, 0.0, 20.0, 40.0],
      [0.0, 0.0, 10.0, 30.0],
      [0.0, 30.0, 10.0, 20.0],
    ],
  },
  {
    id: "limits-shrink-min-second",
    config: {
      extent: 40.0,
      column: false,
      gap: 0.0,
      justify: 0,
      children: [
        { basis: 40.0, grow: 0.0, shrink: 1.0, minimum: 0.0, maximum: None, },
        { basis: 40.0, grow: 0.0, shrink: 1.0, minimum: 30.0, maximum: None, },
      ],
    },
    upstream: [
      [0.0, 0.0, 40.0, 20.0],
      [0.0, 0.0, 10.0, 10.0],
      [10.0, 0.0, 30.0, 10.0],
    ],
    before: [
      [0.0, 0.0, 40.0, 20.0],
      [0.0, 0.0, 20.0, 10.0],
      [20.0, 0.0, 30.0, 10.0],
    ],
  },
  {
    id: "limits-shrink-min-both-control",
    config: {
      extent: 40.0,
      column: false,
      gap: 0.0,
      justify: 0,
      children: [
        { basis: 40.0, grow: 0.0, shrink: 1.0, minimum: 30.0, maximum: None, },
        { basis: 40.0, grow: 0.0, shrink: 1.0, minimum: 30.0, maximum: None, },
      ],
    },
    upstream: [
      [0.0, 0.0, 40.0, 20.0],
      [0.0, 0.0, 30.0, 10.0],
      [30.0, 0.0, 30.0, 10.0],
    ],
    before: [
      [0.0, 0.0, 40.0, 20.0],
      [0.0, 0.0, 30.0, 10.0],
      [30.0, 0.0, 30.0, 10.0],
    ],
  },
  {
    id: "limits-shrink-min-center",
    config: {
      extent: 40.0,
      column: false,
      gap: 0.0,
      justify: 1,
      children: [
        { basis: 40.0, grow: 0.0, shrink: 1.0, minimum: 30.0, maximum: None, },
        { basis: 40.0, grow: 0.0, shrink: 1.0, minimum: 0.0, maximum: None, },
      ],
    },
    upstream: [
      [0.0, 0.0, 40.0, 20.0],
      [0.0, 0.0, 30.0, 10.0],
      [30.0, 0.0, 10.0, 10.0],
    ],
    before: [
      [0.0, 0.0, 40.0, 20.0],
      [-5.0, 0.0, 30.0, 10.0],
      [25.0, 0.0, 20.0, 10.0],
    ],
  },
  {
    id: "limits-shrink-min-end",
    config: {
      extent: 40.0,
      column: false,
      gap: 0.0,
      justify: 2,
      children: [
        { basis: 40.0, grow: 0.0, shrink: 1.0, minimum: 30.0, maximum: None, },
        { basis: 40.0, grow: 0.0, shrink: 1.0, minimum: 0.0, maximum: None, },
      ],
    },
    upstream: [
      [0.0, 0.0, 40.0, 20.0],
      [0.0, 0.0, 30.0, 10.0],
      [30.0, 0.0, 10.0, 10.0],
    ],
    before: [
      [0.0, 0.0, 40.0, 20.0],
      [-10.0, 0.0, 30.0, 10.0],
      [20.0, 0.0, 20.0, 10.0],
    ],
  },
  {
    id: "limits-shrink-min-gap",
    config: {
      extent: 48.0,
      column: false,
      gap: 8.0,
      justify: 0,
      children: [
        { basis: 40.0, grow: 0.0, shrink: 1.0, minimum: 30.0, maximum: None, },
        { basis: 40.0, grow: 0.0, shrink: 1.0, minimum: 0.0, maximum: None, },
      ],
    },
    upstream: [
      [0.0, 0.0, 48.0, 20.0],
      [0.0, 0.0, 30.0, 10.0],
      [38.0, 0.0, 10.0, 10.0],
    ],
    before: [
      [0.0, 0.0, 48.0, 20.0],
      [0.0, 0.0, 30.0, 10.0],
      [38.0, 0.0, 20.0, 10.0],
    ],
  },
  {
    id: "limits-shrink-min-unequal-bases",
    config: {
      extent: 40.0,
      column: false,
      gap: 0.0,
      justify: 0,
      children: [
        { basis: 20.0, grow: 0.0, shrink: 1.0, minimum: 15.0, maximum: None, },
        { basis: 60.0, grow: 0.0, shrink: 1.0, minimum: 0.0, maximum: None, },
      ],
    },
    upstream: [
      [0.0, 0.0, 40.0, 20.0],
      [0.0, 0.0, 15.0, 10.0],
      [15.0, 0.0, 25.0, 10.0],
    ],
    before: [
      [0.0, 0.0, 40.0, 20.0],
      [0.0, 0.0, 15.0, 10.0],
      [15.0, 0.0, 30.0, 10.0],
    ],
  },
  {
    id: "limits-partial-shrink-clamp-control",
    config: {
      extent: 40.0,
      column: false,
      gap: 0.0,
      justify: 0,
      children: [
        { basis: 40.0, grow: 0.0, shrink: 0.25, minimum: 35.0, maximum: None, },
        { basis: 40.0, grow: 0.0, shrink: 0.25, minimum: 0.0, maximum: None, },
      ],
    },
    upstream: [
      [0.0, 0.0, 40.0, 20.0],
      [0.0, 0.0, 35.0, 10.0],
      [35.0, 0.0, 30.0, 10.0],
    ],
    before: [
      [0.0, 0.0, 40.0, 20.0],
      [0.0, 0.0, 35.0, 10.0],
      [35.0, 0.0, 30.0, 10.0],
    ],
  },
  {
    id: "limits-raw-exact-fit-min",
    config: {
      extent: 60.0,
      column: false,
      gap: 0.0,
      justify: 0,
      children: [
        { basis: 20.0, grow: 0.0, shrink: 1.0, minimum: 30.0, maximum: None, },
        { basis: 40.0, grow: 0.0, shrink: 1.0, minimum: 0.0, maximum: None, },
      ],
    },
    upstream: [
      [0.0, 0.0, 60.0, 20.0],
      [0.0, 0.0, 30.0, 10.0],
      [30.0, 0.0, 30.0, 10.0],
    ],
    before: [
      [0.0, 0.0, 60.0, 20.0],
      [0.0, 0.0, 30.0, 10.0],
      [30.0, 0.0, 40.0, 10.0],
    ],
  },
  {
    id: "limits-inflexible-limits-control",
    config: {
      extent: 100.0,
      column: false,
      gap: 0.0,
      justify: 0,
      children: [
        { basis: 20.0, grow: 0.0, shrink: 0.0, minimum: 30.0, maximum: None, },
        {
          basis: 20.0,
          grow: 0.0,
          shrink: 0.0,
          minimum: 0.0,
          maximum: Some(10.0),
        },
      ],
    },
    upstream: [
      [0.0, 0.0, 100.0, 20.0],
      [0.0, 0.0, 30.0, 10.0],
      [30.0, 0.0, 10.0, 10.0],
    ],
    before: [
      [0.0, 0.0, 100.0, 20.0],
      [0.0, 0.0, 30.0, 10.0],
      [30.0, 0.0, 10.0, 10.0],
    ],
  },
  {
    id: "limits-generous-max-control",
    config: {
      extent: 100.0,
      column: false,
      gap: 0.0,
      justify: 0,
      children: [
        {
          basis: 20.0,
          grow: 1.0,
          shrink: 1.0,
          minimum: 0.0,
          maximum: Some(100.0),
        },
        {
          basis: 20.0,
          grow: 1.0,
          shrink: 1.0,
          minimum: 0.0,
          maximum: Some(100.0),
        },
      ],
    },
    upstream: [
      [0.0, 0.0, 100.0, 20.0],
      [0.0, 0.0, 50.0, 10.0],
      [50.0, 0.0, 50.0, 10.0],
    ],
    before: [
      [0.0, 0.0, 100.0, 20.0],
      [0.0, 0.0, 50.0, 10.0],
      [50.0, 0.0, 50.0, 10.0],
    ],
  },
  {
    id: "limits-zero-max",
    config: {
      extent: 100.0,
      column: false,
      gap: 0.0,
      justify: 0,
      children: [
        {
          basis: 20.0,
          grow: 1.0,
          shrink: 1.0,
          minimum: 0.0,
          maximum: Some(0.0),
        },
        { basis: 20.0, grow: 1.0, shrink: 1.0, minimum: 0.0, maximum: None, },
      ],
    },
    upstream: [
      [0.0, 0.0, 100.0, 20.0],
      [0.0, 0.0, 0.0, 10.0],
      [0.0, 0.0, 100.0, 10.0],
    ],
    before: [
      [0.0, 0.0, 100.0, 20.0],
      [0.0, 0.0, 0.0, 10.0],
      [0.0, 0.0, 50.0, 10.0],
    ],
  },
  {
    id: "limits-mixed-min-max",
    config: {
      extent: 100.0,
      column: false,
      gap: 0.0,
      justify: 0,
      children: [
        { basis: 40.0, grow: 1.0, shrink: 1.0, minimum: 60.0, maximum: None, },
        {
          basis: 40.0,
          grow: 1.0,
          shrink: 1.0,
          minimum: 0.0,
          maximum: Some(30.0),
        },
      ],
    },
    upstream: [
      [0.0, 0.0, 100.0, 20.0],
      [0.0, 0.0, 70.0, 10.0],
      [70.0, 0.0, 30.0, 10.0],
    ],
    before: [
      [0.0, 0.0, 100.0, 20.0],
      [0.0, 0.0, 60.0, 10.0],
      [60.0, 0.0, 30.0, 10.0],
    ],
  },
  {
    id: "limits-hypothetical-exact-fit-control",
    config: {
      extent: 80.0,
      column: false,
      gap: 0.0,
      justify: 0,
      children: [
        {
          basis: 40.0,
          grow: 1.0,
          shrink: 1.0,
          minimum: 0.0,
          maximum: Some(35.0),
        },
        { basis: 40.0, grow: 1.0, shrink: 1.0, minimum: 45.0, maximum: None, },
      ],
    },
    upstream: [
      [0.0, 0.0, 80.0, 20.0],
      [0.0, 0.0, 35.0, 10.0],
      [35.0, 0.0, 45.0, 10.0],
    ],
    before: [
      [0.0, 0.0, 80.0, 20.0],
      [0.0, 0.0, 35.0, 10.0],
      [35.0, 0.0, 45.0, 10.0],
    ],
  },
  {
    id: "limits-zero-basis-capped-partial-control",
    config: {
      extent: 100.0,
      column: false,
      gap: 0.0,
      justify: 0,
      children: [
        {
          basis: 0.0,
          grow: 0.25,
          shrink: 1.0,
          minimum: 0.0,
          maximum: Some(0.0),
        },
        { basis: 20.0, grow: 0.25, shrink: 1.0, minimum: 0.0, maximum: None, },
      ],
    },
    upstream: [
      [0.0, 0.0, 100.0, 20.0],
      [0.0, 0.0, 0.0, 10.0],
      [0.0, 0.0, 40.0, 10.0],
    ],
    before: [
      [0.0, 0.0, 100.0, 20.0],
      [0.0, 0.0, 0.0, 10.0],
      [0.0, 0.0, 40.0, 10.0],
    ],
  },
]

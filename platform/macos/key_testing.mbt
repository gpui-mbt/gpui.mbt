///|
fn test_ascii_key_code(ascii : Int) -> Int? {
  match ascii {
    65 | 97 => Some(0)
    66 | 98 => Some(11)
    67 | 99 => Some(8)
    68 | 100 => Some(2)
    69 | 101 => Some(14)
    70 | 102 => Some(3)
    71 | 103 => Some(5)
    72 | 104 => Some(4)
    73 | 105 => Some(34)
    74 | 106 => Some(38)
    75 | 107 => Some(40)
    76 | 108 => Some(37)
    77 | 109 => Some(46)
    78 | 110 => Some(45)
    79 | 111 => Some(31)
    80 | 112 => Some(35)
    81 | 113 => Some(12)
    82 | 114 => Some(15)
    83 | 115 => Some(1)
    84 | 116 => Some(17)
    85 | 117 => Some(32)
    86 | 118 => Some(9)
    87 | 119 => Some(13)
    88 | 120 => Some(7)
    89 | 121 => Some(16)
    90 | 122 => Some(6)
    33 | 49 => Some(18)
    34 | 39 => Some(39)
    35 | 51 => Some(20)
    36 | 52 => Some(21)
    37 | 53 => Some(23)
    38 | 55 => Some(26)
    40 | 57 => Some(25)
    41 | 48 => Some(29)
    42 | 56 => Some(28)
    43 | 61 => Some(24)
    44 | 60 => Some(43)
    45 | 95 => Some(27)
    46 | 62 => Some(47)
    47 | 63 => Some(44)
    50 | 64 => Some(19)
    54 | 94 => Some(22)
    58 | 59 => Some(41)
    91 | 123 => Some(33)
    92 | 124 => Some(42)
    93 | 125 => Some(30)
    96 | 126 => Some(50)
    32 => Some(49)
    _ => None
  }
}

///|
fn test_key_code(
  key : @primitives.Key,
) -> Result[(Int, String), @diagnostics.FrameworkError] {
  match key {
    @primitives.Character(value) => {
      let bytes = @utf8.encode(value)
      if bytes.length() == 1 &&
        bytes[0].to_int() >= 0x20 &&
        bytes[0].to_int() <= 0x7e {
        match test_ascii_key_code(bytes[0].to_int()) {
          Some(code) => Ok((code, value))
          None => Err(error(@diagnostics.InvalidInput, "post_test_key"))
        }
      } else {
        Err(error(@diagnostics.InvalidInput, "post_test_key"))
      }
    }
    @primitives.Enter => Ok((36, "\r"))
    @primitives.Escape => Ok((53, "\u001b"))
    @primitives.Backspace => Ok((51, "\u007f"))
    @primitives.Delete => Ok((117, "\u007f"))
    @primitives.Tab => Ok((48, "\t"))
    @primitives.Space => Ok((49, " "))
    @primitives.ArrowLeft => Ok((123, ""))
    @primitives.ArrowRight => Ok((124, ""))
    @primitives.ArrowDown => Ok((125, ""))
    @primitives.ArrowUp => Ok((126, ""))
    @primitives.Home => Ok((115, ""))
    @primitives.End => Ok((119, ""))
    @primitives.PageUp => Ok((116, ""))
    @primitives.PageDown => Ok((121, ""))
  }
}

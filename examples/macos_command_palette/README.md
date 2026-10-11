# macOS command palette sample

This native AppKit/Metal sample composes the merged shared command palette,
TextField, CoreText measurement provider, and macOS host. Command+K opens the
palette. Arrow keys move through enabled results, Enter runs the selected
command once, and Escape closes it. The sample displays its action and
background-key counts.

The search adapter accepts printable ASCII characters from ordinary AppKit
key events and lowercases them before sending them through the shared
TextField. Matching therefore remains the shared palette's exact substring
filter over lowercased labels. Backspace, caret navigation, and field clicks
use the shared TextField. The host does not deliver committed insertText
callbacks to this sample; non-ASCII key characters, Japanese IME composition,
candidate windows, paste, and general keyboard-layout behavior are unsupported.
Command, Control, and Option character shortcuts are consumed while the palette
is open; they do not provide copy, paste, or other editing commands.
This sample does not qualify PR #40's native text-input ownership or Kotoeri
acceptance. macOS accessibility transport is also outside its scope.

The opt-in E2E sends synthetic key events through the owned NSWindow and
checks completed Metal frames. It verifies open, ASCII search, disabled-row
skipping, activation, cancellation, reopening, and teardown. This is host-event
and pixel evidence, not physical keyboard or IME evidence.

Build or run on macOS with the repository MoonBit toolchain:

    ./script/build_macos_command_palette.sh --build
    ./script/build_macos_command_palette.sh --e2e
    ./script/build_macos_command_palette.sh --run

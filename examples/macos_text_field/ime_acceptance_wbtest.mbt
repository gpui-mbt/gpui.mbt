///|
test "final IME acceptance finishes only after the blurred frame is presented" {
  // Synthetic order: the Escape ACK ends the session and reaches step 11
  // with a dirty blurred field. Finishing now would record the last batch
  // frame instead of a newer final frame, so the finish must wait.
  assert_false(mac_acceptance_finish_ready(11, false, true))
  // After the blurred frame's own present is accepted the finish may run:
  // its final frame revision is then newer than the last acknowledged batch.
  assert_true(mac_acceptance_finish_ready(11, false, false))
  // No other step or an already-finished state may trigger the finish.
  assert_false(mac_acceptance_finish_ready(10, false, false))
  assert_false(mac_acceptance_finish_ready(11, true, false))
}

///|
test "finish is emitted after the blur frame's present, never on the ACK frame" {
  // Synthetic event order: Escape ACK -> dirty blur -> accepted present ->
  // finish. Recording what the loop's predicate emits per frame fixes the
  // ordering regression where the finish ran on the ACK frame itself.
  let emitted : Array[String] = []
  let mut dirty = true
  // Frame answering the Escape ACK: the blurred field is still dirty, so
  // the finish is held and the blur is presented instead.
  if mac_acceptance_finish_ready(11, false, dirty) {
    emitted.push("finish")
  } else {
    emitted.push("hold")
  }
  // The blur frame's own present is accepted, which clears dirty.
  dirty = false
  // Next accepted frame emits the held finish.
  if mac_acceptance_finish_ready(11, false, dirty) {
    emitted.push("finish")
  } else {
    emitted.push("hold")
  }
  assert_eq(emitted, ["hold", "finish"])
  // A rejected blur present leaves the field dirty, so the finish stays
  // held on the following frame too — success is never claimed on a failed
  // or Busy present.
  dirty = true
  if mac_acceptance_finish_ready(11, false, dirty) {
    emitted.push("finish")
  } else {
    emitted.push("hold")
  }
  assert_eq(emitted, ["hold", "finish", "hold"])
}

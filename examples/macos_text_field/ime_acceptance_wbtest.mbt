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

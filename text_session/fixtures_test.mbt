///|
/// Transport-free PR89-compatible ordering seam. A host has its own exact ACK
/// and fence; this fixture asserts the required order without loading AppKit.
test "batch acceptance exact ACK then deferred geometry fixture" {
  let session = owner()
  let ingress = session.target().unwrap()
  let foreign = owner().target().unwrap()
  let events : Array[String] = []
  let batch = [preview("に"), preview("日本")]
  let receipt = session
    .apply_batch(
      ingress,
      batch,
      fn(document) {
        // Preparation sees the old published model throughout the atomic batch.
        if session.snapshot().published_revision() != 0UL {
          abort("partial publication")
        }
        measure(document)
      },
      admit,
    )
    .unwrap()
  events.push("accepted")
  assert_false(receipt.acknowledges(foreign))
  assert_false(receipt.acknowledges(session.target().unwrap()))
  assert_true(receipt.acknowledges(ingress))
  events.push("exact ACK")
  let geometry = receipt.snapshot().field().caret_rect().unwrap()
  assert_true(geometry.size().height() > 0.0)
  events.push("deferred geometry")
  assert_eq(events[0], "accepted")
  assert_eq(events[1], "exact ACK")
  assert_eq(events[2], "deferred geometry")
  // Receipt arrays cannot be mutated to change the saved ordered outcomes.
  let copy = receipt.outcomes()
  copy.clear()
  assert_eq(receipt.outcomes().length(), 2)
}

///|
test "rejected batch produces no acceptance ACK or geometry publication" {
  let session = owner()
  let target = session.target().unwrap()
  let events : Array[String] = []
  match
    session.apply_batch(
      target,
      [preview("日本"), @text_session.PreviewUtf8("😀", 1, 1)],
      measure,
      admit,
    ) {
    Ok(receipt) => {
      events.push("accepted")
      if receipt.acknowledges(target) {
        events.push("ACK")
      }
      let _ = receipt.snapshot().field().caret_rect().unwrap()
      events.push("geometry")
    }
    Err(_) => ()
  }
  assert_eq(events.length(), 0)
  assert_eq(session.snapshot().delivery_watermark(), 0UL)
  assert_eq(session.snapshot().field().document().text(), "abcd")
}

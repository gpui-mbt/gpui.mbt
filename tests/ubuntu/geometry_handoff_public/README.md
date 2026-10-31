# Retained geometry handoff: controlled public-path fixture

Run `bash tests/ubuntu/geometry_handoff_public/run.sh [framework_sha]` with the
normal Ubuntu native build prerequisites. The default framework source is
`aa629d20318f9792ff27f68f38ede136427de2c3` (#207); the script prints the exact
framework and harness commits, archives that framework into a temporary
workspace, and applies only the checked-in harness wrapper there. The native
FIFO, retained route, decoder, exact-head ACK and geometry update are the
framework source, with the following explicitly controlled boundaries:

- Wayland protocol requests are replaced by test mocks; no compositor or live
  IME is involved. The host is a synthetic native host but uses the real
  `RetainedOrderedRoute::new`, `begin`, `peek`, `handoff_geometry_head`,
  `retry_geometry` and `take_owned_geometry_text` APIs.
- The inactive/focus state is constructed after the real begin/enter to
  reproduce a partial native update error; IME Commit callbacks are invoked
  directly. Their seat, proxy, epoch and sequence are supplied by the real
  native queue and decoder.
- One injected native ACK failure is returned before the real ACK function;
  retry calls the real native ACK. The tests also inject incorrect native seat
  and epoch, a nontext head, multiple arrivals and a forged root receipt. The
  forged root is whitebox fault injection: a public consumer cannot construct
  that private receipt field.
- `review207_finish` frees the synthetic host for fixture isolation; it is not
  evidence of a successful production cutoff or cleanup. No field, action,
  model or scene application is performed.

A passing result establishes only these controlled public route/native FIFO
cases for the printed framework and harness revisions. It does not establish
physical input, compositor/IME behavior, consumer integration or the P1 goal.

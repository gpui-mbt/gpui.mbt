///|
// Definite single-line main-axis resolution. Cross-axis measurement and placement
// remain in layout.mbt; this helper does not implement wrapping or intrinsic sizing.
fn resolve_main_sizes(
  prepared : Array[PreparedItem],
  main_extent : Double,
  gaps : Double,
) -> Result[(Array[Double], Double), LayoutError] {
  let resolved : Array[Double] = []
  let frozen : Array[Bool] = []
  let violations : Array[Double] = []
  let mut basis_total = 0.0
  let mut grow_total = 0.0
  let mut weight_total = 0.0
  let mut hypothetical_total = 0.0
  for entry in prepared {
    basis_total += entry.basis
    grow_total += entry.item.grow
    weight_total += entry.weight
    let hypothetical = clamp_once(
      entry.basis,
      entry.item.min_main,
      entry.item.max_main,
    )
    hypothetical_total += hypothetical
    resolved.push(hypothetical)
    frozen.push(false)
    violations.push(0.0)
  }
  // Retain the existing aggregate finite-value contract even if limits would
  // otherwise hide overflowing bases or factors.
  if !finite(basis_total) ||
    !finite(grow_total) ||
    !finite(weight_total) ||
    !finite(hypothetical_total) ||
    !finite(main_extent - gaps - basis_total) {
    return Err(NonFiniteValue)
  }
  let hypothetical_used = gaps + hypothetical_total
  if !finite(hypothetical_used) {
    return Err(NonFiniteValue)
  }
  let growing = hypothetical_used < main_extent
  let shrinking = hypothetical_used > main_extent
  let mut initial_basis = 0.0
  let mut active = 0
  for index = 0; index < prepared.length(); index = index + 1 {
    let entry = prepared[index]
    let freeze = (!growing && !shrinking) ||
      (entry.item.grow == 0.0 && entry.item.shrink == 0.0) ||
      (growing && entry.basis > resolved[index]) ||
      (shrinking && entry.basis < resolved[index])
    frozen[index] = freeze
    initial_basis += if freeze { resolved[index] } else { entry.basis }
    if !freeze {
      active += 1
    }
  }
  let initial_free = main_extent - gaps - initial_basis
  if !finite(initial_free) {
    return Err(NonFiniteValue)
  }
  // Every nonterminal pass freezes at least one child, bounding the number of
  // passes by the line's child count. Partial budgets always use initial_free.
  while active > 0 {
    let mut used_basis = 0.0
    let mut active_grow = 0.0
    let mut active_weight = 0.0
    let mut active_shrink = 0.0
    for index = 0; index < prepared.length(); index = index + 1 {
      let entry = prepared[index]
      if frozen[index] {
        used_basis += resolved[index]
      } else {
        used_basis += entry.basis
        active_grow += entry.item.grow
        active_weight += entry.weight
        // Only the below-one threshold is needed. Avoid overflowing huge raw
        // shrink factors with zero bases; scaled weights are checked separately.
        active_shrink = if entry.item.shrink >= 1.0 - active_shrink {
          1.0
        } else {
          active_shrink + entry.item.shrink
        }
      }
    }
    let remaining = main_extent - gaps - used_basis
    let budget = if growing && active_grow < 1.0 {
      let partial = initial_free * active_grow - gaps
      if partial < remaining {
        partial
      } else {
        remaining
      }
    } else if shrinking && active_shrink < 1.0 {
      let partial = initial_free * active_shrink - gaps
      if partial > remaining {
        partial
      } else {
        remaining
      }
    } else {
      remaining
    }
    if !finite(remaining) || !finite(budget) {
      return Err(NonFiniteValue)
    }
    let mut total_violation = 0.0
    for index = 0; index < prepared.length(); index = index + 1 {
      if !frozen[index] {
        let entry = prepared[index]
        let proposed = if budget != 0.0 && growing && active_grow > 0.0 {
          entry.basis + budget * (entry.item.grow / active_grow)
        } else if budget != 0.0 && shrinking && active_weight > 0.0 {
          entry.basis + budget * (entry.weight / active_weight)
        } else {
          resolved[index]
        }
        if !finite(proposed) {
          return Err(NonFiniteValue)
        }
        let bounded = clamp_once(
          non_negative(proposed),
          entry.item.min_main,
          entry.item.max_main,
        )
        resolved[index] = bounded
        violations[index] = bounded - proposed
        total_violation += violations[index]
      }
    }
    if !finite(total_violation) {
      return Err(NonFiniteValue)
    }
    let before = active
    for index = 0; index < prepared.length(); index = index + 1 {
      if !frozen[index] &&
        (
          total_violation == 0.0 ||
          (total_violation > 0.0 && violations[index] > 0.0) ||
          (total_violation < 0.0 && violations[index] < 0.0)
        ) {
        frozen[index] = true
        active -= 1
      }
    }
    if active == before {
      return Err(NonFiniteValue)
    }
  }
  let mut used = gaps
  for value in resolved {
    used += value
  }
  if !finite(used) {
    Err(NonFiniteValue)
  } else {
    Ok((resolved, used))
  }
}

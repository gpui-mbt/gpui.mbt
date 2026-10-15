# Flex min/max redistribution comparison

Actual pinned GPUI `zed-industries/zed@d9afb21688e04f89d9e94d96d33eb530aef90886`
(0.2.2, locked Taffy 0.13.0) and gpui.mbt
`e7854d297ebd8f64ef332ba17e9893061b930a03` (0.7.2) were executed on macOS
26.5.2 arm64. The independently authored 29-case corpus in suite
`48e40200c15f61eb2b4799fe9391ff91aa3b13ef` records nine passes and twenty
mismatches. These are retained headless framework executions, not golden answers.

In a 100-point row, two 20-point bases with grow factors one and a 30-point
maximum on the first child resolve to 30/70 in GPUI and 30/50 before correction.
In a 40-point line, two 40-point bases with shrink factors one and a 30-point
minimum on the first resolve to 30/10 and 30/20 respectively. Gaps, column
placement and center/end justification expose the same redistribution gap.
Clamped hypothetical sizes also select the factor mode: raw bases that exactly
fill a line can require growth or shrink after applying their limits.

The independently written resolver freezes constrained children, recomputes
remaining space from frozen sizes and unfrozen bases, and allocates/clamps the
active children until no further violations remain. A positive total violation
freezes minimum violations; a negative total freezes maximum violations; zero
freezes all remaining children. Every nonterminal pass freezes at least one
child. The bounded algorithm takes at most one pass per child, with quadratic
worst-case line work, without changing public types or placement.

Fractional factors continue using the initial free-space budget. For example,
0.5/0.5 growth with a first-child cap of 30 resolves to 30/50 rather than
30/70; 0.25/0.25 shrink with a first-child minimum of 35 resolves to 35/30,
retaining overflow. Zero factors, zero maxima, both constrained children and
mixed min/max limits are explicit controls. Existing numerical validation,
large finite zero-basis factors, cross-axis behavior and overflow tolerance
remain separate MoonBit contracts. Three-child successive freezing has an
additional unit regression and is outside the two-child GPUI oracle corpus.

Five of six new unit tests fail before correction. All 72 earlier headless
cases and deliberate width controls must be rerun with the extended adapters.
Both adapters consume the same optional `min_main`/`max_main` arrays; omitted
limits preserve the old inputs. The comparator, tolerance and upstream pin do
not change. Native window execution remains unverified: the current MoonBit
host unconditionally presents/activates a window, which conflicts with the
session's no-focus-disruption constraint. Headless agreement does not establish
native pixels, window lifecycle, physical input, IME, wrapping or full CSS parity.

GPUI style/test-support APIs and its locked Taffy flex resolution source were
inspected to understand the measured results. No upstream implementation or
test fixture was copied. The provenance record distinguishes GPUI's Apache-2.0
package from the MIT-licensed Taffy dependency and its locked crate checksum.

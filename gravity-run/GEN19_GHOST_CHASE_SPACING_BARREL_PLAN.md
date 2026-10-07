# Gen19 pursuit, encounter spacing, and barrel follow-up

## Scope and constraints

This follow-up investigates three reports in the public Gen17 build and current Gen19 candidate: the one-shot angry ghost sometimes appears to leave instead of overtake, long empty stretches remain in narrow corridors, and ordinary rolling barrels may be destroyed before they reach the runner. Reuse the shared SP/MP event, support, collision, and world-ledger paths. Do not change barrel destruction or coin/wallet behavior without a reproduced route-level cause. Preserve the public Gen17 and pre-follow-up Gen18 courses byte-for-byte.

The user-approved Gen19 ghost behavior snapshots one valid triggering runner's lane at authoritative activation, moves toward that lane once, locks it, overtakes and exits. No continuous homing or return pass. Activation, target selection, replay, baseline, and reconnect must remain shared and deterministic. Demonstrate floor-origin and ceiling-origin events, both target lanes where a safe route exists, 12-tick reaction, and RunnerMotion at 250/500/750px/s with all generated hazards retained.

## Investigation and implementation sequence

1. Trace generated event → world commit/snapshot → model pose → SP presentation and MP baseline/replay. Verify variant dispatch reaches the intended pursuit model rather than a sibling flyby path.
2. Run actual moving SP scenes and full-manifest RunnerMotion routes. Record activation ticks, locked target lane, warning reaction, pass/exit, and any earlier terminal contact. Keep tick and terrain support real; never remove or destroy a hazard to manufacture a safe route.
3. Measure post-filter hazard-event centers and supported narrow-corridor meetings on matched Gen18/Gen19 seeds. Report source candidates, resolved events, max event-center gap, narrow-region rate, and coins separately; these are spatial proxies, not perceived reaction time.
4. Measure ordinary and spiked barrels in shared world simulation at the same seeds and 250/500/750px/s. Separate actual runner-path intersection, destruction-before-runner, and remaining active barrels. Adjust only Gen19 placement if a repeatable positioning defect is demonstrated; retain the shared destruction policy.
5. Preserve Gen17/18 fixtures and update the API/game/backend gate only if the final manifest contract requires it. No live migration, commit, push, or publication before root review.

## Acceptance

- Frozen Gen17/18 fixtures remain exact after Gen19-only changes.
- Real SP and world-model tests show the Gen19 ghost entering the viewport, reacting on the captured lane, locking, overtaking, and leaving at all three speeds; test at least one generated event from each origin lane. Full-manifest routes keep support, sim time, and every resolved lethal encounter.
- Any repeated close pursuit that forces the runner back into the previous locked lane is rejected deterministically by a Gen19-only rule with a regression at the exact boundary.
- Density and barrel measurements state limitations and do not imply every seed is proven playable.

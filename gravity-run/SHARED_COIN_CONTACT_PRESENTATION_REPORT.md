# Shared coin contact presentation

The host now sends one `COIN_CONTACT_PRESENTATION` reliable control event as soon as it validates a player's swept coin contact against the authoritative motion history, active entity incarnation, roster, input sequence, round, and terminal-contact boundary. This event starts the existing `CoinScene` burst on every connected client while the existing 120 ms claim window remains open. It does not change the world ledger, winner, wallet, or collected signal. The later world commit finalizes the already-running effect without replaying it.

If the contact becomes invalid before arbitration, the host sends a scoped cancellation; clients restore the same coin only while the canonical ledger still says it is active. Event deduplication is scoped to round/entity/incarnation and bounded to 2,048 presentations per round. Baselines never start a historical burst.

Verification used Godot 4.7.2 scene-backed tests:

- `coin_contact_broadcast_integration_test.tscn`: host validation, host and guest canonical worlds, guest control receive handler, presentation before the award decision, simultaneous claims with the existing deterministic tie-break, duplicate packet/commit, invalid and stale events, and cancellation restoring an active coin.
- `coin_match_commit_integration_test.tscn`: swept local prediction, delayed service award, denial restore, losing claim, and no reward signal from the effect.

The broadcast integration test exercises the production service receive path with an envelope-shaped control packet, but injects that packet locally; it does not establish a live browser/WebRTC session. The release's ordinary reliable WebRTC control transport is used by the production send path and still needs an in-browser two-client pickup check. No backend migration or reward-policy change was required.

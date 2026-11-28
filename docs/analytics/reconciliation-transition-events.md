# Reconciliation transition event contract

Escrow analytics must treat an applied lifecycle transition as the canonical
activity record, regardless of whether initialization, milestone approval, or
polling reconciliation discovered it.

Each transition record uses the idempotency identity
`contract_id:event_type:observed_ledger_sequence`. The event insert and escrow
status update must share one database transaction. Replaying the same ledger
state therefore updates neither the status nor the analytics count.

`1793400000000_analytics_after_polling` implements this contract. The physical
event table and `webhook_records` response field keep their legacy names for
compatibility, but both now describe the canonical lifecycle journal.

Sync health is recorded once per completed polling cycle in
`reconciliation_runs`. The compatibility-named health query reports the last
successful reconciliation time and pending/dead-letter confirmation retries;
it no longer derives health from callback traffic.

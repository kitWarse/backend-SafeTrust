-- Polling reconciliation lifecycle journal fixture. The repeated funded insert
-- uses the same identity to prove a replay does not add an analytics event.
DELETE FROM safetrust.trustless_work_webhook_events
WHERE contract_id LIKE 'test-ana-reconcile-%';

INSERT INTO safetrust.trustless_work_webhook_events (
  contract_id, event_type, event_identity, payload,
  processed, processed_at, created_at, tenant_id
) VALUES
  ('test-ana-reconcile-funded', 'escrow.funded', 'reconcile-funded-ledger-100',
   '{"source":"reconciliation","observedLedgerSeq":"100"}', true,
   '2026-10-15 12:00+00', '2026-10-15 12:00+00', 'safetrust'),
  ('test-ana-reconcile-released', 'funds.released', 'reconcile-released-ledger-101',
   '{"source":"reconciliation","observedLedgerSeq":"101"}', true,
   '2026-10-15 12:01+00', '2026-10-15 12:01+00', 'safetrust'),
  ('test-ana-reconcile-disputed', 'dispute.raised', 'reconcile-disputed-ledger-102',
   '{"source":"reconciliation","observedLedgerSeq":"102"}', true,
   '2026-10-15 12:02+00', '2026-10-15 12:02+00', 'safetrust')
ON CONFLICT (tenant_id, event_identity) DO NOTHING;

INSERT INTO safetrust.trustless_work_webhook_events (
  contract_id, event_type, event_identity, payload,
  processed, processed_at, created_at, tenant_id
) VALUES (
  'test-ana-reconcile-funded', 'escrow.funded', 'reconcile-funded-ledger-100',
  '{"source":"reconciliation","observedLedgerSeq":"100"}', true,
  '2026-10-15 12:00+00', '2026-10-15 12:00+00', 'safetrust'
)
ON CONFLICT (tenant_id, event_identity) DO NOTHING;

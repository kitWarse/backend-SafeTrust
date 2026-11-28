DROP FUNCTION IF EXISTS safetrust.get_webhook_health_summary(JSON);
DROP TABLE IF EXISTS safetrust.reconciliation_runs;

CREATE OR REPLACE FUNCTION safetrust.get_webhook_health_summary(hasura_session JSON DEFAULT NULL)
RETURNS SETOF safetrust.webhook_health_summary
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
  session_claims JSONB := COALESCE(
    hasura_session::jsonb,
    NULLIF(current_setting('hasura.user', TRUE), '')::JSONB,
    '{}'::JSONB
  );
  session_role TEXT := session_claims ->> 'x-hasura-role';
  session_tenant_id TEXT := NULLIF(session_claims ->> 'x-hasura-tenant-id', '');
BEGIN
  IF session_role IS DISTINCT FROM 'admin' AND session_tenant_id IS NULL THEN
    RAISE EXCEPTION 'A verified x-hasura-tenant-id session claim is required'
      USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  WITH event_summary AS (
    SELECT
      COUNT(*) FILTER (WHERE processed IS NOT TRUE) AS pending_count,
      COUNT(*) FILTER (WHERE error_message IS NOT NULL) AS failed_count,
      MIN(created_at) FILTER (WHERE processed IS NOT TRUE) AS oldest_unprocessed_at
    FROM safetrust.trustless_work_webhook_events
    WHERE session_role = 'admin' OR tenant_id = session_tenant_id
  ),
  source_updates AS (
    SELECT updated_at FROM safetrust.trustless_work_escrows
    WHERE session_role = 'admin' OR tenant_id = session_tenant_id
    UNION ALL
    SELECT updated_at FROM safetrust.escrow_transactions
    WHERE session_role = 'admin' OR tenant_id = session_tenant_id
  ),
  latest_source_update AS (
    SELECT MAX(updated_at) AS last_sync_at FROM source_updates
  )
  SELECT
    event_summary.pending_count,
    event_summary.failed_count,
    ROUND(
      (EXTRACT(EPOCH FROM (statement_timestamp() - event_summary.oldest_unprocessed_at)) / 60)::NUMERIC,
      2
    ),
    latest_source_update.last_sync_at,
    FLOOR(EXTRACT(EPOCH FROM (statement_timestamp() - latest_source_update.last_sync_at)))::BIGINT
  FROM event_summary
  CROSS JOIN latest_source_update;
END;
$$;

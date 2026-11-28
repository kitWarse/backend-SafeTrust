-- Analytics after Trustless Work callback removal.
-- The existing event table is retained as a compatibility-named lifecycle
-- journal; reconciliation writes to it atomically with each status transition.

CREATE TABLE IF NOT EXISTS safetrust.reconciliation_runs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id VARCHAR(255) NOT NULL,
  total_escrows INTEGER NOT NULL,
  updated_count INTEGER NOT NULL,
  unchanged_count INTEGER NOT NULL,
  skipped_count INTEGER NOT NULL,
  error_count INTEGER NOT NULL,
  duration_ms INTEGER NOT NULL,
  completed_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_reconciliation_runs_tenant_completed
  ON safetrust.reconciliation_runs (tenant_id, completed_at DESC);

COMMENT ON TABLE safetrust.trustless_work_webhook_events IS
  'Compatibility-named escrow lifecycle event journal. Initialize, milestone, and reconciliation transitions are recorded exactly once by event_identity.';
COMMENT ON TABLE safetrust.reconciliation_runs IS
  'One row per completed polling reconciliation cycle, used for operational sync health.';

DROP FUNCTION IF EXISTS safetrust.get_webhook_health_summary(JSON);

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
  WITH retry_summary AS (
    SELECT
      COUNT(*) FILTER (WHERE status = 'retrying') AS pending_count,
      COUNT(*) FILTER (WHERE status = 'dead_letter') AS failed_count,
      MIN(created_at) FILTER (WHERE status = 'retrying') AS oldest_pending_at
    FROM safetrust.escrow_confirmation_retries
    WHERE session_role = 'admin' OR tenant_id = session_tenant_id
  ),
  latest_run AS (
    SELECT completed_at AS last_sync_at
    FROM safetrust.reconciliation_runs
    WHERE session_role = 'admin' OR tenant_id = session_tenant_id
    ORDER BY completed_at DESC
    LIMIT 1
  )
  SELECT
    retry_summary.pending_count,
    retry_summary.failed_count,
    ROUND(
      (EXTRACT(EPOCH FROM (statement_timestamp() - retry_summary.oldest_pending_at)) / 60)::NUMERIC,
      2
    ) AS oldest_unprocessed_age_minutes,
    latest_run.last_sync_at,
    FLOOR(EXTRACT(EPOCH FROM (statement_timestamp() - latest_run.last_sync_at)))::BIGINT
      AS sync_lag_seconds
  FROM retry_summary
  LEFT JOIN latest_run ON TRUE;
END;
$$;

COMMENT ON FUNCTION safetrust.get_webhook_health_summary(JSON) IS
  'Compatibility-named sync health summary: pending/dead-letter confirmation retries and time since the last completed reconciliation run.';

COMMENT ON FUNCTION safetrust.get_escrow_analytics_by_day(DATE, DATE, VARCHAR) IS
  'Daily lifecycle analytics sourced from the canonical event journal, including transitions applied by polling reconciliation.';

-- Manual spend logged from Goals (“Log spend”) toward the weekly limit (same row as weekly_targets).
-- Run once in Supabase SQL editor.

-- Prefer idempotent ADD (safe for fresh and existing databases):
ALTER TABLE weekly_targets
  ADD COLUMN IF NOT EXISTS spent_manual_top_up double precision NOT NULL DEFAULT 0;

-- Legacy builds used top_up_allowance — copy then drop when present (optional one-time):
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'weekly_targets'
      AND column_name = 'top_up_allowance'
  ) THEN
    EXECUTE 'UPDATE weekly_targets SET spent_manual_top_up = COALESCE(top_up_allowance, spent_manual_top_up)';
    EXECUTE 'ALTER TABLE weekly_targets DROP COLUMN top_up_allowance';
  END IF;
END $$;

COMMENT ON COLUMN weekly_targets.spent_manual_top_up IS
  'Manual spend added via Goals; combined with transaction sum vs limit_amount';

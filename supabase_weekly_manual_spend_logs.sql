-- Weekly manual spend logs — created when the user taps "Log spend" on a weekly target.
-- Run in Supabase SQL Editor after `weekly_targets` exists.
-- App dual-writes each row to SQLite + this table with the same UUID, then bumps `user_sync_versions`
-- via RPC `bump_sync_version` (see app `VersionSync.bumpVersion`).

CREATE TABLE IF NOT EXISTS weekly_manual_spend_logs (
  id UUID PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  weekly_target_id UUID REFERENCES weekly_targets(id) ON DELETE SET NULL,
  category TEXT NOT NULL,
  amount DOUBLE PRECISION NOT NULL CHECK (amount > 0),
  occurred_at TIMESTAMPTZ NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_wmsl_user_occurred ON weekly_manual_spend_logs(user_id, occurred_at DESC);

ALTER TABLE weekly_manual_spend_logs ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users manage own weekly manual spend logs"
  ON weekly_manual_spend_logs FOR ALL
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

-- =============================================================================
-- Expense Activity Log for Fluid Ledger
-- Run this in your Supabase SQL Editor
-- =============================================================================

CREATE TABLE IF NOT EXISTS expense_activity (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  group_id UUID NOT NULL REFERENCES split_groups(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  action TEXT NOT NULL,         -- 'added', 'edited', 'deleted', 'settled'
  description TEXT NOT NULL,    -- expense title or settlement summary
  details TEXT,                 -- what changed: "₹1000 → ₹1200" etc.
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Index for fast group-level queries
CREATE INDEX IF NOT EXISTS idx_expense_activity_group
  ON expense_activity(group_id, created_at DESC);

-- Enable RLS
ALTER TABLE expense_activity ENABLE ROW LEVEL SECURITY;

-- Users can read activity for groups they belong to
CREATE POLICY "Members can read group activity"
  ON expense_activity FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM group_members
      WHERE group_members.group_id = expense_activity.group_id
        AND group_members.user_id = auth.uid()
    )
  );

-- Users can insert activity for groups they belong to
CREATE POLICY "Members can log activity"
  ON expense_activity FOR INSERT
  WITH CHECK (
    auth.uid() = user_id
    AND EXISTS (
      SELECT 1 FROM group_members
      WHERE group_members.group_id = expense_activity.group_id
        AND group_members.user_id = auth.uid()
    )
  );

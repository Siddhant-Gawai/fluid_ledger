-- =============================================================================
-- Per-table version sync for Fluid Ledger
-- Run this in your Supabase SQL Editor
-- =============================================================================

-- 1. Create the version tracking table
CREATE TABLE IF NOT EXISTS user_sync_versions (
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  table_name TEXT NOT NULL,
  version INTEGER NOT NULL DEFAULT 0,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, table_name)
);

-- Enable RLS
ALTER TABLE user_sync_versions ENABLE ROW LEVEL SECURITY;

-- Users can only read/write their own versions
CREATE POLICY "Users can read own sync versions"
  ON user_sync_versions FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "Users can upsert own sync versions"
  ON user_sync_versions FOR INSERT
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update own sync versions"
  ON user_sync_versions FOR UPDATE
  USING (auth.uid() = user_id);

-- 2. Create the RPC function to atomically bump a version
CREATE OR REPLACE FUNCTION bump_sync_version(p_user_id UUID, p_table_name TEXT)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  INSERT INTO user_sync_versions (user_id, table_name, version, updated_at)
  VALUES (p_user_id, p_table_name, 1, now())
  ON CONFLICT (user_id, table_name)
  DO UPDATE SET version = user_sync_versions.version + 1, updated_at = now();
END;
$$;

-- 3. Auto-bump triggers (bump version when data changes from any source)
--    These ensure version stays correct even for direct SQL edits or other clients.

-- Transactions
CREATE OR REPLACE FUNCTION trg_bump_transactions_version()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  uid UUID;
BEGIN
  uid := COALESCE(NEW.user_id, OLD.user_id);
  IF uid IS NOT NULL THEN
    PERFORM bump_sync_version(uid, 'transactions');
  END IF;
  RETURN COALESCE(NEW, OLD);
END;
$$;

DROP TRIGGER IF EXISTS bump_transactions_version ON transactions;
CREATE TRIGGER bump_transactions_version
  AFTER INSERT OR UPDATE OR DELETE ON transactions
  FOR EACH ROW EXECUTE FUNCTION trg_bump_transactions_version();

-- Profiles
CREATE OR REPLACE FUNCTION trg_bump_profiles_version()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  uid UUID;
BEGIN
  uid := COALESCE(NEW.id, OLD.id);
  IF uid IS NOT NULL THEN
    PERFORM bump_sync_version(uid, 'profiles');
  END IF;
  RETURN COALESCE(NEW, OLD);
END;
$$;

DROP TRIGGER IF EXISTS bump_profiles_version ON profiles;
CREATE TRIGGER bump_profiles_version
  AFTER INSERT OR UPDATE OR DELETE ON profiles
  FOR EACH ROW EXECUTE FUNCTION trg_bump_profiles_version();

-- Split Groups (bump for all members of the group)
CREATE OR REPLACE FUNCTION trg_bump_split_groups_version()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  gid UUID;
  member_uid UUID;
BEGIN
  gid := COALESCE(NEW.id, OLD.id);
  FOR member_uid IN
    SELECT user_id FROM group_members WHERE group_id = gid AND user_id IS NOT NULL
  LOOP
    PERFORM bump_sync_version(member_uid, 'split_groups');
  END LOOP;
  RETURN COALESCE(NEW, OLD);
END;
$$;

DROP TRIGGER IF EXISTS bump_split_groups_version ON split_groups;
CREATE TRIGGER bump_split_groups_version
  AFTER INSERT OR UPDATE OR DELETE ON split_groups
  FOR EACH ROW EXECUTE FUNCTION trg_bump_split_groups_version();

-- Group Members (bump for all members of the group)
CREATE OR REPLACE FUNCTION trg_bump_group_members_version()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  gid UUID;
  member_uid UUID;
BEGIN
  gid := COALESCE(NEW.group_id, OLD.group_id);
  FOR member_uid IN
    SELECT user_id FROM group_members WHERE group_id = gid AND user_id IS NOT NULL
  LOOP
    PERFORM bump_sync_version(member_uid, 'group_members');
  END LOOP;
  RETURN COALESCE(NEW, OLD);
END;
$$;

DROP TRIGGER IF EXISTS bump_group_members_version ON group_members;
CREATE TRIGGER bump_group_members_version
  AFTER INSERT OR UPDATE OR DELETE ON group_members
  FOR EACH ROW EXECUTE FUNCTION trg_bump_group_members_version();

-- Split Expenses (bump for all members of the expense's group)
CREATE OR REPLACE FUNCTION trg_bump_split_expenses_version()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  gid UUID;
  member_uid UUID;
BEGIN
  gid := COALESCE(NEW.group_id, OLD.group_id);
  FOR member_uid IN
    SELECT user_id FROM group_members WHERE group_id = gid AND user_id IS NOT NULL
  LOOP
    PERFORM bump_sync_version(member_uid, 'split_expenses');
  END LOOP;
  RETURN COALESCE(NEW, OLD);
END;
$$;

DROP TRIGGER IF EXISTS bump_split_expenses_version ON split_expenses;
CREATE TRIGGER bump_split_expenses_version
  AFTER INSERT OR UPDATE OR DELETE ON split_expenses
  FOR EACH ROW EXECUTE FUNCTION trg_bump_split_expenses_version();

-- Settlements (bump for all members of the settlement's group)
CREATE OR REPLACE FUNCTION trg_bump_settlements_version()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  gid UUID;
  member_uid UUID;
BEGIN
  gid := COALESCE(NEW.group_id, OLD.group_id);
  FOR member_uid IN
    SELECT user_id FROM group_members WHERE group_id = gid AND user_id IS NOT NULL
  LOOP
    PERFORM bump_sync_version(member_uid, 'settlements');
  END LOOP;
  RETURN COALESCE(NEW, OLD);
END;
$$;

DROP TRIGGER IF EXISTS bump_settlements_version ON settlements;
CREATE TRIGGER bump_settlements_version
  AFTER INSERT OR UPDATE OR DELETE ON settlements
  FOR EACH ROW EXECUTE FUNCTION trg_bump_settlements_version();

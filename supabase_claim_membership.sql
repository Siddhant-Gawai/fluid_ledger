-- =============================================================================
-- Claim group membership by phone — bypasses RLS
-- Run this in your Supabase SQL Editor
-- =============================================================================

-- 1. Returns group_ids where the user is a member (by user_id OR phone).
--    SECURITY DEFINER bypasses RLS so phone-matched rows are visible.
CREATE OR REPLACE FUNCTION get_my_group_ids(p_user_id UUID, p_phone TEXT)
RETURNS TABLE(group_id UUID)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  digits TEXT;
BEGIN
  digits := right(regexp_replace(p_phone, '[^0-9]', '', 'g'), 10);
  RETURN QUERY
    SELECT DISTINCT gm.group_id
    FROM group_members gm
    WHERE gm.user_id = p_user_id
       OR (digits != '' AND right(regexp_replace(gm.phone, '[^0-9]', '', 'g'), 10) = digits);
END;
$$;

-- 2. Claims unclaimed memberships: sets user_id on rows matching phone
--    where user_id is currently NULL. Called once on login.
--    Matches by last 10 digits to handle +91 vs 91 format differences.
CREATE OR REPLACE FUNCTION claim_memberships(p_user_id UUID, p_phone TEXT)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  digits TEXT;
BEGIN
  digits := regexp_replace(p_phone, '[^0-9]', '', 'g');
  UPDATE group_members
  SET user_id = p_user_id
  WHERE user_id IS NULL
    AND right(regexp_replace(phone, '[^0-9]', '', 'g'), 10) = right(digits, 10);
END;
$$;

-- 3. Fix existing phone formats: strip + prefix to match Supabase auth format
UPDATE group_members SET phone = replace(phone, '+', '') WHERE phone LIKE '+%';
UPDATE saved_contacts SET phone = replace(phone, '+', '') WHERE phone LIKE '+%';

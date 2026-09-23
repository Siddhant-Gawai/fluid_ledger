-- =============================================================================
-- Lookup user by phone — bypasses RLS for member linking
-- Run this in your Supabase SQL Editor
-- =============================================================================

-- Returns the user's UUID if a profile with that phone exists, null otherwise.
-- SECURITY DEFINER so it bypasses RLS on profiles table.
-- Only returns the ID — no other profile data is exposed.
-- Tries multiple formats: exact match, with/without +, last 10 digits.

CREATE OR REPLACE FUNCTION lookup_user_by_phone(p_phone TEXT)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  found_id UUID;
  digits TEXT;
BEGIN
  -- 1. Exact match
  SELECT id INTO found_id FROM profiles WHERE phone = p_phone LIMIT 1;
  IF found_id IS NOT NULL THEN RETURN found_id; END IF;

  -- 2. Strip all non-digits for fuzzy matching
  digits := regexp_replace(p_phone, '[^0-9]', '', 'g');

  -- 3. Match last 10 digits (the actual Indian mobile number)
  IF length(digits) >= 10 THEN
    SELECT id INTO found_id
    FROM profiles
    WHERE regexp_replace(phone, '[^0-9]', '', 'g') LIKE '%' || right(digits, 10)
    LIMIT 1;
  END IF;

  RETURN found_id;
END;
$$;

-- Lookup profile name by user_id (for fixing "You" names)
CREATE OR REPLACE FUNCTION lookup_profile_name(p_user_id UUID)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  found_name TEXT;
BEGIN
  SELECT name INTO found_name FROM profiles WHERE id = p_user_id LIMIT 1;
  RETURN found_name;
END;
$$;

-- Fix existing "You" entries with real names
UPDATE group_members gm
SET name = p.name
FROM profiles p
WHERE gm.name = 'You'
  AND gm.user_id = p.id
  AND p.name IS NOT NULL;

-- Also fix existing members that were added before this feature:
-- Links any group_member with a matching phone to their user account.
-- Uses last-10-digit matching for flexibility.
UPDATE group_members gm
SET user_id = p.id
FROM profiles p
WHERE gm.user_id IS NULL
  AND p.phone IS NOT NULL
  AND gm.phone IS NOT NULL
  AND right(regexp_replace(gm.phone, '[^0-9]', '', 'g'), 10)
    = right(regexp_replace(p.phone, '[^0-9]', '', 'g'), 10);

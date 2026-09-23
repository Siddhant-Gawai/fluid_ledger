-- Splitwise hardening: dedupe existing group_members + enforce uniqueness.
-- Run in Supabase SQL editor (one-time migration).

BEGIN;

-- 1) Normalize phone values into digits-only so comparisons are reliable.
UPDATE group_members
SET phone = nullif(regexp_replace(phone, '[^0-9]', '', 'g'), '')
WHERE phone IS NOT NULL;

-- 2) Remove duplicates by (group_id, user_id) when user_id exists.
WITH ranked AS (
  SELECT
    id,
    ROW_NUMBER() OVER (
      PARTITION BY group_id, user_id
      ORDER BY created_at NULLS FIRST, id
    ) AS rn
  FROM group_members
  WHERE user_id IS NOT NULL
)
DELETE FROM group_members gm
USING ranked r
WHERE gm.id = r.id
  AND r.rn > 1;

-- 3) Remove duplicates by (group_id, phone) when phone exists.
WITH ranked AS (
  SELECT
    id,
    ROW_NUMBER() OVER (
      PARTITION BY group_id, phone
      ORDER BY created_at NULLS FIRST, id
    ) AS rn
  FROM group_members
  WHERE phone IS NOT NULL
)
DELETE FROM group_members gm
USING ranked r
WHERE gm.id = r.id
  AND r.rn > 1;

-- 4) Optional safety: remove duplicates by (group_id, lower(name))
-- only for rows with no user_id and no phone.
WITH ranked AS (
  SELECT
    id,
    ROW_NUMBER() OVER (
      PARTITION BY group_id, lower(trim(name))
      ORDER BY created_at NULLS FIRST, id
    ) AS rn
  FROM group_members
  WHERE user_id IS NULL
    AND phone IS NULL
)
DELETE FROM group_members gm
USING ranked r
WHERE gm.id = r.id
  AND r.rn > 1;

-- 5) Enforce future uniqueness (partial unique indexes).
CREATE UNIQUE INDEX IF NOT EXISTS ux_group_members_group_user
  ON group_members(group_id, user_id)
  WHERE user_id IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS ux_group_members_group_phone
  ON group_members(group_id, phone)
  WHERE phone IS NOT NULL;

COMMIT;

-- Verification helpers:
-- SELECT group_id, user_id, COUNT(*) FROM group_members WHERE user_id IS NOT NULL GROUP BY 1,2 HAVING COUNT(*) > 1;
-- SELECT group_id, phone, COUNT(*) FROM group_members WHERE phone IS NOT NULL GROUP BY 1,2 HAVING COUNT(*) > 1;

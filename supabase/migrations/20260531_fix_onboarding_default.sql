-- Fix onboarding default: new users created via trigger should see onboarding.
-- Existing rows already have has_seen_onboarding = true (set by 20260531_add_onboarding_flag.sql)
-- and are unaffected. Only future INSERT default changes.
ALTER TABLE profiles ALTER COLUMN has_seen_onboarding SET DEFAULT false;

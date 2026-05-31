-- Add onboarding flag to profiles.
-- DEFAULT true grandfathers existing users so they skip onboarding.
-- New users have no profile row at all; the Flutter layer treats profile=null as
-- "not onboarded" and shows OnboardingScreen before the row is created.
ALTER TABLE profiles
  ADD COLUMN IF NOT EXISTS has_seen_onboarding boolean NOT NULL DEFAULT true;

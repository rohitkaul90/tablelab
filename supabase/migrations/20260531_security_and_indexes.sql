-- ── Rate-limit RLS hardening ───────────────────────────────────────────────────
-- The FOR ALL policy on ai_usage_log allows authenticated users to DELETE their
-- own log entries via the Supabase REST API, bypassing the Edge Function rate
-- limiter. Replace with SELECT + INSERT only.

DROP POLICY IF EXISTS "Users manage own usage log" ON ai_usage_log;

CREATE POLICY "Users read own usage log"
  ON ai_usage_log FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "Users insert own usage log"
  ON ai_usage_log FOR INSERT
  WITH CHECK (auth.uid() = user_id);

-- ── AI cache lookup indexes ────────────────────────────────────────────────────
-- analyze-session queries ai_analyses by session_id only (RLS adds user_id check,
-- but the unique index is on (user_id, session_id) — second-column-only scans may
-- not use it efficiently). Add explicit single-column indexes.

CREATE INDEX IF NOT EXISTS idx_ai_analyses_session_id
  ON ai_analyses(session_id);

CREATE INDEX IF NOT EXISTS idx_ai_hand_analyses_hand_id
  ON ai_hand_analyses(hand_id);

-- Email Report Subscriptions Migration
-- Stores manager email report preferences for daily/weekly PO spend summaries

CREATE TABLE IF NOT EXISTS public.email_report_subscriptions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  manager_name TEXT NOT NULL,
  email TEXT NOT NULL,
  report_type TEXT NOT NULL DEFAULT 'both', -- 'daily' | 'weekly' | 'both'
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_by UUID REFERENCES public.engineer_profiles(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
  last_sent_at TIMESTAMPTZ,
  CONSTRAINT valid_report_type CHECK (report_type IN ('daily', 'weekly', 'both'))
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_email_report_subs_email ON public.email_report_subscriptions(email);
CREATE INDEX IF NOT EXISTS idx_email_report_subs_active ON public.email_report_subscriptions(is_active);

-- Enable RLS
ALTER TABLE public.email_report_subscriptions ENABLE ROW LEVEL SECURITY;

-- All authenticated users can read subscriptions
DROP POLICY IF EXISTS "authenticated_read_email_subs" ON public.email_report_subscriptions;
CREATE POLICY "authenticated_read_email_subs"
ON public.email_report_subscriptions
FOR SELECT
TO authenticated
USING (true);

-- Authenticated users can insert/update/delete subscriptions
DROP POLICY IF EXISTS "authenticated_manage_email_subs" ON public.email_report_subscriptions;
CREATE POLICY "authenticated_manage_email_subs"
ON public.email_report_subscriptions
FOR ALL
TO authenticated
USING (true)
WITH CHECK (true);

-- Email send log table
CREATE TABLE IF NOT EXISTS public.email_send_log (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  subscription_id UUID REFERENCES public.email_report_subscriptions(id) ON DELETE CASCADE,
  recipient_email TEXT NOT NULL,
  report_type TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'sent', -- 'sent' | 'failed'
  error_message TEXT,
  sent_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_email_send_log_sub ON public.email_send_log(subscription_id);
CREATE INDEX IF NOT EXISTS idx_email_send_log_sent_at ON public.email_send_log(sent_at);

ALTER TABLE public.email_send_log ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "authenticated_read_email_log" ON public.email_send_log;
CREATE POLICY "authenticated_read_email_log"
ON public.email_send_log
FOR SELECT
TO authenticated
USING (true);

DROP POLICY IF EXISTS "authenticated_insert_email_log" ON public.email_send_log;
CREATE POLICY "authenticated_insert_email_log"
ON public.email_send_log
FOR INSERT
TO authenticated
WITH CHECK (true);

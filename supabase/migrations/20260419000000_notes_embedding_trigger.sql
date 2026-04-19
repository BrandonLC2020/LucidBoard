-- Enable pg_net for async HTTP calls from triggers
CREATE EXTENSION IF NOT EXISTS pg_net;

-- Trigger function: calls the generate-embedding Edge Function after note text changes
CREATE OR REPLACE FUNCTION trigger_generate_embedding()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  payload jsonb;
  service_role_key text;
  supabase_url text;
BEGIN
  service_role_key := current_setting('app.service_role_key', true);
  supabase_url := current_setting('app.supabase_url', true);

  IF TG_OP = 'INSERT' THEN
    payload := jsonb_build_object('type', TG_OP, 'record', row_to_json(NEW));
  ELSE
    payload := jsonb_build_object('type', TG_OP, 'record', row_to_json(NEW), 'old_record', row_to_json(OLD));
  END IF;

  PERFORM net.http_post(
    url     := supabase_url || '/functions/v1/generate-embedding',
    headers := jsonb_build_object(
      'Content-Type',  'application/json',
      'Authorization', 'Bearer ' || service_role_key
    ),
    body    := payload::text
  );

  RETURN NEW;
END;
$$;

-- Fire after INSERT or after UPDATE only when content_text actually changes
CREATE OR REPLACE TRIGGER notes_embedding_trigger
AFTER INSERT OR UPDATE OF content_text ON notes
FOR EACH ROW EXECUTE FUNCTION trigger_generate_embedding();

-- Instructions: set these in your Supabase project's Database Settings → Configuration:
--   app.supabase_url  = 'https://<project-ref>.supabase.co'
--   app.service_role_key = '<service-role-key>'
-- Or run:
--   ALTER DATABASE postgres SET app.supabase_url = 'https://<project-ref>.supabase.co';
--   ALTER DATABASE postgres SET app.service_role_key = '<service-role-key>';

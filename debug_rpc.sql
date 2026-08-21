CREATE OR REPLACE FUNCTION get_system_logs()
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
    logs JSONB;
BEGIN
    SELECT jsonb_agg(
        jsonb_build_object(
            'id', id,
            'status_code', status_code,
            'error_msg', error_msg,
            'created_at', created_at,
            'response', content::text
        )
    ) INTO logs
    FROM (
        SELECT id, status_code, error_msg, created, content 
        FROM net._http_response 
        ORDER BY created DESC 
        LIMIT 5
    ) sub;
    
    RETURN COALESCE(logs, '[]'::jsonb);
END;
$$;

GRANT EXECUTE ON FUNCTION get_system_logs() TO anon;

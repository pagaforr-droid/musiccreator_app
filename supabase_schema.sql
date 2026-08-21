-- ==============================================================================
-- SUPABASE MASTER SCRIPT - AI MUSIC GENERATOR
-- ==============================================================================

-- 1. Habilitar extensión pg_net para llamadas HTTP
CREATE EXTENSION IF NOT EXISTS pg_net WITH SCHEMA extensions;

-- 2. Crear tabla de configuración para almacenar la API Key de Replicate
CREATE TABLE IF NOT EXISTS public.app_config (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL
);

ALTER TABLE public.app_config ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Block anon on config" ON public.app_config;
CREATE POLICY "Block anon on config" ON public.app_config FOR ALL TO anon USING (false);

INSERT INTO public.app_config (key, value) VALUES ('replicate_api_key', 'INSERT_YOUR_REPLICATE_API_KEY_HERE')
ON CONFLICT (key) DO NOTHING;

INSERT INTO public.app_config (key, value) VALUES ('supabase_anon_key', 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InNqam5vdnNpdWhqZ2p0cXNxd2J0Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODczNDI1NTksImV4cCI6MjEwMjkxODU1OX0.8chAAmC2LetDjQoA1sMP9It-3nhsw2eGhuFevu3HpPE')
ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;

-- 3. Crear tipo Enum para los estados
DO $$ BEGIN
    CREATE TYPE generation_status AS ENUM ('pending', 'analyzing', 'generating', 'cleaning', 'completed', 'failed');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

-- 4. Crear tabla principal 'generations'
CREATE TABLE IF NOT EXISTS public.generations (
    id UUID PRIMARY KEY DEFAULT extensions.uuid_generate_v4(),
    session_id UUID NOT NULL,
    reference_audio_url TEXT NOT NULL,
    extracted_bpm NUMERIC,
    extracted_chords JSONB,
    target_instrument TEXT NOT NULL,
    target_style TEXT NOT NULL,
    final_stem_url TEXT,
    status generation_status DEFAULT 'pending',
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE public.generations ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Permitir inserts publicos" ON public.generations;
CREATE POLICY "Permitir inserts publicos" ON public.generations FOR INSERT TO anon WITH CHECK (true);

DROP POLICY IF EXISTS "Permitir select publicos" ON public.generations;
CREATE POLICY "Permitir select publicos" ON public.generations FOR SELECT TO anon USING (true);

DROP POLICY IF EXISTS "Permitir update publicos" ON public.generations;
CREATE POLICY "Permitir update publicos" ON public.generations FOR UPDATE TO anon USING (true);

-- ==============================================================================
-- RPCs (Remote Procedure Calls) - ORQUESTADOR DE WEBHOOKS
-- ==============================================================================

-- Eliminar las funciones antiguas para que Postgres no se confunda (Evitar error "not unique")
DROP FUNCTION IF EXISTS webhook_phase_1(JSONB, UUID);
DROP FUNCTION IF EXISTS webhook_phase_2(JSONB, UUID);
DROP FUNCTION IF EXISTS webhook_phase_3(JSONB, UUID);

CREATE OR REPLACE FUNCTION get_replicate_key() RETURNS TEXT
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
    secret_key TEXT;
BEGIN
    SELECT value INTO secret_key FROM public.app_config WHERE key = 'replicate_api_key';
    RETURN secret_key;
END;
$$;

CREATE OR REPLACE FUNCTION get_anon_key() RETURNS TEXT
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
    secret_key TEXT;
BEGIN
    SELECT value INTO secret_key FROM public.app_config WHERE key = 'supabase_anon_key';
    RETURN secret_key;
END;
$$;

CREATE OR REPLACE FUNCTION get_project_url() RETURNS TEXT
LANGUAGE plpgsql AS $$
BEGIN
    RETURN 'https://sjjnovsiuhjgjtqsqwbt.supabase.co';
END;
$$;

-- FASE 1: Iniciar Generación (Usa cwalo/all-in-one-music-structure-analysis)
CREATE OR REPLACE FUNCTION start_generation(p_session_id UUID, p_audio_url TEXT, p_instrument TEXT, p_style TEXT)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
    new_gen_id UUID;
    req_id BIGINT;
    api_key TEXT;
BEGIN
    INSERT INTO public.generations (session_id, reference_audio_url, target_instrument, target_style, status)
    VALUES (p_session_id, p_audio_url, p_instrument, p_style, 'analyzing')
    RETURNING id INTO new_gen_id;

    api_key := get_replicate_key();

    SELECT net.http_post(
        url := 'https://api.replicate.com/v1/predictions',
        headers := jsonb_build_object('Authorization', 'Bearer ' || api_key, 'Content-Type', 'application/json'),
        body := jsonb_build_object(
            'version', '6deeba047db17da69e9826c0285cd137cd2a81af05eb44ff496b7acd69b3a383',
            'input', jsonb_build_object('music_input', p_audio_url),
            'webhook', get_project_url() || '/rest/v1/rpc/webhook_phase_1?apikey=' || get_anon_key() || '&gen_id=' || new_gen_id,
            'webhook_events_filter', jsonb_build_array('completed')
        )
    ) INTO req_id;

    RETURN new_gen_id;
END;
$$;

-- FASE 2: Webhook Fase 1 (Llama a sakemin/musicongen)
CREATE OR REPLACE FUNCTION webhook_phase_1(
    gen_id UUID,
    status TEXT DEFAULT NULL,
    output JSONB DEFAULT NULL,
    error TEXT DEFAULT NULL,
    id TEXT DEFAULT NULL,
    version TEXT DEFAULT NULL,
    created_at TEXT DEFAULT NULL,
    started_at TEXT DEFAULT NULL,
    completed_at TEXT DEFAULT NULL,
    logs TEXT DEFAULT NULL,
    input JSONB DEFAULT NULL,
    metrics JSONB DEFAULT NULL,
    urls JSONB DEFAULT NULL
)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
    v_bpm NUMERIC;
    v_chords JSONB;
    v_instrument TEXT;
    v_style TEXT;
    api_key TEXT;
    req_id BIGINT;
    chords_str TEXT;
BEGIN
    IF status != 'succeeded' THEN
        UPDATE public.generations SET status = 'failed', updated_at = NOW() WHERE id = gen_id;
        RETURN jsonb_build_object('status', 'error', 'msg', error);
    END IF;

    IF jsonb_typeof(output) = 'object' THEN
        v_bpm := (output->>'bpm')::NUMERIC;
        v_chords := output->'chords';
    ELSE
        v_bpm := NULL;
        v_chords := NULL;
    END IF;

    chords_str := COALESCE(v_chords::TEXT, 'C G A:min F');

    UPDATE public.generations 
    SET extracted_bpm = v_bpm, extracted_chords = v_chords, status = 'generating', updated_at = NOW()
    WHERE id = gen_id
    RETURNING target_instrument, target_style INTO v_instrument, v_style;

    api_key := get_replicate_key();

    SELECT net.http_post(
        url := 'https://api.replicate.com/v1/predictions',
        headers := jsonb_build_object('Authorization', 'Bearer ' || api_key, 'Content-Type', 'application/json'),
        body := jsonb_build_object(
            'version', 'a05ec8bdf5cc902cd849077d985029ce9b05e3dfb98a2d74accc9c94fdf15747',
            'input', jsonb_build_object(
                'prompt', 'Isolated ' || v_instrument || ' stem, ' || v_style || ' style.',
                'chord_progression', chords_str,
                'bpm', COALESCE(v_bpm, 120)
            ),
            'webhook', get_project_url() || '/rest/v1/rpc/webhook_phase_2?apikey=' || get_anon_key() || '&gen_id=' || gen_id,
            'webhook_events_filter', jsonb_build_array('completed')
        )
    ) INTO req_id;

    RETURN jsonb_build_object('status', 'success');
END;
$$;

-- FASE 3: Webhook Fase 2 (Llama a lucataco/mvsep-mdx23-music-separation)
CREATE OR REPLACE FUNCTION webhook_phase_2(
    gen_id UUID,
    status TEXT DEFAULT NULL,
    output JSONB DEFAULT NULL,
    error TEXT DEFAULT NULL,
    id TEXT DEFAULT NULL,
    version TEXT DEFAULT NULL,
    created_at TEXT DEFAULT NULL,
    started_at TEXT DEFAULT NULL,
    completed_at TEXT DEFAULT NULL,
    logs TEXT DEFAULT NULL,
    input JSONB DEFAULT NULL,
    metrics JSONB DEFAULT NULL,
    urls JSONB DEFAULT NULL
)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
    v_generated_audio TEXT;
    api_key TEXT;
    req_id BIGINT;
BEGIN
    IF status != 'succeeded' THEN
        UPDATE public.generations SET status = 'failed', updated_at = NOW() WHERE id = gen_id;
        RETURN jsonb_build_object('status', 'error', 'msg', error);
    END IF;

    -- Sakemin returns a URL string
    v_generated_audio := output#>>'{}';

    UPDATE public.generations SET status = 'cleaning', updated_at = NOW() WHERE id = gen_id;

    api_key := get_replicate_key();

    SELECT net.http_post(
        url := 'https://api.replicate.com/v1/predictions',
        headers := jsonb_build_object('Authorization', 'Bearer ' || api_key, 'Content-Type', 'application/json'),
        body := jsonb_build_object(
            'version', '510b9b91aec1bfa7d634e6c06ee80c18492fb0fc06aa1474533fbda90dd3dba4',
            'input', jsonb_build_object('audio', v_generated_audio),
            'webhook', get_project_url() || '/rest/v1/rpc/webhook_phase_3?apikey=' || get_anon_key() || '&gen_id=' || gen_id,
            'webhook_events_filter', jsonb_build_array('completed')
        )
    ) INTO req_id;

    RETURN jsonb_build_object('status', 'success');
END;
$$;

-- FASE FINAL: Webhook Fase 3
CREATE OR REPLACE FUNCTION webhook_phase_3(
    gen_id UUID,
    status TEXT DEFAULT NULL,
    output JSONB DEFAULT NULL,
    error TEXT DEFAULT NULL,
    id TEXT DEFAULT NULL,
    version TEXT DEFAULT NULL,
    created_at TEXT DEFAULT NULL,
    started_at TEXT DEFAULT NULL,
    completed_at TEXT DEFAULT NULL,
    logs TEXT DEFAULT NULL,
    input JSONB DEFAULT NULL,
    metrics JSONB DEFAULT NULL,
    urls JSONB DEFAULT NULL
)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
    v_instrument TEXT;
    v_final_url TEXT;
BEGIN
    IF status != 'succeeded' THEN
        UPDATE public.generations SET status = 'failed', updated_at = NOW() WHERE id = gen_id;
        RETURN jsonb_build_object('status', 'error', 'msg', error);
    END IF;

    SELECT target_instrument INTO v_instrument FROM public.generations WHERE id = gen_id;

    IF v_instrument = 'Bajo' THEN
        v_final_url := output->>'bass';
    ELSIF v_instrument = 'Batería' THEN
        v_final_url := output->>'drums';
    ELSE
        v_final_url := output->>'other';
    END IF;

    UPDATE public.generations 
    SET final_stem_url = v_final_url, status = 'completed', updated_at = NOW() 
    WHERE id = gen_id;

    RETURN jsonb_build_object('status', 'success');
END;
$$;

-- Otorgar permisos de ejecución a los webhooks para que anon pueda llamarlos
GRANT EXECUTE ON FUNCTION webhook_phase_1 TO anon;
GRANT EXECUTE ON FUNCTION webhook_phase_2 TO anon;
GRANT EXECUTE ON FUNCTION webhook_phase_3 TO anon;

-- ==============================================================================
-- STORAGE SECURITY POLICIES (Fixing "new row violates row-level security policy")
-- ==============================================================================
-- Permitir subida de archivos (INSERT) al bucket reference_audio para usuarios anónimos
DROP POLICY IF EXISTS "Permitir subida anonima a reference_audio" ON storage.objects;
CREATE POLICY "Permitir subida anonima a reference_audio" 
ON storage.objects FOR INSERT TO anon 
WITH CHECK (bucket_id = 'reference_audio');

-- Permitir lectura (SELECT) de archivos en el bucket reference_audio
DROP POLICY IF EXISTS "Permitir lectura publica de reference_audio" ON storage.objects;
CREATE POLICY "Permitir lectura publica de reference_audio" 
ON storage.objects FOR SELECT TO anon 
USING (bucket_id = 'reference_audio');

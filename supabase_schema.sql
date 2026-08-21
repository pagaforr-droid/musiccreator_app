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
CREATE POLICY "Block anon on config" ON public.app_config FOR ALL TO anon USING (false);

INSERT INTO public.app_config (key, value) VALUES ('replicate_api_key', 'INSERT_YOUR_REPLICATE_API_KEY_HERE')
ON CONFLICT (key) DO NOTHING;

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
CREATE POLICY "Permitir inserts publicos" ON public.generations FOR INSERT TO anon WITH CHECK (true);
CREATE POLICY "Permitir select publicos" ON public.generations FOR SELECT TO anon USING (true);
CREATE POLICY "Permitir update publicos" ON public.generations FOR UPDATE TO anon USING (true);

-- ==============================================================================
-- RPCs (Remote Procedure Calls) - ORQUESTADOR DE WEBHOOKS
-- ==============================================================================

CREATE OR REPLACE FUNCTION get_replicate_key() RETURNS TEXT
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
    secret_key TEXT;
BEGIN
    SELECT value INTO secret_key FROM public.app_config WHERE key = 'replicate_api_key';
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

    -- Usamos el endpoint directo del modelo para no necesitar el hash de versión
    SELECT net.http_post(
        url := 'https://api.replicate.com/v1/models/cwalo/all-in-one-music-structure-analysis/predictions',
        headers := jsonb_build_object('Authorization', 'Bearer ' || api_key, 'Content-Type', 'application/json'),
        body := jsonb_build_object(
            'input', jsonb_build_object('audio', p_audio_url),
            'webhook', get_project_url() || '/rest/v1/rpc/webhook_phase_1?gen_id=' || new_gen_id,
            'webhook_events_filter', jsonb_build_array('completed')
        )
    ) INTO req_id;

    RETURN new_gen_id;
END;
$$;

-- FASE 2: Webhook Fase 1 (Llama a sakemin/musicongen)
CREATE OR REPLACE FUNCTION webhook_phase_1(payload JSONB, gen_id UUID)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
    v_bpm NUMERIC;
    v_chords JSONB;
    v_instrument TEXT;
    v_style TEXT;
    api_key TEXT;
    req_id BIGINT;
BEGIN
    -- Extraemos de forma genérica (dependerá del output exacto de cwalo)
    v_bpm := (payload->'output'->>'bpm')::NUMERIC;
    v_chords := payload->'output'->'chords';

    UPDATE public.generations 
    SET extracted_bpm = v_bpm, extracted_chords = v_chords, status = 'generating', updated_at = NOW()
    WHERE id = gen_id
    RETURNING target_instrument, target_style INTO v_instrument, v_style;

    api_key := get_replicate_key();

    SELECT net.http_post(
        url := 'https://api.replicate.com/v1/models/sakemin/musicongen/predictions',
        headers := jsonb_build_object('Authorization', 'Bearer ' || api_key, 'Content-Type', 'application/json'),
        body := jsonb_build_object(
            'input', jsonb_build_object(
                'prompt', 'Isolated ' || v_instrument || ' stem, ' || v_style || ' style. Tempo: ' || COALESCE(v_bpm::TEXT, '120') || ' bpm.',
                'chords', v_chords
            ),
            'webhook', get_project_url() || '/rest/v1/rpc/webhook_phase_2?gen_id=' || gen_id,
            'webhook_events_filter', jsonb_build_array('completed')
        )
    ) INTO req_id;

    RETURN jsonb_build_object('status', 'success');
END;
$$;

-- FASE 3: Webhook Fase 2 (Llama a lucataco/mvsep-mdx23-music-separation)
CREATE OR REPLACE FUNCTION webhook_phase_2(payload JSONB, gen_id UUID)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
    v_generated_audio TEXT;
    api_key TEXT;
    req_id BIGINT;
BEGIN
    v_generated_audio := payload->>'output';

    UPDATE public.generations SET status = 'cleaning', updated_at = NOW() WHERE id = gen_id;

    api_key := get_replicate_key();

    SELECT net.http_post(
        url := 'https://api.replicate.com/v1/models/lucataco/mvsep-mdx23-music-separation/predictions',
        headers := jsonb_build_object('Authorization', 'Bearer ' || api_key, 'Content-Type', 'application/json'),
        body := jsonb_build_object(
            'input', jsonb_build_object('audio', v_generated_audio),
            'webhook', get_project_url() || '/rest/v1/rpc/webhook_phase_3?gen_id=' || gen_id,
            'webhook_events_filter', jsonb_build_array('completed')
        )
    ) INTO req_id;

    RETURN jsonb_build_object('status', 'success');
END;
$$;

-- FASE FINAL: Webhook Fase 3
CREATE OR REPLACE FUNCTION webhook_phase_3(payload JSONB, gen_id UUID)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
    v_instrument TEXT;
    v_final_url TEXT;
BEGIN
    SELECT target_instrument INTO v_instrument FROM public.generations WHERE id = gen_id;

    IF v_instrument = 'Bajo' THEN
        v_final_url := payload->'output'->>'bass';
    ELSIF v_instrument = 'Batería' THEN
        v_final_url := payload->'output'->>'drums';
    ELSE
        v_final_url := payload->'output'->>'other';
    END IF;

    UPDATE public.generations 
    SET final_stem_url = v_final_url, status = 'completed', updated_at = NOW() 
    WHERE id = gen_id;

    RETURN jsonb_build_object('status', 'success');
END;
$$;

-- ==============================================================================
-- STORAGE SECURITY POLICIES (Fixing "new row violates row-level security policy")
-- ==============================================================================
-- Permitir subida de archivos (INSERT) al bucket reference_audio para usuarios anónimos
CREATE POLICY "Permitir subida anonima a reference_audio" 
ON storage.objects FOR INSERT TO anon 
WITH CHECK (bucket_id = 'reference_audio');

-- Permitir lectura (SELECT) de archivos en el bucket reference_audio
CREATE POLICY "Permitir lectura publica de reference_audio" 
ON storage.objects FOR SELECT TO anon 
USING (bucket_id = 'reference_audio');

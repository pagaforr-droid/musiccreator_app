-- ==============================================================================
-- SUPABASE MASTER SCRIPT - AI MUSIC GENERATOR (FIXED WEBHOOK ROUTING)
-- ==============================================================================

-- 1. Habilitar extensión pg_net para llamadas HTTP
CREATE EXTENSION IF NOT EXISTS pg_net WITH SCHEMA extensions;

-- 2. Crear tabla de configuración
CREATE TABLE IF NOT EXISTS public.app_config (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL
);

ALTER TABLE public.app_config ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Block anon on config" ON public.app_config;
CREATE POLICY "Block anon on config" ON public.app_config FOR ALL TO anon USING (false);

INSERT INTO public.app_config (key, value) VALUES ('replicate_api_key', 'INSERT_YOUR_REPLICATE_API_KEY_HERE') ON CONFLICT DO NOTHING;
INSERT INTO public.app_config (key, value) VALUES ('supabase_anon_key', 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InNqam5vdnNpdWhqZ2p0cXNxd2J0Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODczNDI1NTksImV4cCI6MjEwMjkxODU1OX0.8chAAmC2LetDjQoA1sMP9It-3nhsw2eGhuFevu3HpPE') ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;

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
    replicate_id TEXT, -- NUEVO: Guarda el ID de la prediccion de Replicate
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Si la tabla ya existía, asegurar que tenga la columna
ALTER TABLE public.generations ADD COLUMN IF NOT EXISTS replicate_id TEXT;

ALTER TABLE public.generations ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Permitir inserts publicos" ON public.generations;
CREATE POLICY "Permitir inserts publicos" ON public.generations FOR INSERT TO anon WITH CHECK (true);
DROP POLICY IF EXISTS "Permitir select publicos" ON public.generations;
CREATE POLICY "Permitir select publicos" ON public.generations FOR SELECT TO anon USING (true);
DROP POLICY IF EXISTS "Permitir update publicos" ON public.generations;
CREATE POLICY "Permitir update publicos" ON public.generations FOR UPDATE TO anon USING (true);

-- 5. Tabla de Mapeo (Conecta pg_net con Replicate)
CREATE TABLE IF NOT EXISTS public.request_mappings (
    req_id BIGINT PRIMARY KEY,
    gen_id UUID NOT NULL
);

-- ==============================================================================
-- TRIGGER PARA SINCRONIZAR IDs DE REPLICATE
-- ==============================================================================
CREATE OR REPLACE FUNCTION link_replicate_id_to_gen() RETURNS TRIGGER AS $$
DECLARE
    v_replicate_id TEXT;
    v_gen_id UUID;
BEGIN
    IF NEW.status_code = 201 OR NEW.status_code = 200 THEN
        v_replicate_id := (NEW.content::jsonb)->>'id';
        IF v_replicate_id IS NOT NULL THEN
            SELECT gen_id INTO v_gen_id FROM public.request_mappings WHERE req_id = NEW.id;
            IF v_gen_id IS NOT NULL THEN
                UPDATE public.generations SET replicate_id = v_replicate_id WHERE id = v_gen_id;
                DELETE FROM public.request_mappings WHERE req_id = NEW.id; -- Limpieza
            END IF;
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_link_replicate_id ON net._http_response;
CREATE TRIGGER trg_link_replicate_id
AFTER INSERT ON net._http_response
FOR EACH ROW EXECUTE FUNCTION link_replicate_id_to_gen();


-- ==============================================================================
-- RPCs (Remote Procedure Calls) - ORQUESTADOR DE WEBHOOKS
-- ==============================================================================
DROP FUNCTION IF EXISTS webhook_phase_1(JSONB, UUID);
DROP FUNCTION IF EXISTS webhook_phase_2(JSONB, UUID);
DROP FUNCTION IF EXISTS webhook_phase_3(JSONB, UUID);
DROP FUNCTION IF EXISTS webhook_phase_1(JSONB, TEXT, TEXT, UUID, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, JSONB, JSONB, JSONB);
DROP FUNCTION IF EXISTS webhook_phase_2(JSONB, TEXT, TEXT, UUID, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, JSONB, JSONB, JSONB);
DROP FUNCTION IF EXISTS webhook_phase_3(JSONB, TEXT, TEXT, UUID, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, JSONB, JSONB, JSONB);
DROP FUNCTION IF EXISTS webhook_phase_1(UUID, TEXT, JSONB, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, JSONB, JSONB, JSONB);
DROP FUNCTION IF EXISTS webhook_phase_2(UUID, TEXT, JSONB, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, JSONB, JSONB, JSONB);
DROP FUNCTION IF EXISTS webhook_phase_3(UUID, TEXT, JSONB, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, JSONB, JSONB, JSONB);

CREATE OR REPLACE FUNCTION get_replicate_key() RETURNS TEXT LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE secret_key TEXT; BEGIN SELECT value INTO secret_key FROM public.app_config WHERE key = 'replicate_api_key'; RETURN secret_key; END; $$;

CREATE OR REPLACE FUNCTION get_anon_key() RETURNS TEXT LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE secret_key TEXT; BEGIN SELECT value INTO secret_key FROM public.app_config WHERE key = 'supabase_anon_key'; RETURN secret_key; END; $$;

CREATE OR REPLACE FUNCTION get_project_url() RETURNS TEXT LANGUAGE plpgsql AS $$
BEGIN RETURN 'https://sjjnovsiuhjgjtqsqwbt.supabase.co'; END; $$;

-- FASE 1: Iniciar Generación
CREATE OR REPLACE FUNCTION start_generation(p_session_id UUID, p_audio_url TEXT, p_instrument TEXT, p_style TEXT)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
    new_gen_id UUID;
    req_id BIGINT;
BEGIN
    INSERT INTO public.generations (session_id, reference_audio_url, target_instrument, target_style, status)
    VALUES (p_session_id, p_audio_url, p_instrument, p_style, 'analyzing')
    RETURNING id INTO new_gen_id;

    SELECT net.http_post(
        url := 'https://api.replicate.com/v1/predictions',
        headers := jsonb_build_object('Authorization', 'Bearer ' || get_replicate_key(), 'Content-Type', 'application/json'),
        body := jsonb_build_object(
            'version', '6deeba047db17da69e9826c0285cd137cd2a81af05eb44ff496b7acd69b3a383',
            'input', jsonb_build_object('music_input', p_audio_url),
            'webhook', get_project_url() || '/rest/v1/rpc/webhook_phase_1?apikey=' || get_anon_key(),
            'webhook_events_filter', jsonb_build_array('completed')
        )
    ) INTO req_id;
    
    INSERT INTO public.request_mappings (req_id, gen_id) VALUES (req_id, new_gen_id);

    RETURN new_gen_id;
END;
$$;

-- FASE 2: Webhook Fase 1
CREATE OR REPLACE FUNCTION webhook_phase_1(payload JSONB)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
    v_gen_id UUID;
    v_bpm NUMERIC;
    v_chords JSONB;
    v_instrument TEXT;
    v_style TEXT;
    req_id BIGINT;
    v_replicate_id TEXT;
    v_status TEXT;
    v_error TEXT;
    v_output JSONB;
BEGIN
    v_replicate_id := payload->>'id';
    v_status := payload->>'status';
    v_error := payload->>'error';
    v_output := payload->'output';

    SELECT g.id INTO v_gen_id FROM public.generations g WHERE g.replicate_id = v_replicate_id;
    IF v_gen_id IS NULL THEN RETURN jsonb_build_object('status', 'error', 'msg', 'Generation not found'); END IF;

    IF v_status != 'succeeded' THEN
        UPDATE public.generations SET status = 'failed', updated_at = NOW() WHERE id = v_gen_id;
        RETURN jsonb_build_object('status', 'error', 'msg', v_error);
    END IF;

    IF jsonb_typeof(v_output) = 'object' THEN
        v_bpm := (v_output->>'bpm')::NUMERIC;
        v_chords := v_output->'chords';
    END IF;

    UPDATE public.generations 
    SET extracted_bpm = v_bpm, extracted_chords = v_chords, status = 'generating', updated_at = NOW()
    WHERE id = v_gen_id
    RETURNING target_instrument, target_style INTO v_instrument, v_style;

    SELECT net.http_post(
        url := 'https://api.replicate.com/v1/predictions',
        headers := jsonb_build_object('Authorization', 'Bearer ' || get_replicate_key(), 'Content-Type', 'application/json'),
        body := jsonb_build_object(
            'version', 'a05ec8bdf5cc902cd849077d985029ce9b05e3dfb98a2d74accc9c94fdf15747',
            'input', jsonb_build_object(
                'prompt', 'Isolated ' || v_instrument || ' stem, ' || v_style || ' style.',
                'chord_progression', COALESCE(v_chords::TEXT, 'C G A:min F'),
                'bpm', COALESCE(v_bpm, 120)
            ),
            'webhook', get_project_url() || '/rest/v1/rpc/webhook_phase_2?apikey=' || get_anon_key(),
            'webhook_events_filter', jsonb_build_array('completed')
        )
    ) INTO req_id;

    INSERT INTO public.request_mappings (req_id, gen_id) VALUES (req_id, v_gen_id);
    RETURN jsonb_build_object('status', 'success');
END;
$$;

-- FASE 3: Webhook Fase 2
CREATE OR REPLACE FUNCTION webhook_phase_2(payload JSONB)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
    v_gen_id UUID;
    v_generated_audio TEXT;
    req_id BIGINT;
    v_replicate_id TEXT;
    v_status TEXT;
    v_error TEXT;
    v_output JSONB;
BEGIN
    v_replicate_id := payload->>'id';
    v_status := payload->>'status';
    v_error := payload->>'error';
    v_output := payload->'output';

    SELECT g.id INTO v_gen_id FROM public.generations g WHERE g.replicate_id = v_replicate_id;
    IF v_gen_id IS NULL THEN RETURN jsonb_build_object('status', 'error', 'msg', 'Generation not found'); END IF;

    IF v_status != 'succeeded' THEN
        UPDATE public.generations SET status = 'failed', updated_at = NOW() WHERE id = v_gen_id;
        RETURN jsonb_build_object('status', 'error', 'msg', v_error);
    END IF;

    v_generated_audio := v_output#>>'{}';
    UPDATE public.generations SET status = 'cleaning', updated_at = NOW() WHERE id = v_gen_id;

    SELECT net.http_post(
        url := 'https://api.replicate.com/v1/predictions',
        headers := jsonb_build_object('Authorization', 'Bearer ' || get_replicate_key(), 'Content-Type', 'application/json'),
        body := jsonb_build_object(
            'version', '510b9b91aec1bfa7d634e6c06ee80c18492fb0fc06aa1474533fbda90dd3dba4',
            'input', jsonb_build_object('audio', v_generated_audio),
            'webhook', get_project_url() || '/rest/v1/rpc/webhook_phase_3?apikey=' || get_anon_key(),
            'webhook_events_filter', jsonb_build_array('completed')
        )
    ) INTO req_id;

    INSERT INTO public.request_mappings (req_id, gen_id) VALUES (req_id, v_gen_id);
    RETURN jsonb_build_object('status', 'success');
END;
$$;

-- FASE FINAL: Webhook Fase 3
CREATE OR REPLACE FUNCTION webhook_phase_3(payload JSONB)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
    v_gen_id UUID;
    v_instrument TEXT;
    v_final_url TEXT;
    v_replicate_id TEXT;
    v_status TEXT;
    v_error TEXT;
    v_output JSONB;
BEGIN
    v_replicate_id := payload->>'id';
    v_status := payload->>'status';
    v_error := payload->>'error';
    v_output := payload->'output';

    SELECT g.id INTO v_gen_id FROM public.generations g WHERE g.replicate_id = v_replicate_id;
    IF v_gen_id IS NULL THEN RETURN jsonb_build_object('status', 'error', 'msg', 'Generation not found'); END IF;

    IF v_status != 'succeeded' THEN
        UPDATE public.generations SET status = 'failed', updated_at = NOW() WHERE id = v_gen_id;
        RETURN jsonb_build_object('status', 'error', 'msg', v_error);
    END IF;

    SELECT target_instrument INTO v_instrument FROM public.generations WHERE id = v_gen_id;

    IF v_instrument = 'Bajo' THEN v_final_url := v_output->>'bass';
    ELSIF v_instrument = 'Batería' THEN v_final_url := v_output->>'drums';
    ELSE v_final_url := v_output->>'other'; END IF;

    UPDATE public.generations SET final_stem_url = v_final_url, status = 'completed', updated_at = NOW() WHERE id = v_gen_id;
    RETURN jsonb_build_object('status', 'success');
END;
$$;

-- Permisos
GRANT EXECUTE ON FUNCTION webhook_phase_1 TO anon;
GRANT EXECUTE ON FUNCTION webhook_phase_2 TO anon;
GRANT EXECUTE ON FUNCTION webhook_phase_3 TO anon;

-- Storage
DROP POLICY IF EXISTS "Permitir subida anonima a reference_audio" ON storage.objects;
CREATE POLICY "Permitir subida anonima a reference_audio" ON storage.objects FOR INSERT TO anon WITH CHECK (bucket_id = 'reference_audio');
DROP POLICY IF EXISTS "Permitir lectura publica de reference_audio" ON storage.objects;
CREATE POLICY "Permitir lectura publica de reference_audio" ON storage.objects FOR SELECT TO anon USING (bucket_id = 'reference_audio');

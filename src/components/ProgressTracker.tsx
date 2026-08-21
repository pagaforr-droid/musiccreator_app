import { useEffect, useState } from 'react';
import { supabase } from '../lib/supabase';
import { Loader2, Music4, CheckCircle2, AlertTriangle, Download, Sparkles, Terminal } from 'lucide-react';

interface ProgressTrackerProps {
  generationId: string;
}

export function ProgressTracker({ generationId }: ProgressTrackerProps) {
  const [status, setStatus] = useState<string>('pending');
  const [stemUrl, setStemUrl] = useState<string | null>(null);
  const [showDebug, setShowDebug] = useState(false);
  const [debugLogs, setDebugLogs] = useState<any[]>([]);

  const fetchLogs = async () => {
    const { data, error } = await supabase.rpc('get_system_logs');
    if (!error && data) {
      setDebugLogs(data);
    }
  };

  useEffect(() => {
    const fetchStatus = async () => {
      const { data } = await supabase
        .from('generations')
        .select('status, final_stem_url')
        .eq('id', generationId)
        .single();
      
      if (data) {
        setStatus(data.status);
        if (data.final_stem_url) setStemUrl(data.final_stem_url);
      }
    };
    fetchStatus();

    const channel = supabase.channel(`generation_${generationId}`)
      .on(
        'postgres_changes',
        { event: 'UPDATE', schema: 'public', table: 'generations', filter: `id=eq.${generationId}` },
        (payload) => {
          setStatus(payload.new.status);
          if (payload.new.final_stem_url) {
            setStemUrl(payload.new.final_stem_url);
          }
        }
      )
      .subscribe();

    return () => { supabase.removeChannel(channel); };
  }, [generationId]);

  useEffect(() => {
    if (showDebug) {
      fetchLogs();
      const interval = setInterval(fetchLogs, 3000);
      return () => clearInterval(interval);
    }
  }, [showDebug]);

  const steps = [
    { id: 'analyzing', label: 'Extracción Estructural', desc: 'Determinando BPM y mapa de acordes' },
    { id: 'generating', label: 'Síntesis Neuronal', desc: 'Generando pista en el espacio latente' },
    { id: 'cleaning', label: 'Aislamiento de Frecuencias', desc: 'Limpiando sangría acústica usando MDX23' },
    { id: 'completed', label: 'Stem Finalizado', desc: 'Renderización completada' },
  ];

  const currentIndex = status === 'failed' ? -1 : status === 'pending' ? 0 : steps.findIndex(s => s.id === status);

  if (status === 'failed') {
    return (
      <div className="max-w-2xl mx-auto bg-red-950/30 p-8 rounded-2xl border border-red-900/50 text-center backdrop-blur-xl shadow-2xl">
        <div className="w-20 h-20 bg-red-500/10 rounded-full flex items-center justify-center mx-auto mb-6">
          <AlertTriangle className="w-10 h-10 text-red-500" />
        </div>
        <h3 className="text-2xl font-bold text-red-400 mb-2">Anomalía Detectada</h3>
        <p className="text-red-300/80">El pipeline de inferencia falló o agotó su tiempo de espera. Por favor, inténtalo de nuevo.</p>
      </div>
    );
  }

  return (
    <div className="max-w-2xl mx-auto">
      <div className="bg-slate-900/80 backdrop-blur-xl p-8 md:p-10 rounded-3xl border border-slate-700/50 shadow-2xl relative overflow-hidden">
        
        {/* Animated Background Pulse */}
        <div className="absolute top-0 left-0 w-full h-1 bg-gradient-to-r from-transparent via-indigo-500 to-transparent opacity-50"></div>
        {status !== 'completed' && (
          <div className="absolute top-0 left-0 w-1/2 h-1 bg-indigo-400 animate-slide-right"></div>
        )}

        <div className="flex items-center justify-between mb-10">
          <div className="flex items-center gap-4">
            <div className="p-3 bg-indigo-500/20 rounded-xl border border-indigo-500/30">
              <Sparkles className="w-6 h-6 text-indigo-400" />
            </div>
            <div>
              <h2 className="text-2xl font-bold text-slate-100">Pipeline en Ejecución</h2>
              <p className="text-slate-400 text-sm">Monitoreo de telemetría ML</p>
            </div>
          </div>
          <button 
            onClick={() => setShowDebug(!showDebug)}
            className={`p-2 rounded-lg border transition-colors ${showDebug ? 'bg-slate-700 border-slate-500 text-white' : 'bg-slate-800/50 border-slate-700 text-slate-400 hover:text-white'}`}
            title="Detector de Bugs"
          >
            <Terminal className="w-5 h-5" />
          </button>
        </div>
        
        <div className="space-y-8 relative before:absolute before:inset-0 before:ml-[1.125rem] before:-translate-x-px md:before:mx-auto md:before:translate-x-0 before:h-full before:w-0.5 before:bg-gradient-to-b before:from-indigo-500/50 before:via-slate-700 before:to-transparent">
          {steps.map((step, index) => {
            const isPast = index < currentIndex;
            const isCurrent = index === currentIndex;
            
            return (
              <div key={step.id} className={`relative flex items-center justify-between md:justify-normal md:odd:flex-row-reverse group is-active transition-opacity duration-500 ${isPast ? 'opacity-50' : 'opacity-100'}`}>
                
                {/* Icon Marker */}
                <div className={`flex items-center justify-center w-10 h-10 rounded-full border-4 shrink-0 md:order-1 md:group-odd:-translate-x-1/2 md:group-even:translate-x-1/2 shadow-lg z-10 transition-colors duration-300
                  ${isPast ? 'bg-indigo-900 border-indigo-500/50' : 
                    isCurrent ? 'border-indigo-400 bg-indigo-500/20 text-indigo-400 shadow-[0_0_20px_-3px_rgba(99,102,241,0.5)]' : 
                    'bg-slate-900 border-slate-700 text-slate-600'}`}
                >
                  {isPast ? <CheckCircle2 className="w-5 h-5 text-indigo-400" /> : 
                   isCurrent && step.id !== 'completed' ? <Loader2 className="w-5 h-5 animate-spin" /> : 
                   <span className="w-2 h-2 rounded-full bg-slate-500"></span>}
                </div>
                
                {/* Text Card */}
                <div className={`w-[calc(100%-4rem)] md:w-[calc(50%-2.5rem)] p-4 rounded-xl border transition-all duration-300
                  ${isCurrent ? 'bg-indigo-500/10 border-indigo-500/30' : 'bg-slate-800/50 border-slate-700/50'}`}>
                  <h3 className={`font-bold text-lg mb-1 ${isCurrent ? 'text-indigo-300' : 'text-slate-300'}`}>
                    {step.label}
                  </h3>
                  <p className="text-slate-400 text-sm leading-snug">{step.desc}</p>
                </div>

              </div>
            );
          })}
        </div>

        {/* Debug Console */}
        {showDebug && (
          <div className="mt-8 bg-black/80 rounded-xl border border-slate-700 p-4 font-mono text-xs overflow-hidden">
            <div className="flex justify-between text-slate-400 mb-2 border-b border-slate-800 pb-2">
              <span>TERMINAL DE DEPURACIÓN (HTTP OUTBOUND)</span>
              <span className="flex items-center gap-2"><div className="w-2 h-2 bg-green-500 rounded-full animate-pulse"></div> EN VIVO</span>
            </div>
            <div className="space-y-3 max-h-60 overflow-y-auto">
              {debugLogs.length === 0 ? (
                <p className="text-slate-500">Esperando respuestas de red...</p>
              ) : (
                debugLogs.map((log, i) => (
                  <div key={i} className="border-l-2 border-slate-700 pl-3">
                    <div className="flex gap-2 text-slate-500">
                      <span>[{new Date(log.created_at).toLocaleTimeString()}]</span>
                      <span className={log.status_code >= 400 ? 'text-red-400' : log.status_code >= 200 ? 'text-green-400' : 'text-yellow-400'}>
                        HTTP {log.status_code || 'ERROR'}
                      </span>
                    </div>
                    {log.error_msg && <div className="text-red-400">{log.error_msg}</div>}
                    {log.response && <div className="text-indigo-300 mt-1 whitespace-pre-wrap break-all">{log.response.substring(0, 300)}{log.response.length > 300 ? '...' : ''}</div>}
                  </div>
                ))
              )}
            </div>
          </div>
        )}
      </div>

      {/* Completion Player */}
      {status === 'completed' && stemUrl && (
        <div className="mt-8 bg-slate-900/80 backdrop-blur-xl p-8 rounded-3xl border border-green-500/30 shadow-[0_0_50px_-12px_rgba(34,197,94,0.2)] text-center animate-fade-in-up">
          <div className="inline-flex items-center justify-center w-16 h-16 rounded-full bg-green-500/20 text-green-400 mb-6 border border-green-500/30">
            <Music4 className="w-8 h-8" />
          </div>
          <h3 className="text-3xl font-extrabold text-white mb-2">
            ¡Síntesis Completada!
          </h3>
          <p className="text-slate-400 mb-8">Tu pista aislada está lista para usarse en tu DAW.</p>
          
          <div className="bg-black/40 rounded-2xl p-4 mb-6">
            <audio controls className="w-full custom-audio" src={stemUrl}>
              Tu navegador no soporta audio.
            </audio>
          </div>
          
          <a 
            href={stemUrl} 
            download
            target="_blank"
            rel="noreferrer"
            className="inline-flex items-center gap-2 bg-green-600 hover:bg-green-500 text-white font-bold py-4 px-8 rounded-xl transition-all shadow-lg hover:shadow-green-500/25 hover:-translate-y-1"
          >
            <Download className="w-5 h-5" />
            Descargar Archivo WAV/MP3
          </a>
        </div>
      )}
    </div>
  );
}

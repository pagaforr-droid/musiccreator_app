import { useEffect, useState } from 'react';
import { supabase } from '../lib/supabase';
import { Loader2, Music4, CheckCircle2, AlertCircle } from 'lucide-react';

interface ProgressTrackerProps {
  generationId: string;
}

export function ProgressTracker({ generationId }: ProgressTrackerProps) {
  const [status, setStatus] = useState<string>('pending');
  const [stemUrl, setStemUrl] = useState<string | null>(null);

  useEffect(() => {
    // 1. Fetch initial status
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

    // 2. Subscribe to realtime updates
    const channel = supabase.channel(`generation_${generationId}`)
      .on(
        'postgres_changes',
        {
          event: 'UPDATE',
          schema: 'public',
          table: 'generations',
          filter: `id=eq.${generationId}`,
        },
        (payload) => {
          console.log('Realtime update:', payload.new);
          setStatus(payload.new.status);
          if (payload.new.final_stem_url) {
            setStemUrl(payload.new.final_stem_url);
          }
        }
      )
      .subscribe();

    return () => {
      supabase.removeChannel(channel);
    };
  }, [generationId]);

  const steps = [
    { id: 'analyzing', label: 'Analizando estructura musical (Tempo/Acordes)' },
    { id: 'generating', label: 'Generando pista condicional' },
    { id: 'cleaning', label: 'Aislando frecuencias y limpiando stem' },
    { id: 'completed', label: 'Completado' },
  ];

  const getCurrentStepIndex = () => {
    if (status === 'failed') return -1;
    if (status === 'pending') return 0;
    return steps.findIndex(s => s.id === status);
  };

  const currentIndex = getCurrentStepIndex();

  if (status === 'failed') {
    return (
      <div className="max-w-xl mx-auto bg-red-900/20 p-8 rounded-xl border border-red-800 text-center">
        <AlertCircle className="w-12 h-12 text-red-500 mx-auto mb-4" />
        <h3 className="text-xl font-bold text-red-400">La generación ha fallado</h3>
        <p className="text-red-300 mt-2">Ocurrió un error en el pipeline de IA.</p>
      </div>
    );
  }

  return (
    <div className="max-w-xl mx-auto bg-slate-800 p-8 rounded-xl shadow-lg border border-slate-700 mt-8">
      <h2 className="text-2xl font-bold mb-6 text-center text-slate-100">Estado de Generación</h2>
      
      <div className="space-y-6">
        {steps.map((step, index) => {
          const isPast = index < currentIndex;
          const isCurrent = index === currentIndex;
          
          return (
            <div key={step.id} className={`flex items-center gap-4 ${isPast ? 'opacity-50' : ''}`}>
              <div className={`w-10 h-10 rounded-full flex items-center justify-center shrink-0 border-2
                ${isPast ? 'bg-indigo-900 border-indigo-500' : 
                  isCurrent ? 'border-indigo-400 bg-indigo-500/20 text-indigo-400' : 
                  'border-slate-600 text-slate-500'}`}
              >
                {isPast ? <CheckCircle2 className="w-6 h-6 text-indigo-400" /> : 
                 isCurrent && step.id !== 'completed' ? <Loader2 className="w-5 h-5 animate-spin" /> : 
                 <Music4 className="w-5 h-5" />}
              </div>
              <span className={`text-lg font-medium ${isCurrent ? 'text-indigo-300' : 'text-slate-400'}`}>
                {step.label}
              </span>
            </div>
          );
        })}
      </div>

      {status === 'completed' && stemUrl && (
        <div className="mt-8 p-6 bg-slate-900 rounded-lg border border-indigo-500/30 text-center animate-fade-in">
          <h3 className="text-xl font-bold text-green-400 mb-4 flex justify-center items-center gap-2">
            <CheckCircle2 />
            ¡Tu stem está listo!
          </h3>
          <audio controls className="w-full mb-4">
            <source src={stemUrl} type="audio/wav" />
            Tu navegador no soporta el elemento de audio.
          </audio>
          <a 
            href={stemUrl} 
            download
            target="_blank"
            rel="noreferrer"
            className="inline-block bg-indigo-600 hover:bg-indigo-500 text-white font-semibold py-2 px-6 rounded-lg transition-colors"
          >
            Descargar Stem
          </a>
        </div>
      )}
    </div>
  );
}

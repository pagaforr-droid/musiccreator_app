import { useState, useCallback, type FormEvent } from 'react';
import { useDropzone } from 'react-dropzone';
import { supabase } from '../lib/supabase';
import { Upload, Music, Settings, Loader2, Sparkles, AudioLines } from 'lucide-react';

interface UploadFormProps {
  sessionId: string;
  onGenerationStart: (genId: string) => void;
}

export function UploadForm({ sessionId, onGenerationStart }: UploadFormProps) {
  const [file, setFile] = useState<File | null>(null);
  const [instrument, setInstrument] = useState('Bajo');
  const [style, setStyle] = useState('');
  const [isUploading, setIsUploading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const onDrop = useCallback((acceptedFiles: File[]) => {
    if (acceptedFiles.length > 0) {
      setFile(acceptedFiles[0]);
    }
  }, []);

  const { getRootProps, getInputProps, isDragActive } = useDropzone({
    onDrop,
    accept: {
      'audio/*': ['.mp3', '.wav', '.flac', '.m4a']
    },
    maxFiles: 1
  });

  const handleSubmit = async (e: FormEvent) => {
    e.preventDefault();
    if (!file) {
      setError('Por favor, selecciona un archivo de audio para comenzar.');
      return;
    }
    if (!style) {
      setError('El estilo es necesario para guiar a la IA.');
      return;
    }

    setIsUploading(true);
    setError(null);

    try {
      const fileExt = file.name.split('.').pop();
      const fileName = `${sessionId}_${Date.now()}.${fileExt}`;
      const { error: uploadError } = await supabase.storage
        .from('reference_audio')
        .upload(fileName, file);

      if (uploadError) throw uploadError;

      const { data: { publicUrl } } = supabase.storage
        .from('reference_audio')
        .getPublicUrl(fileName);

      const { data: genId, error: rpcError } = await supabase.rpc('start_generation', {
        p_session_id: sessionId,
        p_audio_url: publicUrl,
        p_instrument: instrument,
        p_style: style
      });

      if (rpcError) throw rpcError;

      onGenerationStart(genId);
    } catch (err: any) {
      console.error(err);
      setError(err.message || 'Error de conexión con el motor de IA.');
    } finally {
      setIsUploading(false);
    }
  };

  return (
    <div className="max-w-2xl mx-auto relative group">
      {/* Background glow effect */}
      <div className="absolute -inset-1 bg-gradient-to-r from-purple-600 to-indigo-600 rounded-2xl blur opacity-25 group-hover:opacity-40 transition duration-1000 group-hover:duration-200"></div>
      
      {/* Main Glassmorphism Card */}
      <div className="relative bg-slate-900/80 backdrop-blur-xl p-8 rounded-2xl border border-slate-700/50 shadow-2xl">
        <div className="flex items-center justify-between mb-8">
          <h2 className="text-2xl font-bold flex items-center gap-3 text-slate-100">
            <div className="p-2 bg-indigo-500/20 rounded-lg border border-indigo-500/30">
              <AudioLines className="w-6 h-6 text-indigo-400" />
            </div>
            Configuración de IA
          </h2>
        </div>
        
        <form onSubmit={handleSubmit} className="space-y-8">
          {/* Audio Dropzone */}
          <div>
            <label className="block text-sm font-semibold tracking-wide text-slate-400 uppercase mb-3">
              1. Audio Base (Referencia)
            </label>
            <div 
              {...getRootProps()} 
              className={`relative overflow-hidden border-2 border-dashed rounded-xl p-10 text-center cursor-pointer transition-all duration-300 ease-in-out
                ${isDragActive 
                  ? 'border-indigo-400 bg-indigo-500/10 scale-[1.02]' 
                  : 'border-slate-700 hover:border-indigo-500/50 hover:bg-slate-800/50'}`}
            >
              <input {...getInputProps()} />
              
              <div className="relative z-10 flex flex-col items-center justify-center">
                <div className={`p-4 rounded-full mb-4 transition-colors ${isDragActive ? 'bg-indigo-500/20' : 'bg-slate-800'}`}>
                  <Upload className={`w-8 h-8 ${isDragActive ? 'text-indigo-400' : 'text-slate-400'}`} />
                </div>
                {file ? (
                  <div className="flex flex-col items-center">
                    <p className="text-indigo-300 font-medium text-lg">{file.name}</p>
                    <p className="text-slate-500 text-sm mt-1">{(file.size / 1024 / 1024).toFixed(2)} MB</p>
                  </div>
                ) : (
                  <div>
                    <p className="text-slate-300 text-lg font-medium mb-1">
                      {isDragActive ? "Suelta el audio para analizar..." : "Arrastra tu pista aquí"}
                    </p>
                    <p className="text-slate-500 text-sm">o haz clic para explorar tus archivos</p>
                  </div>
                )}
              </div>
            </div>
          </div>

          {/* Settings Grid */}
          <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
            <div>
              <label className="block text-sm font-semibold tracking-wide text-slate-400 uppercase mb-3">
                2. Target
              </label>
              <div className="relative">
                <Music className="absolute left-4 top-1/2 -translate-y-1/2 w-5 h-5 text-slate-500" />
                <select 
                  value={instrument}
                  onChange={(e) => setInstrument(e.target.value)}
                  className="w-full bg-slate-950/50 border border-slate-700/80 rounded-xl pl-12 pr-4 py-3.5 text-slate-200 focus:ring-2 focus:ring-indigo-500 focus:border-transparent transition-all appearance-none cursor-pointer"
                >
                  <option>Bajo</option>
                  <option>Batería</option>
                  <option>Piano</option>
                  <option>Guitarra</option>
                  <option>Sintetizador</option>
                </select>
              </div>
            </div>
            <div>
              <label className="block text-sm font-semibold tracking-wide text-slate-400 uppercase mb-3">
                3. Estilo (Prompt)
              </label>
              <div className="relative">
                <Sparkles className="absolute left-4 top-1/2 -translate-y-1/2 w-5 h-5 text-slate-500" />
                <input 
                  type="text" 
                  placeholder="Ej: Dark synthwave, chillhop..."
                  value={style}
                  onChange={(e) => setStyle(e.target.value)}
                  className="w-full bg-slate-950/50 border border-slate-700/80 rounded-xl pl-12 pr-4 py-3.5 text-slate-200 focus:ring-2 focus:ring-indigo-500 focus:border-transparent transition-all placeholder:text-slate-600"
                />
              </div>
            </div>
          </div>

          {error && (
            <div className="bg-red-500/10 border border-red-500/20 text-red-400 text-sm p-4 rounded-xl flex items-start gap-3">
              <div className="w-1.5 h-1.5 rounded-full bg-red-500 mt-2"></div>
              {error}
            </div>
          )}

          {/* Submit Button */}
          <button 
            type="submit" 
            disabled={isUploading || !file || !style}
            className="w-full relative group/btn overflow-hidden rounded-xl disabled:opacity-50 disabled:cursor-not-allowed"
          >
            <div className="absolute inset-0 bg-gradient-to-r from-indigo-500 via-purple-500 to-indigo-500 bg-[length:200%_100%] animate-[gradient_2s_linear_infinite] opacity-80 group-hover/btn:opacity-100 transition-opacity"></div>
            <div className="relative flex items-center justify-center gap-3 bg-slate-900/40 backdrop-blur-sm px-6 py-4 text-white font-semibold text-lg transition-all hover:bg-transparent">
              {isUploading ? (
                <>
                  <Loader2 className="w-6 h-6 animate-spin text-indigo-200" />
                  <span>Procesando Modelos ML...</span>
                </>
              ) : (
                <>
                  <Settings className="w-6 h-6" />
                  <span>Sintetizar Stem</span>
                </>
              )}
            </div>
          </button>
        </form>
      </div>
    </div>
  );
}

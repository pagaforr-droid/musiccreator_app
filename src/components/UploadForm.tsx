import { useState, useCallback, FormEvent } from 'react';
import { useDropzone } from 'react-dropzone';
import { supabase } from '../lib/supabase';
import { Upload, Music, Settings, Loader2 } from 'lucide-react';

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
      setError('Por favor, selecciona un archivo de audio.');
      return;
    }
    if (!style) {
      setError('Por favor, ingresa el estilo musical deseado.');
      return;
    }

    setIsUploading(true);
    setError(null);

    try {
      // 1. Upload to Supabase Storage
      const fileExt = file.name.split('.').pop();
      const fileName = `${sessionId}_${Date.now()}.${fileExt}`;
      const { error: uploadError } = await supabase.storage
        .from('reference_audio')
        .upload(fileName, file);

      if (uploadError) throw uploadError;

      // 2. Get Public URL
      const { data: { publicUrl } } = supabase.storage
        .from('reference_audio')
        .getPublicUrl(fileName);

      // 3. Call start_generation RPC
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
      setError(err.message || 'Error al iniciar la generación.');
    } finally {
      setIsUploading(false);
    }
  };

  return (
    <div className="max-w-xl mx-auto bg-slate-800 p-8 rounded-xl shadow-lg border border-slate-700">
      <h2 className="text-2xl font-bold mb-6 flex items-center gap-2">
        <Music className="w-6 h-6 text-indigo-400" />
        Generar Stem Musical
      </h2>
      
      <form onSubmit={handleSubmit} className="space-y-6">
        {/* Dropzone */}
        <div>
          <label className="block text-sm font-medium text-slate-300 mb-2">Audio de Referencia</label>
          <div 
            {...getRootProps()} 
            className={`border-2 border-dashed rounded-lg p-8 text-center cursor-pointer transition-colors
              ${isDragActive ? 'border-indigo-500 bg-indigo-500/10' : 'border-slate-600 hover:border-slate-500 hover:bg-slate-700/50'}`}
          >
            <input {...getInputProps()} />
            <Upload className="w-10 h-10 mx-auto mb-4 text-slate-400" />
            {file ? (
              <p className="text-indigo-300 font-medium">{file.name}</p>
            ) : (
              <p className="text-slate-400">
                {isDragActive ? "Suelta el audio aquí..." : "Arrastra un audio, o haz clic para seleccionar"}
              </p>
            )}
          </div>
        </div>

        {/* Form Inputs */}
        <div className="grid grid-cols-2 gap-4">
          <div>
            <label className="block text-sm font-medium text-slate-300 mb-2">Instrumento a Aislar</label>
            <select 
              value={instrument}
              onChange={(e) => setInstrument(e.target.value)}
              className="w-full bg-slate-900 border border-slate-700 rounded-lg px-4 py-2 text-slate-200 focus:ring-2 focus:ring-indigo-500 focus:outline-none"
            >
              <option>Bajo</option>
              <option>Batería</option>
              <option>Piano</option>
              <option>Guitarra</option>
              <option>Sintetizador</option>
            </select>
          </div>
          <div>
            <label className="block text-sm font-medium text-slate-300 mb-2">Estilo (Prompt)</label>
            <input 
              type="text" 
              placeholder="Ej: Lo-Fi chill, 80s synthwave..."
              value={style}
              onChange={(e) => setStyle(e.target.value)}
              className="w-full bg-slate-900 border border-slate-700 rounded-lg px-4 py-2 text-slate-200 focus:ring-2 focus:ring-indigo-500 focus:outline-none"
            />
          </div>
        </div>

        {error && <div className="text-red-400 text-sm bg-red-900/20 p-3 rounded-lg border border-red-900/50">{error}</div>}

        <button 
          type="submit" 
          disabled={isUploading || !file || !style}
          className="w-full flex items-center justify-center gap-2 bg-indigo-600 hover:bg-indigo-700 disabled:bg-slate-600 disabled:cursor-not-allowed text-white font-semibold py-3 px-6 rounded-lg transition-colors"
        >
          {isUploading ? <Loader2 className="w-5 h-5 animate-spin" /> : <Settings className="w-5 h-5" />}
          {isUploading ? 'Procesando e Iniciando IA...' : 'Generar Pista Mágica'}
        </button>
      </form>
    </div>
  );
}

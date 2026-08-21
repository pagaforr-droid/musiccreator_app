import { useState, useEffect } from 'react';
import { UploadForm } from './components/UploadForm';
import { ProgressTracker } from './components/ProgressTracker';

function App() {
  const [sessionId, setSessionId] = useState<string>('');
  const [currentGenerationId, setCurrentGenerationId] = useState<string | null>(null);

  useEffect(() => {
    // Generar o recuperar sessionId anónimo
    let storedSession = localStorage.getItem('ai_music_session');
    if (!storedSession) {
      storedSession = crypto.randomUUID();
      localStorage.setItem('ai_music_session', storedSession);
    }
    setSessionId(storedSession);
  }, []);

  return (
    <div className="min-h-screen bg-slate-900 text-slate-100 py-12 px-4 sm:px-6 lg:px-8 font-sans">
      <div className="max-w-4xl mx-auto">
        
        <header className="text-center mb-12">
          <h1 className="text-4xl md:text-5xl font-extrabold text-transparent bg-clip-text bg-gradient-to-r from-indigo-400 to-purple-400 mb-4">
            AI Stem Generator
          </h1>
          <p className="text-lg text-slate-400 max-w-2xl mx-auto">
            Sube un audio de referencia. Extraeremos los acordes y el tempo mágicamente para generar un stem aislado (bajo, batería, etc.) que encaje perfecto con tu progresión.
          </p>
        </header>

        {sessionId && !currentGenerationId && (
          <UploadForm 
            sessionId={sessionId} 
            onGenerationStart={(genId) => setCurrentGenerationId(genId)} 
          />
        )}

        {currentGenerationId && (
          <div className="space-y-8 animate-fade-in">
            <ProgressTracker generationId={currentGenerationId} />
            <div className="text-center">
              <button 
                onClick={() => setCurrentGenerationId(null)}
                className="text-slate-400 hover:text-white transition-colors underline"
              >
                Generar otro stem
              </button>
            </div>
          </div>
        )}

      </div>
    </div>
  );
}

export default App;

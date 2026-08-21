import { useState, useEffect } from 'react';
import { UploadForm } from './components/UploadForm';
import { ProgressTracker } from './components/ProgressTracker';

function App() {
  const [sessionId, setSessionId] = useState<string>('');
  const [currentGenerationId, setCurrentGenerationId] = useState<string | null>(null);

  useEffect(() => {
    let storedSession = localStorage.getItem('ai_music_session');
    if (!storedSession) {
      storedSession = crypto.randomUUID();
      localStorage.setItem('ai_music_session', storedSession);
    }
    setSessionId(storedSession);
  }, []);

  return (
    <div className="min-h-screen bg-[#09090b] text-slate-100 font-sans selection:bg-indigo-500/30 overflow-x-hidden relative">
      
      {/* Abstract Background Orbs */}
      <div className="absolute top-[-20%] left-[-10%] w-[500px] h-[500px] bg-indigo-600/20 rounded-full blur-[120px] pointer-events-none"></div>
      <div className="absolute bottom-[-20%] right-[-10%] w-[600px] h-[600px] bg-purple-600/10 rounded-full blur-[150px] pointer-events-none"></div>

      <div className="relative z-10 max-w-5xl mx-auto py-16 px-4 sm:px-6 lg:px-8">
        
        {/* Header Section */}
        <header className="text-center mb-16">
          <div className="inline-flex items-center gap-2 px-3 py-1 rounded-full bg-white/5 border border-white/10 text-sm font-medium text-slate-300 mb-6 backdrop-blur-md">
            <span className="w-2 h-2 rounded-full bg-indigo-500 animate-pulse"></span>
            Replicate AI Engine v2.0
          </div>
          <h1 className="text-5xl md:text-7xl font-extrabold tracking-tight mb-6">
            Neural <span className="text-transparent bg-clip-text bg-gradient-to-r from-indigo-400 via-purple-400 to-indigo-400 animate-gradient-x">Stem</span> Synthesis
          </h1>
          <p className="text-lg md:text-xl text-slate-400 max-w-2xl mx-auto leading-relaxed">
            Sube tu progresión base. Nuestro pipeline extraerá estructuralmente el tempo y los acordes para sintetizar pistas aisladas perfectas.
          </p>
        </header>

        {/* Dynamic Content Area */}
        <div className="transition-all duration-500 ease-in-out">
          {sessionId && !currentGenerationId && (
            <div className="animate-fade-in-up">
              <UploadForm 
                sessionId={sessionId} 
                onGenerationStart={(genId) => setCurrentGenerationId(genId)} 
              />
            </div>
          )}

          {currentGenerationId && (
            <div className="animate-fade-in-up">
              <ProgressTracker generationId={currentGenerationId} />
              
              <div className="text-center mt-12">
                <button 
                  onClick={() => setCurrentGenerationId(null)}
                  className="group inline-flex items-center gap-2 text-sm text-slate-400 hover:text-white transition-colors"
                >
                  <span className="w-8 h-[1px] bg-slate-700 group-hover:bg-indigo-500 transition-colors"></span>
                  Generar nueva secuencia
                  <span className="w-8 h-[1px] bg-slate-700 group-hover:bg-indigo-500 transition-colors"></span>
                </button>
              </div>
            </div>
          )}
        </div>

      </div>
    </div>
  );
}

export default App;

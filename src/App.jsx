import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import './App.css';
import { scoreWordLocally, warmupLocalSync } from './localSync';

const STATIC_GRAY = '#2C3E50';

const SYNC_STOPS = [
  { max: 20, color: '#1a3a52', label: 'steel' },
  { max: 50, color: '#6d28d9', label: 'violet' },
  { max: 80, color: '#f59e0b', label: 'amber' },
  { max: 99, color: '#c2410c', label: 'blood' },
  { max: 100, color: '#fefce8', label: 'sync' },
];

const EMOJI_BY_LABEL = {
  steel: '🟦',
  violet: '🟪',
  amber: '🟧',
  blood: '🟥',
  sync: '⬜',
};

const COPY = {
  en: {
    menuTitle: 'Choose language',
    menuSubtitle: 'Select your gameplay language',
    english: 'English',
    hebrew: 'עברית',
    syncLabel: 'Sync',
    loadingModel: 'Loading local neural model...',
    winTitle: 'NEURAL SYNC',
    transmit: 'Transmit',
    placeholder: 'Type a word - Enter',
    inputAria: 'Transmit word',
    share: (cycles, line, url) =>
      `IKAROS 001\nSync Achieved in ${cycles} Cycles.\n${line}\nSync your mind with the machine: ${url}`,
  },
  he: {
    menuTitle: 'בחירת שפה',
    menuSubtitle: 'בחרו את שפת המשחק',
    english: 'English',
    hebrew: 'עברית',
    syncLabel: 'סנכרון',
    loadingModel: 'טוען מודל מקומי...',
    winTitle: 'סנכרון מלא',
    transmit: 'שיתוף',
    placeholder: 'הקלידו מילה - Enter',
    inputAria: 'שליחת מילה',
    share: (cycles, line, url) =>
      `IKAROS 001\nהסנכרון הושלם ב-${cycles} מהלכים.\n${line}\nסנכרנו תודעה עם המכונה: ${url}`,
  },
};

function bandForScore(score) {
  for (const s of SYNC_STOPS) {
    if (score <= s.max) return s;
  }
  return SYNC_STOPS[SYNC_STOPS.length - 1];
}

function backgroundForScore(score, hasPlayed) {
  if (!hasPlayed) return STATIC_GRAY;
  return bandForScore(score).color;
}

export default function App() {
  const [locale, setLocale] = useState(null);
  const [input, setInput] = useState('');
  const [sync, setSync] = useState(0);
  const [hasPlayed, setHasPlayed] = useState(false);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState(null);
  const [pulse, setPulse] = useState(false);
  const [neuralSync, setNeuralSync] = useState(false);
  const [cycles, setCycles] = useState(0);
  const [modelReady, setModelReady] = useState(false);
  const journeyRef = useRef([]);

  const bg = useMemo(
    () => backgroundForScore(sync, hasPlayed),
    [sync, hasPlayed]
  );
  const rtl = locale === 'he';
  const copy = locale ? COPY[locale] : null;

  const appendJourney = useCallback((score) => {
    const { label } = bandForScore(score);
    journeyRef.current = [...journeyRef.current, EMOJI_BY_LABEL[label] || '⬜'];
  }, []);

  useEffect(() => {
    let mounted = true;
    warmupLocalSync()
      .then(() => {
        if (mounted) setModelReady(true);
      })
      .catch((e) => {
        const reason =
          e && typeof e.message === 'string' && e.message.trim()
            ? e.message.trim()
            : 'Unknown error';
        if (mounted) setError(`Local model failed to load: ${reason}`);
      });
    return () => {
      mounted = false;
    };
  }, []);

  const submit = useCallback(async () => {
    const word = input.trim();
    if (!word || loading || !locale) return;

    setLoading(true);
    setError(null);
    setPulse(true);
    window.setTimeout(() => setPulse(false), 600);

    try {
      const score = await scoreWordLocally(word);
      setHasPlayed(true);
      setSync(score);
      setCycles((c) => c + 1);
      appendJourney(score);
      setInput('');
      if (score >= 100) {
        setNeuralSync(true);
      }
    } catch {
      setError('Signal lost');
    } finally {
      setLoading(false);
    }
  }, [input, loading, appendJourney, locale]);

  const onKeyDown = (e) => {
    if (e.key === 'Enter') {
      e.preventDefault();
      submit();
    }
  };

  const shareText = useMemo(() => {
    if (!locale) return '';
    const url = typeof window !== 'undefined' ? window.location.href : '';
    const line = journeyRef.current.join('');
    return COPY[locale].share(cycles, line, url);
  }, [cycles, locale, neuralSync]);

  const transmit = async () => {
    try {
      await navigator.clipboard.writeText(shareText);
    } catch {
      const ta = document.createElement('textarea');
      ta.value = shareText;
      document.body.appendChild(ta);
      ta.select();
      document.execCommand('copy');
      document.body.removeChild(ta);
    }
  };

  return (
    <div
      className={`app ${sync >= 81 ? 'app--hot' : ''} ${rtl ? 'app--rtl' : 'app--ltr'}`}
      dir={rtl ? 'rtl' : 'ltr'}
    >
      <div
        className={`canvas-bg ${pulse ? 'canvas-bg--pulse' : ''} ${neuralSync ? 'canvas-bg--neural' : ''}`}
        style={{ '--canvas-bg': bg }}
        aria-hidden
      />

      {!locale ? (
        <div className="language-menu">
          <p className="language-menu__title">{COPY.en.menuTitle}</p>
          <p className="language-menu__subtitle">{COPY.en.menuSubtitle}</p>
          <div className="language-menu__actions">
            <button type="button" className="language-menu__button" onClick={() => setLocale('en')}>
              {COPY.en.english}
            </button>
            <button type="button" className="language-menu__button" onClick={() => setLocale('he')}>
              {COPY.he.hebrew}
            </button>
          </div>
        </div>
      ) : null}

      <div className="sync-hud" aria-live="polite">
        {hasPlayed ? (
          <>
            <span className="sync-hud__label">{copy.syncLabel}</span>
            <span className="sync-hud__value">{sync}%</span>
          </>
        ) : null}
      </div>

      {error ? <div className="toast">{error}</div> : null}
      {!modelReady && !error ? <div className="toast">{copy ? copy.loadingModel : COPY.en.loadingModel}</div> : null}

      {neuralSync ? (
        <div className="win-layer" role="status">
          <p className="win-layer__title">{copy.winTitle}</p>
          <button type="button" className="transmit" onClick={transmit}>
            {copy.transmit}
          </button>
        </div>
      ) : null}

      <div className="dock">
        <input
          className={`zero-input ${rtl ? 'zero-input--rtl' : 'zero-input--ltr'}`}
          type="text"
          autoComplete="off"
          autoCorrect="off"
          spellCheck={false}
          placeholder={copy ? copy.placeholder : COPY.en.placeholder}
          value={input}
          disabled={loading || neuralSync || !locale}
          autoFocus
          onChange={(e) => setInput(e.target.value)}
          onKeyDown={onKeyDown}
          aria-label={copy ? copy.inputAria : COPY.en.inputAria}
        />
      </div>
    </div>
  );
}

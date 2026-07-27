import { createContext, ReactNode, useContext, useState } from 'react';
import { surfaces, ThemeMode } from './theme';

// App-wide dark/light mode for themed screens. Toggled from the home header.

const ThemeContext = createContext<{
  mode: ThemeMode;
  toggle: () => void;
  p: (typeof surfaces)[ThemeMode];
}>({ mode: 'light', toggle: () => {}, p: surfaces.light });

export function ThemeProvider({ children }: { children: ReactNode }) {
  const [mode, setMode] = useState<ThemeMode>('light'); // 라이트 통일 — 나이트 러너 테마는 전 화면 완성 후
  return (
    <ThemeContext.Provider
      value={{ mode, toggle: () => setMode((m) => (m === 'dark' ? 'light' : 'dark')), p: surfaces[mode] }}
    >
      {children}
    </ThemeContext.Provider>
  );
}

export function useTheme() {
  return useContext(ThemeContext);
}

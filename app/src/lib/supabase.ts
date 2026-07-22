import AsyncStorage from '@react-native-async-storage/async-storage';
import { createClient } from '@supabase/supabase-js';

// Set these in .env (see .env.example). EXPO_PUBLIC_ vars are inlined at build time.
const url = process.env.EXPO_PUBLIC_SUPABASE_URL;
const anonKey = process.env.EXPO_PUBLIC_SUPABASE_ANON_KEY;

if (!url || !anonKey) {
  console.warn('Supabase env vars missing — copy .env.example to .env and fill them in.');
}

export const supabase = createClient(url ?? '', anonKey ?? '', {
  auth: {
    storage: AsyncStorage, // 세션이 앱 재시작에도 유지
    autoRefreshToken: true,
    persistSession: true,
    detectSessionInUrl: false, // RN — URL 세션 감지 없음
    flowType: 'pkce', // 카카오 OAuth 코드 교환용
  },
});

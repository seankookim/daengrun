import { createClient } from '@supabase/supabase-js';

// Set these in .env (see .env.example). EXPO_PUBLIC_ vars are inlined at build time.
const url = process.env.EXPO_PUBLIC_SUPABASE_URL;
const anonKey = process.env.EXPO_PUBLIC_SUPABASE_ANON_KEY;

if (!url || !anonKey) {
  console.warn('Supabase env vars missing — copy .env.example to .env and fill them in.');
}

export const supabase = createClient(url ?? '', anonKey ?? '');

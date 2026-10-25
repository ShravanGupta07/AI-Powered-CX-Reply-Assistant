import { createClient } from '@supabase/supabase-js';

const rawUrl = (process.env.NEXT_PUBLIC_SUPABASE_URL || '').trim();
const rawKey = (process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY || '').trim();

// Strip any accidental /rest/v1 or trailing slashes added by user
const cleanUrl = rawUrl.replace(/\/rest\/v1\/?$/i, '').replace(/\/+$/, '');
const isValidUrl = cleanUrl.startsWith('http://') || cleanUrl.startsWith('https://');
const supabaseUrl = isValidUrl ? cleanUrl : 'https://placeholder.supabase.co';
const supabaseKey = rawKey && rawKey !== 'your_supabase_anon_key' ? rawKey : 'dummy-anon-key';

export const isSupabaseConfigured = Boolean(
  isValidUrl &&
  !cleanUrl.includes('your_supabase_project_url') &&
  rawKey &&
  rawKey !== 'your_supabase_anon_key'
);

export const supabase = createClient(supabaseUrl, supabaseKey);
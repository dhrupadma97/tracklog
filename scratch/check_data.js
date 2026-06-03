const { createClient } = require('@supabase/supabase-js');
const fs = require('fs');

const env = JSON.parse(fs.readFileSync('env.json', 'utf8'));
const supabase = createClient(env.SUPABASE_URL, env.SUPABASE_ANON_KEY);

async function run() {
  console.log('Signing in as admin...');
  const { error: authError } = await supabase.auth.signInWithPassword({
    email: 'dhrupad_ma@goodyear.com',
    password: 'Dm@nikon12345',
  });
  if (authError) {
    console.error('Failed to sign in:', authError);
    return;
  }
  
  console.log('Checking database content...');
  
  const { data: sessions, error: errorSessions } = await supabase.from('engineer_sessions').select('count', { count: 'exact' });
  console.log('Sessions count:', errorSessions ? errorSessions : sessions);

  const { data: rates, error: errorRates } = await supabase.from('track_rates').select('count', { count: 'exact' });
  console.log('Rates count:', errorRates ? errorRates : rates);

  const { data: invoices, error: errorInvoices } = await supabase.from('monthly_invoices').select('count', { count: 'exact' });
  console.log('Invoices count:', errorInvoices ? errorInvoices : invoices);
}

run();


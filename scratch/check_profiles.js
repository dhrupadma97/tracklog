const { createClient } = require('@supabase/supabase-js');
const fs = require('fs');

const env = JSON.parse(fs.readFileSync('env.json', 'utf8'));
const supabase = createClient(env.SUPABASE_URL, env.SUPABASE_ANON_KEY);

async function run() {
  console.log('Fetching profiles...');
  const { data, error } = await supabase
    .from('engineer_profiles')
    .select('*');

  if (error) {
    console.error('Error fetching profiles:', error);
  } else {
    console.log('Profiles in database:', data);
  }
}

run();

const { createClient } = require('@supabase/supabase-js');
const fs = require('fs');

const env = JSON.parse(fs.readFileSync('env.json', 'utf8'));
const supabase = createClient(env.SUPABASE_URL, env.SUPABASE_ANON_KEY);

async function run() {
  const email = 'dhrupad_ma@goodyear.com';
  const password = 'Dm@nikon12345';
  
  console.log(`Signing up admin: ${email}...`);
  const { data, error } = await supabase.auth.signUp({
    email,
    password,
    options: {
      data: {
        engineer_name: 'Dhrupad Mullath Anilkumar',
        engineer_id: 'GY-ENG-000',
        department: 'Tyre Testing',
      }
    }
  });

  if (error) {
    console.error('Signup error:', error);
  } else {
    console.log('Signup successful!', data);
  }
}

run();

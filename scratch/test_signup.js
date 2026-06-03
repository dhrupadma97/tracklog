const { createClient } = require('@supabase/supabase-js');
const fs = require('fs');

const env = JSON.parse(fs.readFileSync('env.json', 'utf8'));
const supabase = createClient(env.SUPABASE_URL, env.SUPABASE_ANON_KEY);

async function test() {
  const email = 'test_new_123@goodyear.com';
  const password = 'Dm@nikon12345';
  
  console.log(`Signing up fresh user: ${email}...`);
  const { data, error } = await supabase.auth.signUp({
    email,
    password,
    options: {
      data: {
        engineer_name: 'Fresh Test',
        engineer_id: 'GY-ENG-FRESH',
      }
    }
  });

  if (error) {
    console.error('Signup error:', error);
  } else {
    console.log('Signup successful!', data);
  }
}

test();

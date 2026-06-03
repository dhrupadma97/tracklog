const { createClient } = require('@supabase/supabase-js');
const fs = require('fs');

const env = JSON.parse(fs.readFileSync('env.json', 'utf8'));

const supabase = createClient(env.SUPABASE_URL, env.SUPABASE_ANON_KEY);

async function run() {
  const email = 'dhrupad_ma@goodyear.com';
  const password = 'Dm@nikon12345';
  const name = 'Dhrupad Mullath Anilkumar';
  const engineerId = 'GY-ENG-000';

  console.log(`Attempting to sign up admin: ${email}...`);
  
  const { data, error } = await supabase.auth.signUp({
    email,
    password,
    options: {
      data: {
        engineer_name: name,
        engineer_id: engineerId,
        department: 'Tyre Testing',
      }
    }
  });

  if (error) {
    if (error.message.includes('already registered') || error.message.includes('already exists')) {
      console.log('User already registered. Attempting to sign in and verify...');
      const { data: signInData, error: signInError } = await supabase.auth.signInWithPassword({
        email,
        password,
      });
      if (signInError) {
        console.error('Error signing in:', signInError);
        return;
      }
      console.log('Sign in successful. User ID:', signInData.user.id);
      
      // Update profile
      const { error: updateError } = await supabase
        .from('engineer_profiles')
        .update({
          engineer_name: name,
          engineer_id: engineerId,
          user_role: 'engineer', // Admin role in the app
        })
        .eq('id', signInData.user.id);

      if (updateError) {
        console.error('Error updating profile:', updateError);
      } else {
        console.log('Profile updated successfully!');
      }
    } else {
      console.error('Sign up error:', error);
    }
  } else {
    console.log('Sign up successful! User ID:', data.user.id);
    // Standard signup trigger handle_new_engineer handles the profile insert
    // Let's sign in to update user_role if needed
    const { data: signInData, error: signInError } = await supabase.auth.signInWithPassword({
      email,
      password,
    });
    if (!signInError) {
      await supabase
        .from('engineer_profiles')
        .update({
          user_role: 'engineer',
        })
        .eq('id', signInData.user.id);
      console.log('Admin profile initialized successfully!');
    }
  }
}

run();

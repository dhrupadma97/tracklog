import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseService {
  static SupabaseService? _instance;
  static SupabaseService get instance => _instance ??= SupabaseService._();

  SupabaseService._();

  static const String _envUrl = String.fromEnvironment('SUPABASE_URL');
  static const String supabaseUrl = _envUrl != '' ? _envUrl : 'https://qmcsxfqizvjbzffbrakp.supabase.co';

  static const String _envKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  static const String supabaseAnonKey = _envKey != '' ? _envKey : 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InFtY3N4ZnFpenZqYnpmZmJyYWtwIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzkyNzI1NjgsImV4cCI6MjA5NDg0ODU2OH0.3zWXIpO4Ruyk25LG9JS1hQwAE5Q2uLe7BKSJyV-eZ7c';

  // Initialize Supabase - call this in main()
  static Future<void> initialize() async {
    if (supabaseUrl.isEmpty || supabaseAnonKey.isEmpty) {
      throw Exception(
        'SUPABASE_URL and SUPABASE_ANON_KEY must be defined using --dart-define.',
      );
    }

    await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);
  }

  // Get Supabase client
  SupabaseClient get client => Supabase.instance.client;
}

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../routes/app_routes.dart';
import '../../services/supabase_service.dart';
import '../../theme/app_theme.dart';

/// Where a "reset your password" email link lands.
///
/// Before this screen the link was a dead end. It signed the user in and
/// dropped them on the dashboard, and the only way to change a password was
/// Settings, which asks for the CURRENT one — the very thing they had
/// forgotten. Supabase's recovery session is the proof of identity here, so
/// no current password is asked for.
class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key});

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _passCtrl = TextEditingController();
  final _confCtrl = TextEditingController();
  bool _obscurePass = true, _obscureConf = true;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _passCtrl.dispose();
    _confCtrl.dispose();
    super.dispose();
  }

  String get _email =>
      SupabaseService.instance.client.auth.currentUser?.email ?? '';

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await SupabaseService.instance.client.auth
          .updateUser(UserAttributes(password: _passCtrl.text));
      // Cleared only after the write succeeds, so a failed save leaves the
      // user on this screen rather than locked out of both passwords.
      clearPasswordRecovery();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Password changed. You are signed in.',
            style: GoogleFonts.spaceGrotesk(
                color: Colors.white, fontWeight: FontWeight.w600)),
        backgroundColor: AppTheme.success,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ));
      context.go(AppRoutes.projectSelection);
    } on AuthException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error =
          'Could not change the password. The link may have expired — '
          'ask for a new one from the sign-in page.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Leaves without setting a password. The recovery session is signed out so
  /// a half-finished reset cannot leave someone signed in on a shared machine.
  Future<void> _cancel() async {
    clearPasswordRecovery();
    await SupabaseService.instance.client.auth.signOut();
    if (mounted) context.go(AppRoutes.login);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF060B1A),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      width: 52, height: 52,
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withAlpha(25),
                        borderRadius: BorderRadius.circular(16),
                        border:
                            Border.all(color: AppTheme.primary.withAlpha(70)),
                      ),
                      child: const Icon(Icons.lock_reset_rounded,
                          color: AppTheme.primary, size: 26),
                    ),
                    const SizedBox(height: 18),
                    Text('Choose a new password',
                        style: GoogleFonts.spaceGrotesk(
                            fontSize: 21,
                            fontWeight: FontWeight.w800,
                            color: Colors.white)),
                    const SizedBox(height: 6),
                    Text(
                      _email.isEmpty
                          ? 'Set a password and you are back in.'
                          : 'For $_email. Set a password and you are back in.',
                      style: GoogleFonts.spaceGrotesk(
                          fontSize: 13,
                          height: 1.45,
                          color: const Color(0xFF9AA3BE)),
                    ),
                    const SizedBox(height: 22),
                    _passwordField(
                      controller: _passCtrl,
                      label: 'New password',
                      obscure: _obscurePass,
                      onToggle: () =>
                          setState(() => _obscurePass = !_obscurePass),
                      validator: (v) {
                        if (v == null || v.isEmpty) {
                          return 'Enter a new password';
                        }
                        if (v.length < 8) {
                          return 'Use at least 8 characters';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    _passwordField(
                      controller: _confCtrl,
                      label: 'Type it again',
                      obscure: _obscureConf,
                      onToggle: () =>
                          setState(() => _obscureConf = !_obscureConf),
                      validator: (v) => v == _passCtrl.text
                          ? null
                          : 'The two passwords do not match',
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppTheme.error.withAlpha(25),
                          borderRadius: BorderRadius.circular(10),
                          border:
                              Border.all(color: AppTheme.error.withAlpha(70)),
                        ),
                        child: Text(_error!,
                            style: GoogleFonts.spaceGrotesk(
                                fontSize: 12.5,
                                height: 1.4,
                                color: AppTheme.error)),
                      ),
                    ],
                    const SizedBox(height: 22),
                    SizedBox(
                      height: 50,
                      child: ElevatedButton(
                        onPressed: _saving ? null : _save,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primary,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor:
                              AppTheme.primary.withAlpha(80),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                          elevation: 0,
                        ),
                        child: _saving
                            ? const SizedBox(
                                width: 20, height: 20,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                        Colors.white)))
                            : Text('Save new password',
                                style: GoogleFonts.spaceGrotesk(
                                    fontSize: 14.5,
                                    fontWeight: FontWeight.w700)),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextButton(
                      onPressed: _saving ? null : _cancel,
                      child: Text('Cancel and sign out',
                          style: GoogleFonts.spaceGrotesk(
                              fontSize: 13, color: const Color(0xFF9AA3BE))),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _passwordField({
    required TextEditingController controller,
    required String label,
    required bool obscure,
    required VoidCallback onToggle,
    required String? Function(String?) validator,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscure,
      validator: validator,
      style: GoogleFonts.spaceGrotesk(color: Colors.white, fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: GoogleFonts.spaceGrotesk(
            color: const Color(0xFF9AA3BE), fontSize: 13),
        filled: true,
        fillColor: Colors.white.withAlpha(12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white.withAlpha(26)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white.withAlpha(26)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppTheme.primary),
        ),
        suffixIcon: IconButton(
          icon: Icon(
              obscure
                  ? Icons.visibility_outlined
                  : Icons.visibility_off_outlined,
              size: 19,
              color: const Color(0xFF9AA3BE)),
          onPressed: onToggle,
        ),
      ),
    );
  }
}

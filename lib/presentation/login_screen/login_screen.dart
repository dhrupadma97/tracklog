import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../theme/app_theme.dart';
import '../../services/engineer_auth_service.dart';
import '../../routes/app_routes.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _idController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isLoading = false;
  bool _isSignUp = false;
  bool _obscurePassword = true;
  String? _errorMessage;
  final bool _resetEmailSent = false;

  late AnimationController _bgAnimController;
  late AnimationController _cardAnimController;
  late Animation<double> _cardSlideAnim;
  late Animation<double> _cardFadeAnim;
  late Animation<double> _bgPulseAnim;

  @override
  void initState() {
    super.initState();
    _bgAnimController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat(reverse: true);

    _bgPulseAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _bgAnimController, curve: Curves.easeInOut),
    );

    _cardAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _cardSlideAnim = Tween<double>(begin: 60.0, end: 0.0).animate(
      CurvedAnimation(parent: _cardAnimController, curve: Curves.easeOutCubic),
    );
    _cardFadeAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _cardAnimController,
        curve: const Interval(0.0, 0.7, curve: Curves.easeOut),
      ),
    );
    _cardAnimController.forward();
  }

  @override
  void dispose() {
    _bgAnimController.dispose();
    _cardAnimController.dispose();
    _nameController.dispose();
    _idController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      if (_isSignUp) {
        await EngineerAuthService.instance.signUp(
          engineerName: _nameController.text.trim(),
          engineerId: _idController.text.trim().toUpperCase(),
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );
      } else {
        await EngineerAuthService.instance.signIn(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );
      }
      if (mounted) {
        if (kIsWeb) {
          context.go('/session-history-screen');
        } else {
          context.go('/active-session-screen');
        }
      }
    } on AuthException catch (e) {
      setState(() => _errorMessage = e.message);
    } catch (e) {
      setState(
        () => _errorMessage = 'An unexpected error occurred. Please try again.',
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _showForgotPasswordDialog() async {
    final resetEmailController = TextEditingController();
    bool isSending = false;
    String? dialogError;
    bool emailSent = false;

    await showDialog(
      context: context,
      barrierColor: Colors.black.withAlpha(160),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return Dialog(
              backgroundColor: const Color(0xFF0A1025),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20.0),
                side: BorderSide(color: Colors.white.withAlpha(20)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFF00F3FF).withAlpha(25),
                            borderRadius: BorderRadius.circular(10.0),
                          ),
                          child: const Icon(
                            Icons.lock_reset_rounded,
                            color: Color(0xFF00F3FF),
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Reset Password',
                            style: GoogleFonts.spaceGrotesk(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        GestureDetector(
                          onTap: () => Navigator.of(ctx).pop(),
                          child: Icon(
                            Icons.close_rounded,
                            color: Colors.white.withAlpha(120),
                            size: 20,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (!emailSent) ...[
                      Text(
                        'Enter your registered email address and we\'ll send you a password reset link.',
                        style: GoogleFonts.spaceGrotesk(
                          fontSize: 13,
                          color: Colors.white.withAlpha(140),
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 18),
                      TextField(
                        controller: resetEmailController,
                        keyboardType: TextInputType.emailAddress,
                        style: GoogleFonts.spaceGrotesk(
                          color: const Color(0xFFdfe2f0),
                          fontSize: 14,
                        ),
                        decoration: InputDecoration(
                          hintText: 'engineer@goodyear.com',
                          hintStyle: GoogleFonts.spaceGrotesk(
                            color: const Color(0xFF6B7490),
                            fontSize: 13,
                          ),
                          prefixIcon: const Icon(
                            Icons.email_outlined,
                            color: Color(0xFF6B7490),
                            size: 20,
                          ),
                          filled: true,
                          fillColor: Colors.white.withAlpha(10),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: Colors.white.withAlpha(20),
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: Colors.white.withAlpha(20),
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(
                              color: Color(0xFF00F3FF),
                              width: 1.5,
                            ),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                        ),
                      ),
                      if (dialogError != null) ...[
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.error.withAlpha(25),
                            borderRadius: BorderRadius.circular(8.0),
                            border: Border.all(
                              color: AppTheme.error.withAlpha(70),
                            ),
                          ),
                          child: Text(
                            dialogError!,
                            style: GoogleFonts.spaceGrotesk(
                              color: AppTheme.error,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 20),
                      SizedBox(
                        height: 48,
                        child: ElevatedButton(
                          onPressed: isSending
                              ? null
                              : () async {
                                  final email = resetEmailController.text
                                      .trim();
                                  if (email.isEmpty || !email.contains('@')) {
                                    setDialogState(
                                      () => dialogError =
                                          'Please enter a valid email address.',
                                    );
                                    return;
                                  }
                                  setDialogState(() {
                                    isSending = true;
                                    dialogError = null;
                                  });
                                  try {
                                    await Supabase.instance.client.auth
                                        .resetPasswordForEmail(
                                          email,
                                          redirectTo:
                                              'https://tracklog4686.builtwithrocket.new',
                                        );
                                    setDialogState(() {
                                      emailSent = true;
                                      isSending = false;
                                    });
                                  } on AuthException catch (e) {
                                    setDialogState(() {
                                      dialogError = e.message;
                                      isSending = false;
                                    });
                                  } catch (_) {
                                    setDialogState(() {
                                      dialogError =
                                          'Failed to send reset email. Please try again.';
                                      isSending = false;
                                    });
                                  }
                                },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF00F3FF),
                            foregroundColor: Colors.white,
                            disabledBackgroundColor: const Color(
                              0xFF00F3FF,
                            ).withAlpha(80),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12.0),
                            ),
                            elevation: 0,
                          ),
                          child: isSending
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      Colors.white,
                                    ),
                                  ),
                                )
                              : Text(
                                  'Send Reset Link',
                                  style: GoogleFonts.spaceGrotesk(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                        ),
                      ),
                    ] else ...[
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppTheme.success.withAlpha(20),
                          borderRadius: BorderRadius.circular(12.0),
                          border: Border.all(
                            color: AppTheme.success.withAlpha(60),
                          ),
                        ),
                        child: Column(
                          children: [
                            const Icon(
                              Icons.mark_email_read_outlined,
                              color: AppTheme.success,
                              size: 36,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Reset link sent!',
                              style: GoogleFonts.spaceGrotesk(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.success,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Check your inbox at ${resetEmailController.text.trim()} and follow the link to reset your password.',
                              style: GoogleFonts.spaceGrotesk(
                                fontSize: 12,
                                color: Colors.white.withAlpha(160),
                                height: 1.5,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextButton(
                        onPressed: () => Navigator.of(ctx).pop(),
                        child: Text(
                          'Back to Sign In',
                          style: GoogleFonts.spaceGrotesk(
                            color: const Color(0xFF00F3FF),
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        );
      },
    );
    resetEmailController.dispose();
  }

  void _toggleMode() {
    setState(() {
      _isSignUp = !_isSignUp;
      _errorMessage = null;
    });
    _cardAnimController.reset();
    _cardAnimController.forward();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: const Color(0xFF050811),
      body: Stack(
        children: [
          // ── Background: aerial track image ──────────────────────────
          Positioned.fill(
            child: Image.asset(
              'assets/images/GYRacing_DesktopTeamsWallpaper_5-1779284234231.png',
              fit: BoxFit.cover,
              semanticLabel:
                  'Goodyear racing team wallpaper with race cars on track',
              errorBuilder: (_, __, ___) =>
                  Container(color: const Color(0xFF050811)),
            ),
          ),

          // ── Multi-layer dark gradient overlay ───────────────────────
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _bgPulseAnim,
              builder: (context, _) {
                return Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      stops: const [0.0, 0.35, 0.65, 1.0],
                      colors: [
                        const Color(0xFF050811).withAlpha(200),
                        const Color(0xFF050811).withAlpha(140),
                        const Color(0xFF050811).withAlpha(210),
                        const Color(0xFF050811).withAlpha(255),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),

          // ── Animated accent glow (NATRAX orange) ────────────────────
          Positioned(
            top: -80,
            right: -60,
            child: AnimatedBuilder(
              animation: _bgPulseAnim,
              builder: (context, _) {
                return Container(
                  width: 320,
                  height: 320,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        const Color(
                          0xFF00F3FF,
                        ).withAlpha((30 + (_bgPulseAnim.value * 20)).toInt()),
                        Colors.transparent,
                      ],
                    ),
                  ),
                );
              },
            ),
          ),

          // ── Teal accent glow (bottom left) ──────────────────────────
          Positioned(
            bottom: size.height * 0.25,
            left: -80,
            child: AnimatedBuilder(
              animation: _bgPulseAnim,
              builder: (context, _) {
                return Container(
                  width: 260,
                  height: 260,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        AppTheme.primary.withAlpha(
                          (20 + (_bgPulseAnim.value * 15)).toInt(),
                        ),
                        Colors.transparent,
                      ],
                    ),
                  ),
                );
              },
            ),
          ),

          // ── NATRAX orange top accent bar ────────────────────────────
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              height: 3,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Color(0xFF00F3FF),
                    Color(0xFF7000FF),
                    Color(0xFF00F3FF),
                  ],
                ),
              ),
            ),
          ),

          // ── Main scrollable content ──────────────────────────────────
          SafeArea(
            child: AnimatedBuilder(
              animation: _cardAnimController,
              builder: (context, child) {
                return Transform.translate(
                  offset: Offset(0, _cardSlideAnim.value),
                  child: Opacity(opacity: _cardFadeAnim.value, child: child),
                );
              },
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 20,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 16),

                    // ── Header branding ──────────────────────────────
                    _buildHeader(),

                    const SizedBox(height: 36),

                    // ── Track stats strip ────────────────────────────
                    _buildTrackStatsStrip(),

                    const SizedBox(height: 32),

                    // ── Login card ───────────────────────────────────
                    _buildLoginCard(),

                    const SizedBox(height: 20),

                    // ── Toggle sign-in / sign-up ─────────────────────
                    _buildToggleRow(),

                    const SizedBox(height: 24),

                    // ── Demo credentials ─────────────────────────────
                    _buildDemoCredentials(),

                    const SizedBox(height: 32),

                    // ── Footer ───────────────────────────────────────
                    _buildFooter(),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Header ────────────────────────────────────────────────────────────
  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Logos row
        Row(
          children: [
            // NATRAX badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF00F3FF),
                borderRadius: BorderRadius.circular(6.0),
              ),
              child: Text(
                'NATRAX',
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  letterSpacing: 1.5,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Container(width: 1, height: 28, color: Colors.white.withAlpha(40)),
            const SizedBox(width: 10),
            // Goodyear logo pill
            Container(
              height: 36,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(6.0),
              ),
              child: Image.asset(
                'assets/images/goodyear-sightline-logo-single-black-1779279917234.png',
                fit: BoxFit.contain,
                semanticLabel:
                    'Goodyear SightLine logo — black text on white background',
              ),
            ),
          ],
        ),

        const SizedBox(height: 20),

        // Main title
        RichText(
          text: TextSpan(
            children: [
              TextSpan(
                text: 'Track',
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 32,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  height: 1.1,
                ),
              ),
              TextSpan(
                text: 'Log',
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 32,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF00F3FF),
                  height: 1.1,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Proving Ground Session Management',
          style: GoogleFonts.spaceGrotesk(
            fontSize: 13,
            fontWeight: FontWeight.w400,
            color: Colors.white.withAlpha(160),
            letterSpacing: 0.3,
          ),
        ),
      ],
    );
  }

  // ── Track stats strip ─────────────────────────────────────────────────
  Widget _buildTrackStatsStrip() {
    return Row(
      children: [
        _statChip('14', 'Test Tracks'),
        const SizedBox(width: 10),
        _statChip('3,000', 'Acres'),
        const SizedBox(width: 10),
        _statChip('16', 'Track Types'),
      ],
    );
  }

  Widget _statChip(String value, String label) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withAlpha(10),
          borderRadius: BorderRadius.circular(10.0),
          border: Border.all(color: Colors.white.withAlpha(20)),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: GoogleFonts.spaceGrotesk(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF00F3FF),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: GoogleFonts.spaceGrotesk(
                fontSize: 10,
                fontWeight: FontWeight.w500,
                color: Colors.white.withAlpha(120),
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Login card ────────────────────────────────────────────────────────
  Widget _buildLoginCard() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0A1025).withAlpha(230),
        borderRadius: BorderRadius.circular(20.0),
        border: Border.all(color: Colors.white.withAlpha(18)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(100),
            blurRadius: 40,
            offset: const Offset(0, 20),
          ),
          BoxShadow(
            color: const Color(0xFF00F3FF).withAlpha(15),
            blurRadius: 60,
            offset: const Offset(0, 0),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Card header tab
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: Colors.white.withAlpha(12)),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 3,
                  height: 18,
                  decoration: BoxDecoration(
                    color: const Color(0xFF00F3FF),
                    borderRadius: BorderRadius.circular(2.0),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  _isSignUp ? 'Create Engineer Profile' : 'Engineer Sign In',
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withAlpha(25),
                    borderRadius: BorderRadius.circular(6.0),
                    border: Border.all(color: AppTheme.primary.withAlpha(60)),
                  ),
                  child: Text(
                    'SECURE',
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.primary,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Form body
          Padding(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_isSignUp) ...[
                    _buildLabel('Full Name'),
                    const SizedBox(height: 8),
                    _buildTextField(
                      controller: _nameController,
                      hint: 'e.g. Arjun Sharma',
                      icon: Icons.person_outline_rounded,
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? 'Please enter your full name'
                          : null,
                    ),
                    const SizedBox(height: 18),
                    _buildLabel('Engineer ID'),
                    const SizedBox(height: 8),
                    _buildTextField(
                      controller: _idController,
                      hint: 'e.g. GY-ENG-001',
                      icon: Icons.badge_outlined,
                      textCapitalization: TextCapitalization.characters,
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? 'Please enter your engineer ID'
                          : null,
                    ),
                    const SizedBox(height: 18),
                  ],

                  _buildLabel('Email Address'),
                  const SizedBox(height: 8),
                  _buildTextField(
                    controller: _emailController,
                    hint: 'engineer@goodyear.com',
                    icon: Icons.email_outlined,
                    keyboardType: TextInputType.emailAddress,
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) {
                        return 'Please enter your email';
                      }
                      if (!v.contains('@')) return 'Enter a valid email';
                      return null;
                    },
                  ),
                  const SizedBox(height: 18),

                  _buildLabel('Password'),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    style: GoogleFonts.spaceGrotesk(
                      color: const Color(0xFFdfe2f0),
                      fontSize: 14,
                    ),
                    decoration: _inputDecoration(
                      hint: _isSignUp
                          ? 'Create a password'
                          : 'Enter your password',
                      icon: Icons.lock_outline_rounded,
                      suffix: IconButton(
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                          color: const Color(0xFF6B7490),
                          size: 20,
                        ),
                        onPressed: () => setState(
                          () => _obscurePassword = !_obscurePassword,
                        ),
                      ),
                    ),
                    validator: (v) {
                      if (v == null || v.isEmpty) {
                        return 'Please enter your password';
                      }
                      if (_isSignUp && v.length < 8) {
                        return 'Password must be at least 8 characters';
                      }
                      return null;
                    },
                  ),

                  // ── Forgot password link (sign-in mode only) ──────────
                  if (!_isSignUp) ...[
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: GestureDetector(
                        onTap: _showForgotPasswordDialog,
                        child: Text(
                          'Forgot Password?',
                          style: GoogleFonts.spaceGrotesk(
                            color: const Color(0xFF00F3FF),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],

                  if (_errorMessage != null) ...[
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.error.withAlpha(25),
                        borderRadius: BorderRadius.circular(10.0),
                        border: Border.all(color: AppTheme.error.withAlpha(70)),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.error_outline_rounded,
                            color: AppTheme.error,
                            size: 16,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _errorMessage!,
                              style: GoogleFonts.spaceGrotesk(
                                color: AppTheme.error,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 26),

                  // Submit button
                  SizedBox(
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF00F3FF),
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: const Color(
                          0xFF00F3FF,
                        ).withAlpha(80),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12.0),
                        ),
                        elevation: 0,
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Colors.white,
                                ),
                              ),
                            )
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  _isSignUp
                                      ? 'Create Profile & Sign In'
                                      : 'Sign In to TrackLog',
                                  style: GoogleFonts.spaceGrotesk(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.3,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                const Icon(
                                  Icons.arrow_forward_rounded,
                                  size: 18,
                                ),
                              ],
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Toggle row ────────────────────────────────────────────────────────
  Widget _buildToggleRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          _isSignUp ? 'Already have a profile? ' : 'New engineer? ',
          style: GoogleFonts.spaceGrotesk(
            color: Colors.white.withAlpha(140),
            fontSize: 13,
          ),
        ),
        GestureDetector(
          onTap: _toggleMode,
          child: Text(
            _isSignUp ? 'Sign In' : 'Create Profile',
            style: GoogleFonts.spaceGrotesk(
              color: const Color(0xFF00F3FF),
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }

  // ── Demo credentials ──────────────────────────────────────────────────
  Widget _buildDemoCredentials() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(8),
        borderRadius: BorderRadius.circular(14.0),
        border: Border.all(color: Colors.white.withAlpha(15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: AppTheme.info.withAlpha(25),
                  borderRadius: BorderRadius.circular(6.0),
                ),
                child: const Icon(
                  Icons.info_outline_rounded,
                  color: AppTheme.info,
                  size: 14,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Demo Accounts',
                style: GoogleFonts.spaceGrotesk(
                  color: AppTheme.info,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _demoCredRow('arjun.sharma@goodyear.com', 'Goodyear@2026'),
          const SizedBox(height: 6),
          _demoCredRow('priya.nair@goodyear.com', 'Goodyear@2026'),
          const SizedBox(height: 6),
          _demoCredRow('rahul.mehta@goodyear.com', 'Goodyear@2026'),
        ],
      ),
    );
  }

  // ── Footer ────────────────────────────────────────────────────────────
  Widget _buildFooter() {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(width: 40, height: 1, color: Colors.white.withAlpha(25)),
            const SizedBox(width: 12),
            Text(
              'NATRAX · Pithampur, Madhya Pradesh',
              style: GoogleFonts.spaceGrotesk(
                fontSize: 10,
                color: Colors.white.withAlpha(60),
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(width: 12),
            Container(width: 40, height: 1, color: Colors.white.withAlpha(25)),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          'Asia\'s Largest Automotive Proving Ground',
          style: GoogleFonts.spaceGrotesk(
            fontSize: 10,
            color: Colors.white.withAlpha(40),
            letterSpacing: 0.3,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 10),
        GestureDetector(
          onTap: () => context.push(AppRoutes.privacyPolicy),
          child: Text(
            'Privacy Policy',
            style: GoogleFonts.spaceGrotesk(
              fontSize: 11,
              color: AppTheme.primary.withAlpha(180),
              fontWeight: FontWeight.w500,
              decoration: TextDecoration.underline,
              decorationColor: AppTheme.primary.withAlpha(120),
            ),
          ),
        ),
      ],
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────
  Widget _buildLabel(String label) {
    return Text(
      label,
      style: GoogleFonts.spaceGrotesk(
        color: Colors.white.withAlpha(160),
        fontSize: 12,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.3,
      ),
    );
  }

  InputDecoration _inputDecoration({
    required String hint,
    required IconData icon,
    Widget? suffix,
  }) {
    return InputDecoration(
      hintText: hint,
      hintStyle: GoogleFonts.spaceGrotesk(
        color: const Color(0xFF6B7490),
        fontSize: 13,
      ),
      prefixIcon: Icon(icon, color: const Color(0xFF6B7490), size: 20),
      suffixIcon: suffix,
      filled: true,
      fillColor: Colors.white.withAlpha(10),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.white.withAlpha(20)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.white.withAlpha(20)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFF00F3FF), width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppTheme.error),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppTheme.error, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    TextCapitalization textCapitalization = TextCapitalization.none,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      textCapitalization: textCapitalization,
      style: GoogleFonts.spaceGrotesk(color: const Color(0xFFdfe2f0), fontSize: 14),
      decoration: _inputDecoration(hint: hint, icon: icon),
      validator: validator,
    );
  }

  Widget _demoCredRow(String email, String password) {
    return Row(
      children: [
        Container(
          width: 5,
          height: 5,
          decoration: const BoxDecoration(
            color: Color(0xFF00F3FF),
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            '$email  /  $password',
            style: GoogleFonts.spaceGrotesk(
              color: Colors.white.withAlpha(160),
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

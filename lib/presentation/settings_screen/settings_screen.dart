import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:go_router/go_router.dart';

import '../../services/engineer_auth_service.dart';
import '../../services/supabase_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/custom_icon_widget.dart';
import '../../routes/app_routes.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _fadeAnim;

  EngineerProfile? _profile;
  bool _loadingProfile = true;

  // Password change
  final _currentPasswordCtrl = TextEditingController();
  final _newPasswordCtrl = TextEditingController();
  final _confirmPasswordCtrl = TextEditingController();
  bool _obscureCurrent = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;
  bool _savingPassword = false;

  // Notification preferences
  bool _notifySessionStart = true;
  bool _notifySessionEnd = true;
  bool _notifyReportReady = true;
  bool _notifyGateAlert = false;
  bool _savingNotifications = false;

  // Export frequency
  String _exportFrequency = 'monthly'; // 'monthly' | 'yearly'
  bool _savingExport = false;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 480),
    );
    _fadeAnim = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOutCubic,
    );
    _loadProfile();
  }

  @override
  void dispose() {
    _animController.dispose();
    _currentPasswordCtrl.dispose();
    _newPasswordCtrl.dispose();
    _confirmPasswordCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    final profile = await EngineerAuthService.instance.getCurrentProfile();
    if (mounted) {
      setState(() {
        _profile = profile;
        _loadingProfile = false;
      });
      _animController.forward(from: 0);
    }
  }

  Future<void> _changePassword() async {
    final current = _currentPasswordCtrl.text.trim();
    final newPass = _newPasswordCtrl.text.trim();
    final confirm = _confirmPasswordCtrl.text.trim();

    if (current.isEmpty || newPass.isEmpty || confirm.isEmpty) {
      _showSnack('Please fill in all password fields.', isError: true);
      return;
    }
    if (newPass.length < 8) {
      _showSnack('New password must be at least 8 characters.', isError: true);
      return;
    }
    if (newPass != confirm) {
      _showSnack('New passwords do not match.', isError: true);
      return;
    }

    setState(() => _savingPassword = true);
    try {
      // Re-authenticate then update
      final email = _profile?.email ?? '';
      await EngineerAuthService.instance.signIn(
        email: email,
        password: current,
      );
      await SupabaseService.instance.client.auth.updateUser(
        UserAttributes(password: newPass),
      );
      _currentPasswordCtrl.clear();
      _newPasswordCtrl.clear();
      _confirmPasswordCtrl.clear();
      _showSnack('Password updated successfully.');
    } catch (e) {
      _showSnack(
        'Failed to update password. Check your current password.',
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _savingPassword = false);
    }
  }

  Future<void> _saveNotifications() async {
    setState(() => _savingNotifications = true);
    await Future.delayed(const Duration(milliseconds: 600));
    if (mounted) {
      setState(() => _savingNotifications = false);
      _showSnack('Notification preferences saved.');
    }
  }

  Future<void> _saveExportFrequency() async {
    setState(() => _savingExport = true);
    await Future.delayed(const Duration(milliseconds: 500));
    if (mounted) {
      setState(() => _savingExport = false);
      _showSnack(
        'Export frequency set to ${_exportFrequency == 'monthly' ? 'Monthly' : 'Yearly'}.',
      );
    }
  }

  void _showSnack(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: GoogleFonts.spaceGrotesk(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: Colors.white,
          ),
        ),
        backgroundColor: isError ? AppTheme.error : AppTheme.success,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: _loadingProfile
            ? const Center(
                child: CircularProgressIndicator(color: AppTheme.primary),
              )
            : FadeTransition(
                opacity: _fadeAnim,
                child: CustomScrollView(
                  physics: const BouncingScrollPhysics(),
                  slivers: [
                    SliverToBoxAdapter(child: _buildHeader()),
                    SliverToBoxAdapter(child: _buildProfileCard()),
                    SliverToBoxAdapter(
                      child: _buildSection(
                        icon: 'lock',
                        title: 'Change Password',
                        child: _buildPasswordSection(),
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: _buildSection(
                        icon: 'notifications',
                        title: 'Notification Preferences',
                        child: _buildNotificationsSection(),
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: _buildSection(
                        icon: 'file_download',
                        title: 'Export Frequency',
                        child: _buildExportSection(),
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: _buildSection(
                        icon: 'receipt_long',
                        title: 'PO Tracker',
                        child: _buildPoTrackerSection(),
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: _buildSection(
                        icon: 'email',
                        title: 'Email Reports',
                        child: _buildEmailReportsSection(),
                      ),
                    ),
                    const SliverToBoxAdapter(child: SizedBox(height: 120)),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppTheme.primary.withAlpha(25),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.primary.withAlpha(70)),
            ),
            child: const Icon(
              Icons.settings,
              color: AppTheme.primary,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Settings',
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFFdfe2f0),
                ),
              ),
              Text(
                'Manage your account preferences',
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: const Color(0xFF6B7490),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildProfileCard() {
    final name = _profile?.engineerName ?? 'Engineer';
    final email = _profile?.email ?? '';
    final dept = _profile?.department ?? 'Tyre Testing';
    final role = _profile?.userRole ?? 'engineer';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFF0A1025).withAlpha(200),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFF849495).withAlpha(120)),
            ),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        AppTheme.primary.withAlpha(80),
                        AppTheme.primary.withAlpha(30),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppTheme.primary.withAlpha(100)),
                  ),
                  child: Center(
                    child: Text(
                      name.isNotEmpty ? name[0].toUpperCase() : 'E',
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.primary,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: GoogleFonts.spaceGrotesk(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFFdfe2f0),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        email,
                        style: GoogleFonts.spaceGrotesk(
                          fontSize: 12,
                          color: const Color(0xFFA8B0C8),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          _buildBadge(dept, AppTheme.info),
                          const SizedBox(width: 6),
                          _buildBadge(
                            role == 'manager' ? 'Manager' : 'Engineer',
                            role == 'manager'
                                ? AppTheme.accent
                                : AppTheme.primary,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBadge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withAlpha(25),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withAlpha(80)),
      ),
      child: Text(
        label,
        style: GoogleFonts.spaceGrotesk(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: color,
          letterSpacing: 0.3,
        ),
      ),
    );
  }

  Widget _buildSection({
    required String icon,
    required String title,
    required Widget child,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF0A1025).withAlpha(190),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFF849495).withAlpha(100)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
                  child: Row(
                    children: [
                      CustomIconWidget(
                        iconName: icon,
                        color: AppTheme.primary,
                        size: 18,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        title,
                        style: GoogleFonts.spaceGrotesk(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFFdfe2f0),
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(
                  color: Color(0xFF3a494b),
                  height: 1,
                  thickness: 1,
                ),
                Padding(padding: const EdgeInsets.all(18), child: child),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPasswordSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildPasswordField(
          controller: _currentPasswordCtrl,
          label: 'Current Password',
          obscure: _obscureCurrent,
          onToggle: () => setState(() => _obscureCurrent = !_obscureCurrent),
        ),
        const SizedBox(height: 12),
        _buildPasswordField(
          controller: _newPasswordCtrl,
          label: 'New Password',
          obscure: _obscureNew,
          onToggle: () => setState(() => _obscureNew = !_obscureNew),
        ),
        const SizedBox(height: 12),
        _buildPasswordField(
          controller: _confirmPasswordCtrl,
          label: 'Confirm New Password',
          obscure: _obscureConfirm,
          onToggle: () => setState(() => _obscureConfirm = !_obscureConfirm),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _savingPassword ? null : _changePassword,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: const Color(0xFF001A10),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              elevation: 0,
            ),
            child: _savingPassword
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Color(0xFF001A10),
                    ),
                  )
                : Text(
                    'Update Password',
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildPasswordField({
    required TextEditingController controller,
    required String label,
    required bool obscure,
    required VoidCallback onToggle,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      style: GoogleFonts.spaceGrotesk(fontSize: 13, color: const Color(0xFFdfe2f0)),
      decoration: InputDecoration(
        labelText: label,
        suffixIcon: GestureDetector(
          onTap: onToggle,
          child: Icon(
            obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
            color: const Color(0xFF6B7490),
            size: 18,
          ),
        ),
      ),
    );
  }

  Widget _buildNotificationsSection() {
    final items = [
      _NotifItem(
        icon: 'play_circle',
        label: 'Session Started',
        subtitle: 'Alert when a new session begins',
        value: _notifySessionStart,
        onChanged: (v) => setState(() => _notifySessionStart = v),
      ),
      _NotifItem(
        icon: 'stop_circle',
        label: 'Session Ended',
        subtitle: 'Alert when a session is completed',
        value: _notifySessionEnd,
        onChanged: (v) => setState(() => _notifySessionEnd = v),
      ),
      _NotifItem(
        icon: 'email',
        label: 'Report Ready',
        subtitle: 'Notify when an email report is sent',
        value: _notifyReportReady,
        onChanged: (v) => setState(() => _notifyReportReady = v),
      ),
      _NotifItem(
        icon: 'location_on',
        label: 'Gate Alerts',
        subtitle: 'Notify on gate entry/exit events',
        value: _notifyGateAlert,
        onChanged: (v) => setState(() => _notifyGateAlert = v),
      ),
    ];

    return Column(
      children: [
        ...items.map((item) => _buildToggleRow(item)),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _savingNotifications ? null : _saveNotifications,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF181B25),
              foregroundColor: AppTheme.primary,
              padding: const EdgeInsets.symmetric(vertical: 13),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(color: AppTheme.primary.withAlpha(80)),
              ),
              elevation: 0,
            ),
            child: _savingNotifications
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppTheme.primary,
                    ),
                  )
                : Text(
                    'Save Preferences',
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildToggleRow(_NotifItem item) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppTheme.primary.withAlpha(20),
              borderRadius: BorderRadius.circular(10),
            ),
            child: CustomIconWidget(
              iconName: item.icon,
              color: AppTheme.primary,
              size: 17,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.label,
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFFdfe2f0),
                  ),
                ),
                Text(
                  item.subtitle,
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 11,
                    color: const Color(0xFF6B7490),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Switch(value: item.value, onChanged: item.onChanged),
        ],
      ),
    );
  }

  Widget _buildExportSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Choose how often activity reports are exported and sent.',
          style: GoogleFonts.spaceGrotesk(
            fontSize: 12,
            color: const Color(0xFFA8B0C8),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _buildFrequencyChip(
                label: 'Monthly',
                icon: 'calendar_month',
                subtitle: 'Every month',
                value: 'monthly',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildFrequencyChip(
                label: 'Yearly',
                icon: 'calendar_today',
                subtitle: 'Once a year',
                value: 'yearly',
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _savingExport ? null : _saveExportFrequency,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF181B25),
              foregroundColor: AppTheme.primary,
              padding: const EdgeInsets.symmetric(vertical: 13),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(color: AppTheme.primary.withAlpha(80)),
              ),
              elevation: 0,
            ),
            child: _savingExport
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppTheme.primary,
                    ),
                  )
                : Text(
                    'Save Frequency',
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildPoTrackerSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Manage and track Purchase Orders for your sessions.',
          style: GoogleFonts.spaceGrotesk(
            fontSize: 12,
            color: const Color(0xFFA8B0C8),
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () => context.push(AppRoutes.poTracker),
            icon: const Icon(Icons.receipt_long_rounded, size: 18),
            label: Text(
              'Open PO Tracker',
              style: GoogleFonts.spaceGrotesk(
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: const Color(0xFF001A10),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              elevation: 0,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmailReportsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Configure email report subscriptions and send session summaries.',
          style: GoogleFonts.spaceGrotesk(
            fontSize: 12,
            color: const Color(0xFFA8B0C8),
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () => context.push(AppRoutes.emailReports),
            icon: const Icon(Icons.email_rounded, size: 18),
            label: Text(
              'Open Email Reports',
              style: GoogleFonts.spaceGrotesk(
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF181B25),
              foregroundColor: AppTheme.primary,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(color: AppTheme.primary.withAlpha(80)),
              ),
              elevation: 0,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFrequencyChip({
    required String label,
    required String icon,
    required String subtitle,
    required String value,
  }) {
    final isSelected = _exportFrequency == value;
    return GestureDetector(
      onTap: () => setState(() => _exportFrequency = value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 14),
        decoration: BoxDecoration(
          color: isSelected
              ? AppTheme.primary.withAlpha(25)
              : const Color(0xFF181B25),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? AppTheme.primary.withAlpha(150)
                : const Color(0xFF849495).withAlpha(100),
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CustomIconWidget(
                  iconName: icon,
                  color: isSelected
                      ? AppTheme.primary
                      : const Color(0xFF6B7490),
                  size: 18,
                ),
                const Spacer(),
                if (isSelected)
                  Container(
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      color: AppTheme.primary,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.check,
                      size: 12,
                      color: Color(0xFF001A10),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              label,
              style: GoogleFonts.spaceGrotesk(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: isSelected ? AppTheme.primary : const Color(0xFFdfe2f0),
              ),
            ),
            Text(
              subtitle,
              style: GoogleFonts.spaceGrotesk(
                fontSize: 11,
                color: const Color(0xFF6B7490),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmailReportTypeChip({
    required String label,
    required String icon,
    required String value,
    required bool selected,
  }) {
    return GestureDetector(
      onTap: () => setState(() => _exportFrequency = value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 14),
        decoration: BoxDecoration(
          color: selected
              ? AppTheme.primary.withAlpha(25)
              : const Color(0xFF181B25),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected
                ? AppTheme.primary.withAlpha(150)
                : const Color(0xFF849495).withAlpha(100),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            CustomIconWidget(
              iconName: icon,
              color: selected ? AppTheme.primary : const Color(0xFF6B7490),
              size: 18,
            ),
            const SizedBox(width: 10),
            Text(
              label,
              style: GoogleFonts.spaceGrotesk(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: selected ? AppTheme.primary : const Color(0xFFdfe2f0),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NotifItem {
  final String icon;
  final String label;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _NotifItem({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });
}

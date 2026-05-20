import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:sizer/sizer.dart';
import '../../theme/app_theme.dart';
import '../../widgets/custom_icon_widget.dart';

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundDark,
      appBar: AppBar(
        backgroundColor: AppTheme.surfaceDark,
        elevation: 0,
        leading: IconButton(
          icon: const CustomIconWidget(
            iconName: 'arrow_back',
            color: Colors.white,
            size: 22,
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Privacy Policy',
          style: GoogleFonts.inter(
            color: Colors.white,
            fontSize: 16.sp,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: true,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: const Color(0xFF2A3450)),
        ),
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.symmetric(horizontal: 4.w, vertical: 2.h),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(),
            SizedBox(height: 2.h),
            _buildSection(
              icon: 'info',
              title: 'Overview',
              content:
                  'TrackLog ("the App") is operated by the Goodyear testing team for internal use at NATRAX (National Automotive Test Tracks). This Privacy Policy explains how we collect, use, and protect information when you use the App.',
            ),
            _buildSection(
              icon: 'location_on',
              title: 'Location Data',
              content:
                  'TrackLog collects your precise GPS location to:\n\n'
                  '• Display your real-time position on the NATRAX track map\n'
                  '• Detect when you enter or exit track gate geofences\n'
                  '• Auto-start and auto-stop test sessions based on gate proximity\n'
                  '• Record location data as part of session logs\n\n'
                  'Location is collected in the foreground while the app is active, and in the background when background location permission is granted (required for automatic gate detection). Location data is stored securely in our Supabase database and is only accessible to authorised team members.',
            ),
            _buildSection(
              icon: 'timer',
              title: 'Session & Activity Data',
              content:
                  'We collect session start/end times, gate entry/exit events, session duration, and associated cost calculations. This data is used to generate reports for operational tracking and PO management. Session logs are retained for the duration of the testing programme.',
            ),
            _buildSection(
              icon: 'person',
              title: 'Account Information',
              content:
                  'We store your email address and engineer profile (name, role) to authenticate you and associate session data with the correct engineer. This information is managed via Supabase Auth and is not shared with third parties.',
            ),
            _buildSection(
              icon: 'email',
              title: 'Email Communications',
              content:
                  'If you are a subscribed manager, you may receive automated daily or weekly email reports summarising PO spend and session activity. These emails are sent via Resend and contain operational data only. You can be removed from the subscriber list at any time by an app administrator.',
            ),
            _buildSection(
              icon: 'security',
              title: 'Data Security',
              content:
                  'All data is transmitted over HTTPS and stored in a secured Supabase project with row-level security (RLS) policies. Only authenticated users with appropriate roles can access data. We do not sell, rent, or share your personal data with any external parties.',
            ),
            _buildSection(
              icon: 'phone_android',
              title: 'Device Permissions',
              content:
                  'The App requests the following device permissions:\n\n'
                  '• Location (Foreground) — required for map display and gate detection\n'
                  '• Location (Background) — required for automatic session start/stop\n'
                  '• Notifications — used to alert you of session events and gate crossings\n\n'
                  'You can revoke these permissions at any time in your device settings. Revoking location permission will disable geofence-based session automation.',
            ),
            _buildSection(
              icon: 'update',
              title: 'Data Retention',
              content:
                  'Session and location data is retained for the duration of the active testing programme. Upon programme completion, data may be archived or deleted in accordance with Goodyear internal data governance policies.',
            ),
            _buildSection(
              icon: 'contact_support',
              title: 'Contact',
              content:
                  'For questions about this Privacy Policy or your data, please contact your Goodyear programme administrator or the TrackLog system owner.',
            ),
            _buildLastUpdated(),
            SizedBox(height: 3.h),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(4.w),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppTheme.primary.withAlpha(30),
            AppTheme.primary.withAlpha(10),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16.0),
        border: Border.all(color: AppTheme.primary.withAlpha(60), width: 1),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppTheme.primary.withAlpha(30),
              borderRadius: BorderRadius.circular(12.0),
            ),
            child: CustomIconWidget(
              iconName: 'shield',
              color: AppTheme.primary,
              size: 24,
            ),
          ),
          SizedBox(width: 3.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'TrackLog Privacy Policy',
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: 14.sp,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(height: 0.4.h),
                Text(
                  'Internal use — Goodyear NATRAX Testing Programme',
                  style: GoogleFonts.inter(
                    color: const Color(0xFF8A94B0),
                    fontSize: 11.sp,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSection({
    required String icon,
    required String title,
    required String content,
  }) {
    return Padding(
      padding: EdgeInsets.only(bottom: 2.h),
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.all(4.w),
        decoration: BoxDecoration(
          color: AppTheme.surfaceDark,
          borderRadius: BorderRadius.circular(12.0),
          border: Border.all(color: const Color(0xFF2A3450), width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CustomIconWidget(
                  iconName: icon,
                  color: AppTheme.primary,
                  size: 18,
                ),
                SizedBox(width: 2.w),
                Text(
                  title,
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: 13.sp,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            SizedBox(height: 1.2.h),
            Text(
              content,
              style: GoogleFonts.inter(
                color: const Color(0xFFB0BAD0),
                fontSize: 12.sp,
                fontWeight: FontWeight.w400,
                height: 1.6,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLastUpdated() {
    return Center(
      child: Text(
        'Last updated: May 2026',
        style: GoogleFonts.inter(
          color: const Color(0xFF6B7490),
          fontSize: 11.sp,
          fontWeight: FontWeight.w400,
        ),
      ),
    );
  }
}
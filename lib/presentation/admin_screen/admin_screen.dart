import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:file_picker/file_picker.dart';
import 'package:excel/excel.dart' as ex;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/app_export.dart';
import '../../services/supabase_service.dart';
import '../../services/engineer_auth_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/custom_icon_widget.dart';

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  bool _isProcessing = false;
  String _statusMessage = '';
  List<TrackRate> _rates = [];
  bool _loadingRates = true;

  @override
  void initState() {
    super.initState();
    _loadTrackRates();
  }

  Future<void> _loadTrackRates() async {
    setState(() => _loadingRates = true);
    try {
      final data = await SupabaseService.instance.client
          .from('track_rates')
          .select()
          .order('track_code');
      if (mounted) {
        setState(() {
          _rates = (data as List).map((e) => TrackRate.fromJson(e)).toList();
          _loadingRates = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingRates = false);
    }
  }

  Future<void> _importExcel() async {
    setState(() {
      _isProcessing = true;
      _statusMessage = 'Selecting file...';
    });

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xlsm'],
        withData: true,
      );

      if (result == null || result.files.isEmpty) {
        setState(() {
          _isProcessing = false;
          _statusMessage = 'Import cancelled.';
        });
        return;
      }

      final fileBytes = result.files.first.bytes;
      if (fileBytes == null) {
        throw Exception('Failed to read file bytes.');
      }

      setState(() => _statusMessage = 'Parsing Excel sheet...');

      final excel = ex.Excel.decodeBytes(fileBytes);
      final detailedSheet = excel.tables['Detailed Utilisation'];

      if (detailedSheet == null) {
        throw Exception('Detailed Utilisation sheet not found in Excel file.');
      }

      final rows = detailedSheet.rows;
      if (rows.length <= 1) {
        throw Exception('No data rows found in sheet.');
      }

      final user = SupabaseService.instance.client.auth.currentUser;
      if (user == null) {
        throw Exception('You must be logged in to perform imports.');
      }

      setState(() => _statusMessage = 'Processing and importing rows...');

      int importedCount = 0;
      final List<Map<String, dynamic>> sessionsToInsert = [];

      // Assume header is on row 0
      for (int i = 1; i < rows.length; i++) {
        final row = rows[i];
        if (row.isEmpty || row.length < 5) continue;

        final dateVal = row[0]?.value;
        final trackVal = row[1]?.value;
        final inTimeVal = row[2]?.value;
        final outTimeVal = row[3]?.value;
        final decimalHrsVal = row[4]?.value;

        if (dateVal == null || trackVal == null) continue;

        // Parse date and times
        final dateInt = int.tryParse(dateVal.toString());
        final inTimeDouble = double.tryParse(inTimeVal.toString()) ?? 0.0;
        final outTimeDouble = double.tryParse(outTimeVal.toString()) ?? 0.0;
        final decimalHrs = double.tryParse(decimalHrsVal.toString()) ?? 0.0;

        if (dateInt == null) continue;

        final startedAt = _excelToDateTime(dateInt, inTimeDouble);
        final endedAt = _excelToDateTime(dateInt, outTimeDouble);
        final durationMins = (decimalHrs * 60).round();

        final trackCode = trackVal.toString().trim();

        sessionsToInsert.add({
          'engineer_id': user.id,
          'track_code': trackCode,
          'track_name': trackCode, // Fallback to trackCode as name
          'vehicle_category': 'below_3_5t',
          'booking_type': 'standard',
          'session_status': 'completed',
          'started_at': startedAt.toIso8601String(),
          'ended_at': endedAt.toIso8601String(),
          'duration_minutes': durationMins,
          'hourly_rate': 25000.0,
          'total_cost': decimalHrs * 25000.0,
          'notes': 'Imported via Web Admin Upload'
        });
      }

      if (sessionsToInsert.isEmpty) {
        throw Exception('No valid sessions processed from sheet.');
      }

      // Insert in batches of 50
      for (int i = 0; i < sessionsToInsert.length; i += 50) {
        final end = (i + 50 < sessionsToInsert.length) ? i + 50 : sessionsToInsert.length;
        final batch = sessionsToInsert.sublist(i, end);
        await SupabaseService.instance.client.from('engineer_sessions').insert(batch);
        importedCount += batch.length;
        setState(() => _statusMessage = 'Imported $importedCount of ${sessionsToInsert.length} sessions...');
      }

      setState(() {
        _isProcessing = false;
        _statusMessage = 'Success! Imported $importedCount sessions.';
      });
      _showSnack('Imported $importedCount sessions successfully.', isError: false);
    } catch (e) {
      setState(() {
        _isProcessing = false;
        _statusMessage = 'Error: ${e.toString()}';
      });
      _showSnack('Import failed: ${e.toString()}', isError: true);
    }
  }

  DateTime _excelToDateTime(int serialDate, double serialTime) {
    final baseDate = DateTime.utc(1899, 12, 30);
    final daysMs = serialDate * 24 * 60 * 60 * 1000;
    final timeMs = (serialTime * 24 * 60 * 60 * 1000).round();
    return baseDate.add(Duration(milliseconds: daysMs + timeMs));
  }

  void _showSnack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? AppTheme.error : AppTheme.success,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(),
              const SizedBox(height: 24),
              _buildExcelImportCard(),
              const SizedBox(height: 24),
              _buildRatesCard(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
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
            Icons.admin_panel_settings_rounded,
            color: AppTheme.primary,
            size: 20,
          ),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Admin Control Center',
              style: GoogleFonts.manrope(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: const Color(0xFFE8EAF0),
              ),
            ),
            Text(
              'System management, track rates & bulk imports',
              style: GoogleFonts.manrope(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: const Color(0xFF6B7490),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildExcelImportCard() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: const Color(0xFF1A2236).withAlpha(200),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFF3A4460).withAlpha(120)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Spreadsheet Billing Data Import',
                style: GoogleFonts.manrope(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFFE8EAF0),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Upload a NATRAX Comprehensive Billing Excel sheet (.xlsx/.xlsm) to import raw sessions from the Detailed Utilisation tab.',
                style: GoogleFonts.manrope(
                  fontSize: 12,
                  color: const Color(0xFF9098B0),
                ),
              ),
              const SizedBox(height: 20),
              if (_statusMessage.isNotEmpty) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F1520),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFF3A4460).withAlpha(80)),
                  ),
                  child: Text(
                    _statusMessage,
                    style: GoogleFonts.manrope(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.primary,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton.icon(
                  onPressed: _isProcessing ? null : _importExcel,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: _isProcessing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.upload_file_rounded),
                  label: Text(
                    _isProcessing ? 'Processing...' : 'Upload Excel Sheet',
                    style: GoogleFonts.manrope(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRatesCard() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: const Color(0xFF1A2236).withAlpha(200),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFF3A4460).withAlpha(120)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Track Rate Management',
                style: GoogleFonts.manrope(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFFE8EAF0),
                ),
              ),
              const SizedBox(height: 16),
              if (_loadingRates)
                const Center(child: CircularProgressIndicator())
              else if (_rates.isEmpty)
                Text(
                  'No rates configured. Run migrations or add rates first.',
                  style: GoogleFonts.manrope(
                    fontSize: 13,
                    color: const Color(0xFF6B7490),
                  ),
                )
              else
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _rates.length,
                  separatorBuilder: (_, __) => const Divider(color: Color(0xFF3A4460)),
                  itemBuilder: (context, idx) {
                    final rate = _rates[idx];
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${rate.trackCode} — ${rate.trackName}',
                                  style: GoogleFonts.manrope(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: const Color(0xFFE8EAF0),
                                  ),
                                ),
                                Text(
                                  'Min billing: ${rate.minHoursPerDay} hrs/day',
                                  style: GoogleFonts.manrope(
                                    fontSize: 11,
                                    color: const Color(0xFF6B7490),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            '₹${rate.rateBelow3_5t.toStringAsFixed(0)}/hr',
                            style: GoogleFonts.manrope(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.primary,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}

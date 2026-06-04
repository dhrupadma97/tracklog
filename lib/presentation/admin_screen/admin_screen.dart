import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:file_picker/file_picker.dart';
import 'package:excel/excel.dart' as ex;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:spreadsheet_decoder/spreadsheet_decoder.dart';

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


  Future<void> _compareExcel() async {
    setState(() {
      _isProcessing = true;
      _statusMessage = 'Selecting NATRAX sheet for comparison...';
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
          _statusMessage = 'Comparison cancelled.';
        });
        return;
      }

      final fileBytes = result.files.first.bytes;
      if (fileBytes == null) throw Exception('Failed to read file bytes.');

      setState(() => _statusMessage = 'Parsing Excel sheet...');

      final List<int> bytesList = List<int>.from(fileBytes);
        final decoder = SpreadsheetDecoder.decodeBytes(bytesList, update: true);
      final detailedSheet = decoder.tables['Detailed Utilisation'];

      if (detailedSheet == null) {
        throw Exception('Detailed Utilisation sheet not found in Excel file.');
      }

      final rows = detailedSheet.rows;
      if (rows.length <= 1) throw Exception('No data rows found in sheet.');

      setState(() => _statusMessage = 'Matching against our database...');

      // Extract NATRAX records
      final List<Map<String, dynamic>> natraxRecords = [];
      DateTime? minDate;
      DateTime? maxDate;

      for (int i = 1; i < rows.length; i++) {
        final row = rows[i];
        if (row.isEmpty || row.length < 5) continue;

        final dateVal = row[0];
        final trackVal = row[1];
        final decimalHrsVal = row[4];

        if (dateVal == null || trackVal == null) continue;

        final dateInt = int.tryParse(dateVal.toString());
        final decimalHrs = double.tryParse(decimalHrsVal.toString()) ?? 0.0;

        if (dateInt == null) continue;

        final date = _excelToDateTime(dateInt, 0.0);
        
        if (minDate == null || date.isBefore(minDate)) minDate = date;
        if (maxDate == null || date.isAfter(maxDate)) maxDate = date;

        final trackCode = trackVal.toString().trim();
        final durationMins = (decimalHrs * 60).round();

        natraxRecords.add({
          'date': date,
          'track': trackCode,
          'duration': durationMins,
        });
      }

      if (natraxRecords.isEmpty) throw Exception('No valid records parsed from NATRAX sheet.');
      
      // Expand query range slightly
      final queryStart = minDate!.subtract(const Duration(days: 1)).toIso8601String();
      final queryEnd = maxDate!.add(const Duration(days: 2)).toIso8601String();

      // Fetch our records
      final supabase = SupabaseService.instance.client;
      final ourData = await supabase
          .from('engineer_sessions')
          .select('id, started_at, duration_minutes, track_code, session_status')
          .gte('started_at', queryStart)
          .lte('started_at', queryEnd);

      // Perform matching
      int exactMatches = 0;
      int durationMismatches = 0;
      List<Map<String, dynamic>> missingFromUs = [];
      List<Map<String, dynamic>> discrepancies = [];

      // We'll map NATRAX by date string (YYYY-MM-DD) and track code to sum up hours
      Map<String, int> natraxAgg = {};
      for (var r in natraxRecords) {
        final dStr = (r['date'] as DateTime).toIso8601String().split('T')[0];
        final tCode = (r['track'] as String).toLowerCase();
        final key = '${dStr}_${tCode}';
        natraxAgg[key] = (natraxAgg[key] ?? 0) + ((r['duration'] as num).toInt());
      }

      Map<String, int> ourAgg = {};
      for (var s in (ourData as List)) {
        final start = s['started_at'] as String;
        final dStr = start.split('T')[0];
        final tCode = (s['track_code'] as String).toLowerCase();
        final key = '${dStr}_${tCode}';
        final dur = (s['duration_minutes'] as num?)?.toInt() ?? 0;
        ourAgg[key] = (ourAgg[key] ?? 0) + dur;
      }

      // Compare
      natraxAgg.forEach((key, natraxDur) {
        final ourDur = ourAgg[key] ?? 0;
        final parts = key.split('_');
        final dStr = parts[0];
        final tCode = parts[1].toUpperCase();

        if (ourDur == 0) {
          missingFromUs.add({'date': dStr, 'track': tCode, 'natraxDur': natraxDur});
        } else if ((ourDur - natraxDur).abs() > 15) { // 15 mins tolerance
          discrepancies.add({
            'date': dStr, 'track': tCode, 
            'natraxDur': natraxDur, 'ourDur': ourDur,
            'diff': ourDur - natraxDur
          });
          durationMismatches++;
        } else {
          exactMatches++;
        }
        
        ourAgg.remove(key); // Mark as checked
      });

      int missingFromNatrax = ourAgg.length; // Remaining were logged by us but not billed by NATRAX!

      setState(() {
        _isProcessing = false;
        _statusMessage = 'Comparison Complete';
      });

      _showComparisonReport(exactMatches, durationMismatches, missingFromUs.length, missingFromNatrax, discrepancies, missingFromUs, ourAgg);

    } catch (e) {
      setState(() {
        _isProcessing = false;
        _statusMessage = 'Comparison failed: ${e.toString()}';
      });
      _showSnack('Comparison failed: ${e.toString()}', isError: true);
    }
  }

  void _showComparisonReport(int matches, int mismatches, int missingUs, int missingNatrax, List<Map> discrepancies, List<Map> missingFromUs, Map<String, int> missingFromNatraxMap) {
    showDialog(
      context: context,
      builder: (ctx) {
        return Dialog(
          backgroundColor: const Color(0xFF0F172A),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: const Color(0xFF849495).withOpacity(0.3))),
          child: Container(
            width: 700,
            constraints: const BoxConstraints(maxHeight: 600),
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('NATRAX Billing Auto-Reconciliation', style: GoogleFonts.spaceGrotesk(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white)),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _kpiBox('Exact Matches', '${matches}', const Color(0xFF00F3FF)),
                    _kpiBox('Duration Mismatch', '${mismatches}', const Color(0xFFFFB547)),
                    _kpiBox('Missing (Us)', '${missingUs}', const Color(0xFFFF4D6A)),
                    _kpiBox('Not Billed', '${missingNatrax}', const Color(0xFF4A9EFF)),
                  ],
                ),
                const SizedBox(height: 24),
                Expanded(
                  child: ListView(
                    children: [
                      if (discrepancies.isNotEmpty) ...[
                        Text('⏱ Duration Mismatches (>15 mins)', style: GoogleFonts.spaceGrotesk(color: const Color(0xFFFFB547), fontWeight: FontWeight.w700)),
                        const SizedBox(height: 8),
                        ...discrepancies.map((d) => _issueRow(d['date'], d['track'], 'Natrax billed ${(d['natraxDur']/60).toStringAsFixed(1)}h, we logged ${(d['ourDur']/60).toStringAsFixed(1)}h (Diff: ${d['diff']}m)')),
                        const SizedBox(height: 20),
                      ],
                      if (missingFromUs.isNotEmpty) ...[
                        Text('❗ Missing From Our Logs (Natrax Billed)', style: GoogleFonts.spaceGrotesk(color: const Color(0xFFFF4D6A), fontWeight: FontWeight.w700)),
                        const SizedBox(height: 8),
                        ...missingFromUs.map((d) => _issueRow(d['date'], d['track'], 'Natrax billed ${(d['natraxDur']/60).toStringAsFixed(1)}h, we have NO log')),
                        const SizedBox(height: 20),
                      ],
                      if (missingFromNatraxMap.isNotEmpty) ...[
                        Text('🎉 Unbilled Sessions (We logged, Natrax missed)', style: GoogleFonts.spaceGrotesk(color: const Color(0xFF4A9EFF), fontWeight: FontWeight.w700)),
                        const SizedBox(height: 8),
                        ...missingFromNatraxMap.entries.map((e) {
                          final p = e.key.split('_');
                          return _issueRow(p[0], p[1].toUpperCase(), 'We logged ${(e.value/60).toStringAsFixed(1)}h, Natrax did not bill');
                        }),
                      ],
                      if (discrepancies.isEmpty && missingFromUs.isEmpty && missingFromNatraxMap.isEmpty)
                        Center(child: Text('Perfect Match! No discrepancies found.', style: GoogleFonts.spaceGrotesk(color: Colors.white70))),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: Text('CLOSE', style: GoogleFonts.spaceGrotesk(color: const Color(0xFF00F3FF), fontWeight: FontWeight.w700)),
                  ),
                )
              ],
            ),
          ),
        );
      }
    );
  }

  Widget _kpiBox(String title, String val, Color color) {
    return Container(
      width: 140, padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(12), border: Border.all(color: color.withOpacity(0.3))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: GoogleFonts.spaceGrotesk(fontSize: 10, color: color, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(val, style: GoogleFonts.spaceGrotesk(fontSize: 24, color: Colors.white, fontWeight: FontWeight.w800)),
        ],
      )
    );
  }

  Widget _issueRow(String date, String track, String desc) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(8)),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(color: Colors.black38, borderRadius: BorderRadius.circular(4)),
            child: Text(date, style: GoogleFonts.spaceGrotesk(fontSize: 11, color: Colors.white70, fontWeight: FontWeight.w600)),
          ),
          const SizedBox(width: 12),
          SizedBox(width: 70, child: Text(track, style: GoogleFonts.spaceGrotesk(fontSize: 12, color: Colors.white, fontWeight: FontWeight.w700))),
          const SizedBox(width: 12),
          Expanded(child: Text(desc, style: GoogleFonts.spaceGrotesk(fontSize: 12, color: Colors.white70))),
        ],
      )
    );
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

      final decoder = SpreadsheetDecoder.decodeBytes(fileBytes);
      final detailedSheet = decoder.tables['Detailed Utilisation'];

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

        final dateVal = row[0];
        final trackVal = row[1];
        final inTimeVal = row[2];
        final outTimeVal = row[3];
        final decimalHrsVal = row[4];

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
              style: GoogleFonts.spaceGrotesk(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: const Color(0xFFdfe2f0),
              ),
            ),
            Text(
              'System management, track rates & bulk imports',
              style: GoogleFonts.spaceGrotesk(
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
            color: const Color(0xFF0A1025).withAlpha(200),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFF849495).withAlpha(120)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Spreadsheet Billing Data Import',
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFFdfe2f0),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Upload a NATRAX Comprehensive Billing Excel sheet (.xlsx/.xlsm) to import raw sessions from the Detailed Utilisation tab.',
                style: GoogleFonts.spaceGrotesk(
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
                    color: const Color(0xFF0A1025),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFF849495).withAlpha(80)),
                  ),
                  child: Text(
                    _statusMessage,
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.primary,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],

              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 50,
                      child: ElevatedButton.icon(
                        onPressed: _isProcessing ? null : _importExcel,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          side: const BorderSide(color: Color(0xFF00F3FF)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        icon: const Icon(Icons.upload_file_rounded, color: Color(0xFF00F3FF)),
                        label: Text(
                          'Raw Import',
                          style: GoogleFonts.spaceGrotesk(fontSize: 13, fontWeight: FontWeight.w700, color: const Color(0xFF00F3FF)),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: SizedBox(
                      height: 50,
                      child: ElevatedButton.icon(
                        onPressed: _isProcessing ? null : _compareExcel,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF00F3FF),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        icon: _isProcessing
                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF0F172A)))
                            : const Icon(Icons.compare_arrows_rounded, color: Color(0xFF0F172A)),
                        label: Text(
                          _isProcessing ? 'Processing...' : 'Compare with TrackLog',
                          style: GoogleFonts.spaceGrotesk(fontSize: 13, fontWeight: FontWeight.w800, color: const Color(0xFF0F172A)),
                        ),
                      ),
                    ),
                  ),
                ],
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
            color: const Color(0xFF0A1025).withAlpha(200),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFF849495).withAlpha(120)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Track Rate Management',
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFFdfe2f0),
                ),
              ),
              const SizedBox(height: 16),
              if (_loadingRates)
                const Center(child: CircularProgressIndicator())
              else if (_rates.isEmpty)
                Text(
                  'No rates configured. Run migrations or add rates first.',
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 13,
                    color: const Color(0xFF6B7490),
                  ),
                )
              else
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _rates.length,
                  separatorBuilder: (_, __) => const Divider(color: Color(0xFF849495)),
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
                                  style: GoogleFonts.spaceGrotesk(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: const Color(0xFFdfe2f0),
                                  ),
                                ),
                                Text(
                                  'Min billing: ${rate.minHoursPerDay} hrs/day',
                                  style: GoogleFonts.spaceGrotesk(
                                    fontSize: 11,
                                    color: const Color(0xFF6B7490),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            '₹${rate.rateBelow3_5t.toStringAsFixed(0)}/hr',
                            style: GoogleFonts.spaceGrotesk(
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

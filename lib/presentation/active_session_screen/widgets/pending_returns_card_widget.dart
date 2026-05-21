import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../services/rental_service.dart';

/// Persistent card shown on the Active Session screen listing all unreturned
/// sand bag and rental instrument entries with live running cost and a
/// "Return Today" button per item.
class PendingReturnsCardWidget extends StatefulWidget {
  const PendingReturnsCardWidget({super.key});

  @override
  State<PendingReturnsCardWidget> createState() =>
      _PendingReturnsCardWidgetState();
}

class _PendingReturnsCardWidgetState extends State<PendingReturnsCardWidget> {
  List<SandBagRental> _sandBags = [];
  List<RentalInstrument> _instruments = [];
  bool _loading = true;
  Timer? _refreshTimer;
  final Set<String> _returningIds = {};

  @override
  void initState() {
    super.initState();
    _loadPendingReturns();
    // Refresh live costs every 60 seconds
    _refreshTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      if (mounted) _loadPendingReturns(silent: true);
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadPendingReturns({bool silent = false}) async {
    if (!silent && mounted) setState(() => _loading = true);
    final result = await RentalService.instance.getPendingReturns();
    if (mounted) {
      setState(() {
        _sandBags = result['sand_bags'] as List<SandBagRental>;
        _instruments = result['instruments'] as List<RentalInstrument>;
        _loading = false;
      });
    }
  }

  Future<void> _returnSandBag(SandBagRental rental) async {
    setState(() => _returningIds.add(rental.id));
    final success = await RentalService.instance.returnSandBagRental(rental.id);
    if (mounted) {
      setState(() => _returningIds.remove(rental.id));
      if (success) {
        _loadPendingReturns(silent: true);
        _showReturnedSnackbar(
          'Sand bags (${rental.bagQuantity} bags) returned',
        );
      }
    }
  }

  Future<void> _returnInstrument(RentalInstrument rental) async {
    setState(() => _returningIds.add(rental.id));
    final success = await RentalService.instance.returnRentalInstrument(
      rental.id,
    );
    if (mounted) {
      setState(() => _returningIds.remove(rental.id));
      if (success) {
        _loadPendingReturns(silent: true);
        _showReturnedSnackbar('${rental.instrumentName} returned');
      }
    }
  }

  void _showReturnedSnackbar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(
              Icons.check_circle_rounded,
              color: Color(0xFF00C896),
              size: 16,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: GoogleFonts.manrope(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF1A2236),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  bool get _hasItems => _sandBags.isNotEmpty || _instruments.isNotEmpty;

  double get _totalLiveCost {
    double total = 0;
    for (final s in _sandBags) {
      total += s.liveCost;
    }
    for (final i in _instruments) {
      total += i.liveCost;
    }
    return total;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return _buildLoadingState();
    }
    if (!_hasItems) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF1A1228),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: const Color(0xFFFF6B35).withAlpha(120),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFFF6B35).withAlpha(30),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(),
            const Divider(color: Color(0xFF2A1E35), height: 1),
            ..._sandBags.map((r) => _buildSandBagRow(r)),
            ..._instruments.map((r) => _buildInstrumentRow(r)),
            _buildFooter(),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingState() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        height: 60,
        decoration: BoxDecoration(
          color: const Color(0xFF1A1228),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFF2A1E35)),
        ),
        child: const Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Color(0xFFFF6B35),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: const Color(0xFFFF6B35).withAlpha(30),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.pending_actions_rounded,
              color: Color(0xFFFF6B35),
              size: 16,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Pending Returns',
                  style: GoogleFonts.manrope(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFFFF6B35),
                  ),
                ),
                Text(
                  '${_sandBags.length + _instruments.length} item${(_sandBags.length + _instruments.length) == 1 ? '' : 's'} unreturned',
                  style: GoogleFonts.manrope(
                    fontSize: 10,
                    color: const Color(0xFF8B7090),
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '₹${_totalLiveCost.toStringAsFixed(0)}',
                style: GoogleFonts.manrope(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFFFF6B35),
                ),
              ),
              Text(
                'running total',
                style: GoogleFonts.manrope(
                  fontSize: 9,
                  color: const Color(0xFF8B7090),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSandBagRow(SandBagRental rental) {
    final isReturning = _returningIds.contains(rental.id);
    final days = rental.daysElapsed;
    return _buildRentalRow(
      id: rental.id,
      icon: Icons.inventory_2_rounded,
      iconColor: const Color(0xFFFFB300),
      title: 'Sand Bags — ${rental.bagQuantity} bags',
      subtitle:
          'Taken ${DateFormat('dd MMM').format(rental.takenDate)} · ${rental.bagQuantity} × $days day${days == 1 ? '' : 's'} × ₹${rental.dailyRate.toStringAsFixed(0)}',
      daysElapsed: days,
      liveCost: rental.liveCost,
      isReturning: isReturning,
      onReturn: () => _returnSandBag(rental),
    );
  }

  Widget _buildInstrumentRow(RentalInstrument rental) {
    final isReturning = _returningIds.contains(rental.id);
    final days = rental.daysElapsed;
    return _buildRentalRow(
      id: rental.id,
      icon: Icons.build_rounded,
      iconColor: const Color(0xFF6C63FF),
      title: rental.instrumentName,
      subtitle:
          'Taken ${DateFormat('dd MMM').format(rental.takenDate)} · $days day${days == 1 ? '' : 's'} × ₹${rental.dailyRate.toStringAsFixed(0)}/day',
      daysElapsed: days,
      liveCost: rental.liveCost,
      isReturning: isReturning,
      onReturn: () => _returnInstrument(rental),
    );
  }

  Widget _buildRentalRow({
    required String id,
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required int daysElapsed,
    required double liveCost,
    required bool isReturning,
    required VoidCallback onReturn,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFF2A1E35), width: 1)),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: iconColor.withAlpha(25),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: iconColor, size: 15),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.manrope(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFFE8EAF0),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: GoogleFonts.manrope(
                    fontSize: 10,
                    color: const Color(0xFF8B7090),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '₹${liveCost.toStringAsFixed(0)}',
                style: GoogleFonts.manrope(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: daysElapsed > 3
                      ? const Color(0xFFFF4444)
                      : const Color(0xFFFFB300),
                ),
              ),
              const SizedBox(height: 4),
              GestureDetector(
                onTap: isReturning ? null : onReturn,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: isReturning
                        ? const Color(0xFF252E45)
                        : const Color(0xFF00C896).withAlpha(30),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isReturning
                          ? const Color(0xFF3A4460)
                          : const Color(0xFF00C896).withAlpha(100),
                    ),
                  ),
                  child: isReturning
                      ? const SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.5,
                            color: Color(0xFF00C896),
                          ),
                        )
                      : Text(
                          'Return Today',
                          style: GoogleFonts.manrope(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF00C896),
                          ),
                        ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFooter() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
      child: Row(
        children: [
          const Icon(
            Icons.info_outline_rounded,
            color: Color(0xFF8B7090),
            size: 12,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'Costs calculated daily. Tap "Return Today" to stop the counter.',
              style: GoogleFonts.manrope(
                fontSize: 10,
                color: const Color(0xFF8B7090),
              ),
            ),
          ),
          GestureDetector(
            onTap: () => _loadPendingReturns(),
            child: const Icon(
              Icons.refresh_rounded,
              color: Color(0xFF8B7090),
              size: 16,
            ),
          ),
        ],
      ),
    );
  }
}

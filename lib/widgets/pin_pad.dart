import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// A numeric keypad for entering or confirming a PIN.
///
/// Purely an input surface — it knows nothing about credentials. Whoever
/// shows it decides what a completed PIN means. See [PinLockService] for what
/// a PIN can and cannot protect.
class PinPad extends StatefulWidget {
  final String title;
  final String subtitle;
  final int length;

  /// Called with the digits once [length] is reached. Return an error string
  /// to keep the pad open and show it, or null when the PIN was accepted.
  final Future<String?> Function(String pin) onComplete;

  /// Shown under the pad as a way out — usually "Use email and password".
  final String? escapeLabel;
  final VoidCallback? onEscape;

  const PinPad({
    super.key,
    required this.title,
    required this.onComplete,
    this.subtitle = '',
    this.length = 4,
    this.escapeLabel,
    this.onEscape,
  });

  @override
  State<PinPad> createState() => _PinPadState();
}

class _PinPadState extends State<PinPad> {
  String _entered = '';
  String? _error;
  bool _busy = false;

  static const _accent = Color(0xFF00F3FF);
  static const _panel = Color(0xFF0A1025);

  Future<void> _push(String digit) async {
    if (_busy || _entered.length >= widget.length) return;
    setState(() {
      _entered += digit;
      _error = null;
    });
    if (_entered.length == widget.length) {
      setState(() => _busy = true);
      final err = await widget.onComplete(_entered);
      if (!mounted) return;
      setState(() {
        _busy = false;
        // A rejected PIN clears the pad; an accepted one is the caller's to
        // dismiss, so the dots stay filled while it navigates away.
        if (err != null) {
          _error = err;
          _entered = '';
        }
      });
    }
  }

  void _backspace() {
    if (_busy || _entered.isEmpty) return;
    setState(() {
      _entered = _entered.substring(0, _entered.length - 1);
      _error = null;
    });
  }

  Widget _dot(bool filled) => Container(
        width: 16,
        height: 16,
        margin: const EdgeInsets.symmetric(horizontal: 9),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: filled ? _accent : Colors.transparent,
          border: Border.all(
            color: filled ? _accent : Colors.white.withAlpha(70),
            width: 1.6,
          ),
        ),
      );

  Widget _key(String label, {VoidCallback? onTap, IconData? icon}) {
    return Padding(
      padding: const EdgeInsets.all(6),
      child: Material(
        color: icon != null ? Colors.transparent : Colors.white.withAlpha(13),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: _busy ? null : (onTap ?? () => _push(label)),
          child: SizedBox(
            width: 64,
            height: 64,
            child: Center(
              child: icon != null
                  ? Icon(icon, color: Colors.white.withAlpha(180), size: 24)
                  : Text(
                      label,
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 24,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: _panel,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: Colors.white.withAlpha(20)),
      ),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.title,
                textAlign: TextAlign.center,
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              if (widget.subtitle.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  widget.subtitle,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 12.5,
                    color: Colors.white.withAlpha(150),
                  ),
                ),
              ],
              const SizedBox(height: 22),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                    widget.length, (i) => _dot(i < _entered.length)),
              ),
              const SizedBox(height: 14),
              SizedBox(
                height: 34,
                child: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: _accent))
                    : Text(
                        _error ?? '',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.spaceGrotesk(
                          fontSize: 12,
                          color: const Color(0xFFFF6B6B),
                        ),
                      ),
              ),
              for (final row in const [
                ['1', '2', '3'],
                ['4', '5', '6'],
                ['7', '8', '9'],
              ])
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [for (final d in row) _key(d)],
                ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(width: 76),
                  _key('0'),
                  _key('', icon: Icons.backspace_outlined, onTap: _backspace),
                ],
              ),
              if (widget.escapeLabel != null) ...[
                const SizedBox(height: 6),
                TextButton(
                  onPressed: _busy ? null : widget.onEscape,
                  child: Text(
                    widget.escapeLabel!,
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 12.5,
                      color: _accent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

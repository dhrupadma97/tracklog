import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../services/project_catalog.dart';
import '../../services/project_registry.dart';
import '../../services/vehicle_lookup_service.dart';

const _bg = Color(0xFF0A1025);
const _field = Color(0xFF050811);
const _line = Color(0xFF1E293B);
const _muted = Color(0xFF6B7490);
const _teal = Color(0xFF00F3FF);
const _amber = Color(0xFFFFB547);
const _red = Color(0xFFFF6B6B);
const _green = Color(0xFF22C55E);

TextStyle _t(double size, {FontWeight w = FontWeight.w500, Color c = Colors.white, double? h}) =>
    GoogleFonts.spaceGrotesk(fontSize: size, fontWeight: w, color: c, height: h);

/// Add a programme: its name and vehicle, the vehicle's details looked up
/// online and checked, and whether it is running yet.
///
/// Returns true when one was added, so the Projects screen reloads.
class NewProjectDialog extends StatefulWidget {
  const NewProjectDialog({super.key});

  static Future<bool?> show(BuildContext context) => showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const NewProjectDialog(),
      );

  @override
  State<NewProjectDialog> createState() => _NewProjectDialogState();
}

class _NewProjectDialogState extends State<NewProjectDialog> {
  final _name = TextEditingController();
  final _vehicle = TextEditingController();
  final _type = TextEditingController();
  final _specs = [TextEditingController(), TextEditingController(), TextEditingController()];
  final _details = TextEditingController();
  final _summary = TextEditingController();
  final _image = TextEditingController();
  String? _source;
  String _powertrain = 'ice';
  ProgrammeStatus _status = ProgrammeStatus.upcoming;

  bool _looking = false;
  bool _saving = false;
  String? _lookupNote;
  bool _lookupFailed = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_name, _vehicle, _type, _details, _summary, _image, ..._specs]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _lookup() async {
    final v = _vehicle.text.trim();
    if (v.isEmpty) {
      setState(() => _error = 'Type the vehicle first, e.g. "Hyundai Creta".');
      return;
    }
    setState(() {
      _looking = true;
      _error = null;
      _lookupNote = null;
    });
    try {
      final f = await VehicleLookupService.lookup(v);
      if (!mounted) return;
      if (f == null) {
        setState(() {
          _lookupFailed = true;
          _lookupNote = 'Nothing found for "$v". Fill the details in by hand.';
        });
        return;
      }
      setState(() {
        _type.text = f.vehicleType;
        _powertrain = f.powertrain;
        for (var i = 0; i < 3; i++) {
          _specs[i].text = i < f.specs.length ? f.specs[i] : '';
        }
        _details.text = f.details.join('\n');
        _summary.text = f.description.isEmpty
            ? f.summary
            : '${f.description[0].toUpperCase()}${f.description.substring(1)}. ${f.summary}';
        _image.text = f.imageUrl ?? '';
        _source = f.sourceUrl;
        _lookupFailed = false;
        _lookupNote = 'Found "${f.title}" on Wikipedia. Check the details below — '
            'they are a starting point, not a source of record.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _lookupFailed = true;
        _lookupNote = 'Could not reach Wikipedia ($e). Fill the details in by hand.';
      });
    } finally {
      if (mounted) setState(() => _looking = false);
    }
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final vehicle = _vehicle.text.trim();
    if (name.isEmpty || vehicle.isEmpty) {
      setState(() => _error = 'A programme name and a vehicle are both needed.');
      return;
    }
    final key = ProgrammeProfile.keyFor(name);
    if (ProjectCatalog.byKey(key) != null) {
      setState(() => _error = 'There is already a programme called "$name".');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ProjectRegistry.instance.add(
        ProgrammeProfile(
          key: key,
          displayName: name,
          vehicle: vehicle,
          powertrain: _powertrain,
          vehicleType: _type.text,
          summary: _summary.text,
          specs: [for (final c in _specs) c.text],
          details: _details.text.split('\n'),
          imageUrl: _image.text,
          sourceUrl: _source,
        ),
        _status,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      final s = e.toString();
      setState(() {
        _saving = false;
        _error = s.contains('PGRST205') || s.contains('does not exist')
            ? 'One setup step first: paste 20261119090000_projects.sql into the '
                'Supabase SQL editor and run it.'
            : (s.contains('row-level security') || s.contains('42501')
                ? 'This account cannot add programmes (it is not on the writers list).'
                : 'Could not save: $s');
      });
    }
  }

  InputDecoration _deco(String hint, {String? label}) => InputDecoration(
        hintText: hint,
        labelText: label,
        labelStyle: _t(12, c: _muted),
        hintStyle: _t(12.5, c: const Color(0xFF4A5470)),
        isDense: true,
        filled: true,
        fillColor: _field,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _line)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _line)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: _teal.withAlpha(150))),
      );

  Widget _label(String s) => Padding(
        padding: const EdgeInsets.only(top: 14, bottom: 6),
        child: Text(s, style: _t(10.5, w: FontWeight.w800, c: _muted).copyWith(letterSpacing: 1)),
      );

  Widget _choice(String label, bool on, Color c, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: on ? c.withAlpha(36) : Colors.transparent,
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: on ? c : _line),
            ),
            child: Text(label, style: _t(12, w: on ? FontWeight.w800 : FontWeight.w600, c: on ? c : Colors.white70)),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final img = _image.text.trim();
    return Dialog(
      backgroundColor: _bg,
      insetPadding: const EdgeInsets.all(24),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18), side: BorderSide(color: _teal.withAlpha(60))),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760, maxHeight: 860),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 12, 4),
            child: Row(children: [
              const Icon(Icons.add_circle_outline, color: _teal, size: 22),
              const SizedBox(width: 10),
              Expanded(child: Text('New project', style: _t(18, w: FontWeight.w800))),
              IconButton(
                tooltip: 'Cancel',
                onPressed: _saving ? null : () => Navigator.pop(context, false),
                icon: const Icon(Icons.close, color: _muted),
              ),
            ]),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                    'Name the programme and the vehicle, then look the vehicle up. '
                    'It appears in Manual Entry, the muster, the Analyser and the '
                    'reports as soon as it is saved.',
                    style: _t(12, c: _muted, h: 1.45)),
                _label('PROGRAMME NAME'),
                TextField(controller: _name, style: _t(13.5), decoration: _deco('e.g. Hyundai Creta PoC')),
                _label('VEHICLE'),
                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: _vehicle,
                      style: _t(13.5),
                      decoration: _deco('e.g. Hyundai Creta'),
                      onSubmitted: (_) => _lookup(),
                    ),
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton.icon(
                    onPressed: _looking ? null : _lookup,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _teal.withAlpha(30),
                      foregroundColor: _teal,
                      side: BorderSide(color: _teal.withAlpha(140)),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: _looking
                        ? const SizedBox(
                            width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: _teal))
                        : const Icon(Icons.travel_explore, size: 18),
                    label: Text(_looking ? 'Looking…' : 'Look up online',
                        style: _t(12.5, w: FontWeight.w700, c: _teal)),
                  ),
                ]),
                if (_lookupNote != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(_lookupNote!,
                        style: _t(11.5, c: _lookupFailed ? _amber : _green, h: 1.4)),
                  ),
                _label('STATUS'),
                Wrap(spacing: 8, children: [
                  _choice('Upcoming', _status == ProgrammeStatus.upcoming, _amber,
                      () => setState(() => _status = ProgrammeStatus.upcoming)),
                  _choice('Active', _status == ProgrammeStatus.active, _green,
                      () => setState(() => _status = ProgrammeStatus.active)),
                ]),
                _label('POWERTRAIN'),
                Wrap(spacing: 8, children: [
                  _choice('Petrol / diesel (ICE)', _powertrain == 'ice', _teal,
                      () => setState(() => _powertrain = 'ice')),
                  _choice('Electric (BEV)', _powertrain == 'bev', _teal,
                      () => setState(() => _powertrain = 'bev')),
                ]),
                _label('VEHICLE TYPE'),
                TextField(controller: _type, style: _t(13), decoration: _deco('e.g. Compact crossover SUV')),
                _label('THREE HEADLINE SPECS (THE CARD CHIPS)'),
                Row(children: [
                  for (var i = 0; i < 3; i++) ...[
                    Expanded(
                      child: TextField(
                        controller: _specs[i],
                        style: _t(12.5),
                        decoration: _deco(['Engine / battery', 'Transmission', 'Drive / power'][i]),
                      ),
                    ),
                    if (i < 2) const SizedBox(width: 8),
                  ],
                ]),
                _label('DETAILS (ONE PER LINE — SHOWN ON HOVER)'),
                TextField(
                  controller: _details,
                  style: _t(12.5, h: 1.4),
                  minLines: 3,
                  maxLines: 7,
                  decoration: _deco('Engine: 1.5 L turbo petrol\nTransmission: 7-speed DCT\nOEM tyre size: 215/60 R17'),
                ),
                _label('DESCRIPTION'),
                TextField(
                  controller: _summary,
                  style: _t(12.5, h: 1.4),
                  minLines: 2,
                  maxLines: 5,
                  decoration: _deco('A line or two about the vehicle and the programme'),
                ),
                _label('PICTURE (WEB ADDRESS)'),
                TextField(
                  controller: _image,
                  style: _t(12),
                  decoration: _deco('Filled by the lookup, or paste an image link'),
                  onChanged: (_) => setState(() {}),
                ),
                if (img.startsWith('http'))
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.network(
                        img,
                        height: 170,
                        width: double.infinity,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          height: 60,
                          alignment: Alignment.center,
                          color: _field,
                          child: Text('This picture could not be loaded.', style: _t(11.5, c: _amber)),
                        ),
                      ),
                    ),
                  ),
                if (_source != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text('Source: $_source', style: _t(10.5, c: _muted)),
                  ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(_error!, style: _t(12, w: FontWeight.w600, c: _red)),
                  ),
                const SizedBox(height: 8),
              ]),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
            child: Row(children: [
              const Spacer(),
              TextButton(
                onPressed: _saving ? null : () => Navigator.pop(context, false),
                child: Text('Cancel', style: _t(13, c: _muted)),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: _saving ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _teal,
                  foregroundColor: const Color(0xFF050811),
                  padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: _saving
                    ? const SizedBox(
                        width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF050811)))
                    : Text('Add project', style: _t(13, w: FontWeight.w800, c: const Color(0xFF050811))),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

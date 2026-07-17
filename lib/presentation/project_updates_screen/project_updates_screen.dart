import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/engineer_auth_service.dart';
import '../../services/project_manager.dart';
import '../../services/supabase_service.dart';
import '../../theme/app_theme.dart';

// ─── Models ───────────────────────────────────────────────────────────────────

enum UpdateType { update, milestone, alert, attachment }

extension UpdateTypeX on UpdateType {
  String get label => switch (this) {
        UpdateType.update => 'Update',
        UpdateType.milestone => 'Milestone',
        UpdateType.alert => 'Alert',
        UpdateType.attachment => 'Attachment',
      };
  Color get color => switch (this) {
        UpdateType.update => const Color(0xFF4A9EFF),
        UpdateType.milestone => const Color(0xFF00F3FF),
        UpdateType.alert => const Color(0xFFFFB547),
        UpdateType.attachment => const Color(0xFFA855F7),
      };
  IconData get icon => switch (this) {
        UpdateType.update => Icons.update_rounded,
        UpdateType.milestone => Icons.flag_rounded,
        UpdateType.alert => Icons.warning_amber_rounded,
        UpdateType.attachment => Icons.attach_file_rounded,
      };
  String get dbValue => name;
  static UpdateType from(String? s) => UpdateType.values.firstWhere(
      (e) => e.name == s, orElse: () => UpdateType.update);
}

class ProjectUpdate {
  final String id;
  final String projectName;
  final String title;
  final String body;
  final UpdateType type;
  final String authorName;
  final String authorEmail;
  final List<String> attachmentUrls;
  final DateTime createdAt;

  const ProjectUpdate({
    required this.id,
    required this.projectName,
    required this.title,
    required this.body,
    required this.type,
    required this.authorName,
    required this.authorEmail,
    required this.attachmentUrls,
    required this.createdAt,
  });

  factory ProjectUpdate.fromJson(Map<String, dynamic> j) => ProjectUpdate(
        id: j['id'] as String,
        projectName: j['project_name'] as String? ?? '',
        title: j['title'] as String? ?? '',
        body: j['body'] as String? ?? '',
        type: UpdateTypeX.from(j['type'] as String?),
        authorName: j['author_name'] as String? ?? 'Team',
        authorEmail: j['author_email'] as String? ?? '',
        attachmentUrls: (j['attachment_urls'] as List?)?.cast<String>() ?? [],
        createdAt: DateTime.tryParse(j['created_at'] as String? ?? '') ?? DateTime.now(),
      );
}

// ─── Screen ───────────────────────────────────────────────────────────────────

class ProjectUpdatesScreen extends StatefulWidget {
  const ProjectUpdatesScreen({super.key});
  @override
  State<ProjectUpdatesScreen> createState() => _ProjectUpdatesScreenState();
}

class _ProjectUpdatesScreenState extends State<ProjectUpdatesScreen> {
  bool _isLoading = true;
  List<ProjectUpdate> _updates = [];
  UpdateType? _filterType;
  String _activeProject = '';
  EngineerProfile? _profile;

  @override
  void initState() {
    super.initState();
    _activeProject = ProjectManager.instance.activeProject;
    ProjectManager.instance.addListener(_onProjectChanged);
    _loadProfile();
    _loadUpdates();
  }

  @override
  void dispose() {
    ProjectManager.instance.removeListener(_onProjectChanged);
    super.dispose();
  }

  void _onProjectChanged() {
    if (mounted && _activeProject != ProjectManager.instance.activeProject) {
      setState(() => _activeProject = ProjectManager.instance.activeProject);
      _loadUpdates();
    }
  }

  Future<void> _loadProfile() async {
    final p = await EngineerAuthService.instance.getCurrentProfile();
    if (mounted) setState(() => _profile = p);
  }

  Future<void> _loadUpdates() async {
    setState(() => _isLoading = true);
    try {
      final client = SupabaseService.instance.client;
      final data = await client
          .from('project_updates')
          .select()
          .eq('project_name', _activeProject)
          .order('created_at', ascending: false);

      if (mounted) {
        setState(() {
          _updates = (data as List).map((e) => ProjectUpdate.fromJson(e)).toList();
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  List<ProjectUpdate> get _filtered => _filterType == null
      ? _updates
      : _updates.where((u) => u.type == _filterType).toList();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showComposeSheet,
        backgroundColor: AppTheme.primary,
        foregroundColor: const Color(0xFF001A10),
        icon: const Icon(Icons.add_rounded, size: 20),
        label: Text('Post Update',
            style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w700)),
      ),
      body: SafeArea(
        bottom: false,
        child: Stack(
          children: [
            Positioned.fill(
              child: Image.asset(
                'assets/images/GYRacing_DesktopTeamsWallpaper_5-1779284234231.png',
                fit: BoxFit.cover,
              ),
            ),
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      const Color(0xFF042024).withAlpha(225),
                      const Color(0xFF030712).withAlpha(245),
                    ],
                    stops: const [0.0, 0.7],
                  ),
                ),
              ),
            ),
            _isLoading
                ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
                : CustomScrollView(
                    slivers: [
                      SliverToBoxAdapter(child: _buildHeader()),
                      SliverToBoxAdapter(child: _buildFilterRow()),
                      if (_filtered.isEmpty)
                        SliverFillRemaining(child: _buildEmpty())
                      else
                        SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (_, i) => _buildUpdateCard(_filtered[i]),
                            childCount: _filtered.length,
                          ),
                        ),
                      const SliverToBoxAdapter(child: SizedBox(height: 120)),
                    ],
                  ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Row(
        children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (kIsWeb)
                GestureDetector(
                  onTap: () => ProjectManager.instance.setProject(''),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.arrow_back_ios_rounded, color: Color(0xFF94A3B8), size: 14),
                    const SizedBox(width: 4),
                    Text('All Projects',
                        style: GoogleFonts.spaceGrotesk(fontSize: 12, color: const Color(0xFF94A3B8))),
                  ]),
                ),
              if (kIsWeb) const SizedBox(height: 8),
              Text('Project Updates',
                  style: GoogleFonts.spaceGrotesk(
                      fontSize: 24, fontWeight: FontWeight.w800, color: Colors.white)),
              Row(children: [
                Text('$_activeProject · ', style: GoogleFonts.spaceGrotesk(fontSize: 12, color: const Color(0xFF6B7490))),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withAlpha(30),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppTheme.primary.withAlpha(80)),
                  ),
                  child: Text('${_updates.length} posts',
                      style: GoogleFonts.spaceGrotesk(
                          fontSize: 10, fontWeight: FontWeight.w700, color: AppTheme.primary)),
                ),
              ]),
            ]),
          ),
          // Subscribers button
          GestureDetector(
            onTap: _showSubscribersSheet,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF0A1025).withAlpha(180),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF849495).withAlpha(100)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.group_outlined, color: Color(0xFF6B7490), size: 18),
                const SizedBox(width: 6),
                Text('Subscribers',
                    style: GoogleFonts.spaceGrotesk(color: const Color(0xFF6B7490), fontSize: 12)),
              ]),
            ),
          ),
          const SizedBox(width: 12),
          Image.asset(
            'assets/images/goodyear_sightline_logo.png',
            height: 20,
            color: Colors.white70,
            fit: BoxFit.contain,
          ),
        ],
      ),
    );
  }

  Widget _buildFilterRow() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _filterChip(null, 'All', const Color(0xFF94A3B8)),
            ...UpdateType.values.map((t) => _filterChip(t, t.label, t.color)),
          ],
        ),
      ),
    );
  }

  Widget _filterChip(UpdateType? type, String label, Color color) {
    final selected = _filterType == type;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: () => setState(() => _filterType = type),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: selected ? color.withAlpha(38) : const Color(0xFF0A1025),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected ? color.withAlpha(128) : const Color(0xFF849495),
              width: 1,
            ),
          ),
          child: Text(label,
              style: GoogleFonts.spaceGrotesk(
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? color : const Color(0xFFA8B0C8))),
        ),
      ),
    );
  }

  Widget _buildUpdateCard(ProjectUpdate u) {
    final dateFmt = DateFormat('d MMM yyyy · HH:mm');
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF0A1025).withAlpha(200),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: u.type.color.withAlpha(60)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // Type badge + date
              Row(children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: u.type.color.withAlpha(30),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: u.type.color.withAlpha(80)),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(u.type.icon, color: u.type.color, size: 11),
                    const SizedBox(width: 4),
                    Text(u.type.label,
                        style: GoogleFonts.spaceGrotesk(
                            fontSize: 10, fontWeight: FontWeight.w700, color: u.type.color)),
                  ]),
                ),
                const Spacer(),
                Text(dateFmt.format(u.createdAt.toLocal()),
                    style: GoogleFonts.spaceGrotesk(fontSize: 10, color: const Color(0xFF6B7490))),
              ]),
              const SizedBox(height: 10),
              // Title
              Text(u.title,
                  style: GoogleFonts.spaceGrotesk(
                      fontSize: 15, fontWeight: FontWeight.w800, color: Colors.white)),
              const SizedBox(height: 6),
              // Body
              Text(u.body,
                  style: GoogleFonts.spaceGrotesk(
                      fontSize: 13, color: const Color(0xFF94A3B8), height: 1.55)),
              // Attachments
              if (u.attachmentUrls.isNotEmpty) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  children: u.attachmentUrls.map((url) {
                    final name = url.split('/').last;
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: const Color(0xFFA855F7).withAlpha(20),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFA855F7).withAlpha(60)),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.attach_file_rounded, color: Color(0xFFA855F7), size: 12),
                        const SizedBox(width: 4),
                        Text(name,
                            style: GoogleFonts.spaceGrotesk(
                                fontSize: 10, color: const Color(0xFFA855F7))),
                      ]),
                    );
                  }).toList(),
                ),
              ],
              const SizedBox(height: 10),
              // Author
              Row(children: [
                Container(
                  width: 24, height: 24,
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withAlpha(30),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      u.authorName.isNotEmpty ? u.authorName[0].toUpperCase() : 'T',
                      style: GoogleFonts.spaceGrotesk(
                          fontSize: 10, fontWeight: FontWeight.w700, color: AppTheme.primary),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(u.authorName,
                    style: GoogleFonts.spaceGrotesk(fontSize: 11, color: const Color(0xFF6B7490))),
              ]),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.campaign_outlined, color: Colors.white.withAlpha(40), size: 48),
        const SizedBox(height: 12),
        Text('No updates yet',
            style: GoogleFonts.spaceGrotesk(fontSize: 14, color: const Color(0xFF6B7490))),
        const SizedBox(height: 6),
        Text('Post the first update for $_activeProject',
            style: GoogleFonts.spaceGrotesk(fontSize: 12, color: const Color(0xFF4A5470))),
      ]),
    );
  }

  void _showComposeSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ComposeUpdateSheet(
        projectName: _activeProject,
        authorName: _profile?.engineerName ?? 'Team',
        authorEmail: _profile?.email ?? '',
        isManager: _profile?.isManager ?? false,
        onPosted: () {
          Navigator.pop(context);
          _loadUpdates();
        },
      ),
    );
  }

  void _showSubscribersSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _SubscribersSheet(projectName: _activeProject),
    );
  }
}

// ─── Compose Sheet ────────────────────────────────────────────────────────────

class _ComposeUpdateSheet extends StatefulWidget {
  final String projectName;
  final String authorName;
  final String authorEmail;
  final bool isManager;
  final VoidCallback onPosted;
  const _ComposeUpdateSheet({
    required this.projectName,
    required this.authorName,
    required this.authorEmail,
    required this.isManager,
    required this.onPosted,
  });
  @override
  State<_ComposeUpdateSheet> createState() => _ComposeUpdateSheetState();
}

class _ComposeUpdateSheetState extends State<_ComposeUpdateSheet> {
  final _titleCtrl = TextEditingController();
  final _bodyCtrl = TextEditingController();
  UpdateType _type = UpdateType.update;
  bool _notifyEmail = true;
  bool _notifyTeams = false;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _bodyCtrl.dispose();
    super.dispose();
  }

  bool get _isAdmin => widget.isManager;

  String _buildSubject() =>
      '[${_type.label}] ${widget.projectName}: ${_titleCtrl.text.trim()}';

  void _showPreview() {
    if (_titleCtrl.text.trim().isEmpty || _bodyCtrl.text.trim().isEmpty) {
      setState(() => _error = 'Title and body are required to preview');
      return;
    }
    setState(() => _error = null);
    showDialog(
      context: context,
      barrierColor: Colors.black.withAlpha(180),
      builder: (_) => _EmailPreviewDialog(
        subject: _buildSubject(),
        projectName: widget.projectName,
        title: _titleCtrl.text.trim(),
        body: _bodyCtrl.text.trim(),
        type: _type,
        authorName: widget.authorName,
        notifyEmail: _notifyEmail,
        notifyTeams: _notifyTeams,
        onSend: () {
          Navigator.pop(context);
          _post(fromPreview: true);
        },
      ),
    );
  }

  Future<void> _post({bool fromPreview = false}) async {
    if (_titleCtrl.text.trim().isEmpty || _bodyCtrl.text.trim().isEmpty) {
      setState(() => _error = 'Title and body are required');
      return;
    }
    setState(() { _saving = true; _error = null; });
    try {
      final client = SupabaseService.instance.client;
      await client.from('project_updates').insert({
        'project_name': widget.projectName,
        'title': _titleCtrl.text.trim(),
        'body': _bodyCtrl.text.trim(),
        'type': _type.dbValue,
        'author_name': widget.authorName,
        'author_email': widget.authorEmail,
        'attachment_urls': [],
        'notify_email': _notifyEmail,
        'notify_teams': _notifyTeams,
      });

      if (_notifyEmail) {
        try {
          await client.functions.invoke('send-project-update', body: {
            'projectName': widget.projectName,
            'title': _titleCtrl.text.trim(),
            'body': _bodyCtrl.text.trim(),
            'type': _type.label,
            'authorName': widget.authorName,
            'authorEmail': widget.authorEmail,
            'senderEmail': 'dhrupad_ma@goodyear.com',
          });
        } catch (_) {}
      }

      widget.onPosted();
    } catch (e) {
      setState(() { _saving = false; _error = e.toString(); });
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      builder: (_, ctrl) => ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            color: const Color(0xFF0A1025),
            child: ListView(
              controller: ctrl,
              padding: EdgeInsets.fromLTRB(24, 0, 24, MediaQuery.of(context).viewInsets.bottom + 32),
              children: [
                const SizedBox(height: 12),
                Center(child: Container(width: 40, height: 4,
                    decoration: BoxDecoration(color: const Color(0xFF849495), borderRadius: BorderRadius.circular(2)))),
                const SizedBox(height: 20),
                Text('Post Update', style: GoogleFonts.spaceGrotesk(
                    color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
                Text('for ${widget.projectName}', style: GoogleFonts.spaceGrotesk(
                    color: const Color(0xFF6B7490), fontSize: 12)),
                const SizedBox(height: 20),

                // Type selector
                Text('Type', style: _lbl()),
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(children: UpdateType.values.map((t) {
                    final sel = _type == t;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: GestureDetector(
                        onTap: () => setState(() => _type = t),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: sel ? t.color.withAlpha(40) : const Color(0xFF0D1421),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: sel ? t.color : const Color(0xFF2A3450)),
                          ),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(t.icon, color: sel ? t.color : const Color(0xFF6B7490), size: 14),
                            const SizedBox(width: 6),
                            Text(t.label, style: GoogleFonts.spaceGrotesk(
                                color: sel ? t.color : const Color(0xFF6B7490),
                                fontSize: 12, fontWeight: sel ? FontWeight.w700 : FontWeight.w500)),
                          ]),
                        ),
                      ),
                    );
                  }).toList()),
                ),
                const SizedBox(height: 16),

                // Title
                Text('Title', style: _lbl()),
                const SizedBox(height: 6),
                _field(_titleCtrl, 'e.g. T3 Wet track cleared for testing', maxLines: 1),
                const SizedBox(height: 14),

                // Body
                Text('Details', style: _lbl()),
                const SizedBox(height: 6),
                _field(_bodyCtrl, 'Add details, findings, next steps...', maxLines: 4),
                const SizedBox(height: 16),

                // Notifications
                Text('Notify subscribers via', style: _lbl()),
                const SizedBox(height: 8),
                Row(children: [
                  _toggle('Email', Icons.email_outlined, _notifyEmail,
                      (v) => setState(() => _notifyEmail = v)),
                  const SizedBox(width: 12),
                  _toggle('Teams', Icons.groups_outlined, _notifyTeams,
                      (v) => setState(() => _notifyTeams = v)),
                ]),

                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.redAccent.withAlpha(26),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.redAccent.withAlpha(80)),
                    ),
                    child: Text(_error!, style: GoogleFonts.spaceGrotesk(color: Colors.redAccent, fontSize: 12)),
                  ),
                ],
                const SizedBox(height: 24),
                if (_isAdmin && _notifyEmail) ...[
                  // Manager sees Preview → then Send from preview dialog
                  Row(children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _saving ? null : _showPreview,
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: const Color(0xFFFFB547).withAlpha(200)),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        icon: const Icon(Icons.preview_rounded, color: Color(0xFFFFB547), size: 16),
                        label: Text('Preview Email',
                            style: GoogleFonts.spaceGrotesk(
                                color: const Color(0xFFFFB547), fontWeight: FontWeight.w700)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _saving ? null : () => _post(),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primary,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        icon: _saving
                            ? const SizedBox(width: 16, height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF001A10)))
                            : const Icon(Icons.send_rounded, color: Color(0xFF001A10), size: 16),
                        label: Text(_saving ? 'Posting…' : 'Post & Send',
                            style: GoogleFonts.spaceGrotesk(
                                color: const Color(0xFF001A10), fontWeight: FontWeight.w800)),
                      ),
                    ),
                  ]),
                ] else ...[
                  ElevatedButton.icon(
                    onPressed: _saving ? null : () => _post(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: _saving
                        ? const SizedBox(width: 16, height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF001A10)))
                        : const Icon(Icons.send_rounded, color: Color(0xFF001A10), size: 18),
                    label: Text(_saving ? 'Posting…' : 'Post & Notify',
                        style: GoogleFonts.spaceGrotesk(
                            color: const Color(0xFF001A10), fontWeight: FontWeight.w800)),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  TextStyle _lbl() => GoogleFonts.spaceGrotesk(
      color: const Color(0xFF8A94B0), fontSize: 12, fontWeight: FontWeight.w600);

  Widget _field(TextEditingController ctrl, String hint, {int maxLines = 1}) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0D1421),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF2A3450)),
      ),
      child: TextField(
        controller: ctrl,
        maxLines: maxLines,
        style: GoogleFonts.spaceGrotesk(color: Colors.white, fontSize: 13),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: GoogleFonts.spaceGrotesk(color: const Color(0xFF4A5470), fontSize: 12),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.all(14),
        ),
      ),
    );
  }

  Widget _toggle(String label, IconData icon, bool value, ValueChanged<bool> onChanged) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: value ? AppTheme.primary.withAlpha(30) : const Color(0xFF0D1421),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: value ? AppTheme.primary.withAlpha(100) : const Color(0xFF2A3450)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: value ? AppTheme.primary : const Color(0xFF6B7490), size: 16),
          const SizedBox(width: 6),
          Text(label, style: GoogleFonts.spaceGrotesk(
              color: value ? AppTheme.primary : const Color(0xFF6B7490),
              fontSize: 12, fontWeight: value ? FontWeight.w700 : FontWeight.w500)),
        ]),
      ),
    );
  }
}

// ─── Email Preview Dialog ─────────────────────────────────────────────────────

class _EmailPreviewDialog extends StatelessWidget {
  final String subject;
  final String projectName;
  final String title;
  final String body;
  final UpdateType type;
  final String authorName;
  final bool notifyEmail;
  final bool notifyTeams;
  final VoidCallback onSend;

  const _EmailPreviewDialog({
    required this.subject,
    required this.projectName,
    required this.title,
    required this.body,
    required this.type,
    required this.authorName,
    required this.notifyEmail,
    required this.notifyTeams,
    required this.onSend,
  });

  static const _to = 'praharshithkumar_komaragiri@goodyear.com';
  static const _cc = ['v_vimal@goodyear.com', 'ashish_pandit@goodyear.com',
                       'yeswanth_golla@goodyear.com', 'niranjan_poloju@goodyear.com'];
  static const _from = 'dhrupad_ma@goodyear.com';

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            width: 700,
            constraints: const BoxConstraints(maxHeight: 720),
            decoration: BoxDecoration(
              color: const Color(0xFF0A1025),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFF849495).withAlpha(60)),
            ),
            child: Column(
              children: [
                // Dialog header
                Container(
                  padding: const EdgeInsets.fromLTRB(24, 20, 20, 16),
                  decoration: BoxDecoration(
                    border: Border(bottom: BorderSide(color: Colors.white.withAlpha(15))),
                  ),
                  child: Row(children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFB547).withAlpha(30),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.preview_rounded, color: Color(0xFFFFB547), size: 18),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Email Preview',
                          style: GoogleFonts.spaceGrotesk(
                              color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
                      Text('Review before sending to team',
                          style: GoogleFonts.spaceGrotesk(
                              color: const Color(0xFF6B7490), fontSize: 11)),
                    ])),
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Icon(Icons.close_rounded, color: Colors.white.withAlpha(100), size: 20),
                    ),
                  ]),
                ),

                // Email metadata
                Container(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                  child: Column(children: [
                    _metaRow('From', _from, const Color(0xFF94A3B8)),
                    _metaRow('To', _to, AppTheme.primary),
                    _metaRow('CC', _cc.join(' · '), const Color(0xFF94A3B8)),
                    _metaRow('Subject', subject, Colors.white),
                    const SizedBox(height: 12),
                    Container(height: 1, color: Colors.white.withAlpha(10)),
                  ]),
                ),

                // Email body preview
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: _buildEmailBody(),
                  ),
                ),

                // Action buttons
                Container(
                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
                  decoration: BoxDecoration(
                    border: Border(top: BorderSide(color: Colors.white.withAlpha(10))),
                  ),
                  child: Row(children: [
                    // Notification channels
                    Row(children: [
                      if (notifyEmail) _channelBadge(Icons.email_rounded, 'Email', AppTheme.primary),
                      if (notifyTeams) ...[
                        const SizedBox(width: 8),
                        _channelBadge(Icons.groups_rounded, 'Teams', const Color(0xFF4A9EFF)),
                      ],
                    ]),
                    const Spacer(),
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text('Edit', style: GoogleFonts.spaceGrotesk(
                          color: const Color(0xFF6B7490), fontWeight: FontWeight.w600)),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: onSend,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      icon: const Icon(Icons.send_rounded, color: Color(0xFF001A10), size: 16),
                      label: Text('Confirm & Send',
                          style: GoogleFonts.spaceGrotesk(
                              color: const Color(0xFF001A10), fontWeight: FontWeight.w800)),
                    ),
                  ]),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmailBody() {
    final ts = DateFormat('dd MMM yyyy · HH:mm').format(DateTime.now());
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1520),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withAlpha(10)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Email header bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF00F3FF), Color(0xFF4A9EFF)],
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(children: [
            Text('NATRAX TrackLog',
                style: GoogleFonts.spaceGrotesk(
                    color: Colors.white, fontSize: 13, fontWeight: FontWeight.w800)),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(30),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(type.label.toUpperCase(),
                  style: GoogleFonts.spaceGrotesk(
                      color: Colors.white, fontSize: 9,
                      fontWeight: FontWeight.w700, letterSpacing: 1.5)),
            ),
          ]),
        ),

        // Project badge
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: type.color.withAlpha(25),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: type.color.withAlpha(60)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(type.icon, color: type.color, size: 12),
            const SizedBox(width: 6),
            Text(projectName,
                style: GoogleFonts.spaceGrotesk(
                    color: type.color, fontSize: 11, fontWeight: FontWeight.w700)),
          ]),
        ),
        const SizedBox(height: 14),

        // Title
        Text(title,
            style: GoogleFonts.spaceGrotesk(
                color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800, height: 1.3)),
        const SizedBox(height: 10),

        // Body
        Text(body,
            style: GoogleFonts.spaceGrotesk(
                color: const Color(0xFF94A3B8), fontSize: 13, height: 1.7)),

        const SizedBox(height: 20),
        Container(height: 1, color: Colors.white.withAlpha(10)),
        const SizedBox(height: 14),

        // Signature
        Row(children: [
          Container(
            width: 32, height: 32,
            decoration: BoxDecoration(
                color: AppTheme.primary.withAlpha(30), shape: BoxShape.circle),
            child: Center(child: Text('D',
                style: GoogleFonts.spaceGrotesk(
                    color: AppTheme.primary, fontSize: 14, fontWeight: FontWeight.w800))),
          ),
          const SizedBox(width: 10),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(authorName,
                style: GoogleFonts.spaceGrotesk(
                    color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
            Text('Goodyear · NATRAX PoC Team',
                style: GoogleFonts.spaceGrotesk(
                    color: const Color(0xFF6B7490), fontSize: 10)),
          ]),
          const Spacer(),
          Text(ts, style: GoogleFonts.spaceGrotesk(
              color: const Color(0xFF4A5470), fontSize: 10)),
        ]),
      ]),
    );
  }

  Widget _metaRow(String label, String value, Color valueColor) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 52,
            child: Text(label,
                style: GoogleFonts.spaceGrotesk(
                    color: const Color(0xFF4A5470), fontSize: 11, fontWeight: FontWeight.w600))),
        const SizedBox(width: 8),
        Expanded(child: Text(value,
            style: GoogleFonts.spaceGrotesk(color: valueColor, fontSize: 11),
            overflow: TextOverflow.ellipsis, maxLines: 2)),
      ]),
    );
  }

  Widget _channelBadge(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withAlpha(20),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withAlpha(60)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, color: color, size: 13),
        const SizedBox(width: 5),
        Text(label, style: GoogleFonts.spaceGrotesk(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

// ─── Subscribers Sheet ────────────────────────────────────────────────────────

class _SubscribersSheet extends StatefulWidget {
  final String projectName;
  const _SubscribersSheet({required this.projectName});
  @override
  State<_SubscribersSheet> createState() => _SubscribersSheetState();
}

class _SubscribersSheetState extends State<_SubscribersSheet> {
  List<Map<String, dynamic>> _subs = [];
  bool _loading = true;
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await SupabaseService.instance.client
          .from('update_subscribers')
          .select()
          .eq('project_name', widget.projectName)
          .order('created_at');
      if (mounted) setState(() { _subs = (data as List).cast(); _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addSub() async {
    if (_nameCtrl.text.trim().isEmpty || _emailCtrl.text.trim().isEmpty) return;
    setState(() => _saving = true);
    try {
      await SupabaseService.instance.client.from('update_subscribers').insert({
        'project_name': widget.projectName,
        'name': _nameCtrl.text.trim(),
        'email': _emailCtrl.text.trim(),
        'notify_email': true,
        'notify_teams': false,
        'is_active': true,
      });
      _nameCtrl.clear();
      _emailCtrl.clear();
      await _load();
    } catch (_) {}
    if (mounted) setState(() => _saving = false);
  }

  Future<void> _toggle(String id, bool current) async {
    await SupabaseService.instance.client
        .from('update_subscribers')
        .update({'is_active': !current}).eq('id', id);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      maxChildSize: 0.92,
      builder: (_, ctrl) => ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            color: const Color(0xFF0A1025),
            child: ListView(
              controller: ctrl,
              padding: EdgeInsets.fromLTRB(24, 0, 24, MediaQuery.of(context).viewInsets.bottom + 32),
              children: [
                const SizedBox(height: 12),
                Center(child: Container(width: 40, height: 4,
                    decoration: BoxDecoration(color: const Color(0xFF849495), borderRadius: BorderRadius.circular(2)))),
                const SizedBox(height: 20),
                Text('Subscribers', style: GoogleFonts.spaceGrotesk(
                    color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
                Text('${widget.projectName} · Gets notified on new posts',
                    style: GoogleFonts.spaceGrotesk(color: const Color(0xFF6B7490), fontSize: 12)),
                const SizedBox(height: 20),
                // Add form
                Row(children: [
                  Expanded(child: _mini(_nameCtrl, 'Name')),
                  const SizedBox(width: 8),
                  Expanded(flex: 2, child: _mini(_emailCtrl, 'email@goodyear.com')),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: _saving ? null : _addSub,
                    child: Container(
                      width: 40, height: 40,
                      decoration: BoxDecoration(
                          color: AppTheme.primary, borderRadius: BorderRadius.circular(10)),
                      child: _saving
                          ? const Center(child: SizedBox(width: 16, height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black)))
                          : const Icon(Icons.add, color: Colors.black, size: 20),
                    ),
                  ),
                ]),
                const SizedBox(height: 20),
                if (_loading)
                  const Center(child: CircularProgressIndicator(color: AppTheme.primary))
                else
                  ..._subs.map((s) => _subRow(s)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _mini(TextEditingController c, String hint) => Container(
    height: 40,
    decoration: BoxDecoration(
        color: const Color(0xFF0D1421), borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF2A3450))),
    child: TextField(
      controller: c,
      style: GoogleFonts.spaceGrotesk(color: Colors.white, fontSize: 12),
      decoration: InputDecoration(hintText: hint,
          hintStyle: GoogleFonts.spaceGrotesk(color: const Color(0xFF4A5470), fontSize: 11),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
    ),
  );

  Widget _subRow(Map<String, dynamic> s) {
    final active = s['is_active'] as bool? ?? true;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(children: [
        Container(
          width: 32, height: 32,
          decoration: BoxDecoration(
              color: AppTheme.primary.withAlpha(30), shape: BoxShape.circle),
          child: Center(child: Text(
            (s['name'] as String? ?? 'T')[0].toUpperCase(),
            style: GoogleFonts.spaceGrotesk(color: AppTheme.primary, fontSize: 13, fontWeight: FontWeight.w700),
          )),
        ),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(s['name'] as String? ?? '', style: GoogleFonts.spaceGrotesk(
              color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
          Text(s['email'] as String? ?? '', style: GoogleFonts.spaceGrotesk(
              color: const Color(0xFF6B7490), fontSize: 11)),
        ])),
        Switch(
          value: active,
          onChanged: (_) => _toggle(s['id'] as String, active),
          activeColor: AppTheme.primary,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ]),
    );
  }
}

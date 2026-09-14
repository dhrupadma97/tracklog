import 'package:flutter/foundation.dart';

/// Global project context manager.
/// Holds the currently active project key and broadcasts changes.
class ProjectManager extends ChangeNotifier {
  static final ProjectManager _instance = ProjectManager._();
  static ProjectManager get instance => _instance;
  ProjectManager._();

  String _activeProject = 'Mahindra EV PoC';
  String get activeProject => _activeProject;

  /// Normalised key (lowercase, trimmed)
  String get activeKey => _activeProject.toLowerCase().trim();

  void setProject(String project) {
    if (_activeProject != project) {
      _activeProject = project;
      notifyListeners();
    }
  }

  /// Returns true if a session should be shown for the current project.
  /// General/empty project_name sessions always belong to Mahindra EV PoC.
  bool sessionBelongsToProject(String? sessionProjectName) =>
      sessionBelongsTo(sessionProjectName, _activeProject);

  /// The same rule, asked about an arbitrary project rather than the globally
  /// selected one.
  ///
  /// Exists because not every screen is scoped by [ProjectManager]. The
  /// Analyser picks its own vehicle and is deliberately independent of the
  /// global selection, but it filtered sessions through
  /// [sessionBelongsToProject] — the global one — while labelling the result
  /// with its own choice. Picking Mahindra ICE PoC therefore showed Mahindra
  /// EV PoC's sessions under an ICE heading: May 2026 figures for a vehicle
  /// that arrived in September.
  ///
  /// Kept as one implementation on purpose. The Empty/General rule is a data
  /// convention, not a UI detail, and a second copy of it would drift.
  static bool sessionBelongsTo(String? sessionProjectName, String projectName) {
    final raw = (sessionProjectName ?? '').trim();
    final key = projectName.toLowerCase().trim();
    // Empty/General → Mahindra EV PoC
    if (raw.isEmpty || raw.toLowerCase() == 'general') {
      return key == 'mahindra ev poc';
    }
    return raw.toLowerCase() == key;
  }
}

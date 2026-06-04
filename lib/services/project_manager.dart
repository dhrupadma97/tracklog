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
  bool sessionBelongsToProject(String? sessionProjectName) {
    final raw = (sessionProjectName ?? '').trim();
    // Empty/General → Mahindra EV PoC
    if (raw.isEmpty || raw.toLowerCase() == 'general') {
      return activeKey == 'mahindra ev poc';
    }
    return raw.toLowerCase() == activeKey;
  }
}

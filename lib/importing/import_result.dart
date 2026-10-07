import '../domain/models.dart';

/// A single, user-facing problem encountered while importing a file.
///
/// Diagnostics are deliberately retained instead of throwing for individual
/// rows. This lets the import UI show a preview and allows a user to fix one
/// bad row without losing the valid rows from a timetable export.
class ImportDiagnostic {
  const ImportDiagnostic({
    this.line,
    required this.message,
    this.isError = true,
  });

  final int? line;
  final String message;
  final bool isError;

  @override
  String toString() => line == null ? message : 'line $line: $message';
}

class ImportResult {
  const ImportResult({
    required this.courses,
    required this.diagnostics,
    required this.skippedRows,
    required this.sourceLabel,
  });

  final List<Course> courses;
  final List<ImportDiagnostic> diagnostics;
  final int skippedRows;
  final String sourceLabel;

  bool get hasErrors => diagnostics.any((d) => d.isError);
  bool get hasWarnings => diagnostics.any((d) => !d.isError);
}

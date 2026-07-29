import '../domain/owner_alpha_models.dart';

/// Temporary Android 16 launch-safety gateway.
///
/// The previous implementation registered WorkManager and local-notification
/// plugins in the application process. Physical-device feedback showed an
/// immediate process crash before the first Flutter frame. Background scans are
/// therefore fail-closed in this hotfix while foreground scanning, journaling,
/// and native in-app notifications remain available.
///
/// A background implementation may replace this class only after it passes a
/// real cold-start smoke test on Android 14, 15, and 16.
final class WorkmanagerBackgroundScanGateway implements BackgroundScanGateway {
  const WorkmanagerBackgroundScanGateway();

  @override
  Future<void> configure({
    required bool enabled,
    required OwnerAlphaSettings settings,
    required String languageCode,
  }) async {
    // Intentionally unavailable in the Android 16 cold-start hotfix.
  }
}

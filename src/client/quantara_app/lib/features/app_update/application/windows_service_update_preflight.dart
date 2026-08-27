// Keep the public named dependency explicit while storing it privately.
// ignore_for_file: prefer_initializing_formals

import '../../windows_desktop/application/windows_service_status_reader.dart';
import '../../windows_desktop/domain/windows_service_protocol.dart';

final class WindowsServiceUpdatePreflightException implements Exception {
  const WindowsServiceUpdatePreflightException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Read-only, fail-closed gate before handing a verified Windows artifact to
/// the operating system installer.
///
/// The authenticated native helper remains the source of service truth. The
/// installer path is allowed only while the service is explicitly disarmed;
/// interrupted, reconciliation-required, malformed, unavailable, or
/// unauthenticated status blocks the handoff without mutating service state.
final class WindowsServiceUpdatePreflight {
  const WindowsServiceUpdatePreflight({
    required WindowsServiceStatusReader reader,
  }) : _reader = reader;

  final WindowsServiceStatusReader _reader;

  Future<void> assertSafeForInstallerHandoff() async {
    late WindowsServiceStatusSnapshot snapshot;
    try {
      snapshot = await _reader.read();
    } on Object {
      throw const WindowsServiceUpdatePreflightException(
        'Windows service status could not be verified; update handoff is blocked.',
      );
    }

    if (snapshot.safetyState != WindowsServiceSafetyState.disarmed) {
      throw WindowsServiceUpdatePreflightException(
        'Windows service is ${snapshot.safetyState.name}; update handoff requires an authenticated disarmed service.',
      );
    }
  }
}

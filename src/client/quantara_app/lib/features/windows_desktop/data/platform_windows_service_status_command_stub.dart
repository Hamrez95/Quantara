import '../application/windows_service_status_reader.dart';

WindowsServiceStatusCommand createWindowsServiceStatusCommand() {
  return () async {
    throw const WindowsServiceStatusReadException(
      'Windows service status is unavailable on this platform.',
    );
  };
}

import '../application/windows_service_status_reader.dart';
import 'platform_windows_service_status_command_stub.dart'
    if (dart.library.io) 'platform_windows_service_status_command_io.dart'
    as platform;

WindowsServiceStatusReader createPlatformWindowsServiceStatusReader() {
  return WindowsServiceStatusReader(
    command: platform.createWindowsServiceStatusCommand(),
  );
}

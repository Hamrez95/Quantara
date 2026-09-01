import '../application/windows_service_management_client.dart';
import 'platform_windows_service_management_command_stub.dart'
    if (dart.library.io) 'platform_windows_service_management_command_io.dart'
    as platform;

WindowsServiceManagementClient createPlatformWindowsServiceManagementClient() {
  return WindowsServiceManagementClient(
    closeCommand: platform.createWindowsServiceCloseExistingPositionCommand(),
    tightenStopCommand: platform.createWindowsServiceTightenExistingStopCommand(),
  );
}

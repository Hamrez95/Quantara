import '../application/windows_service_management_client.dart';

WindowsServiceCloseExistingPositionCommand
createWindowsServiceCloseExistingPositionCommand() {
  return (positionId) async => throw const WindowsServiceManagementException(
    'Windows service management is unavailable on this platform.',
  );
}

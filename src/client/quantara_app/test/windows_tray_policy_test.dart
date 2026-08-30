import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/windows_desktop/domain/windows_tray_policy.dart';

void main() {
  test('stopped tray exposes only Open', () {
    expect(
      WindowsTrayPolicy.actionsFor(
        WindowsServiceRuntimeState.stopped,
        emergencyCloseExplicitlyEnabled: true,
      ),
      {WindowsTrayAction.open},
    );
  });

  test('monitoring can stop new entries but cannot emergency close', () {
    expect(
      WindowsTrayPolicy.actionsFor(
        WindowsServiceRuntimeState.monitoring,
        emergencyCloseExplicitlyEnabled: true,
      ),
      {WindowsTrayAction.open, WindowsTrayAction.stopEntries},
    );
  });

  test('managing hides emergency close unless explicitly enabled', () {
    expect(
      WindowsTrayPolicy.actionsFor(
        WindowsServiceRuntimeState.managing,
        emergencyCloseExplicitlyEnabled: false,
      ),
      {WindowsTrayAction.open, WindowsTrayAction.stopEntries},
    );
  });

  test('managing exposes emergency close only with explicit enablement', () {
    expect(
      WindowsTrayPolicy.actionsFor(
        WindowsServiceRuntimeState.managing,
        emergencyCloseExplicitlyEnabled: true,
      ),
      {
        WindowsTrayAction.open,
        WindowsTrayAction.stopEntries,
        WindowsTrayAction.emergencyClose,
      },
    );
  });

  test('emergency close always requires confirmation', () {
    expect(
      WindowsTrayPolicy.requiresConfirmation(WindowsTrayAction.emergencyClose),
      isTrue,
    );
    expect(
      WindowsTrayPolicy.requiresConfirmation(WindowsTrayAction.stopEntries),
      isFalse,
    );
  });
}

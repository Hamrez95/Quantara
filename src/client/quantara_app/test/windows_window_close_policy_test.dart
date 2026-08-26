import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/windows_desktop/domain/windows_tray_policy.dart';
import 'package:quantara_app/features/windows_desktop/domain/windows_window_close_policy.dart';

void main() {
  test('stopped service permits UI exit without implying a service stop', () {
    final decision = WindowsWindowClosePolicy.resolve(
      serviceState: WindowsServiceRuntimeState.stopped,
      trayAvailable: true,
    );

    expect(decision.disposition, WindowsWindowCloseDisposition.exitUi);
    expect(decision.serviceContinues, isFalse);
    expect(decision.blocksImplicitServiceStop, isTrue);
  });

  for (final state in <WindowsServiceRuntimeState>{
    WindowsServiceRuntimeState.monitoring,
    WindowsServiceRuntimeState.managing,
    WindowsServiceRuntimeState.reconciling,
    WindowsServiceRuntimeState.circuitBreaker,
  }) {
    test('$state minimizes to tray when background state is active', () {
      final decision = WindowsWindowClosePolicy.resolve(
        serviceState: state,
        trayAvailable: true,
      );

      expect(
        decision.disposition,
        WindowsWindowCloseDisposition.minimizeToTray,
      );
      expect(decision.serviceContinues, isTrue);
      expect(decision.blocksImplicitServiceStop, isTrue);
    });

    test('$state requires confirmation when tray is unavailable', () {
      final decision = WindowsWindowClosePolicy.resolve(
        serviceState: state,
        trayAvailable: false,
      );

      expect(
        decision.disposition,
        WindowsWindowCloseDisposition.requireConfirmation,
      );
      expect(decision.serviceContinues, isTrue);
      expect(decision.blocksImplicitServiceStop, isTrue);
    });
  }

  test('starting service cannot be hidden behind an implicit UI exit', () {
    for (final trayAvailable in <bool>{true, false}) {
      final decision = WindowsWindowClosePolicy.resolve(
        serviceState: WindowsServiceRuntimeState.starting,
        trayAvailable: trayAvailable,
      );

      expect(
        decision.disposition,
        WindowsWindowCloseDisposition.requireConfirmation,
      );
      expect(decision.serviceContinues, isTrue);
      expect(decision.blocksImplicitServiceStop, isTrue);
    }
  });
}

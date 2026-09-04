import '../data/durable_global_pause_runtime_store.dart';

/// Fail-closed admission gate for work that can start new market scans.
///
/// This reads only the durable Global Pause intent. It has no exchange/order
/// authority and never infers account or protection state. Corrupt persisted
/// state is handled by [DurableGlobalPauseRuntimeStore.restore] as paused.
final class GlobalPauseBackgroundGate {
  const GlobalPauseBackgroundGate({required this.store});

  final DurableGlobalPauseRuntimeStore store;

  Future<bool> allowsNewScanning() async {
    try {
      final snapshot = await store.restore();
      return snapshot.allowsNewScanning;
    } on Object {
      // Background callbacks must fail closed if pause intent cannot be read.
      return false;
    }
  }
}

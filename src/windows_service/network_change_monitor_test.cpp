#include "network_change_monitor.h"

#include <atomic>
#include <iostream>

namespace {

bool Expect(bool condition, const char* message) {
  if (!condition) {
    std::cerr << message << '\n';
    return false;
  }
  return true;
}

}  // namespace

int main() {
  using quantara::ServiceSafetyState;

  if (!Expect(
          quantara::SafetyStateAfterNetworkChange(ServiceSafetyState::kDisarmed) ==
              ServiceSafetyState::kReconciliationRequired,
          "Network change must never leave a previously disarmed snapshot trusted.")) {
    return 1;
  }
  if (!Expect(quantara::SafetyStateAfterNetworkChange(
                  ServiceSafetyState::kInterrupted) ==
                  ServiceSafetyState::kReconciliationRequired,
              "Interrupted network truth must require reconciliation.")) {
    return 1;
  }
  if (!Expect(quantara::SafetyStateAfterNetworkChange(
                  ServiceSafetyState::kReconciliationRequired) ==
                  ServiceSafetyState::kReconciliationRequired,
              "Repeated network changes must be idempotently fail-closed.")) {
    return 1;
  }

  std::atomic<ServiceSafetyState> state{ServiceSafetyState::kDisarmed};
  quantara::NetworkChangeMonitor monitor(state);
  if (!Expect(!monitor.running(), "Monitor must start stopped.")) {
    return 1;
  }
  if (!Expect(monitor.Start(), "Windows network monitor failed to register.")) {
    return 1;
  }
  if (!Expect(monitor.running(), "Monitor must report a registered callback.")) {
    return 1;
  }
  if (!Expect(monitor.Start(), "Starting an active monitor must be idempotent.")) {
    return 1;
  }
  monitor.Stop();
  if (!Expect(!monitor.running(), "Monitor must unregister on stop.")) {
    return 1;
  }
  monitor.Stop();
  return 0;
}

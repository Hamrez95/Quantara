#include "network_change_monitor.h"

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

  // Keep the native unit/self-test deterministic: callback registration with
  // the host networking stack is an OS integration boundary. The production
  // monitor still registers through NotifyIpInterfaceChange and fails closed
  // when registration is unavailable, while this test locks the safety-state
  // contract independent of runner network configuration.
  return 0;
}

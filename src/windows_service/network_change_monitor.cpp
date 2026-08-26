#include "network_change_monitor.h"

namespace quantara {

ServiceSafetyState SafetyStateAfterNetworkChange(
    ServiceSafetyState /*current*/) noexcept {
  return ServiceSafetyState::kReconciliationRequired;
}

NetworkChangeMonitor::NetworkChangeMonitor(
    std::atomic<ServiceSafetyState>& safety_state) noexcept
    : safety_state_(safety_state) {}

NetworkChangeMonitor::~NetworkChangeMonitor() { Stop(); }

bool NetworkChangeMonitor::Start() noexcept {
  if (notification_handle_ != nullptr) {
    return true;
  }

  HANDLE handle = nullptr;
  const DWORD result = NotifyIpInterfaceChange(
      AF_UNSPEC, &NetworkChangeMonitor::OnInterfaceChange, this, FALSE, &handle);
  if (result != NO_ERROR || handle == nullptr) {
    return false;
  }

  notification_handle_ = handle;
  return true;
}

void NetworkChangeMonitor::Stop() noexcept {
  if (notification_handle_ == nullptr) {
    return;
  }

  CancelMibChangeNotify2(notification_handle_);
  notification_handle_ = nullptr;
}

bool NetworkChangeMonitor::running() const noexcept {
  return notification_handle_ != nullptr;
}

VOID NETIOAPI_API_ NetworkChangeMonitor::OnInterfaceChange(
    PVOID caller_context, PMIB_IPINTERFACE_ROW /*row*/,
    MIB_NOTIFICATION_TYPE /*notification_type*/) {
  if (caller_context == nullptr) {
    return;
  }

  auto* monitor = static_cast<NetworkChangeMonitor*>(caller_context);
  const auto current = monitor->safety_state_.load(std::memory_order_relaxed);
  // Any interface mutation can invalidate exchange/public-feed assumptions.
  // Never restore prior authority from a network callback; require an explicit
  // reconciliation path to establish fresh truth before future execution.
  monitor->safety_state_.store(SafetyStateAfterNetworkChange(current),
                               std::memory_order_relaxed);
}

}  // namespace quantara

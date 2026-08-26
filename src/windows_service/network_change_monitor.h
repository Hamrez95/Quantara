#pragma once

#include <windows.h>
#include <netioapi.h>

#include <atomic>

#include "ipc_response_protocol.h"

namespace quantara {

ServiceSafetyState SafetyStateAfterNetworkChange(
    ServiceSafetyState current) noexcept;

class NetworkChangeMonitor final {
 public:
  explicit NetworkChangeMonitor(
      std::atomic<ServiceSafetyState>& safety_state) noexcept;
  NetworkChangeMonitor(const NetworkChangeMonitor&) = delete;
  NetworkChangeMonitor& operator=(const NetworkChangeMonitor&) = delete;
  ~NetworkChangeMonitor();

  bool Start() noexcept;
  void Stop() noexcept;
  bool running() const noexcept;

 private:
  static VOID CALLBACK OnInterfaceChange(
      PVOID caller_context, PMIB_IPINTERFACE_ROW row,
      MIB_NOTIFICATION_TYPE notification_type) noexcept;

  std::atomic<ServiceSafetyState>& safety_state_;
  HANDLE notification_handle_ = nullptr;
};

}  // namespace quantara

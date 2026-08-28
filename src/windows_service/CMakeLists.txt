cmake_minimum_required(VERSION 3.20)

project(quantara_windows_service LANGUAGES CXX)

add_executable(quantara_windows_service
  main.cpp
  bitunix_request_signer.cpp
  bitunix_request_signer.h
  bitunix_request_authorizer.cpp
  bitunix_request_authorizer.h
  bitunix_https_readonly_transport.cpp
  bitunix_https_readonly_transport.h
  credential_readiness.cpp
  credential_readiness.h
  credential_vault.cpp
  credential_vault.h
  ipc_request_protocol.cpp
  ipc_request_protocol.h
  ipc_response_protocol.cpp
  ipc_response_protocol.h
  ipc_readonly_listener.cpp
  ipc_readonly_listener.h
  ipc_readonly_session.cpp
  ipc_readonly_session.h
  local_pipe_security.cpp
  local_pipe_security.h
  local_pipe_transport.cpp
  local_pipe_transport.h
  network_change_monitor.cpp
  network_change_monitor.h
)

target_compile_features(quantara_windows_service PRIVATE cxx_std_20)
target_compile_definitions(quantara_windows_service PRIVATE
  UNICODE
  _UNICODE
  WIN32_LEAN_AND_MEAN
  NOMINMAX
)
target_compile_options(quantara_windows_service PRIVATE
  /W4
  /WX
  /permissive-
)
target_link_libraries(quantara_windows_service PRIVATE advapi32 bcrypt crypt32 iphlpapi ole32 shell32 winhttp)

add_executable(quantara_windows_service_client
  status_client.cpp
)
target_compile_features(quantara_windows_service_client PRIVATE cxx_std_20)
target_compile_definitions(quantara_windows_service_client PRIVATE
  UNICODE
  _UNICODE
  WIN32_LEAN_AND_MEAN
  NOMINMAX
)
target_compile_options(quantara_windows_service_client PRIVATE
  /W4
  /WX
  /permissive-
)
target_link_libraries(quantara_windows_service_client PRIVATE advapi32)

add_executable(quantara_windows_credentials
  credential_provisioner.cpp
  credential_vault.cpp
  credential_vault.h
)
target_compile_features(quantara_windows_credentials PRIVATE cxx_std_20)
target_compile_definitions(quantara_windows_credentials PRIVATE
  UNICODE
  _UNICODE
  WIN32_LEAN_AND_MEAN
  NOMINMAX
)
target_compile_options(quantara_windows_credentials PRIVATE
  /W4
  /WX
  /permissive-
)
target_link_libraries(quantara_windows_credentials PRIVATE advapi32 crypt32 ole32 shell32)

add_executable(quantara_windows_tray WIN32
  tray_monitor.cpp
)
target_compile_features(quantara_windows_tray PRIVATE cxx_std_20)
target_compile_definitions(quantara_windows_tray PRIVATE
  UNICODE
  _UNICODE
  WIN32_LEAN_AND_MEAN
  NOMINMAX
)
target_compile_options(quantara_windows_tray PRIVATE
  /W4
  /WX
  /permissive-
)
target_link_libraries(quantara_windows_tray PRIVATE shell32 user32)

add_executable(quantara_windows_service_credential_vault_test
  credential_vault.cpp
  credential_vault.h
  credential_vault_test.cpp
)
target_compile_features(quantara_windows_service_credential_vault_test PRIVATE cxx_std_20)
target_compile_definitions(quantara_windows_service_credential_vault_test PRIVATE
  UNICODE
  _UNICODE
  WIN32_LEAN_AND_MEAN
  NOMINMAX
)
target_compile_options(quantara_windows_service_credential_vault_test PRIVATE
  /W4
  /WX
  /permissive-
)
target_link_libraries(quantara_windows_service_credential_vault_test PRIVATE advapi32 crypt32)

add_executable(quantara_windows_service_credential_readiness_test
  credential_readiness.cpp
  credential_readiness.h
  credential_readiness_test.cpp
  credential_vault.cpp
  credential_vault.h
)
target_compile_features(quantara_windows_service_credential_readiness_test PRIVATE cxx_std_20)
target_compile_definitions(quantara_windows_service_credential_readiness_test PRIVATE
  UNICODE
  _UNICODE
  WIN32_LEAN_AND_MEAN
  NOMINMAX
)
target_compile_options(quantara_windows_service_credential_readiness_test PRIVATE
  /W4
  /WX
  /permissive-
)
target_link_libraries(quantara_windows_service_credential_readiness_test PRIVATE advapi32 crypt32)

add_executable(quantara_windows_service_response_test
  ipc_request_protocol.cpp
  ipc_request_protocol.h
  ipc_response_protocol.cpp
  ipc_response_protocol.h
  ipc_response_protocol_test.cpp
)
target_compile_features(quantara_windows_service_response_test PRIVATE cxx_std_20)
target_compile_definitions(quantara_windows_service_response_test PRIVATE
  UNICODE
  _UNICODE
  WIN32_LEAN_AND_MEAN
  NOMINMAX
)
target_compile_options(quantara_windows_service_response_test PRIVATE
  /W4
  /WX
  /permissive-
)

add_executable(quantara_windows_service_session_test
  ipc_request_protocol.cpp
  ipc_request_protocol.h
  ipc_response_protocol.cpp
  ipc_response_protocol.h
  ipc_readonly_session.cpp
  ipc_readonly_session.h
  ipc_readonly_session_test.cpp
  local_pipe_security.cpp
  local_pipe_security.h
  local_pipe_transport.cpp
  local_pipe_transport.h
)
target_compile_features(quantara_windows_service_session_test PRIVATE cxx_std_20)
target_compile_definitions(quantara_windows_service_session_test PRIVATE
  UNICODE
  _UNICODE
  WIN32_LEAN_AND_MEAN
  NOMINMAX
)
target_compile_options(quantara_windows_service_session_test PRIVATE
  /W4
  /WX
  /permissive-
)
target_link_libraries(quantara_windows_service_session_test PRIVATE advapi32)

add_executable(quantara_windows_service_listener_test
  ipc_request_protocol.cpp
  ipc_request_protocol.h
  ipc_response_protocol.cpp
  ipc_response_protocol.h
  ipc_readonly_listener.cpp
  ipc_readonly_listener.h
  ipc_readonly_listener_test.cpp
  ipc_readonly_session.cpp
  ipc_readonly_session.h
  local_pipe_security.cpp
  local_pipe_security.h
  local_pipe_transport.cpp
  local_pipe_transport.h
  network_change_monitor.cpp
  network_change_monitor.h
)
target_compile_features(quantara_windows_service_listener_test PRIVATE cxx_std_20)
target_compile_definitions(quantara_windows_service_listener_test PRIVATE
  UNICODE
  _UNICODE
  WIN32_LEAN_AND_MEAN
  NOMINMAX
)
target_compile_options(quantara_windows_service_listener_test PRIVATE
  /W4
  /WX
  /permissive-
)
target_link_libraries(quantara_windows_service_listener_test PRIVATE advapi32 iphlpapi)

add_executable(quantara_windows_service_network_change_test
  ipc_request_protocol.cpp
  ipc_request_protocol.h
  ipc_response_protocol.cpp
  ipc_response_protocol.h
  network_change_monitor.cpp
  network_change_monitor.h
  network_change_monitor_test.cpp
)
target_compile_features(quantara_windows_service_network_change_test PRIVATE cxx_std_20)
target_compile_definitions(quantara_windows_service_network_change_test PRIVATE
  UNICODE
  _UNICODE
  WIN32_LEAN_AND_MEAN
  NOMINMAX
)
target_compile_options(quantara_windows_service_network_change_test PRIVATE
  /W4
  /WX
  /permissive-
)
target_link_libraries(quantara_windows_service_network_change_test PRIVATE iphlpapi)

add_executable(quantara_windows_service_existing_position_management_policy_test
  ../native/execution/existing_position_management_policy.cpp
  ../native/execution/existing_position_management_policy.h
  ../native/execution/existing_position_management_policy_test.cpp
)
target_compile_features(quantara_windows_service_existing_position_management_policy_test PRIVATE cxx_std_20)
target_compile_definitions(quantara_windows_service_existing_position_management_policy_test PRIVATE
  UNICODE
  _UNICODE
  WIN32_LEAN_AND_MEAN
  NOMINMAX
)
target_compile_options(quantara_windows_service_existing_position_management_policy_test PRIVATE
  /W4
  /WX
  /permissive-
)

add_executable(quantara_windows_service_management_only_recovery_coordinator_test
  ../native/execution/existing_position_management_policy.cpp
  ../native/execution/existing_position_management_policy.h
  ../native/execution/management_only_recovery_coordinator.cpp
  ../native/execution/management_only_recovery_coordinator.h
  ../native/execution/management_only_recovery_coordinator_test.cpp
)
target_compile_features(quantara_windows_service_management_only_recovery_coordinator_test PRIVATE cxx_std_20)
target_compile_definitions(quantara_windows_service_management_only_recovery_coordinator_test PRIVATE
  UNICODE
  _UNICODE
  WIN32_LEAN_AND_MEAN
  NOMINMAX
)
target_compile_options(quantara_windows_service_management_only_recovery_coordinator_test PRIVATE
  /W4
  /WX
  /permissive-
)

add_executable(quantara_windows_service_bitunix_request_signer_test
  bitunix_request_signer.cpp
  bitunix_request_signer.h
  bitunix_request_signer_test.cpp
)
target_compile_features(quantara_windows_service_bitunix_request_signer_test PRIVATE cxx_std_20)
target_compile_definitions(quantara_windows_service_bitunix_request_signer_test PRIVATE
  UNICODE
  _UNICODE
  WIN32_LEAN_AND_MEAN
  NOMINMAX
)
target_compile_options(quantara_windows_service_bitunix_request_signer_test PRIVATE
  /W4
  /WX
  /permissive-
)
target_link_libraries(quantara_windows_service_bitunix_request_signer_test PRIVATE bcrypt)

add_executable(quantara_windows_service_bitunix_request_authorizer_test
  bitunix_request_authorizer.cpp
  bitunix_request_authorizer.h
  bitunix_request_authorizer_test.cpp
  bitunix_request_signer.cpp
  bitunix_request_signer.h
  credential_vault.cpp
  credential_vault.h
)
target_compile_features(quantara_windows_service_bitunix_request_authorizer_test PRIVATE cxx_std_20)
target_compile_definitions(quantara_windows_service_bitunix_request_authorizer_test PRIVATE
  UNICODE
  _UNICODE
  WIN32_LEAN_AND_MEAN
  NOMINMAX
)
target_compile_options(quantara_windows_service_bitunix_request_authorizer_test PRIVATE
  /W4
  /WX
  /permissive-
)
target_link_libraries(quantara_windows_service_bitunix_request_authorizer_test PRIVATE advapi32 bcrypt crypt32)

add_executable(quantara_windows_service_bitunix_readonly_request_test
  bitunix_readonly_request.cpp
  bitunix_readonly_request.h
  bitunix_readonly_request_test.cpp
  bitunix_request_authorizer.cpp
  bitunix_request_authorizer.h
  bitunix_request_signer.cpp
  bitunix_request_signer.h
  credential_vault.cpp
  credential_vault.h
)
target_compile_features(quantara_windows_service_bitunix_readonly_request_test PRIVATE cxx_std_20)
target_compile_definitions(quantara_windows_service_bitunix_readonly_request_test PRIVATE
  UNICODE
  _UNICODE
  WIN32_LEAN_AND_MEAN
  NOMINMAX
)
target_compile_options(quantara_windows_service_bitunix_readonly_request_test PRIVATE
  /W4
  /WX
  /permissive-
)
target_link_libraries(quantara_windows_service_bitunix_readonly_request_test PRIVATE advapi32 bcrypt crypt32)

add_executable(quantara_windows_service_bitunix_https_readonly_transport_test
  bitunix_https_readonly_transport.cpp
  bitunix_https_readonly_transport.h
  bitunix_https_readonly_transport_test.cpp
)
target_compile_features(quantara_windows_service_bitunix_https_readonly_transport_test PRIVATE cxx_std_20)
target_compile_definitions(quantara_windows_service_bitunix_https_readonly_transport_test PRIVATE
  UNICODE
  _UNICODE
  WIN32_LEAN_AND_MEAN
  NOMINMAX
)
target_compile_options(quantara_windows_service_bitunix_https_readonly_transport_test PRIVATE
  /W4
  /WX
  /permissive-
)
target_link_libraries(quantara_windows_service_bitunix_https_readonly_transport_test PRIVATE winhttp)

add_executable(quantara_windows_service_bitunix_exchange_truth_parser_test
  bitunix_exchange_truth_parser.cpp
  bitunix_exchange_truth_parser.h
  bitunix_exchange_truth_parser_test.cpp
)
target_compile_features(quantara_windows_service_bitunix_exchange_truth_parser_test PRIVATE cxx_std_20)
target_compile_definitions(quantara_windows_service_bitunix_exchange_truth_parser_test PRIVATE
  UNICODE
  _UNICODE
  WIN32_LEAN_AND_MEAN
  NOMINMAX
)
target_compile_options(quantara_windows_service_bitunix_exchange_truth_parser_test PRIVATE
  /W4
  /WX
  /permissive-
)

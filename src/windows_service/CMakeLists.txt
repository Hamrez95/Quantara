cmake_minimum_required(VERSION 3.20)

project(quantara_windows_service LANGUAGES CXX)

add_executable(quantara_windows_service
  main.cpp
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
target_link_libraries(quantara_windows_service PRIVATE advapi32 crypt32)

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
target_link_libraries(quantara_windows_service_listener_test PRIVATE advapi32)

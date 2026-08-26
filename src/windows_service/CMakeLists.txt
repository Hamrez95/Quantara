cmake_minimum_required(VERSION 3.20)

project(quantara_windows_service LANGUAGES CXX)

add_executable(quantara_windows_service
  main.cpp
  credential_vault.cpp
  credential_vault.h
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

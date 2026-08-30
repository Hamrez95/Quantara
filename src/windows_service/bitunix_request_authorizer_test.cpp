#include "bitunix_request_authorizer.h"

#include <windows.h>

#include <filesystem>
#include <iostream>
#include <string>
#include <utility>
#include <vector>

#include "credential_vault.h"

namespace {

bool Expect(bool condition, const char* message) {
  if (!condition) std::cerr << message << '\n';
  return condition;
}

std::filesystem::path TestRoot() {
  wchar_t temp_path[MAX_PATH]{};
  const DWORD length = GetTempPathW(MAX_PATH, temp_path);
  if (length == 0 || length >= MAX_PATH) return {};
  return std::filesystem::path(temp_path) /
         (L"quantara-bitunix-authorizer-" + std::to_wstring(GetCurrentProcessId()));
}

}  // namespace

int main() {
  bool ok = true;
  const auto root = TestRoot();
  ok &= Expect(!root.empty(), "Temporary credential root must be available.");
  if (root.empty()) return 1;

  std::error_code ignored;
  std::filesystem::remove_all(root, ignored);

  const std::vector<std::pair<std::string, std::string>> query = {
      {"symbol", "BTCUSDT"}, {"limit", "100"}, {"skip", "0"}};

  const auto missing = quantara::AuthorizeBitunixPrivateRequest(
      root, "00112233445566778899aabbccddeeff", "1767225600123", query);
  ok &= Expect(!missing.has_value(),
               "Missing protected credentials must fail closed.");

  try {
    quantara::CredentialVault vault(root);
    vault.Store(L"bitunix-api-key", "demo-api");
    vault.Store(L"bitunix-api-secret", "demo-secret");

    const auto authorization = quantara::AuthorizeBitunixPrivateRequest(
        root, "00112233445566778899aabbccddeeff", "1767225600123", query);
    ok &= Expect(authorization.has_value(),
                 "Complete protected credentials must authorize signing.");
    if (authorization.has_value()) {
      ok &= Expect(authorization->api_key == "demo-api",
                   "Authorization must expose only the API key header value.");
      ok &= Expect(
          authorization->digest ==
              "aeb2aa31ef1ad337b28c9e5fcd5ef14a3e7ac2819a387e2a8e0049412d65a9f7",
          "Authorization digest must match the canonical Flutter vector.");
      ok &= Expect(
          authorization->sign ==
              "d9c126d885c800a82f88dbbfdd7f8870e1f1b987615d2d8c345ebbda1dc26f83",
          "Authorization signature must match the canonical Flutter vector.");
      ok &= Expect(authorization->nonce == "00112233445566778899aabbccddeeff" &&
                       authorization->timestamp == "1767225600123",
                   "Authorization must preserve the exact nonce/timestamp.");
    }

    ok &= Expect(
        !quantara::AuthorizeBitunixPrivateRequest(root, "", "1767225600123", query)
             .has_value(),
        "Empty nonce must fail closed before signing.");

    vault.Remove(L"bitunix-api-secret");
    ok &= Expect(
        !quantara::AuthorizeBitunixPrivateRequest(
             root, "00112233445566778899aabbccddeeff", "1767225600123", query)
             .has_value(),
        "Incomplete protected credentials must fail closed.");
  } catch (...) {
    ok = false;
    std::cerr << "Credential authorizer test raised an unexpected exception.\n";
  }

  std::filesystem::remove_all(root, ignored);
  return ok ? 0 : 1;
}

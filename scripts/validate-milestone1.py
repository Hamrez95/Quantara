from pathlib import Path

required = [
    "docs/product-scope.md",
    "docs/architecture.md",
    "docs/threat-model.md",
    "docs/risk-engine.md",
    "docs/order-state-machine.md",
    "docs/adr/0001-modular-monorepo.md",
    "docs/adr/0002-paper-default-live-gated.md",
    "docker-compose.yml",
    "src/backend/Quantara.Domain/Exchanges/IExchangeConnector.cs",
    "src/backend/Quantara.Infrastructure/Exchanges/DeterministicMockExchangeConnector.cs",
]
missing = [path for path in required if not Path(path).exists()]
if missing:
    raise SystemExit(f"Missing required files: {missing}")
connector = Path("src/backend/Quantara.Domain/Exchanges/IExchangeConnector.cs").read_text()
for method in ["GetInstrumentsAsync", "GetBalancesAsync", "GetCandlesAsync", "PlaceOrderAsync", "ReconcileAsync"]:
    assert method in connector, method
mock = Path("src/backend/Quantara.Infrastructure/Exchanges/DeterministicMockExchangeConnector.cs").read_text()
assert "DeterministicMockExchangeConnector" in mock
assert "DuplicateIgnored" in mock
print("Milestone 1 repository validation passed")


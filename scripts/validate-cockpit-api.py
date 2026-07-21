#!/usr/bin/env python3

import json
import sys
from datetime import datetime, timezone
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen


def fail(message: str) -> None:
    raise SystemExit(f"cockpit API validation failed: {message}")


def require(condition: bool, message: str) -> None:
    if not condition:
        fail(message)


def parse_utc(value: object, field: str) -> datetime:
    require(isinstance(value, str), f"{field} must be a string")
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError as error:
        fail(f"{field} is not an ISO timestamp: {error}")
    require(parsed.tzinfo is not None, f"{field} must include an offset")
    return parsed.astimezone(timezone.utc)


def main() -> None:
    if len(sys.argv) != 2:
        fail("usage: validate-cockpit-api.py <cockpit-url>")

    request = Request(
        sys.argv[1],
        headers={"Accept": "application/json"},
        method="GET",
    )
    try:
        with urlopen(request, timeout=10) as response:
            status = response.status
            headers = response.headers
            raw = response.read(1_048_577)
    except (HTTPError, URLError, TimeoutError) as error:
        fail(f"request failed: {error}")

    require(status == 200, f"unexpected HTTP status {status}")
    require(len(raw) <= 1_048_576, "response exceeds one megabyte")
    require(
        headers.get_content_type() == "application/json",
        "content type must be application/json",
    )
    require("no-store" in headers.get("Cache-Control", ""), "missing no-store")
    require(
        headers.get("X-Content-Type-Options") == "nosniff",
        "missing nosniff header",
    )
    require(headers.get("X-Frame-Options") == "DENY", "missing frame protection")
    require(
        "default-src 'none'" in headers.get("Content-Security-Policy", ""),
        "missing restrictive content security policy",
    )
    require(
        headers.get("Permissions-Policy")
        == "camera=(), geolocation=(), microphone=(), payment=()",
        "missing permissions policy",
    )

    try:
        payload = json.loads(raw.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        fail(f"invalid UTF-8 JSON: {error}")

    require(isinstance(payload, dict), "root must be an object")
    require(payload.get("schemaVersion") == "cockpit-v1", "unsupported schema")
    require(payload.get("environment") == "demo", "environment must be demo")
    require(
        payload.get("dataSourceMode") == "deterministic_demo",
        "unexpected data source mode",
    )
    require(
        payload.get("marketStatusCode") == "demo_not_connected",
        "demo connection status is missing",
    )

    safety = payload.get("safety")
    require(isinstance(safety, dict), "safety object is missing")
    require(safety.get("executionAuthority") == "none", "authority is not none")
    require(safety.get("realMoneyEnabled") is False, "real-money flag must be false")
    require(safety.get("orderSubmissionEnabled") is False, "submit flag must be false")
    require(safety.get("withdrawalEnabled") is False, "withdrawal flag must be false")

    generated_at = parse_utc(payload.get("generatedAt"), "generatedAt")
    now = datetime.now(timezone.utc)
    require(abs((now - generated_at).total_seconds()) < 60, "generatedAt is stale")

    watchlist = payload.get("watchlist")
    require(isinstance(watchlist, list) and watchlist, "watchlist must be non-empty")
    symbols: set[str] = set()
    for index, quote in enumerate(watchlist):
        require(isinstance(quote, dict), f"watchlist[{index}] must be an object")
        symbol = quote.get("symbol")
        require(isinstance(symbol, str) and symbol, f"watchlist[{index}] symbol invalid")
        require(symbol not in symbols, f"duplicate symbol {symbol}")
        symbols.add(symbol)
        require(quote.get("price", 0) > 0, f"{symbol} price must be positive")
        require(quote.get("spreadBps", -1) >= 0, f"{symbol} spread is invalid")
        require(
            parse_utc(quote.get("observedAt"), f"{symbol}.observedAt") <= generated_at,
            f"{symbol} observation is in the future",
        )
        sparkline = quote.get("sparkline")
        require(
            isinstance(sparkline, list)
            and len(sparkline) >= 2
            and all(isinstance(value, (int, float)) and value > 0 for value in sparkline),
            f"{symbol} sparkline is invalid",
        )

    analysis = payload.get("analysis")
    require(isinstance(analysis, dict), "analysis is missing")
    require(analysis.get("decision") == "no_trade", "demo decision must be no_trade")
    require(
        isinstance(analysis.get("confidencePercent"), int)
        and 0 <= analysis["confidencePercent"] <= 100,
        "confidence is invalid",
    )

    account = payload.get("paperAccount")
    require(isinstance(account, dict), "paperAccount is missing")
    require(account.get("isSimulated") is True, "paper account must be simulated")
    require(
        account.get("equity") == account.get("availableBalance") + account.get("usedMargin"),
        "paper account balance does not reconcile",
    )
    require(
        0 <= account.get("currentDailyRiskPercent", -1)
        <= account.get("maximumDailyRiskPercent", -1),
        "paper account risk is invalid",
    )

    print("cockpit API validation passed")


if __name__ == "__main__":
    main()

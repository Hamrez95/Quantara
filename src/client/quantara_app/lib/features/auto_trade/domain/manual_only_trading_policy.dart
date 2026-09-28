/// Product execution policy for the current Quantara release.
///
/// Setup discovery, Bitunix account connection, and explicit manual orders stay
/// available. Autonomous local and unattended execution are intentionally
/// disabled until a future release explicitly re-enables them.
const bool quantaraManualOnlyMode = true;

const String manualOnlyTradingMessage =
    'Automatic trading is disabled. Select a setup and place trades manually.';

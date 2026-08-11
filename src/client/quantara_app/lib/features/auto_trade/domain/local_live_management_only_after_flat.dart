final class LocalLiveManagementOnlyAfterFlatPolicy {
  const LocalLiveManagementOnlyAfterFlatPolicy._();

  static bool effectiveEntriesEnabled({
    required bool userRequestedEntries,
    required bool managementOnlyAfterFlat,
  }) => userRequestedEntries && !managementOnlyAfterFlat;

  static bool shouldLatchAfterFinalExchangeClose({
    required bool hadManagedPositions,
    required bool hasManagedPositions,
    required int exchangeOpenPositionCount,
    required bool userRequestedEntries,
  }) =>
      userRequestedEntries &&
      hadManagedPositions &&
      !hasManagedPositions &&
      exchangeOpenPositionCount == 0;
}

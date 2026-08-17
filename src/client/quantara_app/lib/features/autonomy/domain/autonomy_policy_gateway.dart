import 'dart:collection';

enum AutonomyExecutionMode {
  readOnly,
  approvalRequired,
  guardedAuto,
  cappedAuto,
  autonomous,
}

enum AutonomyPromotionState {
  researchOnly,
  shadowEligible,
  paperEligible,
  cappedCanaryEligible,
  autonomousEligible,
  suspended,
  rolledBack,
}

enum AutonomyOperation {
  observe,
  protectedNewEntry,
  reduceOnlyExistingExposure,
  addToExistingExposure,
  averagingDown,
  martingale,
  widenStop,
  removeStop,
  withdrawal,
  transfer,
  crossMargin,
}

enum AutonomyPolicyBlockReason {
  none,
  readOnlyMode,
  promotionSuspended,
  promotionInsufficient,
  canonicalDecisionRejected,
  riskDecisionRejected,
  allocationDecisionRejected,
  marketTruthUnhealthy,
  privateTruthUnhealthy,
  protectionUnhealthy,
  riskAccountMismatch,
  riskBreakerTripped,
  executionQualityUnhealthy,
  strategyDriftUnhealthy,
  criticalHealthUnhealthy,
  userApprovalRequired,
  explicitSessionRequired,
  strategyEvidenceMissing,
  faultCertificationMissing,
  buildIdentityUnapproved,
  strategyIdentityUnapproved,
  capitalRiskCapsMissing,
  durableWorkerUncertified,
  persistentCredentialBoundaryUnready,
}

final class AutonomyModeCapabilities {
  const AutonomyModeCapabilities({
    required this.canRequestEntry,
    required this.canAutoSubmitEntry,
    required this.requiresUserApproval,
    required this.requiresExplicitSession,
    required this.requiresDurableWorker,
  });

  final bool canRequestEntry;
  final bool canAutoSubmitEntry;
  final bool requiresUserApproval;
  final bool requiresExplicitSession;
  final bool requiresDurableWorker;
}

final class AutonomyPolicyInput {
  const AutonomyPolicyInput({
    required this.mode,
    required this.promotionState,
    required this.canonicalDecisionEligible,
    required this.riskDecisionAllowed,
    required this.allocationSelected,
    required this.marketTruthHealthy,
    required this.privateTruthHealthy,
    required this.protectionHealthy,
    required this.riskAccountConsistent,
    required this.riskBreakersClear,
    required this.executionQualityHealthy,
    required this.strategyDriftHealthy,
    required this.criticalHealthClear,
    this.userApproved = false,
    this.explicitSessionStarted = false,
    this.strategyEvidenceApproved = false,
    this.faultCertificationCurrent = false,
    this.buildIdentityApproved = false,
    this.strategyIdentityApproved = false,
    this.capitalRiskCapsConfigured = false,
    this.durableWorkerCertified = false,
    this.persistentCredentialBoundaryReady = false,
    this.hasManagedExposure = false,
  });

  final AutonomyExecutionMode mode;
  final AutonomyPromotionState promotionState;
  final bool canonicalDecisionEligible;
  final bool riskDecisionAllowed;
  final bool allocationSelected;
  final bool marketTruthHealthy;
  final bool privateTruthHealthy;
  final bool protectionHealthy;
  final bool riskAccountConsistent;
  final bool riskBreakersClear;
  final bool executionQualityHealthy;
  final bool strategyDriftHealthy;
  final bool criticalHealthClear;
  final bool userApproved;
  final bool explicitSessionStarted;
  final bool strategyEvidenceApproved;
  final bool faultCertificationCurrent;
  final bool buildIdentityApproved;
  final bool strategyIdentityApproved;
  final bool capitalRiskCapsConfigured;
  final bool durableWorkerCertified;
  final bool persistentCredentialBoundaryReady;
  final bool hasManagedExposure;
}

final class AutonomyPolicyDecision {
  AutonomyPolicyDecision({
    required this.version,
    required this.mode,
    required this.promotionState,
    required this.capabilities,
    required this.blockReason,
    required this.newEntryAuthorized,
    required this.reduceOnlyManagementAuthorized,
    Iterable<String> evidence = const [],
  }) : evidence = UnmodifiableListView(evidence.toList(growable: false));

  final String version;
  final AutonomyExecutionMode mode;
  final AutonomyPromotionState promotionState;
  final AutonomyModeCapabilities capabilities;
  final AutonomyPolicyBlockReason blockReason;
  final bool newEntryAuthorized;
  final bool reduceOnlyManagementAuthorized;
  final UnmodifiableListView<String> evidence;

  bool authorizes(AutonomyOperation operation) => switch (operation) {
    AutonomyOperation.observe => true,
    AutonomyOperation.protectedNewEntry => newEntryAuthorized,
    AutonomyOperation.reduceOnlyExistingExposure =>
      reduceOnlyManagementAuthorized,
    AutonomyOperation.addToExistingExposure ||
    AutonomyOperation.averagingDown ||
    AutonomyOperation.martingale ||
    AutonomyOperation.widenStop ||
    AutonomyOperation.removeStop ||
    AutonomyOperation.withdrawal ||
    AutonomyOperation.transfer ||
    AutonomyOperation.crossMargin => false,
  };
}

final class AutonomyPolicyGateway {
  const AutonomyPolicyGateway({this.version = 'autonomy-policy/1.0'});

  final String version;

  static const Map<AutonomyExecutionMode, AutonomyModeCapabilities>
  capabilityMatrix = {
    AutonomyExecutionMode.readOnly: AutonomyModeCapabilities(
      canRequestEntry: false,
      canAutoSubmitEntry: false,
      requiresUserApproval: false,
      requiresExplicitSession: false,
      requiresDurableWorker: false,
    ),
    AutonomyExecutionMode.approvalRequired: AutonomyModeCapabilities(
      canRequestEntry: true,
      canAutoSubmitEntry: false,
      requiresUserApproval: true,
      requiresExplicitSession: false,
      requiresDurableWorker: false,
    ),
    AutonomyExecutionMode.guardedAuto: AutonomyModeCapabilities(
      canRequestEntry: true,
      canAutoSubmitEntry: true,
      requiresUserApproval: false,
      requiresExplicitSession: true,
      requiresDurableWorker: false,
    ),
    AutonomyExecutionMode.cappedAuto: AutonomyModeCapabilities(
      canRequestEntry: true,
      canAutoSubmitEntry: true,
      requiresUserApproval: false,
      requiresExplicitSession: false,
      requiresDurableWorker: true,
    ),
    AutonomyExecutionMode.autonomous: AutonomyModeCapabilities(
      canRequestEntry: true,
      canAutoSubmitEntry: true,
      requiresUserApproval: false,
      requiresExplicitSession: false,
      requiresDurableWorker: true,
    ),
  };

  AutonomyPolicyDecision evaluate(AutonomyPolicyInput input) {
    if (version.trim().isEmpty) {
      throw const FormatException('Autonomy policy version is required.');
    }

    final capabilities = capabilityMatrix[input.mode]!;
    final blockReason = _entryBlockReason(input, capabilities);
    return AutonomyPolicyDecision(
      version: version,
      mode: input.mode,
      promotionState: input.promotionState,
      capabilities: capabilities,
      blockReason: blockReason,
      newEntryAuthorized: blockReason == AutonomyPolicyBlockReason.none,
      reduceOnlyManagementAuthorized: input.hasManagedExposure,
      evidence: [
        'mode:${input.mode.name}',
        'promotion:${input.promotionState.name}',
        'canonical:${input.canonicalDecisionEligible}',
        'risk:${input.riskDecisionAllowed}',
        'allocation:${input.allocationSelected}',
        'marketTruth:${input.marketTruthHealthy}',
        'privateTruth:${input.privateTruthHealthy}',
        'protection:${input.protectionHealthy}',
        'riskAccount:${input.riskAccountConsistent}',
        'riskBreakers:${input.riskBreakersClear}',
        'executionQuality:${input.executionQualityHealthy}',
        'strategyDrift:${input.strategyDriftHealthy}',
        'criticalHealth:${input.criticalHealthClear}',
        'userApproved:${input.userApproved}',
        'explicitSession:${input.explicitSessionStarted}',
        'strategyEvidence:${input.strategyEvidenceApproved}',
        'faultCertification:${input.faultCertificationCurrent}',
        'buildIdentity:${input.buildIdentityApproved}',
        'strategyIdentity:${input.strategyIdentityApproved}',
        'capitalRiskCaps:${input.capitalRiskCapsConfigured}',
        'durableWorker:${input.durableWorkerCertified}',
        'credentialBoundary:${input.persistentCredentialBoundaryReady}',
      ],
    );
  }

  AutonomyPolicyBlockReason _entryBlockReason(
    AutonomyPolicyInput input,
    AutonomyModeCapabilities capabilities,
  ) {
    if (input.mode == AutonomyExecutionMode.readOnly ||
        !capabilities.canRequestEntry) {
      return AutonomyPolicyBlockReason.readOnlyMode;
    }
    if (input.promotionState == AutonomyPromotionState.suspended ||
        input.promotionState == AutonomyPromotionState.rolledBack) {
      return AutonomyPolicyBlockReason.promotionSuspended;
    }
    if (!input.canonicalDecisionEligible) {
      return AutonomyPolicyBlockReason.canonicalDecisionRejected;
    }
    if (!input.riskDecisionAllowed) {
      return AutonomyPolicyBlockReason.riskDecisionRejected;
    }
    if (!input.allocationSelected) {
      return AutonomyPolicyBlockReason.allocationDecisionRejected;
    }
    if (!input.marketTruthHealthy) {
      return AutonomyPolicyBlockReason.marketTruthUnhealthy;
    }
    if (!input.privateTruthHealthy) {
      return AutonomyPolicyBlockReason.privateTruthUnhealthy;
    }
    if (!input.protectionHealthy) {
      return AutonomyPolicyBlockReason.protectionUnhealthy;
    }
    if (!input.riskAccountConsistent) {
      return AutonomyPolicyBlockReason.riskAccountMismatch;
    }
    if (!input.riskBreakersClear) {
      return AutonomyPolicyBlockReason.riskBreakerTripped;
    }
    if (!input.executionQualityHealthy) {
      return AutonomyPolicyBlockReason.executionQualityUnhealthy;
    }
    if (!input.strategyDriftHealthy) {
      return AutonomyPolicyBlockReason.strategyDriftUnhealthy;
    }
    if (!input.criticalHealthClear) {
      return AutonomyPolicyBlockReason.criticalHealthUnhealthy;
    }

    return switch (input.mode) {
      AutonomyExecutionMode.readOnly => AutonomyPolicyBlockReason.readOnlyMode,
      AutonomyExecutionMode.approvalRequired =>
        input.userApproved
            ? AutonomyPolicyBlockReason.none
            : AutonomyPolicyBlockReason.userApprovalRequired,
      AutonomyExecutionMode.guardedAuto =>
        input.explicitSessionStarted
            ? AutonomyPolicyBlockReason.none
            : AutonomyPolicyBlockReason.explicitSessionRequired,
      AutonomyExecutionMode.cappedAuto => _cappedAutoBlockReason(input),
      AutonomyExecutionMode.autonomous => _autonomousBlockReason(input),
    };
  }

  AutonomyPolicyBlockReason _cappedAutoBlockReason(AutonomyPolicyInput input) {
    final promoted =
        input.promotionState == AutonomyPromotionState.cappedCanaryEligible ||
        input.promotionState == AutonomyPromotionState.autonomousEligible;
    if (!promoted) {
      return AutonomyPolicyBlockReason.promotionInsufficient;
    }
    return _durableModeBlockReason(input);
  }

  AutonomyPolicyBlockReason _autonomousBlockReason(AutonomyPolicyInput input) {
    if (input.promotionState != AutonomyPromotionState.autonomousEligible) {
      return AutonomyPolicyBlockReason.promotionInsufficient;
    }
    return _durableModeBlockReason(input);
  }

  AutonomyPolicyBlockReason _durableModeBlockReason(AutonomyPolicyInput input) {
    if (!input.strategyEvidenceApproved) {
      return AutonomyPolicyBlockReason.strategyEvidenceMissing;
    }
    if (!input.faultCertificationCurrent) {
      return AutonomyPolicyBlockReason.faultCertificationMissing;
    }
    if (!input.buildIdentityApproved) {
      return AutonomyPolicyBlockReason.buildIdentityUnapproved;
    }
    if (!input.strategyIdentityApproved) {
      return AutonomyPolicyBlockReason.strategyIdentityUnapproved;
    }
    if (!input.capitalRiskCapsConfigured) {
      return AutonomyPolicyBlockReason.capitalRiskCapsMissing;
    }
    if (!input.durableWorkerCertified) {
      return AutonomyPolicyBlockReason.durableWorkerUncertified;
    }
    if (!input.persistentCredentialBoundaryReady) {
      return AutonomyPolicyBlockReason.persistentCredentialBoundaryUnready;
    }
    return AutonomyPolicyBlockReason.none;
  }
}

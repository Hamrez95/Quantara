# Branching and Release Policy

## Long-lived branches

- `dev` is the integration branch for completed milestone work.
- `main` is the release branch and must contain only reviewed, releasable changes.
- The repository default branch should move to `dev` during active pre-release development or the team must explicitly target `dev` when creating work.

## Required workflow

Every implementation follows this sequence:

1. Create or select a GitHub issue with scope, safety constraints, and acceptance criteria.
2. Create a short-lived branch from `dev` named with the issue number, for example `feat/3-ci-quality-gates`.
3. Make logically separated commits that reference the issue.
4. Open a pull request to `dev`.
5. Require CI to pass and review the actual diff, not only the generated summary.
6. Record test evidence, limitations, and any deferred risks in the pull request.
7. Merge only after acceptance criteria are met.
8. Promote `dev` to `main` through a separate release pull request after milestone validation.

Direct feature commits to `main` are prohibited. Direct feature commits to `dev` should be avoided except for an explicitly documented emergency repair.

## Pull request evidence

A pull request must state:

- The issue it closes or advances.
- What changed and why.
- Safety impact.
- Exact commands or CI jobs executed.
- Test results and known test gaps.
- Database or configuration changes.
- Rollback considerations.
- Confirmation that live-trading capability was not expanded unless that expansion is the explicitly approved scope.

## Release rules

A release pull request from `dev` to `main` requires:

- Green required checks on the release commit.
- No unresolved blocking review threads.
- Updated user-facing and engineering documentation.
- Migration and rollback review where applicable.
- Security and risk review for any exchange, credential, order, position, or market-data change.
- A versioned release note describing limitations without profit or win-rate guarantees.

## Emergency changes

Emergency fixes must still receive an issue, a focused branch, tests, and a pull request. If an urgent safety response requires disabling functionality, prefer fail-closed behavior, kill switches, and removal of opening-order capability while preserving safe reduce-only exits.


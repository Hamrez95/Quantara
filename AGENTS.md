# Repository agent guidance

## Product contract

- Product: Quantara
- Current milestone: Android owner-alpha stabilization after 0.9.0 preview
- Primary outcome: understandable, time-bounded paper-trading ideas that remain traceable from strategy to outcome
- Product brief: `docs/product-brief.fa.md`
- Definition of done: `docs/quality-gates.md` plus a passing stability report

## Repository map

- Flutter application: `src/client/quantara_app`
- Backend/API: `src`
- Flutter tests: `src/client/quantara_app/test`
- Infrastructure: `infra` and `docker-compose.yml`
- Documentation: `docs`
- Generated artifacts: `artifacts/` (never commit)

## Exact commands

- Bootstrap: `dotnet restore Quantara.sln && cd src/client/quantara_app && flutter pub get`
- Flutter format: `dart format --output=none --set-exit-if-changed lib test`
- Flutter analysis: `flutter analyze --fatal-infos`
- Flutter tests: `flutter test`
- Backend build/tests: `dotnet build Quantara.sln --configuration Release --no-restore && dotnet test Quantara.sln --configuration Release --no-build`
- Android/PWA artifacts: `./scripts/build-app.ps1 -Target all -Configuration Release`

## Engineering and product rules

- Paper-only by default; never add live orders, withdrawals, or autonomous LLM execution.
- Keep stale-data, cost, liquidity, reward/risk, invalidation and sizing gates fail-closed.
- Keep domain logic separate from Flutter UI and platform integrations.
- Add regression tests for changed behavior; do not claim an integration without evidence.
- Use semantic tokens, light/dark themes, Persian/English localization, RTL/LTR, logical layout, accessible semantics and text scaling.
- Explain trading decisions in plain language with strategy/version and validity timestamps.
- Never commit secrets, signing material, personal data or generated artifacts.

## Git and release rules

- `main` is stable and releasable; version work enters through `dev`.
- Use linked issues and short-lived branches; preserve unrelated changes.
- Do not merge into `main` until checks, installable artifact smoke tests, quality score >= 90, release notes and rollback pass.
- Production/store publication requires explicit approval.

## Graphify context optimization
- Project-scoped Graphify skills live at `.agents/skills/graphify/SKILL.md` and `.codex/skills/graphify/SKILL.md`.
- For codebase architecture, dependency, impact-analysis, and code-navigation questions, use `graphify query`, `graphify path`, or `graphify explain` before broad grep/file reads whenever `graphify-out/graph.json` exists.
- If the graph is missing, invoke the Graphify skill and build a structural code-only graph with `graphify extract . --code-only` before broad repository exploration.
- Treat the graph as an index, never as source of truth: open and verify the exact returned source before edits or definitive claims.
- After code modifications, refresh with `graphify extract . --code-only`; this intentionally avoids semantic LLM passes during routine development.
- Keep generated `graphify-out/` artifacts local and uncommitted. Do not run docs/PDF/image/video semantic extraction unless the task explicitly needs it.

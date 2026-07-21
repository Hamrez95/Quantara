# Flutter cockpit foundation

## Product decision

Quantara will not wait for every backend milestone before becoming visible and testable. The first client slice uses deterministic demo data behind repository interfaces while the durable paper-account and read-only market APIs continue separately.

This is a vertical product slice, not a disposable design mock. Its presentation models, states, accessibility rules, and repository boundaries are intended to survive the transition from demo data to API-backed data.

## Cross-functional agreement

### Product management

The first release must answer three user questions immediately:

1. What is happening in the watched markets?
2. What does Quantara currently conclude, and why?
3. What is the state of the paper account and its risk budget?

Features that do not improve one of these journeys are deferred from the first cockpit slice.

### UX and visual design

- Demo, paper, shadow, and real-money states must never look interchangeable.
- A persistent demo banner explains that prices and results are simulated.
- `NO_TRADE` is a complete decision with confidence, evidence, and reconsideration conditions.
- Information hierarchy is more important than displaying many indicators.
- Mobile uses bottom navigation; desktop uses a navigation rail and wider analytical layout.
- Dark and light themes share the same semantic colors and spacing system.
- Decorative charts are excluded from screen-reader output; meaningful values have semantic labels.

### Client engineering

- One Flutter codebase targets Android, iOS, and web/PWA.
- Domain-shaped presentation models distinguish environment, decision, regime, evidence impact, quote freshness, and paper risk.
- The client depends on a `CockpitRepository`; the first implementation is deterministic demo data.
- No large state-management or chart package is introduced before the interaction model requires it.
- Loading, error, phone, and desktop states are covered by widget tests.

### Backend and API engineering

The future API should satisfy the existing client contracts rather than expose database entities. Initial read contracts should provide:

- environment and safety state;
- watchlist quotes with freshness and spread;
- explainable analysis with decision, regime, confidence, evidence factors, and reconsideration conditions;
- paper-account equity, available balance, used margin, PnL, open positions, and daily risk usage.

The client must remain useful with demo repositories when the API is unavailable.

### Risk and compliance

- There is no credential entry, order submission, or real-money action in this slice.
- Real-money capability is explicitly shown as locked.
- Demo data is never described as current market data.
- No profitability, certainty, or win-rate claim is displayed.
- Analysis is informational and cannot grant execution authority.

### Quality engineering

Flutter CI must pass:

- deterministic dependency restore;
- Dart formatting;
- static analysis with informational findings treated as failures;
- widget tests;
- release web build;
- Android debug-package build.

The existing backend CI remains mandatory on the same pull request.

## Responsive layout

- Under 1,024 logical pixels: bottom navigation and a single-column reading order.
- At or above 1,024 logical pixels: side navigation.
- At or above 1,080 logical pixels inside the content area: analysis and paper-account cards share a row.
- Market cards use one, two, or four columns based on available width.
- Main content is capped at 1,480 logical pixels to preserve scanability on wide monitors.

## Initial performance budget

- No network request is required to display the demo cockpit.
- No external font, image, chart, or animation package is required.
- The first meaningful demo state should appear immediately after the deliberate loading-state exercise.
- Web release and Android debug builds are produced in CI.

## Deferred work

- API-backed repositories and authentication.
- Full candlestick charting and drawing tools.
- Durable paper-order entry and lifecycle.
- Notifications and background refresh.
- Offline cache and reconnect synchronization.
- Golden screenshots across themes and locales.
- Real-time WebSocket updates.
- Any real-money control.

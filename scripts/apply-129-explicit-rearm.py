from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    file = Path(path)
    text = file.read_text()
    if old not in text:
        raise SystemExit(f'missing patch anchor in {path}: {old[:100]!r}')
    file.write_text(text.replace(old, new, 1))


models = 'src/client/quantara_app/lib/features/auto_trade/domain/local_live_trade_models.dart'
replace_once(
    models,
    "  bool get isRunning =>\n      state == LocalLiveTradeState.running ||\n      state == LocalLiveTradeState.managingOnly;\n",
    "  bool get isRunning =>\n      state == LocalLiveTradeState.running ||\n      state == LocalLiveTradeState.managingOnly;\n\n  bool get canResumeEntries =>\n      state == LocalLiveTradeState.managingOnly &&\n      !entriesEnabled &&\n      openPositionCount == 0;\n",
)

page = 'src/client/quantara_app/lib/features/owner_alpha/presentation/owner_alpha_auto_trade.dart'
replace_once(
    page,
    """    final status = widget.controller.status;
    final running = status.isRunning;
    final breaker = status.state == LocalLiveTradeState.circuitBreaker;
    final color = breaker
        ? QuantaraColors.danger
        : running
        ? QuantaraColors.success
        : QuantaraColors.cyan;
""",
    """    final status = widget.controller.status;
    final serviceActive = status.isRunning;
    final entriesActive =
        status.state == LocalLiveTradeState.running && status.entriesEnabled;
    final canResumeEntries = status.canResumeEntries;
    final starting = status.state == LocalLiveTradeState.starting;
    final breaker = status.state == LocalLiveTradeState.circuitBreaker;
    final color = breaker
        ? QuantaraColors.danger
        : entriesActive
        ? QuantaraColors.success
        : serviceActive
        ? QuantaraColors.warning
        : QuantaraColors.cyan;
""",
)
replace_once(
    page,
    """                  running
                      ? Icons.play_circle_fill_rounded
                      : Icons.phone_android_rounded,
""",
    """                  entriesActive
                      ? Icons.play_circle_fill_rounded
                      : serviceActive
                      ? Icons.pause_circle_filled_rounded
                      : Icons.phone_android_rounded,
""",
)
replace_once(
    page,
    """                icon: running
                    ? Icons.shield_rounded
                    : Icons.stop_circle_outlined,
""",
    """                icon: entriesActive
                    ? Icons.shield_rounded
                    : serviceActive
                    ? Icons.pause_circle_outline_rounded
                    : Icons.stop_circle_outlined,
""",
)
replace_once(
    page,
    """          AnimatedSwitcher(
            duration: QuantaraMotion.fast,
            child: Text(
              localizedStatus,
              key: ValueKey(localizedStatus),
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: 8),
""",
    """          AnimatedSwitcher(
            duration: QuantaraMotion.fast,
            child: Text(
              localizedStatus,
              key: ValueKey(localizedStatus),
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          if (canResumeEntries) ...[
            const SizedBox(height: 10),
            _BoundaryNotice(
              text: _t(
                'ورود جدید متوقف است و هیچ پوزیشن بازی برای مدیریت وجود ندارد. برای فعال‌سازی دوباره، دکمه «ازسرگیری ورود» را بزن و همه تأییدهای پول واقعی را دوباره انجام بده.',
                'New entries are stopped and there is no open position to manage. Use Resume entries and repeat every real-money confirmation to arm entries again.',
              ),
              color: QuantaraColors.warning,
            ),
          ],
          const SizedBox(height: 8),
""",
)
replace_once(
    page,
    """            absorbing:
                running || widget.controller.isBusy || !_preferencesLoaded,
            child: Opacity(
              opacity: running ? 0.60 : 1,
""",
    """            absorbing:
                serviceActive ||
                widget.controller.isBusy ||
                !_preferencesLoaded,
            child: Opacity(
              opacity: serviceActive ? 0.60 : 1,
""",
)
replace_once(
    page,
    """                  onPressed: widget.controller.isBusy || running || breaker
                      ? null
                      : _confirmStart,
""",
    """                  onPressed:
                      widget.controller.isBusy ||
                          starting ||
                          breaker ||
                          (serviceActive && !canResumeEntries)
                      ? null
                      : _confirmStart,
""",
)
replace_once(
    page,
    """                  label: Text(
                    _t('شروع ترید', 'Start trading'),
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
""",
    """                  label: Text(
                    canResumeEntries
                        ? _t('ازسرگیری ورود', 'Resume entries')
                        : _t('شروع ترید', 'Start trading'),
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
""",
)
replace_once(
    page,
    """                  onPressed: widget.controller.isBusy || !running
                      ? null
                      : _confirmStop,
""",
    """                  onPressed: widget.controller.isBusy || !serviceActive
                      ? null
                      : _confirmStop,
""",
)

test = 'src/client/quantara_app/test/local_live_trade_models_test.dart'
replace_once(
    test,
    """    expect(status(LocalLiveTradeState.stopped).isRunning, isFalse);
  });
}
""",
    """    expect(status(LocalLiveTradeState.stopped).isRunning, isFalse);
  });

  test('managing-only can resume entries only with no open position', () {
    final resumable = LocalLiveTradeStatus(
      state: LocalLiveTradeState.managingOnly,
      updatedAt: DateTime.utc(2026, 8, 3),
      message: 'entries stopped',
      entriesEnabled: false,
    );
    final protectedPosition = LocalLiveTradeStatus(
      state: LocalLiveTradeState.managingOnly,
      updatedAt: DateTime.utc(2026, 8, 3),
      message: 'managing position',
      openPositionCount: 1,
      entriesEnabled: false,
    );
    final active = LocalLiveTradeStatus(
      state: LocalLiveTradeState.running,
      updatedAt: DateTime.utc(2026, 8, 3),
      message: 'running',
      entriesEnabled: true,
    );

    expect(resumable.canResumeEntries, isTrue);
    expect(protectedPosition.canResumeEntries, isFalse);
    expect(active.canResumeEntries, isFalse);
  });
}
""",
)

guard = 'src/client/quantara_app/test/realtime_malformed_bootstrap_source_test.dart'
replace_once(
    guard,
    """    expect(page, contains('Degraded live monitoring'));
  });
}
""",
    """    expect(page, contains('Degraded live monitoring'));
    expect(page, contains('canResumeEntries'));
    expect(page, contains('Resume entries'));
  });
}
""",
)

print('Explicit managing-only re-arm patch applied.')

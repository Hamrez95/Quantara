from pathlib import Path
import re


def sub1(path: str, pattern: str, replacement: str) -> None:
    p = Path(path)
    text = p.read_text()
    new, count = re.subn(pattern, replacement, text, count=1, flags=re.MULTILINE)
    if count != 1:
        raise SystemExit(f"Expected one regex match in {path}; got {count}: {pattern}")
    p.write_text(new)


policy = "src/client/quantara_app/lib/features/auto_trade/domain/remaining_target_protection_policy.dart"
sub1(
    policy,
    r"(\n\s*)final pending = pendingProtection\.toList\(growable: false\);",
    r"\1final comparisonTolerance = quantityTolerance / 2;\1final pending = pendingProtection.toList(growable: false);",
)
sub1(policy, r"filled > planned \+ quantityTolerance", "filled > planned + comparisonTolerance")
sub1(policy, r"filled > quantityTolerance", "filled > comparisonTolerance")
sub1(policy, r"if \(remaining <= quantityTolerance\) continue;", "if (remaining <= comparisonTolerance) continue;")
sub1(
    policy,
    r"item\.quantity\.isFinite\s*&&\s*item\.quantity \+ quantityTolerance >= remaining,",
    "item.quantity.isFinite &&\n            item.quantity > 0 &&\n            item.quantity + comparisonTolerance >= remaining,",
)

service = "src/client/quantara_app/lib/features/auto_trade/application/local_live_trade_service.dart"
sub1(
    service,
    r"(if \(!_targetIdentityLayoutValid\([\s\S]*?\)\) \{\s*return false;\s*\}\s*)(for \(var index = 0; index < 3; index\+\+\) \{\s*final id = targetOrderIds\[index\]\.trim\(\);\s*final planned = targetQuantities\[index\];\s*if \(planned <= 0\) continue;)",
    r"\1final comparisonTolerance = quantityTolerance / 2;\n    \2",
)
sub1(
    service,
    r"item\.takeProfitPrice > 0\s*&&\s*item\.takeProfitQuantity \+ quantityTolerance >=\s*targetQuantities\[index\],",
    "item.takeProfitPrice > 0 &&\n            item.takeProfitQuantity.isFinite &&\n            item.takeProfitQuantity > 0 &&\n            item.takeProfitQuantity + comparisonTolerance >= planned,",
)

observer = "src/client/quantara_app/lib/features/trading_journal/application/local_live_journal_observer.dart"
p = Path(observer)
text = p.read_text()
old_r = "(target) => riskPerUnit <= 0"
count = text.count(old_r)
if count != 2:
    raise SystemExit(f"Expected 2 expected-R lambdas, got {count}")
text = text.replace(old_r, "(target) => target <= 0 || riskPerUnit <= 0")
if "confirmed-three-target-ladder" not in text:
    raise SystemExit("Missing legacy target ladder label")
text = text.replace("confirmed-three-target-ladder", "confirmed-active-target-ladder")
if "1.2.0-rc.2+121" not in text:
    raise SystemExit("Missing legacy journal observer version")
text = text.replace("1.2.0-rc.2+121", "1.2.0-rc.2+124")
p.write_text(text)

test_path = Path("src/client/quantara_app/test/issue_173_post_reinstall_regression_test.dart")
test_text = test_path.read_text()
anchor = "  test('recovered journal uses live context without rewriting frozen plan', () {"
insertion = """  test('one exchange lot TP still requires actual positive exchange evidence', () {\n    expect(\n      RemainingTargetProtectionPolicy.allRemainingTargetsProtected(\n        targetOrderIds: const ['tp-1', '', ''],\n        targetQuantities: const [0.1, 0, 0],\n        filledQuantities: const [0, 0, 0],\n        pendingProtection: const [],\n        quantityTolerance: 0.1,\n      ),\n      isFalse,\n    );\n    expect(\n      RemainingTargetProtectionPolicy.allRemainingTargetsProtected(\n        targetOrderIds: const ['tp-1', '', ''],\n        targetQuantities: const [0.1, 0, 0],\n        filledQuantities: const [0, 0, 0],\n        pendingProtection: const [\n          PendingTargetProtectionEvidence(\n            orderId: 'tp-1',\n            triggerPrice: 88.8,\n            quantity: 0,\n          ),\n        ],\n        quantityTolerance: 0.1,\n      ),\n      isFalse,\n    );\n  });\n\n"""
if anchor not in test_text:
    raise SystemExit("Missing test insertion anchor")
test_text = test_text.replace(anchor, insertion + anchor, 1)
old = """    expect(source, contains('if (planned <= 0) continue;'));\n    expect(\n      source,\n      isNot(contains('if (planned <= quantityTolerance) continue;')),\n    );\n  });\n}\n"""
new = """    expect(source, contains('if (planned <= 0) continue;'));\n    expect(source, contains('final comparisonTolerance = quantityTolerance / 2;'));\n    expect(source, contains('item.takeProfitQuantity > 0'));\n    expect(\n      source,\n      isNot(contains('if (planned <= quantityTolerance) continue;')),\n    );\n  });\n\n  test('recovered evidence ignores inactive target R values', () {\n    final source = File(\n      'lib/features/trading_journal/application/local_live_journal_observer.dart',\n    ).readAsStringSync();\n    expect(source, contains('target <= 0 || riskPerUnit <= 0'));\n    expect(source, contains('confirmed-active-target-ladder'));\n    expect(source, contains(\"appVersion: '1.2.0-rc.2+124'\"));\n  });\n}\n"""
if old not in test_text:
    raise SystemExit("Missing test tail anchor")
test_path.write_text(test_text.replace(old, new, 1))

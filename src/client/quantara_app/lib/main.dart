import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import 'app/quantara_app.dart';
import 'features/owner_alpha/data/background_opportunity_scanner.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterForegroundTask.initCommunicationPort();

  // Flutter intentionally replaces build failures with a plain gray box in
  // release mode. Keep the failure bounded and understandable so one malformed
  // card cannot create an apparently endless gray Setups page.
  ErrorWidget.builder = (details) => const _QuantaraBuildFailure();

  runApp(const QuantaraApp());

  WidgetsBinding.instance.addPostFrameCallback((_) {
    unawaited(BackgroundOpportunityScanner.initialize());
  });
}

class _QuantaraBuildFailure extends StatelessWidget {
  const _QuantaraBuildFailure();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: 'Quantara interface recovery Q-UI-001',
      child: SizedBox(
        height: 164,
        width: double.infinity,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xFF181D27),
            border: Border.all(color: const Color(0xFFF4B740)),
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Padding(
            padding: EdgeInsets.all(16),
            child: Directionality(
              textDirection: TextDirection.rtl,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.warning_amber_rounded,
                        color: Color(0xFFF4B740),
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'این بخش موقتاً قابل نمایش نیست',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 8),
                  Text(
                    'صفحه را یک‌بار تازه‌سازی کن. سایر بخش‌ها و سفارش‌های محافظتی صرافی مستقل باقی می‌مانند. کد: Q-UI-001',
                    style: TextStyle(color: Color(0xFFC9CED8), height: 1.5),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

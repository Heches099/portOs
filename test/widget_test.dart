import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:auto_port/app_bootstrap.dart';
import 'package:auto_port/main.dart';
import 'package:auto_port/models/terminal_stats.dart';
import 'package:auto_port/providers/operations_repository.dart';
import 'package:auto_port/services/port_api_service.dart';
import 'package:auto_port/widgets/operations_pie_analysis_card.dart';

void main() {
  testWidgets('shows the login screen by default', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MyApp(
        bootstrapState: AppBootstrapState(isFirebaseAvailable: false),
      ),
    );

    expect(find.text('PORT OS'), findsOneWidget);
    expect(find.text('INITIALIZE SYSTEM'), findsOneWidget);
    expect(find.text('Forgot access key?'), findsOneWidget);
  });

  testWidgets('renders operations pie analysis across time windows',
      (WidgetTester tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1600, 1400);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OperationsPieAnalysisCard(
            stats: TerminalStats.initial(),
            operations: OperationsRepository(
              apiService: PortApiService(firebaseEnabled: false),
            ),
            noticeCount: 2,
          ),
        ),
      ),
    );

    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('Cautions'), findsOneWidget);

    await tester.tap(find.text('Monthly'));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('BREAKDOWN'), findsOneWidget);
  });
}

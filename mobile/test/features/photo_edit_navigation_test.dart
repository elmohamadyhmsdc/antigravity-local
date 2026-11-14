import 'package:antigravity_mobile/core/router.dart';
import 'package:antigravity_mobile/features/photo_edit/photo_edit_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../support/fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Router parses /photo-edit route and builds PhotoEditScreen', (tester) async {
    final router = GoRouter(
      initialLocation: Routes.photoEdit,
      routes: [
        GoRoute(
          path: Routes.photoEdit,
          builder: (context, state) => PhotoEditScreen(
            initialPhotoBytes: tinyPng,
          ),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp.router(
          routerConfig: router,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(PhotoEditScreen), findsOneWidget);
    expect(find.text('AI Photo Edit'), findsOneWidget);
  });
}

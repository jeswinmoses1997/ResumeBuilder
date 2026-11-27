import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:resume_studio/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('moves from profile to experience', (tester) async {
    await tester.pumpWidget(const ResumeStudioApp());

    expect(
      find.text('Let’s build a resume that feels like you.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(find.text('Experience worth highlighting.'), findsOneWidget);
    expect(find.text('Role 1'), findsOneWidget);
  });

  testWidgets('adds another experience entry', (tester) async {
    await tester.pumpWidget(const ResumeStudioApp());
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    final addButton = find.text('Add another experience');
    await tester.ensureVisible(addButton);
    await tester.tap(addButton);
    await tester.pumpAndSettle();

    expect(find.text('Role 1'), findsOneWidget);
    expect(find.text('Role 2'), findsOneWidget);
  });

  testWidgets('restores saved job status from local preferences',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'resume_studio_applications_v1': jsonEncode([
        {
          'role': 'Product Designer',
          'company': 'Example Studio',
          'location': 'Chennai',
          'salaryRange': '',
          'jobDescription': 'Design accessible product experiences.',
          'applicationUrl': 'https://example.com/jobs/1',
          'packagePath': '',
          'status': 'Interview',
        },
      ]),
    });

    await tester.pumpWidget(const ResumeStudioApp());
    await tester.pumpAndSettle();
    for (var step = 0; step < 4; step++) {
      final continueButton = find.text('Continue');
      await tester.ensureVisible(continueButton);
      await tester.tap(continueButton);
      await tester.pumpAndSettle();
    }

    expect(find.text('Product Designer · Example Studio'), findsOneWidget);
    expect(find.text('Interview'), findsOneWidget);
  });

  testWidgets('saves the draft, restores it and clears it', (tester) async {
    Finder field(String label) => find.widgetWithText(TextField, label);
    String textOf(String label) =>
        tester.widget<TextField>(field(label)).controller!.text;

    await tester.pumpWidget(const ResumeStudioApp());
    await tester.pumpAndSettle();
    await tester.enterText(field('Full name'), 'Alex Morgan');
    await tester.enterText(field('Phone number'), '+91 98765 43210');
    await tester.pump(const Duration(seconds: 2));

    // Close the app, then start it again.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(const ResumeStudioApp());
    await tester.pumpAndSettle();
    expect(textOf('Full name'), 'Alex Morgan');
    expect(textOf('Phone number'), '+91 98765 43210');

    final clear = find.text('Clear saved draft');
    await tester.ensureVisible(clear);
    await tester.tap(clear);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clear draft'));
    await tester.pumpAndSettle();
    expect(textOf('Full name'), isEmpty);
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString('resume_studio_draft_v1'), isNull);
  });

  testWidgets('restores experience and education entries', (tester) async {
    SharedPreferences.setMockInitialValues({
      'resume_studio_draft_v1': jsonEncode({
        'experiences': [
          {'title': 'Designer', 'currentRole': true},
          {'title': 'Intern'},
        ],
        'educations': [
          {'degree': 'Master\'s', 'fieldOfStudy': 'Design'},
        ],
      }),
    });
    await tester.pumpWidget(const ResumeStudioApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('Designer'), findsOneWidget);
    expect(find.text('Role 2'), findsOneWidget);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('Design'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

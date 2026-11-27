import 'package:flutter_test/flutter_test.dart';
import 'package:resume_studio/degree.dart';

void main() {
  test('recognises abbreviated and spelled-out degree names', () {
    const expected = {
      'B.Tech': 'Bachelor\'s',
      'B. E. Computer Science': 'Bachelor\'s',
      'BSc': 'Bachelor\'s',
      'MBBS': 'Bachelor\'s',
      'Bachelor of Arts': 'Bachelor\'s',
      'MBA': 'Master\'s',
      'M.Tech': 'Master\'s',
      'M.S.': 'Master\'s',
      'Master of Science': 'Master\'s',
      'Ph.D.': 'PhD',
      'Doctorate': 'PhD',
      'Diploma in ME': 'Other',
      'Higher Secondary': 'Other',
      '': 'Other',
    };
    for (final entry in expected.entries) {
      expect(normalizeDegree(entry.key), entry.value, reason: entry.key);
    }
    expect(normalizeDegree(null), 'Other');
  });
}

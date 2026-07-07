import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:pyrita_app/shared/widgets/py_flag.dart';

void main() {
  test('maps production server country codes to local flag assets', () {
    expect(pyFlagAssetForCode('FI'), 'assets/images/flags/fi.svg');
    expect(pyFlagAssetForCode('us'), 'assets/images/flags/us.svg');
    expect(pyFlagAssetForCode(' RU '), isNull);
  });

  testWidgets('renders server flags from SVG assets', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Row(
            textDirection: TextDirection.ltr,
            children: [
              PyFlag(code: 'FI'),
              PyFlag(code: 'US'),
            ],
          ),
        ),
      ),
    );

    expect(find.byType(SvgPicture), findsNWidgets(2));
  });
}

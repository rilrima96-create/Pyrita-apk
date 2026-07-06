import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pyrita_app/features/account/account_optional_loader.dart';

void main() {
  test('returns loaded value when optional account section completes',
      () async {
    final result = await loadOptionalAccountSection<int>(
      load: () async => 42,
      fallback: 0,
      timeout: const Duration(milliseconds: 50),
    );

    expect(result, 42);
  });

  test('returns fallback quickly when optional account section hangs',
      () async {
    final result = await loadOptionalAccountSection<int>(
      load: () => Completer<int>().future,
      fallback: 7,
      timeout: const Duration(milliseconds: 10),
    );

    expect(result, 7);
  });

  test('returns fallback and reports error when optional account section fails',
      () async {
    Object? capturedError;
    StackTrace? capturedStackTrace;

    final result = await loadOptionalAccountSection<int>(
      load: () async => throw StateError('boom'),
      fallback: 3,
      timeout: const Duration(milliseconds: 50),
      onError: (error, stackTrace) {
        capturedError = error;
        capturedStackTrace = stackTrace;
      },
    );

    expect(result, 3);
    expect(capturedError, isA<StateError>());
    expect(capturedStackTrace, isNotNull);
  });
}

Future<T> loadOptionalAccountSection<T>({
  required Future<T> Function() load,
  required T fallback,
  required Duration timeout,
  void Function(Object error, StackTrace stackTrace)? onError,
}) async {
  try {
    return await load().timeout(timeout);
  } catch (error, stackTrace) {
    onError?.call(error, stackTrace);
    return fallback;
  }
}

/// Serializes foreground library work with the scan without pausing its queue.
typedef LibraryActionRunner = Future<T> Function<T>(Future<T> Function() work);

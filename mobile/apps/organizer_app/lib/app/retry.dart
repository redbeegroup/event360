import 'package:event360_core/event360_core.dart';

import 'errors.dart';

/// The one retry policy for every provider in the app (set on the ProviderScope).
///
/// A failed load is retried only when waiting can help: no answer from the server, or a 5xx. That is at most twice,
/// after 400 ms and then 1 s, so an error screen never takes longer than about 1.4 s to appear.
/// 401/403/404 and every other 4xx are final, and anything that is not an [ApiException] is a bug, not a bad connection.
/// A provider that sets its own `retry` (sales, payouts, attendees) keeps it.
const retryDelays = [Duration(milliseconds: 400), Duration(seconds: 1)];

Duration? appRetry(int retryCount, Object error) {
  if (error is! ApiException || isFinalError(error)) return null;
  final status = error.status;
  if (status != null && status < 500) return null;
  return retryCount < retryDelays.length ? retryDelays[retryCount] : null;
}

import 'package:event360_core/event360_core.dart';

import '../l10n/app_localizations.dart';

/// The reason code of a failed call, from an [ApiException] or a [SeatsChanged].
String? reasonCodeOf(Object error) => switch (error) {
      ApiException(:final reasonCode) => reasonCode,
      SeatsChanged(:final reasonCode) => reasonCode,
      _ => null,
    };

/// Plain text for a failed call, for load errors and action errors alike. Never the server's English `message`.
/// 401, 403 and 404 say what happened; a known `reasonCode` has its own sentence; connection problems and anything
/// else read as the connection text.
String errorText(L10n t, Object error) {
  if (error is ApiException) {
    if (error.status == 401) return t.sessionEnded;
    if (error.status == 403) return t.noAccess;
    if (error.status == 404 && reasonCodeText(t, error.reasonCode) == null) return t.notAvailable;
  }
  final reason = reasonCodeText(t, reasonCodeOf(error));
  return reason ?? t.loadError;
}

/// The sentence for a machine code from the API, or null when the code is not known (or absent).
String? reasonCodeText(L10n t, String? code) => switch (code) {
      'SEATS_NOT_AVAILABLE' => t.reasonSeatsNotAvailable,
      'SEATS_NOT_HELD' || 'SEATS_MUST_BE_HELD_FIRST' => t.reasonSeatsNotHeld,
      'NO_SEAT_MAP' => t.reasonNoSeatMap,
      'EVENT_ENDED' => t.reasonEventEnded,
      'GUEST_ALREADY_CHECKED_IN' => t.reasonGuestAlreadyCheckedIn,
      'GUEST_ALREADY_REVOKED' => t.reasonGuestAlreadyRevoked,
      'GUEST_TICKET_NOT_FOUND' => t.reasonGuestTicketNotFound,
      'NOT_CHECKED_IN' => t.reasonNotCheckedIn,
      _ => null,
    };

/// A load error that retrying cannot fix: no access, or the thing is gone.
bool isFinalError(Object? error) => error is ApiException && (error.status == 403 || error.status == 404);

import 'package:event360_core/event360_core.dart';

import '../l10n/app_localizations.dart';

/// Localized text for a waitlist or offer error: the API's `reasonCode`, never its raw English `message`.
/// Unknown codes and network errors get a generic localized line.
String waitlistErrorText(L10n t, Object error) {
  if (error is! ApiException) return t.waitlistGenericError;
  switch (error.reasonCode) {
    case 'WAITLIST_CLOSED':
      return t.waitlistClosed;
    case 'WAITLIST_PAUSED':
      return t.waitlistPaused;
    case 'ALREADY_WAITING':
      return t.waitlistAlreadyIn;
    case 'NOT_SOLD_OUT':
      return t.waitlistNotSoldOut;
    case 'LIMIT':
      return t.waitlistLimit;
    case 'CHECKOUT_PENDING':
      return t.waitlistCheckoutPending;
    case 'OFFER_CLOSED':
      return t.offerClosed;
    case 'NOT_WAITING':
      return t.waitlistNotIn;
    default:
      return error.isNetwork ? t.loadError : t.waitlistGenericError;
  }
}

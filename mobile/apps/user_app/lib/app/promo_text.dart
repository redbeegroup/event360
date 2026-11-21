import '../l10n/app_localizations.dart';

/// Localized text for a rejected promo code. Unknown or absent codes fall back to the generic "not valid" text,
/// so raw API English is never shown.
String promoReasonText(L10n t, String? reasonCode) {
  switch (reasonCode) {
    case 'USED_UP':
      return t.promoUsedUp;
    case 'EXPIRED':
      return t.promoExpired;
    case 'NOT_STARTED':
      return t.promoNotStarted;
    case 'NOT_APPLICABLE':
      return t.promoNotApplicable;
    default:
      return t.promoInvalid;
  }
}

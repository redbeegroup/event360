import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_my.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of L10n
/// returned by `L10n.of(context)`.
///
/// Applications need to include `L10n.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: L10n.localizationsDelegates,
///   supportedLocales: L10n.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the L10n.supportedLocales
/// property.
abstract class L10n {
  L10n(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static L10n of(BuildContext context) {
    return Localizations.of<L10n>(context, L10n)!;
  }

  static const LocalizationsDelegate<L10n> delegate = _L10nDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('my'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'Event 360 Crew'**
  String get appTitle;

  /// No description provided for @signInTitle.
  ///
  /// In en, this message translates to:
  /// **'Door check-in'**
  String get signInTitle;

  /// No description provided for @tabAccount.
  ///
  /// In en, this message translates to:
  /// **'Crew account'**
  String get tabAccount;

  /// No description provided for @tabCode.
  ///
  /// In en, this message translates to:
  /// **'Event code'**
  String get tabCode;

  /// No description provided for @email.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get email;

  /// No description provided for @password.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get password;

  /// No description provided for @signIn.
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get signIn;

  /// No description provided for @eventCode.
  ///
  /// In en, this message translates to:
  /// **'Event code'**
  String get eventCode;

  /// No description provided for @eventCodeHint.
  ///
  /// In en, this message translates to:
  /// **'From the organizer, e.g. K7QM-4XRT'**
  String get eventCodeHint;

  /// No description provided for @deviceName.
  ///
  /// In en, this message translates to:
  /// **'Device name'**
  String get deviceName;

  /// No description provided for @deviceNameHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. Gate A phone'**
  String get deviceNameHint;

  /// No description provided for @useCode.
  ///
  /// In en, this message translates to:
  /// **'Start with this code'**
  String get useCode;

  /// No description provided for @scanCodeQr.
  ///
  /// In en, this message translates to:
  /// **'Scan the organizer\'s QR'**
  String get scanCodeQr;

  /// No description provided for @chooseEvent.
  ///
  /// In en, this message translates to:
  /// **'Choose event'**
  String get chooseEvent;

  /// No description provided for @noEvents.
  ///
  /// In en, this message translates to:
  /// **'No events to check in right now. Ask the organizer to add you as crew.'**
  String get noEvents;

  /// No description provided for @setupTitle.
  ///
  /// In en, this message translates to:
  /// **'Gate setup'**
  String get setupTitle;

  /// No description provided for @gate.
  ///
  /// In en, this message translates to:
  /// **'Gate'**
  String get gate;

  /// No description provided for @gateHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. Main gate, VIP entrance'**
  String get gateHint;

  /// No description provided for @startScanning.
  ///
  /// In en, this message translates to:
  /// **'Start scanning'**
  String get startScanning;

  /// No description provided for @pointCamera.
  ///
  /// In en, this message translates to:
  /// **'Point the camera at the ticket QR'**
  String get pointCamera;

  /// No description provided for @typeOrScan.
  ///
  /// In en, this message translates to:
  /// **'Ticket QR text or code (handheld scanners work here too)'**
  String get typeOrScan;

  /// No description provided for @submit.
  ///
  /// In en, this message translates to:
  /// **'Check'**
  String get submit;

  /// No description provided for @resultAccepted.
  ///
  /// In en, this message translates to:
  /// **'Checked in'**
  String get resultAccepted;

  /// No description provided for @resultDuplicate.
  ///
  /// In en, this message translates to:
  /// **'Already checked in'**
  String get resultDuplicate;

  /// No description provided for @resultWrongEvent.
  ///
  /// In en, this message translates to:
  /// **'Ticket for another event'**
  String get resultWrongEvent;

  /// No description provided for @resultInvalid.
  ///
  /// In en, this message translates to:
  /// **'Not a valid ticket'**
  String get resultInvalid;

  /// No description provided for @resultVoid.
  ///
  /// In en, this message translates to:
  /// **'Ticket cancelled'**
  String get resultVoid;

  /// No description provided for @resultRefunded.
  ///
  /// In en, this message translates to:
  /// **'Ticket refunded'**
  String get resultRefunded;

  /// No description provided for @resultTransferred.
  ///
  /// In en, this message translates to:
  /// **'Ticket was transferred — ask for the new QR'**
  String get resultTransferred;

  /// No description provided for @outdatedQr.
  ///
  /// In en, this message translates to:
  /// **'This QR is out of date — ask the guest to reopen their ticket'**
  String get outdatedQr;

  /// No description provided for @otherEvent.
  ///
  /// In en, this message translates to:
  /// **'For: {title}'**
  String otherEvent(String title);

  /// No description provided for @checkedInAt.
  ///
  /// In en, this message translates to:
  /// **'Checked in at {time}'**
  String checkedInAt(String time);

  /// No description provided for @atGate.
  ///
  /// In en, this message translates to:
  /// **'at {gate}'**
  String atGate(String gate);

  /// No description provided for @byWho.
  ///
  /// In en, this message translates to:
  /// **'by {name}'**
  String byWho(String name);

  /// No description provided for @offline.
  ///
  /// In en, this message translates to:
  /// **'Offline'**
  String get offline;

  /// No description provided for @offlineBanner.
  ///
  /// In en, this message translates to:
  /// **'No connection — checking tickets on this device. {n} scan(s) waiting to sync.'**
  String offlineBanner(int n);

  /// No description provided for @pendingSync.
  ///
  /// In en, this message translates to:
  /// **'{n} waiting to sync'**
  String pendingSync(int n);

  /// No description provided for @offlineChecked.
  ///
  /// In en, this message translates to:
  /// **'Checked offline'**
  String get offlineChecked;

  /// No description provided for @notInList.
  ///
  /// In en, this message translates to:
  /// **'Not in the downloaded list yet — signature is valid'**
  String get notInList;

  /// No description provided for @syncConflict.
  ///
  /// In en, this message translates to:
  /// **'Synced: was already checked in at another gate'**
  String get syncConflict;

  /// No description provided for @lookup.
  ///
  /// In en, this message translates to:
  /// **'Find guest'**
  String get lookup;

  /// No description provided for @searchHint.
  ///
  /// In en, this message translates to:
  /// **'Name, phone digits or ticket code'**
  String get searchHint;

  /// No description provided for @noResults.
  ///
  /// In en, this message translates to:
  /// **'No matching tickets'**
  String get noResults;

  /// No description provided for @checkIn.
  ///
  /// In en, this message translates to:
  /// **'Check in'**
  String get checkIn;

  /// No description provided for @confirmCheckIn.
  ///
  /// In en, this message translates to:
  /// **'Check in {name}?'**
  String confirmCheckIn(String name);

  /// No description provided for @activity.
  ///
  /// In en, this message translates to:
  /// **'Activity'**
  String get activity;

  /// No description provided for @undo.
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get undo;

  /// No description provided for @undoConfirm.
  ///
  /// In en, this message translates to:
  /// **'Undo the check-in for {name}? The ticket can be scanned again.'**
  String undoConfirm(String name);

  /// No description provided for @undone.
  ///
  /// In en, this message translates to:
  /// **'Undone'**
  String get undone;

  /// No description provided for @undoOffline.
  ///
  /// In en, this message translates to:
  /// **'Undo needs a connection'**
  String get undoOffline;

  /// No description provided for @duplicate.
  ///
  /// In en, this message translates to:
  /// **'Duplicate'**
  String get duplicate;

  /// No description provided for @manual.
  ///
  /// In en, this message translates to:
  /// **'Manual'**
  String get manual;

  /// No description provided for @attendance.
  ///
  /// In en, this message translates to:
  /// **'{checked} / {total} checked in'**
  String attendance(int checked, int total);

  /// No description provided for @byGate.
  ///
  /// In en, this message translates to:
  /// **'By gate'**
  String get byGate;

  /// No description provided for @byTicketType.
  ///
  /// In en, this message translates to:
  /// **'By ticket type'**
  String get byTicketType;

  /// No description provided for @noGate.
  ///
  /// In en, this message translates to:
  /// **'(no gate)'**
  String get noGate;

  /// No description provided for @recentScans.
  ///
  /// In en, this message translates to:
  /// **'Recent scans'**
  String get recentScans;

  /// No description provided for @noScans.
  ///
  /// In en, this message translates to:
  /// **'No scans yet'**
  String get noScans;

  /// No description provided for @signOut.
  ///
  /// In en, this message translates to:
  /// **'Sign out'**
  String get signOut;

  /// No description provided for @switchEvent.
  ///
  /// In en, this message translates to:
  /// **'Change event or gate'**
  String get switchEvent;

  /// No description provided for @cameraUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Camera not available — type the code or use a handheld scanner.'**
  String get cameraUnavailable;

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// No description provided for @loadError.
  ///
  /// In en, this message translates to:
  /// **'Could not load. Check the connection.'**
  String get loadError;

  /// No description provided for @sessionEnded.
  ///
  /// In en, this message translates to:
  /// **'Your session ended. Sign in again.'**
  String get sessionEnded;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @ok.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get ok;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'မြန်မာ / English'**
  String get language;
}

class _L10nDelegate extends LocalizationsDelegate<L10n> {
  const _L10nDelegate();

  @override
  Future<L10n> load(Locale locale) {
    return SynchronousFuture<L10n>(lookupL10n(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'my'].contains(locale.languageCode);

  @override
  bool shouldReload(_L10nDelegate old) => false;
}

L10n lookupL10n(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return L10nEn();
    case 'my':
      return L10nMy();
  }

  throw FlutterError(
    'L10n.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}

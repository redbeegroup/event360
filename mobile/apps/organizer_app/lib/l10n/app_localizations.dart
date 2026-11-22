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
  /// **'Event 360 Organizer'**
  String get appTitle;

  /// No description provided for @signInTitle.
  ///
  /// In en, this message translates to:
  /// **'Sign in with your organizer account'**
  String get signInTitle;

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

  /// No description provided for @signOut.
  ///
  /// In en, this message translates to:
  /// **'Sign out'**
  String get signOut;

  /// No description provided for @notOrganizer.
  ///
  /// In en, this message translates to:
  /// **'This account is not part of any organization. Ask your organization owner to invite you in the portal.'**
  String get notOrganizer;

  /// No description provided for @events.
  ///
  /// In en, this message translates to:
  /// **'Events'**
  String get events;

  /// No description provided for @upcoming.
  ///
  /// In en, this message translates to:
  /// **'Upcoming'**
  String get upcoming;

  /// No description provided for @past.
  ///
  /// In en, this message translates to:
  /// **'Past'**
  String get past;

  /// No description provided for @noEvents.
  ///
  /// In en, this message translates to:
  /// **'No events yet. Create events in the portal.'**
  String get noEvents;

  /// No description provided for @liveNow.
  ///
  /// In en, this message translates to:
  /// **'Live now'**
  String get liveNow;

  /// No description provided for @loadError.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load. Check your connection.'**
  String get loadError;

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// No description provided for @organization.
  ///
  /// In en, this message translates to:
  /// **'Organization'**
  String get organization;

  /// No description provided for @status_DRAFT.
  ///
  /// In en, this message translates to:
  /// **'Draft'**
  String get status_DRAFT;

  /// No description provided for @status_SUBMITTED.
  ///
  /// In en, this message translates to:
  /// **'In review'**
  String get status_SUBMITTED;

  /// No description provided for @status_PUBLISHED.
  ///
  /// In en, this message translates to:
  /// **'Published'**
  String get status_PUBLISHED;

  /// No description provided for @status_ONGOING.
  ///
  /// In en, this message translates to:
  /// **'Ongoing'**
  String get status_ONGOING;

  /// No description provided for @status_COMPLETED.
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get status_COMPLETED;

  /// No description provided for @status_CANCELLED.
  ///
  /// In en, this message translates to:
  /// **'Cancelled'**
  String get status_CANCELLED;

  /// No description provided for @status_REJECTED.
  ///
  /// In en, this message translates to:
  /// **'Rejected'**
  String get status_REJECTED;

  /// No description provided for @orderStatus_PENDING_PAYMENT.
  ///
  /// In en, this message translates to:
  /// **'Awaiting payment'**
  String get orderStatus_PENDING_PAYMENT;

  /// No description provided for @orderStatus_PAID.
  ///
  /// In en, this message translates to:
  /// **'Paid'**
  String get orderStatus_PAID;

  /// No description provided for @orderStatus_CONFIRMED.
  ///
  /// In en, this message translates to:
  /// **'Confirmed'**
  String get orderStatus_CONFIRMED;

  /// No description provided for @orderStatus_EXPIRED.
  ///
  /// In en, this message translates to:
  /// **'Expired'**
  String get orderStatus_EXPIRED;

  /// No description provided for @orderStatus_CANCELLED.
  ///
  /// In en, this message translates to:
  /// **'Cancelled'**
  String get orderStatus_CANCELLED;

  /// No description provided for @orderStatus_REFUNDED.
  ///
  /// In en, this message translates to:
  /// **'Refunded'**
  String get orderStatus_REFUNDED;

  /// No description provided for @orderStatus_FAILED.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get orderStatus_FAILED;

  /// No description provided for @tabOverview.
  ///
  /// In en, this message translates to:
  /// **'Overview'**
  String get tabOverview;

  /// No description provided for @tabDoor.
  ///
  /// In en, this message translates to:
  /// **'Door'**
  String get tabDoor;

  /// No description provided for @tabAnnounce.
  ///
  /// In en, this message translates to:
  /// **'Announce'**
  String get tabAnnounce;

  /// No description provided for @tabPromos.
  ///
  /// In en, this message translates to:
  /// **'Promos'**
  String get tabPromos;

  /// No description provided for @ticketsSold.
  ///
  /// In en, this message translates to:
  /// **'Tickets sold'**
  String get ticketsSold;

  /// No description provided for @revenue.
  ///
  /// In en, this message translates to:
  /// **'Revenue'**
  String get revenue;

  /// No description provided for @checkedIn.
  ///
  /// In en, this message translates to:
  /// **'Checked in'**
  String get checkedIn;

  /// No description provided for @orders.
  ///
  /// In en, this message translates to:
  /// **'Orders'**
  String get orders;

  /// No description provided for @pageViews.
  ///
  /// In en, this message translates to:
  /// **'Page views'**
  String get pageViews;

  /// No description provided for @discounts.
  ///
  /// In en, this message translates to:
  /// **'Discounts'**
  String get discounts;

  /// No description provided for @byTicketType.
  ///
  /// In en, this message translates to:
  /// **'By ticket type'**
  String get byTicketType;

  /// No description provided for @seatsTitle.
  ///
  /// In en, this message translates to:
  /// **'Seats'**
  String get seatsTitle;

  /// No description provided for @seatsAvailable.
  ///
  /// In en, this message translates to:
  /// **'Available'**
  String get seatsAvailable;

  /// No description provided for @seatsHeld.
  ///
  /// In en, this message translates to:
  /// **'Held at checkout'**
  String get seatsHeld;

  /// No description provided for @seatsGuest.
  ///
  /// In en, this message translates to:
  /// **'Held for guests'**
  String get seatsGuest;

  /// No description provided for @seatsSold.
  ///
  /// In en, this message translates to:
  /// **'Sold'**
  String get seatsSold;

  /// No description provided for @seatsComp.
  ///
  /// In en, this message translates to:
  /// **'Complimentary'**
  String get seatsComp;

  /// No description provided for @byGate.
  ///
  /// In en, this message translates to:
  /// **'Check-ins by gate'**
  String get byGate;

  /// No description provided for @recentOrders.
  ///
  /// In en, this message translates to:
  /// **'Recent orders'**
  String get recentOrders;

  /// No description provided for @noOrders.
  ///
  /// In en, this message translates to:
  /// **'No orders yet.'**
  String get noOrders;

  /// No description provided for @updatedAt.
  ///
  /// In en, this message translates to:
  /// **'Updated {time}'**
  String updatedAt(String time);

  /// No description provided for @noGate.
  ///
  /// In en, this message translates to:
  /// **'No gate'**
  String get noGate;

  /// No description provided for @doorHint.
  ///
  /// In en, this message translates to:
  /// **'Create a code for each group of volunteers. They open the Crew app, scan the QR (or type the code) and start checking tickets in.'**
  String get doorHint;

  /// No description provided for @codeLabel.
  ///
  /// In en, this message translates to:
  /// **'Name (e.g. Volunteers)'**
  String get codeLabel;

  /// No description provided for @gate.
  ///
  /// In en, this message translates to:
  /// **'Gate (optional)'**
  String get gate;

  /// No description provided for @createCode.
  ///
  /// In en, this message translates to:
  /// **'Create code'**
  String get createCode;

  /// No description provided for @codeCreated.
  ///
  /// In en, this message translates to:
  /// **'Show this to your volunteers'**
  String get codeCreated;

  /// No description provided for @codeOnce.
  ///
  /// In en, this message translates to:
  /// **'The code is shown only now. Create a new one if it gets lost.'**
  String get codeOnce;

  /// No description provided for @revoke.
  ///
  /// In en, this message translates to:
  /// **'Revoke'**
  String get revoke;

  /// No description provided for @revokeConfirm.
  ///
  /// In en, this message translates to:
  /// **'Revoke this code? Phones using it are signed out.'**
  String get revokeConfirm;

  /// No description provided for @devices.
  ///
  /// In en, this message translates to:
  /// **'{n} phones'**
  String devices(int n);

  /// No description provided for @expired.
  ///
  /// In en, this message translates to:
  /// **'Expired'**
  String get expired;

  /// No description provided for @revoked.
  ///
  /// In en, this message translates to:
  /// **'Revoked'**
  String get revoked;

  /// No description provided for @openCrewApp.
  ///
  /// In en, this message translates to:
  /// **'Open the Crew app'**
  String get openCrewApp;

  /// No description provided for @done.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get done;

  /// No description provided for @announceHint.
  ///
  /// In en, this message translates to:
  /// **'Sends a notification to everyone holding a ticket (not SMS). Up to 3 per day.'**
  String get announceHint;

  /// No description provided for @recipients.
  ///
  /// In en, this message translates to:
  /// **'{n} ticket holders'**
  String recipients(int n);

  /// No description provided for @leftToday.
  ///
  /// In en, this message translates to:
  /// **'{n} left today'**
  String leftToday(int n);

  /// No description provided for @heading.
  ///
  /// In en, this message translates to:
  /// **'Heading'**
  String get heading;

  /// No description provided for @message.
  ///
  /// In en, this message translates to:
  /// **'Message'**
  String get message;

  /// No description provided for @headingMy.
  ///
  /// In en, this message translates to:
  /// **'Heading (Myanmar, optional)'**
  String get headingMy;

  /// No description provided for @messageMy.
  ///
  /// In en, this message translates to:
  /// **'Message (Myanmar, optional)'**
  String get messageMy;

  /// No description provided for @send.
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get send;

  /// No description provided for @sendConfirm.
  ///
  /// In en, this message translates to:
  /// **'Send this to all ticket holders now?'**
  String get sendConfirm;

  /// No description provided for @sent.
  ///
  /// In en, this message translates to:
  /// **'Sent'**
  String get sent;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @noAnnouncements.
  ///
  /// In en, this message translates to:
  /// **'Nothing sent yet.'**
  String get noAnnouncements;

  /// No description provided for @promosHint.
  ///
  /// In en, this message translates to:
  /// **'Discounts for paid tickets. Commission is calculated on the discounted price.'**
  String get promosHint;

  /// No description provided for @promoCode.
  ///
  /// In en, this message translates to:
  /// **'Code'**
  String get promoCode;

  /// No description provided for @percent.
  ///
  /// In en, this message translates to:
  /// **'% off'**
  String get percent;

  /// No description provided for @fixed.
  ///
  /// In en, this message translates to:
  /// **'MMK off'**
  String get fixed;

  /// No description provided for @amount.
  ///
  /// In en, this message translates to:
  /// **'Amount'**
  String get amount;

  /// No description provided for @maxUses.
  ///
  /// In en, this message translates to:
  /// **'Max uses (optional)'**
  String get maxUses;

  /// No description provided for @createPromo.
  ///
  /// In en, this message translates to:
  /// **'Create code'**
  String get createPromo;

  /// No description provided for @used.
  ///
  /// In en, this message translates to:
  /// **'Used {n}'**
  String used(String n);

  /// No description provided for @turnOn.
  ///
  /// In en, this message translates to:
  /// **'Turn on'**
  String get turnOn;

  /// No description provided for @turnOff.
  ///
  /// In en, this message translates to:
  /// **'Turn off'**
  String get turnOff;

  /// No description provided for @off.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get off;

  /// No description provided for @noPromos.
  ///
  /// In en, this message translates to:
  /// **'No codes yet.'**
  String get noPromos;

  /// No description provided for @notifications.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get notifications;

  /// No description provided for @markAllRead.
  ///
  /// In en, this message translates to:
  /// **'Mark all read'**
  String get markAllRead;

  /// No description provided for @noNotifications.
  ///
  /// In en, this message translates to:
  /// **'Sales milestones, approvals and the daily summary will appear here.'**
  String get noNotifications;

  /// No description provided for @readOnly.
  ///
  /// In en, this message translates to:
  /// **'View only: your role can\'t change this.'**
  String get readOnly;

  /// No description provided for @tabGuests.
  ///
  /// In en, this message translates to:
  /// **'Guests'**
  String get tabGuests;

  /// No description provided for @guestsCount.
  ///
  /// In en, this message translates to:
  /// **'{inCount} of {total} checked in'**
  String guestsCount(int inCount, int total);

  /// No description provided for @guestsSearch.
  ///
  /// In en, this message translates to:
  /// **'Search name, phone or seat'**
  String get guestsSearch;

  /// No description provided for @guestsNotIn.
  ///
  /// In en, this message translates to:
  /// **'Not checked in'**
  String get guestsNotIn;

  /// No description provided for @statusIn.
  ///
  /// In en, this message translates to:
  /// **'Checked in'**
  String get statusIn;

  /// No description provided for @statusNotIn.
  ///
  /// In en, this message translates to:
  /// **'Not in'**
  String get statusNotIn;

  /// No description provided for @statusCancelled.
  ///
  /// In en, this message translates to:
  /// **'Cancelled'**
  String get statusCancelled;

  /// No description provided for @guestBadge.
  ///
  /// In en, this message translates to:
  /// **'Guest'**
  String get guestBadge;

  /// No description provided for @guestsEmpty.
  ///
  /// In en, this message translates to:
  /// **'No tickets yet'**
  String get guestsEmpty;

  /// No description provided for @guestsNoMatch.
  ///
  /// In en, this message translates to:
  /// **'No one matches'**
  String get guestsNoMatch;

  /// No description provided for @checkIn.
  ///
  /// In en, this message translates to:
  /// **'Check in'**
  String get checkIn;

  /// No description provided for @undoCheckIn.
  ///
  /// In en, this message translates to:
  /// **'Undo check-in'**
  String get undoCheckIn;

  /// No description provided for @undoCheckInConfirm.
  ///
  /// In en, this message translates to:
  /// **'Undo the check-in for {name}?'**
  String undoCheckInConfirm(String name);

  /// No description provided for @checkedInOk.
  ///
  /// In en, this message translates to:
  /// **'{name} is checked in'**
  String checkedInOk(String name);

  /// No description provided for @alreadyCheckedIn.
  ///
  /// In en, this message translates to:
  /// **'Already checked in at {time}'**
  String alreadyCheckedIn(String time);

  /// No description provided for @alreadyCheckedInGate.
  ///
  /// In en, this message translates to:
  /// **'Already checked in at {time}, {gate}'**
  String alreadyCheckedInGate(String time, String gate);

  /// No description provided for @checkInRefused.
  ///
  /// In en, this message translates to:
  /// **'Can\'t check in: this ticket is {status}'**
  String checkInRefused(String status);

  /// No description provided for @checkInNoConnection.
  ///
  /// In en, this message translates to:
  /// **'Not checked in — no connection. Try again.'**
  String get checkInNoConnection;

  /// No description provided for @checkInClosed.
  ///
  /// In en, this message translates to:
  /// **'Check-in opens one day before the event'**
  String get checkInClosed;

  /// No description provided for @call.
  ///
  /// In en, this message translates to:
  /// **'Call'**
  String get call;

  /// No description provided for @registeredOn.
  ///
  /// In en, this message translates to:
  /// **'Registered {date}'**
  String registeredOn(String date);

  /// No description provided for @checkInRefusedGeneric.
  ///
  /// In en, this message translates to:
  /// **'Can\'t check in this ticket'**
  String get checkInRefusedGeneric;

  /// No description provided for @tabSeats.
  ///
  /// In en, this message translates to:
  /// **'Seats'**
  String get tabSeats;

  /// No description provided for @seatsSelected.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 seat selected} other{{count} seats selected}}'**
  String seatsSelected(int count);

  /// No description provided for @clear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get clear;

  /// No description provided for @holdForGuests.
  ///
  /// In en, this message translates to:
  /// **'Hold for guests'**
  String get holdForGuests;

  /// No description provided for @holdLabelField.
  ///
  /// In en, this message translates to:
  /// **'Label (e.g. Sponsor)'**
  String get holdLabelField;

  /// No description provided for @releaseSeats.
  ///
  /// In en, this message translates to:
  /// **'Release'**
  String get releaseSeats;

  /// No description provided for @releaseConfirm.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Put 1 seat back on sale?} other{Put {count} seats back on sale?}}'**
  String releaseConfirm(int count);

  /// No description provided for @issueGuestTickets.
  ///
  /// In en, this message translates to:
  /// **'Issue guest tickets'**
  String get issueGuestTickets;

  /// No description provided for @guestNameField.
  ///
  /// In en, this message translates to:
  /// **'Guest name'**
  String get guestNameField;

  /// No description provided for @guestPhoneField.
  ///
  /// In en, this message translates to:
  /// **'Guest phone'**
  String get guestPhoneField;

  /// No description provided for @guestLabelField.
  ///
  /// In en, this message translates to:
  /// **'Label (optional)'**
  String get guestLabelField;

  /// No description provided for @issueHelp.
  ///
  /// In en, this message translates to:
  /// **'The guest finds the tickets in the Event 360 app after signing in with this number. No SMS is sent.'**
  String get issueHelp;

  /// No description provided for @issueConfirmText.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Issue 1 guest ticket to {phone}?} other{Issue {count} guest tickets to {phone}?}}'**
  String issueConfirmText(int count, String phone);

  /// No description provided for @seatsMixedHint.
  ///
  /// In en, this message translates to:
  /// **'Select only free seats or only held seats'**
  String get seatsMixedHint;

  /// No description provided for @seatsNoTypeHint.
  ///
  /// In en, this message translates to:
  /// **'Some held seats have no ticket type'**
  String get seatsNoTypeHint;

  /// No description provided for @seatsTooMany.
  ///
  /// In en, this message translates to:
  /// **'Select 200 seats or fewer'**
  String get seatsTooMany;

  /// No description provided for @seatsChanged.
  ///
  /// In en, this message translates to:
  /// **'Some of those seats changed. The map has been updated.'**
  String get seatsChanged;

  /// No description provided for @heldLabel.
  ///
  /// In en, this message translates to:
  /// **'Held: {label}'**
  String heldLabel(String label);

  /// No description provided for @legendAvailable.
  ///
  /// In en, this message translates to:
  /// **'On sale'**
  String get legendAvailable;

  /// No description provided for @legendHeld.
  ///
  /// In en, this message translates to:
  /// **'Held for guests'**
  String get legendHeld;

  /// No description provided for @legendSold.
  ///
  /// In en, this message translates to:
  /// **'Sold'**
  String get legendSold;

  /// No description provided for @legendGuest.
  ///
  /// In en, this message translates to:
  /// **'Guest tickets'**
  String get legendGuest;

  /// No description provided for @guestList.
  ///
  /// In en, this message translates to:
  /// **'Guest tickets'**
  String get guestList;

  /// No description provided for @revokeGuestConfirm.
  ///
  /// In en, this message translates to:
  /// **'Revoke the guest ticket for {name}?'**
  String revokeGuestConfirm(String name);

  /// No description provided for @guestRevoked.
  ///
  /// In en, this message translates to:
  /// **'Revoked'**
  String get guestRevoked;

  /// No description provided for @phoneInvalid.
  ///
  /// In en, this message translates to:
  /// **'Enter a Myanmar mobile number'**
  String get phoneInvalid;

  /// No description provided for @viewOnlySeats.
  ///
  /// In en, this message translates to:
  /// **'You can view seats but not change them'**
  String get viewOnlySeats;

  /// No description provided for @seatsZoomHint.
  ///
  /// In en, this message translates to:
  /// **'Zoom in to select seats'**
  String get seatsZoomHint;

  /// No description provided for @fieldRequired.
  ///
  /// In en, this message translates to:
  /// **'Required'**
  String get fieldRequired;

  /// No description provided for @noGuestTickets.
  ///
  /// In en, this message translates to:
  /// **'No guest tickets yet'**
  String get noGuestTickets;
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

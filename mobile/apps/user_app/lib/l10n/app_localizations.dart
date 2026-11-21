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
  /// **'Event 360'**
  String get appTitle;

  /// No description provided for @home.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get home;

  /// No description provided for @explore.
  ///
  /// In en, this message translates to:
  /// **'Explore'**
  String get explore;

  /// No description provided for @myTickets.
  ///
  /// In en, this message translates to:
  /// **'My tickets'**
  String get myTickets;

  /// No description provided for @profile.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get profile;

  /// No description provided for @searchHint.
  ///
  /// In en, this message translates to:
  /// **'Search events'**
  String get searchHint;

  /// No description provided for @allCategories.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get allCategories;

  /// No description provided for @upcoming.
  ///
  /// In en, this message translates to:
  /// **'Upcoming events'**
  String get upcoming;

  /// No description provided for @freeEvents.
  ///
  /// In en, this message translates to:
  /// **'Free events'**
  String get freeEvents;

  /// No description provided for @seeAll.
  ///
  /// In en, this message translates to:
  /// **'See all'**
  String get seeAll;

  /// No description provided for @noEvents.
  ///
  /// In en, this message translates to:
  /// **'No events found.'**
  String get noEvents;

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

  /// No description provided for @free.
  ///
  /// In en, this message translates to:
  /// **'Free'**
  String get free;

  /// No description provided for @soldOut.
  ///
  /// In en, this message translates to:
  /// **'Sold out'**
  String get soldOut;

  /// No description provided for @fromPrice.
  ///
  /// In en, this message translates to:
  /// **'From {price}'**
  String fromPrice(String price);

  /// No description provided for @mmk.
  ///
  /// In en, this message translates to:
  /// **'{amount} MMK'**
  String mmk(String amount);

  /// No description provided for @register.
  ///
  /// In en, this message translates to:
  /// **'Register'**
  String get register;

  /// No description provided for @registerFree.
  ///
  /// In en, this message translates to:
  /// **'Register for free'**
  String get registerFree;

  /// No description provided for @quantity.
  ///
  /// In en, this message translates to:
  /// **'Tickets'**
  String get quantity;

  /// No description provided for @perPersonLimit.
  ///
  /// In en, this message translates to:
  /// **'Up to {n} per person'**
  String perPersonLimit(int n);

  /// No description provided for @remaining.
  ///
  /// In en, this message translates to:
  /// **'{n} left'**
  String remaining(int n);

  /// No description provided for @tickets.
  ///
  /// In en, this message translates to:
  /// **'Tickets'**
  String get tickets;

  /// No description provided for @about.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get about;

  /// No description provided for @organizer.
  ///
  /// In en, this message translates to:
  /// **'Organizer'**
  String get organizer;

  /// No description provided for @verified.
  ///
  /// In en, this message translates to:
  /// **'Verified organizer'**
  String get verified;

  /// No description provided for @venue.
  ///
  /// In en, this message translates to:
  /// **'Venue'**
  String get venue;

  /// No description provided for @formatOnline.
  ///
  /// In en, this message translates to:
  /// **'Online'**
  String get formatOnline;

  /// No description provided for @formatInPerson.
  ///
  /// In en, this message translates to:
  /// **'In person'**
  String get formatInPerson;

  /// No description provided for @formatHybrid.
  ///
  /// In en, this message translates to:
  /// **'In person + online'**
  String get formatHybrid;

  /// No description provided for @paidSoon.
  ///
  /// In en, this message translates to:
  /// **'Paid tickets will be available soon.'**
  String get paidSoon;

  /// No description provided for @signIn.
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get signIn;

  /// No description provided for @signInToRegister.
  ///
  /// In en, this message translates to:
  /// **'Sign in with your phone number to register.'**
  String get signInToRegister;

  /// No description provided for @phoneNumber.
  ///
  /// In en, this message translates to:
  /// **'Phone number'**
  String get phoneNumber;

  /// No description provided for @phoneHint.
  ///
  /// In en, this message translates to:
  /// **'09xxxxxxxxx'**
  String get phoneHint;

  /// No description provided for @sendCode.
  ///
  /// In en, this message translates to:
  /// **'Send code'**
  String get sendCode;

  /// No description provided for @codeSentTo.
  ///
  /// In en, this message translates to:
  /// **'Enter the 6-digit code sent to {phone}'**
  String codeSentTo(String phone);

  /// No description provided for @code.
  ///
  /// In en, this message translates to:
  /// **'Code'**
  String get code;

  /// No description provided for @verify.
  ///
  /// In en, this message translates to:
  /// **'Verify'**
  String get verify;

  /// No description provided for @changeNumber.
  ///
  /// In en, this message translates to:
  /// **'Change number'**
  String get changeNumber;

  /// No description provided for @devCode.
  ///
  /// In en, this message translates to:
  /// **'Test environment code: {code}'**
  String devCode(String code);

  /// No description provided for @invalidPhone.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid Myanmar mobile number (09…)'**
  String get invalidPhone;

  /// No description provided for @invalidCode.
  ///
  /// In en, this message translates to:
  /// **'Enter the 6-digit code'**
  String get invalidCode;

  /// No description provided for @tooManyCodes.
  ///
  /// In en, this message translates to:
  /// **'Too many codes requested. Please wait a few minutes.'**
  String get tooManyCodes;

  /// No description provided for @signOut.
  ///
  /// In en, this message translates to:
  /// **'Sign out'**
  String get signOut;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @signedInAs.
  ///
  /// In en, this message translates to:
  /// **'Signed in as {phone}'**
  String signedInAs(String phone);

  /// No description provided for @notSignedIn.
  ///
  /// In en, this message translates to:
  /// **'You are not signed in.'**
  String get notSignedIn;

  /// No description provided for @registered.
  ///
  /// In en, this message translates to:
  /// **'You\'re registered! 🎉'**
  String get registered;

  /// No description provided for @viewTickets.
  ///
  /// In en, this message translates to:
  /// **'View my tickets'**
  String get viewTickets;

  /// No description provided for @showAtEntrance.
  ///
  /// In en, this message translates to:
  /// **'Show this QR code at the entrance'**
  String get showAtEntrance;

  /// No description provided for @offlineReady.
  ///
  /// In en, this message translates to:
  /// **'Available offline'**
  String get offlineReady;

  /// No description provided for @noTickets.
  ///
  /// In en, this message translates to:
  /// **'No tickets yet. Find an event to join!'**
  String get noTickets;

  /// No description provided for @past.
  ///
  /// In en, this message translates to:
  /// **'Past'**
  String get past;

  /// No description provided for @upcomingTickets.
  ///
  /// In en, this message translates to:
  /// **'Upcoming'**
  String get upcomingTickets;

  /// No description provided for @ticketCancelled.
  ///
  /// In en, this message translates to:
  /// **'This ticket is no longer valid'**
  String get ticketCancelled;

  /// No description provided for @share.
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get share;

  /// No description provided for @freeOnly.
  ///
  /// In en, this message translates to:
  /// **'Free only'**
  String get freeOnly;

  /// No description provided for @city.
  ///
  /// In en, this message translates to:
  /// **'City'**
  String get city;

  /// No description provided for @anyCity.
  ///
  /// In en, this message translates to:
  /// **'Any city'**
  String get anyCity;

  /// No description provided for @clearFilters.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get clearFilters;

  /// No description provided for @eventCancelled.
  ///
  /// In en, this message translates to:
  /// **'This event has been cancelled'**
  String get eventCancelled;

  /// No description provided for @eventEnded.
  ///
  /// In en, this message translates to:
  /// **'This event has ended'**
  String get eventEnded;

  /// No description provided for @chooseLanguage.
  ///
  /// In en, this message translates to:
  /// **'Choose your language'**
  String get chooseLanguage;

  /// No description provided for @continueLabel.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get continueLabel;

  /// No description provided for @addToCalendar.
  ///
  /// In en, this message translates to:
  /// **'Add to calendar'**
  String get addToCalendar;

  /// No description provided for @openInMaps.
  ///
  /// In en, this message translates to:
  /// **'Open in Maps'**
  String get openInMaps;

  /// No description provided for @schedule.
  ///
  /// In en, this message translates to:
  /// **'Schedule'**
  String get schedule;

  /// No description provided for @lineup.
  ///
  /// In en, this message translates to:
  /// **'Lineup'**
  String get lineup;

  /// No description provided for @gallery.
  ///
  /// In en, this message translates to:
  /// **'Photos'**
  String get gallery;

  /// No description provided for @practicalInfo.
  ///
  /// In en, this message translates to:
  /// **'Good to know'**
  String get practicalInfo;

  /// No description provided for @ageLimit.
  ///
  /// In en, this message translates to:
  /// **'Ages {n}+'**
  String ageLimit(int n);

  /// No description provided for @dressCode.
  ///
  /// In en, this message translates to:
  /// **'Dress code'**
  String get dressCode;

  /// No description provided for @languages.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get languages;

  /// No description provided for @parking.
  ///
  /// In en, this message translates to:
  /// **'Parking'**
  String get parking;

  /// No description provided for @accessibility.
  ///
  /// In en, this message translates to:
  /// **'Accessibility'**
  String get accessibility;

  /// No description provided for @whatToBring.
  ///
  /// In en, this message translates to:
  /// **'What to bring'**
  String get whatToBring;

  /// No description provided for @faq.
  ///
  /// In en, this message translates to:
  /// **'FAQ'**
  String get faq;

  /// No description provided for @terms.
  ///
  /// In en, this message translates to:
  /// **'Terms & conditions'**
  String get terms;

  /// No description provided for @refundPolicy.
  ///
  /// In en, this message translates to:
  /// **'Refund policy'**
  String get refundPolicy;

  /// No description provided for @directions.
  ///
  /// In en, this message translates to:
  /// **'Getting there'**
  String get directions;

  /// No description provided for @viewOrganizer.
  ///
  /// In en, this message translates to:
  /// **'View organizer'**
  String get viewOrganizer;

  /// No description provided for @organizerEvents.
  ///
  /// In en, this message translates to:
  /// **'Upcoming events'**
  String get organizerEvents;

  /// No description provided for @website.
  ///
  /// In en, this message translates to:
  /// **'Website'**
  String get website;

  /// No description provided for @facebook.
  ///
  /// In en, this message translates to:
  /// **'Facebook'**
  String get facebook;

  /// No description provided for @contact.
  ///
  /// In en, this message translates to:
  /// **'Contact'**
  String get contact;

  /// No description provided for @noUpcomingEvents.
  ///
  /// In en, this message translates to:
  /// **'No upcoming events right now.'**
  String get noUpcomingEvents;

  /// No description provided for @watch.
  ///
  /// In en, this message translates to:
  /// **'Watch'**
  String get watch;

  /// No description provided for @liveNow.
  ///
  /// In en, this message translates to:
  /// **'LIVE'**
  String get liveNow;

  /// No description provided for @watchLive.
  ///
  /// In en, this message translates to:
  /// **'Watch live'**
  String get watchLive;

  /// No description provided for @recordingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Recordings'**
  String get recordingsTitle;

  /// No description provided for @startsAtTime.
  ///
  /// In en, this message translates to:
  /// **'Starts {time}'**
  String startsAtTime(String time);

  /// No description provided for @availableUntil.
  ///
  /// In en, this message translates to:
  /// **'Available until {date}'**
  String availableUntil(String date);

  /// No description provided for @needTicketToWatch.
  ///
  /// In en, this message translates to:
  /// **'Register for this event to watch.'**
  String get needTicketToWatch;

  /// No description provided for @notLiveNow.
  ///
  /// In en, this message translates to:
  /// **'This stream is not live right now.'**
  String get notLiveNow;

  /// No description provided for @otherDevice.
  ///
  /// In en, this message translates to:
  /// **'You started watching on another device, so playback here stopped.'**
  String get otherDevice;

  /// No description provided for @videoError.
  ///
  /// In en, this message translates to:
  /// **'The video could not be played. Check your connection and try again.'**
  String get videoError;

  /// No description provided for @liveEnded.
  ///
  /// In en, this message translates to:
  /// **'The live stream has ended. A recording may be available soon.'**
  String get liveEnded;

  /// No description provided for @getTickets.
  ///
  /// In en, this message translates to:
  /// **'Get tickets'**
  String get getTickets;

  /// No description provided for @checkout.
  ///
  /// In en, this message translates to:
  /// **'Checkout'**
  String get checkout;

  /// No description provided for @total.
  ///
  /// In en, this message translates to:
  /// **'Total'**
  String get total;

  /// No description provided for @payWith.
  ///
  /// In en, this message translates to:
  /// **'Pay with'**
  String get payWith;

  /// No description provided for @payNow.
  ///
  /// In en, this message translates to:
  /// **'Pay {amount}'**
  String payNow(String amount);

  /// No description provided for @holdExpiresIn.
  ///
  /// In en, this message translates to:
  /// **'Tickets held for {time}'**
  String holdExpiresIn(String time);

  /// No description provided for @waitingForPayment.
  ///
  /// In en, this message translates to:
  /// **'Waiting for your payment…'**
  String get waitingForPayment;

  /// No description provided for @waitingHint.
  ///
  /// In en, this message translates to:
  /// **'Finish paying in your wallet app, then come back here. This page updates by itself.'**
  String get waitingHint;

  /// No description provided for @openWalletAgain.
  ///
  /// In en, this message translates to:
  /// **'Open payment page again'**
  String get openWalletAgain;

  /// No description provided for @scanToPay.
  ///
  /// In en, this message translates to:
  /// **'Scan this QR with your wallet app'**
  String get scanToPay;

  /// No description provided for @paymentReceived.
  ///
  /// In en, this message translates to:
  /// **'Payment received. Your tickets are ready.'**
  String get paymentReceived;

  /// No description provided for @holdExpired.
  ///
  /// In en, this message translates to:
  /// **'The hold expired before payment arrived. If you paid, you will be refunded or get your tickets shortly.'**
  String get holdExpired;

  /// No description provided for @startAgain.
  ///
  /// In en, this message translates to:
  /// **'Start again'**
  String get startAgain;

  /// No description provided for @cancelOrder.
  ///
  /// In en, this message translates to:
  /// **'Cancel order'**
  String get cancelOrder;

  /// No description provided for @orderCancelled.
  ///
  /// In en, this message translates to:
  /// **'Order cancelled.'**
  String get orderCancelled;

  /// No description provided for @paymentNotAvailable.
  ///
  /// In en, this message translates to:
  /// **'No payment method is available right now.'**
  String get paymentNotAvailable;

  /// No description provided for @continuePayment.
  ///
  /// In en, this message translates to:
  /// **'Continue payment'**
  String get continuePayment;

  /// No description provided for @pendingPayments.
  ///
  /// In en, this message translates to:
  /// **'Awaiting payment'**
  String get pendingPayments;

  /// No description provided for @ticketRefunded.
  ///
  /// In en, this message translates to:
  /// **'This ticket was refunded.'**
  String get ticketRefunded;

  /// No description provided for @choosePayment.
  ///
  /// In en, this message translates to:
  /// **'Choose how to pay'**
  String get choosePayment;

  /// No description provided for @orderSummary.
  ///
  /// In en, this message translates to:
  /// **'{qty} × {name}'**
  String orderSummary(String qty, String name);

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
  /// **'No notifications yet. Ticket updates, reminders and organizer announcements will appear here.'**
  String get noNotifications;

  /// No description provided for @promoCode.
  ///
  /// In en, this message translates to:
  /// **'Promo code'**
  String get promoCode;

  /// No description provided for @apply.
  ///
  /// In en, this message translates to:
  /// **'Apply'**
  String get apply;

  /// No description provided for @addPromoCode.
  ///
  /// In en, this message translates to:
  /// **'Add promo code'**
  String get addPromoCode;

  /// No description provided for @removePromo.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get removePromo;

  /// No description provided for @promoInvalid.
  ///
  /// In en, this message translates to:
  /// **'This code is not valid'**
  String get promoInvalid;

  /// No description provided for @promoUsedUp.
  ///
  /// In en, this message translates to:
  /// **'This code has been used up'**
  String get promoUsedUp;

  /// No description provided for @promoExpired.
  ///
  /// In en, this message translates to:
  /// **'This code has expired'**
  String get promoExpired;

  /// No description provided for @promoNotStarted.
  ///
  /// In en, this message translates to:
  /// **'This code is not active yet'**
  String get promoNotStarted;

  /// No description provided for @promoNotApplicable.
  ///
  /// In en, this message translates to:
  /// **'This code does not apply to these tickets'**
  String get promoNotApplicable;

  /// No description provided for @priceRisesTo.
  ///
  /// In en, this message translates to:
  /// **'Price rises to {price} on {date}'**
  String priceRisesTo(String price, String date);

  /// No description provided for @groupDiscountLine.
  ///
  /// In en, this message translates to:
  /// **'Group discount −{amount}'**
  String groupDiscountLine(String amount);

  /// No description provided for @groupDiscountHint.
  ///
  /// In en, this message translates to:
  /// **'Buy {n}+ tickets to save {percent}%'**
  String groupDiscountHint(int n, String percent);

  /// No description provided for @promoLostToGroup.
  ///
  /// In en, this message translates to:
  /// **'Your code isn\'t applied — the group discount is bigger'**
  String get promoLostToGroup;

  /// No description provided for @promoApplied.
  ///
  /// In en, this message translates to:
  /// **'Code applied: {amount} off'**
  String promoApplied(String amount);

  /// No description provided for @discount.
  ///
  /// In en, this message translates to:
  /// **'Discount'**
  String get discount;

  /// No description provided for @transferTicket.
  ///
  /// In en, this message translates to:
  /// **'Send to someone'**
  String get transferTicket;

  /// No description provided for @transferHint.
  ///
  /// In en, this message translates to:
  /// **'Enter the Myanmar phone number of the person who will use this ticket. Your QR stops working and they will find the ticket in the app after signing in with that number.'**
  String get transferHint;

  /// No description provided for @send.
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get send;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @transferDone.
  ///
  /// In en, this message translates to:
  /// **'Ticket sent to {phone}'**
  String transferDone(String phone);

  /// No description provided for @chooseSeats.
  ///
  /// In en, this message translates to:
  /// **'Choose seats'**
  String get chooseSeats;

  /// No description provided for @seatPickerTitle.
  ///
  /// In en, this message translates to:
  /// **'Choose your seats'**
  String get seatPickerTitle;

  /// No description provided for @standingTickets.
  ///
  /// In en, this message translates to:
  /// **'Standing tickets'**
  String get standingTickets;

  /// No description provided for @tapSeatHint.
  ///
  /// In en, this message translates to:
  /// **'Tap a seat to select it'**
  String get tapSeatHint;

  /// No description provided for @zoomToPick.
  ///
  /// In en, this message translates to:
  /// **'Zoom in to pick seats, or tap a section'**
  String get zoomToPick;

  /// No description provided for @bestAvailable.
  ///
  /// In en, this message translates to:
  /// **'Best available'**
  String get bestAvailable;

  /// No description provided for @bestAvailableHint.
  ///
  /// In en, this message translates to:
  /// **'We\'ll pick the best seats together that are still free.'**
  String get bestAvailableHint;

  /// No description provided for @findSeats.
  ///
  /// In en, this message translates to:
  /// **'Find seats'**
  String get findSeats;

  /// No description provided for @ticketTypeLabel.
  ///
  /// In en, this message translates to:
  /// **'Ticket type'**
  String get ticketTypeLabel;

  /// No description provided for @seatLimit.
  ///
  /// In en, this message translates to:
  /// **'You can choose up to {n} seats'**
  String seatLimit(int n);

  /// No description provided for @seatsJustTaken.
  ///
  /// In en, this message translates to:
  /// **'Just taken: {seats}. They were removed from your choice. Pick others to continue.'**
  String seatsJustTaken(String seats);

  /// No description provided for @seatNotAvailable.
  ///
  /// In en, this message translates to:
  /// **'That seat isn\'t available'**
  String get seatNotAvailable;

  /// No description provided for @seatsChosen.
  ///
  /// In en, this message translates to:
  /// **'{n} seats'**
  String seatsChosen(int n);

  /// No description provided for @legendYours.
  ///
  /// In en, this message translates to:
  /// **'Yours'**
  String get legendYours;

  /// No description provided for @legendTaken.
  ///
  /// In en, this message translates to:
  /// **'Taken'**
  String get legendTaken;

  /// No description provided for @legendWheelchair.
  ///
  /// In en, this message translates to:
  /// **'Wheelchair space'**
  String get legendWheelchair;

  /// No description provided for @legendRestricted.
  ///
  /// In en, this message translates to:
  /// **'Restricted view'**
  String get legendRestricted;

  /// No description provided for @complimentary.
  ///
  /// In en, this message translates to:
  /// **'Complimentary'**
  String get complimentary;

  /// No description provided for @complimentaryLabel.
  ///
  /// In en, this message translates to:
  /// **'Complimentary · {label}'**
  String complimentaryLabel(String label);

  /// No description provided for @cancelTicket.
  ///
  /// In en, this message translates to:
  /// **'Cancel ticket'**
  String get cancelTicket;

  /// No description provided for @cancelTicketTitle.
  ///
  /// In en, this message translates to:
  /// **'Cancel this ticket?'**
  String get cancelTicketTitle;

  /// No description provided for @cancelTicketBody.
  ///
  /// In en, this message translates to:
  /// **'Your seat goes back on sale. This can\'t be undone.'**
  String get cancelTicketBody;

  /// No description provided for @keepTicket.
  ///
  /// In en, this message translates to:
  /// **'Keep ticket'**
  String get keepTicket;

  /// No description provided for @ticketCancelledDone.
  ///
  /// In en, this message translates to:
  /// **'Ticket cancelled'**
  String get ticketCancelledDone;
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

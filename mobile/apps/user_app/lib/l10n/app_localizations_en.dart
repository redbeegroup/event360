// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class L10nEn extends L10n {
  L10nEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Event 360';

  @override
  String get home => 'Home';

  @override
  String get explore => 'Explore';

  @override
  String get myTickets => 'My tickets';

  @override
  String get profile => 'Profile';

  @override
  String get searchHint => 'Search events';

  @override
  String get allCategories => 'All';

  @override
  String get upcoming => 'Upcoming events';

  @override
  String get freeEvents => 'Free events';

  @override
  String get seeAll => 'See all';

  @override
  String get noEvents => 'No events found.';

  @override
  String get loadError => 'Couldn\'t load. Check your connection.';

  @override
  String get retry => 'Retry';

  @override
  String get free => 'Free';

  @override
  String get soldOut => 'Sold out';

  @override
  String fromPrice(String price) {
    return 'From $price';
  }

  @override
  String mmk(String amount) {
    return '$amount MMK';
  }

  @override
  String get register => 'Register';

  @override
  String get registerFree => 'Register for free';

  @override
  String get quantity => 'Tickets';

  @override
  String perPersonLimit(int n) {
    return 'Up to $n per person';
  }

  @override
  String remaining(int n) {
    return '$n left';
  }

  @override
  String get tickets => 'Tickets';

  @override
  String get about => 'About';

  @override
  String get organizer => 'Organizer';

  @override
  String get verified => 'Verified organizer';

  @override
  String get venue => 'Venue';

  @override
  String get formatOnline => 'Online';

  @override
  String get formatInPerson => 'In person';

  @override
  String get formatHybrid => 'In person + online';

  @override
  String get paidSoon => 'Paid tickets will be available soon.';

  @override
  String get signIn => 'Sign in';

  @override
  String get signInToRegister => 'Sign in with your phone number to register.';

  @override
  String get phoneNumber => 'Phone number';

  @override
  String get phoneHint => '09xxxxxxxxx';

  @override
  String get sendCode => 'Send code';

  @override
  String codeSentTo(String phone) {
    return 'Enter the 6-digit code sent to $phone';
  }

  @override
  String get code => 'Code';

  @override
  String get verify => 'Verify';

  @override
  String get changeNumber => 'Change number';

  @override
  String devCode(String code) {
    return 'Test environment code: $code';
  }

  @override
  String get invalidPhone => 'Enter a valid Myanmar mobile number (09…)';

  @override
  String get invalidCode => 'Enter the 6-digit code';

  @override
  String get tooManyCodes =>
      'Too many codes requested. Please wait a few minutes.';

  @override
  String get signOut => 'Sign out';

  @override
  String get language => 'Language';

  @override
  String signedInAs(String phone) {
    return 'Signed in as $phone';
  }

  @override
  String get notSignedIn => 'You are not signed in.';

  @override
  String get registered => 'You\'re registered! 🎉';

  @override
  String get viewTickets => 'View my tickets';

  @override
  String get showAtEntrance => 'Show this QR code at the entrance';

  @override
  String get offlineReady => 'Available offline';

  @override
  String get noTickets => 'No tickets yet. Find an event to join!';

  @override
  String get past => 'Past';

  @override
  String get upcomingTickets => 'Upcoming';

  @override
  String get ticketCancelled => 'This ticket is no longer valid';

  @override
  String get share => 'Share';

  @override
  String get freeOnly => 'Free only';

  @override
  String get city => 'City';

  @override
  String get anyCity => 'Any city';

  @override
  String get clearFilters => 'Clear';

  @override
  String get eventCancelled => 'This event has been cancelled';

  @override
  String get eventEnded => 'This event has ended';

  @override
  String get chooseLanguage => 'Choose your language';

  @override
  String get continueLabel => 'Continue';
}

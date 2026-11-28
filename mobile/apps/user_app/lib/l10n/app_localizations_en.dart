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
  String get tabDiscover => 'Discover';

  @override
  String get tabTickets => 'Tickets';

  @override
  String get tabAccount => 'Account';

  @override
  String get findThingsToDo => 'Find things to do';

  @override
  String inCity(String city) {
    return 'in $city';
  }

  @override
  String get inMyanmar => 'in Myanmar';

  @override
  String get popular => 'Popular';

  @override
  String get filters => 'Filters';

  @override
  String get reservedSeating => 'Reserved seating';

  @override
  String get switchLanguage => 'Switch language';

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
  String get freeTicketsAvailable => 'Free tickets available';

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

  @override
  String get addToCalendar => 'Add to calendar';

  @override
  String get openInMaps => 'Open in Maps';

  @override
  String get schedule => 'Schedule';

  @override
  String get lineup => 'Lineup';

  @override
  String get gallery => 'Photos';

  @override
  String get practicalInfo => 'Practical info';

  @override
  String ageLimit(int n) {
    return 'Ages $n+';
  }

  @override
  String get dressCode => 'Dress code';

  @override
  String get languages => 'Language';

  @override
  String get parking => 'Parking';

  @override
  String get accessibility => 'Accessibility';

  @override
  String get whatToBring => 'What to bring';

  @override
  String get faq => 'FAQ';

  @override
  String get terms => 'Terms & conditions';

  @override
  String get refundPolicy => 'Refund policy';

  @override
  String get directions => 'Getting there';

  @override
  String get viewOrganizer => 'View organizer';

  @override
  String get organizerEvents => 'Upcoming events';

  @override
  String get website => 'Website';

  @override
  String get facebook => 'Facebook';

  @override
  String get contact => 'Contact';

  @override
  String get noUpcomingEvents => 'No upcoming events right now.';

  @override
  String get watch => 'Watch';

  @override
  String get liveNow => 'LIVE';

  @override
  String get watchLive => 'Watch live';

  @override
  String get recordingsTitle => 'Recordings';

  @override
  String startsAtTime(String time) {
    return 'Starts $time';
  }

  @override
  String availableUntil(String date) {
    return 'Available until $date';
  }

  @override
  String get needTicketToWatch => 'Register for this event to watch.';

  @override
  String get notLiveNow => 'This stream is not live right now.';

  @override
  String get otherDevice =>
      'You started watching on another device, so playback here stopped.';

  @override
  String get videoError =>
      'The video could not be played. Check your connection and try again.';

  @override
  String get liveEnded =>
      'The live stream has ended. A recording may be available soon.';

  @override
  String get getTickets => 'Get tickets';

  @override
  String get checkout => 'Checkout';

  @override
  String get total => 'Total';

  @override
  String get payWith => 'Pay with';

  @override
  String payNow(String amount) {
    return 'Pay $amount';
  }

  @override
  String holdExpiresIn(String time) {
    return 'Tickets held for $time';
  }

  @override
  String get waitingForPayment => 'Waiting for your payment…';

  @override
  String get waitingHint =>
      'Finish paying in your wallet app, then come back here. This page updates by itself.';

  @override
  String get openWalletAgain => 'Open payment page again';

  @override
  String get scanToPay => 'Scan this QR with your wallet app';

  @override
  String get paymentReceived => 'Payment received. Your tickets are ready.';

  @override
  String get holdExpired =>
      'The hold expired before payment arrived. If you paid, you will be refunded or get your tickets shortly.';

  @override
  String get startAgain => 'Start again';

  @override
  String get cancelOrder => 'Cancel order';

  @override
  String get orderCancelled => 'Order cancelled.';

  @override
  String get paymentNotAvailable => 'No payment method is available right now.';

  @override
  String get continuePayment => 'Continue payment';

  @override
  String get pendingPayments => 'Awaiting payment';

  @override
  String get ticketRefunded => 'This ticket was refunded.';

  @override
  String get choosePayment => 'Choose how to pay';

  @override
  String orderSummary(String qty, String name) {
    return '$qty × $name';
  }

  @override
  String get notifications => 'Notifications';

  @override
  String get markAllRead => 'Mark all read';

  @override
  String get noNotifications =>
      'No notifications yet. Ticket updates, reminders and organizer announcements will appear here.';

  @override
  String get promoCode => 'Promo code';

  @override
  String get apply => 'Apply';

  @override
  String get addPromoCode => 'Add promo code';

  @override
  String get removePromo => 'Remove';

  @override
  String get promoInvalid => 'This code is not valid';

  @override
  String get promoUsedUp => 'This code has been used up';

  @override
  String get promoExpired => 'This code has expired';

  @override
  String get promoNotStarted => 'This code is not active yet';

  @override
  String get promoNotApplicable => 'This code does not apply to these tickets';

  @override
  String priceRisesTo(String price, String date) {
    return 'Price rises to $price on $date';
  }

  @override
  String groupDiscountLine(String amount) {
    return 'Group discount −$amount';
  }

  @override
  String groupDiscountHint(int n, String percent) {
    return 'Buy $n+ tickets to save $percent%';
  }

  @override
  String get promoLostToGroup =>
      'Your code isn\'t applied — the group discount is bigger';

  @override
  String get promoChecking => 'Checking your code…';

  @override
  String promoApplied(String amount) {
    return 'Code applied: $amount off';
  }

  @override
  String get discount => 'Discount';

  @override
  String get transferTicket => 'Send to someone';

  @override
  String get transferHint =>
      'Enter the Myanmar phone number of the person who will use this ticket. Your QR stops working and they will find the ticket in the app after signing in with that number.';

  @override
  String get send => 'Send';

  @override
  String get cancel => 'Cancel';

  @override
  String get eventGuide => 'Event guide';

  @override
  String get happeningToday => 'Happening today';

  @override
  String get openGuide => 'Open your guide';

  @override
  String get checkedIn => 'Checked in';

  @override
  String checkedInAt(String time) {
    return 'Checked in at $time';
  }

  @override
  String get ticketUsed => 'This ticket has been used to enter';

  @override
  String get ticketStatusCancelled => 'Cancelled';

  @override
  String get ticketStatusRefunded => 'Refunded';

  @override
  String transferDone(String phone) {
    return 'Ticket sent to $phone';
  }

  @override
  String get chooseSeats => 'Choose seats';

  @override
  String get seatPickerTitle => 'Choose your seats';

  @override
  String get standingTickets => 'Standing tickets';

  @override
  String get chooseTicketKind => 'Choose ticket type';

  @override
  String get tapSeatHint => 'Tap a seat to select it';

  @override
  String get zoomToPick => 'Zoom in to pick seats, or tap a section';

  @override
  String get bestAvailable => 'Best available';

  @override
  String get bestAvailableHint =>
      'We\'ll pick the best seats together that are still free.';

  @override
  String get findSeats => 'Find seats';

  @override
  String get ticketTypeLabel => 'Ticket type';

  @override
  String seatLimit(int n) {
    return 'You can choose up to $n seats';
  }

  @override
  String seatsJustTaken(String seats) {
    return 'Just taken: $seats. They were removed from your choice. Pick others to continue.';
  }

  @override
  String get seatNotAvailable => 'That seat isn\'t available';

  @override
  String seatsChosen(int n) {
    return '$n seats';
  }

  @override
  String get legendYours => 'Yours';

  @override
  String get legendTaken => 'Taken';

  @override
  String get legendWheelchair => 'Wheelchair space';

  @override
  String get legendRestricted => 'Restricted view';

  @override
  String get complimentary => 'Complimentary';

  @override
  String complimentaryLabel(String label) {
    return 'Complimentary · $label';
  }

  @override
  String get cancelTicket => 'Cancel ticket';

  @override
  String get cancelTicketTitle => 'Cancel this ticket?';

  @override
  String get cancelTicketBody =>
      'Your seat goes back on sale. This can\'t be undone.';

  @override
  String get keepTicket => 'Keep ticket';

  @override
  String get ticketCancelledDone => 'Ticket cancelled';

  @override
  String get joinWaitlist => 'Join waitlist';

  @override
  String get waitlistSheetTitle => 'Join the waitlist';

  @override
  String get waitlistHint =>
      'If tickets come back we\'ll tell you, and you\'ll have 30 minutes to buy them.';

  @override
  String get waitlistJoinAction => 'Join the line';

  @override
  String waitlistPosition(int n) {
    return 'You\'re #$n in line';
  }

  @override
  String get leaveWaitlist => 'Leave';

  @override
  String get waitlistLeft => 'You left the waitlist';

  @override
  String get waitlistOfferedInline => 'Tickets are reserved for you';

  @override
  String get buyNow => 'Buy now';

  @override
  String offerBanner(String time) {
    return 'Tickets are waiting for you — $time left';
  }

  @override
  String get offerSheetTitle => 'Your reserved tickets';

  @override
  String offerSheetHint(int n, String time) {
    return 'You can buy up to $n now · $time left';
  }

  @override
  String get offerEnded => 'This offer has ended';

  @override
  String get reservedForYou => 'Reserved for you';

  @override
  String reservedForYouLeft(String time) {
    return 'Reserved for you · $time left';
  }

  @override
  String get waitlistClosed => 'The waitlist is closed';

  @override
  String get waitlistPaused =>
      'The waitlist is paused while the event is being reviewed';

  @override
  String get waitlistAlreadyIn => 'You are already on this waitlist';

  @override
  String get waitlistNotSoldOut =>
      'These tickets are not sold out: you can buy them now';

  @override
  String get waitlistLimit =>
      'You have reached the per-person ticket limit for this type';

  @override
  String get offerClosed => 'This offer is no longer open';

  @override
  String get waitlistNotIn => 'You are not on this waitlist';

  @override
  String get waitlistGenericError => 'Something went wrong. Please try again.';

  @override
  String get waitlistCheckoutPending =>
      'Finish or cancel the checkout from your waitlist offer first';

  @override
  String get offerTotalEstimate => 'Estimated total';

  @override
  String get overview => 'Overview';

  @override
  String get goodToKnow => 'Good to know';

  @override
  String get readMore => 'Read more';

  @override
  String get continueToPayment => 'Continue to payment';

  @override
  String byOrganizer(String name) {
    return 'By $name';
  }

  @override
  String get priceRiseSoon => 'Price rises soon';

  @override
  String priceRiseCard(String type, String price, String date) {
    return '$type goes to $price on $date';
  }

  @override
  String get groupDiscountTitle => 'Group discount';

  @override
  String groupTierLine(int n, String percent) {
    return '$n+ tickets: $percent% off';
  }

  @override
  String ticketsTotal(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n tickets',
      one: '1 ticket',
    );
    return '$_temp0 · Total';
  }

  @override
  String fewerTickets(String type) {
    return 'One fewer $type ticket';
  }

  @override
  String moreTickets(String type) {
    return 'One more $type ticket';
  }

  @override
  String get ticketDate => 'Date';

  @override
  String get ticketTime => 'Time';

  @override
  String get ticketSeatLabel => 'Seat';

  @override
  String get ticketKind => 'Ticket';

  @override
  String get getDirections => 'Directions';

  @override
  String get openFailed => 'Couldn\'t open that. Try again.';

  @override
  String guideStartsInDays(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count days',
      one: '1 day',
    );
    return 'Starts in $_temp0';
  }

  @override
  String guideStartsInHours(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count hours',
      one: '1 hour',
    );
    return 'Starts in $_temp0';
  }

  @override
  String guideStartsInMinutes(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count minutes',
      one: '1 minute',
    );
    return 'Starts in $_temp0';
  }

  @override
  String get guideOnNow => 'On now';

  @override
  String get guideEnded => 'Ended';

  @override
  String get guideCancelled => 'This event was cancelled';

  @override
  String get yourTickets => 'Your tickets';

  @override
  String get showTicket => 'Show ticket';

  @override
  String get nowTitle => 'Now';

  @override
  String get nextTitle => 'Next';

  @override
  String get fullSchedule => 'Full schedule';

  @override
  String get announcements => 'Announcements';

  @override
  String get guideThanks => 'Thank you for coming';

  @override
  String savedCopy(String time) {
    return 'Saved copy · updated $time. Newer announcements may exist.';
  }

  @override
  String get neverSaved => 'Connect once to save this event for offline use.';

  @override
  String get needsConnection => 'Needs a connection';

  @override
  String get guideGone => 'This event is no longer available';

  @override
  String get guideStreamNotStarted => 'Stream not started yet';

  @override
  String get searchThisEvent => 'Search this event';

  @override
  String get searchEventHint => 'Sessions, line-up, questions';

  @override
  String searchNoResults(String query) {
    return 'Nothing found for “$query”';
  }
}

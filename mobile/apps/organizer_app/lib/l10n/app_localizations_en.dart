// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class L10nEn extends L10n {
  L10nEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Event 360 Organizer';

  @override
  String get signInTitle => 'Sign in with your organizer account';

  @override
  String get email => 'Email';

  @override
  String get password => 'Password';

  @override
  String get signIn => 'Sign in';

  @override
  String get signOut => 'Sign out';

  @override
  String get notOrganizer =>
      'This account is not part of any organization. Ask your organization owner to invite you in the portal.';

  @override
  String get events => 'Events';

  @override
  String get upcoming => 'Upcoming';

  @override
  String get past => 'Past';

  @override
  String get noEvents => 'No events yet. Create events in the portal.';

  @override
  String get liveNow => 'Live now';

  @override
  String get loadError => 'Couldn\'t load. Check your connection.';

  @override
  String get retry => 'Retry';

  @override
  String get organization => 'Organization';

  @override
  String get status_DRAFT => 'Draft';

  @override
  String get status_SUBMITTED => 'In review';

  @override
  String get status_PUBLISHED => 'Published';

  @override
  String get status_ONGOING => 'Ongoing';

  @override
  String get status_COMPLETED => 'Completed';

  @override
  String get status_CANCELLED => 'Cancelled';

  @override
  String get status_REJECTED => 'Rejected';

  @override
  String get orderStatus_PENDING_PAYMENT => 'Awaiting payment';

  @override
  String get orderStatus_PAID => 'Paid';

  @override
  String get orderStatus_CONFIRMED => 'Confirmed';

  @override
  String get orderStatus_EXPIRED => 'Expired';

  @override
  String get orderStatus_CANCELLED => 'Cancelled';

  @override
  String get orderStatus_REFUNDED => 'Refunded';

  @override
  String get orderStatus_FAILED => 'Failed';

  @override
  String get tabOverview => 'Overview';

  @override
  String get tabDoor => 'Door';

  @override
  String get tabAnnounce => 'Announce';

  @override
  String get tabPromos => 'Promos';

  @override
  String get ticketsSold => 'Tickets sold';

  @override
  String get revenue => 'Revenue';

  @override
  String get checkedIn => 'Checked in';

  @override
  String get orders => 'Orders';

  @override
  String get pageViews => 'Page views';

  @override
  String get discounts => 'Discounts';

  @override
  String get byTicketType => 'By ticket type';

  @override
  String get seatsTitle => 'Seats';

  @override
  String get seatsAvailable => 'Available';

  @override
  String get seatsHeld => 'Held at checkout';

  @override
  String get seatsGuest => 'Held for guests';

  @override
  String get seatsSold => 'Sold';

  @override
  String get seatsComp => 'Complimentary';

  @override
  String get byGate => 'Check-ins by gate';

  @override
  String get recentOrders => 'Recent orders';

  @override
  String get noOrders => 'No orders yet.';

  @override
  String updatedAt(String time) {
    return 'Updated $time';
  }

  @override
  String get noGate => 'No gate';

  @override
  String get doorHint =>
      'Create a code for each group of volunteers. They open the Crew app, scan the QR (or type the code) and start checking tickets in.';

  @override
  String get codeLabel => 'Name (e.g. Volunteers)';

  @override
  String get gate => 'Gate (optional)';

  @override
  String get createCode => 'Create code';

  @override
  String get codeCreated => 'Show this to your volunteers';

  @override
  String get codeOnce =>
      'The code is shown only now. Create a new one if it gets lost.';

  @override
  String get revoke => 'Revoke';

  @override
  String get revokeConfirm =>
      'Revoke this code? Phones using it are signed out.';

  @override
  String devices(int n) {
    return '$n phones';
  }

  @override
  String get expired => 'Expired';

  @override
  String get revoked => 'Revoked';

  @override
  String get openCrewApp => 'Open the Crew app';

  @override
  String get done => 'Done';

  @override
  String get announceHint =>
      'Sends a notification to everyone holding a ticket (not SMS). Up to 3 per day.';

  @override
  String recipients(int n) {
    return '$n ticket holders';
  }

  @override
  String leftToday(int n) {
    return '$n left today';
  }

  @override
  String get heading => 'Heading';

  @override
  String get message => 'Message';

  @override
  String get headingMy => 'Heading (Myanmar, optional)';

  @override
  String get messageMy => 'Message (Myanmar, optional)';

  @override
  String get send => 'Send';

  @override
  String get sendConfirm => 'Send this to all ticket holders now?';

  @override
  String get sent => 'Sent';

  @override
  String get cancel => 'Cancel';

  @override
  String get noAnnouncements => 'Nothing sent yet.';

  @override
  String get promosHint =>
      'Discounts for paid tickets. Commission is calculated on the discounted price.';

  @override
  String get promoCode => 'Code';

  @override
  String get percent => '% off';

  @override
  String get fixed => 'MMK off';

  @override
  String get amount => 'Amount';

  @override
  String get maxUses => 'Max uses (optional)';

  @override
  String get createPromo => 'Create code';

  @override
  String used(String n) {
    return 'Used $n';
  }

  @override
  String get turnOn => 'Turn on';

  @override
  String get turnOff => 'Turn off';

  @override
  String get off => 'Off';

  @override
  String get noPromos => 'No codes yet.';

  @override
  String get notifications => 'Notifications';

  @override
  String get markAllRead => 'Mark all read';

  @override
  String get noNotifications =>
      'Sales milestones, approvals and the daily summary will appear here.';

  @override
  String get readOnly => 'View only: your role can\'t change this.';

  @override
  String get tabGuests => 'Guests';

  @override
  String guestsCount(int inCount, int total) {
    return '$inCount of $total checked in';
  }

  @override
  String get guestsSearch => 'Search name, phone or seat';

  @override
  String get guestsNotIn => 'Not checked in';

  @override
  String get statusIn => 'Checked in';

  @override
  String get statusNotIn => 'Not in';

  @override
  String get statusCancelled => 'Cancelled';

  @override
  String get guestBadge => 'Guest';

  @override
  String get guestsEmpty => 'No tickets yet';

  @override
  String get guestsNoMatch => 'No one matches';

  @override
  String get checkIn => 'Check in';

  @override
  String get undoCheckIn => 'Undo check-in';

  @override
  String undoCheckInConfirm(String name) {
    return 'Undo the check-in for $name?';
  }

  @override
  String checkedInOk(String name) {
    return '$name is checked in';
  }

  @override
  String alreadyCheckedIn(String time) {
    return 'Already checked in at $time';
  }

  @override
  String alreadyCheckedInGate(String time, String gate) {
    return 'Already checked in at $time, $gate';
  }

  @override
  String checkInRefused(String status) {
    return 'Can\'t check in: this ticket is $status';
  }

  @override
  String get checkInNoConnection =>
      'Not checked in — no connection. Try again.';

  @override
  String get checkInClosed => 'Check-in opens one day before the event';

  @override
  String get call => 'Call';

  @override
  String registeredOn(String date) {
    return 'Registered $date';
  }
}

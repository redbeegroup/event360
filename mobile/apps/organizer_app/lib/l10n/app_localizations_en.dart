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
  String get seatsComp => 'Guest tickets';

  @override
  String get seatsOffered => 'Waitlist offers';

  @override
  String get waitlistTitle => 'Waitlist';

  @override
  String waitlistLine(String waiting, String offered) {
    return '$waiting waiting · $offered with an offer';
  }

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
  String get checkInEnded => 'Check-in has closed';

  @override
  String get call => 'Call';

  @override
  String registeredOn(String date) {
    return 'Registered $date';
  }

  @override
  String get checkInRefusedGeneric => 'Can\'t check in this ticket';

  @override
  String get tabSeats => 'Seats';

  @override
  String seatsSelected(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count seats selected',
      one: '1 seat selected',
    );
    return '$_temp0';
  }

  @override
  String get clear => 'Clear';

  @override
  String get holdForGuests => 'Hold for guests';

  @override
  String get holdLabelField => 'Label (e.g. Sponsor)';

  @override
  String get releaseSeats => 'Release';

  @override
  String releaseConfirm(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Put $count seats back on sale?',
      one: 'Put 1 seat back on sale?',
    );
    return '$_temp0';
  }

  @override
  String get issueGuestTickets => 'Issue guest tickets';

  @override
  String get guestNameField => 'Guest name';

  @override
  String get guestPhoneField => 'Guest phone';

  @override
  String get guestLabelField => 'Label (optional)';

  @override
  String get issueHelp =>
      'The guest finds the tickets in the Event 360 app after signing in with this number. No SMS is sent.';

  @override
  String issueConfirmText(int count, String phone) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Issue $count guest tickets to $phone?',
      one: 'Issue 1 guest ticket to $phone?',
    );
    return '$_temp0';
  }

  @override
  String get seatsMixedHint => 'Select only free seats or only held seats';

  @override
  String get seatsNoTypeHint => 'Some held seats have no ticket type';

  @override
  String get seatsTooMany => 'Select 200 seats or fewer';

  @override
  String get seatsChanged =>
      'Some of those seats changed. The map has been updated.';

  @override
  String heldLabel(String label) {
    return 'Held: $label';
  }

  @override
  String get legendAvailable => 'On sale';

  @override
  String get legendHeld => 'Held for guests';

  @override
  String get legendSold => 'Sold';

  @override
  String get legendGuest => 'Guest tickets';

  @override
  String get guestList => 'Guest tickets';

  @override
  String revokeGuestConfirm(String name, String seat) {
    return 'Revoke the guest ticket for $name, $seat?';
  }

  @override
  String get guestRevoked => 'Revoked';

  @override
  String get phoneInvalid => 'Enter a Myanmar mobile number';

  @override
  String get viewOnlySeats => 'You can view seats but not change them';

  @override
  String get seatsZoomHint => 'Zoom in to select seats';

  @override
  String get fieldRequired => 'Required';

  @override
  String get noGuestTickets => 'No guest tickets yet';

  @override
  String get seatsViewMap => 'Map';

  @override
  String seatsViewGuests(int count) {
    return 'Guest tickets ($count)';
  }

  @override
  String get legendSelected => 'Selected';

  @override
  String ticketsIssued(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count guest tickets issued',
      one: '1 guest ticket issued',
    );
    return '$_temp0';
  }

  @override
  String get tabSales => 'Sales';

  @override
  String get paidOrders => 'Paid orders';

  @override
  String get grossSales => 'Gross sales';

  @override
  String get grossCaption => 'Paid orders only, after discounts';

  @override
  String get commission => 'Commission';

  @override
  String get netToYou => 'Net to you';

  @override
  String refundedLine(String count, String amount) {
    return '$count · $amount';
  }

  @override
  String get refunded => 'Refunded';

  @override
  String get noPaidTickets => 'This event has no paid tickets';

  @override
  String nextPriceLine(String amount, String date) {
    return 'Next price $amount on $date';
  }

  @override
  String soldOf(String sold, String quota) {
    return '$sold of $quota sold';
  }

  @override
  String get allOrders => 'All orders';

  @override
  String get orderSearchHint =>
      'Search name, full phone number or order number';

  @override
  String get filterAll => 'All';

  @override
  String get filterPaid => 'Paid';

  @override
  String get filterRefunded => 'Refunded';

  @override
  String get filterPending => 'Waiting for payment';

  @override
  String get filterIncomplete => 'Not completed';

  @override
  String orderNumber(String number) {
    return 'Order $number';
  }

  @override
  String get walkUp => 'Walk-up';

  @override
  String get beingReviewed => 'Being reviewed';

  @override
  String get reviewNote =>
      'Event 360 is reviewing this payment. If money needs to go back to the buyer, we will refund it.';

  @override
  String holdUntil(String time) {
    return 'Hold ends $time';
  }

  @override
  String get ordersEmpty => 'No orders yet';

  @override
  String get ordersNoMatch => 'No orders match';

  @override
  String get loadMoreFailed => 'Couldn\'t load more. Tap to retry.';

  @override
  String orderCreated(String time) {
    return 'Ordered $time';
  }

  @override
  String orderPaid(String time) {
    return 'Paid $time';
  }

  @override
  String get subtotal => 'Subtotal';

  @override
  String get discount => 'Discount';

  @override
  String discountPromo(String code) {
    return 'Discount ($code)';
  }

  @override
  String get discountGroup => 'Group discount';

  @override
  String get total => 'Total';

  @override
  String get payments => 'Payments';

  @override
  String get refunds => 'Refunds';

  @override
  String get refundInProgress => 'Refund in progress';

  @override
  String get refundByHand => 'Event 360 is returning it by hand';

  @override
  String get refundDone => 'Refunded';

  @override
  String get wholeOrderRefund => 'Refunds are always for the whole order.';

  @override
  String ticketsCheckedIn(String inCount, String total) {
    return '$inCount of $total tickets checked in';
  }

  @override
  String seatsLine(String seats) {
    return 'Seats: $seats';
  }

  @override
  String get salesViewSummary => 'Summary';

  @override
  String get salesViewOrders => 'Orders';

  @override
  String get refreshFailed => 'Couldn\'t refresh. Showing earlier data.';

  @override
  String holdEnded(String time) {
    return 'Hold ended $time';
  }

  @override
  String get paymentCash => 'Cash';

  @override
  String get paymentCard => 'Card';

  @override
  String get payouts => 'Payouts';

  @override
  String get earned => 'Earned';

  @override
  String get paidOut => 'Paid out';

  @override
  String get owedToYou => 'Owed to you';

  @override
  String youOwe(String amount) {
    return 'You owe Event 360 $amount';
  }

  @override
  String get reconcileNote =>
      'This is a sales breakdown; totals come from the ledger.';

  @override
  String get byEvent => 'By event';

  @override
  String get salesBeforeRefunds => 'Sales before refunds';

  @override
  String get payoutHistory => 'Payout history';

  @override
  String get noPayouts => 'No payouts yet.';

  @override
  String get voided => 'Voided';

  @override
  String get methodBANK => 'Bank transfer';

  @override
  String get methodOTHER => 'Other';

  @override
  String get reference => 'Reference';

  @override
  String get noSalesYet => 'No sales yet';

  @override
  String get revenueCaption => 'Ticket revenue is before discounts';

  @override
  String get refundedAmount => 'Refunded';

  @override
  String get discountsIncluded => 'Discounts given (already taken off sales)';

  @override
  String get balance => 'Balance';

  @override
  String ticketCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count tickets',
      one: '1 ticket',
    );
    return '$_temp0';
  }
}

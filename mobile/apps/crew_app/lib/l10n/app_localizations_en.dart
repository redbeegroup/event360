// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class L10nEn extends L10n {
  L10nEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Event 360 Crew';

  @override
  String get signInTitle => 'Door check-in';

  @override
  String get tabAccount => 'Crew account';

  @override
  String get tabCode => 'Event code';

  @override
  String get email => 'Email';

  @override
  String get password => 'Password';

  @override
  String get signIn => 'Sign in';

  @override
  String get eventCode => 'Event code';

  @override
  String get eventCodeHint => 'From the organizer, e.g. K7QM-4XRT';

  @override
  String get deviceName => 'Device name';

  @override
  String get deviceNameHint => 'e.g. Gate A phone';

  @override
  String get useCode => 'Start with this code';

  @override
  String get scanCodeQr => 'Scan the organizer\'s QR';

  @override
  String get chooseEvent => 'Choose event';

  @override
  String get noEvents =>
      'No events to check in right now. Ask the organizer to add you as crew.';

  @override
  String get setupTitle => 'Gate setup';

  @override
  String get gate => 'Gate';

  @override
  String get gateHint => 'e.g. Main gate, VIP entrance';

  @override
  String get startScanning => 'Start scanning';

  @override
  String get pointCamera => 'Point the camera at the ticket QR';

  @override
  String get typeOrScan =>
      'Ticket QR text or code (handheld scanners work here too)';

  @override
  String get submit => 'Check';

  @override
  String get resultAccepted => 'Checked in';

  @override
  String get resultDuplicate => 'Already checked in';

  @override
  String get resultWrongEvent => 'Ticket for another event';

  @override
  String get resultInvalid => 'Not a valid ticket';

  @override
  String get resultVoid => 'Ticket cancelled';

  @override
  String get resultRefunded => 'Ticket refunded';

  @override
  String get resultTransferred => 'Ticket was transferred — ask for the new QR';

  @override
  String get outdatedQr =>
      'This QR is out of date — ask the guest to reopen their ticket';

  @override
  String otherEvent(String title) {
    return 'For: $title';
  }

  @override
  String checkedInAt(String time) {
    return 'Checked in at $time';
  }

  @override
  String atGate(String gate) {
    return 'at $gate';
  }

  @override
  String byWho(String name) {
    return 'by $name';
  }

  @override
  String get offline => 'Offline';

  @override
  String offlineBanner(int n) {
    return 'No connection — checking tickets on this device. $n scan(s) waiting to sync.';
  }

  @override
  String pendingSync(int n) {
    return '$n waiting to sync';
  }

  @override
  String get offlineChecked => 'Checked offline';

  @override
  String get notInList => 'Not in the downloaded list yet — signature is valid';

  @override
  String get syncConflict => 'Synced: was already checked in at another gate';

  @override
  String get lookup => 'Find guest';

  @override
  String get searchHint => 'Name, phone digits or ticket code';

  @override
  String get noResults => 'No matching tickets';

  @override
  String get checkIn => 'Check in';

  @override
  String confirmCheckIn(String name) {
    return 'Check in $name?';
  }

  @override
  String get activity => 'Activity';

  @override
  String get undo => 'Undo';

  @override
  String undoConfirm(String name) {
    return 'Undo the check-in for $name? The ticket can be scanned again.';
  }

  @override
  String get undone => 'Undone';

  @override
  String get undoOffline => 'Undo needs a connection';

  @override
  String get duplicate => 'Duplicate';

  @override
  String get manual => 'Manual';

  @override
  String attendance(int checked, int total) {
    return '$checked / $total checked in';
  }

  @override
  String get byGate => 'By gate';

  @override
  String get byTicketType => 'By ticket type';

  @override
  String get noGate => '(no gate)';

  @override
  String get recentScans => 'Recent scans';

  @override
  String get noScans => 'No scans yet';

  @override
  String get signOut => 'Sign out';

  @override
  String get switchEvent => 'Change event or gate';

  @override
  String get cameraUnavailable =>
      'Camera not available — type the code or use a handheld scanner.';

  @override
  String get retry => 'Retry';

  @override
  String get loadError => 'Could not load. Check the connection.';

  @override
  String get sessionEnded => 'Your session ended. Sign in again.';

  @override
  String get cancel => 'Cancel';

  @override
  String get ok => 'OK';

  @override
  String get language => 'မြန်မာ / English';
}

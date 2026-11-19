// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Burmese (`my`).
class L10nMy extends L10n {
  L10nMy([String locale = 'my']) : super(locale);

  @override
  String get appTitle => 'Event 360 Crew';

  @override
  String get signInTitle => 'ဝင်ပေါက် စစ်ဆေးခြင်း';

  @override
  String get tabAccount => 'ဝန်ထမ်းအကောင့်';

  @override
  String get tabCode => 'ပွဲကုဒ်';

  @override
  String get email => 'အီးမေးလ်';

  @override
  String get password => 'စကားဝှက်';

  @override
  String get signIn => 'ဝင်ရန်';

  @override
  String get eventCode => 'ပွဲကုဒ်';

  @override
  String get eventCodeHint => 'စီစဉ်သူထံမှ ကုဒ်၊ ဥပမာ K7QM-4XRT';

  @override
  String get deviceName => 'စက်အမည်';

  @override
  String get deviceNameHint => 'ဥပမာ ဂိတ် A ဖုန်း';

  @override
  String get useCode => 'ဤကုဒ်ဖြင့် စတင်ရန်';

  @override
  String get scanCodeQr => 'စီစဉ်သူ၏ QR ကို စကင်ဖတ်ရန်';

  @override
  String get chooseEvent => 'ပွဲ ရွေးပါ';

  @override
  String get noEvents =>
      'ယခု စစ်ဆေးရန် ပွဲမရှိပါ။ ဝန်ထမ်းအဖြစ် ထည့်ပေးရန် စီစဉ်သူကို မေးပါ။';

  @override
  String get setupTitle => 'ဂိတ် သတ်မှတ်ခြင်း';

  @override
  String get gate => 'ဂိတ်';

  @override
  String get gateHint => 'ဥပမာ ပင်မဂိတ်၊ VIP ဝင်ပေါက်';

  @override
  String get startScanning => 'စကင် စတင်ရန်';

  @override
  String get pointCamera => 'လက်မှတ် QR ကို ကင်မရာဖြင့် ချိန်ပါ';

  @override
  String get typeOrScan =>
      'လက်မှတ် QR စာသား သို့ ကုဒ် (လက်ကိုင်စကင်နာလည်း အသုံးပြုနိုင်)';

  @override
  String get submit => 'စစ်ရန်';

  @override
  String get resultAccepted => 'ဝင်ခွင့်ရပြီ';

  @override
  String get resultDuplicate => 'ဝင်ပြီးသား';

  @override
  String get resultWrongEvent => 'အခြားပွဲ၏ လက်မှတ်';

  @override
  String get resultInvalid => 'မှန်ကန်သော လက်မှတ် မဟုတ်ပါ';

  @override
  String get resultVoid => 'ပယ်ဖျက်ထားသော လက်မှတ်';

  @override
  String get resultRefunded => 'ငွေပြန်အမ်းထားသော လက်မှတ်';

  @override
  String get resultTransferred =>
      'လွှဲပြောင်းထားသော လက်မှတ် — QR အသစ် တောင်းပါ';

  @override
  String get outdatedQr => 'QR သက်တမ်းမမှန် — လက်မှတ်ကို ပြန်ဖွင့်ခိုင်းပါ';

  @override
  String otherEvent(String title) {
    return 'ပွဲ: $title';
  }

  @override
  String checkedInAt(String time) {
    return '$time တွင် ဝင်ခဲ့သည်';
  }

  @override
  String atGate(String gate) {
    return '$gate တွင်';
  }

  @override
  String byWho(String name) {
    return '$name မှ';
  }

  @override
  String get offline => 'အော့ဖ်လိုင်း';

  @override
  String offlineBanner(int n) {
    return 'အင်တာနက်မရှိ — ဤစက်ပေါ်တွင် စစ်ဆေးနေသည်။ စင့်ခ်လုပ်ရန် $n ခု ကျန်။';
  }

  @override
  String pendingSync(int n) {
    return 'စင့်ခ်ရန် $n ခု';
  }

  @override
  String get offlineChecked => 'အော့ဖ်လိုင်း စစ်ဆေးပြီး';

  @override
  String get notInList =>
      'ဒေါင်းလုဒ်စာရင်းတွင် မပါသေး — လက်မှတ်ထိုးချက် မှန်ကန်သည်';

  @override
  String get syncConflict => 'စင့်ခ်ပြီး: အခြားဂိတ်တွင် ဝင်ပြီးသား';

  @override
  String get lookup => 'ဧည့်သည် ရှာရန်';

  @override
  String get searchHint => 'အမည်၊ ဖုန်းနံပါတ် သို့ လက်မှတ်ကုဒ်';

  @override
  String get noResults => 'ကိုက်ညီသော လက်မှတ် မရှိပါ';

  @override
  String get checkIn => 'ဝင်ခွင့်ပေးရန်';

  @override
  String confirmCheckIn(String name) {
    return '$name ကို ဝင်ခွင့်ပေးမလား?';
  }

  @override
  String get activity => 'လှုပ်ရှားမှု';

  @override
  String get undo => 'ပြန်ဖျက်ရန်';

  @override
  String undoConfirm(String name) {
    return '$name ၏ ဝင်ခွင့်ကို ပြန်ဖျက်မလား? လက်မှတ်ကို ထပ်စကင်ဖတ်နိုင်ပါမည်။';
  }

  @override
  String get undone => 'ပြန်ဖျက်ပြီး';

  @override
  String get undoOffline => 'ပြန်ဖျက်ရန် အင်တာနက် လိုပါသည်';

  @override
  String get duplicate => 'ထပ်နေ';

  @override
  String get manual => 'လက်ဖြင့်';

  @override
  String attendance(int checked, int total) {
    return '$checked / $total ဝင်ပြီး';
  }

  @override
  String get byGate => 'ဂိတ်အလိုက်';

  @override
  String get byTicketType => 'လက်မှတ်အမျိုးအစားအလိုက်';

  @override
  String get noGate => '(ဂိတ် မသတ်မှတ်)';

  @override
  String get recentScans => 'နောက်ဆုံး စကင်များ';

  @override
  String get noScans => 'စကင် မရှိသေးပါ';

  @override
  String get signOut => 'ထွက်ရန်';

  @override
  String get switchEvent => 'ပွဲ သို့ ဂိတ် ပြောင်းရန်';

  @override
  String get cameraUnavailable =>
      'ကင်မရာ မရနိုင်ပါ — ကုဒ်ရိုက်ထည့်ပါ သို့ လက်ကိုင်စကင်နာ သုံးပါ။';

  @override
  String get retry => 'ထပ်ကြိုးစားရန်';

  @override
  String get loadError => 'ဖွင့်၍ မရပါ။ အင်တာနက် စစ်ပါ။';

  @override
  String get sessionEnded => 'အချိန်ကုန်သွားပါပြီ။ ပြန်ဝင်ပါ။';

  @override
  String get cancel => 'မလုပ်တော့ပါ';

  @override
  String get ok => 'အိုကေ';

  @override
  String get language => 'မြန်မာ / English';
}

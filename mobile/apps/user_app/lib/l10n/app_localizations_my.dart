// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Burmese (`my`).
class L10nMy extends L10n {
  L10nMy([String locale = 'my']) : super(locale);

  @override
  String get appTitle => 'Event 360';

  @override
  String get home => 'ပင်မ';

  @override
  String get explore => 'ရှာဖွေ';

  @override
  String get myTickets => 'လက်မှတ်များ';

  @override
  String get profile => 'ပရိုဖိုင်';

  @override
  String get searchHint => 'ပွဲများ ရှာဖွေရန်';

  @override
  String get allCategories => 'အားလုံး';

  @override
  String get upcoming => 'လာမည့်ပွဲများ';

  @override
  String get freeEvents => 'အခမဲ့ပွဲများ';

  @override
  String get seeAll => 'အားလုံးကြည့်ရန်';

  @override
  String get noEvents => 'ပွဲ မတွေ့ပါ။';

  @override
  String get loadError => 'ဖွင့်၍မရပါ။ အင်တာနက်ကို စစ်ဆေးပါ။';

  @override
  String get retry => 'ထပ်ကြိုးစားမည်';

  @override
  String get free => 'အခမဲ့';

  @override
  String get soldOut => 'ကုန်သွားပါပြီ';

  @override
  String fromPrice(String price) {
    return '$price မှစ၍';
  }

  @override
  String mmk(String amount) {
    return '$amount ကျပ်';
  }

  @override
  String get register => 'စာရင်းသွင်းမည်';

  @override
  String get registerFree => 'အခမဲ့ စာရင်းသွင်းမည်';

  @override
  String get quantity => 'လက်မှတ်';

  @override
  String perPersonLimit(int n) {
    return 'တစ်ဦးလျှင် $n စောင်အထိ';
  }

  @override
  String remaining(int n) {
    return '$n စောင် ကျန်';
  }

  @override
  String get tickets => 'လက်မှတ်များ';

  @override
  String get about => 'အကြောင်း';

  @override
  String get organizer => 'စီစဉ်သူ';

  @override
  String get verified => 'အတည်ပြုထားသော စီစဉ်သူ';

  @override
  String get venue => 'နေရာ';

  @override
  String get formatOnline => 'အွန်လိုင်း';

  @override
  String get formatInPerson => 'တိုက်ရိုက်တက်ရောက်';

  @override
  String get formatHybrid => 'တိုက်ရိုက် + အွန်လိုင်း';

  @override
  String get paidSoon => 'ငွေပေးလက်မှတ်များကို မကြာမီ ဝယ်ယူနိုင်ပါမည်။';

  @override
  String get signIn => 'ဝင်ရန်';

  @override
  String get signInToRegister => 'စာရင်းသွင်းရန် ဖုန်းနံပါတ်ဖြင့် ဝင်ပါ။';

  @override
  String get phoneNumber => 'ဖုန်းနံပါတ်';

  @override
  String get phoneHint => '09xxxxxxxxx';

  @override
  String get sendCode => 'ကုဒ်ပို့မည်';

  @override
  String codeSentTo(String phone) {
    return '$phone သို့ ပို့ထားသော ဂဏန်း ၆ လုံး ကုဒ်ကို ထည့်ပါ';
  }

  @override
  String get code => 'ကုဒ်';

  @override
  String get verify => 'အတည်ပြုမည်';

  @override
  String get changeNumber => 'နံပါတ်ပြောင်းမည်';

  @override
  String devCode(String code) {
    return 'စမ်းသပ်ကုဒ်: $code';
  }

  @override
  String get invalidPhone => 'မှန်ကန်သော မိုဘိုင်းနံပါတ် ထည့်ပါ (09…)';

  @override
  String get invalidCode => 'ဂဏန်း ၆ လုံး ကုဒ်ကို ထည့်ပါ';

  @override
  String get tooManyCodes =>
      'ကုဒ်တောင်းဆိုမှု များလွန်းပါသည်။ မိနစ်အနည်းငယ် စောင့်ပါ။';

  @override
  String get signOut => 'ထွက်မည်';

  @override
  String get language => 'ဘာသာစကား';

  @override
  String signedInAs(String phone) {
    return '$phone ဖြင့် ဝင်ထားသည်';
  }

  @override
  String get notSignedIn => 'မဝင်ရသေးပါ။';

  @override
  String get registered => 'စာရင်းသွင်းပြီးပါပြီ! 🎉';

  @override
  String get viewTickets => 'လက်မှတ်များ ကြည့်မည်';

  @override
  String get showAtEntrance => 'ဝင်ပေါက်တွင် ဤ QR ကုဒ်ကို ပြပါ';

  @override
  String get offlineReady => 'အင်တာနက်မရှိလည်း ကြည့်နိုင်သည်';

  @override
  String get noTickets => 'လက်မှတ် မရှိသေးပါ။ ပွဲတစ်ခု ရှာဖွေလိုက်ပါ!';

  @override
  String get past => 'ပြီးခဲ့သော';

  @override
  String get upcomingTickets => 'လာမည့်';

  @override
  String get ticketCancelled => 'ဤလက်မှတ် အသုံးမပြုနိုင်တော့ပါ';

  @override
  String get share => 'မျှဝေမည်';

  @override
  String get freeOnly => 'အခမဲ့သာ';

  @override
  String get city => 'မြို့';

  @override
  String get anyCity => 'မြို့အားလုံး';

  @override
  String get clearFilters => 'ရှင်းမည်';

  @override
  String get eventCancelled => 'ဤပွဲကို ဖျက်သိမ်းလိုက်ပါပြီ';

  @override
  String get eventEnded => 'ဤပွဲ ပြီးဆုံးသွားပါပြီ';

  @override
  String get chooseLanguage => 'ဘာသာစကား ရွေးချယ်ပါ';

  @override
  String get continueLabel => 'ဆက်လက်မည်';

  @override
  String get addToCalendar => 'ပြက္ခဒိန်တွင် ထည့်မည်';

  @override
  String get openInMaps => 'မြေပုံတွင် ဖွင့်မည်';

  @override
  String get schedule => 'အစီအစဉ်';

  @override
  String get lineup => 'တင်ဆက်သူများ';

  @override
  String get gallery => 'ဓာတ်ပုံများ';

  @override
  String get practicalInfo => 'သိထားသင့်သည်များ';

  @override
  String ageLimit(int n) {
    return 'အသက် $n နှစ်နှင့်အထက်';
  }

  @override
  String get dressCode => 'ဝတ်စားဆင်ယင်မှု';

  @override
  String get languages => 'ဘာသာစကား';

  @override
  String get parking => 'ကားရပ်နားရန်';

  @override
  String get accessibility => 'အဆင်ပြေမှု';

  @override
  String get whatToBring => 'ယူဆောင်လာရန်';

  @override
  String get faq => 'မေးလေ့ရှိသော မေးခွန်းများ';

  @override
  String get terms => 'စည်းကမ်းချက်များ';

  @override
  String get refundPolicy => 'ငွေပြန်အမ်းမူဝါဒ';

  @override
  String get directions => 'သွားရောက်ပုံ';

  @override
  String get viewOrganizer => 'စီစဉ်သူကို ကြည့်မည်';

  @override
  String get organizerEvents => 'လာမည့်ပွဲများ';

  @override
  String get website => 'ဝက်ဘ်ဆိုက်';

  @override
  String get facebook => 'Facebook';

  @override
  String get contact => 'ဆက်သွယ်ရန်';

  @override
  String get noUpcomingEvents => 'လောလောဆယ် လာမည့်ပွဲ မရှိသေးပါ။';

  @override
  String get watch => 'ကြည့်ရှုရန်';

  @override
  String get liveNow => 'တိုက်ရိုက်';

  @override
  String get watchLive => 'တိုက်ရိုက် ကြည့်ရန်';

  @override
  String get recordingsTitle => 'မှတ်တမ်းများ';

  @override
  String startsAtTime(String time) {
    return '$time တွင် စမည်';
  }

  @override
  String availableUntil(String date) {
    return '$date အထိ ကြည့်နိုင်';
  }

  @override
  String get needTicketToWatch => 'ကြည့်ရှုရန် ဤပွဲအတွက် စာရင်းသွင်းပါ။';

  @override
  String get notLiveNow => 'ယခု တိုက်ရိုက်ထုတ်လွှင့်မနေပါ။';

  @override
  String get otherDevice =>
      'အခြားစက်တွင် ကြည့်ရှုနေသဖြင့် ဤနေရာတွင် ရပ်လိုက်ပါသည်။';

  @override
  String get videoError =>
      'ဗီဒီယို ဖွင့်၍ မရပါ။ အင်တာနက် စစ်ပြီး ထပ်ကြိုးစားပါ။';

  @override
  String get liveEnded =>
      'တိုက်ရိုက်ထုတ်လွှင့်မှု ပြီးဆုံးပါပြီ။ မှတ်တမ်း မကြာမီ ရနိုင်ပါသည်။';

  @override
  String get getTickets => 'လက်မှတ်ဝယ်မည်';

  @override
  String get checkout => 'ငွေပေးချေရန်';

  @override
  String get total => 'စုစုပေါင်း';

  @override
  String get payWith => 'ငွေပေးနည်း';

  @override
  String payNow(String amount) {
    return '$amount ပေးချေမည်';
  }

  @override
  String holdExpiresIn(String time) {
    return 'လက်မှတ်များကို $time ထိန်းထားပါသည်';
  }

  @override
  String get waitingForPayment => 'ငွေပေးချေမှုကို စောင့်နေပါသည်…';

  @override
  String get waitingHint =>
      'ပိုက်ဆံအိတ် App တွင် ငွေပေးချေပြီး ဤနေရာသို့ ပြန်လာပါ။ ဤစာမျက်နှာ အလိုအလျောက် ပြောင်းပါမည်။';

  @override
  String get openWalletAgain => 'ငွေပေးစာမျက်နှာ ပြန်ဖွင့်မည်';

  @override
  String get scanToPay => 'ပိုက်ဆံအိတ် App ဖြင့် ဤ QR ကို စကင်ဖတ်ပါ';

  @override
  String get paymentReceived =>
      'ငွေလက်ခံရရှိပါပြီ။ လက်မှတ်များ အသင့်ဖြစ်ပါပြီ။';

  @override
  String get holdExpired =>
      'ငွေမရောက်မီ ထိန်းထားချိန် ကုန်သွားပါပြီ။ ငွေပေးပြီးပါက မကြာမီ လက်မှတ်ရရှိမည် သို့မဟုတ် ငွေပြန်အမ်းပါမည်။';

  @override
  String get startAgain => 'ပြန်စမည်';

  @override
  String get cancelOrder => 'အော်ဒါ ပယ်ဖျက်မည်';

  @override
  String get orderCancelled => 'အော်ဒါ ပယ်ဖျက်ပြီးပါပြီ။';

  @override
  String get paymentNotAvailable => 'လောလောဆယ် ငွေပေးနည်း မရှိပါ။';

  @override
  String get continuePayment => 'ငွေဆက်ပေးမည်';

  @override
  String get pendingPayments => 'ငွေပေးရန် ကျန်';

  @override
  String get ticketRefunded => 'ဤလက်မှတ်ကို ငွေပြန်အမ်းပြီးပါပြီ။';

  @override
  String get choosePayment => 'ငွေပေးနည်း ရွေးပါ';

  @override
  String orderSummary(String qty, String name) {
    return '$qty × $name';
  }
}

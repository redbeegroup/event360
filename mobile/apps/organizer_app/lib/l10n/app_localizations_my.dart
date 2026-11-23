// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Burmese (`my`).
class L10nMy extends L10n {
  L10nMy([String locale = 'my']) : super(locale);

  @override
  String get appTitle => 'Event 360 စီစဉ်သူ';

  @override
  String get signInTitle => 'စီစဉ်သူ အကောင့်ဖြင့် ဝင်ပါ';

  @override
  String get email => 'အီးမေးလ်';

  @override
  String get password => 'စကားဝှက်';

  @override
  String get signIn => 'ဝင်မည်';

  @override
  String get signOut => 'ထွက်မည်';

  @override
  String get notOrganizer =>
      'ဤအကောင့်သည် မည်သည့်အဖွဲ့အစည်းတွင်မှ မပါဝင်ပါ။ Portal မှ ဖိတ်ကြားရန် အဖွဲ့ပိုင်ရှင်ကို မေးပါ။';

  @override
  String get events => 'ပွဲများ';

  @override
  String get upcoming => 'လာမည့်ပွဲ';

  @override
  String get past => 'ပြီးခဲ့သောပွဲ';

  @override
  String get noEvents => 'ပွဲ မရှိသေးပါ။ Portal တွင် ပွဲဖန်တီးပါ။';

  @override
  String get liveNow => 'ယခု ကျင်းပနေ';

  @override
  String get loadError => 'ဖွင့်၍မရပါ။ အင်တာနက်ကို စစ်ပါ။';

  @override
  String get retry => 'ထပ်ကြိုးစားမည်';

  @override
  String get organization => 'အဖွဲ့အစည်း';

  @override
  String get status_DRAFT => 'မူကြမ်း';

  @override
  String get status_SUBMITTED => 'စစ်ဆေးနေ';

  @override
  String get status_PUBLISHED => 'ထုတ်ပြန်ပြီး';

  @override
  String get status_ONGOING => 'ကျင်းပနေ';

  @override
  String get status_COMPLETED => 'ပြီးဆုံး';

  @override
  String get status_CANCELLED => 'ဖျက်သိမ်း';

  @override
  String get status_REJECTED => 'ငြင်းပယ်';

  @override
  String get orderStatus_PENDING_PAYMENT => 'ငွေပေးချေရန် စောင့်နေ';

  @override
  String get orderStatus_PAID => 'ငွေပေးချေပြီး';

  @override
  String get orderStatus_CONFIRMED => 'အတည်ပြုပြီး';

  @override
  String get orderStatus_EXPIRED => 'သက်တမ်းကုန်';

  @override
  String get orderStatus_CANCELLED => 'ဖျက်သိမ်း';

  @override
  String get orderStatus_REFUNDED => 'ငွေပြန်အမ်းပြီး';

  @override
  String get orderStatus_FAILED => 'မအောင်မြင်';

  @override
  String get tabOverview => 'အကျဉ်း';

  @override
  String get tabDoor => 'ဝင်ပေါက်';

  @override
  String get tabAnnounce => 'ကြေညာ';

  @override
  String get tabPromos => 'ပရိုမို';

  @override
  String get ticketsSold => 'ရောင်းပြီး လက်မှတ်';

  @override
  String get revenue => 'ဝင်ငွေ';

  @override
  String get checkedIn => 'ဝင်ရောက်ပြီး';

  @override
  String get orders => 'အော်ဒါ';

  @override
  String get pageViews => 'ကြည့်ရှုမှု';

  @override
  String get discounts => 'လျှော့စျေး';

  @override
  String get byTicketType => 'အမျိုးအစားအလိုက်';

  @override
  String get seatsTitle => 'ထိုင်ခုံများ';

  @override
  String get seatsAvailable => 'ရနိုင်သည်';

  @override
  String get seatsHeld => 'ငွေပေးချေနေဆဲ';

  @override
  String get seatsGuest => 'ဧည့်သည်ထားသည်';

  @override
  String get seatsSold => 'ရောင်းပြီး';

  @override
  String get seatsComp => 'ဧည့်သည်လက်မှတ်';

  @override
  String get seatsOffered => 'ကမ်းလှမ်းထားသည်';

  @override
  String get waitlistTitle => 'စောင့်ဆိုင်းစာရင်း';

  @override
  String waitlistLine(String waiting, String offered) {
    return 'စောင့်နေသူ $waiting ဦး · ကမ်းလှမ်းချက်ရသူ $offered ဦး';
  }

  @override
  String get byGate => 'ဂိတ်အလိုက် ဝင်ရောက်မှု';

  @override
  String get recentOrders => 'နောက်ဆုံး အော်ဒါများ';

  @override
  String get noOrders => 'အော်ဒါ မရှိသေးပါ။';

  @override
  String updatedAt(String time) {
    return '$time တွင် အပ်ဒိတ်';
  }

  @override
  String get noGate => 'ဂိတ်မရှိ';

  @override
  String get doorHint =>
      'စေတနာ့ဝန်ထမ်း အဖွဲ့တစ်ခုစီအတွက် ကုဒ်ဖန်တီးပါ။ ၎င်းတို့သည် Crew App ကိုဖွင့်ပြီး QR စကင်ဖတ် (သို့ ကုဒ်ရိုက်ထည့်) ကာ လက်မှတ်စစ်နိုင်ပါသည်။';

  @override
  String get codeLabel => 'အမည် (ဥပမာ စေတနာ့ဝန်ထမ်း)';

  @override
  String get gate => 'ဂိတ် (မထည့်လည်းရ)';

  @override
  String get createCode => 'ကုဒ် ဖန်တီးမည်';

  @override
  String get codeCreated => 'စေတနာ့ဝန်ထမ်းများကို ပြပါ';

  @override
  String get codeOnce =>
      'ကုဒ်ကို ယခုတစ်ကြိမ်သာ ပြပါမည်။ ပျောက်ပါက အသစ်ဖန်တီးပါ။';

  @override
  String get revoke => 'ပယ်ဖျက်မည်';

  @override
  String get revokeConfirm =>
      'ဤကုဒ်ကို ပယ်ဖျက်မလား။ အသုံးပြုနေသော ဖုန်းများ ထွက်သွားပါမည်။';

  @override
  String devices(int n) {
    return 'ဖုန်း $n လုံး';
  }

  @override
  String get expired => 'သက်တမ်းကုန်';

  @override
  String get revoked => 'ပယ်ဖျက်ပြီး';

  @override
  String get openCrewApp => 'Crew App ဖွင့်မည်';

  @override
  String get done => 'ပြီးပြီ';

  @override
  String get announceHint =>
      'လက်မှတ်ကိုင်ဆောင်သူ အားလုံးထံ အသိပေးချက် ပို့သည် (SMS မဟုတ်)။ တစ်ရက် ၃ ကြိမ်အထိ။';

  @override
  String recipients(int n) {
    return 'လက်မှတ်ကိုင်ဆောင်သူ $n ဦး';
  }

  @override
  String leftToday(int n) {
    return 'ယနေ့ $n ကြိမ် ကျန်';
  }

  @override
  String get heading => 'ခေါင်းစဉ်';

  @override
  String get message => 'စာ';

  @override
  String get headingMy => 'ခေါင်းစဉ် (မြန်မာ၊ မထည့်လည်းရ)';

  @override
  String get messageMy => 'စာ (မြန်မာ၊ မထည့်လည်းရ)';

  @override
  String get send => 'ပို့မည်';

  @override
  String get sendConfirm => 'လက်မှတ်ကိုင်ဆောင်သူ အားလုံးထံ ယခု ပို့မလား။';

  @override
  String get sent => 'ပို့ပြီး';

  @override
  String get cancel => 'မလုပ်တော့ပါ';

  @override
  String get noAnnouncements => 'မပို့ရသေးပါ။';

  @override
  String get promosHint =>
      'ငွေပေးလက်မှတ်များအတွက် လျှော့စျေး။ ကော်မရှင်ကို လျှော့ပြီးစျေးဖြင့် တွက်သည်။';

  @override
  String get promoCode => 'ကုဒ်';

  @override
  String get percent => '% လျှော့';

  @override
  String get fixed => 'ကျပ် လျှော့';

  @override
  String get amount => 'ပမာဏ';

  @override
  String get maxUses => 'အများဆုံး အသုံးပြုမှု (မထည့်လည်းရ)';

  @override
  String get createPromo => 'ကုဒ် ဖန်တီးမည်';

  @override
  String used(String n) {
    return '$n ကြိမ် သုံးပြီး';
  }

  @override
  String get turnOn => 'ဖွင့်မည်';

  @override
  String get turnOff => 'ပိတ်မည်';

  @override
  String get off => 'ပိတ်ထား';

  @override
  String get noPromos => 'ကုဒ် မရှိသေးပါ။';

  @override
  String get notifications => 'အသိပေးချက်များ';

  @override
  String get markAllRead => 'အားလုံး ဖတ်ပြီး';

  @override
  String get noNotifications =>
      'အရောင်း မှတ်တိုင်များ၊ အတည်ပြုချက်များနှင့် နေ့စဉ် အနှစ်ချုပ် ဤနေရာတွင် ပေါ်ပါမည်။';

  @override
  String get readOnly => 'ကြည့်ရှုရန်သာ — သင့်ရာထူးဖြင့် ပြင်၍မရပါ။';

  @override
  String get tabGuests => 'ဧည့်သည်များ';

  @override
  String guestsCount(int inCount, int total) {
    return '$total ဦးအနက် $inCount ဦး ဝင်ပြီး';
  }

  @override
  String get guestsSearch => 'အမည်၊ ဖုန်း သို့မဟုတ် ခုံ ရှာပါ';

  @override
  String get guestsNotIn => 'မဝင်သေးသူ';

  @override
  String get statusIn => 'ဝင်ရောက်ပြီး';

  @override
  String get statusNotIn => 'မဝင်သေး';

  @override
  String get statusCancelled => 'ပယ်ဖျက်ပြီး';

  @override
  String get guestBadge => 'ဧည့်သည်';

  @override
  String get guestsEmpty => 'လက်မှတ် မရှိသေးပါ';

  @override
  String get guestsNoMatch => 'ကိုက်ညီသူ မရှိပါ';

  @override
  String get checkIn => 'ဝင်ရောက်မှု မှတ်မည်';

  @override
  String get undoCheckIn => 'ဝင်ရောက်မှု ပြန်ရုတ်မည်';

  @override
  String undoCheckInConfirm(String name) {
    return '$name ၏ ဝင်ရောက်မှုကို ပြန်ရုတ်မလား။';
  }

  @override
  String checkedInOk(String name) {
    return '$name ဝင်ရောက်ပြီးပါပြီ';
  }

  @override
  String alreadyCheckedIn(String time) {
    return '$time တွင် ဝင်ရောက်ပြီးဖြစ်သည်';
  }

  @override
  String alreadyCheckedInGate(String time, String gate) {
    return '$time တွင် $gate မှ ဝင်ရောက်ပြီးဖြစ်သည်';
  }

  @override
  String checkInRefused(String status) {
    return 'ဝင်ရောက်မှု မမှတ်နိုင်ပါ — ဤလက်မှတ်သည် $status ဖြစ်သည်';
  }

  @override
  String get checkInNoConnection =>
      'ဝင်ရောက်မှု မမှတ်ရသေးပါ — ဆက်သွယ်မှု မရှိပါ။ ထပ်စမ်းပါ။';

  @override
  String get checkInClosed =>
      'ပွဲမတိုင်မီ တစ်ရက်အလိုမှ ဝင်ရောက်မှု မှတ်နိုင်သည်';

  @override
  String get checkInEnded => 'ဝင်ရောက်မှု မှတ်ချိန် ပြီးဆုံးသွားပါပြီ';

  @override
  String get call => 'ဖုန်းခေါ်မည်';

  @override
  String registeredOn(String date) {
    return '$date တွင် မှတ်ပုံတင်သည်';
  }

  @override
  String get checkInRefusedGeneric => 'ဤလက်မှတ်ကို ဝင်ရောက်မှု မမှတ်နိုင်ပါ';

  @override
  String get tabSeats => 'ထိုင်ခုံများ';

  @override
  String seatsSelected(int count) {
    return 'ခုံ $count ခု ရွေးထားသည်';
  }

  @override
  String get clear => 'ရှင်းမည်';

  @override
  String get holdForGuests => 'ဧည့်သည်အတွက် ထိန်းထားမည်';

  @override
  String get holdLabelField => 'အမည်တပ်ရန် (ဥပမာ - ပံ့ပိုးသူ)';

  @override
  String get releaseSeats => 'ပြန်လွှတ်မည်';

  @override
  String releaseConfirm(int count) {
    return 'ခုံ $count ခုကို ပြန်လည်ရောင်းချနိုင်အောင် လွှတ်မလား။';
  }

  @override
  String get issueGuestTickets => 'ဧည့်သည်လက်မှတ် ထုတ်ပေးမည်';

  @override
  String get guestNameField => 'ဧည့်သည်အမည်';

  @override
  String get guestPhoneField => 'ဧည့်သည်ဖုန်းနံပါတ်';

  @override
  String get guestLabelField => 'အမည်တပ်ရန် (မဖြည့်လည်းရသည်)';

  @override
  String get issueHelp =>
      'ဧည့်သည်သည် ဤနံပါတ်ဖြင့် ဝင်ပြီးနောက် Event 360 အက်ပ်တွင် လက်မှတ်များကို တွေ့ရမည်။ SMS မပို့ပါ။';

  @override
  String issueConfirmText(int count, String phone) {
    return 'ဧည့်သည်လက်မှတ် $count စောင်ကို $phone သို့ ထုတ်ပေးမလား။';
  }

  @override
  String get seatsMixedHint =>
      'ရောင်းချနေသောခုံများသာ သို့မဟုတ် ထိန်းထားသောခုံများသာ ရွေးပါ';

  @override
  String get seatsNoTypeHint =>
      'ထိန်းထားသောခုံအချို့တွင် လက်မှတ်အမျိုးအစား မသတ်မှတ်ရသေးပါ';

  @override
  String get seatsTooMany => 'ခုံ 200 သို့မဟုတ် ထို့ထက်နည်းအောင် ရွေးပါ';

  @override
  String get seatsChanged =>
      'ခုံအချို့ ပြောင်းလဲသွားပါပြီ။ မြေပုံကို ပြန်လည်ပြင်ဆင်ထားသည်။';

  @override
  String heldLabel(String label) {
    return 'ထိန်းထားသည် - $label';
  }

  @override
  String get legendAvailable => 'ရောင်းချနေသည်';

  @override
  String get legendHeld => 'ဧည့်သည်အတွက် ထိန်းထား';

  @override
  String get legendSold => 'ရောင်းပြီး';

  @override
  String get legendGuest => 'ဧည့်သည်လက်မှတ်';

  @override
  String get guestList => 'ဧည့်သည်လက်မှတ်များ';

  @override
  String revokeGuestConfirm(String name, String seat) {
    return '$name ($seat) ၏ ဧည့်သည်လက်မှတ်ကို ရုပ်သိမ်းမလား။';
  }

  @override
  String get guestRevoked => 'ရုပ်သိမ်းပြီး';

  @override
  String get phoneInvalid => 'မြန်မာမိုဘိုင်းဖုန်းနံပါတ် ထည့်ပါ';

  @override
  String get viewOnlySeats =>
      'ခုံများကို ကြည့်ရှုနိုင်သော်လည်း မပြောင်းလဲနိုင်ပါ';

  @override
  String get seatsZoomHint => 'ခုံရွေးရန် ချဲ့ကြည့်ပါ';

  @override
  String get fieldRequired => 'လိုအပ်သည်';

  @override
  String get noGuestTickets => 'ဧည့်သည်လက်မှတ် မရှိသေးပါ';

  @override
  String get seatsViewMap => 'မြေပုံ';

  @override
  String seatsViewGuests(int count) {
    return 'ဧည့်သည်လက်မှတ် ($count)';
  }

  @override
  String get legendSelected => 'ရွေးထားသည်';

  @override
  String ticketsIssued(int count) {
    return 'ဧည့်သည်လက်မှတ် $count စောင် ထုတ်ပေးပြီး';
  }

  @override
  String get tabSales => 'ရောင်းချမှု';

  @override
  String get paidOrders => 'ငွေပေးချေပြီး အော်ဒါများ';

  @override
  String get grossSales => 'စုစုပေါင်း ရောင်းရငွေ';

  @override
  String get grossCaption => 'ငွေပေးချေပြီး အော်ဒါများသာ၊ လျှော့စျေး နုတ်ပြီး';

  @override
  String get commission => 'ကော်မရှင်';

  @override
  String get netToYou => 'သင့်ထံ ရမည့်ငွေ';

  @override
  String refundedLine(String count, String amount) {
    return '$count · $amount';
  }

  @override
  String get refunded => 'ငွေပြန်အမ်းပြီး';

  @override
  String get noPaidTickets => 'ဤပွဲတွင် ငွေပေးဝယ်ရသော လက်မှတ် မရှိပါ';

  @override
  String nextPriceLine(String amount, String date) {
    return '$date တွင် စျေးနှုန်း $amount ဖြစ်မည်';
  }

  @override
  String soldOf(String sold, String quota) {
    return '$quota ထဲက $sold ရောင်းပြီး';
  }

  @override
  String get allOrders => 'အော်ဒါအားလုံး';

  @override
  String get orderSearchHint =>
      'အမည်၊ ဖုန်းနံပါတ်အပြည့်အစုံ သို့ အော်ဒါနံပါတ် ရှာရန်';

  @override
  String get filterAll => 'အားလုံး';

  @override
  String get filterPaid => 'ငွေပေးချေပြီး';

  @override
  String get filterRefunded => 'ငွေပြန်အမ်းပြီး';

  @override
  String get filterPending => 'ငွေပေးချေရန် စောင့်နေ';

  @override
  String get filterIncomplete => 'မပြီးစီးသော';

  @override
  String orderNumber(String number) {
    return 'အော်ဒါ $number';
  }

  @override
  String get walkUp => 'ပွဲနေရာတွင် ဝယ်သူ';

  @override
  String get beingReviewed => 'စစ်ဆေးနေဆဲ';

  @override
  String get reviewNote =>
      'Event 360 က ဤငွေပေးချေမှုကို စစ်ဆေးနေပါသည်။ ဝယ်သူထံ ငွေပြန်ပေးရန် လိုအပ်ပါက ကျွန်ုပ်တို့ ပြန်အမ်းပေးပါမည်။';

  @override
  String holdUntil(String time) {
    return '$time တွင် သိမ်းထားချိန် ကုန်မည်';
  }

  @override
  String get ordersEmpty => 'အော်ဒါ မရှိသေးပါ';

  @override
  String get ordersNoMatch => 'ကိုက်ညီသော အော်ဒါ မရှိပါ';

  @override
  String get loadMoreFailed => 'ထပ်မံ မရယူနိုင်ပါ။ ထပ်ကြိုးစားရန် နှိပ်ပါ။';

  @override
  String orderCreated(String time) {
    return 'မှာယူချိန် $time';
  }

  @override
  String orderPaid(String time) {
    return 'ငွေပေးချေချိန် $time';
  }

  @override
  String get subtotal => 'ခွဲပေါင်း';

  @override
  String get discount => 'လျှော့စျေး';

  @override
  String discountPromo(String code) {
    return 'လျှော့စျေး ($code)';
  }

  @override
  String get discountGroup => 'အုပ်စုလျှော့စျေး';

  @override
  String get total => 'စုစုပေါင်း';

  @override
  String get payments => 'ငွေပေးချေမှုများ';

  @override
  String get refunds => 'ငွေပြန်အမ်းမှုများ';

  @override
  String get refundInProgress => 'ငွေပြန်အမ်းနေဆဲ';

  @override
  String get refundByHand => 'Event 360 က ကိုယ်တိုင် ပြန်အမ်းပေးနေပါသည်';

  @override
  String get refundDone => 'ငွေပြန်အမ်းပြီး';

  @override
  String get wholeOrderRefund =>
      'ငွေပြန်အမ်းခြင်းသည် အော်ဒါတစ်ခုလုံးအတွက်သာ ဖြစ်ပါသည်။';

  @override
  String ticketsCheckedIn(String inCount, String total) {
    return 'လက်မှတ် $total စောင်ထဲမှ $inCount စောင် ဝင်ပြီး';
  }

  @override
  String seatsLine(String seats) {
    return 'ခုံ: $seats';
  }

  @override
  String get salesViewSummary => 'အနှစ်ချုပ်';

  @override
  String get salesViewOrders => 'အော်ဒါများ';

  @override
  String get refreshFailed =>
      'ပြန်လည်မရယူနိုင်ပါ။ အရင်ရထားသော အချက်အလက်ကို ပြထားပါသည်။';

  @override
  String holdEnded(String time) {
    return '$time တွင် သိမ်းထားချိန် ကုန်သွားပြီ';
  }

  @override
  String get paymentCash => 'ငွေသား';

  @override
  String get paymentCard => 'ကတ်';

  @override
  String get payouts => 'ငွေထုတ်ပေးမှုများ';

  @override
  String get earned => 'ရရှိငွေ';

  @override
  String get paidOut => 'ထုတ်ပေးပြီးငွေ';

  @override
  String get owedToYou => 'သင့်ကို ပေးရန်ကျန်';

  @override
  String youOwe(String amount) {
    return 'သင်သည် Event 360 ကို $amount ပေးရန်ကျန်ပါသည်';
  }

  @override
  String get reconcileNote =>
      'ဤသည်မှာ အရောင်း အသေးစိတ်ဖြစ်ပါသည်။ စုစုပေါင်းများကို စာရင်းဇယားမှ ယူထားပါသည်။';

  @override
  String get byEvent => 'ပွဲအလိုက်';

  @override
  String get salesBeforeRefunds => 'ငွေပြန်မအမ်းမီ ရောင်းရငွေ';

  @override
  String get payoutHistory => 'ငွေထုတ်ပေးမှု မှတ်တမ်း';

  @override
  String get noPayouts => 'ငွေထုတ်ပေးမှု မရှိသေးပါ။';

  @override
  String get voided => 'ပယ်ဖျက်ပြီး';

  @override
  String get methodBANK => 'ဘဏ်လွှဲ';

  @override
  String get methodOTHER => 'အခြား';

  @override
  String get reference => 'ကိုးကားနံပါတ်';

  @override
  String get noSalesYet => 'ရောင်းရမှု မရှိသေးပါ';

  @override
  String get revenueCaption =>
      'လက်မှတ်ရောင်းရငွေသည် လျှော့စျေး မနုတ်မီ ငွေဖြစ်ပါသည်';

  @override
  String get refundedAmount => 'ပြန်အမ်းငွေ';

  @override
  String get discountsIncluded =>
      'ပေးထားသော လျှော့စျေး (ရောင်းရငွေထဲမှ နုတ်ပြီးသား)';

  @override
  String get balance => 'လက်ကျန်';
}

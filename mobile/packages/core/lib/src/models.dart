/// Plain models for the Event 360 API (hand-written; see apps/api for the source of truth).
library;

DateTime _dt(Object? v) => DateTime.parse(v as String);
DateTime? _dtn(Object? v) => v == null ? null : DateTime.parse(v as String);

/// Picks the Myanmar text when the UI is Myanmar and it exists, else English.
String pickLang(String lang, String? en, String? my) =>
    (lang == 'my' && my != null && my.isNotEmpty) ? my : (en ?? my ?? '');

class Category {
  Category({required this.id, required this.slug, required this.nameEn, this.nameMy, this.iconKey, this.children = const []});
  final String id;
  final String slug;
  final String nameEn;
  final String? nameMy;
  final String? iconKey;
  final List<Category> children;

  String name(String lang) => pickLang(lang, nameEn, nameMy);

  factory Category.fromJson(Map<String, dynamic> j) => Category(
        id: j['id'] as String,
        slug: j['slug'] as String,
        nameEn: j['nameEn'] as String,
        nameMy: j['nameMy'] as String?,
        iconKey: j['iconKey'] as String?,
        children: ((j['children'] as List?) ?? const []).map((c) => Category.fromJson(c as Map<String, dynamic>)).toList(),
      );
}

class Venue {
  Venue({required this.name, this.nameMy, this.address, required this.city, this.mapUrl, this.directions, this.directionsMy, this.latitude, this.longitude});
  final String name;
  final String? nameMy;
  final String? address;
  final String city;
  final String? mapUrl;
  final String? directions;
  final String? directionsMy;
  final double? latitude;
  final double? longitude;

  /// Link that opens the venue in a maps app: the organizer's link, else coordinates, else a text search.
  Uri get mapsUri {
    if (mapUrl != null && mapUrl!.isNotEmpty) return Uri.parse(mapUrl!);
    if (latitude != null && longitude != null) {
      return Uri.parse('https://www.google.com/maps/search/?api=1&query=$latitude,$longitude');
    }
    return Uri.parse('https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent([name, address, city].whereType<String>().join(', '))}');
  }

  factory Venue.fromJson(Map<String, dynamic> j) => Venue(
        name: j['name'] as String,
        nameMy: j['nameMy'] as String?,
        address: j['address'] as String?,
        city: j['city'] as String,
        mapUrl: j['mapUrl'] as String?,
        directions: j['directions'] as String?,
        directionsMy: j['directionsMy'] as String?,
        latitude: (j['latitude'] as num?)?.toDouble(),
        longitude: (j['longitude'] as num?)?.toDouble(),
      );
}

class ScheduleItem {
  ScheduleItem({required this.title, this.titleMy, this.description, this.descriptionMy, this.location, required this.startsAt, required this.endsAt});
  final String title;
  final String? titleMy;
  final String? description;
  final String? descriptionMy;
  final String? location;
  final DateTime startsAt;
  final DateTime endsAt;

  factory ScheduleItem.fromJson(Map<String, dynamic> j) => ScheduleItem(
        title: j['title'] as String,
        titleMy: j['titleMy'] as String?,
        description: j['description'] as String?,
        descriptionMy: j['descriptionMy'] as String?,
        location: j['location'] as String?,
        startsAt: _dt(j['startsAt']),
        endsAt: _dt(j['endsAt']),
      );
}

class Performer {
  Performer({required this.name, this.nameMy, this.role, this.roleMy, this.bio, this.bioMy, this.photoUrl});
  final String name;
  final String? nameMy;
  final String? role;
  final String? roleMy;
  final String? bio;
  final String? bioMy;
  final String? photoUrl;

  factory Performer.fromJson(Map<String, dynamic> j) => Performer(
        name: j['name'] as String,
        nameMy: j['nameMy'] as String?,
        role: j['role'] as String?,
        roleMy: j['roleMy'] as String?,
        bio: j['bio'] as String?,
        bioMy: j['bioMy'] as String?,
        photoUrl: j['photoUrl'] as String?,
      );
}

class GalleryImage {
  GalleryImage({required this.url, this.caption, this.captionMy});
  final String url;
  final String? caption;
  final String? captionMy;
  factory GalleryImage.fromJson(Map<String, dynamic> j) =>
      GalleryImage(url: j['url'] as String, caption: j['caption'] as String?, captionMy: j['captionMy'] as String?);
}

class Faq {
  Faq({required this.question, this.questionMy, required this.answer, this.answerMy});
  final String question;
  final String? questionMy;
  final String answer;
  final String? answerMy;
  factory Faq.fromJson(Map<String, dynamic> j) =>
      Faq(question: j['question'] as String, questionMy: j['questionMy'] as String?, answer: j['answer'] as String, answerMy: j['answerMy'] as String?);
}

/// Bilingual practical-info text pair; empty strings count as missing.
class LocalizedText {
  const LocalizedText(this.en, this.my);
  final String? en;
  final String? my;
  bool get isEmpty => (en == null || en!.isEmpty) && (my == null || my!.isEmpty);
  String of(String lang) => pickLang(lang, (en?.isEmpty ?? true) ? null : en, (my?.isEmpty ?? true) ? null : my);
}

class TicketType {
  TicketType({
    required this.id,
    required this.name,
    this.nameMy,
    required this.priceMmk,
    required this.quota,
    required this.remaining,
    required this.maxPerOrder,
  });
  final String id;
  final String name;
  final String? nameMy;
  final int priceMmk;
  final int quota;
  final int remaining;
  final int maxPerOrder;

  bool get isFree => priceMmk == 0;
  bool get soldOut => remaining <= 0;

  factory TicketType.fromJson(Map<String, dynamic> j) => TicketType(
        id: j['id'] as String,
        name: j['name'] as String,
        nameMy: j['nameMy'] as String?,
        priceMmk: (j['priceMmk'] as num).toInt(),
        quota: (j['quota'] as num).toInt(),
        remaining: (j['remaining'] as num).toInt(),
        maxPerOrder: (j['maxPerOrder'] as num).toInt(),
      );
}

class EventSummary {
  EventSummary({
    required this.id,
    required this.slug,
    required this.status,
    required this.title,
    this.titleMy,
    this.summary,
    this.summaryMy,
    this.description,
    this.descriptionMy,
    this.coverImageUrl,
    required this.format,
    required this.isFree,
    this.minPriceMmk,
    required this.startsAt,
    required this.endsAt,
    required this.categoryName,
    this.categoryNameMy,
    this.venue,
    required this.organizerName,
    required this.organizerVerified,
    this.organizerSlug,
    this.organizerLogoUrl,
    required this.ticketTypes,
    required this.soldOut,
    this.ageMin,
    this.dressCode = const LocalizedText(null, null),
    this.languages = const LocalizedText(null, null),
    this.parking = const LocalizedText(null, null),
    this.accessibility = const LocalizedText(null, null),
    this.whatToBring = const LocalizedText(null, null),
    this.terms = const LocalizedText(null, null),
    this.refundPolicy = const LocalizedText(null, null),
    this.schedule = const [],
    this.performers = const [],
    this.gallery = const [],
    this.faqs = const [],
  });

  final String id;
  final String slug;
  final String status;
  final String title;
  final String? titleMy;
  final String? summary;
  final String? summaryMy;
  final String? description;
  final String? descriptionMy;
  final String? coverImageUrl;
  final String format;
  final bool isFree;
  final int? minPriceMmk;
  final DateTime startsAt;
  final DateTime endsAt;
  final String categoryName;
  final String? categoryNameMy;
  final Venue? venue;
  final String organizerName;
  final bool organizerVerified;
  final String? organizerSlug;
  final String? organizerLogoUrl;
  final List<TicketType> ticketTypes;
  final bool soldOut;
  final int? ageMin;
  final LocalizedText dressCode;
  final LocalizedText languages;
  final LocalizedText parking;
  final LocalizedText accessibility;
  final LocalizedText whatToBring;
  final LocalizedText terms;
  final LocalizedText refundPolicy;
  final List<ScheduleItem> schedule;
  final List<Performer> performers;
  final List<GalleryImage> gallery;
  final List<Faq> faqs;

  bool get hasPracticalInfo =>
      ageMin != null || !dressCode.isEmpty || !languages.isEmpty || !parking.isEmpty || !accessibility.isEmpty || !whatToBring.isEmpty;

  factory EventSummary.fromJson(Map<String, dynamic> j) {
    final cat = j['category'] as Map<String, dynamic>;
    final org = j['organization'] as Map<String, dynamic>;
    return EventSummary(
      id: j['id'] as String,
      slug: j['slug'] as String,
      status: j['status'] as String,
      title: j['title'] as String,
      titleMy: j['titleMy'] as String?,
      summary: j['summary'] as String?,
      summaryMy: j['summaryMy'] as String?,
      description: j['description'] as String?,
      descriptionMy: j['descriptionMy'] as String?,
      coverImageUrl: j['coverImageUrl'] as String?,
      format: j['format'] as String,
      isFree: j['isFree'] as bool,
      minPriceMmk: (j['minPriceMmk'] as num?)?.toInt(),
      startsAt: _dt(j['startsAt']),
      endsAt: _dt(j['endsAt']),
      categoryName: cat['nameEn'] as String,
      categoryNameMy: cat['nameMy'] as String?,
      venue: j['venue'] == null ? null : Venue.fromJson(j['venue'] as Map<String, dynamic>),
      organizerName: org['name'] as String,
      organizerVerified: org['kycStatus'] == 'APPROVED',
      organizerSlug: org['slug'] as String?,
      organizerLogoUrl: org['logoUrl'] as String?,
      ageMin: (j['ageMin'] as num?)?.toInt(),
      dressCode: LocalizedText(j['dressCode'] as String?, j['dressCodeMy'] as String?),
      languages: LocalizedText(j['languages'] as String?, j['languagesMy'] as String?),
      parking: LocalizedText(j['parking'] as String?, j['parkingMy'] as String?),
      accessibility: LocalizedText(j['accessibility'] as String?, j['accessibilityMy'] as String?),
      whatToBring: LocalizedText(j['whatToBring'] as String?, j['whatToBringMy'] as String?),
      terms: LocalizedText(j['terms'] as String?, j['termsMy'] as String?),
      refundPolicy: LocalizedText(j['refundPolicy'] as String?, j['refundPolicyMy'] as String?),
      schedule: ((j['sessions'] as List?) ?? const []).map((x) => ScheduleItem.fromJson(x as Map<String, dynamic>)).toList(),
      performers: ((j['performers'] as List?) ?? const []).map((x) => Performer.fromJson(x as Map<String, dynamic>)).toList(),
      gallery: ((j['media'] as List?) ?? const []).map((x) => GalleryImage.fromJson(x as Map<String, dynamic>)).toList(),
      faqs: ((j['faqs'] as List?) ?? const []).map((x) => Faq.fromJson(x as Map<String, dynamic>)).toList(),
      ticketTypes: ((j['ticketTypes'] as List?) ?? const []).map((t) => TicketType.fromJson(t as Map<String, dynamic>)).toList(),
      soldOut: (j['soldOut'] as bool?) ?? false,
    );
  }
}

class EventPage {
  EventPage({required this.items, required this.page, required this.total, required this.limit});
  final List<EventSummary> items;
  final int page;
  final int total;
  final int limit;
  bool get hasMore => page * limit < total;

  factory EventPage.fromJson(Map<String, dynamic> j) => EventPage(
        items: (j['items'] as List).map((e) => EventSummary.fromJson(e as Map<String, dynamic>)).toList(),
        page: (j['page'] as num).toInt(),
        total: (j['total'] as num).toInt(),
        limit: (j['limit'] as num).toInt(),
      );
}

/// A ticket the signed-in user holds. Stored as JSON for offline use, so keep [toJson] in sync.
class MyTicket {
  MyTicket({
    required this.id,
    required this.status,
    required this.ticketTypeName,
    this.ticketTypeNameMy,
    required this.eventId,
    required this.eventTitle,
    this.eventTitleMy,
    required this.startsAt,
    required this.endsAt,
    this.venueName,
    this.venueCity,
    this.coverImageUrl,
    required this.organizer,
    this.qr,
    this.canTransfer = false,
  });

  final String id;
  final String status;
  final String ticketTypeName;
  final String? ticketTypeNameMy;
  final String eventId;
  final String eventTitle;
  final String? eventTitleMy;
  final DateTime startsAt;
  final DateTime endsAt;
  final String? venueName;
  final String? venueCity;
  final String? coverImageUrl;
  final String organizer;
  final String? qr;

  /// The holder may send this ticket to someone else (organizer allows it, not used, not too close to the start).
  final bool canTransfer;

  bool get isUpcoming => endsAt.isAfter(DateTime.now());

  factory MyTicket.fromApi(Map<String, dynamic> j) {
    final tt = j['ticketType'] as Map<String, dynamic>;
    final e = j['event'] as Map<String, dynamic>;
    final venue = e['venue'] as Map<String, dynamic>?;
    return MyTicket(
      id: j['id'] as String,
      status: j['status'] as String,
      ticketTypeName: tt['name'] as String,
      ticketTypeNameMy: tt['nameMy'] as String?,
      eventId: e['id'] as String,
      eventTitle: e['title'] as String,
      eventTitleMy: e['titleMy'] as String?,
      startsAt: _dt(e['startsAt']),
      endsAt: _dt(e['endsAt']),
      venueName: venue?['name'] as String?,
      venueCity: venue?['city'] as String?,
      coverImageUrl: e['coverImageUrl'] as String?,
      organizer: e['organization'] as String,
      qr: j['qr'] as String?,
      canTransfer: j['canTransfer'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'status': status,
        'ticketTypeName': ticketTypeName,
        'ticketTypeNameMy': ticketTypeNameMy,
        'eventId': eventId,
        'eventTitle': eventTitle,
        'eventTitleMy': eventTitleMy,
        'startsAt': startsAt.toIso8601String(),
        'endsAt': endsAt.toIso8601String(),
        'venueName': venueName,
        'venueCity': venueCity,
        'coverImageUrl': coverImageUrl,
        'organizer': organizer,
        'qr': qr,
        'canTransfer': canTransfer,
      };

  factory MyTicket.fromJson(Map<String, dynamic> j) => MyTicket(
        id: j['id'] as String,
        status: j['status'] as String,
        ticketTypeName: j['ticketTypeName'] as String,
        ticketTypeNameMy: j['ticketTypeNameMy'] as String?,
        eventId: j['eventId'] as String,
        eventTitle: j['eventTitle'] as String,
        eventTitleMy: j['eventTitleMy'] as String?,
        startsAt: _dt(j['startsAt']),
        endsAt: _dt(j['endsAt']),
        venueName: j['venueName'] as String?,
        venueCity: j['venueCity'] as String?,
        coverImageUrl: j['coverImageUrl'] as String?,
        organizer: j['organizer'] as String,
        qr: j['qr'] as String?,
        canTransfer: j['canTransfer'] as bool? ?? false,
      );
}

class Me {
  Me({required this.id, this.displayName, this.phone});
  final String id;
  final String? displayName;
  final String? phone;

  factory Me.fromJson(Map<String, dynamic> j) => Me(id: j['id'] as String, displayName: j['displayName'] as String?, phone: j['phone'] as String?);
}

/// Unused but kept for symmetry with the API's nullable dates.
DateTime? parseNullableDate(Object? v) => _dtn(v);

/// Public organizer page.
class OrganizerProfile {
  OrganizerProfile({
    required this.name,
    required this.slug,
    this.description,
    this.descriptionMy,
    this.logoUrl,
    this.website,
    this.facebookUrl,
    this.contactEmail,
    this.contactPhone,
    required this.verified,
    required this.events,
  });
  final String name;
  final String slug;
  final String? description;
  final String? descriptionMy;
  final String? logoUrl;
  final String? website;
  final String? facebookUrl;
  final String? contactEmail;
  final String? contactPhone;
  final bool verified;
  final List<EventSummary> events;

  factory OrganizerProfile.fromJson(Map<String, dynamic> j) => OrganizerProfile(
        name: j['name'] as String,
        slug: j['slug'] as String,
        description: j['description'] as String?,
        descriptionMy: j['descriptionMy'] as String?,
        logoUrl: j['logoUrl'] as String?,
        website: j['website'] as String?,
        facebookUrl: j['facebookUrl'] as String?,
        contactEmail: j['contactEmail'] as String?,
        contactPhone: j['contactPhone'] as String?,
        verified: j['verified'] as bool,
        events: (j['events'] as List).map((e) => EventSummary.fromJson(e as Map<String, dynamic>)).toList(),
      );
}

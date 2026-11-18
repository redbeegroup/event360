import 'dart:convert';

import 'package:event360_ticketing/event360_ticketing.dart';
import 'package:test/test.dart';

/// Test vector produced by the API's own TicketTokenService (apps/api/src/modules/tickets/ticket-token.service.ts):
/// proves a QR signed by the server verifies in the Dart verifier the crew app will use offline.
const apiPublicKeyBase64 = 'K/E/REKJTd6qNAz8D+kxUNLRtnyYD93CjkkV7s4Ncbw=';
const apiToken = 'eyJ0aWQiOiIwYjZmM2MyZS0xMTExLTRhNWItOWM4ZC0xMjM0NTY3ODlhYmMiLCJlaWQiOiI5YTFlMmYzZC0yMjIyLTRiNmMtOGQ5ZS1hYmNkZWZhYmNkZWYiLCJ0dCI6IjdjOGQ5ZTBmLTMzMzMtNGM3ZC05ZTBmLWZlZGNiYWZlZGNiYSIsInYiOjF9.U9loAuSTYEYmp2zxEnT7_8WkkdVMM49Nw3_0gMJ2gUc2nOdpbOsVIZ5RJmAOD1xOafozITDP5APVKaEckiUADw';

void main() {
  final verifier = OfflineTicketVerifier(base64.decode(apiPublicKeyBase64));

  test('verifies a QR token issued by the API', () async {
    final claims = await verifier.verify(apiToken);
    expect(claims, isNotNull);
    expect(claims!.ticketId, '0b6f3c2e-1111-4a5b-9c8d-123456789abc');
    expect(claims.eventId, '9a1e2f3d-2222-4b6c-8d9e-abcdefabcdef');
    expect(claims.ticketTypeId, '7c8d9e0f-3333-4c7d-9e0f-fedcbafedcba');
    expect(claims.version, 1);
  });

  test('rejects the API token after any change', () async {
    final parts = apiToken.split('.');
    final forged = base64Url.encode(utf8.encode(jsonEncode({'tid': 'other', 'eid': 'x', 'tt': 'y', 'v': 1}))).replaceAll('=', '');
    expect(await verifier.verify('$forged.${parts[1]}'), isNull);
    expect(await verifier.verify('${parts[0]}.${parts[1].substring(0, parts[1].length - 2)}AA'), isNull);
  });
}

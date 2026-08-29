import 'package:flutter_contacts/flutter_contacts.dart' as fc;
import 'package:url_launcher/url_launcher.dart';

/// One contact reduced to what Mobina needs for voice commands.
class ContactSummary {
  const ContactSummary({required this.name, required this.number});

  final String name;
  final String number;
}

/// Reads the device contact book (via flutter_contacts) and performs the
/// fuzzy name matching used by Mobina's "call a contact" voice command.
///
/// All matching/normalization helpers are pure and unit-tested.
class ContactsService {
  const ContactsService();

  /// Requests read permission (system dialog on first use). True when the
  /// contact book can be read afterwards.
  Future<bool> ensurePermission() async {
    try {
      final status =
          await fc.FlutterContacts.permissions.request(fc.PermissionType.read);
      return status == fc.PermissionStatus.granted ||
          status == fc.PermissionStatus.limited;
    } catch (_) {
      return false;
    }
  }

  Future<bool> hasPermission() async {
    try {
      return await fc.FlutterContacts.permissions.has(fc.PermissionType.read);
    } catch (_) {
      return false;
    }
  }

  /// All contacts with at least one phone number (first/primary number).
  Future<List<ContactSummary>> list() async {
    final contacts = await fc.FlutterContacts.getAll(
      properties: {fc.ContactProperty.phone},
    );
    final out = <ContactSummary>[];
    for (final c in contacts) {
      final name = (c.displayName ?? '').trim();
      if (name.isEmpty) continue;
      final phones =
          c.phones.where((p) => p.number.trim().isNotEmpty).toList();
      if (phones.isEmpty) continue;
      final primary = phones.firstWhere(
        (p) => p.isPrimary == true,
        orElse: () => phones.first,
      );
      out.add(ContactSummary(name: name, number: primary.number));
    }
    return out;
  }

  /// Looks up [query] in the contact list.
  ///
  /// Score order: exact normalized match > name contains query > query
  /// contains name; among equals the shorter (more specific) name wins.
  ContactSummary? lookup(List<ContactSummary> contacts, String query) {
    final q = normalizeName(query);
    if (q.isEmpty) return null;
    ContactSummary? best;
    var bestScore = -1;
    for (final c in contacts) {
      final n = normalizeName(c.name);
      if (n.isEmpty) continue;
      final int score;
      if (n == q) {
        score = 1000;
      } else if (n.contains(q)) {
        score = 500 + (100 - n.length);
      } else if (q.contains(n)) {
        score = 300 + (100 - n.length);
      } else {
        continue;
      }
      if (score > bestScore) {
        bestScore = score;
        best = c;
      }
    }
    return best;
  }

  /// Normalizes a Persian/Latin name for comparison: strips ZWNJ and
  /// punctuation, unifies ي/ی ك/ك أ/إ/آ/ا, lowercases.
  static String normalizeName(String s) {
    return s.trim()
        .replaceAll('\u200C', '') // ZWNJ (half space)
        .replaceAll('ي', 'ی')
        .replaceAll('ك', 'ک')
        .replaceAll('أ', 'ا')
        .replaceAll('إ', 'ا')
        .replaceAll('آ', 'ا')
        .replaceAll('ـ', '')
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\u0600-\u06FF]'), '');
  }

  /// Opens the dialer with [number] pre-filled (user taps call).
  Future<void> dial(String number) async {
    final digits = number.replaceAll(RegExp(r'[^0-9+]'), '');
    await launchUrl(Uri.parse('tel:$digits'),
        mode: LaunchMode.platformDefault);
  }
}

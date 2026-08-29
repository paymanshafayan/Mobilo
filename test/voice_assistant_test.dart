import 'package:flutter_test/flutter_test.dart';
import 'package:mobilo/core/fa.dart';
import 'package:mobilo/services/contacts_service.dart';
import 'package:mobilo/services/voice_assistant.dart';

void main() {
  group('textAfterWakeWord', () {
    test('returns the command after the wake word', () {
      expect(
        textAfterWakeWord('مبینا شماره مامان را بگیر'),
        'شماره مامان را بگیر',
      );
    });

    test('empty after == wake word only', () {
      expect(textAfterWakeWord('مبینا'), '');
    });

    test('null when the wake word is absent', () {
      expect(textAfterWakeWord('سلام چطوری'), isNull);
    });

    test('latin spelling also works', () {
      expect(textAfterWakeWord('mobina show battery'), 'show battery');
    });
  });

  group('ttsReadyText', () {
    test('strips urls and markdown', () {
      expect(
        ttsReadyText('دانلود: [فایل](https://x.com/a.pdf) و *تأکید*'),
        'دانلود: فایل و تأکید',
      );
    });

    test('truncates long text at a sentence boundary', () {
      final long = List.generate(
          60, (i) => 'جمله‌ی شماره $i که کمی طولانی است برای خواندن بلند.')
          .join(' ');
      final out = ttsReadyText(long);
      expect(out.length, lessThanOrEqualTo(460));
      expect(out, isNot(endsWith(' ')));
    });
  });

  group('MobinaIntent.parse', () {
    test('parses a clean JSON object', () {
      final intent = MobinaIntent.parse(
          '{"action":"call_contact","target":"مامان","query":null,"url":null}');
      expect(intent.action, 'call_contact');
      expect(intent.target, 'مامان');
    });

    test('extracts JSON embedded in chatter', () {
      final intent = MobinaIntent.parse(
          'حتماً!\n```json\n{"action": "search_web", "query": "اخبار باتری"}\n```');
      expect(intent.action, 'search_web');
      expect(intent.query, 'اخبار باتری');
    });

    test('falls back to chat on garbage', () {
      expect(MobinaIntent.parse('هیچ JSON ای نیست').action, 'chat');
      expect(MobinaIntent.parse('{"action":"explode"}').action, 'chat');
    });
  });

  group('faDigits', () {
    test('converts phone number digits', () {
      expect(faDigits('0912-3456789'), '۰۹۱۲-۳۴۵۶۷۸۹');
      expect(faDigits('abc123'), 'abc۱۲۳');
    });
  });

  group('ContactsService matching', () {
    final contacts = [
      const ContactSummary(name: 'مامان', number: '09121111111'),
      const ContactSummary(name: 'پدر', number: '09122222222'),
      const ContactSummary(name: 'محمد موسوی', number: '09123333333'),
      const ContactSummary(name: 'موسوی', number: '09124444444'),
    ];

    test('exact normalized match', () {
      expect(
          ContactsService().lookup(contacts, 'مامان')?.number, '09121111111');
    });

    test('partial (contains) match', () {
      expect(
          ContactsService().lookup(contacts, 'موسوی')?.number, '09124444444');
      expect(
          ContactsService().lookup(contacts, 'محمد موسوی')?.number, '09123333333');
    });

    test('yae/alef variants normalize', () {
      final cs = [const ContactSummary(name: 'علي', number: '09120000000')];
      expect(ContactsService().lookup(cs, 'علی')?.number, '09120000000');
    });

    test('no match', () {
      expect(ContactsService().lookup(contacts, 'پسرخاله'), isNull);
    });
  });
}

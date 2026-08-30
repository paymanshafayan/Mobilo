import 'package:flutter_test/flutter_test.dart';
import 'package:mobilo/services/ai_client.dart';
import 'package:mobilo/services/download_service.dart';

void main() {
  group('SseLineParser', () {
    test('parses payloads split across chunks', () {
      final parser = SseLineParser();
      // First chunk ends mid-payload (no blank line yet -> no event is
      // complete).
      expect(parser.feed('data: {"a":1}\nda'), isEmpty);
      // Second chunk completes the second payload.
      expect(parser.feed('ta: {"a":2}\n\n'), ['{"a":1}', '{"a":2}']);
    });

    test('ignores [DONE] and non-data lines', () {
      final parser = SseLineParser();
      expect(
        parser.feed(': comment\ndata: {"x":1}\ndata: [DONE]\n\n'),
        ['{"x":1}'],
      );
    });
  });

  test('AiClient.deltaContent is null-safe', () {
    expect(
      AiClient.deltaContent(
          '{"choices":[{"delta":{"content":"سلام"}}]}'),
      'سلام',
    );
    expect(AiClient.deltaContent('{"choices":[]}'), isNull);
    expect(AiClient.deltaContent('not-json'), isNull);
  });

  group('extractFileUrls', () {
    test('finds file-like urls with query strings', () {
      final urls = extractFileUrls(
        'دانلود: https://example.com/files/report.pdf و https://ex.org/a.zip?token=123\nمتن دیگر',
      );
      expect(urls, [
        'https://example.com/files/report.pdf',
        'https://ex.org/a.zip?token=123',
      ]);
    });

    test('ignores plain web links', () {
      expect(extractFileUrls('بیشتر بخوانید: https://example.com/page'), isEmpty);
    });

    test('dedupes and limits results', () {
      final urls = extractFileUrls(
        'https://a.com/x.pdf https://a.com/x.pdf https://b.com/y.doc '
        'https://c.com/z.txt https://d.com/w.rar https://e.com/v.mp4',
        limit: 3,
      );
      expect(urls, [
        'https://a.com/x.pdf',
        'https://b.com/y.doc',
        'https://c.com/z.txt',
      ]);
    });
  });

  test('fileNameFromUrl', () {
    expect(fileNameFromUrl('https://x.com/a/b/Report.pdf'), 'Report.pdf');
    expect(fileNameFromUrl('https://x.com/?file=1'), startsWith('download-'));
  });
}

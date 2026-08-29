import 'dart:async';
import 'dart:io';

import 'package:cross_file/cross_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// URLs that look like downloadable files (by extension).
final RegExp fileUrlPattern = RegExp(
  r'''https?://[^\s()"\']+\.(?:pdf|zip|apk|doc|docx|xls|xlsx|ppt|pptx|txt|csv|json|mp3|mp4|mov|png|jpe?g|gif|webp|tar|gz|7z|rar|deb|xml|ya?ml|ipynb|jar|whl|iso|dmg|exe)(?:\?[^\s()"\']*)?''',
  caseSensitive: false,
);

/// Extracts unique, file-like URLs from text (up to [limit]).
List<String> extractFileUrls(String text, {int limit = 5}) {
  final seen = <String>{};
  final out = <String>[];
  for (final match in fileUrlPattern.allMatches(text)) {
    final url = match.group(0)!.trim();
    if (seen.add(url) && out.length < limit) {
      out.add(url);
    }
  }
  return out;
}

/// A safe, human-readable file name derived from a URL.
String fileNameFromUrl(String url) {
  final fallback = 'download-${DateTime.now().millisecondsSinceEpoch ~/ 1000}';
  try {
    final uri = Uri.parse(url);
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (segments.isEmpty) return fallback;
    var name = Uri.decodeComponent(segments.last);
    name = name.replaceAll(RegExp(r'[^A-Za-z0-9._\-\u0600-\u06FF]'), '_');
    if (name.isEmpty) return fallback;
    return name;
  } catch (_) {
    return fallback;
  }
}

class DownloadProgress {
  const DownloadProgress(this.receivedBytes, this.totalBytes);

  final int receivedBytes;

  /// Total size in bytes, or null when the server did not report it.
  final int? totalBytes;

  /// 0..1, or null for indeterminate progress.
  double? get fraction =>
      (totalBytes != null && totalBytes! > 0) ? receivedBytes / totalBytes! : null;
}

class DownloadResult {
  const DownloadResult({
    required this.path,
    required this.fileName,
    required this.sizeBytes,
  });

  final String path;
  final String fileName;
  final int sizeBytes;

  String get sizeLabel {
    if (sizeBytes < 1024) return '$sizeBytes B';
    if (sizeBytes < 1024 * 1024) {
      return '${(sizeBytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

/// Downloads file URLs reported by the AI into the app's documents
/// directory (`downloads/` subfolder) and hands them to the system share
/// sheet (the user can open or save them anywhere).
class DownloadService {
  const DownloadService();

  Future<DownloadResult> download({
    required String url,
    void Function(DownloadProgress)? onProgress,
  }) async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/downloads');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    var fileName = fileNameFromUrl(url);
    var file = File('${dir.path}/$fileName');
    var n = 1;
    while (await file.exists()) {
      final dot = fileName.lastIndexOf('.');
      fileName = dot > 0
          ? '${fileName.substring(0, dot)} ($n)${fileName.substring(dot)}'
          : '$fileName ($n)';
      file = File('${dir.path}/$fileName');
      n++;
    }

    final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
    try {
      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close();
      if (response.statusCode != 200) {
        throw Exception('دانلود ناموفق شد (کد ${response.statusCode})');
      }
      final sink = file.openWrite();
      var received = 0;
      await for (final chunk in response) {
        sink.add(chunk);
        received += chunk.length;
        onProgress?.call(DownloadProgress(
            received, response.contentLength > 0 ? response.contentLength : null));
      }
      await sink.flush();
      await sink.close();
      return DownloadResult(path: file.path, fileName: fileName, sizeBytes: received);
    } on Exception catch (e) {
      throw Exception('دانلود ناموفق شد: $e');
    } finally {
      client.close(force: true);
    }
  }

  /// Opens the system share sheet for the file (open / save / send).
  Future<void> share(String path, {String? text}) async {
    await SharePlus.instance.share(
      ShareParams(text: text ?? '', files: [XFile(path)]),
    );
  }
}

import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

class ResumeApiException implements Exception {
  const ResumeApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

class ResumeApi {
  ResumeApi({
    http.Client? client,
    String? baseUrl,
  })  : _client = client ?? http.Client(),
        _baseUrl = (baseUrl ??
                const String.fromEnvironment(
                  'API_BASE_URL',
                  defaultValue: 'http://127.0.0.1:8787',
                ))
            .replaceFirst(RegExp(r'/$'), '');

  final http.Client _client;
  final String _baseUrl;

  void close() => _client.close();

  Future<Map<String, dynamic>> importResume(
    Uint8List bytes,
    String fileName,
  ) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$_baseUrl/api/resume/import'),
    )..files.add(
        http.MultipartFile.fromBytes(
          'resume',
          bytes,
          filename: fileName,
        ),
      );
    final streamed = await _client.send(request).timeout(
          const Duration(seconds: 60),
        );
    final response = await http.Response.fromStream(streamed);
    return _decode(response);
  }

  Future<Map<String, dynamic>> generateWorkDescription({
    required String jobTitle,
    String company = '',
    String location = '',
    String verifiedDetails = '',
  }) {
    return _post('/api/ai/work-description', {
      'jobTitle': jobTitle,
      'company': company,
      'location': location,
      'verifiedDetails': verifiedDetails,
    });
  }

  Future<Map<String, dynamic>> generateProjectDescription({
    required String idea,
    String verifiedDetails = '',
  }) {
    return _post('/api/ai/project-description', {
      'idea': idea,
      'verifiedDetails': verifiedDetails,
    });
  }

  Future<Map<String, dynamic>> generateDocuments({
    required Map<String, dynamic> profile,
    required String jobDescription,
  }) {
    return _post('/api/ai/documents', {
      'profile': profile,
      'jobDescription': jobDescription,
    });
  }

  Future<Map<String, dynamic>> analyzeTailoring({
    required Map<String, dynamic> profile,
    required String jobDescription,
  }) {
    return _post('/api/ai/tailor', {
      'profile': profile,
      'jobDescription': jobDescription,
    });
  }

  Future<Map<String, dynamic>> searchJobs({
    required String query,
    required String countryCode,
    required List<String> locations,
    required Map<String, dynamic> profile,
    int limit = 20,
  }) {
    return _post(
      '/api/jobs/search',
      {
        'query': query,
        'countryCode': countryCode,
        'locations': locations,
        'profile': profile,
        'limit': limit,
      },
      timeout: const Duration(seconds: 90),
    );
  }

  Future<Map<String, dynamic>> scoreAts({
    required String jobDescription,
    required String resumeText,
  }) {
    return _post('/api/ats/score', {
      'jobDescription': jobDescription,
      'resumeText': resumeText,
    });
  }

  Future<String> saveDocumentArchive({
    required String name,
    required Map<String, dynamic> documents,
    required String template,
  }) async {
    final response = await _client
        .post(
          Uri.parse('$_baseUrl/api/documents/export'),
          headers: const {'content-type': 'application/json'},
          body: jsonEncode({
            'name': name,
            'documents': documents,
            'template': template,
          }),
        )
        .timeout(const Duration(seconds: 60));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _errorFromResponse(response);
    }
    final location = await FilePicker.saveFile(
      dialogTitle: 'Save your resume documents',
      fileName: 'resume-package.zip',
      bytes: response.bodyBytes,
    );
    if (location == null) {
      throw const ResumeApiException('Save was cancelled.');
    }
    return location.toString();
  }

  Future<Map<String, dynamic>> connectLinkedIn() async {
    final result = await _post('/api/linkedin/start', const {});
    final state = result['state'];
    final authorizeUrl = result['authorizeUrl'];
    if (state is! String || authorizeUrl is! String) {
      throw const ResumeApiException('LinkedIn sign-in could not be started.');
    }
    final uri = Uri.tryParse(authorizeUrl);
    if (uri == null ||
        !await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      throw const ResumeApiException('Could not open LinkedIn sign-in.');
    }

    final deadline = DateTime.now().add(const Duration(minutes: 5));
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(seconds: 3));
      final response = await _client
          .get(Uri.parse('$_baseUrl/api/linkedin/result/$state'))
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 202) continue;
      return _decode(response);
    }
    throw const ResumeApiException(
        'LinkedIn sign-in timed out. Please try again.');
  }

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> body, {
    Duration timeout = const Duration(seconds: 60),
  }) async {
    final response = await _client
        .post(
          Uri.parse('$_baseUrl$path'),
          headers: const {'content-type': 'application/json'},
          body: jsonEncode(body),
        )
        .timeout(timeout);
    return _decode(response);
  }

  Map<String, dynamic> _decode(http.Response response) {
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! Map<String, dynamic>) {
      throw const ResumeApiException(
          'The server returned an invalid response.');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _errorFromMap(decoded);
    }
    return decoded;
  }

  ResumeApiException _errorFromResponse(http.Response response) {
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is Map<String, dynamic>) return _errorFromMap(decoded);
    } on FormatException {
      // Fall through to the generic HTTP message.
    }
    return ResumeApiException(
        'The server returned HTTP ${response.statusCode}.');
  }

  ResumeApiException _errorFromMap(Map<String, dynamic> response) {
    final message = response['error'];
    return ResumeApiException(
      message is String ? message : 'The request could not be completed.',
    );
  }
}

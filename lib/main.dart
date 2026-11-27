import 'dart:async';
import 'dart:convert';
import 'dart:ui' show AppExitResponse;

import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart'
    show Clipboard, ClipboardData, PlatformException;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'degree.dart';
import 'services/resume_api.dart';

void main() {
  runApp(const ResumeStudioApp());
}

const _ink = Color(0xFF172B3A);
const _muted = Color(0xFF71808C);
const _brand = Color(0xFF236B62);
const _canvas = Color(0xFFF4F7F6);
const _line = Color(0xFFE2E9E7);
const _documentStyles = [
  ('modern', 'Modern'),
  ('classic', 'Classic'),
  ('editorial', 'Editorial'),
];

class ResumeStudioApp extends StatelessWidget {
  const ResumeStudioApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Resume Studio',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: _canvas,
        colorScheme: ColorScheme.fromSeed(
          seedColor: _brand,
          primary: _brand,
          surface: Colors.white,
        ),
        textTheme: const TextTheme(
          headlineMedium: TextStyle(
            color: _ink,
            fontSize: 30,
            height: 1.15,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.7,
          ),
          titleLarge: TextStyle(
            color: _ink,
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
          bodyMedium: TextStyle(color: _ink, fontSize: 14, height: 1.5),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          hintStyle: const TextStyle(color: Color(0xFFA0AAA9), fontSize: 14),
          labelStyle: const TextStyle(color: _muted, fontSize: 13),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: _line),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: _line),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: _brand, width: 1.4),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(11),
            ),
          ),
        ),
      ),
      home: const BuilderHome(),
    );
  }
}

class BuilderHome extends StatefulWidget {
  const BuilderHome({super.key});

  @override
  State<BuilderHome> createState() => _BuilderHomeState();
}

class _BuilderHomeState extends State<BuilderHome> {
  static const _applicationsStorageKey = 'resume_studio_applications_v1';
  static const _draftStorageKey = 'resume_studio_draft_v1';
  static const _steps = [
    ('Your profile', Icons.person_outline),
    ('Experience', Icons.work_outline),
    ('Education', Icons.school_outlined),
    ('Target role', Icons.track_changes_outlined),
    ('Review', Icons.description_outlined),
  ];

  int _currentStep = 0;
  String? _resumeFileName;
  PlatformFile? _resumeFile;
  bool _resumeImported = false;
  bool _aiConsentGiven = false;
  bool _working = false;
  bool _searchingJobs = false;
  String? _activeProvider;
  String? _jobSearchProvider;
  String? _jobListingProvider;
  String? _jobSearchMethod;
  Map<String, dynamic>? _atsResult;
  Map<String, dynamic>? _generatedDocuments;
  List<_JobMatch> _jobResults = [];
  final _api = ResumeApi();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _linkedin = TextEditingController();
  final _skills = TextEditingController();
  final _project = TextEditingController();
  final _jobTitle = TextEditingController();
  final _company = TextEditingController();
  final _location = TextEditingController();
  final _salaryRange = TextEditingController();
  final _applicationUrl = TextEditingController();
  final _jobSearchLocations = TextEditingController(
    text: 'Chennai, Coimbatore, Bengaluru',
  );
  final _jobSearchCountry = TextEditingController(text: 'in');
  final _jobDescription = TextEditingController();
  final _tailoringNotes = TextEditingController();
  final List<_ApplicationRecord> _applications = [];
  int _documentStyleIndex = 0;
  String? _lastPackagePath;
  final List<_ExperienceDraft> _experiences = [_ExperienceDraft()];
  final List<_EducationDraft> _educations = [_EducationDraft()];
  late final Future<void> _applicationsReady;

  // Saving stays off until the stored draft has been read, so that an empty or
  // unreadable draft never overwrites it.
  bool _draftReady = false;
  String? _savedDraft;
  bool _draftSaveFailed = false;
  Timer? _draftTimer;
  late final AppLifecycleListener _lifecycle;

  Map<String, TextEditingController> get _draftFields => {
        'name': _name,
        'email': _email,
        'phone': _phone,
        'linkedin': _linkedin,
        'skills': _skills,
        'project': _project,
        'jobTitle': _jobTitle,
        'company': _company,
        'location': _location,
        'salaryRange': _salaryRange,
        'applicationUrl': _applicationUrl,
        'jobSearchLocations': _jobSearchLocations,
        'jobSearchCountry': _jobSearchCountry,
        'jobDescription': _jobDescription,
        'tailoringNotes': _tailoringNotes,
      };

  @override
  void initState() {
    super.initState();
    _applicationsReady = _restoreApplications();
    // Captured before any edits, so an untouched form is never stored.
    final untouched = _encodeDraft();
    _restoreDraft(untouched);
    _draftTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _persistDraft(),
    );
    _lifecycle = AppLifecycleListener(
      onInactive: _persistDraft,
      onExitRequested: () async {
        await _persistDraft();
        return AppExitResponse.exit;
      },
    );
  }

  String _encodeDraft() => jsonEncode({
        for (final field in _draftFields.entries) field.key: field.value.text,
        'documentStyle': _documentStyleIndex,
        'experiences': [for (final item in _experiences) item.toJson()],
        'educations': [for (final item in _educations) item.toJson()],
      });

  Future<void> _restoreDraft(String untouched) async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final encoded = preferences.getString(_draftStorageKey);
      if (!mounted) return;
      if (encoded != null) {
        final draft = jsonDecode(encoded) as Map<String, dynamic>;
        final experiences = (draft['experiences'] as List)
            .map((item) => _ExperienceDraft.fromJson(item))
            .toList();
        final educations = (draft['educations'] as List)
            .map((item) => _EducationDraft.fromJson(item))
            .toList();
        final replaced = <VoidCallback>[
          for (final item in _experiences) item.dispose,
          for (final item in _educations) item.dispose,
        ];
        setState(() {
          for (final field in _draftFields.entries) {
            final value = draft[field.key];
            if (value is String) field.value.text = value;
          }
          final style = draft['documentStyle'];
          if (style is int && style >= 0 && style < _documentStyles.length) {
            _documentStyleIndex = style;
          }
          _experiences
            ..clear()
            ..addAll(experiences.isEmpty ? [_ExperienceDraft()] : experiences);
          _educations
            ..clear()
            ..addAll(educations.isEmpty ? [_EducationDraft()] : educations);
        });
        // Dispose only after the fields have moved to the new controllers.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          for (final dispose in replaced) {
            dispose();
          }
        });
      }
      _savedDraft = encoded ?? untouched;
      _draftReady = true;
    } catch (error) {
      _showMessage(
        'Could not restore your saved draft. Auto-save is off until you use '
        '"Clear saved draft": $error',
      );
    }
  }

  Future<void> _persistDraft() async {
    if (!_draftReady) return;
    final encoded = _encodeDraft();
    if (encoded == _savedDraft) return;
    _savedDraft = encoded;
    try {
      final preferences = await SharedPreferences.getInstance();
      if (!await preferences.setString(_draftStorageKey, encoded)) {
        throw StateError('Local storage declined the save.');
      }
      _draftSaveFailed = false;
    } catch (error) {
      _savedDraft = null;
      if (_draftSaveFailed) return;
      _draftSaveFailed = true;
      _showMessage('Could not save your draft on this device: $error');
    }
  }

  Future<void> _clearDraft() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear saved draft?'),
        content: const Text(
          'This erases every resume and target job field. Your job tracker is '
          'kept. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear draft'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    _draftReady = false;
    try {
      final preferences = await SharedPreferences.getInstance();
      if (!await preferences.remove(_draftStorageKey)) {
        throw StateError('Local storage declined the removal.');
      }
    } catch (error) {
      _draftReady = true;
      _showMessage('Could not clear your saved draft: $error');
      return;
    }
    if (!mounted) return;
    final replaced = <VoidCallback>[
      for (final item in _experiences) item.dispose,
      for (final item in _educations) item.dispose,
    ];
    setState(() {
      for (final controller in _draftFields.values) {
        controller.clear();
      }
      _jobSearchLocations.text = 'Chennai, Coimbatore, Bengaluru';
      _jobSearchCountry.text = 'in';
      _experiences
        ..clear()
        ..add(_ExperienceDraft());
      _educations
        ..clear()
        ..add(_EducationDraft());
      _documentStyleIndex = 0;
      _resumeFile = null;
      _resumeFileName = null;
      _resumeImported = false;
      _atsResult = null;
      _generatedDocuments = null;
      _lastPackagePath = null;
      _jobResults = [];
      _jobSearchProvider = null;
      _jobListingProvider = null;
      _jobSearchMethod = null;
      _activeProvider = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final dispose in replaced) {
        dispose();
      }
    });
    _savedDraft = _encodeDraft();
    _draftReady = true;
    _showMessage('Saved draft cleared.');
  }

  @override
  void dispose() {
    _draftTimer?.cancel();
    _lifecycle.dispose();
    _persistDraft(); // Reads the controllers before they are disposed.
    _phone.dispose();
    _name.dispose();
    _email.dispose();
    _linkedin.dispose();
    _skills.dispose();
    _project.dispose();
    _jobTitle.dispose();
    _company.dispose();
    _location.dispose();
    _salaryRange.dispose();
    _applicationUrl.dispose();
    _jobSearchLocations.dispose();
    _jobSearchCountry.dispose();
    _jobDescription.dispose();
    _tailoringNotes.dispose();
    for (final experience in _experiences) {
      experience.dispose();
    }
    for (final education in _educations) {
      education.dispose();
    }
    _api.close();
    super.dispose();
  }

  Future<void> _restoreApplications() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final encoded = preferences.getString(_applicationsStorageKey);
      if (encoded == null || encoded.isEmpty) return;
      final decoded = jsonDecode(encoded);
      if (decoded is! List) {
        throw const FormatException('Saved job tracker data is not a list.');
      }
      final restored =
          decoded.map(_ApplicationRecord.fromJson).toList(growable: false);
      if (mounted) setState(() => _applications.addAll(restored));
    } catch (error) {
      _showMessage('Could not restore saved job applications: $error');
    }
  }

  Future<void> _persistApplications() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final saved = await preferences.setString(
        _applicationsStorageKey,
        jsonEncode(
          _applications.map((application) => application.toJson()).toList(),
        ),
      );
      if (!saved) throw StateError('Local storage declined the save.');
    } catch (error) {
      _showMessage(
        'Could not save your job tracker locally; it may be lost when the app closes: $error',
      );
    }
  }

  Future<void> _pickResume() async {
    try {
      final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: const ['pdf', 'docx'],
      );
      if (!mounted || file == null) return;
      setState(() {
        _resumeFile = file;
        _resumeFileName = file.name;
        _resumeImported = false;
      });
    } on PlatformException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Could not open the file picker: ${error.message ?? 'Please try again.'}',
          ),
        ),
      );
    }
  }

  Future<bool> _requestAiConsent() async {
    if (_aiConsentGiven) return true;
    final consent = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Review AI data sharing'),
        content: const Text(
          'The information you choose to submit will be sent to the configured '
          'Resume Studio server and one or more enabled AI providers if '
          'fallback is needed. Do not '
          'include secrets or sensitive personal information. Review all '
          'suggestions before using them; AI must not invent your history.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    if (consent == true && mounted) {
      setState(() => _aiConsentGiven = true);
      return true;
    }
    return false;
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _showDraft({
    required String title,
    required Map<String, dynamic> output,
    required TextEditingController destination,
  }) async {
    final draft = output['draft'];
    final questions = output['questions'];
    final suggestions = output['unverifiedSuggestions'];
    if (draft is! String || draft.trim().isEmpty) {
      _showMessage('The AI response did not contain a usable draft.');
      return;
    }
    final useDraft = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SelectableText(draft),
                if (questions is List && questions.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  const Text(
                    'Questions to make this accurate',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  for (final question in questions)
                    if (question is String)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text('• $question'),
                      ),
                ],
                if (suggestions is List && suggestions.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  const Text(
                    'Unverified suggestions — confirm before using',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  for (final suggestion in suggestions)
                    if (suggestion is String)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text('• $suggestion'),
                      ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep editing'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Use draft'),
          ),
        ],
      ),
    );
    if (useDraft == true) {
      destination.text = draft;
      _showMessage('Draft added. Please verify and edit it before using.');
    }
  }

  Future<void> _generateWorkDescription(_ExperienceDraft experience) async {
    if (experience.title.text.trim().isEmpty) {
      _showMessage('Add a job title first.');
      return;
    }
    if (!await _requestAiConsent()) return;
    setState(() => _working = true);
    try {
      final result = await _api.generateWorkDescription(
        jobTitle: experience.title.text.trim(),
        company: experience.company.text.trim(),
        location: experience.location.text.trim(),
        verifiedDetails: experience.description.text.trim(),
      );
      if (!mounted) return;
      final output = result['output'];
      if (output is! Map<String, dynamic>) {
        throw const ResumeApiException('The AI response was incomplete.');
      }
      setState(() => _activeProvider = result['provider'] as String?);
      await _showDraft(
        title: 'Review work experience draft',
        output: output,
        destination: experience.description,
      );
    } catch (error) {
      _showMessage('Could not write this experience: $error');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _generateProjectDescription() async {
    if (_project.text.trim().isEmpty) {
      _showMessage('Describe your project idea first.');
      return;
    }
    if (!await _requestAiConsent()) return;
    setState(() => _working = true);
    try {
      final result = await _api.generateProjectDescription(
        idea: _project.text.trim(),
      );
      if (!mounted) return;
      final output = result['output'];
      if (output is! Map<String, dynamic>) {
        throw const ResumeApiException('The AI response was incomplete.');
      }
      setState(() => _activeProvider = result['provider'] as String?);
      await _showDraft(
        title: 'Review project draft',
        output: output,
        destination: _project,
      );
    } catch (error) {
      _showMessage('Could not write this project: $error');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _importResume() async {
    final file = _resumeFile;
    if (file == null) {
      _showMessage('Choose a readable PDF or DOCX file first.');
      return;
    }
    if (!await _requestAiConsent()) return;
    setState(() => _working = true);
    final importedExperiences = <_ExperienceDraft>[];
    final importedEducation = <_EducationDraft>[];
    try {
      final bytes = await file.readAsBytes();
      final response = await _api.importResume(bytes, file.name);
      if (!mounted) return;
      final output = response['output'];
      if (output is! Map<String, dynamic>) {
        throw const ResumeApiException(
            'The imported resume could not be parsed.');
      }
      final skills = output['skills'] is List
          ? (output['skills'] as List).whereType<String>().toSet().toList()
          : <String>[];
      final entries = output['experiences'];
      if (entries is List) {
        for (final entry in entries.whereType<Map<String, dynamic>>()) {
          final experience = _ExperienceDraft();
          experience.title.text = _stringValue(entry['title']);
          experience.company.text = _stringValue(entry['company']);
          experience.location.text = _stringValue(entry['location']);
          experience.startDate.text = _stringValue(entry['startDate']);
          experience.endDate.text = _stringValue(entry['endDate']);
          experience.description.text = _stringValue(entry['description']);
          experience.currentRole = entry['currentRole'] == true;
          importedExperiences.add(experience);
        }
      }
      final education = output['education'];
      if (education is List) {
        for (final entry in education.whereType<Map<String, dynamic>>()) {
          final item = _EducationDraft();
          item.degree = normalizeDegree(entry['degree']);
          item.degreeName.text = _stringValue(entry['degree']);
          item.fieldOfStudy.text = _stringValue(entry['fieldOfStudy']);
          item.institution.text = _stringValue(entry['institution']);
          item.graduationYear.text = _stringValue(entry['graduationYear']);
          item.project.text = _stringValue(entry['project']);
          importedEducation.add(item);
        }
      }
      final importedProject = importedEducation
          .map((item) => item.project.text)
          .firstWhere((value) => value.trim().isNotEmpty, orElse: () => '');
      final jdTerms = _terms(_jobDescription.text);
      final matchedImportedSkills = skills
          .where((skill) => jdTerms.intersection(_terms(skill)).isNotEmpty)
          .toList();
      final selection = await showDialog<_ResumeImportSelection>(
        context: context,
        barrierDismissible: false,
        builder: (context) => _ResumeImportDialog(
          importedName: _stringValue(output['name']),
          importedEmail: _stringValue(output['email']),
          importedLinkedIn: _stringValue(output['linkedin']),
          importedPhone: _stringValue(output['phone']),
          currentPhone: _phone.text,
          currentName: _name.text,
          currentEmail: _email.text,
          currentLinkedIn: _linkedin.text,
          currentSkills: _skills.text,
          importedSkills: skills,
          matchedSkills: matchedImportedSkills,
          experiences: importedExperiences,
          education: importedEducation,
          currentProject: _project.text,
          importedProject: importedProject,
          currentJobDescription: _jobDescription.text,
          currentTailoringNotes: _tailoringNotes.text,
        ),
      );
      if (!mounted || selection == null) return;

      if (selection.replaceProfile) {
        _setIfNonEmpty(_name, selection.name);
        _setIfNonEmpty(_email, selection.email);
        _setIfNonEmpty(_linkedin, selection.linkedin);
        _setIfNonEmpty(_phone, selection.phone);
      } else {
        if (_phone.text.trim().isEmpty) _setIfNonEmpty(_phone, selection.phone);
        if (_name.text.trim().isEmpty) _setIfNonEmpty(_name, selection.name);
        if (_email.text.trim().isEmpty) _setIfNonEmpty(_email, selection.email);
        if (_linkedin.text.trim().isEmpty) {
          _setIfNonEmpty(_linkedin, selection.linkedin);
        }
      }

      final existingSkills = _skills.text
          .split(',')
          .map((skill) => skill.trim())
          .where((skill) => skill.isNotEmpty)
          .toList();
      _skills.text = _deduplicateStrings([
        if (selection.mergeIntoDraft) ...existingSkills,
        ...selection.skills,
      ]).join(', ');

      final selectedExperiences = selection.experienceIndexes
          .where((index) => index >= 0 && index < importedExperiences.length)
          .map((index) => _copyExperience(importedExperiences[index]))
          .toList();
      if (!selection.mergeIntoDraft) {
        for (final current in _experiences) {
          current.dispose();
        }
        _experiences.clear();
      } else if (_experiences.length == 1 &&
          _experiences.single.title.text.trim().isEmpty &&
          _experiences.single.description.text.trim().isEmpty) {
        _experiences.removeAt(0).dispose();
      }
      for (final imported in selectedExperiences) {
        final duplicate = _experiences.any(
          (existing) =>
              existing.title.text.trim().toLowerCase() ==
                  imported.title.text.trim().toLowerCase() &&
              existing.company.text.trim().toLowerCase() ==
                  imported.company.text.trim().toLowerCase(),
        );
        if (duplicate) {
          imported.dispose();
        } else {
          _experiences.add(imported);
        }
      }
      if (_experiences.isEmpty) _experiences.add(_ExperienceDraft());

      final selectedEducation = selection.educationIndexes
          .where((index) => index >= 0 && index < importedEducation.length)
          .map((index) => _copyEducation(importedEducation[index]))
          .toList();
      if (!selection.mergeIntoDraft) {
        for (final current in _educations) {
          current.dispose();
        }
        _educations.clear();
      } else if (_educations.length == 1 &&
          _educations.single.institution.text.trim().isEmpty) {
        _educations.removeAt(0).dispose();
      }
      for (final imported in selectedEducation) {
        final duplicate = _educations.any(
          (existing) =>
              existing.degree == imported.degree &&
              existing.fieldOfStudy.text.trim().toLowerCase() ==
                  imported.fieldOfStudy.text.trim().toLowerCase() &&
              existing.institution.text.trim().toLowerCase() ==
                  imported.institution.text.trim().toLowerCase(),
        );
        if (duplicate) {
          imported.dispose();
        } else {
          _educations.add(imported);
        }
      }
      if (_educations.isEmpty) _educations.add(_EducationDraft());

      if (selection.includeProject && selection.project.trim().isNotEmpty) {
        if (!selection.mergeIntoDraft || _project.text.trim().isEmpty) {
          _project.text = selection.project.trim();
        }
      }
      _tailoringNotes.text = selection.tailoringNotes.trim();
      setState(() {
        _activeProvider = response['provider'] as String?;
        _atsResult = null;
        _resumeImported = true;
      });
      _showMessage(
        'Resume details imported. Check every field for accuracy before continuing.',
      );
    } catch (error) {
      _showMessage('Could not import this resume: $error');
    } finally {
      for (final experience in importedExperiences) {
        experience.dispose();
      }
      for (final education in importedEducation) {
        education.dispose();
      }
      if (mounted) setState(() => _working = false);
    }
  }

  List<String> _deduplicateStrings(Iterable<String> values) {
    final seen = <String>{};
    return [
      for (final value in values)
        if (value.trim().isNotEmpty && seen.add(value.trim().toLowerCase()))
          value.trim(),
    ];
  }

  _ExperienceDraft _copyExperience(_ExperienceDraft source) {
    final copy = _ExperienceDraft();
    copy.title.text = source.title.text;
    copy.company.text = source.company.text;
    copy.location.text = source.location.text;
    copy.startDate.text = source.startDate.text;
    copy.endDate.text = source.endDate.text;
    copy.description.text = source.description.text;
    copy.currentRole = source.currentRole;
    return copy;
  }

  _EducationDraft _copyEducation(_EducationDraft source) {
    final copy = _EducationDraft();
    copy.degree = source.degree;
    copy.degreeName.text = source.degreeName.text;
    copy.fieldOfStudy.text = source.fieldOfStudy.text;
    copy.institution.text = source.institution.text;
    copy.graduationYear.text = source.graduationYear.text;
    copy.project.text = source.project.text;
    return copy;
  }

  void _setIfNonEmpty(TextEditingController controller, dynamic value) {
    if (value is String && value.trim().isNotEmpty) {
      controller.text = value.trim();
    }
  }

  String _stringValue(dynamic value) => value is String ? value : '';

  Future<void> _connectLinkedIn() async {
    setState(() => _working = true);
    try {
      final profile = await _api.connectLinkedIn();
      if (!mounted) return;
      _setIfNonEmpty(_name, profile['name']);
      _setIfNonEmpty(_email, profile['email']);
      setState(() {});
      _showMessage(
        profile['notice'] is String
            ? profile['notice'] as String
            : 'LinkedIn profile imported.',
      );
    } catch (error) {
      _showMessage('Could not connect LinkedIn: $error');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  String _resumeText() {
    final values = <String>[
      _skills.text,
      _project.text,
      for (final education in _educations)
        '${education.degree} ${education.degreeName.text} '
            '${education.fieldOfStudy.text} ${education.institution.text} '
            '${education.graduationYear.text}',
      for (final experience in _experiences)
        [
          experience.title.text,
          experience.company.text,
          experience.location.text,
          experience.startDate.text,
          experience.currentRole ? 'present' : experience.endDate.text,
          experience.description.text,
        ].join(' '),
    ];
    return values.where((value) => value.trim().isNotEmpty).join('\n');
  }

  Map<String, dynamic> _keywordCoverage({String? resumeText}) {
    final jobTerms = _terms(_jobDescription.text);
    final resumeTerms = _terms(resumeText ?? _resumeText());
    if (jobTerms.isEmpty || resumeTerms.isEmpty) {
      return {
        'score': null,
        'matchedKeywords': <String>[],
        'missingKeywords': <String>[],
      };
    }
    final matched = jobTerms.intersection(resumeTerms).toList()..sort();
    final missing = jobTerms.difference(resumeTerms).toList()..sort();
    return {
      'score': (matched.length * 100 / jobTerms.length).round(),
      'matchedKeywords': matched,
      'missingKeywords': missing,
    };
  }

  Set<String> _terms(String value) {
    const stopWords = {
      'about',
      'after',
      'also',
      'and',
      'are',
      'for',
      'from',
      'have',
      'into',
      'job',
      'our',
      'role',
      'that',
      'the',
      'their',
      'this',
      'with',
      'you',
      'your',
      'will',
      'years',
      'year',
      'work',
      'working',
      'experience',
    };
    return RegExp(r'[a-z][a-z0-9+#.-]{1,}')
        .allMatches(value.toLowerCase())
        .map((match) => match.group(0)!.replaceFirst(RegExp(r'[.-]+$'), ''))
        .where((term) => term.length > 1 && !stopWords.contains(term))
        .toSet();
  }

  Map<String, dynamic> _profileForAi() {
    return {
      'name': _name.text.trim(),
      'email': _email.text.trim(),
      'phone': _phone.text.trim(),
      'linkedin': _linkedin.text.trim(),
      'skills': _skills.text
          .split(',')
          .map((skill) => skill.trim())
          .where((skill) => skill.isNotEmpty)
          .toList(),
      'education': [
        for (final education in _educations)
          if (education.institution.text.trim().isNotEmpty)
            {
              'degree': education.degree,
              'degreeName': education.degreeName.text.trim(),
              'fieldOfStudy': education.fieldOfStudy.text.trim(),
              'institution': education.institution.text.trim(),
              'graduationYear': education.graduationYear.text.trim(),
            },
      ],
      'project': _project.text.trim(),
      'experiences': [
        for (final entry in _experiences.asMap().entries)
          if (entry.value.title.text.trim().isNotEmpty ||
              entry.value.description.text.trim().isNotEmpty)
            {
              'experienceIndex': entry.key,
              'title': entry.value.title.text.trim(),
              'company': entry.value.company.text.trim(),
              'location': entry.value.location.text.trim(),
              'startDate': entry.value.startDate.text.trim(),
              'endDate': entry.value.currentRole
                  ? 'Present'
                  : entry.value.endDate.text.trim(),
              'description': entry.value.description.text.trim(),
            },
      ],
      'target': {
        'jobTitle': _jobTitle.text.trim(),
        'company': _company.text.trim(),
        'location': _location.text.trim(),
        'salaryRange': _salaryRange.text.trim(),
      },
      'tailoringInstructions': _tailoringNotes.text.trim(),
    };
  }

  Future<void> _analyzeTailoring() async {
    if (_jobDescription.text.trim().isEmpty) {
      _showMessage('Add a job description before comparing your resume.');
      return;
    }
    if (!await _requestAiConsent()) return;
    setState(() => _working = true);
    final suggestions = <_ExperienceSuggestion>[];
    try {
      final response = await _api.analyzeTailoring(
        profile: _profileForAi(),
        jobDescription: _jobDescription.text.trim(),
      );
      if (!mounted) return;
      final output = response['output'];
      if (output is! Map<String, dynamic>) {
        throw const ResumeApiException(
            'The comparison response was incomplete.');
      }
      final rawDrafts = output['experienceDrafts'];
      if (rawDrafts is List) {
        for (final draft in rawDrafts.whereType<Map<String, dynamic>>()) {
          final index = draft['experienceIndex'];
          final revised = draft['revisedDescription'];
          if (index is! int ||
              index < 0 ||
              index >= _experiences.length ||
              revised is! String ||
              revised.trim().isEmpty) {
            continue;
          }
          suggestions.add(
            _ExperienceSuggestion(
              experienceIndex: index,
              original: _experiences[index].description.text,
              revised: revised,
              questions: _stringList(draft['questions']),
            ),
          );
        }
      }
      final selection = await showDialog<_TailoringSelection>(
        context: context,
        barrierDismissible: false,
        builder: (context) => _TailoringReviewDialog(
          matchedSkills: _stringList(output['matchedSkills']),
          suggestedSkills: _deduplicateStrings(
            _stringList(output['suggestedSkills']),
          ),
          experienceSuggestions: suggestions,
          recommendations: _stringList(output['recommendations']),
          questions: _stringList(output['questions']),
          currentNotes: _tailoringNotes.text,
        ),
      );
      if (!mounted || selection == null) return;
      for (final suggestion in suggestions) {
        final revised = selection.rewrites[suggestion.experienceIndex];
        if (revised != null && revised.trim().isNotEmpty) {
          _experiences[suggestion.experienceIndex].description.text =
              revised.trim();
        }
      }
      final existingSkills = _skills.text
          .split(',')
          .map((skill) => skill.trim())
          .where((skill) => skill.isNotEmpty);
      _skills.text = _deduplicateStrings([
        ...existingSkills,
        ...selection.skillsToAdd,
      ]).join(', ');
      _tailoringNotes.text = selection.tailoringNotes.trim();
      setState(() {
        _activeProvider = response['provider'] as String?;
        _atsResult = _keywordCoverage();
      });
      _showMessage(
        'Selected changes were applied. Verify every skill and rewrite before using.',
      );
    } catch (error) {
      _showMessage('Could not compare your resume with the JD: $error');
    } finally {
      for (final suggestion in suggestions) {
        suggestion.dispose();
      }
      if (mounted) setState(() => _working = false);
    }
  }

  String _jobSearchQuery() {
    final chosenRole = _jobTitle.text.trim();
    if (chosenRole.isNotEmpty) return chosenRole;
    final recentRole = _experiences
        .map((experience) => experience.title.text.trim())
        .firstWhere((title) => title.isNotEmpty, orElse: () => '');
    final skills = _skills.text
        .split(',')
        .map((skill) => skill.trim())
        .where((skill) => skill.isNotEmpty)
        .take(3);
    return [recentRole, ...skills].where((value) => value.isNotEmpty).join(' ');
  }

  Future<void> _searchJobs({bool keepBusy = false}) async {
    final query = _jobSearchQuery();
    final countryCode = _jobSearchCountry.text.trim().toLowerCase();
    final locations = _jobSearchLocations.text
        .split(',')
        .map((location) => location.trim())
        .where((location) => location.isNotEmpty)
        .toList();
    if (query.isEmpty) {
      _showMessage(
          'Add a target job title or at least one work experience or skill.');
      return;
    }
    if (query.length > 200) {
      _showMessage('Keep the job search query under 200 characters.');
      return;
    }
    if (!RegExp(r'^[a-z]{2}$').hasMatch(countryCode)) {
      _showMessage('Use a two-letter country code, such as in or us.');
      return;
    }
    if (locations.length > 5) {
      _showMessage('Search up to five locations at a time.');
      return;
    }
    if (!await _requestAiConsent()) return;
    setState(() {
      _working = true;
      _searchingJobs = true;
      _jobResults = [];
      _jobSearchProvider = null;
      _jobListingProvider = null;
      _jobSearchMethod = null;
    });
    try {
      final response = await _api.searchJobs(
        query: query,
        countryCode: countryCode,
        locations: locations,
        profile: _profileForAi(),
        limit: 20,
      );
      final rawJobs = response['jobs'];
      if (rawJobs is! List) {
        throw const ResumeApiException(
            'The job search response was incomplete.');
      }
      final jobs = <_JobMatch>[];
      for (final item in rawJobs) {
        if (item is! Map<String, dynamic>) {
          throw const ResumeApiException(
              'The job search returned an invalid listing.');
        }
        jobs.add(_JobMatch.fromJson(item));
      }
      if (!mounted) return;
      setState(() {
        _jobResults = jobs;
        _jobListingProvider = response['listingProvider'] is String
            ? response['listingProvider'] as String
            : null;
        _jobSearchProvider = response['provider'] is String
            ? response['provider'] as String
            : null;
        _jobSearchMethod = response['matchMethod'] is String
            ? response['matchMethod'] as String
            : null;
      });
      _showMessage(
        jobs.isEmpty
            ? 'No matching job listings were found for those filters.'
            : 'Found ${jobs.length} jobs, ranked by resume relevance. Review each listing.',
      );
    } catch (error) {
      _showMessage('Could not search jobs: $error');
    } finally {
      if (mounted) {
        setState(() {
          if (!keepBusy) _working = false;
          _searchingJobs = false;
        });
      }
    }
  }

  Future<void> _selectJob(_JobMatch job) async {
    _jobTitle.text = job.title;
    _company.text = job.company;
    _location.text = job.location;
    _applicationUrl.text = job.postingUrl;
    _jobDescription.text = job.description;
    _salaryRange.text = job.salaryRange;
    if (job.salaryRange.isEmpty) {
      final salary = await _askForSalaryRange();
      if (salary != null) _salaryRange.text = salary;
    }
    if (!mounted) return;
    setState(() {
      _generatedDocuments = null;
      _lastPackagePath = null;
      _atsResult = _keywordCoverage();
      if (_jobSearchProvider != null) _activeProvider = _jobSearchProvider;
    });
    _showMessage(
      'Job selected. ${job.source} may provide only a preview; open the source listing to confirm details before tailoring.',
    );
  }

  Future<String?> _askForSalaryRange() async {
    final controller = TextEditingController();
    try {
      return await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Salary not listed'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'This listing does not provide a salary range. Enter your target '
                'range if you have one, or leave it blank; the app will not guess.',
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                decoration: const InputDecoration(
                  labelText: 'Your target range (optional)',
                  hintText: 'e.g. INR 12-16 lakh per year',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, ''),
              child: const Text('Leave blank'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, controller.text.trim()),
              child: const Text('Use this range'),
            ),
          ],
        ),
      );
    } finally {
      controller.dispose();
    }
  }

  Future<void> _openExternalUrl(String value) async {
    final uri = Uri.tryParse(value);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      _showMessage('This listing does not have a safe HTTPS link.');
      return;
    }
    try {
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        _showMessage('Could not open this job page on the device.');
      }
    } on PlatformException {
      _showMessage('Could not open this job page on the device.');
    }
  }

  Future<void> _showJobDescription(_JobMatch job) async {
    if (job.description.trim().isEmpty) {
      _showMessage(
          'No description preview was provided. Open the advertiser listing.');
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(job.title),
        content: SizedBox(
          width: 620,
          height: MediaQuery.sizeOf(dialogContext).height * 0.6,
          child: SingleChildScrollView(
            child: SelectableText(job.description),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
          FilledButton.tonalIcon(
            onPressed: () {
              Navigator.pop(dialogContext);
              _openExternalUrl(job.postingUrl);
            },
            icon: const Icon(Icons.open_in_new, size: 16),
            label: Text(
              job.source == 'Jobicy'
                  ? 'View Jobicy listing'
                  : 'View full job & apply',
            ),
          ),
        ],
      ),
    );
  }

  List<String> _stringList(dynamic value) {
    if (value is! List) return [];
    return value
        .whereType<String>()
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();
  }

  Future<void> _createDocuments() async {
    if (_name.text.trim().isEmpty) {
      _showMessage('Add your name before creating the documents.');
      return;
    }
    if (_jobDescription.text.trim().isEmpty) {
      _showMessage('Add the target job description before creating documents.');
      return;
    }
    final hasEvidence = _skills.text.trim().isNotEmpty ||
        _educations
            .any((education) => education.institution.text.trim().isNotEmpty) ||
        _project.text.trim().isNotEmpty ||
        _experiences.any(
          (experience) =>
              experience.title.text.trim().isNotEmpty ||
              experience.description.text.trim().isNotEmpty,
        );
    if (!hasEvidence) {
      _showMessage(
        'Add at least one skill, education entry, project, or work experience.',
      );
      return;
    }
    if (!await _requestAiConsent()) return;
    setState(() => _working = true);
    try {
      final profile = _profileForAi();
      final response = await _api.generateDocuments(
        profile: profile,
        jobDescription: _jobDescription.text.trim(),
      );
      if (!mounted) return;
      final output = response['output'];
      if (output is! Map<String, dynamic>) {
        throw const ResumeApiException('The AI response was incomplete.');
      }
      if (['resume', 'cv', 'coverLetter'].any(
        (key) =>
            output[key] is! String || (output[key] as String).trim().isEmpty,
      )) {
        throw const ResumeApiException(
          'The AI response did not contain all requested documents.',
        );
      }
      if (output['applicationKit'] is! String ||
          (output['applicationKit'] as String).trim().isEmpty) {
        throw const ResumeApiException(
          'The AI response did not contain the application and interview kit.',
        );
      }
      final jobMatchScore = output['jobMatchScore'];
      final jobMatchReasons = output['jobMatchReasons'];
      if (jobMatchScore is! num ||
          jobMatchScore < 0 ||
          jobMatchScore > 100 ||
          jobMatchReasons is! List) {
        throw const ResumeApiException(
          'The AI response did not include a valid job match estimate.',
        );
      }
      final approvedDocuments = await _reviewGeneratedDocuments(output);
      if (!mounted || approvedDocuments == null) return;
      final selectedStyle = _documentStyles[_documentStyleIndex];
      final savedPath = await _saveWithRetry(
        approvedDocuments,
        selectedStyle.$1,
      );
      if (!mounted || savedPath == null) return;
      final completedDocuments = <String, dynamic>{
        ...approvedDocuments,
        'jobMatchScore': jobMatchScore.round(),
        'jobMatchReasons': jobMatchReasons
            .whereType<String>()
            .map((reason) => reason.trim())
            .where((reason) => reason.isNotEmpty)
            .take(3)
            .toList(),
      };
      setState(() {
        _activeProvider = response['provider'] as String?;
        _generatedDocuments = completedDocuments;
        _atsResult = _keywordCoverage(
          resumeText: _stringValue(completedDocuments['resume']),
        );
        _lastPackagePath = savedPath;
        _documentStyleIndex =
            (_documentStyleIndex + 1) % _documentStyles.length;
      });
      _showMessage('Eight polished PDF and Word files saved: $savedPath');
      await _searchJobs(keepBusy: true);
      if (!mounted) return;
      await _offerApplicationHandoff();
    } catch (error) {
      _showMessage('Could not create documents: $error');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  /// Keeps the reviewed documents until they are saved or explicitly discarded.
  Future<String?> _saveWithRetry(
    Map<String, dynamic> documents,
    String template,
  ) async {
    while (mounted) {
      try {
        return await _api.saveDocumentArchive(
          name: _name.text.trim(),
          documents: documents,
          template: template,
        );
      } catch (error) {
        if (!mounted) return null;
        final retry = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: const Text('Documents not saved yet'),
            content: Text(
              '$error\nYour reviewed documents are still here. If you discard '
              'them, you will need to generate them again.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Discard'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Try saving again'),
              ),
            ],
          ),
        );
        if (retry != true) return null;
      }
    }
    return null;
  }

  Future<Map<String, dynamic>?> _reviewGeneratedDocuments(
    Map<String, dynamic> documents,
  ) async {
    final resume =
        TextEditingController(text: _stringValue(documents['resume']));
    final cv = TextEditingController(text: _stringValue(documents['cv']));
    final coverLetter =
        TextEditingController(text: _stringValue(documents['coverLetter']));
    final applicationKit =
        TextEditingController(text: _stringValue(documents['applicationKit']));
    try {
      return await showDialog<Map<String, dynamic>>(
        context: context,
        barrierDismissible: false,
        builder: (context) => _DocumentReviewDialog(
          resume: resume,
          cv: cv,
          coverLetter: coverLetter,
          applicationKit: applicationKit,
        ),
      );
    } finally {
      resume.dispose();
      cv.dispose();
      coverLetter.dispose();
      applicationKit.dispose();
    }
  }

  Future<void> _offerApplicationHandoff() async {
    final shouldTrack = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Would you like to continue with this application?'),
        content: const Text(
          'The application kit includes draft answers and interview preparation. '
          'I can save this role to your device and open the job page. '
          'You will review the form and submit it yourself; this app does not '
          'create accounts or send applications.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Not now'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Track this job'),
          ),
        ],
      ),
    );
    if (!mounted || shouldTrack != true) return;
    final application = await _saveCurrentApplication();
    if (!mounted || application == null) return;
    if (application.applicationUrl.isNotEmpty) {
      await _openApplicationPage(application);
    } else {
      _showMessage('Saved on this device. Add an application URL to open it.');
    }
  }

  Future<_ApplicationRecord?> _saveCurrentApplication() async {
    await _applicationsReady;
    if (!mounted) return null;
    final role = _jobTitle.text.trim();
    final company = _company.text.trim();
    if (role.isEmpty || company.isEmpty) {
      _showMessage(
          'Add the job title and company before tracking this application.');
      return null;
    }
    final existing = _applications.where(
      (application) =>
          application.role.toLowerCase() == role.toLowerCase() &&
          application.company.toLowerCase() == company.toLowerCase() &&
          application.applicationUrl == _applicationUrl.text.trim(),
    );
    if (existing.isNotEmpty) {
      _showMessage('This job is already in your tracker.');
      return existing.first;
    }
    final application = _ApplicationRecord(
      role: role,
      company: company,
      location: _location.text.trim(),
      salaryRange: _salaryRange.text.trim(),
      jobDescription: _jobDescription.text.trim(),
      applicationUrl: _applicationUrl.text.trim(),
      packagePath: _lastPackagePath ?? '',
    );
    setState(() => _applications.insert(0, application));
    await _persistApplications();
    _showMessage('Added to your saved application tracker.');
    return application;
  }

  Future<void> _openApplicationPage(_ApplicationRecord application) async {
    final uri = Uri.tryParse(application.applicationUrl);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      _showMessage('Add a valid HTTPS application link to open the job page.');
      return;
    }
    try {
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        _showMessage('Could not open the application page on this device.');
      }
    } on PlatformException {
      _showMessage('Could not open the application page on this device.');
    }
  }

  Future<void> _markApplicationSubmitted(
    _ApplicationRecord application,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Mark this job as applied?'),
        content: Text(
          'Confirm that you personally submitted the application for '
          '${application.role} at ${application.company}.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('I submitted it'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      setState(() => application.status = 'Applied');
      await _persistApplications();
    }
  }

  Future<void> _setApplicationStatus(
    _ApplicationRecord application,
    String status,
  ) async {
    if (status == 'Applied') {
      await _markApplicationSubmitted(application);
      return;
    }
    setState(() => application.status = status);
    await _persistApplications();
  }

  void _goToStep(int index) {
    final nextStep = index.clamp(0, _steps.length - 1).toInt();
    setState(() {
      _currentStep = nextStep;
      if (nextStep == _steps.length - 1) {
        _atsResult = _keywordCoverage();
      } else {
        _generatedDocuments = null;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 980;
        return Scaffold(
          body: SafeArea(
            child: Column(
              children: [
                _TopBar(wide: wide),
                Expanded(
                  child: Row(
                    children: [
                      if (wide) _buildSidebar(),
                      Expanded(
                        child: Column(
                          children: [
                            if (!wide) _buildCompactSteps(),
                            Expanded(
                              child: SingleChildScrollView(
                                padding: EdgeInsets.fromLTRB(
                                  wide ? 44 : 20,
                                  wide ? 34 : 24,
                                  wide ? 44 : 20,
                                  30,
                                ),
                                child: Center(
                                  child: ConstrainedBox(
                                    constraints:
                                        const BoxConstraints(maxWidth: 850),
                                    child: _buildCurrentStep(wide),
                                  ),
                                ),
                              ),
                            ),
                            _buildFooter(wide),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSidebar() {
    return Container(
      width: 256,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(right: BorderSide(color: _line)),
      ),
      padding: const EdgeInsets.fromLTRB(22, 30, 18, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'YOUR RESUME',
            style: TextStyle(
              color: _muted,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 22),
          for (var index = 0; index < _steps.length; index++)
            _StepTile(
              number: index + 1,
              title: _steps[index].$1,
              icon: _steps[index].$2,
              selected: index == _currentStep,
              complete: index < _currentStep,
              onTap: () => _goToStep(index),
            ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFF2F7F5),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.lock_outline, color: _brand, size: 18),
                SizedBox(width: 9),
                Expanded(
                  child: Text(
                    'Your draft and job tracker are saved on this device.',
                    style: TextStyle(color: _muted, fontSize: 12, height: 1.5),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactSteps() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'STEP ${_currentStep + 1} OF ${_steps.length}',
                style: const TextStyle(
                  color: _muted,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1,
                ),
              ),
              const Spacer(),
              Text(
                _steps[_currentStep].$1,
                style: const TextStyle(
                  color: _brand,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 11),
          ClipRRect(
            borderRadius: BorderRadius.circular(5),
            child: LinearProgressIndicator(
              value: (_currentStep + 1) / _steps.length,
              minHeight: 5,
              backgroundColor: _line,
              color: _brand,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCurrentStep(bool wide) {
    switch (_currentStep) {
      case 0:
        return _buildProfileStep(wide);
      case 1:
        return _buildExperienceStep();
      case 2:
        return _buildEducationStep(wide);
      case 3:
        return _buildTargetStep();
      default:
        return _buildReviewStep(wide);
    }
  }

  Widget _buildProfileStep(bool wide) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Eyebrow('A STRONG FIRST IMPRESSION STARTS HERE'),
        const SizedBox(height: 12),
        Text('Let’s build a resume that feels like you.',
            style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 10),
        const Text(
          'Start with the basics. You can add a past resume for reference, '
          'then review every detail before anything is shared.',
          style: TextStyle(color: _muted, fontSize: 15, height: 1.55),
        ),
        const SizedBox(height: 28),
        _Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SectionHeading(
                title: 'About you',
                subtitle: 'A few details for your resume header.',
              ),
              const SizedBox(height: 20),
              _field(_name, 'Full name', hint: 'e.g. Alex Morgan'),
              const SizedBox(height: 15),
              _field(_email, 'Email address', hint: 'alex@email.com'),
              const SizedBox(height: 15),
              _field(
                _phone,
                'Phone number',
                hint: 'e.g. +91 98765 43210',
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 15),
              _field(
                _linkedin,
                'LinkedIn profile (optional)',
                hint: 'https://linkedin.com/in/your-profile',
              ),
              const SizedBox(height: 15),
              _field(
                _skills,
                'Skills (comma-separated)',
                hint: 'e.g. project planning, Figma, Python',
                maxLines: 2,
              ),
              const SizedBox(height: 8),
              const Text(
                'LinkedIn permits only limited profile fields through sign-in. '
                'Skills and work history may need to be added from your own '
                'profile export.',
                style: TextStyle(color: _muted, fontSize: 12, height: 1.45),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _working ? null : _connectLinkedIn,
                  icon: const Icon(Icons.link, size: 17),
                  label: const Text('Connect LinkedIn'),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        _Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: const Color(0xFFEAF3F0),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child:
                        const Icon(Icons.upload_file_outlined, color: _brand),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _resumeFileName ?? 'Have an old resume?',
                          style: const TextStyle(
                            color: _ink,
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Choose a PDF or DOCX file to import.',
                          style: TextStyle(color: _muted, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton(
                    onPressed: _working ? null : _pickResume,
                    child: Text(
                        _resumeFileName == null ? 'Choose file' : 'Replace'),
                  ),
                ],
              ),
              if (_resumeFileName != null) ...[
                const SizedBox(height: 12),
                FilledButton.tonalIcon(
                  onPressed: _working ? null : _importResume,
                  icon: const Icon(Icons.drive_file_move_outline, size: 18),
                  label: const Text('Read and import details'),
                ),
                const SizedBox(height: 6),
                const Text(
                  'The file is sent to your configured server and AI provider(s) '
                  'to extract details. Review every imported field.',
                  style: TextStyle(color: _muted, fontSize: 12, height: 1.4),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        TextButton.icon(
          onPressed: _working ? null : _clearDraft,
          icon: const Icon(Icons.delete_sweep_outlined, size: 17),
          label: const Text('Clear saved draft'),
        ),
      ],
    );
  }

  Widget _buildExperienceStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Eyebrow('YOUR PROFESSIONAL STORY'),
        const SizedBox(height: 12),
        Text('Experience worth highlighting.',
            style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 10),
        const Text(
          'Add your roles and what you actually did. Specific projects, '
          'tools, and outcomes help make each entry stronger.',
          style: TextStyle(color: _muted, fontSize: 15, height: 1.55),
        ),
        const SizedBox(height: 26),
        for (var index = 0; index < _experiences.length; index++) ...[
          _ExperienceCard(
            key: ObjectKey(_experiences[index]),
            experience: _experiences[index],
            index: index,
            canRemove: _experiences.length > 1,
            isWorking: _working,
            onRemove: () => setState(() {
              _experiences.removeAt(index).dispose();
            }),
            onAiHelp: _generateWorkDescription,
          ),
          const SizedBox(height: 14),
        ],
        OutlinedButton.icon(
          onPressed: () => setState(() => _experiences.add(_ExperienceDraft())),
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Add another experience'),
        ),
        const SizedBox(height: 18),
        const _Notice(
          icon: Icons.fact_check_outlined,
          text: 'AI suggestions are drafts. Verify every responsibility and '
              'result before including it.',
        ),
      ],
    );
  }

  Widget _buildEducationStep(bool wide) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Eyebrow('YOUR EDUCATION'),
        const SizedBox(height: 12),
        Text('Add the education that supports your goals.',
            style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 10),
        const Text(
          'Include completed or in-progress studies. A final project is '
          'optional, but can be a great way to show what you can do.',
          style: TextStyle(color: _muted, fontSize: 15, height: 1.55),
        ),
        const SizedBox(height: 26),
        for (var index = 0; index < _educations.length; index++) ...[
          _Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _SectionHeading(
                        title: 'Degree ${index + 1}',
                        subtitle:
                            'Bachelor’s, master’s, PhD, or another program.',
                      ),
                    ),
                    if (_educations.length > 1)
                      IconButton(
                        onPressed: () => setState(
                          () => _educations.removeAt(index).dispose(),
                        ),
                        tooltip: 'Remove education',
                        icon: const Icon(Icons.delete_outline, color: _muted),
                      ),
                  ],
                ),
                const SizedBox(height: 18),
                DropdownButtonFormField<String>(
                  initialValue: _educations[index].degree,
                  decoration: const InputDecoration(labelText: 'Degree level'),
                  items: const [
                    DropdownMenuItem(
                        value: 'Bachelor\'s', child: Text('Bachelor’s')),
                    DropdownMenuItem(
                        value: 'Master\'s', child: Text('Master’s')),
                    DropdownMenuItem(value: 'PhD', child: Text('PhD')),
                    DropdownMenuItem(value: 'Other', child: Text('Other')),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => _educations[index].degree = value);
                    }
                  },
                ),
                const SizedBox(height: 15),
                _field(
                  _educations[index].degreeName,
                  'Degree name (optional)',
                  hint: 'e.g. B.Tech, MBA',
                ),
                const SizedBox(height: 15),
                _field(
                  _educations[index].fieldOfStudy,
                  'Field of study',
                  hint: 'e.g. Computer Science',
                ),
                const SizedBox(height: 15),
                _field(
                  _educations[index].institution,
                  'College or university',
                  hint: 'Institution name',
                ),
                const SizedBox(height: 15),
                _field(
                  _educations[index].graduationYear,
                  'Graduation year (or expected)',
                  hint: 'e.g. 2025',
                  keyboardType: TextInputType.number,
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
        ],
        OutlinedButton.icon(
          onPressed: () => setState(() => _educations.add(_EducationDraft())),
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Add another degree'),
        ),
        const SizedBox(height: 14),
        _Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SectionHeading(
                title: 'Final semester project',
                subtitle: 'Optional — tell us the idea in your own words.',
                trailing: 'OPTIONAL',
              ),
              const SizedBox(height: 18),
              _field(
                _project,
                'Project idea',
                hint: 'What were you trying to build or solve?',
                maxLines: 4,
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _working ? null : _generateProjectDescription,
                  icon: const Icon(Icons.auto_awesome_outlined, size: 17),
                  label: const Text('Help me describe this project'),
                ),
              ),
            ],
          ),
        ),
        if (wide) const SizedBox(height: 4),
      ],
    );
  }

  Widget _buildTargetStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Eyebrow('MAKE IT RELEVANT'),
        const SizedBox(height: 12),
        Text('What opportunity are you aiming for?',
            style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 10),
        const Text(
          'Share the role and job description so your resume can be tailored '
          'to the opportunity — without adding experience you don’t have.',
          style: TextStyle(color: _muted, fontSize: 15, height: 1.55),
        ),
        const SizedBox(height: 26),
        _Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SectionHeading(
                title: 'Target opportunity',
                subtitle: 'You can change this for each application.',
              ),
              const SizedBox(height: 20),
              _field(_jobTitle, 'Job title', hint: 'e.g. Product Designer'),
              const SizedBox(height: 15),
              _field(_company, 'Company name', hint: 'Company'),
              const SizedBox(height: 15),
              _field(_location, 'Job location',
                  hint: 'City, country or remote'),
              const SizedBox(height: 15),
              _field(
                _salaryRange,
                'Salary range (optional)',
                hint: 'e.g. \$80,000-\$95,000 or Not listed',
              ),
              const SizedBox(height: 15),
              _field(
                _applicationUrl,
                'Official application link (optional)',
                hint: 'https://company.example/jobs/role',
              ),
              const SizedBox(height: 15),
              _field(
                _jobDescription,
                'Job description',
                hint: 'Paste the job description here…',
                maxLines: 8,
              ),
              const SizedBox(height: 8),
              const Text(
                'The job description is used to guide relevance. A real ATS '
                'vendor score is not available; review the estimate yourself.',
                style: TextStyle(color: _muted, fontSize: 12, height: 1.45),
              ),
              const SizedBox(height: 8),
              const Text(
                'Salary is recorded only when you provide it. The application '
                'link is opened for you to review and submit yourself.',
                style: TextStyle(color: _muted, fontSize: 12, height: 1.45),
              ),
              const SizedBox(height: 18),
              _field(
                _tailoringNotes,
                'What would you like to change or emphasize? (optional)',
                hint: 'e.g. Emphasize my mentoring work and product launches.',
                maxLines: 3,
              ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.tonalIcon(
                  onPressed: _working ? null : _analyzeTailoring,
                  icon: const Icon(Icons.compare_arrows, size: 18),
                  label: const Text('Compare resume with this job'),
                ),
              ),
              const Text(
                'You choose which suggested skills or rewrites to apply. '
                'Missing JD skills are never added automatically.',
                style: TextStyle(color: _muted, fontSize: 12, height: 1.45),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _buildJobSearchPanel(),
      ],
    );
  }

  Widget _buildJobSearchPanel() {
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionHeading(
            title: 'Find jobs that fit your resume',
            subtitle:
                'AI compares public listings with your stated experience and skills.',
          ),
          const SizedBox(height: 8),
          Text(
            'Search query: ${_jobSearchQuery().isEmpty ? 'add a role, experience, or skill first' : _jobSearchQuery()}',
            style: const TextStyle(color: _muted, fontSize: 12, height: 1.4),
          ),
          const SizedBox(height: 14),
          _field(
            _jobSearchLocations,
            'Preferred cities (comma-separated)',
            hint: 'Chennai, Coimbatore, Bengaluru',
            maxLines: 2,
          ),
          const SizedBox(height: 12),
          _field(
            _jobSearchCountry,
            'Country code (two-letter)',
            hint: 'in, us, gb, ca, au ...',
          ),
          const SizedBox(height: 8),
          const Text(
            'Search up to five cities and 20 listings through Adzuna. If its '
            'credentials are not configured, the app uses Jobicy’s public remote '
            'feed; it uses broad country/region filters when available, not '
            'city filters, and may return fewer jobs.',
            style: TextStyle(color: _muted, fontSize: 12, height: 1.45),
          ),
          const SizedBox(height: 12),
          FilledButton.tonalIcon(
            onPressed: _working || _searchingJobs ? null : _searchJobs,
            icon: _searchingJobs
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.travel_explore_outlined, size: 18),
            label: Text(
                _searchingJobs ? 'Searching listings…' : 'Find matching jobs'),
          ),
          if (_jobListingProvider != null)
            Text(
              'Listings via $_jobListingProvider. Jobicy results link to the original Jobicy posting; Adzuna results link to the advertiser.',
              style: const TextStyle(color: _muted, fontSize: 11, height: 1.4),
            ),
          OutlinedButton.icon(
            onPressed: _working
                ? null
                : () async {
                    await _saveCurrentApplication();
                  },
            icon: const Icon(Icons.bookmark_add_outlined, size: 18),
            label: const Text('Track current target job'),
          ),
          if (_jobSearchMethod == 'local_keyword_coverage')
            const Text(
              'AI ranking is not configured or was unavailable, so matches use local keyword coverage only. This score does not predict hiring outcomes.',
              style: TextStyle(color: _muted, fontSize: 11, height: 1.4),
            )
          else if (_jobSearchProvider != null)
            Text(
              'Resume match analysis by $_jobSearchProvider. Scores are relevance estimates, not hiring probabilities.',
              style: const TextStyle(color: _muted, fontSize: 11, height: 1.4),
            ),
          for (final job in _jobResults) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFF7FAF9),
                border: Border.all(color: _line),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          job.title,
                          style: const TextStyle(
                            color: _ink,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${job.fitScore}% ${_jobSearchMethod == 'local_keyword_coverage' ? 'keyword coverage' : 'fit'}',
                        style: const TextStyle(
                          color: _brand,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${job.company}${job.location.isEmpty ? '' : ' · ${job.location}'}',
                    style: const TextStyle(color: _muted, fontSize: 12),
                  ),
                  if (job.salaryRange.isNotEmpty) ...[
                    const SizedBox(height: 5),
                    Text(
                      job.salaryRange,
                      style: const TextStyle(color: _ink, fontSize: 12),
                    ),
                  ],
                  if (job.reasons.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Relevant: ${job.reasons.join('; ')}',
                      style: const TextStyle(
                          color: _muted, fontSize: 12, height: 1.4),
                    ),
                  ],
                  if (job.gaps.isNotEmpty) ...[
                    const SizedBox(height: 5),
                    Text(
                      'Check: ${job.gaps.join('; ')}',
                      style: const TextStyle(
                          color: _muted, fontSize: 12, height: 1.4),
                    ),
                  ],
                  if (job.description.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      job.description,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: _muted, fontSize: 12, height: 1.4),
                    ),
                  ],
                  const SizedBox(height: 4),
                  Text(
                    '${job.source} listing. Open the source page for full details and application options.',
                    style: TextStyle(color: _muted, fontSize: 11, height: 1.4),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      TextButton.icon(
                        onPressed: () => _showJobDescription(job),
                        icon: const Icon(Icons.subject, size: 16),
                        label: const Text('Read description'),
                      ),
                      FilledButton.tonal(
                        onPressed: () => _selectJob(job),
                        child: const Text('Use this job'),
                      ),
                      TextButton.icon(
                        onPressed: () => _openExternalUrl(job.postingUrl),
                        icon: const Icon(Icons.open_in_new, size: 16),
                        label: Text(
                          job.source == 'Jobicy'
                              ? 'View Jobicy listing'
                              : 'View full job & apply',
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAtsPanel() {
    final score = _atsResult?['score'];
    final matched = _atsResult?['matchedKeywords'];
    final missing = _atsResult?['missingKeywords'];
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Estimated ATS keyword coverage',
            style: TextStyle(
              color: _ink,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            score is int ? '$score%' : 'Not enough information',
            style: const TextStyle(
              color: _brand,
              fontSize: 30,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _generatedDocuments == null
                ? 'A local keyword-coverage estimate from your current details, not an ATS vendor score or hiring prediction.'
                : 'Calculated from the final generated resume. This is a local keyword-coverage estimate, not an ATS vendor score or hiring prediction.',
            style: TextStyle(color: _muted, fontSize: 12, height: 1.5),
          ),
          if (matched is List && matched.isNotEmpty) ...[
            const SizedBox(height: 14),
            const Text(
              'Matched terms',
              style: TextStyle(color: _ink, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 5),
            Text(
              matched.whereType<String>().join(', '),
              style: const TextStyle(color: _muted, fontSize: 12, height: 1.5),
            ),
          ],
          if (missing is List && missing.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Text(
              'Terms not found in your details',
              style: TextStyle(color: _ink, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 5),
            Text(
              missing.whereType<String>().join(', '),
              style: const TextStyle(color: _muted, fontSize: 12, height: 1.5),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildJobMatchPanel() {
    final score = _generatedDocuments?['jobMatchScore'];
    final reasons = _stringList(_generatedDocuments?['jobMatchReasons']);
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Job description match estimate',
            style: TextStyle(
              color: _ink,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            score is num ? '${score.round()}%' : 'Not available',
            style: const TextStyle(
              color: _brand,
              fontSize: 30,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'AI estimate of how the supplied resume evidence aligns with this JD. '
            'It is not a hiring probability or an ATS-vendor score.',
            style: TextStyle(color: _muted, fontSize: 12, height: 1.5),
          ),
          if (reasons.isNotEmpty) ...[
            const SizedBox(height: 12),
            for (final reason in reasons)
              Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Text(
                  '• $reason',
                  style: const TextStyle(
                    color: _muted,
                    fontSize: 12,
                    height: 1.45,
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildGeneratedResumePreview() {
    final resume = _stringValue(_generatedDocuments?['resume']);
    if (resume.isEmpty) return const SizedBox.shrink();
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionHeading(
            title: 'Your generated resume',
            subtitle:
                'Review the final version saved in your document package.',
          ),
          const SizedBox(height: 12),
          SelectableText(
            resume,
            style: const TextStyle(color: _ink, fontSize: 13, height: 1.55),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () async {
                try {
                  await Clipboard.setData(ClipboardData(text: resume));
                  _showMessage('Generated resume copied to clipboard.');
                } on PlatformException {
                  _showMessage('Could not copy the generated resume.');
                }
              },
              icon: const Icon(Icons.copy_outlined, size: 17),
              label: const Text('Copy resume text'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReviewStep(bool wide) {
    final experienceCount =
        _experiences.where((item) => item.title.text.trim().isNotEmpty).length;
    final educationSummary = _educations
        .where((item) => item.institution.text.trim().isNotEmpty)
        .map((item) => '${item.degree} · ${item.institution.text.trim()}')
        .join('; ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Eyebrow('LOOKING GOOD'),
        const SizedBox(height: 12),
        Text('Review your resume details.',
            style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 10),
        const Text(
          'Check what you’ve added. You’ll be able to edit any section before '
          'creating a final document.',
          style: TextStyle(color: _muted, fontSize: 15, height: 1.55),
        ),
        const SizedBox(height: 26),
        _Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _SectionHeading(
                title: 'Resume look',
                subtitle:
                    'A new professional style is selected after each export.',
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                initialValue: _documentStyles[_documentStyleIndex].$1,
                decoration: const InputDecoration(labelText: 'Document style'),
                items: [
                  for (final style in _documentStyles)
                    DropdownMenuItem(
                      value: style.$1,
                      child: Text(style.$2),
                    ),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  final index = _documentStyles.indexWhere(
                    (style) => style.$1 == value,
                  );
                  if (index >= 0) setState(() => _documentStyleIndex = index);
                },
              ),
              const SizedBox(height: 8),
              const Text(
                'Each style changes typography, spacing, and accent color. '
                'Exports have no watermark.',
                style: TextStyle(color: _muted, fontSize: 12, height: 1.45),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: wide ? 6 : 1,
              child: _Panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _name.text.trim().isEmpty ? 'Your name' : _name.text,
                      style: const TextStyle(
                        color: _ink,
                        fontSize: 23,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (_email.text.trim().isNotEmpty) ...[
                      const SizedBox(height: 5),
                      Text(_email.text, style: const TextStyle(color: _muted)),
                    ],
                    if (_phone.text.trim().isNotEmpty) ...[
                      const SizedBox(height: 5),
                      Text(_phone.text, style: const TextStyle(color: _muted)),
                    ],
                    const SizedBox(height: 20),
                    const Divider(color: _line),
                    const SizedBox(height: 12),
                    _ReviewRow(
                      title: 'Experience',
                      value: '$experienceCount role(s) added',
                      onEdit: () => _goToStep(1),
                    ),
                    _ReviewRow(
                      title: 'Education',
                      value: educationSummary.isEmpty
                          ? 'Not added yet'
                          : educationSummary,
                      onEdit: () => _goToStep(2),
                    ),
                    _ReviewRow(
                      title: 'Target role',
                      value: _jobTitle.text.trim().isEmpty
                          ? 'Not added yet'
                          : '${_jobTitle.text}${_company.text.trim().isEmpty ? '' : ' at ${_company.text}'}',
                      onEdit: () => _goToStep(3),
                    ),
                  ],
                ),
              ),
            ),
            if (wide) ...[
              const SizedBox(width: 16),
              Expanded(flex: 4, child: _buildAtsPanel()),
            ],
          ],
        ),
        if (!wide) ...[
          const SizedBox(height: 14),
          _buildAtsPanel(),
        ],
        if (_generatedDocuments != null) ...[
          const SizedBox(height: 14),
          _buildJobMatchPanel(),
          const SizedBox(height: 14),
          _buildGeneratedResumePreview(),
        ],
        const SizedBox(height: 18),
        _Notice(
          icon: Icons.verified_user_outlined,
          text: _resumeImported
              ? 'Imported $_resumeFileName. Review all extracted details for '
                  'accuracy before generating your documents.'
              : 'Review all details carefully. Your resume should only include '
                  'skills and achievements you can stand behind.',
        ),
        if (_activeProvider != null) ...[
          const SizedBox(height: 12),
          _Notice(
            icon: Icons.auto_awesome_outlined,
            text: 'Most recent AI provider: $_activeProvider. '
                'Verify all generated content.',
          ),
        ],
        if (_generatedDocuments != null) ...[
          const SizedBox(height: 12),
          const _Notice(
            icon: Icons.check_circle_outline,
            text:
                'Resume, CV, cover letter, and application/interview kit were '
                'reviewed and exported. Edit your details and generate again '
                'if anything changes.',
          ),
        ],
        if (_generatedDocuments != null || _applications.isNotEmpty) ...[
          const SizedBox(height: 14),
          _buildApplicationTracker(),
        ],
        if (_generatedDocuments != null) ...[
          const SizedBox(height: 14),
          _buildJobSearchPanel(),
        ],
      ],
    );
  }

  Widget _buildApplicationTracker() {
    final applicationKit = _stringValue(_generatedDocuments?['applicationKit']);
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionHeading(
            title: 'Application follow-through',
            subtitle: 'Keep this job and its interview kit together.',
          ),
          const SizedBox(height: 10),
          const Text(
            'The kit includes draft application answers and interview talking '
            'points. Review and copy them into the official job form yourself. '
            'Job details and status are saved on this device.',
            style: TextStyle(color: _muted, fontSize: 12, height: 1.5),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.tonalIcon(
                onPressed: _generatedDocuments == null
                    ? null
                    : () async {
                        await _saveCurrentApplication();
                      },
                icon: const Icon(Icons.bookmark_add_outlined, size: 18),
                label: const Text('Add current job to tracker'),
              ),
              OutlinedButton.icon(
                onPressed: applicationKit.isEmpty
                    ? null
                    : () async {
                        try {
                          await Clipboard.setData(
                            ClipboardData(text: applicationKit),
                          );
                          _showMessage('Application kit copied to clipboard.');
                        } on PlatformException {
                          _showMessage('Could not copy the application kit.');
                        }
                      },
                icon: const Icon(Icons.copy_outlined, size: 17),
                label: const Text('Copy application kit'),
              ),
            ],
          ),
          if (_applications.isEmpty) ...[
            const SizedBox(height: 12),
            const Text(
              'No jobs tracked yet. Add the current role after checking its details.',
              style: TextStyle(color: _muted, fontSize: 12),
            ),
          ],
          for (final application in _applications) ...[
            const SizedBox(height: 12),
            Material(
              color: const Color(0xFFF7FAF9),
              shape: RoundedRectangleBorder(
                side: const BorderSide(color: _line),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            '${application.role} · ${application.company}',
                            style: const TextStyle(
                              color: _ink,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        DropdownButton<String>(
                          value: application.status,
                          underline: const SizedBox.shrink(),
                          items: const [
                            'Prepared',
                            'Applied',
                            'Interview',
                            'Rejected',
                            'Offer',
                            'Withdrawn',
                          ]
                              .map(
                                (status) => DropdownMenuItem(
                                  value: status,
                                  child: Text(status),
                                ),
                              )
                              .toList(),
                          onChanged: (status) {
                            if (status != null) {
                              _setApplicationStatus(application, status);
                            }
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      [
                        application.location,
                        application.salaryRange.isEmpty
                            ? 'Salary not listed'
                            : application.salaryRange,
                      ].where((part) => part.trim().isNotEmpty).join(' · '),
                      style: const TextStyle(color: _muted, fontSize: 12),
                    ),
                    if (application.packagePath.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 5),
                        child: SelectableText(
                          'Document package: ${application.packagePath}',
                          style: const TextStyle(color: _muted, fontSize: 11),
                        ),
                      ),
                    ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      childrenPadding: EdgeInsets.zero,
                      title: const Text(
                        'View job description',
                        style: TextStyle(fontSize: 12, color: _brand),
                      ),
                      children: [
                        Align(
                          alignment: Alignment.centerLeft,
                          child: SelectableText(
                            application.jobDescription,
                            style: const TextStyle(
                              color: _muted,
                              fontSize: 12,
                              height: 1.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        if (application.applicationUrl.isNotEmpty)
                          TextButton.icon(
                            onPressed: () => _openApplicationPage(application),
                            icon: const Icon(Icons.open_in_new, size: 16),
                            label: const Text('Open job page'),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFooter(bool wide) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: _line)),
      ),
      padding: EdgeInsets.symmetric(
        horizontal: wide ? 44 : 20,
        vertical: 14,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 850),
          child: Row(
            children: [
              if (_currentStep > 0)
                TextButton.icon(
                  onPressed: () => _goToStep(_currentStep - 1),
                  icon: const Icon(Icons.arrow_back, size: 17),
                  label: const Text('Back'),
                )
              else
                const Expanded(
                  child: Text(
                    'Your draft and tracker are saved on this device.',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: _muted, fontSize: 12),
                  ),
                ),
              const Spacer(),
              FilledButton.icon(
                onPressed: _working
                    ? null
                    : _currentStep < _steps.length - 1
                        ? () => _goToStep(_currentStep + 1)
                        : _createDocuments,
                icon: _working
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        _currentStep < _steps.length - 1
                            ? Icons.arrow_forward
                            : Icons.file_download_outlined,
                        size: 17,
                      ),
                label: Text(
                  _working
                      ? 'Working…'
                      : _currentStep < _steps.length - 1
                          ? 'Continue'
                          : 'Create my resume',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    String? hint,
    int maxLines = 1,
    TextInputType? keyboardType,
  }) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        alignLabelWithHint: maxLines > 1,
      ),
    );
  }
}

class _ResumeImportSelection {
  const _ResumeImportSelection({
    required this.replaceProfile,
    required this.mergeIntoDraft,
    required this.name,
    required this.email,
    required this.linkedin,
    required this.phone,
    required this.skills,
    required this.experienceIndexes,
    required this.educationIndexes,
    required this.includeProject,
    required this.project,
    required this.tailoringNotes,
  });

  final bool replaceProfile;
  final bool mergeIntoDraft;
  final String name;
  final String email;
  final String linkedin;
  final String phone;
  final List<String> skills;
  final List<int> experienceIndexes;
  final List<int> educationIndexes;
  final bool includeProject;
  final String project;
  final String tailoringNotes;
}

class _ResumeImportDialog extends StatefulWidget {
  const _ResumeImportDialog({
    required this.importedName,
    required this.importedEmail,
    required this.importedLinkedIn,
    required this.importedPhone,
    required this.currentPhone,
    required this.currentName,
    required this.currentEmail,
    required this.currentLinkedIn,
    required this.currentSkills,
    required this.importedSkills,
    required this.matchedSkills,
    required this.experiences,
    required this.education,
    required this.currentProject,
    required this.importedProject,
    required this.currentJobDescription,
    required this.currentTailoringNotes,
  });

  final String importedName;
  final String importedEmail;
  final String importedLinkedIn;
  final String importedPhone;
  final String currentPhone;
  final String currentName;
  final String currentEmail;
  final String currentLinkedIn;
  final String currentSkills;
  final List<String> importedSkills;
  final List<String> matchedSkills;
  final List<_ExperienceDraft> experiences;
  final List<_EducationDraft> education;
  final String currentProject;
  final String importedProject;
  final String currentJobDescription;
  final String currentTailoringNotes;

  @override
  State<_ResumeImportDialog> createState() => _ResumeImportDialogState();
}

class _ResumeImportDialogState extends State<_ResumeImportDialog> {
  late final TextEditingController _name;
  late final TextEditingController _email;
  late final TextEditingController _linkedin;
  late final TextEditingController _phone;
  late final TextEditingController _extraSkills;
  late final TextEditingController _project;
  late final TextEditingController _tailoringNotes;
  late final Set<int> _selectedExperiences;
  late final Set<int> _selectedEducation;
  late final Set<String> _selectedSkills;
  late bool _replaceProfile;
  late bool _mergeIntoDraft;
  late bool _includeProject;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.importedName);
    _email = TextEditingController(text: widget.importedEmail);
    _linkedin = TextEditingController(text: widget.importedLinkedIn);
    _phone = TextEditingController(text: widget.importedPhone);
    _extraSkills = TextEditingController();
    _project = TextEditingController(text: widget.importedProject);
    _tailoringNotes = TextEditingController(text: widget.currentTailoringNotes);
    _selectedExperiences = {
      for (var index = 0; index < widget.experiences.length; index++) index,
    };
    _selectedEducation = {
      for (var index = 0; index < widget.education.length; index++) index,
    };
    _selectedSkills = widget.importedSkills.toSet();
    _replaceProfile = widget.currentName.trim().isEmpty &&
        widget.currentEmail.trim().isEmpty &&
        widget.currentLinkedIn.trim().isEmpty &&
        widget.currentPhone.trim().isEmpty;
    _mergeIntoDraft = true;
    _includeProject = widget.importedProject.trim().isNotEmpty &&
        widget.currentProject.trim().isEmpty;
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _linkedin.dispose();
    _phone.dispose();
    _extraSkills.dispose();
    _project.dispose();
    _tailoringNotes.dispose();
    super.dispose();
  }

  void _submit() {
    final extraSkills = _extraSkills.text
        .split(',')
        .map((skill) => skill.trim())
        .where((skill) => skill.isNotEmpty);
    Navigator.pop(
      context,
      _ResumeImportSelection(
        replaceProfile: _replaceProfile,
        mergeIntoDraft: _mergeIntoDraft,
        name: _name.text.trim(),
        email: _email.text.trim(),
        linkedin: _linkedin.text.trim(),
        phone: _phone.text.trim(),
        skills: [
          ..._selectedSkills,
          ...extraSkills,
        ],
        experienceIndexes: _selectedExperiences.toList(),
        educationIndexes: _selectedEducation.toList(),
        includeProject: _includeProject,
        project: _project.text,
        tailoringNotes: _tailoringNotes.text,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.sizeOf(context);
    return AlertDialog(
      title: const Text('Review your imported resume'),
      content: SizedBox(
        width: screenSize.width < 720 ? screenSize.width * 0.78 : 620,
        height: screenSize.height * 0.62,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Choose what to keep, correct extracted details, and tell us what '
              'you want changed for the target job.',
              style: TextStyle(color: _muted, fontSize: 13, height: 1.45),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _mergeIntoDraft,
              onChanged: (value) =>
                  setState(() => _mergeIntoDraft = value ?? true),
              title: const Text('Add selected items to my current draft'),
              subtitle: const Text(
                'Turn this off to replace existing skills, experience, and education.',
              ),
              controlAffinity: ListTileControlAffinity.leading,
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _replaceProfile,
              onChanged: (value) =>
                  setState(() => _replaceProfile = value ?? false),
              title: const Text('Use imported name and contact details'),
              subtitle: const Text(
                'Existing profile fields are kept unless you choose this.',
              ),
              controlAffinity: ListTileControlAffinity.leading,
            ),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _ReviewSectionTitle(
                      title: 'Profile',
                      subtitle: 'Edit what was found before applying it.',
                    ),
                    _field(_name, 'Name'),
                    const SizedBox(height: 10),
                    _field(_email, 'Email'),
                    const SizedBox(height: 10),
                    _field(_phone, 'Phone'),
                    const SizedBox(height: 10),
                    _field(_linkedin, 'LinkedIn URL'),
                    const SizedBox(height: 18),
                    _ReviewSectionTitle(
                      title: 'Skills',
                      subtitle: 'Select the skills you want to keep.',
                    ),
                    if (widget.currentSkills.trim().isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          'Already in this draft: ${widget.currentSkills}',
                          style: const TextStyle(
                            color: _muted,
                            fontSize: 12,
                            height: 1.4,
                          ),
                        ),
                      ),
                    if (widget.matchedSkills.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          'Also mentioned in this JD: ${widget.matchedSkills.join(', ')}',
                          style: const TextStyle(
                            color: _brand,
                            fontSize: 12,
                            height: 1.4,
                          ),
                        ),
                      ),
                    if (widget.importedSkills.isEmpty)
                      const Text(
                        'No skills were extracted. Add skills you can verify below.',
                        style: TextStyle(color: _muted, fontSize: 12),
                      ),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        for (final skill in widget.importedSkills)
                          FilterChip(
                            label: Text(skill),
                            selected: _selectedSkills.contains(skill),
                            onSelected: (selected) => setState(() {
                              if (selected) {
                                _selectedSkills.add(skill);
                              } else {
                                _selectedSkills.remove(skill);
                              }
                            }),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _field(
                      _extraSkills,
                      'Add your own verified skills (comma-separated)',
                    ),
                    const SizedBox(height: 18),
                    _ReviewSectionTitle(
                      title: 'Work experience',
                      subtitle:
                          'Untick roles you do not want in the new resume.',
                    ),
                    if (widget.experiences.isEmpty)
                      const Text(
                        'No experience entries were extracted.',
                        style: TextStyle(color: _muted, fontSize: 12),
                      ),
                    for (var index = 0;
                        index < widget.experiences.length;
                        index++)
                      _experienceEntry(index),
                    const SizedBox(height: 18),
                    _ReviewSectionTitle(
                      title: 'Education',
                      subtitle: 'Select and correct the degrees to keep.',
                    ),
                    if (widget.education.isEmpty)
                      const Text(
                        'No education entries were extracted.',
                        style: TextStyle(color: _muted, fontSize: 12),
                      ),
                    for (var index = 0;
                        index < widget.education.length;
                        index++)
                      _educationEntry(index),
                    if (widget.importedProject.trim().isNotEmpty) ...[
                      const SizedBox(height: 14),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        value: _includeProject,
                        onChanged: (value) =>
                            setState(() => _includeProject = value ?? false),
                        title: const Text('Keep the imported project'),
                        controlAffinity: ListTileControlAffinity.leading,
                      ),
                      if (_includeProject)
                        _field(_project, 'Project details', maxLines: 3),
                    ],
                    const SizedBox(height: 18),
                    _ReviewSectionTitle(
                      title: 'Changes for the target job',
                      subtitle: widget.currentJobDescription.trim().isEmpty
                          ? 'Add a JD in the next step to get tailored suggestions.'
                          : 'These notes will guide the JD comparison and document draft.',
                    ),
                    _field(
                      _tailoringNotes,
                      'What should be emphasized or changed?',
                      hint:
                          'e.g. Keep the leadership experience; shorten older roles.',
                      maxLines: 3,
                    ),
                    const SizedBox(height: 12),
                    const _Notice(
                      icon: Icons.fact_check_outlined,
                      text:
                          'Imported details are suggestions from text extraction. '
                          'Verify every item before using it.',
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel import'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('Apply selected details'),
        ),
      ],
    );
  }

  Widget _experienceEntry(int index) {
    final experience = widget.experiences[index];
    final selected = _selectedExperiences.contains(index);
    final role = experience.title.text.trim().isEmpty
        ? 'Experience ${index + 1}'
        : experience.title.text.trim();
    return Column(
      children: [
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          value: selected,
          onChanged: (value) => setState(() {
            if (value == true) {
              _selectedExperiences.add(index);
            } else {
              _selectedExperiences.remove(index);
            }
          }),
          title: Text(role),
          subtitle: Text(
            [
              experience.company.text,
              experience.startDate.text,
              experience.currentRole ? 'Present' : experience.endDate.text,
            ].where((part) => part.trim().isNotEmpty).join(' · '),
          ),
          controlAffinity: ListTileControlAffinity.leading,
        ),
        if (selected)
          Padding(
            padding: const EdgeInsets.only(left: 42, bottom: 12),
            child: Column(
              children: [
                _field(experience.title, 'Job title'),
                const SizedBox(height: 8),
                _field(experience.company, 'Company'),
                const SizedBox(height: 8),
                _field(experience.location, 'Location'),
                const SizedBox(height: 8),
                _field(experience.startDate, 'Start date'),
                const SizedBox(height: 8),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: experience.currentRole,
                  onChanged: (value) => setState(() {
                    experience.currentRole = value ?? false;
                    if (experience.currentRole) experience.endDate.clear();
                  }),
                  title: const Text('Currently work here'),
                  controlAffinity: ListTileControlAffinity.leading,
                ),
                if (!experience.currentRole)
                  _field(experience.endDate, 'End date'),
                const SizedBox(height: 8),
                _field(
                  experience.description,
                  'Description',
                  maxLines: 4,
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _educationEntry(int index) {
    final education = widget.education[index];
    final selected = _selectedEducation.contains(index);
    return Column(
      children: [
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          value: selected,
          onChanged: (value) => setState(() {
            if (value == true) {
              _selectedEducation.add(index);
            } else {
              _selectedEducation.remove(index);
            }
          }),
          title: Text('${education.degree} degree'),
          subtitle: Text(education.institution.text),
          controlAffinity: ListTileControlAffinity.leading,
        ),
        if (selected)
          Padding(
            padding: const EdgeInsets.only(left: 42, bottom: 12),
            child: Column(
              children: [
                DropdownButtonFormField<String>(
                  initialValue: education.degree,
                  decoration: const InputDecoration(labelText: 'Degree level'),
                  items: const [
                    DropdownMenuItem(
                        value: 'Bachelor\'s', child: Text('Bachelor’s')),
                    DropdownMenuItem(
                        value: 'Master\'s', child: Text('Master’s')),
                    DropdownMenuItem(value: 'PhD', child: Text('PhD')),
                    DropdownMenuItem(value: 'Other', child: Text('Other')),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => education.degree = value);
                    }
                  },
                ),
                const SizedBox(height: 8),
                _field(education.degreeName, 'Degree name'),
                const SizedBox(height: 8),
                _field(education.fieldOfStudy, 'Field of study'),
                const SizedBox(height: 8),
                _field(education.institution, 'Institution'),
                const SizedBox(height: 8),
                _field(education.graduationYear, 'Graduation year'),
              ],
            ),
          ),
      ],
    );
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    String? hint,
    int maxLines = 1,
  }) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        alignLabelWithHint: maxLines > 1,
      ),
    );
  }
}

class _JobMatch {
  const _JobMatch({
    required this.id,
    required this.title,
    required this.company,
    required this.location,
    required this.description,
    required this.postingUrl,
    required this.fitScore,
    required this.reasons,
    required this.gaps,
    required this.salaryMin,
    required this.salaryMax,
    required this.salaryCurrency,
    required this.salaryIsPredicted,
    required this.source,
  });

  factory _JobMatch.fromJson(Map<String, dynamic> json) {
    String requiredText(String key) {
      final value = json[key];
      if (value is! String || value.trim().isEmpty) {
        throw ResumeApiException('A job listing is missing $key.');
      }
      return value.trim();
    }

    final score = json['fitScore'];
    if (score is! num || score < 0 || score > 100) {
      throw const ResumeApiException(
          'A job listing has an invalid fit estimate.');
    }
    return _JobMatch(
      id: requiredText('id'),
      title: requiredText('title'),
      company: requiredText('company'),
      location: json['location'] is String ? json['location'] as String : '',
      description:
          json['description'] is String ? json['description'] as String : '',
      postingUrl: requiredText('postingUrl'),
      fitScore: score.round(),
      reasons: _readList(json['reasons']),
      gaps: _readList(json['gaps']),
      salaryMin: json['salaryMin'] is num
          ? (json['salaryMin'] as num).toDouble()
          : null,
      salaryMax: json['salaryMax'] is num
          ? (json['salaryMax'] as num).toDouble()
          : null,
      salaryCurrency: json['salaryCurrency'] is String
          ? json['salaryCurrency'] as String
          : '',
      salaryIsPredicted: json['salaryIsPredicted'] == true,
      source: requiredText('source'),
    );
  }

  static List<String> _readList(dynamic value) {
    if (value is! List) return [];
    return value
        .whereType<String>()
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .take(3)
        .toList();
  }

  final String id;
  final String title;
  final String company;
  final String location;
  final String description;
  final String postingUrl;
  final int fitScore;
  final List<String> reasons;
  final List<String> gaps;
  final double? salaryMin;
  final double? salaryMax;
  final String salaryCurrency;
  final bool salaryIsPredicted;
  final String source;

  String get salaryRange {
    if (salaryMin == null && salaryMax == null) return '';
    final range = [
      if (salaryMin != null) salaryMin!.toStringAsFixed(0),
      if (salaryMax != null) salaryMax!.toStringAsFixed(0),
    ].join(' - ');
    final source = salaryIsPredicted ? 'Adzuna estimate - verify' : 'Listed';
    final currency = salaryCurrency.isEmpty ? '' : ' $salaryCurrency';
    return '$source: $range$currency';
  }
}

class _ApplicationRecord {
  _ApplicationRecord({
    required this.role,
    required this.company,
    required this.location,
    required this.salaryRange,
    required this.jobDescription,
    required this.applicationUrl,
    required this.packagePath,
  });

  final String role;
  final String company;
  final String location;
  final String salaryRange;
  final String jobDescription;
  final String applicationUrl;
  final String packagePath;
  String status = 'Prepared';

  factory _ApplicationRecord.fromJson(Object? value) {
    if (value is! Map<String, dynamic>) {
      throw const FormatException('A saved application entry is invalid.');
    }
    String readString(String key) =>
        value[key] is String ? value[key] as String : '';
    const allowedStatuses = [
      'Prepared',
      'Applied',
      'Interview',
      'Rejected',
      'Offer',
      'Withdrawn',
    ];
    final application = _ApplicationRecord(
      role: readString('role'),
      company: readString('company'),
      location: readString('location'),
      salaryRange: readString('salaryRange'),
      jobDescription: readString('jobDescription'),
      applicationUrl: readString('applicationUrl'),
      packagePath: readString('packagePath'),
    );
    final status = readString('status');
    if (allowedStatuses.contains(status)) application.status = status;
    return application;
  }

  Map<String, String> toJson() => {
        'role': role,
        'company': company,
        'location': location,
        'salaryRange': salaryRange,
        'jobDescription': jobDescription,
        'applicationUrl': applicationUrl,
        'packagePath': packagePath,
        'status': status,
      };
}

class _ExperienceDraft {
  _ExperienceDraft();

  factory _ExperienceDraft.fromJson(Object? value) {
    final json = value as Map<String, dynamic>;
    final draft = _ExperienceDraft();
    for (final field in draft._fields.entries) {
      final text = json[field.key];
      if (text is String) field.value.text = text;
    }
    draft.currentRole = json['currentRole'] == true;
    return draft;
  }

  Map<String, TextEditingController> get _fields => {
        'title': title,
        'company': company,
        'location': location,
        'startDate': startDate,
        'endDate': endDate,
        'description': description,
      };

  Map<String, Object> toJson() => {
        for (final field in _fields.entries) field.key: field.value.text,
        'currentRole': currentRole,
      };

  final title = TextEditingController();
  final company = TextEditingController();
  final location = TextEditingController();
  final startDate = TextEditingController();
  final endDate = TextEditingController();
  final description = TextEditingController();
  bool currentRole = false;

  void dispose() {
    title.dispose();
    company.dispose();
    location.dispose();
    startDate.dispose();
    endDate.dispose();
    description.dispose();
  }
}

class _EducationDraft {
  _EducationDraft();

  factory _EducationDraft.fromJson(Object? value) {
    final json = value as Map<String, dynamic>;
    final draft = _EducationDraft();
    for (final field in draft._fields.entries) {
      final text = json[field.key];
      if (text is String) field.value.text = text;
    }
    // The dropdown only accepts these levels.
    const levels = ['Bachelor\'s', 'Master\'s', 'PhD', 'Other'];
    if (levels.contains(json['degree'])) {
      draft.degree = json['degree'] as String;
    }
    return draft;
  }

  Map<String, TextEditingController> get _fields => {
        'degreeName': degreeName,
        'fieldOfStudy': fieldOfStudy,
        'institution': institution,
        'graduationYear': graduationYear,
        'project': project,
      };

  Map<String, String> toJson() => {
        for (final field in _fields.entries) field.key: field.value.text,
        'degree': degree,
      };

  String degree = 'Bachelor\'s';
  final degreeName = TextEditingController();
  final fieldOfStudy = TextEditingController();
  final institution = TextEditingController();
  final graduationYear = TextEditingController();
  final project = TextEditingController();

  void dispose() {
    degreeName.dispose();
    fieldOfStudy.dispose();
    institution.dispose();
    graduationYear.dispose();
    project.dispose();
  }
}

class _ExperienceCard extends StatefulWidget {
  const _ExperienceCard({
    super.key,
    required this.experience,
    required this.index,
    required this.canRemove,
    required this.isWorking,
    required this.onRemove,
    required this.onAiHelp,
  });

  final _ExperienceDraft experience;
  final int index;
  final bool canRemove;
  final bool isWorking;
  final VoidCallback onRemove;
  final ValueChanged<_ExperienceDraft> onAiHelp;

  @override
  State<_ExperienceCard> createState() => _ExperienceCardState();
}

class _ExperienceCardState extends State<_ExperienceCard> {
  @override
  Widget build(BuildContext context) {
    final item = widget.experience;
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _SectionHeading(
                  title: 'Role ${widget.index + 1}',
                  subtitle: 'Add the details you remember.',
                ),
              ),
              if (widget.canRemove)
                IconButton(
                  onPressed: widget.onRemove,
                  tooltip: 'Remove experience',
                  icon: const Icon(Icons.delete_outline, color: _muted),
                ),
            ],
          ),
          const SizedBox(height: 18),
          _ExperienceTextField(
              controller: item.title,
              label: 'Job title',
              hint: 'e.g. Software Engineer'),
          const SizedBox(height: 14),
          _ExperienceTextField(controller: item.company, label: 'Company name'),
          const SizedBox(height: 14),
          _ExperienceTextField(controller: item.location, label: 'Location'),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final dateFields = Row(
                children: [
                  Expanded(
                    child: _ExperienceTextField(
                      controller: item.startDate,
                      label: 'Start date',
                      hint: 'MM/YYYY',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _ExperienceTextField(
                      controller: item.endDate,
                      label: 'End date',
                      hint: item.currentRole ? 'Current' : 'MM/YYYY',
                      enabled: !item.currentRole,
                    ),
                  ),
                ],
              );
              if (constraints.maxWidth < 600) {
                return Column(
                  children: [
                    dateFields,
                    const SizedBox(height: 8),
                    _currentRoleToggle(item),
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(child: dateFields),
                  const SizedBox(width: 12),
                  Flexible(child: _currentRoleToggle(item)),
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          _ExperienceTextField(
            controller: item.description,
            label: 'What did you work on?',
            hint: 'Describe your responsibilities, projects, and results…',
            maxLines: 5,
          ),
          const SizedBox(height: 7),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: widget.isWorking ? null : () => widget.onAiHelp(item),
              icon: const Icon(Icons.auto_awesome_outlined, size: 17),
              label: const Text('Help me write this'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _currentRoleToggle(_ExperienceDraft item) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Checkbox(
          value: item.currentRole,
          activeColor: _brand,
          onChanged: (value) => setState(() {
            item.currentRole = value ?? false;
            if (item.currentRole) item.endDate.clear();
          }),
        ),
        const Flexible(
          child: Text(
            'I currently work here',
            style: TextStyle(color: _ink, fontSize: 12),
          ),
        ),
      ],
    );
  }
}

class _ExperienceTextField extends StatelessWidget {
  const _ExperienceTextField({
    required this.controller,
    required this.label,
    this.hint,
    this.maxLines = 1,
    this.enabled = true,
  });

  final TextEditingController controller;
  final String label;
  final String? hint;
  final int maxLines;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      enabled: enabled,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        alignLabelWithHint: maxLines > 1,
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.wide});

  final bool wide;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 70,
      padding: EdgeInsets.symmetric(horizontal: wide ? 26 : 18),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF0D1726), Color(0xFF172A3B)],
        ),
        border:
            Border(bottom: BorderSide(color: Color(0xFF2DD4BF), width: 1.5)),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF2DD4BF), Color(0xFF3B82F6)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(10),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x402DD4BF),
                  blurRadius: 12,
                  offset: Offset(0, 3),
                ),
              ],
            ),
            child: const Icon(Icons.description_outlined,
                color: Colors.white, size: 20),
          ),
          const SizedBox(width: 10),
          const Text(
            'resume',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.4,
            ),
          ),
          const Text(
            'studio',
            style: TextStyle(
              color: Color(0xFF5EEAD4),
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          const Icon(Icons.edit_note_outlined,
              color: Color(0xFF8DA0B2), size: 17),
          const SizedBox(width: 7),
          Text(
            wide ? 'Draft in progress' : 'Draft',
            style: const TextStyle(color: Color(0xFFC4D0DC), fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _StepTile extends StatelessWidget {
  const _StepTile({
    required this.number,
    required this.title,
    required this.icon,
    required this.selected,
    required this.complete,
    required this.onTap,
  });

  final int number;
  final String title;
  final IconData icon;
  final bool selected;
  final bool complete;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? _brand : _muted;
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFFEDF5F2) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: complete ? _brand : Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: selected || complete ? _brand : _line,
                  ),
                ),
                child: Icon(
                  complete ? Icons.check : icon,
                  size: 16,
                  color: complete ? Colors.white : color,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: selected ? _brand : _ink,
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
              if (!complete)
                Text(
                  '$number',
                  style: const TextStyle(color: _muted, fontSize: 11),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: _line),
        borderRadius: BorderRadius.circular(17),
        boxShadow: const [
          BoxShadow(
            color: Color(0x09172B3A),
            blurRadius: 24,
            offset: Offset(0, 7),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _Eyebrow extends StatelessWidget {
  const _Eyebrow(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: _brand,
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.2,
      ),
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({
    required this.title,
    required this.subtitle,
    this.trailing,
  });

  final String title;
  final String subtitle;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: const TextStyle(
                      color: _ink, fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(subtitle,
                  style: const TextStyle(color: _muted, fontSize: 12)),
            ],
          ),
        ),
        if (trailing != null)
          Text(
            trailing!,
            style: const TextStyle(
              color: _muted,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.9,
            ),
          ),
      ],
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFEDF5F2),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: _brand),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(color: _ink, fontSize: 12, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReviewRow extends StatelessWidget {
  const _ReviewRow({
    required this.title,
    required this.value,
    required this.onEdit,
  });

  final String title;
  final String value;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        color: _muted,
                        fontSize: 11,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 3),
                Text(value,
                    style: const TextStyle(
                        color: _ink, fontSize: 13, fontWeight: FontWeight.w500),
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          TextButton(
            onPressed: onEdit,
            child: const Text('Edit', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }
}

class _DocumentReviewDialog extends StatelessWidget {
  const _DocumentReviewDialog({
    required this.resume,
    required this.cv,
    required this.coverLetter,
    required this.applicationKit,
  });

  final TextEditingController resume;
  final TextEditingController cv;
  final TextEditingController coverLetter;
  final TextEditingController applicationKit;

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.sizeOf(context);
    return DefaultTabController(
      length: 4,
      child: AlertDialog(
        title: const Text('Review before exporting'),
        content: SizedBox(
          width: screenSize.width < 720 ? screenSize.width * 0.82 : 680,
          height: screenSize.height < 760 ? screenSize.height * 0.56 : 480,
          child: Column(
            children: [
              const TabBar(
                isScrollable: true,
                tabs: [
                  Tab(text: 'Resume'),
                  Tab(text: 'CV'),
                  Tab(text: 'Cover letter'),
                  Tab(text: 'Application kit'),
                ],
              ),
              const SizedBox(height: 10),
              const Text(
                'Check the spelling and every personal detail. Export creates '
                'a PDF and Word file for each document.',
                style: TextStyle(color: _muted, fontSize: 12),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: TabBarView(
                  children: [
                    _editableDocument(resume),
                    _editableDocument(cv),
                    _editableDocument(coverLetter),
                    _editableDocument(applicationKit),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(context, {
              'resume': resume.text.trim(),
              'cv': cv.text.trim(),
              'coverLetter': coverLetter.text.trim(),
              'applicationKit': applicationKit.text.trim(),
            }),
            icon: const Icon(Icons.download_outlined, size: 18),
            label: const Text('Export eight files'),
          ),
        ],
      ),
    );
  }

  Widget _editableDocument(TextEditingController controller) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: TextField(
        controller: controller,
        expands: true,
        minLines: null,
        maxLines: null,
        textAlignVertical: TextAlignVertical.top,
        decoration: const InputDecoration(
          border: OutlineInputBorder(),
          hintText: 'Generated document content',
          alignLabelWithHint: true,
        ),
      ),
    );
  }
}

class _ReviewSectionTitle extends StatelessWidget {
  const _ReviewSectionTitle({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: _ink,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            subtitle,
            style: const TextStyle(color: _muted, fontSize: 12, height: 1.4),
          ),
        ],
      ),
    );
  }
}

class _TailoringSelection {
  const _TailoringSelection({
    required this.skillsToAdd,
    required this.rewrites,
    required this.tailoringNotes,
  });

  final List<String> skillsToAdd;
  final Map<int, String> rewrites;
  final String tailoringNotes;
}

class _ExperienceSuggestion {
  _ExperienceSuggestion({
    required this.experienceIndex,
    required this.original,
    required String revised,
    required this.questions,
  }) : revisedController = TextEditingController(text: revised);

  final int experienceIndex;
  final String original;
  final TextEditingController revisedController;
  final List<String> questions;
  bool selected = false;

  void dispose() => revisedController.dispose();
}

class _TailoringReviewDialog extends StatefulWidget {
  const _TailoringReviewDialog({
    required this.matchedSkills,
    required this.suggestedSkills,
    required this.experienceSuggestions,
    required this.recommendations,
    required this.questions,
    required this.currentNotes,
  });

  final List<String> matchedSkills;
  final List<String> suggestedSkills;
  final List<_ExperienceSuggestion> experienceSuggestions;
  final List<String> recommendations;
  final List<String> questions;
  final String currentNotes;

  @override
  State<_TailoringReviewDialog> createState() => _TailoringReviewDialogState();
}

class _TailoringReviewDialogState extends State<_TailoringReviewDialog> {
  late final TextEditingController _notes;
  final Set<String> _selectedSkills = {};
  bool _confirmSkills = false;

  @override
  void initState() {
    super.initState();
    _notes = TextEditingController(text: widget.currentNotes);
  }

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  void _apply() {
    Navigator.pop(
      context,
      _TailoringSelection(
        skillsToAdd: _confirmSkills ? _selectedSkills.toList() : const [],
        rewrites: {
          for (final suggestion in widget.experienceSuggestions)
            if (suggestion.selected)
              suggestion.experienceIndex:
                  suggestion.revisedController.text.trim(),
        },
        tailoringNotes: _notes.text,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.sizeOf(context);
    final canApplySkills = _selectedSkills.isEmpty || _confirmSkills;
    return AlertDialog(
      title: const Text('Review suggestions for this job'),
      content: SizedBox(
        width: screenSize.width < 720 ? screenSize.width * 0.78 : 620,
        height: screenSize.height * 0.62,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Nothing is changed until you select it. Suggested skills are '
              'not claims about you.',
              style: TextStyle(color: _muted, fontSize: 13, height: 1.45),
            ),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 16),
                    _ReviewSectionTitle(
                      title: 'Skills already in your resume',
                      subtitle: 'These were found in your current skills list.',
                    ),
                    Text(
                      widget.matchedSkills.isEmpty
                          ? 'No current skills matched the job description.'
                          : widget.matchedSkills.join(', '),
                      style: const TextStyle(color: _ink, fontSize: 13),
                    ),
                    const SizedBox(height: 18),
                    _ReviewSectionTitle(
                      title: 'Possible skills to add',
                      subtitle:
                          'Select only skills you genuinely have and can discuss.',
                    ),
                    if (widget.suggestedSkills.isEmpty)
                      const Text(
                        'No additional skill suggestions.',
                        style: TextStyle(color: _muted, fontSize: 12),
                      ),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        for (final skill in widget.suggestedSkills)
                          FilterChip(
                            label: Text(skill),
                            selected: _selectedSkills.contains(skill),
                            onSelected: (selected) => setState(() {
                              if (selected) {
                                _selectedSkills.add(skill);
                              } else {
                                _selectedSkills.remove(skill);
                              }
                              if (_selectedSkills.isEmpty) {
                                _confirmSkills = false;
                              }
                            }),
                          ),
                      ],
                    ),
                    if (_selectedSkills.isNotEmpty)
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        value: _confirmSkills,
                        onChanged: (value) => setState(
                          () => _confirmSkills = value ?? false,
                        ),
                        title: const Text(
                          'I confirm these selected skills are mine',
                        ),
                        controlAffinity: ListTileControlAffinity.leading,
                      ),
                    const SizedBox(height: 18),
                    _ReviewSectionTitle(
                      title: 'Experience rewrites',
                      subtitle:
                          'Select and edit any rewrite you want to apply. Unselected text stays as-is.',
                    ),
                    if (widget.experienceSuggestions.isEmpty)
                      const Text(
                        'No supported rewrites were suggested.',
                        style: TextStyle(color: _muted, fontSize: 12),
                      ),
                    for (final suggestion in widget.experienceSuggestions)
                      _experienceRewrite(suggestion),
                    if (widget.recommendations.isNotEmpty) ...[
                      const SizedBox(height: 18),
                      _ReviewSectionTitle(
                        title: 'Other recommendations',
                        subtitle: 'Review these suggestions yourself.',
                      ),
                      for (final recommendation in widget.recommendations)
                        _bullet(recommendation),
                    ],
                    if (widget.questions.isNotEmpty) ...[
                      const SizedBox(height: 18),
                      _ReviewSectionTitle(
                        title: 'Questions for you',
                        subtitle:
                            'Answer these to make the resume more specific.',
                      ),
                      for (final question in widget.questions)
                        _bullet(question),
                    ],
                    const SizedBox(height: 18),
                    _ReviewSectionTitle(
                      title: 'Your instructions',
                      subtitle:
                          'Add anything else you want emphasized or removed.',
                    ),
                    TextField(
                      controller: _notes,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        hintText: 'Your preferences for this application…',
                        alignLabelWithHint: true,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const _Notice(
                      icon: Icons.fact_check_outlined,
                      text:
                          'AI edits are drafts. Verify every detail before using.',
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Keep current resume'),
        ),
        FilledButton(
          onPressed: canApplySkills ? _apply : null,
          child: const Text('Apply selected changes'),
        ),
      ],
    );
  }

  Widget _experienceRewrite(_ExperienceSuggestion suggestion) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          value: suggestion.selected,
          onChanged: (value) =>
              setState(() => suggestion.selected = value ?? false),
          title: Text('Rewrite experience ${suggestion.experienceIndex + 1}'),
          controlAffinity: ListTileControlAffinity.leading,
        ),
        if (suggestion.selected)
          Padding(
            padding: const EdgeInsets.only(left: 42, bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Current',
                  style: TextStyle(color: _muted, fontSize: 11),
                ),
                const SizedBox(height: 4),
                Text(suggestion.original),
                const SizedBox(height: 10),
                TextField(
                  controller: suggestion.revisedController,
                  maxLines: 5,
                  decoration: const InputDecoration(
                    labelText: 'Proposed rewrite (editable)',
                    alignLabelWithHint: true,
                  ),
                ),
                for (final question in suggestion.questions) _bullet(question),
              ],
            ),
          ),
      ],
    );
  }

  Widget _bullet(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('•  '),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

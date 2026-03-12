import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:table_calendar/table_calendar.dart';
import 'dart:math' as math;
import 'firebase_options.dart';

enum AppLanguage { ko, en }

final ValueNotifier<AppLanguage> appLanguageNotifier =
    ValueNotifier<AppLanguage>(AppLanguage.ko);
const _languagePrefKey = 'app_language';

bool get isEnglish => appLanguageNotifier.value == AppLanguage.en;

String tr(String ko, String en) => isEnglish ? en : ko;

Future<void> _loadSavedLanguage() async {
  final prefs = await SharedPreferences.getInstance();
  final saved = prefs.getString(_languagePrefKey);
  if (saved == 'en') {
    appLanguageNotifier.value = AppLanguage.en;
  } else {
    appLanguageNotifier.value = AppLanguage.ko;
  }
}

Future<void> setAppLanguage(AppLanguage language) async {
  if (appLanguageNotifier.value != language) {
    appLanguageNotifier.value = language;
  }
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(
    _languagePrefKey,
    language == AppLanguage.en ? 'en' : 'ko',
  );
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = true;
  try {
    await dotenv.load(fileName: '.env');
  } catch (_) {}
  await _loadSavedLanguage();

  String? firebaseError;
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    firebaseError = e.toString();
  }

  runApp(DiaryApp(firebaseError: firebaseError));
}

class DiaryApp extends StatelessWidget {
  const DiaryApp({super.key, this.firebaseError});

  final String? firebaseError;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppLanguage>(
      valueListenable: appLanguageNotifier,
      builder: (_, __, ___) {
        final colorScheme = ColorScheme.fromSeed(
          seedColor: const Color(0xFF4F6D7A),
          brightness: Brightness.light,
        );

        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: tr('다이어리', 'Diary'),
          theme: ThemeData(
            useMaterial3: true,
            colorScheme: colorScheme,
            scaffoldBackgroundColor: Colors.white,
            textTheme: GoogleFonts.notoSansKrTextTheme(
              Theme.of(context).textTheme,
            ),
          ),
          home: firebaseError == null
              ? AuthGate()
              : FirebaseSetupErrorPage(error: firebaseError!),
        );
      },
    );
  }
}

class FirebaseSetupErrorPage extends StatelessWidget {
  const FirebaseSetupErrorPage({super.key, required this.error});

  final String error;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.warning_amber_rounded, size: 48),
              const SizedBox(height: 12),
              Text(
                isEnglish
                    ? 'Firebase initialization failed.'
                    : 'Firebase 초기화에 실패했습니다.',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
              Text(
                isEnglish
                    ? 'Please connect Firebase config files and restart the app.'
                    : 'Firebase 설정 파일을 연결한 뒤 앱을 다시 실행해주세요.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(error, textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final user = snapshot.data;
        if (user == null || user.email == null) {
          return AuthPage();
        }

        return DiaryHomePage(userEmail: user.email!);
      },
    );
  }
}

class AuthPage extends StatefulWidget {
  const AuthPage({super.key});

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _isLoginMode = true;
  bool _isLoading = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    final confirmPassword = _confirmPasswordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      _showSnackBar(
        tr('이메일과 비밀번호를 입력해주세요.', 'Please enter your email and password.'),
      );
      return;
    }
    if (!_isLoginMode && confirmPassword.isEmpty) {
      _showSnackBar(
        tr('비밀번호 확인을 입력해주세요.', 'Please enter password confirmation.'),
      );
      return;
    }
    if (!_isLoginMode && password != confirmPassword) {
      _showSnackBar(tr('비밀번호가 일치하지 않습니다.', 'Passwords do not match.'));
      return;
    }

    setState(() => _isLoading = true);
    try {
      final profileRef = FirebaseFirestore.instance
          .collection(email)
          .doc('_profile');

      if (_isLoginMode) {
        await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: email,
          password: password,
        );
      } else {
        final credential = await FirebaseAuth.instance
            .createUserWithEmailAndPassword(email: email, password: password);

        await profileRef.set({
          'email': email,
          'password': password,
          'uid': credential.user?.uid,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
    } on FirebaseAuthException catch (e) {
      _showSnackBar(_authErrorMessage(e));
    } catch (_) {
      _showSnackBar(
        tr('로그인 처리 중 오류가 발생했습니다.', 'An error occurred during authentication.'),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showSnackBar(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  String _authErrorMessage(FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-email':
        return tr('이메일 형식이 올바르지 않습니다.', 'Invalid email format.');
      case 'user-not-found':
        return tr('가입된 사용자가 없습니다.', 'User not found.');
      case 'wrong-password':
      case 'invalid-credential':
        return tr('이메일 또는 비밀번호가 올바르지 않습니다.', 'Incorrect email or password.');
      case 'email-already-in-use':
        return tr('이미 가입된 이메일입니다.', 'Email is already registered.');
      case 'weak-password':
        return tr(
          '비밀번호는 6자 이상이어야 합니다.',
          'Password must be at least 6 characters.',
        );
      default:
        return e.message ??
            tr('인증 오류가 발생했습니다.', 'Authentication error occurred.');
    }
  }

  @override
  Widget build(BuildContext context) {
    const pageBg = Colors.white;
    const panelBg = Color(0xFFF3F4F6);
    const lineColor = Color(0xFFE4E7EC);
    const textMain = Color(0xFF1F2937);
    const textSub = Color(0xFF8A94A6);
    const accent = Color(0xFF111827);

    return Scaffold(
      backgroundColor: pageBg,
      body: SafeArea(
        child: Stack(
          children: [
            Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Column(
                          children: [
                            Text(
                              tr('나의 일기', 'My Diary'),
                              style: GoogleFonts.nanumPenScript(
                                color: textMain,
                                fontSize: 55,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.5,
                              ),
                            ),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(18),
                              child: Container(
                                color: Colors.white,
                                padding: const EdgeInsets.all(6),
                                child: Image.asset(
                                  _isLoginMode
                                      ? 'assets/lLogin.png'
                                      : 'assets/Register.png',
                                  height: 240,
                                  fit: BoxFit.contain,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
                        decoration: BoxDecoration(
                          color: panelBg,
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: lineColor),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _isLoginMode
                                  ? tr('로그인', 'Login')
                                  : tr('회원가입', 'Sign Up'),
                              style: GoogleFonts.nanumPenScript(
                                color: textMain,
                                fontSize: 40,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.5,
                              ),
                            ),
                            const SizedBox(height: 18),
                            TextField(
                              controller: _emailController,
                              keyboardType: TextInputType.emailAddress,
                              style: GoogleFonts.gowunDodum(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                              decoration: InputDecoration(
                                labelText: tr('이메일', 'Email'),
                                labelStyle: GoogleFonts.gowunDodum(
                                  color: textSub,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(
                                    color: lineColor,
                                  ),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(
                                    color: lineColor,
                                  ),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(
                                    color: accent,
                                    width: 1.4,
                                  ),
                                ),
                                filled: true,
                                fillColor: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: _passwordController,
                              obscureText: true,
                              style: GoogleFonts.gowunDodum(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                              decoration: InputDecoration(
                                labelText: tr('비밀번호', 'Password'),
                                labelStyle: GoogleFonts.gowunDodum(
                                  color: textSub,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(
                                    color: lineColor,
                                  ),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(
                                    color: lineColor,
                                  ),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(
                                    color: accent,
                                    width: 1.4,
                                  ),
                                ),
                                filled: true,
                                fillColor: Colors.white,
                              ),
                            ),
                            if (!_isLoginMode) ...[
                              const SizedBox(height: 12),
                              TextField(
                                controller: _confirmPasswordController,
                                obscureText: true,
                                style: GoogleFonts.gowunDodum(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                                decoration: InputDecoration(
                                  labelText: tr('비밀번호 확인', 'Confirm Password'),
                                  labelStyle: GoogleFonts.gowunDodum(
                                    color: textSub,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: const BorderSide(
                                      color: lineColor,
                                    ),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: const BorderSide(
                                      color: lineColor,
                                    ),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: const BorderSide(
                                      color: accent,
                                      width: 1.4,
                                    ),
                                  ),
                                  filled: true,
                                  fillColor: Colors.white,
                                ),
                              ),
                            ],
                            const SizedBox(height: 18),
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton(
                                onPressed: _isLoading ? null : _submit,
                                style: FilledButton.styleFrom(
                                  backgroundColor: accent,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                child: Text(
                                  _isLoginMode
                                      ? tr('로그인', 'Login')
                                      : tr('회원가입', 'Sign Up'),
                                  style: GoogleFonts.nanumPenScript(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: Align(
                                    alignment: Alignment.centerLeft,
                                    child: TextButton(
                                      onPressed: _isLoading
                                          ? null
                                          : () {
                                              setState(() {
                                                _isLoginMode = !_isLoginMode;
                                                _confirmPasswordController
                                                    .clear();
                                              });
                                            },
                                      style: TextButton.styleFrom(
                                        foregroundColor: textSub,
                                      ),
                                      child: Text(
                                        _isLoginMode
                                            ? tr(
                                                '계정이 없으신가요? 회원가입',
                                                "Don't have an account? Sign up",
                                              )
                                            : tr(
                                                '이미 계정이 있나요? 로그인',
                                                'Already have an account? Login',
                                              ),
                                        style: GoogleFonts.nanumPenScript(
                                          fontSize: 15,
                                          color: textSub,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF3F4F6),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: const Color(0xFFE4E7EC),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(
                                        Icons.language_rounded,
                                        size: 16,
                                        color: textSub,
                                      ),
                                      const SizedBox(width: 6),
                                      _LanguageChip(
                                        selected: !isEnglish,
                                        label: '🇰🇷 한국어',
                                        onTap: () =>
                                            setAppLanguage(AppLanguage.ko),
                                      ),
                                      const SizedBox(width: 4),
                                      _LanguageChip(
                                        selected: isEnglish,
                                        label: '🇺🇸 English',
                                        onTap: () =>
                                            setAppLanguage(AppLanguage.en),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LanguageChip extends StatelessWidget {
  const _LanguageChip({
    required this.selected,
    required this.label,
    required this.onTap,
  });

  final bool selected;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFDDE4FF) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? const Color(0xFF30417A) : const Color(0xFF8A94A6),
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class DiaryHomePage extends StatefulWidget {
  const DiaryHomePage({super.key, required this.userEmail});

  final String userEmail;

  @override
  State<DiaryHomePage> createState() => _DiaryHomePageState();
}

class _DiaryHomePageState extends State<DiaryHomePage> {
  static const MethodChannel _widgetChannel = MethodChannel(
    'diary/home_widget',
  );

  late DateTime _focusedDay;
  late DateTime _selectedDay;
  late DateTime _listMonthAnchor;
  bool _isListMode = false;
  final List<MoodOption> _customMoodOptions = [];
  String? _lastWidgetPayload;

  Map<String, MoodOption> get _moodByKey {
    final all = [...kMoodOptions, ..._customMoodOptions];
    return {for (final mood in all) mood.key: mood};
  }

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _focusedDay = now;
    _selectedDay = _normalizeDate(now);
    _listMonthAnchor = DateTime(now.year, now.month, 1);
    _ensureAssetsCached().then((_) {
      if (mounted) setState(() {});
    });
    _loadCustomMoods();
  }

  Future<void> _loadCustomMoods() async {
    try {
      final doc = await _userCollection.doc('_custom_moods').get();
      final moods = doc.exists
          ? ((doc.data()?['moods'] as List<dynamic>?) ?? <dynamic>[])
          : <dynamic>[];
      final seenKeys = <String>{};
      final seenUrls = <String>{};
      final uniqueMoodRows = <Map<String, dynamic>>[];

      for (final raw in moods) {
        if (raw is! Map) continue;
        final moodData = raw.map((k, v) => MapEntry(k.toString(), v));
        final key = (moodData['key'] ?? '').toString();
        final storageUrl = (moodData['storageUrl'] ?? '').toString();
        final storagePath = (moodData['storagePath'] ?? '').toString();
        if (key.isEmpty || (storageUrl.isEmpty && storagePath.isEmpty))
          continue;
        if (seenKeys.contains(key) || seenUrls.contains(storageUrl)) continue;
        seenKeys.add(key);
        if (storageUrl.isNotEmpty) seenUrls.add(storageUrl);
        uniqueMoodRows.add({
          'key': key,
          'storageUrl': storageUrl,
          'storagePath': storagePath,
        });
      }
      var usedStorageFallback = false;
      if (uniqueMoodRows.isEmpty) {
        uniqueMoodRows.addAll(await _listMoodRowsFromStorage(widget.userEmail));
        usedStorageFallback = uniqueMoodRows.isNotEmpty;
      }

      final loadedOptions = <MoodOption>[];
      final cleanedRows = <Map<String, dynamic>>[];
      final seenImageSignatures = <String>{};

      for (final moodData in uniqueMoodRows) {
        final key = (moodData['key'] ?? '').toString();
        final storageUrl = (moodData['storageUrl'] ?? '').toString();
        final storagePath = (moodData['storagePath'] ?? '').toString();
        try {
          final ref = storageUrl.isNotEmpty
              ? FirebaseStorage.instance.refFromURL(storageUrl)
              : FirebaseStorage.instance.ref().child(storagePath);
          final bytes = await ref.getData();
          if (bytes == null || !mounted) continue;
          final signature = base64Encode(bytes);
          if (seenImageSignatures.contains(signature)) {
            continue;
          }
          seenImageSignatures.add(signature);
          cleanedRows.add({
            'key': key,
            'storageUrl': storageUrl,
            'storagePath': ref.fullPath,
          });
          loadedOptions.add(
            MoodOption.custom(
              key: key,
              label: tr('커스텀', 'Custom'),
              customIconBytes: bytes,
            ),
          );
        } catch (_) {}
      }

      if (cleanedRows.isNotEmpty &&
          (usedStorageFallback || cleanedRows.length != moods.length || !doc.exists)) {
        await _userCollection.doc('_custom_moods').set({'moods': cleanedRows});
      }
      if (!mounted) return;
      setState(() {
        _customMoodOptions
          ..clear()
          ..addAll(loadedOptions);
      });
    } catch (_) {}
  }

  bool _isBuiltInMood(String key) {
    return kMoodOptions.any((mood) => mood.key == key);
  }

  bool _canDeleteCustomMood(String key) {
    return !_isBuiltInMood(key) &&
        _customMoodOptions.any((mood) => mood.key == key);
  }

  String _widgetEmojiFromDiaryData(Map<String, dynamic> data) {
    final mood = _resolveMoodFromDiary(data);
    return mood?.fallbackEmoji ?? '없음';
  }

  Future<String> _widgetImageBase64FromMood(MoodOption? mood) async {
    if (mood == null) return '';
    if (mood.customIconBase64 != null && mood.customIconBase64!.isNotEmpty) {
      return mood.customIconBase64!;
    }
    if (mood.customIconBytes != null && mood.customIconBytes!.isNotEmpty) {
      return base64Encode(mood.customIconBytes!);
    }
    if (mood.assetPath.isEmpty) return '';
    try {
      final cached = _globalAssetCache[mood.key];
      if (cached != null && cached.isNotEmpty) {
        return base64Encode(cached);
      }
      final data = await rootBundle.load(mood.assetPath);
      final bytes = data.buffer.asUint8List();
      if (bytes.isNotEmpty) {
        _globalAssetCache[mood.key] = bytes;
        return base64Encode(bytes);
      }
    } catch (_) {}
    return '';
  }

  Future<void> _syncWidgetEmojis(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> diaries,
  ) async {
    final normalized = <Map<String, dynamic>>[];
    for (final diary in diaries) {
      final data = diary.data();
      final writtenAt = data['writtenAt'];
      if (writtenAt is! Timestamp) {
        continue;
      }
      final mood = _resolveMoodFromDiary(data);
      normalized.add({
        'day': _normalizeDate(writtenAt.toDate()),
        'emoji': mood?.fallbackEmoji ?? _widgetEmojiFromDiaryData(data),
        'image': await _widgetImageBase64FromMood(mood),
      });
    }
    normalized.sort(
      (a, b) => (b['day'] as DateTime).compareTo(a['day'] as DateTime),
    );

    final today = _normalizeDate(DateTime.now());
    String todayEmoji = '';
    String todayImage = '';
    for (final item in normalized) {
      if (isSameDay(item['day'] as DateTime, today)) {
        todayEmoji = (item['emoji'] ?? '').toString();
        todayImage = (item['image'] ?? '').toString();
        break;
      }
    }
    final recentEmojis = normalized
        .take(9)
        .map((item) => (item['emoji'] ?? '').toString())
        .map((emoji) => emoji.isEmpty ? '없음' : emoji)
        .toList();
    final recentImages = normalized
        .take(9)
        .map((item) => (item['image'] ?? '').toString())
        .toList();
    final monthKey =
        '${today.year.toString().padLeft(4, '0')}-${today.month.toString().padLeft(2, '0')}';
    final monthEmojiByDay = <String, String>{};
    final monthImageByDay = <String, String>{};
    for (final item in normalized) {
      final day = item['day'] as DateTime;
      if (day.year != today.year || day.month != today.month) {
        continue;
      }
      final dayKey = '${day.day}';
      if (monthEmojiByDay.containsKey(dayKey)) {
        continue;
      }
      final emoji = (item['emoji'] ?? '').toString();
      if (emoji.isNotEmpty) {
        monthEmojiByDay[dayKey] = emoji;
      }
      final image = (item['image'] ?? '').toString();
      if (image.isNotEmpty) {
        monthImageByDay[dayKey] = image;
      }
    }
    final payload = jsonEncode({
      'today': todayEmoji,
      'todayImage': todayImage,
      'recent': recentEmojis,
      'recentImages': recentImages,
      'month': monthKey,
      'monthMap': monthEmojiByDay,
      'monthMapImages': monthImageByDay,
    });
    if (_lastWidgetPayload == payload) {
      return;
    }
    final previousPayload = _lastWidgetPayload;
    _lastWidgetPayload = payload;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('widget_today_emoji', todayEmoji);
      await prefs.setString('widget_today_image_base64', todayImage);
      await prefs.setString(
        'widget_recent_emojis_json',
        jsonEncode(recentEmojis),
      );
      await prefs.setString(
        'widget_recent_images_json',
        jsonEncode(recentImages),
      );
      await prefs.setString('widget_month_key', monthKey);
      await prefs.setString(
        'widget_month_map_json',
        jsonEncode(monthEmojiByDay),
      );
      await prefs.setString(
        'widget_month_map_images_json',
        jsonEncode(monthImageByDay),
      );
      await prefs.setInt(
        'widget_updated_at',
        DateTime.now().millisecondsSinceEpoch,
      );
      await _widgetChannel.invokeMethod('updateDiaryWidget', {
        'today': todayEmoji,
        'todayImage': todayImage,
        'recent': recentEmojis,
        'recentImages': recentImages,
        'month': monthKey,
        'monthMap': monthEmojiByDay,
        'monthMapImages': monthImageByDay,
      });
    } catch (_) {
      _lastWidgetPayload = previousPayload;
    }
  }

  Future<void> _deleteCustomMood(String key) async {
    if (!_canDeleteCustomMood(key)) return;
    try {
      final docRef = FirebaseFirestore.instance
          .collection(widget.userEmail)
          .doc('_custom_moods');
      final doc = await docRef.get();
      final moods = doc.exists
          ? ((doc.data()?['moods'] as List<dynamic>?) ?? <dynamic>[])
          : <dynamic>[];
      final remaining = <Map<String, dynamic>>[];
      final urlsToDelete = <String>{};
      final pathsToDelete = <String>{};
      for (final raw in moods) {
        if (raw is! Map) continue;
        final row = raw.map((k, v) => MapEntry(k.toString(), v));
        final rowKey = (row['key'] ?? '').toString();
        final rowUrl = (row['storageUrl'] ?? '').toString();
        final rowPath = (row['storagePath'] ?? '').toString();
        if (rowKey == key) {
          if (rowUrl.isNotEmpty) urlsToDelete.add(rowUrl);
          if (rowPath.isNotEmpty) pathsToDelete.add(rowPath);
          continue;
        }
        if (rowKey.isNotEmpty && (rowUrl.isNotEmpty || rowPath.isNotEmpty)) {
          remaining.add({
            'key': rowKey,
            'storageUrl': rowUrl,
            'storagePath': rowPath,
          });
        }
      }
      await docRef.set({'moods': remaining});
      for (final url in urlsToDelete) {
        try {
          await FirebaseStorage.instance.refFromURL(url).delete();
        } catch (_) {}
      }
      for (final path in pathsToDelete) {
        try {
          await FirebaseStorage.instance.ref().child(path).delete();
        } catch (_) {}
      }
      // Fallback: older/dirty rows without URL/path metadata.
      if (urlsToDelete.isEmpty && pathsToDelete.isEmpty) {
        try {
          await FirebaseStorage.instance
              .ref()
              .child('${widget.userEmail}/mood_icons/$key.png')
              .delete();
        } catch (_) {}
      }
      if (!mounted) return;
      setState(() {
        _customMoodOptions.removeWhere((mood) => mood.key == key);
      });
    } catch (_) {}
  }

  Future<void> _confirmDeleteCustomMood(
    MoodOption mood, {
    VoidCallback? onDeleted,
  }) async {
    if (!_canDeleteCustomMood(mood.key)) return;
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) {
        const panelBg = Color(0xFFFCFCFD);
        const lineColor = Color(0xFFE4E7EC);
        const textMain = Color(0xFF1F2937);
        const textSub = Color(0xFF8A94A6);
        const danger = Color(0xFFEF4444);
        return AlertDialog(
          backgroundColor: panelBg,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: const BorderSide(color: lineColor),
          ),
          titlePadding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
          contentPadding: const EdgeInsets.fromLTRB(20, 6, 20, 8),
          actionsPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          title: Row(
            children: [
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: danger.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.delete_outline_rounded,
                  size: 16,
                  color: danger,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                tr('아이콘 삭제', 'Delete Icon'),
                style: const TextStyle(
                  color: textMain,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          content: Text(
            tr(
              '이 커스텀 아이콘을 삭제할까요?\n삭제 후 복구할 수 없습니다.',
              'Delete this custom icon?\nThis action cannot be undone.',
            ),
            style: const TextStyle(color: textSub, fontSize: 14, height: 1.4),
          ),
          actions: [
            TextButton(
              style: TextButton.styleFrom(
                foregroundColor: textSub,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
              ),
              onPressed: () => Navigator.of(dialogCtx).pop(false),
              child: Text(tr('취소', 'Cancel')),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: danger,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 9,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: () => Navigator.of(dialogCtx).pop(true),
              child: Text(tr('삭제', 'Delete')),
            ),
          ],
        );
      },
    );
    if (shouldDelete != true) return;
    await _deleteCustomMood(mood.key);
    onDeleted?.call();
  }

  Future<bool> _saveCustomMoodToStorage(String key, Uint8List bytes) async {
    try {
      final ref = FirebaseStorage.instance
          .ref()
          .child(widget.userEmail)
          .child('mood_icons')
          .child('$key.png');
      await ref.putData(bytes, SettableMetadata(contentType: 'image/png'));
      final url = await ref.getDownloadURL();
      final storagePath = ref.fullPath;
      final docRef = _userCollection.doc('_custom_moods');
      final doc = await docRef.get();
      final existing = doc.exists
          ? ((doc.data()?['moods'] as List<dynamic>?) ?? <dynamic>[])
          : <dynamic>[];

      final merged = <Map<String, dynamic>>[
        for (final raw in existing)
          if (raw is Map) raw.map((k, v) => MapEntry(k.toString(), v)),
        {'key': key, 'storageUrl': url, 'storagePath': storagePath},
      ];

      final seenKeys = <String>{};
      final seenUrls = <String>{};
      final dedupedReversed = <Map<String, dynamic>>[];
      for (final item in merged.reversed) {
        final itemKey = (item['key'] ?? '').toString();
        final itemUrl = (item['storageUrl'] ?? '').toString();
        final itemPath = (item['storagePath'] ?? '').toString();
        if (itemKey.isEmpty || (itemUrl.isEmpty && itemPath.isEmpty)) continue;
        if (seenKeys.contains(itemKey) || seenUrls.contains(itemUrl)) continue;
        seenKeys.add(itemKey);
        if (itemUrl.isNotEmpty) seenUrls.add(itemUrl);
        dedupedReversed.add({
          'key': itemKey,
          'storageUrl': itemUrl,
          'storagePath': itemPath,
        });
      }

      await docRef.set({'moods': dedupedReversed.reversed.toList()});
      return true;
    } catch (_) {
      return false;
    }
  }

  CollectionReference<Map<String, dynamic>> get _userCollection {
    return FirebaseFirestore.instance.collection(widget.userEmail);
  }

  Future<void> _openEditPage(String docId, Map<String, dynamic> data) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => NewDiaryPage(
          userEmail: widget.userEmail,
          initialDate: (data['writtenAt'] is Timestamp)
              ? (data['writtenAt'] as Timestamp).toDate()
              : DateTime.now(),
          initialMoodKey: (data['moodKey'] ?? '').toString(),
          initialMoodCustomBase64:
              (data['moodCustomIcon'] ?? '').toString().isEmpty
              ? null
              : data['moodCustomIcon'].toString(),
          docId: docId,
          initialTitle: (data['title'] ?? '').toString(),
          initialContentBlocks: _contentBlocksFromData(data),
        ),
      ),
    );
  }

  Future<void> _openDiaryFullView(Map<String, dynamic> data) async {
    final mood = _resolveMoodFromDiary(data);
    final title = (data['title'] ?? '').toString();
    final blocks = _contentBlocksFromData(data);
    final fallbackContent = (data['content'] ?? '').toString();
    final fallbackImageUrl = (data['imageUrl'] ?? '').toString();
    final ts = data['writtenAt'];
    String dateLabel = '';
    if (ts is Timestamp) {
      final d = ts.toDate();
      final weekdays = isEnglish
          ? const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']
          : const ['월', '화', '수', '목', '금', '토', '일'];
      final dateText =
          '${d.year}.${d.month.toString().padLeft(2, '0')}.${d.day.toString().padLeft(2, '0')}';
      dateLabel = isEnglish
          ? '$dateText ${weekdays[d.weekday - 1]}'
          : '$dateText ${weekdays[d.weekday - 1]}요일';
    }

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: const Color(0xFFF7F7F8),
          appBar: AppBar(
            backgroundColor: const Color(0xFFF7F7F8),
            surfaceTintColor: Colors.transparent,
          ),
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                ),
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (mood != null) ...[
                          _buildMoodAsset(mood, size: 26),
                          const SizedBox(width: 8),
                        ],
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF111827),
                                ),
                              ),
                              if (dateLabel.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  dateLabel,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF9CA3AF),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Divider(height: 1),
                    const SizedBox(height: 14),
                    blocks.isNotEmpty
                        ? _buildReadOnlyBlocks(blocks, contentTextSize: 16)
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (fallbackImageUrl.isNotEmpty) ...[
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: Image.network(
                                    fallbackImageUrl,
                                    width: double.infinity,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                                const SizedBox(height: 10),
                              ],
                              Text(
                                fallbackContent,
                                style: const TextStyle(
                                  fontSize: 16,
                                  height: 1.6,
                                  color: Color(0xFF1F2937),
                                ),
                              ),
                            ],
                          ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showDiaryActionSheet(
    String docId,
    Map<String, dynamic> data,
  ) async {
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.edit_rounded),
                title: Text(tr('수정하기', 'Edit')),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _openEditPage(docId, data);
                },
              ),
              ListTile(
                leading: const Icon(Icons.open_in_full_rounded),
                title: Text(tr('전체로 보기', 'Full View')),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _openDiaryFullView(data);
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.delete_outline_rounded,
                  color: Color(0xFFEF4444),
                ),
                title: Text(
                  tr('삭제하기', 'Delete'),
                  style: const TextStyle(color: Color(0xFFEF4444)),
                ),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _confirmDeleteDiary(docId, data);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Set<String> _collectDiaryImageUrls(Map<String, dynamic> data) {
    final urls = <String>{};
    final blocks = _contentBlocksFromData(data);
    for (final block in blocks) {
      if ((block['type'] ?? '').toString() != 'image') continue;
      final url = (block['url'] ?? '').toString().trim();
      if (url.isNotEmpty) {
        urls.add(url);
      }
    }
    final fallbackUrl = (data['imageUrl'] ?? '').toString().trim();
    if (fallbackUrl.isNotEmpty) {
      urls.add(fallbackUrl);
    }
    return urls;
  }

  Future<void> _deleteDiary(String docId, Map<String, dynamic> data) async {
    final imageUrls = _collectDiaryImageUrls(data);
    try {
      await _userCollection.doc(docId).delete();
      for (final url in imageUrls) {
        try {
          await FirebaseStorage.instance.refFromURL(url).delete();
        } catch (_) {}
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr('일기를 삭제했습니다.', 'Diary deleted.'))),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(tr('삭제 중 오류가 발생했습니다.', 'Failed to delete diary.')),
        ),
      );
    }
  }

  Future<void> _confirmDeleteDiary(
    String docId,
    Map<String, dynamic> data,
  ) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) {
        const panelBg = Color(0xFFFCFCFD);
        const lineColor = Color(0xFFE4E7EC);
        const textMain = Color(0xFF1F2937);
        const textSub = Color(0xFF8A94A6);
        const danger = Color(0xFFEF4444);

        return AlertDialog(
          backgroundColor: panelBg,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: const BorderSide(color: lineColor),
          ),
          titlePadding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
          contentPadding: const EdgeInsets.fromLTRB(20, 6, 20, 8),
          actionsPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          title: Row(
            children: [
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: danger.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.delete_outline_rounded,
                  size: 16,
                  color: danger,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                tr('일기 삭제', 'Delete Diary'),
                style: const TextStyle(
                  color: textMain,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          content: Text(
            tr(
              '이 일기를 삭제할까요?\n일기 내용과 연결된 사진도 함께 삭제됩니다.',
              'Delete this diary?\nAttached photos will be deleted too.',
            ),
            style: const TextStyle(color: textSub, fontSize: 14, height: 1.4),
          ),
          actions: [
            TextButton(
              style: TextButton.styleFrom(
                foregroundColor: textSub,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
              ),
              onPressed: () => Navigator.of(dialogCtx).pop(false),
              child: Text(tr('취소', 'Cancel')),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: danger,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 9,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: () => Navigator.of(dialogCtx).pop(true),
              child: Text(tr('삭제', 'Delete')),
            ),
          ],
        );
      },
    );
    if (shouldDelete != true) return;
    await _deleteDiary(docId, data);
  }

  Future<void> _openWritePageWithMood(
    String initialMoodKey, {
    String? initialMoodCustomBase64,
  }) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => NewDiaryPage(
          userEmail: widget.userEmail,
          // 달력에서 고른 날짜를 기본 작성일로 사용
          initialDate: _selectedDay,
          initialMoodKey: initialMoodKey,
          initialMoodCustomBase64: initialMoodCustomBase64,
        ),
      ),
    );
  }

  Future<void> _openListMonthYearPicker() async {
    final minYear = 2000;
    final maxYear = 2100;
    var tempYear = _listMonthAnchor.year;
    var tempMonth = _listMonthAnchor.month;
    final yearController = FixedExtentScrollController(
      initialItem: tempYear - minYear,
    );
    final monthController = FixedExtentScrollController(
      initialItem: tempMonth - 1,
    );

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: const Color(0xFFF7F7F8),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final preview = DateTime(tempYear, tempMonth, 1);
            final title = isEnglish
                ? '${preview.year} ${preview.month}'
                : '${preview.year}년 ${preview.month}월';
            return SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF3B3B3B),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 180,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          IgnorePointer(
                            child: Container(
                              height: 34,
                              margin: const EdgeInsets.symmetric(horizontal: 6),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF0F1F2),
                                borderRadius: BorderRadius.circular(9),
                              ),
                            ),
                          ),
                          Row(
                            children: [
                              Expanded(
                                child: CupertinoPicker(
                                  scrollController: yearController,
                                  itemExtent: 42,
                                  selectionOverlay: const SizedBox.shrink(),
                                  onSelectedItemChanged: (index) {
                                    setSheetState(() {
                                      tempYear = minYear + index;
                                    });
                                  },
                                  children: [
                                    for (int y = minYear; y <= maxYear; y++)
                                      Center(
                                        child: Text(
                                          isEnglish ? '$y' : '${y}년',
                                          style: const TextStyle(
                                            fontSize: 22,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              Expanded(
                                child: CupertinoPicker(
                                  scrollController: monthController,
                                  itemExtent: 42,
                                  selectionOverlay: const SizedBox.shrink(),
                                  onSelectedItemChanged: (index) {
                                    setSheetState(() {
                                      tempMonth = index + 1;
                                    });
                                  },
                                  children: [
                                    for (int m = 1; m <= 12; m++)
                                      Center(
                                        child: Text(
                                          isEnglish ? '$m' : '${m}월',
                                          style: const TextStyle(
                                            fontSize: 22,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.tonal(
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFFEBEBED),
                              foregroundColor: const Color(0xFF4A4A4A),
                              minimumSize: const Size.fromHeight(44),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            onPressed: () =>
                                Navigator.of(sheetContext).pop(false),
                            child: Text(tr('취소', 'Cancel')),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: const Color(0xFF4A4A4A),
                              minimumSize: const Size.fromHeight(44),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                                side: const BorderSide(
                                  color: Color(0xFFE1E1E1),
                                ),
                              ),
                            ),
                            onPressed: () =>
                                Navigator.of(sheetContext).pop(true),
                            child: Text(tr('확인', 'Done')),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (confirmed != true || !mounted) {
      return;
    }

    setState(() {
      _listMonthAnchor = DateTime(tempYear, tempMonth, 1);
      final lastDay = DateTime(tempYear, tempMonth + 1, 0).day;
      final selectedDay = _selectedDay.day.clamp(1, lastDay).toInt();
      _selectedDay = DateTime(tempYear, tempMonth, selectedDay);
      _focusedDay = _selectedDay;
    });
  }

  Future<void> _openMoodPickerAndWrite() async {
    await _loadCustomMoods();
    if (!mounted) return;
    var deleteMode = false;
    var selectedTabIndex = 0; // 0: 기본, 1: 나의 것
    final sheetBuiltInMoodOptions = <MoodOption>[...kMoodOptions];
    final sheetCustomMoodOptions = <MoodOption>[..._customMoodOptions];
    final pickedKey = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (builderContext, setSheetState) {
            return FractionallySizedBox(
              heightFactor: 0.9,
              child: Container(
                decoration: const BoxDecoration(
                  color: Color(0xFFFCFCFD),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
                ),
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                child: SafeArea(
                  top: false,
                  child: Column(
                    children: [
                      Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: const Color(0xFFD4D7DD),
                          borderRadius: BorderRadius.circular(99),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              tr('오늘은 어떤 기분인가요?', 'How are you feeling today?'),
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF1F2937),
                              ),
                            ),
                          ),
                          if (selectedTabIndex == 1)
                            OutlinedButton.icon(
                              onPressed: () {
                                setSheetState(() {
                                  deleteMode = !deleteMode;
                                });
                              },
                              style: OutlinedButton.styleFrom(
                                foregroundColor: const Color(0xFF4B5563),
                                side: const BorderSide(
                                  color: Color(0xFFD1D5DB),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              icon: Icon(
                                deleteMode
                                    ? Icons.check_circle_outline_rounded
                                    : Icons.delete_outline_rounded,
                                size: 16,
                              ),
                              label: Text(
                                deleteMode
                                    ? tr('완료', 'Done')
                                    : tr('삭제', 'Delete'),
                                style: const TextStyle(fontSize: 13),
                              ),
                            ),
                          const SizedBox(width: 8),
                          FilledButton.icon(
                            onPressed: () async {
                              final customBytes = await showDialog<Uint8List>(
                                context: context,
                                builder: (_) => const _CustomMoodDrawDialog(),
                              );
                              if (customBytes == null || !mounted) return;
                              final key =
                                  'custom_${DateTime.now().millisecondsSinceEpoch}';
                              final newMood = MoodOption.custom(
                                key: key,
                                label: tr('커스텀', 'Custom'),
                                customIconBytes: customBytes,
                              );
                              setState(() => _customMoodOptions.add(newMood));
                              setSheetState(() {
                                sheetCustomMoodOptions.add(newMood);
                                selectedTabIndex = 1;
                                deleteMode = false;
                              });
                              final saved = await _saveCustomMoodToStorage(
                                key,
                                customBytes,
                              );
                              if (!saved && mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      tr(
                                        '아이콘 저장 정보 동기화에 실패했어요. 다시 시도해주세요.',
                                        'Failed to sync icon metadata. Please try again.',
                                      ),
                                    ),
                                  ),
                                );
                              }
                            },
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFF1E1E1E),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 8,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            icon: const Icon(Icons.add_rounded, size: 16),
                            label: Text(
                              tr('아이콘 추가', 'Add Icon'),
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          _buildMoodTab(
                            label: tr('기본', 'Default'),
                            selected: selectedTabIndex == 0,
                            onTap: () {
                              setSheetState(() {
                                selectedTabIndex = 0;
                                deleteMode = false;
                              });
                            },
                          ),
                          const SizedBox(width: 14),
                          _buildMoodTab(
                            label: tr('나의 것', 'Mine'),
                            selected: selectedTabIndex == 1,
                            onTap: () {
                              setSheetState(() {
                                selectedTabIndex = 1;
                              });
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: Builder(
                          builder: (_) {
                            final visibleMoods = selectedTabIndex == 0
                                ? sheetBuiltInMoodOptions
                                : sheetCustomMoodOptions;
                            if (visibleMoods.isEmpty) {
                              return Center(
                                child: Text(
                                  tr(
                                    '추가한 아이콘이 없어요.\n오른쪽 위에서 아이콘을 추가해보세요.',
                                    'No custom icons yet.\nAdd one from the top-right button.',
                                  ),
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    color: Color(0xFF6B7280),
                                    height: 1.45,
                                  ),
                                ),
                              );
                            }
                            return GridView.builder(
                              itemCount: visibleMoods.length,
                              gridDelegate:
                                  const SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: 3,
                                    mainAxisSpacing: 14,
                                    crossAxisSpacing: 8,
                                    childAspectRatio: 1.05,
                                  ),
                              itemBuilder: (context, index) {
                                final mood = visibleMoods[index];
                                final canDelete =
                                    selectedTabIndex == 1 &&
                                    _canDeleteCustomMood(mood.key);
                                return Stack(
                                  children: [
                                    Positioned.fill(
                                      child: InkWell(
                                        borderRadius: BorderRadius.circular(14),
                                        onTap: deleteMode
                                            ? null
                                            : () => Navigator.of(
                                                sheetContext,
                                              ).pop(mood.key),
                                        child: Center(
                                          child: _buildMoodAsset(
                                            mood,
                                            size: 56,
                                          ),
                                        ),
                                      ),
                                    ),
                                    if (deleteMode && canDelete)
                                      Positioned(
                                        top: 2,
                                        right: 2,
                                        child: Material(
                                          color: Colors.transparent,
                                          child: InkWell(
                                            borderRadius: BorderRadius.circular(
                                              99,
                                            ),
                                            onTap: () async {
                                              await _confirmDeleteCustomMood(
                                                mood,
                                                onDeleted: () {
                                                  setSheetState(() {
                                                    sheetCustomMoodOptions
                                                        .removeWhere(
                                                          (item) =>
                                                              item.key ==
                                                              mood.key,
                                                        );
                                                  });
                                                },
                                              );
                                            },
                                            child: Container(
                                              width: 20,
                                              height: 20,
                                              decoration: const BoxDecoration(
                                                color: Color(0xFF111827),
                                                shape: BoxShape.circle,
                                              ),
                                              child: const Icon(
                                                Icons.close_rounded,
                                                size: 13,
                                                color: Colors.white,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                );
                              },
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    if (!mounted || pickedKey == null) return;

    final mood = _moodByKey[pickedKey];
    final customBase64 =
        mood?.customIconBase64 ??
        (mood?.customIconBytes != null
            ? base64Encode(mood!.customIconBytes!)
            : null);

    await _openWritePageWithMood(
      pickedKey,
      initialMoodCustomBase64: customBase64,
    );
  }

  Widget _buildMoodTab({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final textColor = selected
        ? const Color(0xFF111827)
        : const Color(0xFF9CA3AF);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: textColor,
              ),
            ),
            const SizedBox(height: 6),
            AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOut,
              width: 28,
              height: 3,
              decoration: BoxDecoration(
                color: selected ? const Color(0xFF111827) : Colors.transparent,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openSettings() async {
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFFFCFCFD),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFD4D7DD),
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            const SizedBox(height: 20),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                tr('설정', 'Settings'),
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: const Color(0xFF1F2937).withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.language_rounded,
                    size: 20,
                    color: Color(0xFF1F2937),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    tr('언어', 'Language'),
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1F2937),
                    ),
                  ),
                  const Spacer(),
                  _LanguageChip(
                    selected: !isEnglish,
                    label: '🇰🇷',
                    onTap: () {
                      Navigator.of(sheetCtx).pop();
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        setAppLanguage(AppLanguage.ko);
                      });
                    },
                  ),
                  const SizedBox(width: 4),
                  _LanguageChip(
                    selected: isEnglish,
                    label: '🇺🇸',
                    onTap: () {
                      Navigator.of(sheetCtx).pop();
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        setAppLanguage(AppLanguage.en);
                      });
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            _SettingsTile(
              icon: Icons.mail_outline_rounded,
              label: tr('문의하기', 'Contact Us'),
              onTap: () {
                Navigator.of(sheetCtx).pop();
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) _openInquiry();
                });
              },
            ),
            const SizedBox(height: 8),
            _SettingsTile(
              icon: Icons.logout_rounded,
              label: tr('로그아웃', 'Logout'),
              color: const Color(0xFFEF4444),
              onTap: () {
                Navigator.of(sheetCtx).pop();
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) _confirmLogout();
                });
              },
            ),
            const SizedBox(height: 8),
            _SettingsTile(
              icon: Icons.person_remove_alt_1_rounded,
              label: tr('계정 탈퇴', 'Delete Account'),
              color: const Color(0xFFDC2626),
              onTap: () {
                Navigator.of(sheetCtx).pop();
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) _confirmDeleteAccount();
                });
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openInquiry() async {
    String inquiryText = '';
    await showDialog(
      context: context,
      builder: (ctx) {
        const lineColor = Color(0xFFE4E7EC);
        const panelBg = Color(0xFFFCFCFD);
        const textMain = Color(0xFF1F2937);
        const textSub = Color(0xFF8A94A6);
        const accent = Color(0xFF111827);

        return StatefulBuilder(
          builder: (dialogContext, setDialogState) => AlertDialog(
            backgroundColor: panelBg,
            surfaceTintColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              side: const BorderSide(color: lineColor),
            ),
            titlePadding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
            contentPadding: const EdgeInsets.fromLTRB(20, 8, 20, 10),
            actionsPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            title: Row(
              children: [
                Icon(Icons.mail_outline_rounded, size: 18, color: accent),
                SizedBox(width: 6),
                Text(
                  tr('문의하기', 'Contact Us'),
                  style: TextStyle(
                    color: textMain,
                    fontWeight: FontWeight.w700,
                    fontSize: 17,
                  ),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tr(
                      '불편한 점이나 건의사항을 남겨주세요.\n빠르게 확인 후 답변드릴게요.',
                      'Please leave your feedback or suggestions.\nWe will review it as soon as possible.',
                    ),
                    style: TextStyle(
                      fontSize: 13,
                      color: textSub,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFFF7F8FA),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: lineColor),
                    ),
                    child: TextField(
                      maxLines: 6,
                      minLines: 6,
                      maxLength: 500,
                      onChanged: (value) {
                        inquiryText = value;
                        setDialogState(() {});
                      },
                      decoration: InputDecoration(
                        counterText: '',
                        hintText: tr(
                          '예) 앱 사용 중 불편했던 점, 개선 아이디어 등',
                          'e.g. Inconveniences while using the app, improvement ideas',
                        ),
                        hintStyle: const TextStyle(color: Color(0xFF9CA3AF)),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.fromLTRB(
                          12,
                          12,
                          12,
                          10,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      '${inquiryText.trim().length}/500',
                      style: const TextStyle(
                        color: textSub,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: textSub,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                ),
                onPressed: () => Navigator.pop(dialogContext),
                child: Text(tr('취소', 'Cancel')),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: accent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 9,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed: inquiryText.trim().isEmpty
                    ? null
                    : () async {
                        final text = inquiryText.trim();
                        Navigator.of(dialogContext).pop();
                        try {
                          await FirebaseFirestore.instance
                              .collection('inquiry')
                              .add({
                                'email': widget.userEmail,
                                'content': text,
                                'createdAt': FieldValue.serverTimestamp(),
                              });
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  tr(
                                    '문의가 접수되었습니다. 감사합니다!',
                                    'Your inquiry has been submitted. Thank you!',
                                  ),
                                ),
                              ),
                            );
                          }
                        } catch (_) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  tr(
                                    '전송 중 오류가 발생했습니다. 다시 시도해주세요.',
                                    'An error occurred while sending. Please try again.',
                                  ),
                                ),
                              ),
                            );
                          }
                        }
                      },
                child: Text(tr('보내기', 'Send')),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _confirmLogout() async {
    final shouldLogout = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        const lineColor = Color(0xFFE4E7EC);
        const panelBg = Color(0xFFFCFCFD);
        const textMain = Color(0xFF1F2937);
        const textSub = Color(0xFF8A94A6);
        const accent = Color(0xFF111827);

        return AlertDialog(
          backgroundColor: panelBg,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: const BorderSide(color: lineColor),
          ),
          titlePadding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
          contentPadding: const EdgeInsets.fromLTRB(20, 2, 20, 8),
          actionsPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          title: Row(
            children: [
              Icon(Icons.logout_rounded, size: 18, color: accent),
              SizedBox(width: 6),
              Text(
                tr('로그아웃', 'Logout'),
                style: TextStyle(
                  color: textMain,
                  fontWeight: FontWeight.w700,
                  fontSize: 17,
                ),
              ),
            ],
          ),
          content: Text(
            tr('로그아웃 하시겠습니까?', 'Do you want to log out?'),
            style: TextStyle(color: textSub, fontSize: 14, height: 1.35),
          ),
          actions: [
            TextButton(
              style: TextButton.styleFrom(
                foregroundColor: textSub,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
              ),
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(tr('아니오', 'No')),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: accent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 9,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(tr('예', 'Yes')),
            ),
          ],
        );
      },
    );

    if (shouldLogout == true) {
      await FirebaseAuth.instance.signOut();
    }
  }

  Future<void> _confirmDeleteAccount() async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        const lineColor = Color(0xFFE4E7EC);
        const panelBg = Color(0xFFFCFCFD);
        const textMain = Color(0xFF1F2937);
        const textSub = Color(0xFF8A94A6);
        const danger = Color(0xFFDC2626);

        return AlertDialog(
          backgroundColor: panelBg,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: const BorderSide(color: lineColor),
          ),
          titlePadding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
          contentPadding: const EdgeInsets.fromLTRB(20, 2, 20, 8),
          actionsPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          title: Row(
            children: [
              Icon(Icons.person_remove_alt_1_rounded, size: 18, color: danger),
              SizedBox(width: 6),
              Text(
                tr('계정 탈퇴', 'Delete Account'),
                style: TextStyle(
                  color: textMain,
                  fontWeight: FontWeight.w700,
                  fontSize: 17,
                ),
              ),
            ],
          ),
          content: Text(
            tr(
              '정말로 계정을 탈퇴하시겠습니까?\n이 작업은 되돌릴 수 없습니다.',
              'Are you sure you want to delete your account?\nThis action cannot be undone.',
            ),
            style: TextStyle(color: textSub, fontSize: 14, height: 1.35),
          ),
          actions: [
            TextButton(
              style: TextButton.styleFrom(
                foregroundColor: textSub,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
              ),
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(tr('취소', 'Cancel')),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: danger,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 9,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(tr('탈퇴', 'Delete')),
            ),
          ],
        );
      },
    );

    if (shouldDelete != true) return;

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(tr('로그인 정보를 찾을 수 없습니다.', 'No signed-in user found.')),
          ),
        );
        return;
      }

      await _deleteUserStorageData();
      await _deleteUserFirestoreData();
      await user.delete();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(tr('계정이 삭제되었습니다.', 'Your account has been deleted.')),
        ),
      );
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      final message = e.code == 'requires-recent-login'
          ? tr(
              '보안을 위해 다시 로그인 후 탈퇴해주세요.',
              'For security, please sign in again and try deleting your account.',
            )
          : tr(
              '계정 탈퇴 중 오류가 발생했습니다. 다시 시도해주세요.',
              'An error occurred while deleting your account. Please try again.',
            );
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } on FirebaseException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            tr(
              '계정 데이터 삭제 중 오류가 발생했습니다. 다시 시도해주세요.',
              'An error occurred while deleting account data. Please try again.',
            ),
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            tr(
              '계정 탈퇴 중 오류가 발생했습니다. 다시 시도해주세요.',
              'An error occurred while deleting your account. Please try again.',
            ),
          ),
        ),
      );
    }
  }

  Future<void> _deleteUserFirestoreData() async {
    final userCollection = FirebaseFirestore.instance.collection(
      widget.userEmail,
    );
    while (true) {
      final snapshot = await userCollection.limit(300).get();
      if (snapshot.docs.isEmpty) break;
      final batch = FirebaseFirestore.instance.batch();
      for (final doc in snapshot.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
    }

    // 문의 데이터도 사용자 이메일 기준으로 함께 정리.
    while (true) {
      final inquirySnapshot = await FirebaseFirestore.instance
          .collection('inquiry')
          .where('email', isEqualTo: widget.userEmail)
          .limit(300)
          .get();
      if (inquirySnapshot.docs.isEmpty) break;
      final batch = FirebaseFirestore.instance.batch();
      for (final doc in inquirySnapshot.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
    }
  }

  Future<void> _deleteUserStorageData() async {
    final safeEmail = widget.userEmail.replaceAll(RegExp(r'[^\w@.-]'), '_');
    final targets = <String>{
      widget.userEmail,
      'diaries/${widget.userEmail}',
      'diaries/$safeEmail',
    };
    for (final path in targets) {
      await _deleteStorageFolderRecursively(
        FirebaseStorage.instance.ref().child(path),
      );
    }
  }

  Future<void> _deleteStorageFolderRecursively(Reference folderRef) async {
    try {
      final result = await folderRef.listAll();
      for (final item in result.items) {
        try {
          await item.delete();
        } catch (_) {}
      }
      for (final prefix in result.prefixes) {
        await _deleteStorageFolderRecursively(prefix);
      }
    } on FirebaseException catch (e) {
      if (e.code == 'object-not-found') return;
      rethrow;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openMoodPickerAndWrite,
        backgroundColor: const Color(0xFF1E1E1E),
        foregroundColor: Colors.white,
        icon: const Icon(Icons.edit_rounded),
        label: Text(
          tr('일기 작성', 'Write Diary'),
          style: GoogleFonts.nanumPenScript(fontSize: 16),
        ),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _userCollection
            .orderBy('createdAt', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Text(
                tr('일기 데이터를 불러오지 못했습니다.', 'Failed to load diary data.'),
              ),
            );
          }

          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snapshot.data!.docs;
          final diaries = docs
              .where((doc) => doc.id != '_profile')
              .where((doc) => (doc.data()['title'] ?? '').toString().isNotEmpty)
              .toList();
          _syncWidgetEmojis(diaries);

          final diaryByDate = <DateTime, Map<String, dynamic>>{};
          for (final diaryDoc in diaries) {
            final data = diaryDoc.data();
            final writtenAt = data['writtenAt'];
            if (writtenAt is! Timestamp) {
              continue;
            }
            final normalizedDate = _normalizeDate(writtenAt.toDate());
            diaryByDate.putIfAbsent(normalizedDate, () => data);
          }
          final selectedDateDiaries = diaries.where((doc) {
            final writtenAt = doc.data()['writtenAt'];
            if (writtenAt is! Timestamp) {
              return false;
            }
            return isSameDay(_normalizeDate(writtenAt.toDate()), _selectedDay);
          }).toList();

          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
              child: Column(
                children: [
                  Row(
                    children: [
                      _buildViewModeButton(
                        icon: Icons.view_list_rounded,
                        isSelected: _isListMode,
                        onTap: () => setState(() {
                          _isListMode = true;
                          _listMonthAnchor = DateTime(
                            _focusedDay.year,
                            _focusedDay.month,
                            1,
                          );
                        }),
                      ),
                      const SizedBox(width: 6),
                      _buildViewModeButton(
                        icon: Icons.calendar_month_rounded,
                        isSelected: !_isListMode,
                        onTap: () => setState(() => _isListMode = false),
                      ),
                      const Spacer(),
                      IconButton(
                        tooltip: tr('설정', 'Settings'),
                        onPressed: _openSettings,
                        icon: const Icon(Icons.settings_rounded),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  if (_isListMode)
                    Expanded(child: _buildDiaryListView(diaries))
                  else ...[
                    Container(
                      padding: const EdgeInsets.fromLTRB(12, 54, 12, 38),
                      decoration: _calendarDecoration(),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final cellWidth = constraints.maxWidth / 7;
                          final rowHeight = cellWidth.clamp(34.0, 42.0);
                          final emojiSize = math.min(rowHeight * 0.78, 32.0);
                          final dayTextSize = (rowHeight * 0.30).clamp(
                            12.0,
                            15.0,
                          );

                          return TableCalendar<DateTime>(
                            firstDay: DateTime(2000, 1, 1),
                            lastDay: DateTime(2100, 12, 31),
                            focusedDay: _focusedDay,
                            rowHeight: rowHeight,
                            availableCalendarFormats: const {
                              CalendarFormat.month: 'Month',
                            },
                            startingDayOfWeek: StartingDayOfWeek.sunday,
                            headerStyle: HeaderStyle(
                              titleCentered: true,
                              formatButtonVisible: false,
                              leftChevronVisible: true,
                              rightChevronVisible: true,
                              titleTextStyle: GoogleFonts.nanumPenScript(
                                fontSize: 22,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            calendarStyle: const CalendarStyle(
                              outsideDaysVisible: false,
                              isTodayHighlighted: false,
                              defaultDecoration: BoxDecoration(),
                              weekendDecoration: BoxDecoration(),
                              selectedDecoration: BoxDecoration(),
                              todayDecoration: BoxDecoration(),
                            ),
                            selectedDayPredicate: (day) =>
                                isSameDay(day, _selectedDay),
                            onPageChanged: (focusedDay) {
                              setState(() {
                                _focusedDay = focusedDay;
                              });
                            },
                            onDaySelected: (selectedDay, focusedDay) {
                              setState(() {
                                _selectedDay = _normalizeDate(selectedDay);
                                _focusedDay = focusedDay;
                              });
                            },
                            calendarBuilders: CalendarBuilders(
                              headerTitleBuilder: (context, day) {
                                return Center(
                                  child: Text(
                                    isEnglish
                                        ? '${day.month}'
                                        : '${day.month}월',
                                    style: GoogleFonts.nanumPenScript(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 24,
                                    ),
                                  ),
                                );
                              },
                              dowBuilder: (context, day) {
                                final labels = isEnglish
                                    ? const [
                                        'Sun',
                                        'Mon',
                                        'Tue',
                                        'Wed',
                                        'Thu',
                                        'Fri',
                                        'Sat',
                                      ]
                                    : const ['일', '월', '화', '수', '목', '금', '토'];
                                final label = labels[day.weekday % 7];
                                return Center(
                                  child: Text(
                                    label,
                                    style: GoogleFonts.nanumPenScript(
                                      color: const Color(0xFF888888),
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                );
                              },
                              defaultBuilder: (context, day, focusedDay) {
                                return _buildCalendarCell(
                                  day: day,
                                  isSelected: false,
                                  diary: diaryByDate[_normalizeDate(day)],
                                  emojiSize: emojiSize,
                                  dayTextSize: dayTextSize,
                                );
                              },
                              selectedBuilder: (context, day, focusedDay) {
                                return _buildCalendarCell(
                                  day: day,
                                  isSelected: true,
                                  diary: diaryByDate[_normalizeDate(day)],
                                  emojiSize: emojiSize,
                                  dayTextSize: dayTextSize,
                                );
                              },
                              todayBuilder: (context, day, focusedDay) {
                                return _buildCalendarCell(
                                  day: day,
                                  isSelected: isSameDay(day, _selectedDay),
                                  diary: diaryByDate[_normalizeDate(day)],
                                  emojiSize: emojiSize,
                                  dayTextSize: dayTextSize,
                                );
                              },
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 14),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        isEnglish
                            ? '${_selectedDay.month}/${_selectedDay.day} Diary'
                            : '${_selectedDay.month}월 ${_selectedDay.day}일 일기',
                        style: GoogleFonts.gowunDodum(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: _buildSelectedDiaryDetail(selectedDateDiaries),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildCalendarCell({
    required DateTime day,
    required bool isSelected,
    required Map<String, dynamic>? diary,
    required double emojiSize,
    required double dayTextSize,
  }) {
    final mood = diary == null ? null : _resolveMoodFromDiary(diary);
    final hasDiary = diary != null;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
      decoration: BoxDecoration(
        color: isSelected ? const Color(0xFFE8E8E8) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (hasDiary && mood != null)
            _buildMoodAsset(mood, size: emojiSize)
          else
            Text(
              '${day.day}',
              style: GoogleFonts.nanumPenScript(
                fontSize: dayTextSize,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: const Color(0xFF8D8D8D),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMoodAsset(MoodOption mood, {required double size}) {
    if (mood.customIconBytes != null) {
      return ClipOval(
        child: Image.memory(
          mood.customIconBytes!,
          width: size,
          height: size,
          fit: BoxFit.cover,
        ),
      );
    }
    if (mood.customIconBase64 != null && mood.customIconBase64!.isNotEmpty) {
      try {
        final bytes = base64Decode(mood.customIconBase64!);
        return ClipOval(
          child: Image.memory(
            bytes,
            width: size,
            height: size,
            fit: BoxFit.cover,
          ),
        );
      } catch (_) {}
    }
    final cachedBytes = _globalAssetCache[mood.key];
    if (cachedBytes != null) {
      return Image.memory(
        cachedBytes,
        width: size,
        height: size,
        fit: BoxFit.contain,
      );
    }
    if (mood.assetPath.isNotEmpty) {
      return Image.asset(
        mood.assetPath,
        width: size,
        height: size,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) =>
            Text(mood.fallbackEmoji, style: TextStyle(fontSize: size * 0.8)),
      );
    }
    return Text(mood.fallbackEmoji, style: TextStyle(fontSize: size * 0.8));
  }

  MoodOption? _resolveMoodFromDiary(Map<String, dynamic> data) {
    final moodKey = (data['moodKey'] ?? '').toString();
    final mood = _moodByKey[moodKey];
    if (mood != null) {
      return mood;
    }
    final customBase64 = (data['moodCustomIcon'] ?? '').toString();
    if (customBase64.isEmpty) {
      return null;
    }
    return MoodOption.custom(
      key: moodKey.isEmpty ? 'custom_saved' : moodKey,
      label: '커스텀',
      customIconBase64: customBase64,
    );
  }

  List<Map<String, dynamic>> _contentBlocksFromData(Map<String, dynamic> data) {
    final raw = data['contentBlocks'];
    if (raw is! List) {
      return const [];
    }
    return raw
        .whereType<Map>()
        .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
        .cast<Map<String, dynamic>>()
        .toList();
  }

  String _previewTextFromBlocks(
    List<Map<String, dynamic>> blocks, {
    required String fallback,
  }) {
    for (final block in blocks) {
      if (block['type'] == 'text') {
        final text = (block['text'] ?? '').toString().trim();
        if (text.isNotEmpty) {
          return text;
        }
      }
    }
    return fallback;
  }

  String? _firstImageUrlFromBlocks(List<Map<String, dynamic>> blocks) {
    for (final block in blocks) {
      if (block['type'] == 'image') {
        final url = (block['url'] ?? '').toString();
        if (url.isNotEmpty) {
          return url;
        }
      }
    }
    return null;
  }

  Widget _buildReadOnlyBlocks(
    List<Map<String, dynamic>> blocks, {
    required double contentTextSize,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: blocks.map((block) {
        if (block['type'] == 'image') {
          final url = (block['url'] ?? '').toString();
          if (url.isEmpty) {
            return const SizedBox.shrink();
          }
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network(
                url,
                width: double.infinity,
                height: 190,
                fit: BoxFit.cover,
              ),
            ),
          );
        }

        final text = (block['text'] ?? '').toString();
        if (text.trim().isEmpty) {
          return const SizedBox.shrink();
        }
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(
            text,
            style: TextStyle(
              fontSize: contentTextSize,
              height: 1.55,
              color: const Color(0xFF1F2937),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildViewModeButton({
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF111827) : const Color(0xFFF2F2F2),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(
          icon,
          size: 18,
          color: isSelected ? Colors.white : const Color(0xFF707070),
        ),
      ),
    );
  }

  Widget _buildDiaryListView(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> diaries,
  ) {
    if (diaries.isEmpty) {
      return Center(child: Text(tr('작성된 일기가 없습니다.', 'No diaries yet.')));
    }

    final sorted = [...diaries];
    sorted.sort((a, b) {
      final aTs = a.data()['writtenAt'];
      final bTs = b.data()['writtenAt'];
      if (aTs is Timestamp && bTs is Timestamp) {
        return bTs.compareTo(aTs);
      }
      return 0;
    });

    final monthFiltered = sorted.where((doc) {
      final ts = doc.data()['writtenAt'];
      if (ts is! Timestamp) {
        return false;
      }
      final date = ts.toDate();
      return date.year == _listMonthAnchor.year &&
          date.month == _listMonthAnchor.month;
    }).toList();

    return Column(
      children: [
        _buildListMonthHeader(),
        const SizedBox(height: 10),
        Expanded(
          child: monthFiltered.isEmpty
              ? Center(
                  child: Text(
                    tr('해당 달에 작성된 일기가 없습니다.', 'No diaries in this month.'),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.only(bottom: 8),
                  itemCount: monthFiltered.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final data = monthFiltered[index].data();
                    final title = (data['title'] ?? '').toString();
                    final blocks = _contentBlocksFromData(data);
                    final content = _previewTextFromBlocks(
                      blocks,
                      fallback: (data['content'] ?? '').toString(),
                    );
                    final mood = _resolveMoodFromDiary(data);
                    final imageUrl =
                        _firstImageUrlFromBlocks(blocks) ??
                        (data['imageUrl'] ?? '').toString();
                    final ts = data['writtenAt'];
                    final dateText = ts is Timestamp
                        ? '${ts.toDate().year}.${ts.toDate().month.toString().padLeft(2, '0')}.${ts.toDate().day.toString().padLeft(2, '0')}'
                        : '';

                    final weekdays = isEnglish
                        ? const [
                            'Mon',
                            'Tue',
                            'Wed',
                            'Thu',
                            'Fri',
                            'Sat',
                            'Sun',
                          ]
                        : const ['월', '화', '수', '목', '금', '토', '일'];
                    final dateWithWeekday = ts is Timestamp
                        ? (isEnglish
                              ? '$dateText ${weekdays[ts.toDate().weekday - 1]}'
                              : '$dateText ${weekdays[ts.toDate().weekday - 1]}요일')
                        : dateText;

                    final docId = monthFiltered[index].id;
                    return Stack(
                      children: [
                        Container(
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.06),
                                blurRadius: 10,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              if (mood != null) ...[
                                _buildMoodAsset(mood, size: 64),
                                const SizedBox(height: 10),
                              ],
                              if (dateWithWeekday.isNotEmpty)
                                Text(
                                  dateWithWeekday,
                                  style: GoogleFonts.nanumPenScript(
                                    fontSize: 13,
                                    color: const Color(0xFF9CA3AF),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              const SizedBox(height: 6),
                              Text(
                                title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: GoogleFonts.nanumPenScript(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 17,
                                  color: const Color(0xFF111827),
                                ),
                              ),
                              if (content.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Text(
                                  content,
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.center,
                                  style: GoogleFonts.nanumPenScript(
                                    fontSize: 14,
                                    height: 1.5,
                                    color: const Color(0xFF4B5563),
                                  ),
                                ),
                              ],
                              if (imageUrl.isNotEmpty) ...[
                                const SizedBox(height: 12),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: Image.network(
                                    imageUrl,
                                    width: double.infinity,
                                    height: 190,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        Positioned(
                          top: 8,
                          right: 8,
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(16),
                              onTap: () => _showDiaryActionSheet(docId, data),
                              child: Container(
                                width: 30,
                                height: 30,
                                decoration: BoxDecoration(
                                  color: const Color(
                                    0xFF1E1E1E,
                                  ).withValues(alpha: 0.75),
                                  borderRadius: BorderRadius.circular(15),
                                ),
                                child: const Icon(
                                  Icons.edit_rounded,
                                  size: 15,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildListMonthHeader() {
    return GestureDetector(
      onHorizontalDragEnd: (details) {
        final velocity = details.primaryVelocity ?? 0;
        if (velocity > 120) {
          _moveListMonth(-1);
        } else if (velocity < -120) {
          _moveListMonth(1);
        }
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE6E6E6)),
        ),
        child: Row(
          children: [
            IconButton(
              onPressed: () => _moveListMonth(-1),
              icon: const Icon(Icons.chevron_left_rounded),
              visualDensity: VisualDensity.compact,
            ),
            Expanded(
              child: Center(
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: _openListMonthYearPicker,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    child: Text(
                      isEnglish
                          ? '${_listMonthAnchor.year}.${_listMonthAnchor.month.toString().padLeft(2, '0')}'
                          : '${_listMonthAnchor.year}년 ${_listMonthAnchor.month}월',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            IconButton(
              onPressed: () => _moveListMonth(1),
              icon: const Icon(Icons.chevron_right_rounded),
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
      ),
    );
  }

  void _moveListMonth(int delta) {
    setState(() {
      _listMonthAnchor = DateTime(
        _listMonthAnchor.year,
        _listMonthAnchor.month + delta,
        1,
      );
    });
  }

  Widget _buildSelectedDiaryDetail(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> selectedDateDiaries,
  ) {
    if (selectedDateDiaries.isEmpty) {
      return Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: const Color(0xFFF2F2F2),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.menu_book_rounded, color: Color(0xFFBDBDBD), size: 28),
            SizedBox(height: 8),
            Text(
              tr('선택한 날짜의 일기가 없습니다.', 'No diary on selected date.'),
              style: TextStyle(color: Color(0xFF8D8D8D)),
            ),
          ],
        ),
      );
    }

    final docSnapshot = selectedDateDiaries.first;
    final data = docSnapshot.data();
    final mood = _resolveMoodFromDiary(data);
    final title = (data['title'] ?? '').toString();
    final blocks = _contentBlocksFromData(data);
    final fallbackContent = (data['content'] ?? '').toString();
    final fallbackImageUrl = (data['imageUrl'] ?? '').toString();

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFFF2F2F2),
        borderRadius: BorderRadius.circular(18),
      ),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (mood != null) _buildMoodAsset(mood, size: 22),
              if (mood != null) const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF111827),
                  ),
                ),
              ),
              Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => _showDiaryActionSheet(docSnapshot.id, data),
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E1E1E).withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.edit_rounded,
                      size: 15,
                      color: Color(0xFF1E1E1E),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Divider(height: 1),
          const SizedBox(height: 10),
          Expanded(
            child: SingleChildScrollView(
              child: blocks.isNotEmpty
                  ? _buildReadOnlyBlocks(blocks, contentTextSize: 14)
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (fallbackImageUrl.isNotEmpty) ...[
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.network(
                              fallbackImageUrl,
                              width: double.infinity,
                              height: 190,
                              fit: BoxFit.cover,
                            ),
                          ),
                          const SizedBox(height: 10),
                        ],
                        Text(
                          fallbackContent,
                          style: const TextStyle(
                            fontSize: 14,
                            height: 1.55,
                            color: Color(0xFF1F2937),
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class NewDiaryPage extends StatefulWidget {
  const NewDiaryPage({
    super.key,
    required this.userEmail,
    required this.initialDate,
    required this.initialMoodKey,
    this.initialMoodCustomBase64,
    this.docId,
    this.initialTitle,
    this.initialContentBlocks,
  });

  final String userEmail;
  final DateTime initialDate;
  final String initialMoodKey;
  final String? initialMoodCustomBase64;
  final String? docId;
  final String? initialTitle;
  final List<Map<String, dynamic>>? initialContentBlocks;

  bool get isEditMode => docId != null;

  @override
  State<NewDiaryPage> createState() => _NewDiaryPageState();
}

class _NewDiaryPageState extends State<NewDiaryPage> {
  final _titleController = TextEditingController();
  final _imagePicker = ImagePicker();
  final List<MoodOption> _customMoodOptions = [];
  late DateTime _selectedDate;
  late String _selectedMoodKey;
  String? _selectedMoodCustomBase64;
  late List<_DraftContentBlock> _draftBlocks;
  int _focusedBlockIndex = 0;
  bool _isPickingImage = false;
  bool _isAiTransforming = false;
  bool _saving = false;
  List<Map<String, dynamic>>? _lastAiUndoTargets;

  bool get _canUndoAiTransform =>
      _lastAiUndoTargets != null && _lastAiUndoTargets!.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _selectedDate = _normalizeDate(widget.initialDate);
    _selectedMoodKey = widget.initialMoodKey;
    _selectedMoodCustomBase64 = widget.initialMoodCustomBase64;
    if (widget.isEditMode && widget.initialTitle != null) {
      _titleController.text = widget.initialTitle!;
    }
    if (widget.isEditMode &&
        widget.initialContentBlocks != null &&
        widget.initialContentBlocks!.isNotEmpty) {
      _draftBlocks = widget.initialContentBlocks!.map((b) {
        if (b['type'] == 'text') {
          return _createTextBlock((b['text'] ?? '').toString());
        }
        if (b['type'] == 'image') {
          final imageUrl = (b['url'] ?? '').toString();
          if (imageUrl.isNotEmpty) {
            return _DraftContentBlock.image(imageUrl: imageUrl);
          }
        }
        return _createTextBlock();
      }).toList();
      if (_draftBlocks.isEmpty) _draftBlocks = [_createTextBlock()];
    } else {
      _draftBlocks = [_createTextBlock()];
    }
    _loadCustomMoods();
    _ensureAssetsCached().then((_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _loadCustomMoods() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection(widget.userEmail)
          .doc('_custom_moods')
          .get();
      final moods = doc.exists
          ? ((doc.data()?['moods'] as List<dynamic>?) ?? <dynamic>[])
          : <dynamic>[];
      final seenKeys = <String>{};
      final seenUrls = <String>{};
      final uniqueMoodRows = <Map<String, dynamic>>[];

      for (final raw in moods) {
        if (raw is! Map) continue;
        final moodData = raw.map((k, v) => MapEntry(k.toString(), v));
        final key = (moodData['key'] ?? '').toString();
        final storageUrl = (moodData['storageUrl'] ?? '').toString();
        final storagePath = (moodData['storagePath'] ?? '').toString();
        if (key.isEmpty || (storageUrl.isEmpty && storagePath.isEmpty))
          continue;
        if (seenKeys.contains(key) || seenUrls.contains(storageUrl)) continue;
        seenKeys.add(key);
        if (storageUrl.isNotEmpty) seenUrls.add(storageUrl);
        uniqueMoodRows.add({
          'key': key,
          'storageUrl': storageUrl,
          'storagePath': storagePath,
        });
      }
      var usedStorageFallback = false;
      if (uniqueMoodRows.isEmpty) {
        uniqueMoodRows.addAll(await _listMoodRowsFromStorage(widget.userEmail));
        usedStorageFallback = uniqueMoodRows.isNotEmpty;
      }

      final loadedOptions = <MoodOption>[];
      final cleanedRows = <Map<String, dynamic>>[];
      final seenImageSignatures = <String>{};
      for (final moodData in uniqueMoodRows) {
        final key = (moodData['key'] ?? '').toString();
        final storageUrl = (moodData['storageUrl'] ?? '').toString();
        final storagePath = (moodData['storagePath'] ?? '').toString();
        try {
          final ref = storageUrl.isNotEmpty
              ? FirebaseStorage.instance.refFromURL(storageUrl)
              : FirebaseStorage.instance.ref().child(storagePath);
          final bytes = await ref.getData();
          if (bytes == null || !mounted) continue;
          final signature = base64Encode(bytes);
          if (seenImageSignatures.contains(signature)) continue;
          seenImageSignatures.add(signature);
          cleanedRows.add({
            'key': key,
            'storageUrl': storageUrl,
            'storagePath': ref.fullPath,
          });
          loadedOptions.add(
            MoodOption.custom(
              key: key,
              label: tr('커스텀', 'Custom'),
              customIconBytes: bytes,
            ),
          );
        } catch (_) {}
      }
      if (cleanedRows.isNotEmpty &&
          (usedStorageFallback || cleanedRows.length != moods.length || !doc.exists)) {
        await FirebaseFirestore.instance
            .collection(widget.userEmail)
            .doc('_custom_moods')
            .set({'moods': cleanedRows});
      }
      if (!mounted) return;
      setState(() {
        _customMoodOptions
          ..clear()
          ..addAll(loadedOptions);
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    _titleController.dispose();
    for (final block in _draftBlocks) {
      block.controller?.dispose();
      block.focusNode?.dispose();
    }
    super.dispose();
  }

  List<MoodOption> get _editorMoodOptions {
    final options = [...kMoodOptions, ..._customMoodOptions];
    final hasPreset = options.any((mood) => mood.key == _selectedMoodKey);
    if (!hasPreset && (_selectedMoodCustomBase64 ?? '').isNotEmpty) {
      options.insert(
        0,
        MoodOption.custom(
          key: _selectedMoodKey,
          label: tr('현재 감정', 'Current Mood'),
          customIconBase64: _selectedMoodCustomBase64,
        ),
      );
    }
    return options;
  }

  Future<void> _pickEditorMood() async {
    await _loadCustomMoods();
    if (!mounted) return;
    final picked = await showModalBottomSheet<MoodOption>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) => FractionallySizedBox(
        heightFactor: 0.42,
        child: Container(
          decoration: const BoxDecoration(
            color: Color(0xFFFCFCFD),
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
          child: SafeArea(
            top: false,
            child: Column(
              children: [
                Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFD4D7DD),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    tr('감정 선택', 'Select Mood'),
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: GridView.builder(
                    itemCount: _editorMoodOptions.length,
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          mainAxisSpacing: 14,
                          crossAxisSpacing: 8,
                          childAspectRatio: 1.05,
                        ),
                    itemBuilder: (_, index) {
                      final mood = _editorMoodOptions[index];
                      return InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () => Navigator.of(sheetContext).pop(mood),
                        child: Center(
                          child: _buildEditorMoodAsset(mood, size: 56),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (picked == null || !mounted) {
      return;
    }

    setState(() {
      _selectedMoodKey = picked.key;
      _selectedMoodCustomBase64 =
          picked.customIconBase64 ??
          (picked.customIconBytes != null
              ? base64Encode(picked.customIconBytes!)
              : null);
    });
  }

  Future<void> _pickImage() async {
    if (_isPickingImage || _saving) {
      return;
    }
    setState(() => _isPickingImage = true);
    try {
      final picked = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 88,
        maxWidth: 1800,
      );
      if (picked == null) {
        return;
      }
      final bytes = await picked.readAsBytes();
      if (!mounted) {
        return;
      }
      _insertImageBlock(bytes: bytes, imageName: picked.name);
    } catch (_) {
      _showSnackBar(tr('사진을 불러오지 못했습니다.', 'Failed to load image.'));
    } finally {
      if (mounted) {
        setState(() => _isPickingImage = false);
      }
    }
  }

  _DraftContentBlock _createTextBlock([String initialText = '']) {
    final controller = TextEditingController(text: initialText);
    final focusNode = FocusNode();
    focusNode.addListener(() {
      if (!focusNode.hasFocus || !mounted) {
        return;
      }
      final index = _draftBlocks.indexWhere((b) => b.focusNode == focusNode);
      if (index >= 0) {
        _focusedBlockIndex = index;
      }
    });
    return _DraftContentBlock.text(
      controller: controller,
      focusNode: focusNode,
    );
  }

  void _dismissKeyboard() {
    FocusManager.instance.primaryFocus?.unfocus();
  }

  int? _nextTextBlockIndex(int fromIndex) {
    for (var i = fromIndex + 1; i < _draftBlocks.length; i++) {
      if (_draftBlocks[i].isText) {
        return i;
      }
    }
    return null;
  }

  int? _previousTextBlockIndex(int fromIndex) {
    for (var i = fromIndex - 1; i >= 0; i--) {
      if (_draftBlocks[i].isText) {
        return i;
      }
    }
    return null;
  }

  void _focusTextBlockAt(int index, {bool atEnd = true}) {
    if (index < 0 || index >= _draftBlocks.length) {
      return;
    }
    final target = _draftBlocks[index];
    if (!target.isText) {
      return;
    }
    _focusedBlockIndex = index;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final block = _draftBlocks[index];
      final node = block.focusNode;
      final controller = block.controller;
      if (node == null || controller == null) {
        return;
      }
      node.requestFocus();
      final offset = atEnd ? controller.text.length : 0;
      controller.selection = TextSelection.collapsed(offset: offset);
    });
  }

  void _focusInputAroundImage(int imageIndex) {
    var targetIndex =
        _nextTextBlockIndex(imageIndex) ?? _previousTextBlockIndex(imageIndex);
    if (targetIndex == null) {
      setState(() {
        _draftBlocks.add(_createTextBlock());
        targetIndex = _draftBlocks.length - 1;
      });
    }
    _focusTextBlockAt(targetIndex!);
  }

  void _focusLastTextBlock() {
    for (var i = _draftBlocks.length - 1; i >= 0; i--) {
      if (_draftBlocks[i].isText) {
        _focusTextBlockAt(i);
        return;
      }
    }
    setState(() {
      _draftBlocks.add(_createTextBlock());
    });
    _focusTextBlockAt(_draftBlocks.length - 1);
  }

  void _insertImageBlock({
    required Uint8List bytes,
    required String imageName,
  }) {
    final currentIndex = _focusedBlockIndex
        .clamp(0, _draftBlocks.length - 1)
        .toInt();
    final currentBlock = _draftBlocks[currentIndex];
    if (!currentBlock.isText) {
      return;
    }

    final controller = currentBlock.controller!;
    final selection = controller.selection;
    final cursor = selection.isValid
        ? selection.baseOffset.clamp(0, controller.text.length)
        : controller.text.length;
    final before = controller.text.substring(0, cursor);
    final after = controller.text.substring(cursor);

    setState(() {
      controller.text = before;
      final imageBlock = _DraftContentBlock.image(
        imageBytes: bytes,
        imageName: imageName,
      );
      final trailingTextBlock = _createTextBlock(after);
      _draftBlocks.insert(currentIndex + 1, imageBlock);
      _draftBlocks.insert(currentIndex + 2, trailingTextBlock);
      _focusedBlockIndex = currentIndex + 2;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final block = _draftBlocks[_focusedBlockIndex];
      block.focusNode?.requestFocus();
      block.controller?.selection = TextSelection.collapsed(
        offset: block.controller?.text.length ?? 0,
      );
    });
  }

  bool _handleBackspaceOnTextBlock(int index) {
    if (index <= 0 || index >= _draftBlocks.length) {
      return false;
    }
    final current = _draftBlocks[index];
    if (!current.isText) {
      return false;
    }
    final controller = current.controller!;
    final selection = controller.selection;
    final isCursorAtStart = selection.isValid && selection.baseOffset == 0;
    if (!isCursorAtStart) {
      return false;
    }
    final previous = _draftBlocks[index - 1];

    // 1) 이전 블록이 텍스트면 현재 블록을 앞 블록에 병합
    if (previous.isText) {
      final previousController = previous.controller!;
      final previousLength = previousController.text.length;
      setState(() {
        previousController.text = previousController.text + controller.text;
        _draftBlocks.removeAt(index);
        _focusedBlockIndex = index - 1;
      });
      controller.dispose();
      current.focusNode?.dispose();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final block = _draftBlocks[_focusedBlockIndex];
        block.focusNode?.requestFocus();
        block.controller?.selection = TextSelection.collapsed(
          offset: previousLength,
        );
      });
      return true;
    }

    // 2) 이전 블록이 이미지면 이미지 삭제
    //    그리고 그 앞이 텍스트면 현재 텍스트까지 한 번에 병합
    if (index >= 2 && _draftBlocks[index - 2].isText) {
      final previousTextBlock = _draftBlocks[index - 2];
      final previousTextController = previousTextBlock.controller!;
      final previousLength = previousTextController.text.length;
      setState(() {
        previousTextController.text =
            previousTextController.text + controller.text;
        _draftBlocks.removeAt(index); // current text
        _draftBlocks.removeAt(index - 1); // image
        _focusedBlockIndex = index - 2;
      });
      controller.dispose();
      current.focusNode?.dispose();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final block = _draftBlocks[_focusedBlockIndex];
        block.focusNode?.requestFocus();
        block.controller?.selection = TextSelection.collapsed(
          offset: previousLength,
        );
      });
      return true;
    }

    setState(() {
      _draftBlocks.removeAt(index - 1);
      _focusedBlockIndex = (index - 1).clamp(0, _draftBlocks.length - 1);
    });
    return true;
  }

  void _removeImageBlockAt(int index) {
    if (index < 0 || index >= _draftBlocks.length) {
      return;
    }
    final target = _draftBlocks[index];
    if (target.isText) {
      return;
    }

    final hasPrevText = index > 0 && _draftBlocks[index - 1].isText;
    final hasNextText =
        index + 1 < _draftBlocks.length && _draftBlocks[index + 1].isText;

    if (hasPrevText && hasNextText) {
      final prev = _draftBlocks[index - 1];
      final next = _draftBlocks[index + 1];
      final prevController = prev.controller!;
      final nextController = next.controller!;
      final mergedText = prevController.text + nextController.text;

      setState(() {
        prevController.text = mergedText;
        _draftBlocks.removeAt(index + 1);
        _draftBlocks.removeAt(index);
        _focusedBlockIndex = index - 1;
      });

      nextController.dispose();
      next.focusNode?.dispose();

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final block = _draftBlocks[_focusedBlockIndex];
        block.focusNode?.requestFocus();
        block.controller?.selection = TextSelection.collapsed(
          offset: block.controller?.text.length ?? 0,
        );
      });
      return;
    }

    setState(() {
      _draftBlocks.removeAt(index);
      if (_draftBlocks.isEmpty) {
        _draftBlocks.add(_createTextBlock());
      }
      _focusedBlockIndex = _focusedBlockIndex.clamp(0, _draftBlocks.length - 1);
    });
  }

  Future<List<Map<String, dynamic>>> _buildSavedBlocks() async {
    final blocks = <Map<String, dynamic>>[];
    final safeEmail = widget.userEmail.replaceAll(RegExp(r'[^\w@.-]'), '_');

    for (final block in _draftBlocks) {
      if (block.isText) {
        final text = block.controller!.text;
        if (text.trim().isEmpty) {
          continue;
        }
        blocks.add({'type': 'text', 'text': text});
      } else {
        final imageBytes = block.imageBytes;
        if (imageBytes != null) {
          final jpgBytes = _toJpegBytes(imageBytes);
          final ref = FirebaseStorage.instance.ref(
            'diaries/$safeEmail/${DateTime.now().millisecondsSinceEpoch}_${blocks.length}.jpg',
          );
          await ref.putData(
            jpgBytes,
            SettableMetadata(contentType: 'image/jpeg'),
          );
          final url = await ref.getDownloadURL();
          blocks.add({'type': 'image', 'url': url});
          continue;
        }
        final imageUrl = (block.imageUrl ?? '').trim();
        if (imageUrl.isNotEmpty) {
          blocks.add({'type': 'image', 'url': imageUrl});
        }
      }
    }

    return blocks;
  }

  Set<String> _imageUrlsFromBlocks(List<Map<String, dynamic>>? blocks) {
    if (blocks == null) return <String>{};
    final urls = <String>{};
    for (final block in blocks) {
      if ((block['type'] ?? '').toString() != 'image') continue;
      final url = (block['url'] ?? '').toString().trim();
      if (url.isNotEmpty) {
        urls.add(url);
      }
    }
    return urls;
  }

  Future<void> _deleteStorageFiles(Iterable<String> urls) async {
    for (final url in urls) {
      try {
        await FirebaseStorage.instance.refFromURL(url).delete();
      } catch (_) {}
    }
  }

  Uint8List _toJpegBytes(Uint8List sourceBytes) {
    final decoded = img.decodeImage(sourceBytes);
    if (decoded == null) {
      return sourceBytes;
    }
    return Uint8List.fromList(img.encodeJpg(decoded, quality: 90));
  }

  Future<void> _confirmAndTransformByAi() async {
    if (_saving || _isAiTransforming) {
      return;
    }
    final shouldTransform = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        const lineColor = Color(0xFFE4E7EC);
        const panelBg = Color(0xFFFCFCFD);
        const textMain = Color(0xFF1F2937);
        const textSub = Color(0xFF8A94A6);
        const accent = Color(0xFF111827);

        return AlertDialog(
          backgroundColor: panelBg,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: const BorderSide(color: lineColor),
          ),
          titlePadding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
          contentPadding: const EdgeInsets.fromLTRB(20, 2, 20, 8),
          actionsPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          title: Row(
            children: [
              Icon(Icons.auto_awesome_rounded, size: 18, color: accent),
              SizedBox(width: 6),
              Text(
                isEnglish ? 'AI Rewrite' : 'AI 변환',
                style: TextStyle(
                  color: textMain,
                  fontWeight: FontWeight.w700,
                  fontSize: 17,
                ),
              ),
            ],
          ),
          content: Text(
            tr('AI로 글을 변환하겠습니까?', 'Do you want AI to rewrite your text?'),
            style: TextStyle(color: textSub, fontSize: 14, height: 1.35),
          ),
          actions: [
            TextButton(
              style: TextButton.styleFrom(
                foregroundColor: textSub,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
              ),
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(tr('아니오', 'No')),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: accent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 9,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(tr('예', 'Yes')),
            ),
          ],
        );
      },
    );
    if (shouldTransform != true) {
      return;
    }

    final textTargets = <Map<String, dynamic>>[];
    final undoTargets = <Map<String, dynamic>>[];
    for (var i = 0; i < _draftBlocks.length; i++) {
      final block = _draftBlocks[i];
      if (!block.isText) {
        continue;
      }
      final originalText = block.controller!.text;
      final text = originalText.trim();
      if (text.isEmpty) {
        continue;
      }
      textTargets.add({'index': i, 'text': text});
      undoTargets.add({'index': i, 'text': originalText});
    }

    if (textTargets.isEmpty) {
      _showSnackBar(tr('변환할 텍스트가 없습니다.', 'There is no text to transform.'));
      return;
    }

    setState(() => _isAiTransforming = true);
    final minDelay = Future.delayed(const Duration(seconds: 3));
    try {
      final baseUrl = (dotenv.env['BACKEND_BASE_URL'] ?? '').trim().isNotEmpty
          ? (dotenv.env['BACKEND_BASE_URL'] ?? '').trim()
          : const String.fromEnvironment('BACKEND_BASE_URL');
      if (baseUrl.isEmpty) {
        _showSnackBar(
          tr('BACKEND_BASE_URL 설정이 필요합니다.', 'BACKEND_BASE_URL is required.'),
        );
        return;
      }

      final uri = Uri.parse('$baseUrl/api/ai/rewrite');
      final client = HttpClient();
      final req = await client.postUrl(uri);
      req.headers.contentType = ContentType.json;
      req.write(
        jsonEncode({
          'language': isEnglish ? 'en' : 'ko',
          'targets': textTargets,
        }),
      );
      final response = await Future.wait([
        req.close(),
        minDelay,
      ]).then((results) => results[0] as HttpClientResponse);
      final raw = await response.transform(utf8.decoder).join();
      client.close();

      if (response.statusCode < 200 || response.statusCode >= 300) {
        _showAiError(
          tr(
            'AI 변환 서버 호출에 실패했습니다.\n다시 시도해주세요.',
            'Failed to call AI server.\nPlease try again.',
          ),
        );
        return;
      }

      final decoded = jsonDecode(raw);
      final items = decoded is Map<String, dynamic> ? decoded['items'] : null;
      if (items is! List) {
        _showAiError(
          tr(
            'AI 변환 결과 형식이 올바르지 않습니다.\n다시 시도해주세요.',
            'AI result format is invalid.\nPlease try again.',
          ),
        );
        return;
      }

      setState(() {
        _lastAiUndoTargets = undoTargets;
        for (final item in items) {
          if (item is! Map) continue;
          final index = item['index'];
          final text = item['text'];
          if (index is! int || text is! String) continue;
          if (index < 0 || index >= _draftBlocks.length) continue;
          final block = _draftBlocks[index];
          if (!block.isText) continue;
          block.controller!.text = text;
        }
      });
      _showSnackBar(
        tr(
          'AI 변환이 완료되었습니다. 버튼으로 되돌릴 수 있어요.',
          'AI rewrite completed. You can undo from the button.',
        ),
      );
    } catch (_) {
      await minDelay;
      _showAiError(
        tr(
          'AI 변환 중 오류가 발생했습니다.\n다시 시도해주세요.',
          'An error occurred during AI rewrite.\nPlease try again.',
        ),
      );
    } finally {
      if (mounted) setState(() => _isAiTransforming = false);
    }
  }

  void _undoLastAiTransform() {
    if (_saving || _isAiTransforming) {
      return;
    }
    final snapshots = _lastAiUndoTargets;
    if (snapshots == null || snapshots.isEmpty) {
      return;
    }
    setState(() {
      for (final item in snapshots) {
        final index = item['index'];
        final text = item['text'];
        if (index is! int || text is! String) continue;
        if (index < 0 || index >= _draftBlocks.length) continue;
        final block = _draftBlocks[index];
        if (!block.isText) continue;
        block.controller!.text = text;
      }
      _lastAiUndoTargets = null;
    });
    _showSnackBar(tr('AI 변환 전 상태로 되돌렸습니다.', 'Restored text before AI rewrite.'));
  }

  Future<void> _handleAiButtonPressed() async {
    if (_saving || _isAiTransforming) {
      return;
    }
    if (_canUndoAiTransform) {
      _undoLastAiTransform();
      return;
    }
    await _confirmAndTransformByAi();
  }

  String get _formattedDate {
    return '${_selectedDate.year.toString().padLeft(4, '0')}.${_selectedDate.month.toString().padLeft(2, '0')}.${_selectedDate.day.toString().padLeft(2, '0')}';
  }

  Future<void> _saveDiary() async {
    final title = _titleController.text.trim();
    final draftText = _draftBlocks
        .where((b) => b.isText)
        .map((b) => b.controller!.text.trim())
        .where((t) => t.isNotEmpty)
        .join('\n');
    final hasImage = _draftBlocks.any(
      (b) =>
          !b.isText && (b.imageBytes != null || (b.imageUrl ?? '').isNotEmpty),
    );

    if (title.isEmpty) {
      _showSnackBar(tr('제목을 채워주세요.', 'Please enter a title.'));
      return;
    }
    if (draftText.isEmpty && !hasImage) {
      _showSnackBar(tr('내용을 채워주세요.', 'Please add some content.'));
      return;
    }

    setState(() => _saving = true);
    try {
      final previousImageUrls = widget.isEditMode
          ? _imageUrlsFromBlocks(widget.initialContentBlocks)
          : <String>{};
      final contentBlocks = await _buildSavedBlocks();
      final currentImageUrls = _imageUrlsFromBlocks(contentBlocks);
      String? firstImageUrl;
      for (final block in contentBlocks) {
        if (block['type'] == 'image') {
          final url = (block['url'] ?? '').toString();
          if (url.isNotEmpty) {
            firstImageUrl = url;
            break;
          }
        }
      }
      final payload = {
        'title': title,
        'content': draftText,
        'contentBlocks': contentBlocks,
        'moodKey': _selectedMoodKey,
        'moodCustomIcon': _selectedMoodCustomBase64,
        'imageUrl': firstImageUrl,
        'writtenAt': Timestamp.fromDate(_selectedDate),
      };
      if (widget.isEditMode) {
        await FirebaseFirestore.instance
            .collection(widget.userEmail)
            .doc(widget.docId)
            .update(payload);
        final removedImageUrls = previousImageUrls.difference(currentImageUrls);
        await _deleteStorageFiles(removedImageUrls);
      } else {
        await FirebaseFirestore.instance.collection(widget.userEmail).add({
          ...payload,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (_) {
      _showSnackBar(tr('저장 중 오류가 발생했습니다.', 'An error occurred while saving.'));
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  void _showSnackBar(
    String message, {
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(
      SnackBar(
        content: Text(message),
        action: (actionLabel != null && onAction != null)
            ? SnackBarAction(label: actionLabel, onPressed: onAction)
            : null,
      ),
    );
  }

  void _showAiError(String message) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Row(
          children: [
            Icon(Icons.error_outline_rounded, color: Color(0xFFEF4444)),
            SizedBox(width: 8),
            Text(
              isEnglish ? 'Error' : '오류 발생',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ],
        ),
        content: Text(message),
        actions: [
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF1E1E1E),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () => Navigator.pop(context),
            child: Text(tr('확인', 'OK')),
          ),
        ],
      ),
    );
  }

  Widget _buildEditorMoodAsset(MoodOption mood, {required double size}) {
    if (mood.customIconBytes != null) {
      return ClipOval(
        child: Image.memory(
          mood.customIconBytes!,
          width: size,
          height: size,
          fit: BoxFit.cover,
        ),
      );
    }
    if (mood.customIconBase64 != null && mood.customIconBase64!.isNotEmpty) {
      try {
        final bytes = base64Decode(mood.customIconBase64!);
        return ClipOval(
          child: Image.memory(
            bytes,
            width: size,
            height: size,
            fit: BoxFit.cover,
          ),
        );
      } catch (_) {}
    }
    final cachedBytes = _globalAssetCache[mood.key];
    if (cachedBytes != null) {
      return Image.memory(
        cachedBytes,
        width: size,
        height: size,
        fit: BoxFit.contain,
      );
    }
    if (mood.assetPath.isNotEmpty) {
      return Image.asset(
        mood.assetPath,
        width: size,
        height: size,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) =>
            Text(mood.fallbackEmoji, style: TextStyle(fontSize: size * 0.8)),
      );
    }
    return Text(mood.fallbackEmoji, style: TextStyle(fontSize: size * 0.8));
  }

  @override
  Widget build(BuildContext context) {
    const pageBg = Color(0xFFF3F4F6);
    const panelBg = Color(0xFFFCFCFD);
    const lineColor = Color(0xFFE4E7EC);
    const textMain = Color(0xFF1F2937);
    const textSub = Color(0xFF8A94A6);
    const accent = Color(0xFF111827);
    MoodOption? selectedMood;
    for (final mood in kMoodOptions) {
      if (mood.key == _selectedMoodKey) {
        selectedMood = mood;
        break;
      }
    }
    if (selectedMood == null && (_selectedMoodCustomBase64 ?? '').isNotEmpty) {
      selectedMood = MoodOption.custom(
        key: _selectedMoodKey,
        label: tr('커스텀', 'Custom'),
        customIconBase64: _selectedMoodCustomBase64!,
      );
    }

    return Scaffold(
      backgroundColor: pageBg,
      appBar: AppBar(
        backgroundColor: pageBg,
        foregroundColor: textMain,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: null,
      ),
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: _dismissKeyboard,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
            child: Column(
              children: [
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: panelBg,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: lineColor),
                    ),
                    padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Align(
                          alignment: Alignment.center,
                          child: Text(
                            _formattedDate,
                            style: const TextStyle(
                              color: textSub,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        const Divider(height: 1, color: lineColor),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            if (selectedMood != null) ...[
                              InkWell(
                                borderRadius: BorderRadius.circular(20),
                                onTap: _saving ? null : _pickEditorMood,
                                child: _buildEditorMoodAsset(
                                  selectedMood,
                                  size: 26,
                                ),
                              ),
                              const SizedBox(width: 8),
                            ] else ...[
                              InkWell(
                                borderRadius: BorderRadius.circular(20),
                                onTap: _saving ? null : _pickEditorMood,
                                child: const Icon(
                                  Icons.emoji_emotions_outlined,
                                  size: 24,
                                  color: Color(0xFF6B7280),
                                ),
                              ),
                              const SizedBox(width: 8),
                            ],
                            Expanded(
                              child: TextField(
                                controller: _titleController,
                                style: TextStyle(
                                  color: textMain,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 15,
                                ),
                                decoration: InputDecoration(
                                  hintText: tr('제목', 'Title'),
                                  isDense: true,
                                  border: InputBorder.none,
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 8,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        const Divider(height: 1, color: lineColor),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            TextButton.icon(
                              onPressed: _saving ? null : _pickImage,
                              style: TextButton.styleFrom(
                                foregroundColor: accent,
                                backgroundColor: const Color(0xFFE5E7EB),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 8,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              icon: const Icon(Icons.image_outlined, size: 18),
                              label: Text(
                                _isPickingImage
                                    ? tr('불러오는 중...', 'Loading...')
                                    : tr('사진 추가', 'Add Photo'),
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        const Divider(height: 1, color: lineColor),
                        const SizedBox(height: 6),
                        Expanded(
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: _saving ? null : _focusLastTextBlock,
                            child: ListView.builder(
                              itemCount: _draftBlocks.length,
                              itemBuilder: (context, index) {
                                final block = _draftBlocks[index];
                                if (!block.isText) {
                                  final imageBytes = block.imageBytes;
                                  final imageUrl = (block.imageUrl ?? '')
                                      .trim();
                                  final hasImage =
                                      imageBytes != null || imageUrl.isNotEmpty;
                                  if (!hasImage) {
                                    return const SizedBox.shrink();
                                  }
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        GestureDetector(
                                          behavior: HitTestBehavior.opaque,
                                          onTap: _dismissKeyboard,
                                          child: ClipRRect(
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                            child: Stack(
                                              children: [
                                                if (imageBytes != null)
                                                  Image.memory(
                                                    imageBytes,
                                                    width: double.infinity,
                                                    height: 170,
                                                    fit: BoxFit.cover,
                                                  )
                                                else
                                                  Image.network(
                                                    imageUrl,
                                                    width: double.infinity,
                                                    height: 170,
                                                    fit: BoxFit.cover,
                                                  ),
                                                Positioned(
                                                  top: 8,
                                                  right: 8,
                                                  child: InkWell(
                                                    onTap: _saving
                                                        ? null
                                                        : () =>
                                                              _removeImageBlockAt(
                                                                index,
                                                              ),
                                                    child: Container(
                                                      padding:
                                                          const EdgeInsets.all(
                                                            4,
                                                          ),
                                                      decoration: BoxDecoration(
                                                        color: Colors.black
                                                            .withValues(
                                                              alpha: 0.55,
                                                            ),
                                                        shape: BoxShape.circle,
                                                      ),
                                                      child: const Icon(
                                                        Icons.close_rounded,
                                                        color: Colors.white,
                                                        size: 16,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                        GestureDetector(
                                          behavior: HitTestBehavior.opaque,
                                          onTap: _saving
                                              ? null
                                              : () => _focusInputAroundImage(
                                                  index,
                                                ),
                                          child: const SizedBox(
                                            height: 18,
                                            width: double.infinity,
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                }

                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 6),
                                  child: Focus(
                                    onKeyEvent: (node, event) {
                                      if (event.logicalKey ==
                                              LogicalKeyboardKey.backspace &&
                                          event is KeyDownEvent &&
                                          _handleBackspaceOnTextBlock(index)) {
                                        return KeyEventResult.handled;
                                      }
                                      return KeyEventResult.ignored;
                                    },
                                    child: TextField(
                                      controller: block.controller,
                                      focusNode: block.focusNode,
                                      maxLines: null,
                                      textAlignVertical: TextAlignVertical.top,
                                      decoration: InputDecoration(
                                        hintText: index == 0
                                            ? tr(
                                                '오늘은 어떤 하루였나요?',
                                                'How was your day today?',
                                              )
                                            : null,
                                        border: InputBorder.none,
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                              horizontal: 2,
                                              vertical: 8,
                                            ),
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: (_saving || _isAiTransforming)
                            ? null
                            : _handleAiButtonPressed,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: accent,
                          side: const BorderSide(color: Color(0xFFD1D5DB)),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        icon: _isAiTransforming
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Icon(
                                _canUndoAiTransform
                                    ? Icons.undo_rounded
                                    : Icons.auto_awesome_rounded,
                                size: 16,
                              ),
                        label: Text(
                          _canUndoAiTransform
                              ? tr('되돌리기', 'Undo')
                              : tr('AI변환', 'AI Rewrite'),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton(
                        onPressed: _saving ? null : _saveDiary,
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF1F2937),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (_saving) ...[
                              const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(width: 8),
                            ],
                            Text(
                              widget.isEditMode
                                  ? tr('수정 저장', 'Save Changes')
                                  : tr('일기 저장', 'Save Diary'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CustomMoodDrawDialog extends StatefulWidget {
  const _CustomMoodDrawDialog();

  @override
  State<_CustomMoodDrawDialog> createState() => _CustomMoodDrawDialogState();
}

class _CustomMoodDrawDialogState extends State<_CustomMoodDrawDialog> {
  static const double _canvasSize = 260;
  final List<_SketchStroke> _strokes = [];
  bool _eraserMode = false;
  double _penWidth = 5;
  double _eraserWidth = 20;
  Color _penColor = const Color(0xFF111827);
  _PenTexture _penTexture = _PenTexture.solid;
  Offset? _eraserGuidePoint;
  int? _activePointerId;

  void _startStroke(Offset point) {
    _strokes.add(
      _SketchStroke(
        isEraser: _eraserMode,
        width: _eraserMode ? _eraserWidth : _penWidth,
        color: _penColor,
        texture: _penTexture,
      ),
    );
    final clampedPoint = _clampPointToCanvas(point);
    _strokes.last.points.add(clampedPoint);
    if (_eraserMode) {
      _eraserGuidePoint = clampedPoint;
    }
    setState(() {});
  }

  void _addPoint(Offset point) {
    if (_strokes.isEmpty) return;
    final stroke = _strokes.last;
    final nextPoint = _clampPointToCanvas(point);
    final lastPoint = stroke.points.isEmpty ? null : stroke.points.last;
    if (lastPoint == null) {
      stroke.points.add(nextPoint);
    } else {
      final delta = nextPoint - lastPoint;
      final distance = delta.distance;
      if (distance <= 0.4) return;
      final step = math.max(1.2, stroke.width * 0.35);
      final segments = math.max(1, (distance / step).ceil());
      for (int i = 1; i <= segments; i++) {
        final t = i / segments;
        stroke.points.add(
          Offset(lastPoint.dx + delta.dx * t, lastPoint.dy + delta.dy * t),
        );
      }
    }
    if (_eraserMode) {
      _eraserGuidePoint = stroke.points.last;
    }
    setState(() {});
  }

  Offset _clampPointToCanvas(Offset point) {
    return Offset(
      point.dx.clamp(0.0, _canvasSize),
      point.dy.clamp(0.0, _canvasSize),
    );
  }

  void _endStroke() {
    if (_eraserGuidePoint != null) {
      setState(() {
        _eraserGuidePoint = null;
      });
      return;
    }
    setState(() {});
  }

  void _handlePointerDown(PointerDownEvent event) {
    if (_activePointerId != null) return;
    _activePointerId = event.pointer;
    _startStroke(event.localPosition);
  }

  void _handlePointerMove(PointerMoveEvent event) {
    if (_activePointerId != event.pointer) return;
    _addPoint(event.localPosition);
  }

  void _handlePointerEnd(int pointer) {
    if (_activePointerId != pointer) return;
    _activePointerId = null;
    _endStroke();
  }

  void _undoLastStroke() {
    if (_strokes.isEmpty) return;
    setState(() {
      _strokes.removeLast();
    });
  }

  Future<void> _pickPenColorFromBoard() async {
    final picked = await showDialog<Color>(
      context: context,
      builder: (dialogContext) {
        final colors = _buildColorBoardPalette();
        return Dialog(
          backgroundColor: const Color(0xFFF8F8F8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Text(
                      tr('펜 색상 선택', 'Pick Pen Color'),
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    const Spacer(),
                    Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        color: _penColor,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: const Color(0xFF111827),
                          width: 1.3,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                LayoutBuilder(
                  builder: (_, constraints) {
                    final boardWidth = math.min(300.0, constraints.maxWidth);
                    return SizedBox(
                      width: boardWidth,
                      child: GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: colors.length,
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 12,
                              crossAxisSpacing: 0,
                              mainAxisSpacing: 0,
                            ),
                        itemBuilder: (context, index) {
                          final color = colors[index];
                          return InkWell(
                            onTap: () => Navigator.of(dialogContext).pop(color),
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: color,
                                border: Border.all(
                                  color: _penColor.value == color.value
                                      ? const Color(0xFF111827)
                                      : Colors.transparent,
                                  width: 1.4,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    );
                  },
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    child: Text(tr('취소', 'Cancel')),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (!mounted || picked == null) return;
    setState(() {
      _eraserMode = false;
      _penColor = picked;
    });
  }

  Future<void> _save() async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    const outSize = 512.0;
    final scale = outSize / _canvasSize;
    final center = const Offset(outSize / 2, outSize / 2);
    const radius = outSize / 2;

    // Clip to circle and fill white inside
    canvas.save();
    canvas.clipPath(
      Path()..addOval(Rect.fromCircle(center: center, radius: radius)),
    );
    canvas.drawCircle(center, radius, Paint()..color = Colors.white);
    _SketchPainter.drawStrokes(canvas, _strokes, scale: scale);
    canvas.restore();

    final image = await recorder.endRecording().toImage(
      outSize.toInt(),
      outSize.toInt(),
    );
    // PNG 형식으로 저장하여 원 바깥이 투명하게 유지
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null || !mounted) {
      return;
    }
    Navigator.of(context).pop(byteData.buffer.asUint8List());
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
      backgroundColor: const Color(0xFFF8F8F8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: media.size.height * 0.9),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final canvasLength = math.min(
              _canvasSize,
              math.max(160.0, constraints.maxWidth - 64),
            );

            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Text(
                        isEnglish ? 'Draw Icon' : '아이콘 그리기',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: () => setState(() => _strokes.clear()),
                        style: TextButton.styleFrom(
                          foregroundColor: const Color(0xFF9CA3AF),
                        ),
                        child: Text(tr('초기화', 'Reset')),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    tr(
                      '원 안에 나만의 기분 아이콘을 그려보세요',
                      'Draw your own mood icon inside the circle',
                    ),
                    style: TextStyle(fontSize: 12, color: Color(0xFF9CA3AF)),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.06),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: SizedBox(
                      width: canvasLength,
                      height: canvasLength,
                      child: Stack(
                        children: [
                          Container(
                            width: canvasLength,
                            height: canvasLength,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white,
                            ),
                            child: ClipOval(
                              child: Listener(
                                behavior: HitTestBehavior.opaque,
                                onPointerDown: _handlePointerDown,
                                onPointerMove: _handlePointerMove,
                                onPointerUp: (event) =>
                                    _handlePointerEnd(event.pointer),
                                onPointerCancel: (event) =>
                                    _handlePointerEnd(event.pointer),
                                child: CustomPaint(
                                  painter: _SketchPainter(
                                    strokes: _strokes,
                                    eraserGuideCenter: _eraserGuidePoint,
                                    eraserGuideRadius: _eraserWidth / 2,
                                  ),
                                  child: const SizedBox.expand(),
                                ),
                              ),
                            ),
                          ),
                          IgnorePointer(
                            child: CustomPaint(
                              size: Size(canvasLength, canvasLength),
                              painter: _DashedCircleBorderPainter(),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _ToolButton(
                        label: tr('펜', 'Pen'),
                        icon: Icons.edit_rounded,
                        selected: !_eraserMode,
                        onTap: () => setState(() => _eraserMode = false),
                      ),
                      _ToolButton(
                        label: tr('지우개', 'Eraser'),
                        icon: Icons.auto_fix_normal_rounded,
                        selected: _eraserMode,
                        onTap: () => setState(() {
                          _eraserMode = true;
                        }),
                      ),
                      _ToolButton(
                        label: tr('되돌리기', 'Undo'),
                        icon: Icons.undo_rounded,
                        selected: false,
                        onTap: _undoLastStroke,
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Row(
                      children: [
                        Text(
                          tr('펜 색상', 'Pen Color'),
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF6B7280),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const Spacer(),
                        TextButton.icon(
                          onPressed: _pickPenColorFromBoard,
                          icon: const Icon(Icons.grid_on_rounded, size: 16),
                          label: Text(tr('색상표', 'Color Board')),
                          style: TextButton.styleFrom(
                            foregroundColor: const Color(0xFF4B5563),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                        const SizedBox(width: 8),
                        InkWell(
                          onTap: _pickPenColorFromBoard,
                          borderRadius: BorderRadius.circular(99),
                          child: Container(
                            width: 20,
                            height: 20,
                            decoration: BoxDecoration(
                              color: _penColor,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: const Color(0xFF111827),
                                width: 1.2,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      tr('펜 텍스처', 'Pen Texture'),
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF6B7280),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final texture in _PenTexture.values)
                        ChoiceChip(
                          selected: _penTexture == texture,
                          label: Text(_textureLabel(texture)),
                          onSelected: (_) => setState(() {
                            _eraserMode = false;
                            _penTexture = texture;
                          }),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            _eraserMode
                                ? Icons.auto_fix_normal_rounded
                                : Icons.edit_rounded,
                            size: 16,
                            color: const Color(0xFF6B7280),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _eraserMode
                                ? tr('지우개 두께', 'Eraser Width')
                                : tr('펜 두께', 'Pen Width'),
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF6B7280),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      Slider(
                        value: _eraserMode ? _eraserWidth : _penWidth,
                        min: 2,
                        max: 28,
                        divisions: 26,
                        onChanged: (v) {
                          setState(() {
                            if (_eraserMode) {
                              _eraserWidth = v;
                            } else {
                              _penWidth = v;
                            }
                          });
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(context).pop(),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF6B7280),
                            side: const BorderSide(color: Color(0xFFD1D5DB)),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: Text(tr('취소', 'Cancel')),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton(
                          onPressed: _save,
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF1E1E1E),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: Text(tr('저장', 'Save')),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? const Color(0xFF1F2937);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: c.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: c),
            const SizedBox(width: 12),
            Text(
              label,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: c,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF1E1E1E) : const Color(0xFFEEEEEE),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: selected ? Colors.white : const Color(0xFF6B7280),
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: selected ? Colors.white : const Color(0xFF6B7280),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SketchStroke {
  _SketchStroke({
    required this.isEraser,
    required this.width,
    required this.color,
    required this.texture,
  });
  final bool isEraser;
  final double width;
  final Color color;
  final _PenTexture texture;
  final List<Offset> points = [];
}

class _SketchPainter extends CustomPainter {
  const _SketchPainter({
    required this.strokes,
    this.eraserGuideCenter,
    this.eraserGuideRadius = 10,
  });
  final List<_SketchStroke> strokes;
  final Offset? eraserGuideCenter;
  final double eraserGuideRadius;

  static void drawStrokes(
    Canvas canvas,
    List<_SketchStroke> strokes, {
    double scale = 1,
  }) {
    for (final stroke in strokes) {
      if (stroke.points.isEmpty) {
        continue;
      }

      final width = stroke.width * scale;
      final scaledPoints = [
        for (final point in stroke.points)
          Offset(point.dx * scale, point.dy * scale),
      ];

      if (stroke.isEraser) {
        final paint = Paint()
          ..color = Colors.white
          ..strokeWidth = width
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..style = PaintingStyle.stroke;
        _drawLinePath(canvas, scaledPoints, paint);
        continue;
      }

      switch (stroke.texture) {
        case _PenTexture.solid:
          final paint = Paint()
            ..color = stroke.color
            ..strokeWidth = width
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round
            ..style = PaintingStyle.stroke;
          _drawLinePath(canvas, scaledPoints, paint);
          break;
        case _PenTexture.soft:
          final basePaint = Paint()
            ..color = stroke.color.withValues(alpha: 0.34)
            ..strokeWidth = width + 2
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round
            ..style = PaintingStyle.stroke;
          final topPaint = Paint()
            ..color = stroke.color.withValues(alpha: 0.85)
            ..strokeWidth = width
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round
            ..style = PaintingStyle.stroke;
          _drawLinePath(canvas, scaledPoints, basePaint);
          _drawLinePath(canvas, scaledPoints, topPaint);
          break;
      }
    }
  }

  static void _drawLinePath(Canvas canvas, List<Offset> points, Paint paint) {
    if (points.isEmpty) return;
    if (points.length == 1) {
      canvas.drawCircle(
        points.first,
        paint.strokeWidth / 2,
        paint..style = PaintingStyle.fill,
      );
      return;
    }
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }
    canvas.drawPath(path, paint);
  }

  @override
  void paint(Canvas canvas, Size size) {
    drawStrokes(canvas, strokes);
    if (eraserGuideCenter != null) {
      final center = eraserGuideCenter!;
      canvas.drawCircle(
        center,
        eraserGuideRadius,
        Paint()
          ..color = const Color(0xFFEF4444).withValues(alpha: 0.14)
          ..style = PaintingStyle.fill,
      );
      canvas.drawCircle(
        center,
        eraserGuideRadius,
        Paint()
          ..color = const Color(0xFFEF4444).withValues(alpha: 0.85)
          ..strokeWidth = 1.4
          ..style = PaintingStyle.stroke,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SketchPainter oldDelegate) {
    return true;
  }
}

enum _PenTexture { solid, soft }

String _textureLabel(_PenTexture texture) {
  switch (texture) {
    case _PenTexture.solid:
      return tr('기본', 'Solid');
    case _PenTexture.soft:
      return tr('부드럽게', 'Soft');
  }
}

List<Color> _buildColorBoardPalette() {
  const rows = 12;
  const cols = 12;
  final result = <Color>[];
  for (int row = 0; row < rows; row++) {
    final vertical = row / (rows - 1);
    for (int col = 0; col < cols; col++) {
      if (col == 0) {
        final value = (1 - vertical).clamp(0.0, 1.0);
        result.add(HSVColor.fromAHSV(1, 0, 0, value).toColor());
        continue;
      }
      final hue = ((col - 1) / (cols - 2)) * 330;
      // 선명한 색상을 위해 채도를 높게 유지하고 아래로 갈수록 명도만 강하게 낮춘다.
      const saturation = 0.96;
      final value = (1.0 - vertical * 0.98).clamp(0.0, 1.0);
      result.add(
        HSVColor.fromAHSV(1, hue, saturation, value.toDouble()).toColor(),
      );
    }
  }
  return result;
}

Future<List<Map<String, dynamic>>> _listMoodRowsFromStorage(String userEmail) async {
  try {
    final folderRef = FirebaseStorage.instance
        .ref()
        .child(userEmail)
        .child('mood_icons');
    final result = await folderRef.listAll();
    final rows = <Map<String, dynamic>>[];
    for (final item in result.items) {
      try {
        final url = await item.getDownloadURL();
        final fileName = item.name;
        final dotIndex = fileName.lastIndexOf('.');
        final key = (dotIndex > 0 ? fileName.substring(0, dotIndex) : fileName).trim();
        if (key.isEmpty) continue;
        rows.add({
          'key': key,
          'storageUrl': url,
          'storagePath': item.fullPath,
        });
      } catch (_) {}
    }
    return rows;
  } catch (_) {
    return <Map<String, dynamic>>[];
  }
}

class _DashedCircleBorderPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 1.5;
    final paint = Paint()
      ..color = const Color(0xFFAAAAAA)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    const dashCount = 36;
    const totalAngle = 2 * math.pi;
    const dashFraction = 0.55;

    for (int i = 0; i < dashCount; i++) {
      final startAngle = (i / dashCount) * totalAngle;
      final sweepAngle = (1 / dashCount) * totalAngle * dashFraction;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweepAngle,
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_DashedCircleBorderPainter oldDelegate) => false;
}

class _DraftContentBlock {
  _DraftContentBlock.text({required this.controller, required this.focusNode})
    : isText = true,
      imageBytes = null,
      imageName = null,
      imageUrl = null;

  _DraftContentBlock.image({this.imageBytes, this.imageName, this.imageUrl})
    : isText = false,
      controller = null,
      focusNode = null;

  final bool isText;
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final Uint8List? imageBytes;
  final String? imageName;
  final String? imageUrl;
}

DateTime _normalizeDate(DateTime date) {
  return DateTime(date.year, date.month, date.day);
}

BoxDecoration _calendarDecoration() {
  return BoxDecoration(
    borderRadius: BorderRadius.circular(24),
    image: const DecorationImage(
      image: AssetImage('assets/calander.png'),
      fit: BoxFit.fill,
    ),
  );
}

class MoodOption {
  const MoodOption({
    required this.key,
    required this.label,
    required this.backgroundColor,
    this.assetPath = '',
    this.fallbackEmoji = '🙂',
    this.customIconBase64,
    this.customIconBytes,
  });

  factory MoodOption.custom({
    required String key,
    required String label,
    String? customIconBase64,
    Uint8List? customIconBytes,
  }) {
    return MoodOption(
      key: key,
      label: label,
      backgroundColor: const Color(0xFFF1F3F5),
      customIconBase64: customIconBase64,
      customIconBytes: customIconBytes,
      fallbackEmoji: '🙂',
    );
  }

  final String key;
  final String label;
  final Color backgroundColor;
  final String assetPath;
  final String fallbackEmoji;
  final String? customIconBase64;
  final Uint8List? customIconBytes;
}

final Map<String, Uint8List> _globalAssetCache = {};

Future<void> _ensureAssetsCached() async {
  for (final mood in kMoodOptions) {
    if (mood.assetPath.isNotEmpty && !_globalAssetCache.containsKey(mood.key)) {
      try {
        final data = await rootBundle.load(mood.assetPath);
        _globalAssetCache[mood.key] = data.buffer.asUint8List();
      } catch (_) {}
    }
  }
}

const kMoodOptions = [
  MoodOption(
    key: 'very_good',
    label: '최고',
    backgroundColor: Color(0xFFDDF4EA),
    assetPath: 'assets/Moods/good.png',
    fallbackEmoji: '😄',
  ),
  MoodOption(
    key: 'good',
    label: '좋음',
    backgroundColor: Color(0xFFFBEA83),
    assetPath: 'assets/Moods/marong.png',
    fallbackEmoji: '🙂',
  ),
  MoodOption(
    key: 'normal',
    label: '보통',
    backgroundColor: Color(0xFFFFD6E3),
    assetPath: 'assets/Moods/what.png',
    fallbackEmoji: '😐',
  ),
  MoodOption(
    key: 'bad',
    label: '별로',
    backgroundColor: Color(0xFFDDE3FF),
    assetPath: 'assets/Moods/nervous.png',
    fallbackEmoji: '☹️',
  ),
  MoodOption(
    key: 'very_bad',
    label: '최악',
    backgroundColor: Color(0xFFE5ECFF),
    assetPath: 'assets/Moods/cry.png',
    fallbackEmoji: '😭',
  ),
  MoodOption(
    key: 'good_face',
    label: '굿',
    backgroundColor: Color(0xFFF4F5F7),
    assetPath: 'assets/Moods/good.png',
    fallbackEmoji: '🙂',
  ),
  MoodOption(
    key: 'cry_face',
    label: '울음',
    backgroundColor: Color(0xFFF4F5F7),
    assetPath: 'assets/Moods/cry.png',
    fallbackEmoji: '😭',
  ),
  MoodOption(
    key: 'marong_face',
    label: '마롱',
    backgroundColor: Color(0xFFF4F5F7),
    assetPath: 'assets/Moods/marong.png',
    fallbackEmoji: '🙂',
  ),
  MoodOption(
    key: 'love_face',
    label: '사랑',
    backgroundColor: Color(0xFFF4F5F7),
    assetPath: 'assets/Moods/love.png',
    fallbackEmoji: '🥰',
  ),
  MoodOption(
    key: 'what_face',
    label: '어리둥절',
    backgroundColor: Color(0xFFF4F5F7),
    assetPath: 'assets/Moods/what.png',
    fallbackEmoji: '😶',
  ),
  MoodOption(
    key: 'sleep_face',
    label: '졸림',
    backgroundColor: Color(0xFFF4F5F7),
    assetPath: 'assets/Moods/sleep.png',
    fallbackEmoji: '😪',
  ),
  MoodOption(
    key: 'nervous_face',
    label: '긴장',
    backgroundColor: Color(0xFFF4F5F7),
    assetPath: 'assets/Moods/nervous.png',
    fallbackEmoji: '😰',
  ),
];

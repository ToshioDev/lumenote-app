import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'ai_gateway.dart';
import 'auth_service.dart';
import 'backend_contract.dart';
import 'media_bytes.dart';
import 'web_path.dart';

Future<void> showCodexDeviceCodeDialog(BuildContext context) async {
  final code = AiGateway.lastCodexUserCode;
  if (code == null || code.isEmpty) return;
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Conecta tu cuenta de Codex'),
      content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
                'Se abrió Codex en otra pestaña. Introduce este código para autorizar tu propia cuenta:'),
            const SizedBox(height: 18),
            SelectableText(code,
                style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 2)),
            const SizedBox(height: 10),
            const Text(
                'El código es temporal y no se comparte con otros usuarios.',
                style: TextStyle(color: muted, fontSize: 12)),
          ]),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cerrar')),
        FilledButton.icon(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: code));
            if (dialogContext.mounted) Navigator.pop(dialogContext);
            if (context.mounted)
              ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Código copiado.')));
          },
          icon: const Icon(Icons.copy),
          label: const Text('Copiar código'),
        ),
      ],
    ),
  );
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await loadAppearancePreferences();
  } catch (_) {}
  selectedPalette.addListener(scheduleAppearancePersistence);
  appAccent.addListener(scheduleAppearancePersistence);
  appThemeMode.addListener(scheduleAppearancePersistence);
  appFontFamily.addListener(scheduleAppearancePersistence);
  customAccentEnabled.addListener(scheduleAppearancePersistence);
  var supabaseReady = false;
  if (LumenoteBackendConfig.supabaseUrl.isNotEmpty &&
      LumenoteBackendConfig.supabaseAnonKey.isNotEmpty) {
    try {
      await Supabase.initialize(
              url: LumenoteBackendConfig.supabaseUrl,
              anonKey: LumenoteBackendConfig.supabaseAnonKey)
          .timeout(const Duration(seconds: 8));
      supabaseReady = true;
    } catch (_) {
      supabaseReady = false;
    }
  }
  runApp(LumenoteApp(supabaseReady: supabaseReady));
}

const brand = Color(0xff8f7bd8);
const pale = Color(0xfff3f0ff);
const ink = Color(0xff111014);
const line = Color(0xffe8e4ef);
const muted = Color(0xff6f687c);

class LumenotePalette {
  const LumenotePalette(this.name, this.accent, this.gradient);
  final String name;
  final Color accent;
  final List<Color> gradient;
}

const paletteOptions = <LumenotePalette>[
  LumenotePalette(
      'Lavanda', Color(0xffb4a6ed), [Color(0xff8f7bd8), Color(0xffc9bdf5)]),
  LumenotePalette(
      'Malva', Color(0xffc49acb), [Color(0xff9a6d9e), Color(0xffddb9df)]),
  LumenotePalette(
      'Lila', Color(0xff9e8fe0), [Color(0xff6554c8), Color(0xffb9aaf0)]),
  LumenotePalette(
      'Pizarra', Color(0xff8d98c9), [Color(0xff4d5a91), Color(0xffa9b5e5)]),
];
final selectedPalette = ValueNotifier<int>(0);
final appAccent = ValueNotifier<Color>(paletteOptions.first.accent);
final appThemeMode = ValueNotifier<ThemeMode>(ThemeMode.system);
final appFontFamily = ValueNotifier<String>('Quicksand');
final customAccentEnabled = ValueNotifier<bool>(false);
final founderSkinEnabled = ValueNotifier<bool>(false);
final remoteBranding = ValueNotifier<Map<String, dynamic>?>(null);
bool founderSplashPlayed = false;
bool? founderRoleCached;
const _appearancePaletteKey = 'appearance.palette';
const _appearanceAccentKey = 'appearance.accent';
const _appearanceCustomKey = 'appearance.customAccent';
const _appearanceThemeKey = 'appearance.themeMode';
const _appearanceFontKey = 'appearance.fontFamily';
Timer? _appearanceSaveTimer;

void scheduleAppearancePersistence() {
  _appearanceSaveTimer?.cancel();
  _appearanceSaveTimer = Timer(const Duration(milliseconds: 280),
      () => unawaited(persistAppearancePreferences()));
}

Future<void> loadAppearancePreferences() async {
  final prefs = await SharedPreferences.getInstance();
  final palette = prefs.getInt(_appearancePaletteKey) ?? 0;
  final colorValue = prefs.getInt(_appearanceAccentKey);
  selectedPalette.value = palette.clamp(0, paletteOptions.length - 1);
  customAccentEnabled.value = prefs.getBool(_appearanceCustomKey) ?? false;
  appAccent.value = colorValue == null
      ? paletteOptions[selectedPalette.value].accent
      : Color(colorValue);
  appFontFamily.value = prefs.getString(_appearanceFontKey) ?? 'Quicksand';
  appThemeMode.value = switch (prefs.getString(_appearanceThemeKey)) {
    'light' => ThemeMode.light,
    'dark' => ThemeMode.dark,
    _ => ThemeMode.system,
  };
}

Future<void> persistAppearancePreferences() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setInt(_appearancePaletteKey, selectedPalette.value);
  await prefs.setInt(_appearanceAccentKey, appAccent.value.toARGB32());
  await prefs.setBool(_appearanceCustomKey, customAccentEnabled.value);
  await prefs.setString(
      _appearanceThemeKey,
      switch (appThemeMode.value) {
        ThemeMode.light => 'light',
        ThemeMode.dark => 'dark',
        ThemeMode.system => 'system',
      });
  await prefs.setString(_appearanceFontKey, appFontFamily.value);
}

void setCustomAccent(Color color) {
  customAccentEnabled.value = true;
  appAccent.value = color;
  scheduleAppearancePersistence();
}

const kuromiBrandingFallback = <String, dynamic>{
  'app_name': 'KuromiNotes',
  'accent_hex': '#F04D9E',
  'logo_url': null,
  'splash_url': null,
  'hero_url': null,
};
Color _brandingAccent(Map<String, dynamic>? branding,
    {Color fallback = const Color(0xfff04d9e)}) {
  final raw = branding?['accent_hex'];
  if (raw is! String) return fallback;
  final hex = raw.replaceFirst('#', '');
  if (!RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(hex)) return fallback;
  return Color(int.parse('ff$hex', radix: 16));
}

Future<void> signOutAndResetBranding() async {
  await AuthService.signOut();
  founderSkinEnabled.value = false;
  founderRoleCached = null;
  remoteBranding.value = null;
  appAccent.value = customAccentEnabled.value
      ? appAccent.value
      : paletteOptions[selectedPalette.value].accent;
  founderSplashPlayed = false;
}

int pageForWebPath(String? path) {
  const paths = [
    '/home',
    '/library',
    '/capture',
    '/study',
    '/quizzes',
    '/settings',
    '/account',
    '/privacy',
    '/founder'
  ];
  const legacyPaths = [
    '/inicio',
    '/biblioteca',
    '/capturar',
    '/estudiar',
    '/quizzes',
    '/ajustes',
    '/cuenta',
    '/privacidad',
    '/fundador'
  ];
  final index = paths.indexOf(path ?? '');
  final legacyIndex = legacyPaths.indexOf(path ?? '');
  return index >= 0 ? index : (legacyIndex < 0 ? 0 : legacyIndex);
}

void applyPalette(int index) {
  selectedPalette.value = index;
  customAccentEnabled.value = false;
  appAccent.value = paletteOptions[index].accent;
  scheduleAppearancePersistence();
}

bool isDarkTheme(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark;
Color appSurface(BuildContext context) =>
    isDarkTheme(context) ? const Color(0xff1d1a25) : Colors.white;
Color appSoftSurface(BuildContext context) =>
    isDarkTheme(context) ? const Color(0xff292238) : pale;
Color appText(BuildContext context) => Theme.of(context).colorScheme.onSurface;
Color appMutedText(BuildContext context) =>
    isDarkTheme(context) ? const Color(0xffb9b1c5) : muted;
Color appAccentSurface(BuildContext context) => founderSkinEnabled.value
    ? (isDarkTheme(context) ? const Color(0xff392b48) : const Color(0xfff3e5fa))
    : (isDarkTheme(context) ? const Color(0xff302744) : pale);
Color appErrorSurface(BuildContext context) =>
    isDarkTheme(context) ? const Color(0xff3a2023) : const Color(0xfffff2f1);
Color appErrorText(BuildContext context) =>
    isDarkTheme(context) ? const Color(0xffffb4ab) : const Color(0xff8b1a14);
List<Color> appGradient(BuildContext context, int index) {
  if (customAccentEnabled.value) {
    final base = _whiteContrastSurface(appAccent.value);
    return [base, Color.lerp(base, ink, .18)!];
  }
  return paletteOptions[index]
      .gradient
      .map(_whiteContrastSurface)
      .toList(growable: false);
}

double _contrastRatio(Color first, Color second) {
  final a = first.computeLuminance();
  final b = second.computeLuminance();
  final light = a > b ? a : b;
  final dark = a > b ? b : a;
  return (light + .05) / (dark + .05);
}

Color _contrastForeground(Color background) =>
    _contrastRatio(background, Colors.white) >= _contrastRatio(background, ink)
        ? Colors.white
        : ink;

Color _accessibleAccent(Color color, {required bool dark}) {
  final background = dark ? const Color(0xff111014) : Colors.white;
  if (_contrastRatio(color, background) >= 4.5) return color;
  final target = dark ? Colors.white : ink;
  for (var step = 1; step <= 24; step++) {
    final adjusted = Color.lerp(color, target, step / 24)!;
    if (_contrastRatio(adjusted, background) >= 4.5) return adjusted;
  }
  return target;
}

Color _whiteContrastSurface(Color color) {
  if (_contrastRatio(color, Colors.white) >= 4.5) return color;
  for (var step = 1; step <= 24; step++) {
    final adjusted = Color.lerp(color, ink, step / 24)!;
    if (_contrastRatio(adjusted, Colors.white) >= 4.5) return adjusted;
  }
  return ink;
}

List<Color> appHeroGradient(BuildContext context, int index) {
  if (!founderSkinEnabled.value) return appGradient(context, index);
  return isDarkTheme(context)
      ? const [Color(0xff211827), Color(0xff30213b)]
      : const [Color(0xffffe8f5), Color(0xffeadfff)];
}

class CaptureMediaRegistry {
  static final Map<String, Uint8List> _bytes = {};
  static final Map<String, String> _types = {};
  static void put(String key, Uint8List bytes, String mediaType) {
    _bytes[key] = bytes;
    _types[key] = mediaType;
  }

  static ({Uint8List bytes, String mediaType})? take(String? key) {
    if (key == null || !_bytes.containsKey(key)) return null;
    return (bytes: _bytes.remove(key)!, mediaType: _types.remove(key)!);
  }
}

class Note {
  Note(this.title, this.source, this.icon,
      {this.id,
      this.path,
      this.mediaType,
      this.topicId,
      this.topicTitle,
      this.content,
      this.speakerMode = 'single',
      this.speakerCount = 1});
  final String? id;
  final String title;
  final String source;
  final IconData icon;
  final String? path;
  final String? mediaType;
  final String? topicId;
  final String? topicTitle;
  final String? content;
  final String speakerMode;
  final int speakerCount;
  factory Note.fromJson(Map<String, dynamic> json) => Note(
      json['title'] as String? ?? 'Sin título',
      json['source'] as String? ?? 'Captura',
      Icons.notes_outlined,
      id: json['id'] as String?,
      path: json['storage_path'] as String?,
      mediaType: json['media_type'] as String?,
      topicId: json['topic_id'] as String?,
      topicTitle: json['topic_title'] as String?,
      speakerMode: json['speaker_mode'] as String? ?? 'single',
      speakerCount: (json['speaker_count'] as num?)?.toInt() ?? 1);
}

class LumenoteApp extends StatelessWidget {
  const LumenoteApp({super.key, this.supabaseReady = false});
  final bool supabaseReady;
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<
          Map<String, dynamic>?>(
      valueListenable: remoteBranding,
      builder: (context, branding, _) => ValueListenableBuilder<bool>(
          valueListenable: founderSkinEnabled,
          builder: (context, isFounder, _) => ValueListenableBuilder<Color>(
              valueListenable: appAccent,
              builder: (context, accent, _) => ValueListenableBuilder<
                      ThemeMode>(
                  valueListenable: appThemeMode,
                  builder: (context, mode, _) => ValueListenableBuilder<String>(
                      valueListenable: appFontFamily,
                      builder: (context, fontFamily, _) {
                        return MaterialApp(
                          debugShowCheckedModeBanner: false,
                          title: isFounder
                              ? (branding?['app_name'] as String? ??
                                  'KuromiNotes')
                              : 'Lumenote',
                          theme: ThemeData(
                            useMaterial3: true,
                            fontFamily: fontFamily.isEmpty ? null : fontFamily,
                            colorScheme: ColorScheme.light(
                                primary: _accessibleAccent(accent, dark: false),
                                onPrimary: _contrastForeground(
                                    _accessibleAccent(accent, dark: false)),
                                secondary:
                                    _accessibleAccent(accent, dark: false),
                                surface: Colors.white,
                                onSurface: ink),
                            scaffoldBackgroundColor: Colors.white,
                            cardTheme: CardThemeData(
                                color: isFounder
                                    ? const Color(0xfffff5fb)
                                    : Colors.white,
                                elevation: 0,
                                margin: EdgeInsets.zero,
                                shape: RoundedRectangleBorder(
                                    borderRadius:
                                        BorderRadius.all(Radius.circular(18)),
                                    side: BorderSide(color: line))),
                            dividerColor: line,
                            filledButtonTheme: FilledButtonThemeData(
                              style: FilledButton.styleFrom(
                                  backgroundColor:
                                      _accessibleAccent(accent, dark: false),
                                  foregroundColor: _contrastForeground(
                                      _accessibleAccent(accent, dark: false)),
                                  disabledBackgroundColor:
                                      const Color(0xffe7e3ec),
                                  disabledForegroundColor:
                                      const Color(0xff6f687c),
                                  minimumSize: const Size(0, 44),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 18, vertical: 12),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(13))),
                            ),
                            outlinedButtonTheme: OutlinedButtonThemeData(
                              style: OutlinedButton.styleFrom(
                                  foregroundColor: ink,
                                  side: BorderSide(
                                      color: _accessibleAccent(accent,
                                          dark: false),
                                      width: 1.5),
                                  minimumSize: const Size(0, 44),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 18, vertical: 12),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(13))),
                            ),
                            textButtonTheme: TextButtonThemeData(
                              style: TextButton.styleFrom(
                                  foregroundColor:
                                      _accessibleAccent(accent, dark: false),
                                  minimumSize: const Size(0, 44),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 14, vertical: 10),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12))),
                            ),
                            inputDecorationTheme: InputDecorationTheme(
                                filled: true,
                                fillColor: const Color(0xfffaf9fc),
                                border: const OutlineInputBorder(
                                    borderRadius:
                                        BorderRadius.all(Radius.circular(14)),
                                    borderSide: BorderSide(color: line)),
                                enabledBorder: const OutlineInputBorder(
                                    borderRadius:
                                        BorderRadius.all(Radius.circular(14)),
                                    borderSide: BorderSide(color: line)),
                                focusedBorder: OutlineInputBorder(
                                    borderRadius: const BorderRadius.all(
                                        Radius.circular(14)),
                                    borderSide:
                                        BorderSide(color: accent, width: 1.5))),
                          ),
                          darkTheme: ThemeData(
                            useMaterial3: true,
                            fontFamily: fontFamily.isEmpty ? null : fontFamily,
                            brightness: Brightness.dark,
                            colorScheme: ColorScheme.dark(
                              primary: _accessibleAccent(accent, dark: true),
                              onPrimary: _contrastForeground(
                                  _accessibleAccent(accent, dark: true)),
                              secondary: _accessibleAccent(accent, dark: true),
                              surface: const Color(0xff17151d),
                              onSurface: const Color(0xfff4effb),
                              surfaceContainerHighest: const Color(0xff292532),
                              error: const Color(0xffffb4ab),
                              onError: const Color(0xff690005),
                            ),
                            scaffoldBackgroundColor: const Color(0xff111014),
                            canvasColor: const Color(0xff17151d),
                            dialogBackgroundColor: const Color(0xff1d1a25),
                            cardTheme: CardThemeData(
                                color: isFounder
                                    ? const Color(0xff28212f)
                                    : const Color(0xff1d1a25),
                                elevation: 0,
                                margin: EdgeInsets.zero,
                                shape: RoundedRectangleBorder(
                                    borderRadius:
                                        BorderRadius.all(Radius.circular(18)),
                                    side:
                                        BorderSide(color: Color(0xff3b3547)))),
                            dividerColor: const Color(0xff3b3547),
                            appBarTheme: const AppBarTheme(
                                backgroundColor: Color(0xff111014),
                                foregroundColor: Color(0xfff4effb),
                                surfaceTintColor: Colors.transparent),
                            bottomSheetTheme: const BottomSheetThemeData(
                                backgroundColor: Color(0xff1d1a25),
                                modalBackgroundColor: Color(0xff1d1a25),
                                surfaceTintColor: Colors.transparent),
                            snackBarTheme: const SnackBarThemeData(
                                backgroundColor: Color(0xff302a3d),
                                contentTextStyle:
                                    TextStyle(color: Color(0xfff4effb))),
                            chipTheme: ChipThemeData(
                                backgroundColor: const Color(0xff292238),
                                selectedColor: const Color(0xff3b3150),
                                labelStyle:
                                    const TextStyle(color: Color(0xfff4effb)),
                                side:
                                    const BorderSide(color: Color(0xff453d52)),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12))),
                            inputDecorationTheme: InputDecorationTheme(
                              filled: true,
                              fillColor: const Color(0xff211e29),
                              labelStyle:
                                  const TextStyle(color: Color(0xffc8c0d2)),
                              hintStyle:
                                  const TextStyle(color: Color(0xff9d95a8)),
                              iconColor: const Color(0xffb9b1c5),
                              prefixIconColor: const Color(0xffb9b1c5),
                              suffixIconColor: const Color(0xffb9b1c5),
                              border: const OutlineInputBorder(
                                  borderRadius:
                                      BorderRadius.all(Radius.circular(14)),
                                  borderSide:
                                      BorderSide(color: Color(0xff453d52))),
                              enabledBorder: const OutlineInputBorder(
                                  borderRadius:
                                      BorderRadius.all(Radius.circular(14)),
                                  borderSide:
                                      BorderSide(color: Color(0xff453d52))),
                              focusedBorder: OutlineInputBorder(
                                  borderRadius: const BorderRadius.all(
                                      Radius.circular(14)),
                                  borderSide:
                                      BorderSide(color: accent, width: 1.5)),
                            ),
                            filledButtonTheme: FilledButtonThemeData(
                                style: FilledButton.styleFrom(
                                    backgroundColor:
                                        _accessibleAccent(accent, dark: true),
                                    foregroundColor: _contrastForeground(
                                        _accessibleAccent(accent, dark: true)),
                                    disabledBackgroundColor:
                                        const Color(0xff393440),
                                    disabledForegroundColor:
                                        const Color(0xff8f8799),
                                    minimumSize: const Size(0, 44),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 18, vertical: 12),
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(13)))),
                            outlinedButtonTheme: OutlinedButtonThemeData(
                                style: OutlinedButton.styleFrom(
                                    foregroundColor: const Color(0xfff4effb),
                                    disabledForegroundColor:
                                        const Color(0xff827a8c),
                                    side: BorderSide(
                                        color: _accessibleAccent(accent,
                                            dark: true),
                                        width: 1.5),
                                    minimumSize: const Size(0, 44),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 18, vertical: 12),
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(13)))),
                            textButtonTheme: TextButtonThemeData(
                                style: TextButton.styleFrom(
                                    foregroundColor: const Color(0xffe3d9ff),
                                    minimumSize: const Size(0, 44),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 14, vertical: 10),
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(12)))),
                          ),
                          themeMode: mode,
                          home: SplashGate(supabaseReady: supabaseReady),
                        );
                      })))));
}

class SplashGate extends StatefulWidget {
  const SplashGate({super.key, required this.supabaseReady});
  final bool supabaseReady;
  @override
  State<SplashGate> createState() => _SplashGateState();
}

class _SplashGateState extends State<SplashGate>
    with SingleTickerProviderStateMixin {
  late final AnimationController controller;
  static const lumenoteFrameCount = 72;
  late final List<String> frames = List.generate(
      lumenoteFrameCount,
      (index) =>
          'assets/branding/splash_frames/frame-${(index + 1).toString().padLeft(2, '0')}.png');
  static const founderFrames = <String>[
    'assets/branding/kuromi_splash_wave_v2.png',
  ];
  bool founder = false;
  bool ready = false;
  bool finished = false;
  @override
  void initState() {
    super.initState();
    controller = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 4032));
    controller.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        if (founder) founderSplashPlayed = true;
        setState(() => finished = true);
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      founder = await _resolveFounderSkin();
      if (widget.supabaseReady && AuthService.user != null) {
        founderRoleCached = founder;
        founderSkinEnabled.value = founder;
        if (founder) {
          remoteBranding.value =
              Map<String, dynamic>.from(kuromiBrandingFallback);
          appAccent.value = _brandingAccent(remoteBranding.value);
        }
      }
      final selectedFrames = founder ? founderFrames : frames;
      await Future.wait(selectedFrames
          .map((asset) => precacheImage(AssetImage(asset), context)));
      if (!mounted) return;
      setState(() => ready = true);
      controller.forward();
    });
  }

  Future<bool> _resolveFounderSkin() async {
    if (!widget.supabaseReady) return false;
    if (AuthService.user == null) {
      try {
        await AuthService.changes.first
            .timeout(const Duration(milliseconds: 900));
      } catch (_) {
        // No persisted session (or auth is offline); continue with default branding.
      }
    }
    if (AuthService.user == null) return false;
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        if (await AuthService.isFounder().timeout(const Duration(seconds: 3))) {
          return true;
        }
      } catch (_) {
        // Retry transient profile/session restoration failures during startup.
      }
      if (attempt < 2) {
        await Future<void>.delayed(const Duration(milliseconds: 350));
      }
    }
    return false;
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (finished) return AuthGate(supabaseReady: widget.supabaseReady);
    final deviceIsDark =
        MediaQuery.platformBrightnessOf(context) == Brightness.dark;
    final splashBackground =
        deviceIsDark ? const Color(0xff111014) : const Color(0xfffbfaff);
    return Scaffold(
        backgroundColor: splashBackground,
        body: Center(
            child: AnimatedBuilder(
                animation: controller,
                builder: (context, _) {
                  final t = Curves.easeInOutCubic.transform(controller.value);
                  final selectedFrames = founder ? founderFrames : frames;
                  final frame = ready
                      ? (controller.value * selectedFrames.length)
                          .floor()
                          .clamp(0, selectedFrames.length - 1)
                      : 0;
                  final Widget artwork = founder
                      ? _KuromiBuildAnimation(progress: controller.value)
                      : Image.asset(selectedFrames[frame],
                          width: 250, height: 250, fit: BoxFit.contain);
                  return Opacity(
                      opacity: ready ? t.clamp(0.0, 1.0) : 1.0,
                      child: Transform.translate(
                          offset: Offset(0, ready ? 8 * (1 - t) : 0),
                          child: Transform.scale(
                              scale: founder
                                  ? .88 +
                                      (.12 *
                                          Curves.easeOutBack
                                              .transform(controller.value)
                                              .clamp(0.0, 1.0))
                                  : ready
                                      ? .96 + (.04 * t)
                                      : .96,
                              child: artwork)));
                })));
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key, required this.supabaseReady});
  final bool supabaseReady;
  @override
  Widget build(BuildContext context) {
    if (!supabaseReady) return const LoginScreen(configurationMissing: true);
    if (AuthService.user == null) return const LoginScreen();
    return StreamBuilder<AuthState>(
        stream: AuthService.changes,
        builder: (_, snapshot) => AuthService.user == null
            ? const LoginScreen()
            : const FounderSkinGate());
  }
}

class FounderSkinGate extends StatefulWidget {
  const FounderSkinGate({super.key});
  @override
  State<FounderSkinGate> createState() => _FounderSkinGateState();
}

class _FounderSkinGateState extends State<FounderSkinGate> {
  bool showKuromiIntro = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    var value = founderRoleCached;
    if (value == null) {
      try {
        value =
            await AuthService.isFounder().timeout(const Duration(seconds: 3));
      } catch (_) {
        value = false;
      }
    }
    if (!mounted) return;
    final isFounder = value ?? false;
    founderRoleCached = isFounder;
    founderSkinEnabled.value = isFounder;
    if (isFounder) {
      remoteBranding.value = Map<String, dynamic>.from(kuromiBrandingFallback);
      appAccent.value = _brandingAccent(remoteBranding.value);
    } else {
      remoteBranding.value = null;
      appAccent.value = paletteOptions[selectedPalette.value].accent;
    }
    setState(() {
      showKuromiIntro = isFounder && !founderSplashPlayed;
    });
    if (isFounder) unawaited(_refreshRemoteBranding());
  }

  Future<void> _refreshRemoteBranding() async {
    try {
      final branding = await AiGateway.branding().timeout(
        const Duration(seconds: 4),
      );
      if (branding == null || !mounted) return;
      remoteBranding.value = {...kuromiBrandingFallback, ...branding};
      appAccent.value = _brandingAccent(remoteBranding.value);
    } catch (_) {
      // Local Kuromi branding remains available if the remote request is slow/offline.
    }
  }

  @override
  Widget build(BuildContext context) {
    if (showKuromiIntro) {
      return _KuromiLoginSplash(onComplete: () {
        founderSplashPlayed = true;
        if (mounted) setState(() => showKuromiIntro = false);
      });
    }
    return const Shell();
  }
}

class _KuromiLoginSplash extends StatefulWidget {
  const _KuromiLoginSplash({required this.onComplete});
  final VoidCallback onComplete;
  @override
  State<_KuromiLoginSplash> createState() => _KuromiLoginSplashState();
}

class _KuromiLoginSplashState extends State<_KuromiLoginSplash>
    with SingleTickerProviderStateMixin {
  late final AnimationController controller;
  static const frames = <String>['assets/branding/kuromi_splash_wave_v2.png'];
  bool ready = false;

  @override
  void initState() {
    super.initState();
    controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4032),
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed) widget.onComplete();
      });
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Future.wait(
          frames.map((asset) => precacheImage(AssetImage(asset), context)));
      if (!mounted) return;
      setState(() => ready = true);
      controller.forward();
    });
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = MediaQuery.platformBrightnessOf(context) == Brightness.dark;
    return Scaffold(
      backgroundColor: dark ? const Color(0xff111014) : const Color(0xfffff8fc),
      body: Center(
        child: AnimatedBuilder(
          animation: controller,
          builder: (context, _) {
            final t = Curves.easeInOutCubic.transform(controller.value);
            return Opacity(
              opacity: ready ? t.clamp(0.0, 1.0) : 1,
              child: Transform.translate(
                offset: Offset(0, ready ? 8 * (1 - t) : 0),
                child: Transform.scale(
                  scale: .88 +
                      (.12 *
                          Curves.easeOutBack
                              .transform(controller.value)
                              .clamp(0.0, 1.0)),
                  child: _KuromiBuildAnimation(
                      progress: controller.value, size: 300),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _KuromiBuildAnimation extends StatelessWidget {
  const _KuromiBuildAnimation({required this.progress, this.size = 290});
  final double progress;
  final double size;

  @override
  Widget build(BuildContext context) {
    final reveal =
        Curves.easeOutCubic.transform(progress).clamp(0.01, 1.0).toDouble();
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: size * .84,
            height: size * .84,
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(colors: [
                  const Color(0xffffc7df).withValues(alpha: .24),
                  const Color(0xffa889d8).withValues(alpha: .10),
                  Colors.transparent,
                ]),
              ),
            ),
          ),
          ClipRect(
            child: Align(
              alignment: Alignment.bottomCenter,
              heightFactor: reveal,
              child: _KuromiWaveSprite(progress: progress, size: size),
            ),
          ),
        ],
      ),
    );
  }
}

class _KuromiWaveSprite extends StatelessWidget {
  const _KuromiWaveSprite({required this.progress, required this.size});
  final double progress;
  final double size;

  static const _asset = 'assets/branding/kuromi_splash_wave_v2.png';
  static final Future<ui.Image> _sheet = _loadSheet();

  static Future<ui.Image> _loadSheet() async {
    final data = await rootBundle.load(_asset);
    final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
    try {
      return (await codec.getNextFrame()).image;
    } finally {
      codec.dispose();
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<ui.Image>(
      future: _sheet,
      builder: (context, snapshot) {
        final image = snapshot.data;
        if (image == null) return SizedBox.square(dimension: size);
        return CustomPaint(
          size: Size.square(size),
          painter: _KuromiWaveFramePainter(image, progress),
        );
      });
}

class _KuromiWaveFramePainter extends CustomPainter {
  const _KuromiWaveFramePainter(this.sheet, this.progress);
  final ui.Image sheet;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    // Alternate the clearly different relaxed and raised-arm poses. The generated
    // in-between cells were too similar to read as motion at splash-screen size.
    const waveFrames = [0, 2, 0, 2, 0, 2, 0, 2];
    final normalized = progress.clamp(0.0, 1.0).toDouble();
    final frame = normalized < .12
        ? 0
        : waveFrames[(((normalized - .12) / .88) * waveFrames.length)
            .floor()
            .clamp(0, waveFrames.length - 1)];
    final cellWidth = sheet.width / 2;
    final cellHeight = sheet.height / 2;
    final source = Rect.fromLTWH((frame % 2) * cellWidth,
        (frame ~/ 2) * cellHeight, cellWidth, cellHeight);
    canvas.drawImageRect(sheet, source, Offset.zero & size,
        Paint()..filterQuality = FilterQuality.high);
  }

  @override
  bool shouldRepaint(covariant _KuromiWaveFramePainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.sheet != sheet;
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, this.configurationMissing = false});
  final bool configurationMissing;
  @override
  State<LoginScreen> createState() => _LoginState();
}

class _LoginState extends State<LoginScreen> {
  final email = TextEditingController();
  final password = TextEditingController();
  bool create = false;
  bool busy = false;
  String? error;

  @override
  void dispose() {
    email.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (widget.configurationMissing) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (create) {
        await AuthService.signUp(email.text, password.text);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Revisa tu correo para confirmar la cuenta.')),
          );
        }
      } else {
        await AuthService.signIn(email.text, password.text);
      }
    } on AuthException catch (e) {
      if (mounted) setState(() => error = _friendlyAuthError(e.message));
    } catch (_) {
      if (mounted) setState(() => error = 'No se pudo completar el acceso.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  String _friendlyAuthError(String message) {
    final lower = message.toLowerCase();
    if (lower.contains('socketexception') ||
        lower.contains('connection failed') ||
        lower.contains('operation not permitted') ||
        lower.contains('failed host lookup')) {
      return 'No se pudo conectar con el servidor. Verifica tu conexión e inténtalo de nuevo.';
    }
    if (lower.contains('invalid login credentials'))
      return 'El correo o la contraseña no son correctos.';
    if (lower.contains('email not confirmed'))
      return 'Confirma tu correo antes de iniciar sesión.';
    if (lower.contains('network'))
      return 'No hay conexión disponible. Inténtalo de nuevo.';
    return 'No se pudo iniciar sesión. Inténtalo de nuevo.';
  }

  Widget _brandPanel({bool compact = false}) => Container(
        padding: EdgeInsets.all(compact ? 24 : 42),
        decoration: const BoxDecoration(
            gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
              Color(0xff09090b),
              Color(0xff211a52),
              Color(0xff6757e8)
            ])),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment:
                compact ? MainAxisAlignment.center : MainAxisAlignment.start,
            children: [
              AdaptiveLogo(size: compact ? 48 : 58),
              SizedBox(height: compact ? 18 : 0),
              if (!compact) const Spacer(),
              Text('Tus ideas,\ncon contexto.',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: compact ? 30 : 42,
                      height: 1.05,
                      fontWeight: FontWeight.w700)),
              SizedBox(height: compact ? 10 : 18),
              Text('Captura, transcribe y vuelve a encontrar lo importante.',
                  style: TextStyle(
                      color: Color(0xffe6e1ff),
                      fontSize: compact ? 14 : 16,
                      height: 1.4)),
              if (!compact) ...[
                const SizedBox(height: 26),
                const Text('Un espacio privado para aprender mejor.',
                    style: TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w600)),
              ],
            ]),
      );

  Widget _newFormPanel({bool compact = false}) => Container(
        color: isDarkTheme(context) ? const Color(0xff17151d) : Colors.white,
        padding: EdgeInsets.symmetric(
            horizontal: compact ? 24 : 72, vertical: compact ? 24 : 28),
        child: Column(
            mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('Bienvenido a Lumenote',
                  style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      color: appText(context))),
              const SizedBox(height: 8),
              Text(
                  create
                      ? 'Crea tu espacio privado para aprender.'
                      : 'Accede a tus notas y capturas.',
                  style: TextStyle(color: appMutedText(context), fontSize: 15)),
              const SizedBox(height: 28),
              if (widget.configurationMissing)
                Text(
                    'El servicio de acceso no está disponible temporalmente. Recarga en unos segundos.',
                    style: TextStyle(color: appErrorText(context), height: 1.4))
              else ...[
                TextField(
                    controller: email,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                        labelText: 'Correo electrónico',
                        prefixIcon: Icon(Icons.mail_outline))),
                const SizedBox(height: 14),
                TextField(
                    controller: password,
                    obscureText: true,
                    decoration: const InputDecoration(
                        labelText: 'Contraseña',
                        prefixIcon: Icon(Icons.lock_outline))),
                if (error != null)
                  Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(error!,
                          style: TextStyle(color: appErrorText(context)))),
                const SizedBox(height: 22),
                SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: FilledButton(
                        onPressed: busy ? null : submit,
                        style: FilledButton.styleFrom(
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14))),
                        child: Text(busy
                            ? 'Procesando…'
                            : (create ? 'Crear mi cuenta' : 'Entrar')))),
                const SizedBox(height: 8),
                Center(
                    child: TextButton(
                        onPressed: () => setState(() {
                              create = !create;
                              error = null;
                            }),
                        child: Text(create
                            ? 'Ya tengo una cuenta'
                            : 'Crear una cuenta'))),
              ],
            ]),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        body: SafeArea(child: LayoutBuilder(builder: (context, constraints) {
      final wide = constraints.maxWidth >= 820;
      if (wide) {
        return Row(children: [
          Expanded(child: _brandPanel()),
          Expanded(child: _newFormPanel())
        ]);
      }
      return SingleChildScrollView(
          child: Column(children: [
        SizedBox(height: 300, child: _brandPanel(compact: true)),
        _newFormPanel(compact: true)
      ]));
    })));
  }

  Widget _oldBuild(BuildContext context) => Scaffold(
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(26),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const AdaptiveLogo(size: 56),
                      const SizedBox(height: 20),
                      const Text('Lumenote',
                          style: TextStyle(
                              fontSize: 30, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      const Text(
                          'Tu espacio privado para capturar, transcribir y aprender.',
                          style: TextStyle(color: muted, height: 1.35)),
                      Text(widget.configurationMissing
                          ? 'Configura Supabase para activar el acceso.'
                          : (create
                              ? 'Crea tu cuenta'
                              : 'Inicia sesión para ver tus notas')),
                      const SizedBox(height: 22),
                      if (!widget.configurationMissing) ...[
                        TextField(
                          controller: email,
                          keyboardType: TextInputType.emailAddress,
                          decoration: const InputDecoration(
                              labelText: 'Correo',
                              border: OutlineInputBorder()),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: password,
                          obscureText: true,
                          decoration: const InputDecoration(
                              labelText: 'Contraseña',
                              border: OutlineInputBorder()),
                        ),
                        if (error != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: Text(error!,
                                style: const TextStyle(color: Colors.red)),
                          ),
                        const SizedBox(height: 18),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            onPressed: busy ? null : submit,
                            child: Text(busy
                                ? 'Procesando…'
                                : (create ? 'Crear cuenta' : 'Entrar')),
                          ),
                        ),
                        TextButton(
                          onPressed: () => setState(() {
                            create = !create;
                            error = null;
                          }),
                          child: Text(create
                              ? 'Ya tengo una cuenta'
                              : 'Crear una cuenta'),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
}

class Shell extends StatefulWidget {
  const Shell({super.key});
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int page = pageForWebPath(currentWebPath());
  bool sidebarExpanded = true;
  final notes = <Note>[];
  bool loading = true;
  final labels = const [
    'Inicio',
    'Biblioteca',
    'Capturar',
    'Flashcards',
    'Quizzes',
    'Ajustes'
  ];
  String? activeTopicId;
  String? activeTopicTitle;
  @override
  void initState() {
    super.initState();
    if (currentWebPath() == null || currentWebPath() == '/')
      setWebPath('/inicio');
    _loadNotes();
  }

  Future<void> _loadNotes() async {
    try {
      final rows = await AiGateway.notes(ownerId: AuthService.user!.id);
      if (mounted)
        setState(() {
          notes
            ..clear()
            ..addAll(rows.map(Note.fromJson));
          loading = false;
        });
    } catch (_) {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final small = MediaQuery.sizeOf(context).width < 800;
    final ios = defaultTargetPlatform == TargetPlatform.iOS;
    final screens = <Widget>[
      HomeScreen(
          notes: notes,
          onCapture: () => setState(() {
                activeTopicId = null;
                activeTopicTitle = null;
                page = 2;
              }),
          onOpen: _open,
          onCaptureInTopic: (topic) {
            setState(() {
              activeTopicId = topic['id'] as String?;
              activeTopicTitle = topic['title'] as String?;
              page = 2;
            });
          }),
      TopicLibraryScreen(
          onOpen: _open,
          onDelete: _delete,
          onCaptureInTopic: (topic) {
            setState(() {
              activeTopicId = topic['id'] as String?;
              activeTopicTitle = topic['title'] as String?;
              page = 2;
            });
          }),
      CaptureScreen(
          onCreated: _saveNote,
          topicId: activeTopicId,
          topicTitle: activeTopicTitle),
      StudyHubScreen(
          onCreateTopic: () => setState(() => page = 1),
          onCreateNote: () => setState(() => page = 2)),
      const QuizScreen(),
      CompactSettingsScreen(
          onOpenAccount: () => _goPage(6), onOpenPrivacy: () => _goPage(7)),
      AccountMembershipScreen(
          onOpenPrivacy: () => _goPage(7), onOpenFounder: () => _goPage(8)),
      const PrivacyDataScreen(),
      const FounderAdminScreen(),
    ];
    final activeContent =
        loading && page == 0 ? const _HomeLoadingState() : screens[page];
    return Scaffold(
      appBar: null,
      bottomNavigationBar: small
          ? (ios
              ? IOSBottomNav(
                  selectedIndex: _mobileIndex, onSelect: _selectMobileIndex)
              : NavigationBar(
                  selectedIndex: _mobileIndex,
                  onDestinationSelected: _selectMobileIndex,
                  height: 68,
                  labelBehavior:
                      NavigationDestinationLabelBehavior.onlyShowSelected,
                  destinations: const [
                    NavigationDestination(
                        icon: Icon(Icons.home_outlined),
                        selectedIcon: Icon(Icons.home_rounded),
                        label: 'Inicio'),
                    NavigationDestination(
                        icon: Icon(Icons.library_books_outlined),
                        selectedIcon: Icon(Icons.library_books_rounded),
                        label: 'Biblioteca'),
                    NavigationDestination(
                        icon: Icon(Icons.school_outlined),
                        selectedIcon: Icon(Icons.school_rounded),
                        label: 'Estudiar'),
                    NavigationDestination(
                        icon: Icon(Icons.settings_outlined),
                        selectedIcon: Icon(Icons.settings_rounded),
                        label: 'Ajustes'),
                  ],
                ))
          : null,
      body: Row(children: [
        if (!small)
          CompactSideNav(
              selected: page,
              expanded: sidebarExpanded,
              onSelect: _goPage,
              onProfile: () => _goPage(6)),
        Expanded(
            child: small
                ? _transitionPage(activeContent)
                : Stack(children: [
                    Positioned(
                        top: 8,
                        left: 8,
                        child: IconButton(
                            onPressed: () => setState(
                                () => sidebarExpanded = !sidebarExpanded),
                            tooltip: sidebarExpanded
                                ? 'Contraer navegaci?n'
                                : 'Expandir navegaci?n',
                            color: Theme.of(context).colorScheme.onSurface,
                            splashRadius: 22,
                            icon: Icon(sidebarExpanded
                                ? Icons.view_sidebar_outlined
                                : Icons.view_sidebar_rounded))),
                    Positioned.fill(
                        child: Padding(
                            padding: const EdgeInsets.only(top: 54),
                            child: _transitionPage(activeContent))),
                  ])),
      ]),
    );
  }

  Widget _transitionPage(Widget child) => AnimatedSwitcher(
        duration: const Duration(milliseconds: 260),
        reverseDuration: const Duration(milliseconds: 190),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (child, animation) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          );
          return FadeTransition(
            opacity: curved,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0.018, 0),
                end: Offset.zero,
              ).animate(curved),
              child: child,
            ),
          );
        },
        child: KeyedSubtree(
          key: ValueKey('$page-${loading && page == 0}'),
          child: child,
        ),
      );

  int get _mobileIndex => page == 1
      ? 1
      : page >= 3 && page <= 4
          ? 2
          : page == 5
              ? 3
              : 0;
  void _selectMobileIndex(int index) => _goPage([0, 1, 3, 5][index]);
  void _goPage(int target) {
    setState(() {
      page = target;
      if (target != 2) {
        activeTopicId = null;
        activeTopicTitle = null;
      }
    });
    setWebPath(_pagePath(target));
  }

  String _pagePath(int target) => const [
        '/home',
        '/library',
        '/capture',
        '/study',
        '/quizzes',
        '/settings',
        '/account',
        '/privacy',
        '/founder'
      ][target.clamp(0, 8)];
  void _open(Note note) => Navigator.push(
      context, MaterialPageRoute(builder: (_) => NoteScreen(note: note)));
  Future<void> _saveNote(Note note) async {
    final initial = note.content == null ? note.title : 'Nota de texto';
    final title = await _askName('Nombre de la nota', initial);
    if (title == null || title.isEmpty) return;
    final originalContent = note.content;
    note = Note(title, note.source, note.icon,
        path: note.path,
        mediaType: note.mediaType,
        topicId: activeTopicId,
        topicTitle: activeTopicTitle,
        content: originalContent,
        speakerMode: note.speakerMode,
        speakerCount: note.speakerCount);
    try {
      final media = CaptureMediaRegistry.take(note.path);
      final row = await AiGateway.createNote(
          ownerId: AuthService.user!.id,
          title: note.title,
          source: note.source,
          mediaType: media?.mediaType,
          storagePath: note.path,
          topicId: activeTopicId);
      String? processingError;
      try {
        if (media != null) {
          final extension = media.mediaType.split('/').last;
          await AiGateway.processMedia(
              noteId: row['id'] as String,
              bytes: media.bytes,
              filename: 'capture.$extension',
              mediaType: media.mediaType,
              speakerMode: note.speakerMode,
              speakerCount: note.speakerCount);
        } else if (note.source.startsWith('Texto')) {
          await AiGateway.processText(
              noteId: row['id'] as String, text: originalContent ?? note.title);
        }
      } catch (error) {
        processingError = error.toString();
      }
      if (mounted) {
        setState(() {
          notes.insert(0, Note.fromJson(row));
          page = 1;
        });
        if (processingError != null)
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(
                  'Nota guardada; el procesamiento IA quedó pendiente: $processingError')));
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Future<String?> _askName(String label, String initial) async {
    final controller = TextEditingController(text: initial);
    final result = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
                title: Text(label),
                content: TextField(
                    controller: controller,
                    autofocus: true,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                        labelText: 'Nombre',
                        hintText: 'Ej. Clase 3 · fotosíntesis')),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      child: const Text('Cancelar')),
                  FilledButton(
                      onPressed: () =>
                          Navigator.pop(dialogContext, controller.text.trim()),
                      child: const Text('Guardar'))
                ]));
    controller.dispose();
    return result;
  }

  Future<void> _delete(Note note) async {
    final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
                title: const Text('Eliminar captura?'),
                content: const Text('Se eliminará la nota y su captura local.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancelar')),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Eliminar'))
                ]));
    if (ok == true && note.id != null) {
      try {
        await AiGateway.deleteNote(note.id!);
        if (mounted) setState(() => notes.remove(note));
      } catch (e) {
        if (mounted)
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }
}

class IOSBottomNav extends StatelessWidget {
  const IOSBottomNav(
      {super.key, required this.selectedIndex, required this.onSelect});
  final int selectedIndex;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          color: dark ? const Color(0xff17151d) : Colors.white,
          border:
              Border(top: BorderSide(color: Theme.of(context).dividerColor)),
        ),
        child: CupertinoTabBar(
          currentIndex: selectedIndex,
          onTap: onSelect,
          backgroundColor: Colors.transparent,
          activeColor: colors.primary,
          inactiveColor:
              dark ? const Color(0xffaaa2b8) : const Color(0xff706a7d),
          iconSize: 22,
          height: 52,
          items: const [
            BottomNavigationBarItem(
                icon: Icon(CupertinoIcons.house),
                activeIcon: Icon(CupertinoIcons.house_fill),
                label: 'Inicio'),
            BottomNavigationBarItem(
                icon: Icon(CupertinoIcons.book),
                activeIcon: Icon(CupertinoIcons.book_fill),
                label: 'Biblioteca'),
            BottomNavigationBarItem(
                icon: Icon(CupertinoIcons.lightbulb),
                activeIcon: Icon(CupertinoIcons.lightbulb_fill),
                label: 'Estudiar'),
            BottomNavigationBarItem(
                icon: Icon(CupertinoIcons.gear),
                activeIcon: Icon(CupertinoIcons.gear_solid),
                label: 'Ajustes'),
          ],
        ),
      ),
    );
  }
}

class SideNav extends StatelessWidget {
  const SideNav({super.key, required this.selected, required this.onSelect});
  final int selected;
  final ValueChanged<int> onSelect;
  @override
  Widget build(BuildContext context) => Container(
        width: 84,
        color: isDarkTheme(context) ? const Color(0xff17151d) : Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 18),
        child: SafeArea(
            child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 24),
            child: const AdaptiveLogo(size: 40),
          ),
          Expanded(
              child: ListView(padding: EdgeInsets.zero, children: [
            _item(context, 0, Icons.notes_outlined, 'Notas', selected < 3),
            _item(context, 3, Icons.school_outlined, 'Estudiar',
                selected >= 3 && selected < 5),
            _item(
                context, 5, Icons.settings_outlined, 'Ajustes', selected == 5),
          ])),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
                color: appSoftSurface(context),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Theme.of(context).dividerColor)),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('PLAN GRATUITO',
                  style: TextStyle(
                      color: appMutedText(context),
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: .5)),
              const SizedBox(height: 8),
              Text('48 min de transcripcion disponibles.',
                  style: TextStyle(
                      color: appText(context), fontSize: 13, height: 1.25)),
              const SizedBox(height: 12),
              Text('Ver planes  →',
                  style: TextStyle(
                      color: brand, fontSize: 13, fontWeight: FontWeight.bold)),
            ]),
          ),
        ])),
      );

  Widget _item(BuildContext context, int target, IconData icon, String label,
          bool active) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(13),
              onTap: () => onSelect(target),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 13, vertical: 13),
                decoration: BoxDecoration(
                    color:
                        active ? appAccentSurface(context) : Colors.transparent,
                    borderRadius: BorderRadius.circular(13)),
                child: Row(children: [
                  Icon(icon,
                      color: active
                          ? Theme.of(context).colorScheme.primary
                          : appMutedText(context),
                      size: 21),
                  const SizedBox(width: 12),
                  Expanded(
                      child: Text(label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: active
                                  ? Theme.of(context).colorScheme.primary
                                  : appText(context),
                              fontWeight:
                                  active ? FontWeight.w700 : FontWeight.w500)))
                ]),
              ),
            )),
      );
}

class AdaptiveLogo extends StatelessWidget {
  const AdaptiveLogo({super.key, this.size = 40});
  final double size;
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
      valueListenable: founderSkinEnabled,
      builder: (context, founder, _) =>
          ValueListenableBuilder<Map<String, dynamic>?>(
              valueListenable: remoteBranding,
              builder: (context, branding, _) {
                final logoUrl =
                    founder ? (branding?['logo_url'] as String?) : null;
                return logoUrl != null && logoUrl.isNotEmpty
                    ? Image.network(logoUrl,
                        width: size,
                        height: size,
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => KuromiIsotype(size: size))
                    : founder
                        ? KuromiIsotype(size: size)
                        : Image.asset(
                            Theme.of(context).brightness == Brightness.dark
                                ? 'assets/branding/lumenote_isotype_dark.png'
                                : 'assets/branding/lumenote_isotype_light.png',
                            width: size,
                            height: size,
                            fit: BoxFit.contain);
              }));
}

class KuromiIsotype extends StatelessWidget {
  const KuromiIsotype({super.key, this.size = 40});
  final double size;
  @override
  Widget build(BuildContext context) => SizedBox(
      width: size,
      height: size,
      child: Image.asset('assets/branding/kuromi_isotype_v2.png',
          fit: BoxFit.contain));
}

class KuromiMarkPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final center = Offset(size.width / 2, size.height / 2 + s * .06);
    final pink = Paint()..color = const Color(0xffff77b7);
    final black = Paint()..color = const Color(0xff15121b);
    final white = Paint()..color = const Color(0xfffff7fc);
    final earLeft = Path()
      ..moveTo(center.dx - s * .28, center.dy - s * .2)
      ..lineTo(center.dx - s * .4, center.dy - s * .49)
      ..lineTo(center.dx - s * .06, center.dy - s * .32)
      ..close();
    final earRight = Path()
      ..moveTo(center.dx + s * .28, center.dy - s * .2)
      ..lineTo(center.dx + s * .4, center.dy - s * .49)
      ..lineTo(center.dx + s * .06, center.dy - s * .32)
      ..close();
    canvas.drawPath(earLeft, black);
    canvas.drawPath(earRight, black);
    canvas.drawCircle(center, s * .32, black);
    final face = RRect.fromRectAndRadius(
        Rect.fromCenter(
            center: Offset(center.dx, center.dy + s * .04),
            width: s * .48,
            height: s * .34),
        Radius.circular(s * .17));
    canvas.drawRRect(face, white);
    final skull = Path()
      ..addOval(Rect.fromCenter(
          center: Offset(center.dx, center.dy - s * .19),
          width: s * .2,
          height: s * .13));
    canvas.drawPath(skull, pink);
    canvas.drawCircle(
        Offset(center.dx - s * .04, center.dy - s * .19), s * .018, black);
    canvas.drawCircle(
        Offset(center.dx + s * .04, center.dy - s * .19), s * .018, black);
    final k = TextPainter(
        text: TextSpan(
            text: 'K',
            style: TextStyle(
                color: pink.color,
                fontFamily: 'Quicksand',
                fontSize: s * .27,
                fontWeight: FontWeight.w900)),
        textDirection: TextDirection.ltr)
      ..layout();
    k.paint(canvas, Offset(center.dx - k.width / 2, center.dy - k.height * .2));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class DesktopContentHeader extends StatelessWidget {
  const DesktopContentHeader(
      {super.key, required this.expanded, required this.onToggle});
  final bool expanded;
  final VoidCallback onToggle;
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      decoration: BoxDecoration(
          color: dark ? const Color(0xff111014) : Colors.white,
          border: Border(
              bottom:
                  BorderSide(color: dark ? const Color(0xff302a3d) : line))),
      child: Row(children: [
        IconButton(
            onPressed: onToggle,
            tooltip: expanded ? 'Contraer navegación' : 'Expandir navegación',
            color: Theme.of(context).colorScheme.onSurface,
            splashRadius: 22,
            icon: Icon(expanded
                ? Icons.view_sidebar_outlined
                : Icons.view_sidebar_rounded)),
        const Spacer(),
      ]),
    );
  }
}

class CompactSideNav extends StatelessWidget {
  const CompactSideNav(
      {super.key,
      required this.selected,
      required this.onSelect,
      this.expanded = false,
      this.onToggle,
      this.onProfile});
  final int selected;
  final ValueChanged<int> onSelect;
  final bool expanded;
  final VoidCallback? onToggle;
  final VoidCallback? onProfile;
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      width: expanded ? 220 : 76,
      decoration: BoxDecoration(
        color: dark ? const Color(0xff15121c) : Colors.white,
        borderRadius: const BorderRadius.only(
            topRight: Radius.circular(22), bottomRight: Radius.circular(22)),
        border: Border(
            right: BorderSide(color: dark ? const Color(0xff302a3d) : line)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
      child: SafeArea(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(
            height: expanded ? 76 : 58,
            child: Stack(clipBehavior: Clip.none, children: [
              Positioned.fill(
                  child: Center(child: AdaptiveLogo(size: expanded ? 58 : 34))),
              if (onToggle != null)
                Positioned(
                    right: 0,
                    top: expanded ? 8 : 14,
                    child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                            onTap: onToggle,
                            borderRadius: BorderRadius.circular(11),
                            child: Container(
                                width: expanded ? 34 : 30,
                                height: expanded ? 34 : 30,
                                decoration: BoxDecoration(
                                    color: dark
                                        ? const Color(0xff292331)
                                        : const Color(0xfff2effb),
                                    borderRadius: BorderRadius.circular(11),
                                    border: Border.all(
                                        color: dark
                                            ? const Color(0xff45395a)
                                            : line)),
                                child: Icon(
                                    expanded
                                        ? Icons.menu_open_rounded
                                        : Icons.menu_rounded,
                                    size: expanded ? 20 : 18,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .primary))))),
            ])),
        SizedBox(height: expanded ? 18 : 14),
        Expanded(
            child: ListView(padding: EdgeInsets.zero, children: [
          _item(context, 0, Icons.notes_outlined, 'Notas', selected < 3),
          _item(context, 3, Icons.school_outlined, 'Estudiar',
              selected >= 3 && selected < 5),
          _item(context, 5, Icons.settings_outlined, 'Ajustes', selected == 5),
        ])),
        const SizedBox(height: 10),
        _profile(context),
      ])),
    );
  }

  Widget _item(BuildContext context, int target, IconData icon, String label,
      bool active) {
    final accent = Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Tooltip(
          message: label,
          child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => onSelect(target),
                child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 13),
                    decoration: BoxDecoration(
                        color: active
                            ? accent.withOpacity(.16)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(14)),
                    child: Row(children: [
                      Icon(icon,
                          color: active
                              ? accent
                              : Theme.of(context)
                                  .colorScheme
                                  .onSurface
                                  .withOpacity(.68),
                          size: 22),
                      if (expanded) ...[
                        const SizedBox(width: 12),
                        Text(label,
                            style: TextStyle(
                                color: active
                                    ? accent
                                    : Theme.of(context)
                                        .colorScheme
                                        .onSurface
                                        .withOpacity(.78),
                                fontWeight:
                                    active ? FontWeight.w800 : FontWeight.w600))
                      ]
                    ])),
              ))),
    );
  }

  Widget _profile(BuildContext context) {
    final email = AuthService.user?.email ?? 'Cuenta';
    final initial = email.isEmpty ? 'U' : email.substring(0, 1).toUpperCase();
    final dark = isDarkTheme(context);
    final profileText = Theme.of(context).colorScheme.onSurface;
    return Tooltip(
        message: 'Abrir perfil',
        child: Material(
            color: Colors.transparent,
            child: InkWell(
                onTap: onProfile,
                borderRadius: BorderRadius.circular(14),
                child: Container(
                    padding: EdgeInsets.symmetric(
                        horizontal: expanded ? 10 : 7, vertical: 9),
                    decoration: BoxDecoration(
                        color: dark
                            ? const Color(0xff211d2b)
                            : const Color(0xfff8f7fc),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                            color: dark ? const Color(0xff3b334b) : line)),
                    child: Row(children: [
                      CircleAvatar(
                          radius: 17,
                          backgroundColor: dark ? Colors.white : ink,
                          foregroundColor: dark ? ink : Colors.white,
                          child: Text(initial,
                              style: const TextStyle(
                                  fontSize: 13, fontWeight: FontWeight.w800))),
                      if (expanded) ...[
                        const SizedBox(width: 10),
                        Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                              Text('Mi perfil',
                                  style: TextStyle(
                                      color: profileText,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800)),
                              Text(email,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      color: profileText.withOpacity(.68),
                                      fontSize: 11))
                            ])),
                        if (expanded)
                          Icon(Icons.chevron_right,
                              size: 18, color: profileText.withOpacity(.68))
                      ]
                    ])))));
  }
}

class Frame extends StatelessWidget {
  const Frame({super.key, required this.child, this.title, this.action});
  final Widget child;
  final String? title;
  final Widget? action;
  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 600;
    final horizontal = compact ? 16.0 : 28.0;
    return Center(
        child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1180),
            child: ListView(
                padding: EdgeInsets.fromLTRB(
                    horizontal, compact ? 18 : 28, horizontal, 28),
                children: [
                  if (title != null)
                    LayoutBuilder(
                        builder: (context, constraints) => Flex(
                                direction: constraints.maxWidth < 520
                                    ? Axis.vertical
                                    : Axis.horizontal,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  constraints.maxWidth < 520
                                      ? Text(title!,
                                          style: TextStyle(
                                              color: appText(context),
                                              fontSize: compact ? 23 : 28,
                                              fontWeight: FontWeight.w800))
                                      : Expanded(
                                          child: Text(title!,
                                              style: TextStyle(
                                                  color: appText(context),
                                                  fontSize: compact ? 23 : 28,
                                                  fontWeight:
                                                      FontWeight.w800))),
                                  if (action != null) ...[
                                    if (constraints.maxWidth < 520)
                                      const SizedBox(height: 12),
                                    action!
                                  ],
                                ])),
                  if (title != null) SizedBox(height: compact ? 16 : 22),
                  child,
                ])));
  }
}

class StudyHero extends StatelessWidget {
  const StudyHero(
      {super.key, required this.onNewTopic, required this.onCapture});
  final VoidCallback onNewTopic;
  final VoidCallback onCapture;
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
      valueListenable: selectedPalette,
      builder: (context, index, _) =>
          LayoutBuilder(builder: (context, constraints) {
            final compact = constraints.maxWidth < 720;
            final founder = founderSkinEnabled.value;
            final dark = isDarkTheme(context);
            final heroTitleColor = founder
                ? (dark ? const Color(0xfffff0fa) : const Color(0xff34243b))
                : Colors.white;
            final heroSubtitleColor = founder
                ? (dark ? const Color(0xffdfcde7) : const Color(0xff5f4b66))
                : Colors.white70;
            final heroGradient = appHeroGradient(context, index);
            final copy = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  ValueListenableBuilder<bool>(
                      valueListenable: founderSkinEnabled,
                      builder: (context, founder, _) =>
                          ValueListenableBuilder<Map<String, dynamic>?>(
                              valueListenable: remoteBranding,
                              builder: (context, branding, _) => Text(
                                  founder
                                      ? (branding?['app_name'] as String? ??
                                              'KUROMINOTES')
                                          .toUpperCase()
                                      : 'TU ESPACIO DE ESTUDIO',
                                  style: TextStyle(
                                      color: founder
                                          ? (dark
                                              ? const Color(0xffe6b9e1)
                                              : const Color(0xff79518a))
                                          : const Color(0xffe6deff),
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 1.1)))),
                  const SizedBox(height: 10),
                  Text('Organiza cada clase en un solo lugar',
                      style: TextStyle(
                          color: heroTitleColor,
                          fontSize: 28,
                          height: 1.04,
                          fontWeight: FontWeight.w800)),
                  const SizedBox(height: 10),
                  Text(
                      'Agrupa audios, imágenes, documentos y apuntes para que la IA entienda todo el contexto.',
                      style: TextStyle(
                          color: heroSubtitleColor, height: 1.4, fontSize: 13)),
                  const SizedBox(height: 18),
                  Wrap(spacing: 10, runSpacing: 10, children: [
                    FilledButton.icon(
                        onPressed: onNewTopic,
                        icon: const Icon(Icons.create_new_folder_outlined,
                            size: 18),
                        label: const Text('Nuevo tema')),
                    OutlinedButton.icon(
                        onPressed: onCapture,
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('Nueva captura'),
                        style: OutlinedButton.styleFrom(
                            foregroundColor: heroTitleColor,
                            side: BorderSide(
                                color: founder
                                    ? const Color(0xff9b79aa)
                                    : Colors.white54)))
                  ])
                ]);
            final visual = SizedBox(
                width: compact ? double.infinity : 250,
                height: compact ? 188 : 220,
                child: ValueListenableBuilder<bool>(
                    valueListenable: founderSkinEnabled,
                    builder: (context, founder, _) {
                      if (!founder) {
                        return Image.asset(
                            'assets/branding/home_hero_content.png',
                            fit: BoxFit.contain);
                      }
                      final heroUrl =
                          remoteBranding.value?['hero_url'] as String?;
                      if (heroUrl != null && heroUrl.isNotEmpty) {
                        return Image.network(heroUrl,
                            fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) => Image.asset(
                                'assets/branding/kuromi_home_organizing.png',
                                fit: BoxFit.contain));
                      }
                      return Image.asset(
                          'assets/branding/kuromi_home_organizing.png',
                          fit: BoxFit.contain);
                    }));
            return Container(
                padding: EdgeInsets.all(compact ? 20 : 28),
                decoration: BoxDecoration(
                    gradient: LinearGradient(
                        colors: heroGradient,
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight),
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                          color: paletteOptions[index].accent.withOpacity(.18),
                          blurRadius: 22,
                          offset: const Offset(0, 10))
                    ]),
                child: compact
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [copy, const SizedBox(height: 8), visual])
                    : Row(children: [
                        Expanded(child: copy),
                        const SizedBox(width: 24),
                        visual
                      ]));
          }));
}

class HomeScreen extends StatefulWidget {
  const HomeScreen(
      {super.key,
      required this.notes,
      required this.onCapture,
      required this.onOpen,
      required this.onCaptureInTopic});
  final List<Note> notes;
  final VoidCallback onCapture;
  final ValueChanged<Note> onOpen;
  final ValueChanged<Map<String, dynamic>> onCaptureInTopic;
  @override
  State<HomeScreen> createState() => _HomeState();
}

class _HomeState extends State<HomeScreen> {
  List<Map<String, dynamic>> topics = [];
  @override
  void initState() {
    super.initState();
    _loadTopics();
  }

  Future<void> _loadTopics() async {
    try {
      final value = await AiGateway.topics();
      if (mounted) setState(() => topics = value);
    } catch (_) {}
  }

  Future<void> _newTopic() async {
    final controller = TextEditingController();
    final title = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
                title: const Text('Crear tema o clase'),
                content: TextField(
                    controller: controller,
                    autofocus: true,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                        labelText: 'Nombre del tema',
                        hintText: 'Ej. Historia · Revolución francesa')),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      child: const Text('Cancelar')),
                  FilledButton(
                      onPressed: () =>
                          Navigator.pop(dialogContext, controller.text.trim()),
                      child: const Text('Crear tema'))
                ]));
    controller.dispose();
    if (title == null || title.isEmpty) return;
    try {
      final topic = await AiGateway.createTopic(title);
      await _loadTopics();
      if (mounted) widget.onCaptureInTopic(topic);
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  @override
  Widget build(BuildContext context) => Frame(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('MI ESPACIO DE ESTUDIO',
              style: TextStyle(
                  color: brand, fontWeight: FontWeight.bold, fontSize: 12)),
          SizedBox(height: 6),
          Text('Tu espacio de estudio',
              style: TextStyle(fontSize: 30, fontWeight: FontWeight.bold))
        ]),
        const SizedBox(height: 24),
        StudyHero(onNewTopic: _newTopic, onCapture: widget.onCapture),
        const SizedBox(height: 24),
        Row(children: [
          const Expanded(
              child: Text('Mis temas',
                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold))),
          Text('${topics.length} temas',
              style: const TextStyle(color: muted, fontSize: 13))
        ]),
        const SizedBox(height: 12),
        if (topics.isEmpty)
          Card(
              child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Row(children: [
                    Icon(Icons.folder_open_outlined,
                        color: Theme.of(context).colorScheme.primary, size: 28),
                    const SizedBox(width: 12),
                    const Expanded(
                        child: Text(
                            'Todavía no tienes temas. Usa “Nuevo tema” en el banner para comenzar.'))
                  ])))
        else
          Wrap(
              spacing: 12,
              runSpacing: 12,
              children: topics.map((topic) => _topicCard(topic)).toList()),
        const SizedBox(height: 28),
        Row(children: [
          const Expanded(
              child: Text('Notas recientes',
                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold))),
          Text('${widget.notes.length} capturas',
              style: const TextStyle(color: muted, fontSize: 13))
        ]),
        const SizedBox(height: 12),
        if (widget.notes.isEmpty)
          const Card(
              child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                      'Todavía no tienes capturas. Agrega contenido dentro de un tema o crea una captura independiente.')))
        else
          Wrap(
              spacing: 16,
              runSpacing: 16,
              children: widget.notes
                  .take(6)
                  .map((n) => SizedBox(
                      width: 280,
                      child: NoteTile(note: n, onTap: () => widget.onOpen(n))))
                  .toList()),
      ]));
  Widget _topicCard(Map<String, dynamic> topic) => SizedBox(
      width: 290,
      child: Card(
          child: InkWell(
              onTap: () => widget.onCaptureInTopic(topic),
              borderRadius: BorderRadius.circular(18),
              child: Padding(
                  padding: const EdgeInsets.all(17),
                  child: Row(children: [
                    Icon(Icons.folder_outlined,
                        color: Theme.of(context).colorScheme.primary, size: 28),
                    const SizedBox(width: 13),
                    Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          Text('${topic['title']}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w800)),
                          const SizedBox(height: 4),
                          Text('${topic['note_count'] ?? 0} contenidos',
                              style:
                                  const TextStyle(color: muted, fontSize: 12))
                        ])),
                    Icon(Icons.add_circle_outline,
                        color: Theme.of(context).colorScheme.primary, size: 20)
                  ])))));
}

class NoteTile extends StatelessWidget {
  const NoteTile({super.key, required this.note, required this.onTap});
  final Note note;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Card(
      child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(note.icon, color: brand, size: 30),
                    const SizedBox(height: 12),
                    Text(note.title,
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 7),
                    Text(note.source,
                        style: TextStyle(
                            color: appMutedText(context), fontSize: 13)),
                    const SizedBox(height: 12),
                    Chip(
                        label: Text('Resumen',
                            style: TextStyle(
                                color: Theme.of(context).colorScheme.primary,
                                fontSize: 11)),
                        backgroundColor: appAccentSurface(context),
                        side: BorderSide(color: Theme.of(context).dividerColor))
                  ]))));
}

class LegacyTopicLibraryScreen extends StatefulWidget {
  const LegacyTopicLibraryScreen(
      {super.key,
      required this.onOpen,
      required this.onDelete,
      required this.onCaptureInTopic});
  final ValueChanged<Note> onOpen;
  final ValueChanged<Note> onDelete;
  final ValueChanged<Map<String, dynamic>> onCaptureInTopic;
  @override
  State<LegacyTopicLibraryScreen> createState() => _TopicLibraryState();
}

class _TopicLibraryState extends State<LegacyTopicLibraryScreen> {
  List<Map<String, dynamic>> rows = [];
  List<Map<String, dynamic>> topics = [];
  bool loading = true;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await Future.wait(
          [AiGateway.notes(ownerId: AuthService.user!.id), AiGateway.topics()]);
      if (mounted)
        setState(() {
          rows = data[0];
          topics = data[1];
          loading = false;
        });
    } catch (_) {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _newTopic() async {
    final controller = TextEditingController();
    final title = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
                title: const Text('Nuevo tema o clase'),
                content: TextField(
                    controller: controller,
                    autofocus: true,
                    decoration: const InputDecoration(
                        labelText: 'Nombre del tema',
                        hintText: 'Ej. Biología · Unidad 2')),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancelar')),
                  FilledButton(
                      onPressed: () =>
                          Navigator.pop(context, controller.text.trim()),
                      child: const Text('Crear'))
                ]));
    controller.dispose();
    if (title == null || title.isEmpty) return;
    await AiGateway.createTopic(title);
    await _load();
  }

  Future<void> _editTopic(Map<String, dynamic> topic) async {
    final controller = TextEditingController(text: '${topic['title'] ?? ''}');
    final title = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
                title: const Text('Editar tema'),
                content: TextField(
                    controller: controller,
                    autofocus: true,
                    decoration:
                        const InputDecoration(labelText: 'Nombre del tema')),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancelar')),
                  FilledButton(
                      onPressed: () =>
                          Navigator.pop(context, controller.text.trim()),
                      child: const Text('Guardar'))
                ]));
    controller.dispose();
    if (title == null || title.isEmpty) return;
    await AiGateway.updateTopic(topic['id'] as String, title);
    await _load();
  }

  Future<void> _editNote(Note note) async {
    if (note.id == null) return;
    final controller = TextEditingController(text: note.title);
    final title = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
                title: const Text('Editar nombre de nota'),
                content: TextField(
                    controller: controller,
                    autofocus: true,
                    decoration:
                        const InputDecoration(labelText: 'Nombre de la nota')),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancelar')),
                  FilledButton(
                      onPressed: () =>
                          Navigator.pop(context, controller.text.trim()),
                      child: const Text('Guardar'))
                ]));
    controller.dispose();
    if (title == null || title.isEmpty) return;
    await AiGateway.updateNote(note.id!, title);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const _LibrarySkeleton();
    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final row in rows) {
      final key = (row['topic_title'] as String?)?.trim().isNotEmpty == true
          ? row['topic_title'] as String
          : 'Sin clasificar';
      grouped.putIfAbsent(key, () => []).add(row);
    }
    return Frame(
        title: 'Clases y temas',
        action: FilledButton.icon(
            onPressed: _newTopic,
            icon: const Icon(Icons.add),
            label: const Text('Nuevo tema')),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text(
              'Agrupa audios, imágenes y documentos para que la IA estudie todo el contexto.',
              style: TextStyle(color: muted)),
          const SizedBox(height: 22),
          if (topics.isNotEmpty)
            Wrap(
                spacing: 12,
                runSpacing: 12,
                children: topics.map((topic) => _topicCard(topic)).toList()),
          const SizedBox(height: 28),
          ...grouped.entries.map((entry) => _group(entry.key, entry.value))
        ]));
  }

  Widget _topicCard(Map<String, dynamic> topic) => SizedBox(
      width: 290,
      child: Card(
          child: InkWell(
              onTap: () => widget.onCaptureInTopic(topic),
              borderRadius: BorderRadius.circular(18),
              child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Row(children: [
                    Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                            color: appAccentSurface(context),
                            borderRadius: BorderRadius.circular(13)),
                        child: Icon(Icons.folder_open_outlined,
                            color: Theme.of(context).colorScheme.primary)),
                    const SizedBox(width: 12),
                    Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          Text('${topic['title']}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w700)),
                          const SizedBox(height: 4),
                          Text(
                              '${topic['note_count'] ?? 0} capturas · Agregar contenido',
                              style:
                                  const TextStyle(color: muted, fontSize: 12))
                        ])),
                    IconButton(
                        onPressed: () => _editTopic(topic),
                        tooltip: 'Editar tema',
                        icon: const Icon(Icons.edit_outlined, size: 18))
                  ])))));
  Widget _group(String title, List<Map<String, dynamic>> items) => Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        const SizedBox(height: 10),
        ...items.map((row) {
          final note = Note.fromJson(row);
          return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                  leading: CircleAvatar(
                      backgroundColor: appAccentSurface(context),
                      child: Icon(note.icon,
                          color: Theme.of(context).colorScheme.primary)),
                  title: Text(note.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(note.source),
                  trailing: Wrap(spacing: 0, children: [
                    IconButton(
                        onPressed: () => _editNote(note),
                        icon: const Icon(Icons.edit_outlined),
                        tooltip: 'Editar nombre'),
                    IconButton(
                        onPressed: () => widget.onDelete(note),
                        icon: const Icon(Icons.delete_outline),
                        tooltip: 'Eliminar')
                  ]),
                  onTap: () => widget.onOpen(note)));
        })
      ]));
}

class TopicLibraryScreen extends StatefulWidget {
  const TopicLibraryScreen(
      {super.key,
      required this.onOpen,
      required this.onDelete,
      required this.onCaptureInTopic});
  final ValueChanged<Note> onOpen;
  final ValueChanged<Note> onDelete;
  final ValueChanged<Map<String, dynamic>> onCaptureInTopic;
  @override
  State<TopicLibraryScreen> createState() => _TopicLibraryV2State();
}

class _TopicLibraryV2State extends State<TopicLibraryScreen> {
  final search = TextEditingController();
  List<Map<String, dynamic>> rows = [];
  List<Map<String, dynamic>> topics = [];
  bool loading = true;
  @override
  void initState() {
    super.initState();
    search.addListener(() => setState(() {}));
    _load();
  }

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final data = await Future.wait(
          [AiGateway.notes(ownerId: AuthService.user!.id), AiGateway.topics()]);
      if (mounted)
        setState(() {
          rows = data[0];
          topics = data[1];
          loading = false;
        });
    } catch (_) {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _newTopic() async {
    final controller = TextEditingController();
    final title = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
                title: const Text('Nuevo tema o clase'),
                content: TextField(
                    controller: controller,
                    autofocus: true,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                        labelText: 'Nombre del tema',
                        hintText: 'Ej. Biología · Unidad 2')),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancelar')),
                  FilledButton(
                      onPressed: () =>
                          Navigator.pop(context, controller.text.trim()),
                      child: const Text('Crear'))
                ]));
    controller.dispose();
    if (title == null || title.isEmpty) return;
    await AiGateway.createTopic(title);
    await _load();
  }

  Future<void> _editTopic(Map<String, dynamic> topic) async {
    final controller = TextEditingController(text: '${topic['title'] ?? ''}');
    final title = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
                title: const Text('Editar tema'),
                content: TextField(
                    controller: controller,
                    autofocus: true,
                    decoration:
                        const InputDecoration(labelText: 'Nombre del tema')),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancelar')),
                  FilledButton(
                      onPressed: () =>
                          Navigator.pop(context, controller.text.trim()),
                      child: const Text('Guardar'))
                ]));
    controller.dispose();
    if (title == null || title.isEmpty) return;
    await AiGateway.updateTopic(topic['id'] as String, title);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const _LibrarySkeleton();
    final query = search.text.trim().toLowerCase();
    final visibleTopics = topics
        .where((topic) =>
            query.isEmpty ||
            '${topic['title'] ?? ''}'.toLowerCase().contains(query))
        .toList();
    final visibleRows = rows
        .where((row) =>
            query.isEmpty ||
            '${row['title'] ?? ''} ${row['topic_title'] ?? ''}'
                .toLowerCase()
                .contains(query))
        .toList();
    return Frame(
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
              gradient: LinearGradient(
                  colors: appGradient(context, selectedPalette.value)),
              borderRadius: BorderRadius.circular(22)),
          child: LayoutBuilder(
              builder: (context, constraints) => Flex(
                      direction: constraints.maxWidth < 560
                          ? Axis.vertical
                          : Axis.horizontal,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        constraints.maxWidth < 560
                            ? _libraryIntro(context)
                            : Expanded(child: _libraryIntro(context)),
                        if (constraints.maxWidth < 560)
                          const SizedBox(height: 16),
                        FilledButton.icon(
                            onPressed: _newTopic,
                            icon: const Icon(Icons.create_new_folder_outlined),
                            label: const Text('Nuevo tema')),
                      ]))),
      const SizedBox(height: 16),
      TextField(
          controller: search,
          decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: 'Buscar temas o notas…',
              suffixIcon: search.text.isEmpty
                  ? null
                  : IconButton(
                      onPressed: search.clear, icon: const Icon(Icons.close)),
              filled: true)),
      const SizedBox(height: 22),
      Row(children: [
        Expanded(
            child: Text('Tus temas',
                style: TextStyle(
                    color: appText(context),
                    fontSize: 19,
                    fontWeight: FontWeight.w800))),
        _LibraryCount(value: '${visibleTopics.length}', label: 'temas')
      ]),
      const SizedBox(height: 10),
      if (visibleTopics.isEmpty)
        _LibraryEmpty(onCreate: _newTopic)
      else
        LayoutBuilder(
            builder: (context, constraints) => Wrap(
                spacing: 12,
                runSpacing: 12,
                children: visibleTopics
                    .map((topic) => SizedBox(
                        width:
                            constraints.maxWidth < 620 ? double.infinity : 300,
                        child: _libraryTopic(topic)))
                    .toList())),
      const SizedBox(height: 26),
      Row(children: [
        Expanded(
            child: Text('Notas recientes',
                style: TextStyle(
                    color: appText(context),
                    fontSize: 19,
                    fontWeight: FontWeight.w800))),
        _LibraryCount(value: '${visibleRows.length}', label: 'notas')
      ]),
      const SizedBox(height: 10),
      if (visibleRows.isEmpty)
        const _LibraryNotesEmpty()
      else
        ...visibleRows.take(8).map((row) {
          final note = Note.fromJson(row);
          return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                  leading: CircleAvatar(
                      backgroundColor: appSoftSurface(context),
                      child: Icon(note.icon,
                          color: Theme.of(context).colorScheme.primary,
                          size: 19)),
                  title: Text(note.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: appText(context),
                          fontWeight: FontWeight.w700)),
                  subtitle: Text(note.topicTitle ?? note.source,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  trailing: Icon(Icons.chevron_right,
                      color: Theme.of(context).colorScheme.primary),
                  onTap: () => widget.onOpen(note)));
        }),
    ]));
  }

  Widget _libraryIntro(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('BIBLIOTECA DE ESTUDIO',
            style: TextStyle(
                color: Colors.white70,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.1)),
        const SizedBox(height: 7),
        const Text('Clases y temas',
            style: TextStyle(
                color: Colors.white,
                fontSize: 25,
                fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        Text('${topics.length} temas · ${rows.length} notas organizadas',
            style: const TextStyle(color: Colors.white70))
      ]);
  Widget _libraryTopic(Map<String, dynamic> topic) => Card(
      child: InkWell(
          onTap: () => widget.onCaptureInTopic(topic),
          borderRadius: BorderRadius.circular(18),
          child: Padding(
              padding: const EdgeInsets.all(15),
              child: Row(children: [
                Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                        color: appSoftSurface(context),
                        borderRadius: BorderRadius.circular(12)),
                    child: Icon(Icons.folder_open_outlined,
                        color: Theme.of(context).colorScheme.primary)),
                const SizedBox(width: 12),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text('${topic['title'] ?? 'Sin título'}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: appText(context),
                              fontWeight: FontWeight.w800)),
                      const SizedBox(height: 4),
                      Text(
                          '${topic['note_count'] ?? 0} notas · Añadir contenido',
                          style: const TextStyle(color: muted, fontSize: 12))
                    ])),
                IconButton(
                    onPressed: () => _editTopic(topic),
                    tooltip: 'Editar tema',
                    icon: const Icon(Icons.edit_outlined, size: 18))
              ]))));
}

class _LibraryCount extends StatelessWidget {
  const _LibraryCount({required this.value, required this.label});
  final String value;
  final String label;
  @override
  Widget build(BuildContext context) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
          color: appSoftSurface(context),
          borderRadius: BorderRadius.circular(10)),
      child: Text('$value $label',
          style: TextStyle(
              color: Theme.of(context).colorScheme.primary,
              fontSize: 12,
              fontWeight: FontWeight.w800)));
}

class _LibraryEmpty extends StatelessWidget {
  const _LibraryEmpty({required this.onCreate});
  final VoidCallback onCreate;
  @override
  Widget build(BuildContext context) => Card(
      child: Padding(
          padding: const EdgeInsets.all(22),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.create_new_folder_outlined,
                color: Theme.of(context).colorScheme.primary, size: 28),
            const SizedBox(height: 10),
            Text('Crea tu primer tema',
                style: TextStyle(
                    color: appText(context),
                    fontSize: 17,
                    fontWeight: FontWeight.w800)),
            const SizedBox(height: 5),
            const Text(
                'Organiza cada clase y añade audios, imágenes o documentos en un mismo lugar.',
                style: TextStyle(color: muted, height: 1.35)),
            const SizedBox(height: 14),
            FilledButton.icon(
                onPressed: onCreate,
                icon: const Icon(Icons.add),
                label: const Text('Crear tema'))
          ])));
}

class _LibraryNotesEmpty extends StatelessWidget {
  const _LibraryNotesEmpty();
  @override
  Widget build(BuildContext context) => Card(
      child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(children: [
            Icon(Icons.note_add_outlined,
                color: Theme.of(context).colorScheme.primary, size: 25),
            const SizedBox(width: 12),
            const Expanded(
                child: Text(
                    'Todavía no hay notas que coincidan con la búsqueda.',
                    style: TextStyle(color: muted)))
          ])));
}

class LibraryScreen extends StatelessWidget {
  const LibraryScreen(
      {super.key,
      required this.notes,
      required this.onOpen,
      required this.onDelete});
  final List<Note> notes;
  final ValueChanged<Note> onOpen;
  final ValueChanged<Note> onDelete;
  @override
  Widget build(BuildContext context) => Frame(
      title: 'Notas',
      child: Column(
          children: notes
              .map(
                  (n) => ListTile(title: Text(n.title), onTap: () => onOpen(n)))
              .toList()));
}

class _SpeakerSetupCard extends StatelessWidget {
  const _SpeakerSetupCard(
      {required this.mode,
      required this.count,
      required this.onModeChanged,
      required this.onCountChanged});
  final String mode;
  final int count;
  final ValueChanged<String> onModeChanged;
  final ValueChanged<int> onCountChanged;
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: appSoftSurface(context),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Theme.of(context).dividerColor)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.groups_2_outlined,
                color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 10),
            Expanded(
                child: Text('¿Cuántas personas hablarán?',
                    style: TextStyle(
                        color: appText(context),
                        fontWeight: FontWeight.w800,
                        fontSize: 15)))
          ]),
          const SizedBox(height: 5),
          const Text(
              'Esto ayuda a organizar la transcripción y distinguir las intervenciones.',
              style: TextStyle(color: muted, fontSize: 12, height: 1.35)),
          const SizedBox(height: 13),
          Wrap(spacing: 8, runSpacing: 8, children: [
            ChoiceChip(
                label: const Text('Una persona'),
                avatar: const Icon(Icons.person_outline, size: 18),
                selected: mode == 'single',
                onSelected: (_) => onModeChanged('single')),
            ChoiceChip(
                label: const Text('Varias personas'),
                avatar: const Icon(Icons.groups_outlined, size: 18),
                selected: mode == 'multi',
                onSelected: (_) => onModeChanged('multi')),
            if (mode == 'multi')
              DropdownButton<int>(
                  value: count,
                  borderRadius: BorderRadius.circular(12),
                  items: [
                    for (var value = 2; value <= 8; value++)
                      DropdownMenuItem(
                          value: value, child: Text('$value oradores'))
                  ],
                  onChanged: (value) {
                    if (value != null) onCountChanged(value);
                  }),
          ]),
        ]),
      );
}

class CaptureScreen extends StatefulWidget {
  const CaptureScreen(
      {super.key, required this.onCreated, this.topicId, this.topicTitle});
  final ValueChanged<Note> onCreated;
  final String? topicId;
  final String? topicTitle;
  @override
  State<CaptureScreen> createState() => _CaptureState();
}

class _CaptureState extends State<CaptureScreen> {
  final text = TextEditingController();
  final recorder = AudioRecorder();
  Timer? timer;
  int seconds = 0;
  bool recording = false;
  bool paused = false;
  String speakerMode = 'single';
  int speakerCount = 2;
  @override
  void dispose() {
    timer?.cancel();
    recorder.dispose();
    text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Frame(
        title: widget.topicTitle == null
            ? 'Capturar contenido'
            : 'Agregar a ${widget.topicTitle}',
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Crea una nota desde cualquier fuente.',
              style: TextStyle(color: muted)),
          const SizedBox(height: 22),
          Wrap(spacing: 16, runSpacing: 16, children: [
            _capture(Icons.mic_none, 'Grabar clase o reunion',
                'Transcripcion automatica', () => _record()),
            _capture(Icons.upload_file, 'Subir archivo',
                'Audio, video, imagen, PDF o DOCX', () => _upload()),
            _capture(Icons.link, 'Pegar enlace', 'YouTube o pagina web', _link),
          ]),
          if (!recording)
            _SpeakerSetupCard(
                mode: speakerMode,
                count: speakerCount,
                onModeChanged: (value) => setState(() => speakerMode = value),
                onCountChanged: (value) =>
                    setState(() => speakerCount = value)),
          if (recording)
            Card(
                color: isDarkTheme(context)
                    ? const Color(0xff241d30)
                    : const Color(0xfffff5fb),
                child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(children: [
                      const Icon(Icons.fiber_manual_record, color: Colors.red),
                      const SizedBox(width: 10),
                      Expanded(
                          child: Text(
                              'Grabando ${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}',
                              style: TextStyle(
                                  color: appText(context),
                                  fontWeight: FontWeight.w700))),
                      IconButton(
                          color: appText(context),
                          tooltip: 'Pausar',
                          onPressed: paused
                              ? null
                              : () async {
                                  await recorder.pause();
                                  setState(() => paused = true);
                                },
                          icon: const Icon(Icons.pause)),
                      IconButton(
                          color: appText(context),
                          tooltip: 'Continuar',
                          onPressed: paused
                              ? () async {
                                  await recorder.resume();
                                  setState(() => paused = false);
                                }
                              : null,
                          icon: const Icon(Icons.play_arrow)),
                      IconButton(
                          color: Theme.of(context).colorScheme.primary,
                          tooltip: 'Detener',
                          onPressed: _record,
                          icon: const Icon(Icons.stop))
                    ]))),
          const SizedBox(height: 26),
          Card(
              child: Padding(
                  padding: const EdgeInsets.all(22),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Entrada rapida',
                            style: TextStyle(
                                fontSize: 18, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 12),
                        TextField(
                            controller: text,
                            maxLines: 5,
                            decoration: const InputDecoration(
                                hintText:
                                    'Pega transcripcion, apuntes o texto...',
                                border: OutlineInputBorder())),
                        const SizedBox(height: 12),
                        Align(
                            alignment: Alignment.centerRight,
                            child: FilledButton.icon(
                                onPressed: () {
                                  if (text.text.trim().isNotEmpty)
                                    widget.onCreated(Note('Nota de texto',
                                        'Texto pegado - Ahora', Icons.notes,
                                        content: text.text.trim()));
                                },
                                icon: const Icon(Icons.auto_awesome),
                                label: const Text('Generar nota IA'))),
                      ]))),
        ]),
      );
  Widget _capture(IconData i, String t, String d, VoidCallback f) => SizedBox(
      width: 260,
      child: Card(
          child: InkWell(
              onTap: f,
              borderRadius: BorderRadius.circular(18),
              child: Padding(
                  padding: const EdgeInsets.all(22),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CircleAvatar(
                            backgroundColor: appSoftSurface(context),
                            child: Icon(i,
                                color: Theme.of(context).colorScheme.primary)),
                        const SizedBox(height: 15),
                        Text(t,
                            style: TextStyle(
                                color: appText(context),
                                fontWeight: FontWeight.bold,
                                fontSize: 16)),
                        const SizedBox(height: 7),
                        Text(d,
                            style: const TextStyle(color: muted, fontSize: 13)),
                        const SizedBox(height: 12),
                        Text('Comenzar →',
                            style: TextStyle(
                                color: Theme.of(context).colorScheme.primary,
                                fontWeight: FontWeight.bold))
                      ])))));
  Future<void> _record() async {
    if (!recording) {
      if (!await recorder.hasPermission()) {
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Concede permiso para usar el microfono.')));
        return;
      }
      final dir = kIsWeb ? null : await getTemporaryDirectory();
      final path = kIsWeb
          ? 'lumenote_${DateTime.now().millisecondsSinceEpoch}.wav'
          : '${dir!.path}/lumenote_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await recorder.start(const RecordConfig(), path: path);
      setState(() {
        recording = true;
        paused = false;
        seconds = 0;
      });
      timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!paused && mounted) setState(() => seconds++);
      });
    } else {
      final path = await recorder.stop();
      timer?.cancel();
      setState(() {
        recording = false;
        paused = false;
      });
      if (path != null) {
        final bytes = await readMediaBytes(path);
        if (bytes != null) CaptureMediaRegistry.put(path, bytes, 'audio/m4a');
        widget.onCreated(Note(
            'Nueva grabacion', '$seconds segundos de audio - Ahora', Icons.mic,
            path: path,
            speakerMode: speakerMode,
            speakerCount: speakerMode == 'multi' ? speakerCount : 1));
      }
    }
  }

  Future<void> _upload() async {
    final files =
        await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: [
      'mp3',
      'm4a',
      'wav',
      'aac',
      'mp4',
      'mov',
      'webm',
      'mkv',
      'png',
      'jpg',
      'jpeg',
      'webp',
      'pdf',
      'docx',
      'txt'
    ]);
    if (files.isEmpty) return;
    final file = files.first;
    final ext = file.extension?.toLowerCase() ?? '';
    final video = ['mp4', 'mov', 'webm', 'mkv'].contains(ext);
    final image = ['png', 'jpg', 'jpeg', 'webp'].contains(ext);
    final icon = video
        ? Icons.videocam_outlined
        : image
            ? Icons.image_outlined
            : Icons.description_outlined;
    final audio = ['mp3', 'm4a', 'wav', 'aac', 'webm'].contains(ext);
    final mediaType = video
        ? 'video/$ext'
        : image
            ? 'image/$ext'
            : audio
                ? 'audio/$ext'
                : ext == 'pdf'
                    ? 'application/pdf'
                    : ext == 'docx'
                        ? 'application/vnd.openxmlformats-officedocument.wordprocessingml.document'
                        : 'text/plain';
    final pickedBytes = await file.readAsBytes();
    if (mediaType != null)
      CaptureMediaRegistry.put(file.path ?? file.name, pickedBytes, mediaType);
    widget.onCreated(Note(
        file.name,
        '${video ? 'Video' : image ? 'Imagen' : audio ? 'Audio' : 'Archivo'} importado - Ahora',
        icon,
        path: file.path ?? file.name,
        speakerMode: speakerMode,
        speakerCount: speakerMode == 'multi' ? speakerCount : 1));
  }

  void _link() => widget.onCreated(
      Note('Contenido desde enlace', 'Enlace importado - Ahora', Icons.link));
}

class NoteScreen extends StatefulWidget {
  const NoteScreen({super.key, required this.note});
  final Note note;
  @override
  State<NoteScreen> createState() => _NoteState();
}

class _NoteState extends State<NoteScreen> {
  int tab = 0;
  final input = TextEditingController();
  final messages = <String>[
    'Hola, soy tu tutor IA. Preguntame cualquier cosa sobre esta nota.'
  ];
  String? codexThreadId;
  Map<String, dynamic>? insights;
  bool loadingInsights = true;
  Timer? insightsTimer;
  final audioPlayer = AudioPlayer();
  Uint8List? audioBytes;
  bool audioLoading = false;
  bool audioPlaying = false;
  final names = ['Resumen', 'Transcripcion', 'Chat IA', 'Estudiar'];
  @override
  void initState() {
    super.initState();
    _loadInsights();
  }

  @override
  void dispose() {
    insightsTimer?.cancel();
    input.dispose();
    audioPlayer.dispose();
    super.dispose();
  }

  Future<void> _toggleAudio() async {
    if (audioPlaying) {
      await audioPlayer.pause();
      if (mounted) setState(() => audioPlaying = false);
      return;
    }
    if (widget.note.id == null) return;
    if (mounted) setState(() => audioLoading = true);
    try {
      audioBytes ??= await AiGateway.noteMedia(widget.note.id!);
      await audioPlayer.play(BytesSource(audioBytes!));
      if (mounted)
        setState(() {
          audioPlaying = true;
          audioLoading = false;
        });
      audioPlayer.onPlayerComplete.first.then((_) {
        if (mounted) setState(() => audioPlaying = false);
      });
    } catch (error) {
      if (mounted) {
        setState(() => audioLoading = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  Future<void> _playFrom(double seconds) async {
    if (widget.note.id == null) return;
    if (mounted) setState(() => audioLoading = true);
    try {
      audioBytes ??= await AiGateway.noteMedia(widget.note.id!);
      await audioPlayer.play(BytesSource(audioBytes!),
          position: Duration(milliseconds: (seconds * 1000).round()));
      if (mounted)
        setState(() {
          audioPlaying = true;
          audioLoading = false;
        });
    } catch (error) {
      if (mounted) {
        setState(() => audioLoading = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  Future<void> _loadInsights() async {
    if (widget.note.id == null) {
      if (mounted) setState(() => loadingInsights = false);
      return;
    }
    final value = await AiGateway.noteInsights(widget.note.id!);
    if (!mounted) return;
    setState(() {
      insights = value;
      loadingInsights = value == null;
    });
    final status = value?['status'];
    if (status == 'processing') {
      insightsTimer?.cancel();
      insightsTimer =
          Timer.periodic(const Duration(seconds: 2), (_) => _refreshInsights());
    } else {
      insightsTimer?.cancel();
    }
  }

  Future<void> _refreshInsights() async {
    final id = widget.note.id;
    if (id == null) return;
    final value = await AiGateway.noteInsights(id);
    if (!mounted) return;
    setState(() {
      insights = value;
      loadingInsights = false;
    });
    if (value?['status'] != 'processing') insightsTimer?.cancel();
  }

  @override
  Widget build(BuildContext context) {
    final views = <Widget>[
      CompactSummaryView(insights: insights, loading: loadingInsights),
      CompactTranscriptView(
          insights: insights, loading: loadingInsights, onSeek: _playFrom),
      ChatView(messages: messages, input: input, send: _send),
      CompactStudyView(insights: insights, loading: loadingInsights)
    ];
    return Scaffold(
      appBar: AppBar(title: Text(widget.note.title), actions: [
        IconButton(onPressed: () {}, icon: const Icon(Icons.share_outlined)),
        IconButton(onPressed: () {}, icon: const Icon(Icons.download_outlined))
      ]),
      body: Center(
          child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1000),
              child: Column(children: [
                if (insights?['status'] == 'processing' ||
                    insights?['status'] == 'error')
                  ProcessingBanner(
                      insights: insights,
                      onRetry: widget.note.id == null ? null : _retry),
                if (widget.note.mediaType?.startsWith('audio/') == true)
                  AudioReplayCard(
                      loading: audioLoading,
                      playing: audioPlaying,
                      onPressed: _toggleAudio),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 22),
                  child: Container(
                    height: 64,
                    decoration: BoxDecoration(
                      color: appSoftSurface(context),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Theme.of(context).dividerColor),
                    ),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: names.asMap().entries.map((e) {
                          const icons = [
                            Icons.summarize_outlined,
                            Icons.subject,
                            Icons.psychology_outlined,
                            Icons.school_outlined
                          ];
                          final selected = tab == e.key;
                          return SizedBox(
                            width: 150,
                            height: 64,
                            child: Semantics(
                              button: true,
                              selected: selected,
                              label: e.value,
                              child: InkWell(
                                onTap: () => setState(() => tab = e.key),
                                borderRadius: BorderRadius.circular(14),
                                child: Stack(
                                  alignment: Alignment.bottomCenter,
                                  children: [
                                    Center(
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(icons[e.key],
                                              size: 19,
                                              color: selected
                                                  ? Theme.of(context)
                                                      .colorScheme
                                                      .primary
                                                  : appMutedText(context)),
                                          const SizedBox(width: 8),
                                          Text(e.value,
                                              style: TextStyle(
                                                  color: selected
                                                      ? appText(context)
                                                      : appMutedText(context),
                                                  fontWeight: selected
                                                      ? FontWeight.w800
                                                      : FontWeight.w600)),
                                        ],
                                      ),
                                    ),
                                    AnimatedContainer(
                                      duration:
                                          const Duration(milliseconds: 180),
                                      height: 3,
                                      width: selected ? 62 : 0,
                                      margin: const EdgeInsets.only(bottom: 4),
                                      decoration: BoxDecoration(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .primary,
                                          borderRadius:
                                              BorderRadius.circular(4)),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 18, 22, 22),
                  child: Row(children: [
                    Text(names[tab],
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w800)),
                    const Spacer(),
                    Text('${tab + 1} de ${names.length}',
                        style: const TextStyle(color: muted, fontSize: 12)),
                  ]),
                ),
                Expanded(
                    child: Padding(
                        padding: const EdgeInsets.fromLTRB(22, 0, 22, 22),
                        child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 180),
                            child: KeyedSubtree(
                                key: ValueKey(tab), child: views[tab])))),
              ]))),
    );
  }

  Future<void> _retry() async {
    final id = widget.note.id;
    if (id == null) return;
    try {
      await AiGateway.reprocess(id);
      if (mounted) {
        setState(() => loadingInsights = true);
        _loadInsights();
      }
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _send() async {
    final question = input.text.trim();
    if (question.isEmpty) return;
    setState(() {
      messages.add(question);
      input.clear();
    });
    final codex = await AiGateway.codexChat(
        message: question, threadId: codexThreadId, noteId: widget.note.id);
    codexThreadId = codex?['threadId'] ?? codexThreadId;
    final answer = codex?['answer'] ??
        await AiGateway.chat(message: question, history: messages);
    if (!mounted) return;
    setState(() => messages.add(answer ??
        'Conecta el gateway de IA en Docker para recibir respuestas de ChatGPT.'));
  }
}

class SummaryView extends StatelessWidget {
  const SummaryView({super.key});
  @override
  Widget build(BuildContext context) => const Center(
      child: Text('El resumen aparecerá cuando proceses esta nota.',
          textAlign: TextAlign.center));
}

class TranscriptView extends StatelessWidget {
  const TranscriptView({super.key});
  @override
  Widget build(BuildContext context) => const Center(
      child: Text(
          'La transcripción aparecerá cuando proceses el audio o archivo.',
          textAlign: TextAlign.center));
}

class GeneratedSummaryView extends StatelessWidget {
  const GeneratedSummaryView(
      {super.key, required this.insights, required this.loading});
  final Map<String, dynamic>? insights;
  final bool loading;
  @override
  Widget build(BuildContext context) {
    if (loading) return const _NoteSummarySkeleton();
    final summary = insights?['summary'] as String?;
    final points =
        (insights?['study']?['key_points'] as List?)?.cast<String>() ?? [];
    if ((summary == null || summary.isEmpty) && points.isEmpty)
      return const Center(
          child: Text('La IA todavía está procesando esta nota.',
              textAlign: TextAlign.center));
    return ListView(children: [
      if (summary != null && summary.isNotEmpty)
        Card(
            child: Padding(
                padding: const EdgeInsets.all(22),
                child: Text(summary,
                    style: const TextStyle(fontSize: 20, height: 1.45)))),
      if (points.isNotEmpty) ...[
        const SizedBox(height: 18),
        const Text('Puntos clave',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        ...points.map((point) => ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.check_circle_outline, color: brand),
            title: Text(point)))
      ]
    ]);
  }
}

class AudioReplayCard extends StatelessWidget {
  const AudioReplayCard(
      {super.key,
      required this.loading,
      required this.playing,
      required this.onPressed});
  final bool loading;
  final bool playing;
  final VoidCallback onPressed;
  @override
  Widget build(BuildContext context) => Card(
      margin: const EdgeInsets.only(bottom: 14),
      child: ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          leading: CircleAvatar(
              backgroundColor: appSoftSurface(context),
              child: Icon(playing ? Icons.pause : Icons.play_arrow,
                  color: Theme.of(context).colorScheme.primary)),
          title: Text('Grabación guardada',
              style: TextStyle(
                  color: appText(context), fontWeight: FontWeight.w700)),
          subtitle: Text(
              loading
                  ? 'Cargando audio…'
                  : playing
                      ? 'Reproduciendo audio original'
                      : 'Escuchar nuevamente',
              style: const TextStyle(color: muted)),
          trailing: IconButton(
              onPressed: loading ? null : onPressed,
              tooltip: playing ? 'Pausar audio' : 'Reproducir audio',
              icon: Icon(
                  playing ? Icons.pause_circle_filled : Icons.play_circle_fill,
                  color: Theme.of(context).colorScheme.primary,
                  size: 32))));
}

class GeneratedTranscriptView extends StatelessWidget {
  const GeneratedTranscriptView(
      {super.key, required this.insights, required this.loading});
  final Map<String, dynamic>? insights;
  final bool loading;
  @override
  Widget build(BuildContext context) {
    if (loading) return const _TranscriptSkeleton();
    final text = insights?['source_text'] as String?;
    return SingleChildScrollView(
        child: SelectableText(
            text == null || text.isEmpty
                ? 'El contenido aparecerá cuando la IA termine de procesar la captura.'
                : text,
            style: const TextStyle(fontSize: 16, height: 1.55)));
  }
}

class ChatView extends StatefulWidget {
  const ChatView(
      {super.key,
      required this.messages,
      required this.input,
      required this.send});
  final List<String> messages;
  final TextEditingController input;
  final Future<void> Function() send;
  @override
  State<ChatView> createState() => _ChatViewV2State();
}

class _ChatViewState extends State<ChatView> {
  bool connected = false;
  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final value =
        await AiGateway.codexDeviceStatus() || await AiGateway.codexConnected();
    if (mounted) setState(() => connected = value);
  }

  Future<void> _connect() async {
    final opened = await AiGateway.connectCodex();
    if (!mounted) return;
    if (opened) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'Autoriza tu cuenta en la pestaña de Codex y vuelve aquí.')));
      Future<void>.delayed(const Duration(seconds: 8), _refresh);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(AiGateway.lastCodexError ??
              'No se pudo abrir el acceso de Codex.')));
    }
  }

  @override
  Widget build(BuildContext context) => Column(children: [
        Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
                onPressed: _connect,
                icon: Icon(connected ? Icons.check_circle : Icons.login),
                label: Text(connected ? 'Codex conectado' : 'Conectar Codex'))),
        Expanded(
            child: ListView(
                children: widget.messages
                    .map((x) => Align(
                        alignment: Alignment.centerLeft,
                        child: Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                                color: appSurface(context),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                    color: Theme.of(context).dividerColor)),
                            child: Text(x,
                                style: TextStyle(color: appText(context))))))
                    .toList())),
        Row(children: [
          Expanded(
              child: TextField(
                  controller: widget.input,
                  onSubmitted: (_) => widget.send(),
                  decoration: const InputDecoration(
                      hintText: 'Pregunta a tu nota...',
                      border: OutlineInputBorder()))),
          const SizedBox(width: 8),
          IconButton.filled(
              onPressed: widget.send, icon: const Icon(Icons.send))
        ])
      ]);
}

class GeneratedStudyView extends StatelessWidget {
  const GeneratedStudyView(
      {super.key, required this.insights, required this.loading});
  final Map<String, dynamic>? insights;
  final bool loading;
  @override
  Widget build(BuildContext context) {
    if (loading) return const _GeneratedStudySkeleton();
    final study = insights?['study'] as Map<String, dynamic>? ?? {};
    final cards = (study['flashcards'] as List?) ?? [];
    final quiz = (study['quiz'] as List?) ?? [];
    return ListView(children: [
      const Text('Flashcards',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      const SizedBox(height: 10),
      if (cards.isEmpty)
        const Text('Aún no hay flashcards generadas.')
      else
        ...cards.take(8).map((item) {
          final card = item as Map;
          return Card(
              child: ListTile(
                  title: Text('${card['question'] ?? ''}'),
                  subtitle: Text('${card['answer'] ?? ''}')));
        }),
      const SizedBox(height: 20),
      const Text('Quiz',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      const SizedBox(height: 10),
      if (quiz.isEmpty)
        const Text('Aún no hay preguntas generadas.')
      else
        ...quiz.take(8).map((item) {
          final question = item as Map;
          return Card(
              child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${question['question'] ?? ''}',
                            style:
                                const TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        Text((question['options'] as List?)?.join(' · ') ?? '')
                      ])));
        })
    ]);
  }
}

class ProcessingBanner extends StatelessWidget {
  const ProcessingBanner({super.key, required this.insights, this.onRetry});
  final Map<String, dynamic>? insights;
  final VoidCallback? onRetry;
  @override
  Widget build(BuildContext context) {
    final error = insights?['status'] == 'error';
    final progress = (insights?['progress'] as num?)?.toDouble() ?? 0;
    final raw = insights?['message'] as String?;
    final message = raw?.contains('Reconnecting') == true
        ? 'Codex no responde. Puedes reintentar sin volver a grabar.'
        : raw ??
            (error ? 'No se pudo completar el procesamiento.' : 'Preparando…');
    final accent =
        error ? appErrorText(context) : Theme.of(context).colorScheme.primary;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: error ? appErrorSurface(context) : appAccentSurface(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: error
                ? accent.withValues(alpha: .48)
                : Theme.of(context).dividerColor),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(error ? Icons.error_outline : Icons.auto_awesome, color: accent),
          const SizedBox(width: 10),
          Expanded(
              child: Text(message,
                  style: TextStyle(
                      color: error ? appErrorText(context) : appText(context),
                      fontWeight: FontWeight.w700))),
          Text('${progress.round()}%',
              style: TextStyle(color: accent, fontWeight: FontWeight.bold))
        ]),
        if (!error) ...[
          const SizedBox(height: 10),
          ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                  value: progress / 100,
                  minHeight: 6,
                  color: accent,
                  backgroundColor: appSurface(context)))
        ],
        if (error && onRetry != null)
          Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Reintentar'))),
      ]),
    );
  }
}

class StudyHubScreen extends StatefulWidget {
  const StudyHubScreen({super.key, this.onCreateTopic, this.onCreateNote});
  final VoidCallback? onCreateTopic;
  final VoidCallback? onCreateNote;
  @override
  State<StudyHubScreen> createState() => _StudyHubState();
}

class _StudyHubState extends State<StudyHubScreen> {
  bool loading = true;
  final grouped = <String, Map<String, dynamic>>{};

  Widget _studyArtwork({bool empty = false}) => ValueListenableBuilder<bool>(
      valueListenable: founderSkinEnabled,
      builder: (context, founder, _) => Image.asset(
          founder
              ? empty
                  ? 'assets/branding/kuromi_study_empty.png'
                  : 'assets/branding/kuromi_study_scene.png'
              : empty
                  ? 'assets/branding/study_empty_state.png'
                  : 'assets/branding/study_materials_hero.png',
          fit: BoxFit.contain));

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final rows = await AiGateway.notes(ownerId: AuthService.user!.id);
      for (final row in rows) {
        final insight = await AiGateway.noteInsights(row['id'] as String);
        final study = insight?['study'] as Map<String, dynamic>? ?? {};
        final key = (row['topic_title'] as String?)?.trim().isNotEmpty == true
            ? row['topic_title'] as String
            : 'Sin tema';
        final bucket = grouped.putIfAbsent(
            key,
            () => {
                  'cards': <Map<String, dynamic>>[],
                  'quiz': <Map<String, dynamic>>[]
                });
        for (final card in ((study['flashcards'] as List?) ?? [])) {
          if (card is Map)
            (bucket['cards'] as List<Map<String, dynamic>>)
                .add(Map<String, dynamic>.from(card));
        }
        for (final question in ((study['quiz'] as List?) ?? [])) {
          if (question is Map)
            (bucket['quiz'] as List<Map<String, dynamic>>)
                .add(Map<String, dynamic>.from(question));
        }
      }
    } catch (_) {}
    if (mounted) setState(() => loading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const _StudyHubSkeleton();
    final cardCount = grouped.values
        .fold<int>(0, (sum, item) => sum + (item['cards'] as List).length);
    final quizCount = grouped.values
        .fold<int>(0, (sum, item) => sum + (item['quiz'] as List).length);
    final studyHeroGradient = appHeroGradient(context, selectedPalette.value);
    return Frame(
        title: 'Estudiar',
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: studyHeroGradient),
              borderRadius: BorderRadius.circular(22),
            ),
            child: LayoutBuilder(
                builder: (context, constraints) => Flex(
                      direction: constraints.maxWidth < 560
                          ? Axis.vertical
                          : Axis.horizontal,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        constraints.maxWidth < 560
                            ? _studyIntro(context, true)
                            : Expanded(child: _studyIntro(context, false)),
                        if (constraints.maxWidth < 560) ...[
                          const SizedBox(height: 4),
                          SizedBox(
                              height: 142,
                              width: double.infinity,
                              child: _studyArtwork()),
                          const SizedBox(height: 8),
                        ] else ...[
                          const SizedBox(width: 10),
                          SizedBox(
                              width: 142, height: 142, child: _studyArtwork()),
                          const SizedBox(width: 10),
                        ],
                        Row(children: [
                          _studyStat(context, '$cardCount', 'Tarjetas'),
                          const SizedBox(width: 8),
                          _studyStat(context, '$quizCount', 'Preguntas'),
                          const SizedBox(width: 8),
                          _studyStat(context, '${grouped.length}', 'Temas'),
                        ]),
                      ],
                    )),
          ),
          const SizedBox(height: 22),
          if (grouped.isEmpty)
            Card(
                child: Padding(
                    padding: const EdgeInsets.fromLTRB(22, 20, 22, 22),
                    child: LayoutBuilder(
                        builder: (context, constraints) => Flex(
                                direction: constraints.maxWidth < 560
                                    ? Axis.vertical
                                    : Axis.horizontal,
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  SizedBox(
                                      width: constraints.maxWidth < 560
                                          ? 170
                                          : 190,
                                      height: constraints.maxWidth < 560
                                          ? 145
                                          : 160,
                                      child: _studyArtwork(empty: true)),
                                  SizedBox(
                                      width:
                                          constraints.maxWidth < 560 ? 0 : 22,
                                      height:
                                          constraints.maxWidth < 560 ? 12 : 0),
                                  constraints.maxWidth < 560
                                      ? _emptyStudyCopy(context, true)
                                      : Expanded(
                                          child:
                                              _emptyStudyCopy(context, false)),
                                ]))))
          else ...[
            Text('Temas para estudiar',
                style: TextStyle(
                    color: appText(context),
                    fontSize: 18,
                    fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            ...grouped.entries
                .map((entry) => _topicStudy(entry.key, entry.value)),
          ],
        ]));
  }

  Widget _studyIntro(BuildContext context, bool compact) => Column(
          crossAxisAlignment:
              compact ? CrossAxisAlignment.center : CrossAxisAlignment.start,
          children: [
            Text('Tu espacio de repaso',
                style: TextStyle(
                    color: founderSkinEnabled.value
                        ? (isDarkTheme(context)
                            ? const Color(0xffe6b9e1)
                            : const Color(0xff79518a))
                        : Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text('Estudia a tu ritmo',
                style: TextStyle(
                    color: founderSkinEnabled.value && !isDarkTheme(context)
                        ? const Color(0xff34243b)
                        : Colors.white,
                    fontSize: 25,
                    fontWeight: FontWeight.w800)),
            const SizedBox(height: 7),
            Text('Repasa tarjetas y preguntas creadas desde tus temas.',
                style: TextStyle(
                    color: founderSkinEnabled.value
                        ? (isDarkTheme(context)
                            ? const Color(0xffdfcde7)
                            : const Color(0xff5f4b66))
                        : Colors.white70,
                    height: 1.35)),
          ]);
  Widget _emptyStudyCopy(BuildContext context, bool centered) => Column(
          crossAxisAlignment:
              centered ? CrossAxisAlignment.center : CrossAxisAlignment.start,
          children: [
            Text('Empieza a estudiar',
                textAlign: centered ? TextAlign.center : TextAlign.start,
                style: TextStyle(
                    color: appText(context),
                    fontWeight: FontWeight.w800,
                    fontSize: 20)),
            const SizedBox(height: 7),
            Text(
                'Crea un tema y añade tu primera nota. Cuando se procese, aquí aparecerán tus flashcards y preguntas.',
                textAlign: centered ? TextAlign.center : TextAlign.start,
                style: const TextStyle(color: muted, height: 1.4)),
            const SizedBox(height: 16),
            Wrap(
                alignment:
                    centered ? WrapAlignment.center : WrapAlignment.start,
                spacing: 10,
                runSpacing: 10,
                children: [
                  FilledButton.icon(
                      onPressed: widget.onCreateTopic,
                      icon: const Icon(Icons.create_new_folder_outlined),
                      label: const Text('Crear nuevo tema')),
                  OutlinedButton.icon(
                      onPressed: widget.onCreateNote,
                      icon: const Icon(Icons.add_circle_outline),
                      label: const Text('Añadir nueva nota')),
                ]),
          ]);
  Widget _studyStat(BuildContext context, String value, String label) =>
      Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
          decoration: BoxDecoration(
              color: founderSkinEnabled.value
                  ? (isDarkTheme(context)
                      ? const Color(0xff45304f)
                      : const Color(0xffe9d7f3))
                  : Colors.white.withOpacity(.18),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: founderSkinEnabled.value
                      ? const Color(0xff9b79aa)
                      : Colors.white24)),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(value,
                style: TextStyle(
                    color: founderSkinEnabled.value && !isDarkTheme(context)
                        ? const Color(0xff34243b)
                        : Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w800)),
            Text(label,
                style: TextStyle(
                    color: founderSkinEnabled.value
                        ? (isDarkTheme(context)
                            ? const Color(0xffdfcde7)
                            : const Color(0xff5f4b66))
                        : Colors.white70,
                    fontSize: 10))
          ]));
  Widget _topicStudy(String title, Map<String, dynamic> data) {
    final cards = data['cards'] as List<Map<String, dynamic>>;
    final quiz = data['quiz'] as List<Map<String, dynamic>>;
    final children = <Widget>[];
    if (cards.isNotEmpty) {
      children.add(const Align(
          alignment: Alignment.centerLeft,
          child: Text('Flashcards',
              style: TextStyle(fontWeight: FontWeight.w800))));
      children.add(const SizedBox(height: 8));
      children.addAll(cards.take(10).map((card) => Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
                color: appSoftSurface(context),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Theme.of(context).dividerColor)),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${card['question'] ?? ''}',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 5),
              Text('${card['answer'] ?? ''}',
                  style: TextStyle(color: appMutedText(context), height: 1.35)),
            ]),
          )));
    }
    if (quiz.isNotEmpty) {
      children.add(const SizedBox(height: 8));
      children.add(const Align(
          alignment: Alignment.centerLeft,
          child: Text('Examen del tema',
              style: TextStyle(fontWeight: FontWeight.w800))));
      children.add(const SizedBox(height: 8));
      children.add(_QuizPractice(questions: quiz.take(10).toList()));
    }
    if (children.isEmpty)
      children.add(const Align(
          alignment: Alignment.centerLeft,
          child: Text('Este tema todavía no tiene material generado.',
              style: TextStyle(color: muted))));
    return Card(
        margin: const EdgeInsets.only(bottom: 12),
        child: ExpansionTile(
            initiallyExpanded: true,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            collapsedShape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            leading: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                    color: isDarkTheme(context)
                        ? const Color(0xff302440)
                        : const Color(0xfff0edff),
                    borderRadius: BorderRadius.circular(11)),
                child: Icon(Icons.folder_open_outlined,
                    color: Theme.of(context).colorScheme.primary, size: 20)),
            title: Text(title,
                style: TextStyle(
                    color: appText(context), fontWeight: FontWeight.w800)),
            subtitle: Text(
                '${cards.length} tarjetas · ${quiz.length} preguntas',
                style: const TextStyle(color: muted, fontSize: 12)),
            childrenPadding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
            children: children));
  }
}

class FlashcardScreen extends StatefulWidget {
  const FlashcardScreen({super.key});
  @override
  State<FlashcardScreen> createState() => _FlashState();
}

class _FlashState extends State<FlashcardScreen> {
  bool answer = false;
  int number = 1;
  @override
  Widget build(BuildContext context) => Frame(
        title: 'Flashcards',
        action: FilledButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.auto_awesome),
            label: const Text('Generar con IA')),
        child: Column(children: [
          const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                  'No hay tarjetas todavía. Genera tarjetas desde una nota procesada.',
                  style: TextStyle(color: muted))),
          const SizedBox(height: 25),
          GestureDetector(
              onTap: () => setState(() => answer = !answer),
              child: _cardFace()),
          const SizedBox(height: 20),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            OutlinedButton(onPressed: _next, child: const Text('Dificil')),
            const SizedBox(width: 12),
            FilledButton(onPressed: _next, child: const Text('Lo se'))
          ]),
          const SizedBox(height: 15),
          Text('Tarjeta $number', style: const TextStyle(color: muted)),
        ]),
      );
  Widget _cardFace() {
    return Container(
      height: 260,
      width: double.infinity,
      decoration: BoxDecoration(
          color: appSurface(context),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Theme.of(context).dividerColor)),
      child: const Center(
          child: Padding(
              padding: EdgeInsets.all(25),
              child: Text('Sin tarjetas disponibles',
                  textAlign: TextAlign.center,
                  style:
                      TextStyle(fontSize: 24, fontWeight: FontWeight.bold)))),
    );
  }

  void _next() => setState(() {
        number++;
        answer = false;
      });
}

class QuizScreen extends StatefulWidget {
  const QuizScreen({super.key});
  @override
  State<QuizScreen> createState() => _QuizState();
}

class _QuizState extends State<QuizScreen> {
  int? selected;
  bool checked = false;
  final options = <String>[];
  @override
  Widget build(BuildContext context) {
    final answers = options
        .asMap()
        .entries
        .map((e) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: ListTile(
                tileColor: selected == e.key
                    ? appAccentSurface(context)
                    : appSurface(context),
                textColor: appText(context),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: Theme.of(context).dividerColor)),
                leading: CircleAvatar(
                    backgroundColor: appAccentSurface(context),
                    foregroundColor: Theme.of(context).colorScheme.primary,
                    child: Text(String.fromCharCode(65 + e.key))),
                title: Text(e.value),
                onTap:
                    checked ? null : () => setState(() => selected = e.key))))
        .toList();
    return Frame(
        title: 'Quizzes y examenes',
        action: FilledButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.auto_awesome),
            label: const Text('Nuevo quiz')),
        child: Card(
            child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Sin quizzes disponibles',
                          style: TextStyle(
                              color: brand, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 14),
                      const Text('Genera un quiz después de procesar una nota.',
                          style: TextStyle(
                              fontSize: 21, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 18),
                      ...answers,
                      Align(
                          alignment: Alignment.centerRight,
                          child: FilledButton(
                              onPressed: selected == null
                                  ? null
                                  : () => setState(() => checked = true),
                              child: Text(checked
                                  ? 'Continuar'
                                  : 'Comprobar respuesta'))),
                    ]))));
  }
}

class AppearancePreview extends StatelessWidget {
  const AppearancePreview({super.key});
  @override
  Widget build(BuildContext context) {
    final dark = isDarkTheme(context);
    final founder = founderSkinEnabled.value;
    return Container(
        height: 122,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            gradient: LinearGradient(
                colors: appHeroGradient(context, selectedPalette.value)),
            borderRadius: BorderRadius.circular(16)),
        child: Row(children: [
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                Text(dark ? 'Vista oscura' : 'Vista clara',
                    style: TextStyle(
                        color: founder && !dark ? ink : Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w800)),
                const SizedBox(height: 5),
                Text('Así se verá tu espacio de estudio.',
                    style: TextStyle(
                        color: founder && !dark
                            ? const Color(0xff5f4b66)
                            : Colors.white70,
                        fontSize: 12))
              ])),
          Container(
              width: 132,
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                  color: Theme.of(context).cardColor,
                  borderRadius: BorderRadius.circular(12)),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                        width: 62,
                        height: 7,
                        decoration: BoxDecoration(
                            color: appText(context),
                            borderRadius: BorderRadius.circular(5))),
                    const SizedBox(height: 8),
                    Row(children: [
                      Expanded(
                          child: Container(
                              height: 22,
                              decoration: BoxDecoration(
                                  color: appAccentSurface(context),
                                  borderRadius: BorderRadius.circular(6)))),
                      const SizedBox(width: 6),
                      Container(
                          width: 28,
                          height: 22,
                          decoration: BoxDecoration(
                              color: appAccent.value,
                              borderRadius: BorderRadius.circular(6)))
                    ])
                  ]))
        ]));
  }
}

class ThemeModeControl extends StatelessWidget {
  const ThemeModeControl({super.key});
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<ThemeMode>(
        valueListenable: appThemeMode,
        builder: (context, mode, _) => Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: isDarkTheme(context)
                ? const Color(0xff211c2b)
                : const Color(0xfff3f1f8),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Theme.of(context).dividerColor),
          ),
          child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                _modeOption(
                    context,
                    ThemeMode.system,
                    Icons.brightness_auto_outlined,
                    'Sistema',
                    mode == ThemeMode.system),
                _modeOption(context, ThemeMode.light, Icons.light_mode_outlined,
                    'Claro', mode == ThemeMode.light),
                _modeOption(context, ThemeMode.dark, Icons.dark_mode_outlined,
                    'Oscuro', mode == ThemeMode.dark),
              ])),
        ),
      );
  Widget _modeOption(BuildContext context, ThemeMode target, IconData icon,
          String label, bool selected) =>
      InkWell(
        onTap: () => appThemeMode.value = target,
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: selected
                ? Theme.of(context).colorScheme.primary
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon,
                size: 16,
                color: selected
                    ? Theme.of(context).colorScheme.onPrimary
                    : appText(context)),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(
                    color: selected
                        ? Theme.of(context).colorScheme.onPrimary
                        : appText(context),
                    fontWeight: FontWeight.w700,
                    fontSize: 12)),
          ]),
        ),
      );
}

class _ThemeStudio extends StatefulWidget {
  const _ThemeStudio();
  @override
  State<_ThemeStudio> createState() => _ThemeStudioState();
}

class _ThemeStudioState extends State<_ThemeStudio> {
  final _hex = TextEditingController();
  double _hue = 270;
  double _saturation = .45;
  double _lightness = .62;

  @override
  void initState() {
    super.initState();
    _syncColor();
    appAccent.addListener(_syncColor);
  }

  @override
  void dispose() {
    appAccent.removeListener(_syncColor);
    _hex.dispose();
    super.dispose();
  }

  void _syncColor() {
    final hsl = HSLColor.fromColor(appAccent.value);
    _hue = hsl.hue;
    _saturation = hsl.saturation;
    _lightness = hsl.lightness;
    _hex.text =
        '#${appAccent.value.toARGB32().toRadixString(16).substring(2).toUpperCase()}';
    if (mounted) setState(() {});
  }

  void _applyHsl() => setCustomAccent(HSLColor.fromAHSL(
          1, _hue, _saturation.clamp(.25, 1), _lightness.clamp(.28, .78))
      .toColor());

  void _applyHex(String value) {
    final normalized = value.trim().replaceFirst('#', '');
    if (!RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(normalized)) return;
    setCustomAccent(Color(int.parse('ff$normalized', radix: 16)));
  }

  void _reset() {
    selectedPalette.value = 0;
    customAccentEnabled.value = false;
    appAccent.value = paletteOptions.first.accent;
    appFontFamily.value = 'Quicksand';
    appThemeMode.value = ThemeMode.system;
    unawaited(persistAppearancePreferences());
  }

  Widget _panel(BuildContext context,
          {required String title,
          required String description,
          required Widget child}) =>
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title,
                style: TextStyle(
                    color: appText(context),
                    fontWeight: FontWeight.w800,
                    fontSize: 15)),
            const SizedBox(height: 3),
            Text(description,
                style: TextStyle(color: appMutedText(context), fontSize: 12)),
            const SizedBox(height: 14),
            child,
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _panel(context,
              title: 'Tema y vista previa',
              description: 'Previsualiza los cambios al instante.',
              child: Column(children: [
                const Align(
                    alignment: Alignment.centerLeft, child: ThemeModeControl()),
                const SizedBox(height: 12),
                const AppearancePreview(),
              ])),
          const SizedBox(height: 10),
          _panel(context,
              title: 'Paletas',
              description: 'Elige una base o personaliza tu acento.',
              child: ValueListenableBuilder<int>(
                valueListenable: selectedPalette,
                builder: (context, selected, _) => Wrap(
                  spacing: 9,
                  runSpacing: 9,
                  children: [
                    for (var i = 0; i < paletteOptions.length; i++)
                      _SettingsPalette(
                          index: i,
                          selected: customAccentEnabled.value ? -1 : selected),
                  ],
                ),
              )),
          const SizedBox(height: 10),
          _panel(context,
              title: 'Editor de color',
              description:
                  'Ajusta tono, saturación y luminosidad. El texto de los botones se adapta para mantener contraste.',
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      ValueListenableBuilder<Color>(
                          valueListenable: appAccent,
                          builder: (context, color, _) => Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: color,
                                  borderRadius: BorderRadius.circular(13),
                                  border: Border.all(
                                      color: Theme.of(context).dividerColor),
                                ),
                                child: Icon(Icons.check_rounded,
                                    color: _contrastForeground(color)),
                              )),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _hex,
                          textCapitalization: TextCapitalization.characters,
                          onSubmitted: _applyHex,
                          decoration: const InputDecoration(
                            labelText: 'Código HEX',
                            hintText: '#8F7BD8',
                            prefixIcon: Icon(Icons.tag_rounded),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton(
                          onPressed: () => _applyHex(_hex.text),
                          child: const Text('Aplicar')),
                    ]),
                    const SizedBox(height: 14),
                    _colorSlider(context, 'Tono', _hue, 0, 360,
                        (value) => setState(() => _hue = value), '°'),
                    _colorSlider(context, 'Saturación', _saturation, .25, 1,
                        (value) => setState(() => _saturation = value), '%'),
                    _colorSlider(context, 'Luminosidad', _lightness, .28, .78,
                        (value) => setState(() => _lightness = value), '%'),
                    SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                            onPressed: _applyHsl,
                            icon: const Icon(Icons.color_lens_outlined),
                            label: const Text('Aplicar color personalizado'))),
                  ])),
          const SizedBox(height: 10),
          _panel(context,
              title: 'Tipografía',
              description: 'Se aplica a todas las vistas de la app.',
              child: ValueListenableBuilder<String>(
                valueListenable: appFontFamily,
                builder: (context, selected, _) => Wrap(
                  spacing: 9,
                  runSpacing: 9,
                  children: [
                    _FontChoice(
                        label: 'Quicksand',
                        family: 'Quicksand',
                        selected: selected),
                    _FontChoice(
                        label: 'Sistema', family: '', selected: selected),
                    _FontChoice(
                        label: 'Serif', family: 'serif', selected: selected),
                    _FontChoice(
                        label: 'Monoespaciada',
                        family: 'monospace',
                        selected: selected),
                  ],
                ),
              )),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: _reset,
              icon: const Icon(Icons.restart_alt_rounded, size: 18),
              label: const Text('Restablecer apariencia'),
            ),
          ),
        ],
      );

  Widget _colorSlider(BuildContext context, String label, double value,
      double min, double max, ValueChanged<double> onChanged, String suffix) {
    final display =
        suffix == '°' ? value.round().toString() : '${(value * 100).round()}%';
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(
            child: Text(label,
                style: TextStyle(
                    color: appText(context), fontWeight: FontWeight.w700))),
        Text(display, style: TextStyle(color: appMutedText(context))),
      ]),
      Slider(
        value: value.clamp(min, max),
        min: min,
        max: max,
        activeColor:
            _accessibleAccent(appAccent.value, dark: isDarkTheme(context)),
        onChanged: (next) {
          onChanged(next);
          _applyHsl();
        },
      ),
    ]);
  }
}

class _FontChoice extends StatelessWidget {
  const _FontChoice(
      {required this.label, required this.family, required this.selected});
  final String label;
  final String family;
  final String selected;
  @override
  Widget build(BuildContext context) {
    final active = family == selected;
    return InkWell(
      borderRadius: BorderRadius.circular(13),
      onTap: () {
        appFontFamily.value = family;
        unawaited(persistAppearancePreferences());
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        constraints: const BoxConstraints(minWidth: 130),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color:
              active ? appAccentSurface(context) : Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(13),
          border: Border.all(
              color: active
                  ? _accessibleAccent(appAccent.value,
                      dark: isDarkTheme(context))
                  : Theme.of(context).dividerColor,
              width: active ? 1.5 : 1),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Aa',
              style: TextStyle(
                  fontFamily: family.isEmpty ? null : family,
                  fontSize: 19,
                  color: appText(context),
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 3),
          Row(mainAxisSize: MainAxisSize.min, children: [
            if (active) ...[
              Icon(Icons.check_circle, size: 14, color: appText(context)),
              const SizedBox(width: 5),
            ],
            Text(label,
                style: TextStyle(
                    fontFamily: family.isEmpty ? null : family,
                    color: appText(context),
                    fontSize: 12,
                    fontWeight: FontWeight.w700)),
          ]),
        ]),
      ),
    );
  }
}

class RefactoredSettingsScreen extends StatelessWidget {
  const RefactoredSettingsScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final email = AuthService.user?.email ?? 'Cuenta';
    final initial = email.isEmpty ? 'U' : email.substring(0, 1).toUpperCase();
    return Frame(
      title: 'Perfil y ajustes',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SettingsSection(
            title: 'Perfil',
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 25,
                      backgroundColor:
                          isDarkTheme(context) ? Colors.white : ink,
                      foregroundColor:
                          isDarkTheme(context) ? ink : Colors.white,
                      child: Text(initial,
                          style: const TextStyle(
                              fontSize: 18, fontWeight: FontWeight.w800)),
                    ),
                    const SizedBox(width: 13),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Cuenta personal',
                              style: TextStyle(
                                  color: appText(context),
                                  fontWeight: FontWeight.w800)),
                          const SizedBox(height: 3),
                          Text(email,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style:
                                  const TextStyle(color: muted, fontSize: 13)),
                        ],
                      ),
                    ),
                    const Icon(Icons.verified_user_outlined, color: brand),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 22),
          _SettingsSection(
            title: 'Apariencia',
            description: 'Paleta, gradientes y modo de interfaz.',
            child: const _ThemeStudio(),
          ),
          const SizedBox(height: 22),
          _SettingsSection(
              title: 'Integraciones',
              description: 'Servicios conectados a tu espacio.',
              child: const CodexConnectionCard()),
          const SizedBox(height: 22),
          _SettingsSection(
            title: 'Cuenta y privacidad',
            child: Column(
              children: [
                Card(
                  child: ListTile(
                    leading: Icon(Icons.lock_outline,
                        color: Theme.of(context).colorScheme.primary),
                    title: const Text('Privacidad',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: const Text('Datos y permisos',
                        style: TextStyle(color: muted)),
                    trailing: const Icon(Icons.chevron_right, size: 19),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                      onPressed: () => signOutAndResetBranding(),
                      icon: const Icon(Icons.logout),
                      label: const Text('Cerrar sesión')),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class CompactSettingsScreen extends StatefulWidget {
  const CompactSettingsScreen(
      {super.key, this.onOpenAccount, this.onOpenPrivacy});
  final VoidCallback? onOpenAccount;
  final VoidCallback? onOpenPrivacy;
  @override
  State<CompactSettingsScreen> createState() => _CompactSettingsScreenState();
}

class _CompactSettingsScreenState extends State<CompactSettingsScreen> {
  @override
  Widget build(BuildContext context) {
    final email = AuthService.user?.email ?? 'Cuenta';
    final initial = email.isEmpty ? 'U' : email.substring(0, 1).toUpperCase();
    final avatarUrl = AuthService.user?.userMetadata?['avatar_url'] as String?;
    return Frame(
      title: 'Ajustes',
      child: LayoutBuilder(builder: (context, constraints) {
        final wide = constraints.maxWidth >= 980;
        final profile = _SettingsSection(
          title: 'Cuenta',
          child: Card(
              child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(children: [
                    CircleAvatar(
                        radius: 22,
                        backgroundColor:
                            isDarkTheme(context) ? Colors.white : ink,
                        foregroundColor:
                            isDarkTheme(context) ? ink : Colors.white,
                        backgroundImage:
                            avatarUrl == null ? null : NetworkImage(avatarUrl),
                        child: avatarUrl == null
                            ? Text(initial,
                                style: const TextStyle(
                                    fontSize: 17, fontWeight: FontWeight.w800))
                            : null),
                    const SizedBox(width: 12),
                    Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          Text('Cuenta personal',
                              style: TextStyle(
                                  color: appText(context),
                                  fontWeight: FontWeight.w800)),
                          const SizedBox(height: 3),
                          Text(email,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style:
                                  const TextStyle(color: muted, fontSize: 12))
                        ])),
                    OutlinedButton.icon(
                        onPressed: widget.onOpenAccount,
                        icon: const Icon(Icons.person_outline, size: 17),
                        label: const Text('Ver perfil')),
                  ]))),
        );
        final appearance = _SettingsSection(
          title: 'Apariencia',
          description: 'Tema y color del espacio.',
          child: const _ThemeStudio(),
        );
        final integrations = _SettingsSection(
            title: 'Integraciones',
            description: 'Servicios conectados.',
            child: const CodexConnectionCard());
        final privacy = _SettingsSection(
          title: 'Privacidad',
          child: Card(
              child: Column(children: [
            ListTile(
                onTap: widget.onOpenPrivacy,
                dense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 14),
                leading: Icon(Icons.lock_outline,
                    color: Theme.of(context).colorScheme.primary),
                title: const Text('Datos y permisos',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                trailing: const Icon(Icons.chevron_right, size: 18)),
            Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                child: Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                        onPressed: () => signOutAndResetBranding(),
                        icon: const Icon(Icons.logout, size: 18),
                        label: const Text('Cerrar sesión')))),
          ])),
        );
        return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (wide)
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(child: profile),
                  const SizedBox(width: 16),
                  Expanded(child: integrations)
                ])
              else ...[profile, const SizedBox(height: 16), integrations],
              const SizedBox(height: 18),
              if (wide)
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(child: appearance),
                  const SizedBox(width: 16),
                  Expanded(child: privacy)
                ])
              else ...[appearance, const SizedBox(height: 18), privacy],
            ]);
      }),
    );
  }
}

class FounderAdminScreen extends StatefulWidget {
  const FounderAdminScreen({super.key});
  @override
  State<FounderAdminScreen> createState() => _FounderAdminState();
}

class _FounderAdminState extends State<FounderAdminScreen> {
  bool loading = true;
  String? error;
  List<Map<String, dynamic>> users = [];
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      if (!await AuthService.isFounder())
        throw Exception('Esta vista es exclusiva para una cuenta founder.');
      users = await AiGateway.founderUsers();
    } catch (e) {
      error = e.toString();
    }
    if (mounted) setState(() => loading = false);
  }

  Future<void> _create() async {
    final result = await showDialog<bool>(
        context: context, builder: (_) => const FounderCreateUserDialog());
    if (result == true && mounted) {
      setState(() => loading = true);
      await _load();
    }
  }

  Future<void> _assign(Map<String, dynamic> user) async {
    var plan = '${(user['subscription'] as Map?)?['plan'] ?? 'free'}';
    var status = '${(user['subscription'] as Map?)?['status'] ?? 'active'}';
    final result = await showDialog<bool>(
        context: context,
        builder: (context) => StatefulBuilder(
            builder: (context, setDialogState) => AlertDialog(
                    title: const Text('Asignar membresía'),
                    content: Column(mainAxisSize: MainAxisSize.min, children: [
                      DropdownButtonFormField<String>(
                          value: plan,
                          decoration: const InputDecoration(labelText: 'Plan'),
                          items: const [
                            DropdownMenuItem(
                                value: 'free', child: Text('Gratis')),
                            DropdownMenuItem(
                                value: 'plus', child: Text('Plus')),
                            DropdownMenuItem(value: 'pro', child: Text('Pro'))
                          ],
                          onChanged: (value) =>
                              setDialogState(() => plan = value ?? plan)),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                          value: status,
                          decoration:
                              const InputDecoration(labelText: 'Estado'),
                          items: const [
                            DropdownMenuItem(
                                value: 'active', child: Text('Activo')),
                            DropdownMenuItem(
                                value: 'paused', child: Text('Pausado')),
                            DropdownMenuItem(
                                value: 'cancelled', child: Text('Cancelado'))
                          ],
                          onChanged: (value) =>
                              setDialogState(() => status = value ?? status))
                    ]),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Cancelar')),
                      FilledButton(
                          onPressed: () async {
                            await AiGateway.founderAssignMembership(
                                userId: user['id'] as String,
                                plan: plan,
                                status: status);
                            if (context.mounted) Navigator.pop(context, true);
                          },
                          child: const Text('Guardar'))
                    ])));
    if (result == true && mounted) {
      setState(() => loading = true);
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const _FounderPanelSkeleton();
    if (error != null)
      return Frame(
          title: 'Founder',
          child: Card(
              child: Padding(
                  padding: const EdgeInsets.all(22),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.lock_outline,
                            color: Colors.red, size: 30),
                        const SizedBox(height: 10),
                        Text(error!, style: const TextStyle(color: muted)),
                        const SizedBox(height: 14),
                        OutlinedButton.icon(
                            onPressed: () {
                              setState(() {
                                loading = true;
                                error = null;
                              });
                              _load();
                            },
                            icon: const Icon(Icons.refresh),
                            label: const Text('Reintentar'))
                      ]))));
    return Frame(
        title: 'Founder',
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text('Gestión de cuentas',
                      style: TextStyle(
                          color: appText(context),
                          fontSize: 22,
                          fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  const Text('Crea perfiles y asigna membresías manualmente.',
                      style: TextStyle(color: muted, fontSize: 13))
                ])),
            FilledButton.icon(
                onPressed: _create,
                icon: const Icon(Icons.person_add_alt_1_outlined, size: 18),
                label: const Text('Nuevo perfil'))
          ]),
          const SizedBox(height: 18),
          if (users.isEmpty)
            const _CompactEmpty(
                icon: Icons.group_outlined,
                title: 'Sin perfiles',
                detail: 'Crea el primer perfil desde el panel founder.')
          else
            ...users.map((user) =>
                _FounderUserCard(user: user, onAssign: () => _assign(user))),
        ]));
  }
}

class _FounderUserCard extends StatelessWidget {
  const _FounderUserCard({required this.user, required this.onAssign});
  final Map<String, dynamic> user;
  final VoidCallback onAssign;
  @override
  Widget build(BuildContext context) {
    final subscription = user['subscription'] as Map?;
    final plan = '${subscription?['plan'] ?? 'free'}';
    final status = '${subscription?['status'] ?? 'active'}';
    final name = '${user['display_name'] ?? 'Sin nombre'}';
    return Card(
        margin: const EdgeInsets.only(bottom: 10),
        child: ListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            leading: CircleAvatar(
                backgroundColor: appSoftSurface(context),
                child: Text(
                    name.isEmpty ? 'U' : name.substring(0, 1).toUpperCase(),
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.w800))),
            title:
                Text(name, style: const TextStyle(fontWeight: FontWeight.w800)),
            subtitle: Text('$plan · $status',
                style: const TextStyle(color: muted, fontSize: 12)),
            trailing: OutlinedButton(
                onPressed: onAssign, child: const Text('Membresía'))));
  }
}

class FounderCreateUserDialog extends StatefulWidget {
  const FounderCreateUserDialog({super.key});
  @override
  State<FounderCreateUserDialog> createState() => _FounderCreateUserState();
}

class _FounderCreateUserState extends State<FounderCreateUserDialog> {
  final name = TextEditingController();
  final nickname = TextEditingController();
  final email = TextEditingController();
  final password = TextEditingController();
  String plan = 'free';
  String role = 'user';
  bool saving = false;
  String? error;
  @override
  void dispose() {
    name.dispose();
    nickname.dispose();
    email.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (name.text.trim().isEmpty ||
        email.text.trim().isEmpty ||
        password.text.length < 6) {
      setState(() =>
          error = 'Completa nombre, correo y una contraseña de 6 caracteres.');
      return;
    }
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await AiGateway.founderCreateUser(
          name: name.text,
          nickname: nickname.text,
          email: email.text,
          password: password.text,
          plan: plan,
          role: role);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted)
        setState(() {
          saving = false;
          error = e.toString();
        });
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
          title: const Text('Crear perfil'),
          content: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
                controller: name,
                decoration:
                    const InputDecoration(labelText: 'Nombre completo')),
            const SizedBox(height: 10),
            TextField(
                controller: nickname,
                decoration:
                    const InputDecoration(labelText: 'Apodo o marca interna')),
            const SizedBox(height: 10),
            TextField(
                controller: email,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'Correo')),
            const SizedBox(height: 10),
            TextField(
                controller: password,
                obscureText: true,
                decoration:
                    const InputDecoration(labelText: 'Contraseña temporal')),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
                value: role,
                decoration: const InputDecoration(labelText: 'Rol'),
                items: const [
                  DropdownMenuItem(value: 'user', child: Text('Usuario')),
                  DropdownMenuItem(value: 'founder', child: Text('Founder'))
                ],
                onChanged: saving
                    ? null
                    : (value) => setState(() => role = value ?? role)),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
                value: plan,
                decoration:
                    const InputDecoration(labelText: 'Membresía inicial'),
                items: const [
                  DropdownMenuItem(value: 'free', child: Text('Gratis')),
                  DropdownMenuItem(value: 'plus', child: Text('Plus')),
                  DropdownMenuItem(value: 'pro', child: Text('Pro'))
                ],
                onChanged: saving
                    ? null
                    : (value) => setState(() => plan = value ?? plan)),
            if (error != null)
              Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(error!,
                      style: const TextStyle(color: Colors.red, fontSize: 12)))
          ])),
          actions: [
            TextButton(
                onPressed: saving ? null : () => Navigator.pop(context),
                child: const Text('Cancelar')),
            FilledButton(
                onPressed: saving ? null : _save,
                child: Text(saving ? 'Creando…' : 'Crear perfil'))
          ]);
}

class PrivacyDataScreen extends StatefulWidget {
  const PrivacyDataScreen({super.key});
  @override
  State<PrivacyDataScreen> createState() => _PrivacyDataState();
}

class _PrivacyDataState extends State<PrivacyDataScreen> {
  bool aiEnabled = true;
  bool loading = true;
  bool working = false;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      aiEnabled = await AuthService.aiProcessingEnabled();
    } catch (_) {}
    if (mounted) setState(() => loading = false);
  }

  Future<void> _toggle(bool value) async {
    setState(() => aiEnabled = value);
    try {
      await AuthService.setAiProcessingEnabled(value);
    } catch (error) {
      if (mounted) {
        setState(() => aiEnabled = !value);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('No se pudo guardar la preferencia: $error')));
      }
    }
  }

  Future<void> _export() async {
    setState(() => working = true);
    try {
      final json = await AuthService.exportUserData();
      await Clipboard.setData(ClipboardData(text: json));
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'Tus datos fueron preparados y copiados al portapapeles.')));
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) setState(() => working = false);
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
                title: const Text('Eliminar mis datos'),
                content: const Text(
                    'Se eliminarán notas, conversaciones, tarjetas, quizzes, suscripción y perfil. Esta acción no se puede deshacer.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancelar')),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Eliminar datos'))
                ]));
    if (confirmed != true) return;
    setState(() => working = true);
    try {
      await AuthService.deleteUserData();
      await signOutAndResetBranding();
    } catch (error) {
      if (mounted) {
        setState(() => working = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('No se pudieron eliminar todos los datos: $error')));
      }
    }
  }

  @override
  Widget build(BuildContext context) => Frame(
      title: 'Privacidad y datos',
      child: loading
          ? const _PrivacySkeleton()
          : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              _PrivacyIntro(),
              const SizedBox(height: 16),
              Card(
                  child: SwitchListTile(
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 4),
                      value: aiEnabled,
                      onChanged: working ? null : _toggle,
                      secondary: Icon(Icons.auto_awesome_outlined,
                          color: Theme.of(context).colorScheme.primary),
                      title: const Text('Procesamiento con IA',
                          style: TextStyle(fontWeight: FontWeight.w800)),
                      subtitle: const Text(
                          'Permite que Lumenote analice tus audios, imágenes y documentos para crear resúmenes y material de estudio.',
                          style: TextStyle(
                              color: muted, fontSize: 12, height: 1.35)))),
              const SizedBox(height: 12),
              Card(
                  child: Column(children: [
                const ListTile(
                    leading: Icon(Icons.storage_outlined),
                    title: Text('Datos almacenados',
                        style: TextStyle(fontWeight: FontWeight.w800)),
                    subtitle: Text(
                        'Perfil, notas, transcripciones, chats y material de estudio.',
                        style: TextStyle(color: muted, fontSize: 12))),
                const Divider(height: 1),
                ListTile(
                    leading: Icon(Icons.download_outlined,
                        color: Theme.of(context).colorScheme.primary),
                    title: const Text('Exportar mis datos',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: const Text(
                        'Copia un JSON con tu información disponible.',
                        style: TextStyle(color: muted, fontSize: 12)),
                    trailing: working
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.chevron_right),
                    onTap: working ? null : _export)
              ])),
              const SizedBox(height: 12),
              Card(
                  child: Column(children: [
                ListTile(
                    leading:
                        const Icon(Icons.delete_outline, color: Colors.red),
                    title: const Text('Eliminar mis datos',
                        style: TextStyle(
                            color: Colors.red, fontWeight: FontWeight.w800)),
                    subtitle: const Text(
                        'Borra el contenido de tu espacio, sin borrar tu cuenta de autenticación.',
                        style: TextStyle(color: muted, fontSize: 12)),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: working ? null : _delete)
              ])),
            ]));
}

class _PrivacyIntro extends StatelessWidget {
  const _PrivacyIntro();
  @override
  Widget build(BuildContext context) => Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
          color: appSoftSurface(context),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Theme.of(context).dividerColor)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.shield_outlined,
            color: Theme.of(context).colorScheme.primary, size: 26),
        const SizedBox(width: 12),
        const Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Tú controlas tus datos',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          SizedBox(height: 5),
          Text(
              'Gestiona qué procesa la IA, exporta tu información o elimina el contenido de tu espacio.',
              style: TextStyle(color: muted, height: 1.4, fontSize: 13))
        ]))
      ]));
}

class AccountMembershipScreen extends StatefulWidget {
  const AccountMembershipScreen(
      {super.key, this.onOpenPrivacy, this.onOpenFounder});
  final VoidCallback? onOpenPrivacy;
  final VoidCallback? onOpenFounder;
  @override
  State<AccountMembershipScreen> createState() => _AccountMembershipState();
}

class _AccountMembershipState extends State<AccountMembershipScreen> {
  late Future<Map<String, dynamic>?> membership;
  bool founder = false;
  String? membershipValue;
  @override
  void initState() {
    super.initState();
    membership = AuthService.subscription();
    AuthService.isFounder().then((value) {
      if (mounted) setState(() => founder = value);
    });
  }

  @override
  Widget build(BuildContext context) {
    final user = AuthService.user;
    final email = user?.email ?? 'Cuenta';
    final name = user?.userMetadata?['display_name'] as String? ??
        user?.userMetadata?['full_name'] as String? ??
        email.split('@').first;
    final avatar = user?.userMetadata?['avatar_url'] as String?;
    return Frame(
        title: 'Mi cuenta',
        child: FutureBuilder<Map<String, dynamic>?>(
            future: membership,
            builder: (context, snapshot) {
              final data = snapshot.data ?? const <String, dynamic>{};
              final plan = '${data['plan'] ?? 'free'}'.toUpperCase();
              membershipValue = plan;
              final storedUsed = (data['minutes_used'] as num?)?.toInt() ?? 0;
              final usagePeriod = data['usage_period_start']?.toString();
              final utcMonth = DateTime.now().toUtc().toIso8601String().substring(0, 7);
              final used = usagePeriod == null || usagePeriod.startsWith(utcMonth)
                  ? storedUsed
                  : 0;
              final limit = (data['minutes_limit'] as num?)?.toInt() ?? 60;
              final progress =
                  limit <= 0 ? 0.0 : (used / limit).clamp(0.0, 1.0);
              final renewal = data['current_period_end']?.toString();
              return LayoutBuilder(builder: (context, constraints) {
                final wide = constraints.maxWidth >= 900;
                final identity = Card(
                    child: Padding(
                        padding: const EdgeInsets.all(18),
                        child: Row(children: [
                          CircleAvatar(
                              radius: 30,
                              backgroundColor:
                                  isDarkTheme(context) ? Colors.white : ink,
                              foregroundColor:
                                  isDarkTheme(context) ? ink : Colors.white,
                              backgroundImage:
                                  avatar == null ? null : NetworkImage(avatar),
                              child: avatar == null
                                  ? Text(name.substring(0, 1).toUpperCase(),
                                      style: const TextStyle(
                                          fontSize: 22,
                                          fontWeight: FontWeight.w800))
                                  : null),
                          const SizedBox(width: 14),
                          Expanded(
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                Text(name,
                                    style: TextStyle(
                                        color: appText(context),
                                        fontSize: 18,
                                        fontWeight: FontWeight.w800)),
                                const SizedBox(height: 4),
                                Text(email,
                                    style: const TextStyle(
                                        color: muted, fontSize: 13)),
                                const SizedBox(height: 8),
                                _AccountBadge(label: 'Cuenta $plan')
                              ])),
                          IconButton(
                              onPressed: () async {
                                await showDialog<bool>(
                                    context: context,
                                    builder: (_) => const ProfileEditDialog());
                                if (mounted)
                                  setState(() =>
                                      membership = AuthService.subscription());
                              },
                              tooltip: 'Editar perfil',
                              icon: const Icon(Icons.edit_outlined)),
                        ])));
                final planCard = Card(
                    child: Padding(
                        padding: const EdgeInsets.all(18),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(children: [
                                Expanded(
                                    child: Text('Membresía',
                                        style: TextStyle(
                                            color: appText(context),
                                            fontSize: 17,
                                            fontWeight: FontWeight.w800))),
                                _AccountBadge(
                                    label: plan == 'FREE' ? 'Gratuita' : plan)
                              ]),
                              const SizedBox(height: 8),
                              Text(
                                  plan == 'FREE'
                                      ? 'Empieza a organizar tus clases y prueba el flujo completo.'
                                      : 'Tu plan está activo y listo para estudiar.',
                                  style: const TextStyle(
                                      color: muted, height: 1.4)),
                              const SizedBox(height: 14),
                              Wrap(spacing: 8, runSpacing: 8, children: [
                                OutlinedButton.icon(
                                    onPressed: () => _showPlans(context),
                                    icon: const Icon(
                                        Icons.auto_awesome_outlined,
                                        size: 18),
                                    label: const Text('Comparar planes')),
                                if (founder)
                                  FilledButton.icon(
                                      onPressed: widget.onOpenFounder,
                                      icon: const Icon(
                                          Icons.admin_panel_settings_outlined,
                                          size: 18),
                                      label: const Text('Panel founder'))
                              ])
                            ])));
                final usageCard = Card(
                    child: Padding(
                        padding: const EdgeInsets.all(18),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Uso del periodo',
                                  style: TextStyle(
                                      color: appText(context),
                                      fontSize: 17,
                                      fontWeight: FontWeight.w800)),
                              const SizedBox(height: 12),
                              Row(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text('$used',
                                        style: TextStyle(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .primary,
                                            fontSize: 28,
                                            fontWeight: FontWeight.w800)),
                                    const Padding(
                                        padding: EdgeInsets.only(bottom: 4),
                                        child: Text(' min utilizados',
                                            style: TextStyle(
                                                color: muted, fontSize: 12))),
                                    const Spacer(),
                                    Text('$limit min incluidos',
                                        style: const TextStyle(
                                            color: muted, fontSize: 12))
                                  ]),
                              const SizedBox(height: 8),
                              ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: LinearProgressIndicator(
                                      value: progress,
                                      minHeight: 8,
                                      backgroundColor: appSoftSurface(context),
                                      valueColor: AlwaysStoppedAnimation(
                                          Theme.of(context)
                                              .colorScheme
                                              .primary))),
                              if (renewal != null)
                                Padding(
                                    padding: const EdgeInsets.only(top: 10),
                                    child: Text(
                                        'Renovación: ${renewal.split('T').first}',
                                        style: const TextStyle(
                                            color: muted, fontSize: 12)))
                            ])));
                if (snapshot.connectionState == ConnectionState.waiting)
                  return _AccountSkeleton(wide: wide);
                return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      identity,
                      const SizedBox(height: 18),
                      if (wide)
                        Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(child: planCard),
                              const SizedBox(width: 16),
                              Expanded(child: usageCard)
                            ])
                      else ...[planCard, const SizedBox(height: 14), usageCard],
                      const SizedBox(height: 18),
                      _AccountSecurityCard(onOpen: widget.onOpenPrivacy)
                    ]);
              });
            }));
  }

  Future<void> _showPlans(BuildContext context) async {
    final plans = AiGateway.membershipPlans();
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: FutureBuilder<List<Map<String, dynamic>>>(
            future: plans,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Padding(padding: EdgeInsets.all(28), child: Center(child: CircularProgressIndicator()));
              }
              if (snapshot.hasError) return Padding(padding: const EdgeInsets.all(20), child: Text('No se pudieron cargar los planes: ${snapshot.error}'));
              return ConstrainedBox(
                constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .78),
                child: SingleChildScrollView(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Planes de Lumenote', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: appText(context))),
                    const SizedBox(height: 5),
                    const Text('Compara capacidad y herramientas. La compra se habilitará cuando esté listo el checkout seguro.', style: TextStyle(color: muted)),
                    const SizedBox(height: 16),
                    for (final plan in snapshot.data ?? const <Map<String, dynamic>>[]) ...[
                      _PlanOption(
                        name: '${plan['name'] ?? plan['code']}',
                        detail: '${plan['description'] ?? ''} · ${plan['minutes_limit'] ?? 0} min/mes',
                        active: '${plan['code']}' == ((membershipValue ?? 'free').toLowerCase()),
                        price: plan['monthly_price_minor'] == null ? 'Precio por definir' : '${plan['currency'] ?? 'MXN'} ${((plan['monthly_price_minor'] as num) / 100).toStringAsFixed(2)}/mes',
                      ),
                      const SizedBox(height: 8),
                    ],
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: appSoftSurface(context), borderRadius: BorderRadius.circular(12)),
                      child: const Text('Esta pantalla no inicia cobros ni cambia tu membresía. El precio, impuestos, renovación y cancelación se mostrarán antes de activar cualquier pago.', style: TextStyle(color: muted, fontSize: 12, height: 1.4)),
                    ),
                  ]),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Future<void> showPlansLegacy(BuildContext context) async =>
      showModalBottomSheet<void>(
          context: context,
          showDragHandle: true,
          builder: (context) => SafeArea(
              child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                  child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Elige cómo estudiar',
                            style: TextStyle(
                                fontSize: 20, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 6),
                        const Text(
                            'La estructura queda lista para conectar checkout y facturación.',
                            style: TextStyle(color: muted)),
                        const SizedBox(height: 18),
                        _PlanOption(
                            name: 'Gratis',
                            detail: 'Notas y 60 minutos por periodo',
                            active: true),
                        const SizedBox(height: 8),
                        _PlanOption(
                            name: 'Plus',
                            detail: 'Más minutos, IA avanzada y prioridad',
                            active: false)
                      ]))));
}

class _AccountBadge extends StatelessWidget {
  const _AccountBadge({required this.label});
  final String label;
  @override
  Widget build(BuildContext context) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
          color: appSoftSurface(context),
          borderRadius: BorderRadius.circular(20)),
      child: Text(label,
          style: TextStyle(
              color: Theme.of(context).colorScheme.primary,
              fontSize: 11,
              fontWeight: FontWeight.w800)));
}

class _PlanOption extends StatelessWidget {
  const _PlanOption(
      {required this.name, required this.detail, required this.active, this.price});
  final String name;
  final String detail;
  final bool active;
  final String? price;
  @override
  Widget build(BuildContext context) => Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: appSurface(context),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: active
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).dividerColor)),
      child: Row(children: [
        Icon(active ? Icons.check_circle : Icons.lock_outline,
            color: active ? Theme.of(context).colorScheme.primary : muted),
        const SizedBox(width: 10),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(name,
              style: TextStyle(
                  color: appText(context), fontWeight: FontWeight.w800)),
          Text(detail, style: const TextStyle(color: muted, fontSize: 12)),
          if (price != null) ...[
            const SizedBox(height: 4),
            Text(price!, style: TextStyle(color: Theme.of(context).colorScheme.primary, fontSize: 12, fontWeight: FontWeight.w700)),
          ],
        ])),
        if (active) const _AccountBadge(label: 'Actual')
      ]));
}

class _AccountSecurityCard extends StatelessWidget {
  const _AccountSecurityCard({this.onOpen});
  final VoidCallback? onOpen;
  @override
  Widget build(BuildContext context) => Card(
      child: ListTile(
          onTap: onOpen,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          leading: Icon(Icons.shield_outlined,
              color: Theme.of(context).colorScheme.primary),
          title: const Text('Privacidad y datos',
              style: TextStyle(fontWeight: FontWeight.w800)),
          subtitle: const Text(
              'Controla procesamiento IA, exportación y eliminación.',
              style: TextStyle(color: muted, fontSize: 12)),
          trailing: const Icon(Icons.chevron_right, size: 19)));
}

class ProfileEditDialog extends StatefulWidget {
  const ProfileEditDialog({super.key});
  @override
  State<ProfileEditDialog> createState() => _ProfileEditDialogState();
}

class _ProfileEditDialogState extends State<ProfileEditDialog> {
  late final TextEditingController name;
  late final TextEditingController email;
  final password = TextEditingController();
  String language = 'es';
  Uint8List? avatarBytes;
  String avatarExtension = 'jpg';
  String avatarType = 'image/jpeg';
  bool saving = false;
  String? error;

  @override
  void initState() {
    super.initState();
    final current = AuthService.user;
    name = TextEditingController(
        text: current?.userMetadata?['display_name'] as String? ??
            current?.userMetadata?['full_name'] as String? ??
            '');
    email = TextEditingController(text: current?.email ?? '');
    language = (current?.userMetadata?['language'] as String?) ?? 'es';
  }

  @override
  void dispose() {
    name.dispose();
    email.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> _pickAvatar() async {
    final files = await FilePicker.pickFiles(type: FileType.image);
    if (files.isEmpty || !mounted) return;
    final file = files.first;
    final ext = (file.extension ?? 'jpg').toLowerCase();
    final bytes = await file.readAsBytes();
    if (!mounted) return;
    setState(() {
      avatarBytes = bytes;
      avatarExtension = ext;
      avatarType = 'image/${ext == 'jpg' ? 'jpeg' : ext}';
    });
  }

  Future<void> _save() async {
    if (name.text.trim().isEmpty || email.text.trim().isEmpty) {
      setState(() => error = 'Nombre y correo son obligatorios.');
      return;
    }
    if (password.text.isNotEmpty && password.text.length < 6) {
      setState(() => error = 'La contraseña debe tener al menos 6 caracteres.');
      return;
    }
    setState(() {
      saving = true;
      error = null;
    });
    try {
      String? avatarUrl;
      if (avatarBytes != null)
        avatarUrl = await AuthService.uploadAvatar(avatarBytes!,
            extension: avatarExtension, contentType: avatarType);
      final originalEmail = AuthService.user?.email ?? '';
      await AuthService.updateProfile(
          displayName: name.text,
          email: email.text.trim() == originalEmail ? null : email.text,
          avatarUrl: avatarUrl,
          language: language);
      if (password.text.isNotEmpty)
        await AuthService.updatePassword(password.text);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted)
        setState(() {
          saving = false;
          error = e.toString();
        });
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Editar perfil'),
        content: SingleChildScrollView(
            child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 430),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  GestureDetector(
                      onTap: saving ? null : _pickAvatar,
                      child: CircleAvatar(
                          radius: 38,
                          backgroundColor:
                              isDarkTheme(context) ? Colors.white : ink,
                          foregroundColor:
                              isDarkTheme(context) ? ink : Colors.white,
                          backgroundImage: avatarBytes == null
                              ? null
                              : MemoryImage(avatarBytes!),
                          child: avatarBytes == null
                              ? const Icon(Icons.add_a_photo_outlined, size: 25)
                              : null)),
                  const SizedBox(height: 8),
                  const Text('Toca la foto para cambiarla',
                      style: TextStyle(color: muted, fontSize: 12)),
                  const SizedBox(height: 18),
                  TextField(
                      controller: name,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                          labelText: 'Nombre',
                          prefixIcon: Icon(Icons.person_outline))),
                  const SizedBox(height: 12),
                  TextField(
                      controller: email,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                          labelText: 'Correo electrónico',
                          prefixIcon: Icon(Icons.mail_outline))),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                      value: language,
                      decoration: const InputDecoration(
                          labelText: 'Idioma de transcripción',
                          prefixIcon: Icon(Icons.translate_outlined)),
                      items: const [
                        DropdownMenuItem(value: 'es', child: Text('Español')),
                        DropdownMenuItem(value: 'en', child: Text('English')),
                        DropdownMenuItem(value: 'pt', child: Text('Português')),
                        DropdownMenuItem(value: 'fr', child: Text('Français'))
                      ],
                      onChanged: saving
                          ? null
                          : (value) =>
                              setState(() => language = value ?? language)),
                  const SizedBox(height: 12),
                  TextField(
                      controller: password,
                      obscureText: true,
                      decoration: const InputDecoration(
                          labelText: 'Nueva contraseña',
                          hintText: 'Déjala vacía para no cambiarla',
                          prefixIcon: Icon(Icons.lock_outline))),
                  if (error != null) ...[
                    const SizedBox(height: 12),
                    Align(
                        alignment: Alignment.centerLeft,
                        child: Text(error!,
                            style: const TextStyle(
                                color: Colors.red, fontSize: 12)))
                  ],
                ]))),
        actions: [
          TextButton(
              onPressed: saving ? null : () => Navigator.pop(context),
              child: const Text('Cancelar')),
          FilledButton.icon(
              onPressed: saving ? null : _save,
              icon: saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.save_outlined, size: 18),
              label: Text(saving ? 'Guardando' : 'Guardar'))
        ],
      );
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection(
      {required this.title, this.description, required this.child});
  final String title;
  final String? description;
  final Widget child;
  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(title,
            style: TextStyle(
                color: appText(context),
                fontSize: 18,
                fontWeight: FontWeight.w800)),
        if (description != null) ...[
          const SizedBox(height: 4),
          Text(description!, style: const TextStyle(color: muted, fontSize: 13))
        ],
        const SizedBox(height: 10),
        child
      ]);
}

class _SettingsPalette extends StatelessWidget {
  const _SettingsPalette({required this.index, required this.selected});
  final int index;
  final int selected;
  @override
  Widget build(BuildContext context) {
    final palette = paletteOptions[index];
    final labelColor = _contrastForeground(
        Color.lerp(palette.gradient.first, palette.gradient.last, .5)!);
    return InkWell(
        onTap: () => applyPalette(index),
        borderRadius: BorderRadius.circular(13),
        child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            width: 132,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
                gradient: LinearGradient(colors: palette.gradient),
                borderRadius: BorderRadius.circular(13),
                border: Border.all(
                    color: selected == index
                        ? _accessibleAccent(palette.accent,
                            dark: isDarkTheme(context))
                        : Colors.transparent,
                    width: 3)),
            child: Row(children: [
              Icon(
                  selected == index
                      ? Icons.check_circle
                      : Icons.palette_outlined,
                  color: labelColor,
                  size: 17),
              const SizedBox(width: 7),
              Expanded(
                  child: Text(palette.name,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: labelColor,
                          fontWeight: FontWeight.w800,
                          fontSize: 12)))
            ])));
  }
}

class CodexConnectionCard extends StatefulWidget {
  const CodexConnectionCard({super.key});
  @override
  State<CodexConnectionCard> createState() => _CodexConnectionCardState();
}

class _CodexConnectionCardState extends State<CodexConnectionCard> {
  bool connected = false;
  bool loading = true;
  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final value =
        await AiGateway.codexDeviceStatus() || await AiGateway.codexConnected();
    if (mounted)
      setState(() {
        connected = value;
        loading = false;
      });
  }

  Future<void> _connect() async {
    final opened = await AiGateway.connectCodex();
    if (!mounted) return;
    if (opened) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'Autoriza tu cuenta en la pestaña de Codex y vuelve aquí.')));
      Future<void>.delayed(const Duration(seconds: 8), _refresh);
    } else
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(AiGateway.lastCodexError ??
              'No se pudo abrir el acceso de Codex.')));
  }

  @override
  Widget build(BuildContext context) => Card(
      child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(children: [
            Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                    color: isDarkTheme(context)
                        ? Colors.white
                        : const Color(0xfff0edff),
                    borderRadius: BorderRadius.circular(14)),
                padding: const EdgeInsets.all(8),
                child: Image.asset('assets/branding/codex_icon.png',
                    fit: BoxFit.contain)),
            const SizedBox(width: 14),
            const Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text('Codex', style: TextStyle(fontWeight: FontWeight.bold)),
                  SizedBox(height: 4),
                  Text('Conecta tu cuenta para usar el tutor de IA.',
                      style: TextStyle(color: muted, fontSize: 13))
                ])),
            loading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : connected
                    ? const Icon(Icons.check_circle, color: Colors.green)
                    : FilledButton(
                        onPressed: _connect, child: const Text('Conectar')),
          ])));
}

class _ChatViewV2State extends State<ChatView> {
  bool connected = false;
  bool sending = false;
  final scroll = ScrollController();
  final suggestions = const [
    'Resume esta nota',
    '¿Cuáles son los puntos clave?',
    'Explícamelo de forma sencilla'
  ];
  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    final value =
        await AiGateway.codexDeviceStatus() || await AiGateway.codexConnected();
    if (mounted) setState(() => connected = value);
  }

  Future<void> _connect() async {
    final opened = await AiGateway.connectCodex();
    if (!mounted) return;
    if (opened) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'Autoriza tu cuenta en la pestaña de Codex y vuelve aquí.')));
      Future<void>.delayed(const Duration(seconds: 8), _refresh);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(AiGateway.lastCodexError ??
              'No se pudo abrir el acceso de Codex.')));
    }
  }

  Future<void> _send() async {
    if (sending || widget.input.text.trim().isEmpty) return;
    setState(() => sending = true);
    await widget.send();
    if (mounted) {
      setState(() => sending = false);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (scroll.hasClients)
          scroll.animateTo(scroll.position.maxScrollExtent,
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOut);
      });
    }
  }

  void _useSuggestion(String value) {
    widget.input.text = value;
    widget.input.selection = TextSelection.collapsed(offset: value.length);
    _send();
  }

  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 10, 14),
            decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Theme.of(context).dividerColor)),
            child: Row(children: [
              founderSkinEnabled.value
                  ? Image.asset('assets/branding/kuromi_tutor.png',
                      width: MediaQuery.sizeOf(context).width < 560 ? 44 : 54,
                      height: MediaQuery.sizeOf(context).width < 560 ? 44 : 54,
                      fit: BoxFit.contain)
                  : Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                          color: appAccentSurface(context),
                          borderRadius: BorderRadius.circular(13)),
                      child: Icon(Icons.psychology_outlined,
                          color: Theme.of(context).colorScheme.primary)),
              const SizedBox(width: 12),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text('Tutor de esta nota',
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurface,
                            fontWeight: FontWeight.w800,
                            fontSize: 15)),
                    const SizedBox(height: 3),
                    Text(
                        'Pregunta sobre el contenido y recibe respuestas con contexto.',
                        style: TextStyle(
                            color: appMutedText(context), fontSize: 12))
                  ])),
              Icon(connected ? Icons.circle : Icons.circle_outlined,
                  size: 10,
                  color: connected
                      ? const Color(0xff5fd19a)
                      : appMutedText(context)),
              const SizedBox(width: 5),
              if (MediaQuery.sizeOf(context).width >= 460)
                Text(connected ? 'Listo' : 'Sin conectar',
                    style:
                        TextStyle(color: appMutedText(context), fontSize: 12)),
              if (!connected)
                IconButton(
                    onPressed: _connect,
                    tooltip: 'Conectar Codex',
                    icon: const Icon(Icons.login, size: 19))
            ])),
        const SizedBox(height: 12),
        if (widget.messages.length <= 1 && !sending)
          SizedBox(
              height: 38,
              child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: suggestions.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (_, i) => ActionChip(
                      label: Text(suggestions[i]),
                      onPressed: () => _useSuggestion(suggestions[i])))),
        if (widget.messages.length <= 1 && !sending) const SizedBox(height: 8),
        Expanded(
            child: ListView.builder(
                controller: scroll,
                padding: const EdgeInsets.fromLTRB(2, 4, 2, 12),
                itemCount: widget.messages.length + (sending ? 1 : 0),
                itemBuilder: (context, index) {
                  if (sending && index == widget.messages.length)
                    return const _TypingBubble();
                  final isUser = index > 0 && index.isOdd;
                  return _ChatBubble(
                      text: widget.messages[index], isUser: isUser);
                })),
        Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
            decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Theme.of(context).dividerColor),
                boxShadow: const [
                  BoxShadow(
                      color: Color(0x0d4b3a8f),
                      blurRadius: 12,
                      offset: Offset(0, 4))
                ]),
            child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Expanded(
                  child: TextField(
                      controller: widget.input,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.newline,
                      onSubmitted: (_) => _send(),
                      decoration: const InputDecoration(
                          hintText: 'Escribe una pregunta…',
                          hintStyle: TextStyle(color: muted),
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(
                              horizontal: 4, vertical: 8)))),
              const SizedBox(width: 8),
              IconButton.filled(
                  onPressed: sending ? null : _send,
                  tooltip: 'Enviar pregunta',
                  icon: sending
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.arrow_upward_rounded))
            ])),
      ]);
}

class _ChatBubble extends StatelessWidget {
  const _ChatBubble({required this.text, required this.isUser});
  final String text;
  final bool isUser;
  @override
  Widget build(BuildContext context) => Align(
        alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 680),
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
          decoration: BoxDecoration(
            color: isUser
                ? Theme.of(context)
                    .colorScheme
                    .primary
                    .withValues(alpha: isDarkTheme(context) ? .30 : 1)
                : appSurface(context),
            borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(17),
                topRight: const Radius.circular(17),
                bottomLeft: Radius.circular(isUser ? 17 : 5),
                bottomRight: Radius.circular(isUser ? 5 : 17)),
            border: Border.all(
                color: isUser
                    ? Theme.of(context)
                        .colorScheme
                        .primary
                        .withValues(alpha: .55)
                    : Theme.of(context).dividerColor),
          ),
          child: SelectableText(text,
              style: TextStyle(
                  color: appText(context), height: 1.42, fontSize: 14)),
        ),
      );
}

class _TypingDots extends StatefulWidget {
  const _TypingDots({required this.color});
  final Color color;
  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 900))
    ..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => Row(mainAxisSize: MainAxisSize.min, children: [
          for (var i = 0; i < 3; i++) ...[
            if (i > 0) const SizedBox(width: 3),
            Opacity(
              opacity: .35 +
                  .65 *
                      (((_controller.value + i / 3) % 1) < .5
                          ? ((_controller.value + i / 3) % 1) * 2
                          : 2 - ((_controller.value + i / 3) % 1) * 2),
              child: Container(
                width: 5,
                height: 5,
                decoration:
                    BoxDecoration(color: widget.color, shape: BoxShape.circle),
              ),
            ),
          ],
        ]),
      );
}

class _TypingBubble extends StatelessWidget {
  const _TypingBubble();
  @override
  Widget build(BuildContext context) => Align(
      alignment: Alignment.centerLeft,
      child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
          decoration: BoxDecoration(
              color: appAccentSurface(context),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Theme.of(context).dividerColor)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            _TypingDots(color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 10),
            Text('Analizando la nota…',
                style: TextStyle(
                    color: appText(context),
                    fontSize: 13,
                    fontWeight: FontWeight.w600))
          ])));
}

class CompactSummaryView extends StatelessWidget {
  const CompactSummaryView(
      {super.key, required this.insights, required this.loading});
  final Map<String, dynamic>? insights;
  final bool loading;
  Widget _heading(String label) => Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 8),
      child: Text(label,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)));
  @override
  Widget build(BuildContext context) {
    if (loading) return const _NoteSummarySkeleton();
    final summary = insights?['summary'] as String? ?? '';
    final study = insights?['study'] as Map<String, dynamic>? ?? const {};
    final points =
        (study['key_points'] as List?)?.map((item) => '$item').toList() ??
            const <String>[];
    final outline =
        (study['outline'] as List?)?.whereType<Map>().toList() ?? const <Map>[];
    final milestones =
        (study['milestones'] as List?)?.whereType<Map>().toList() ??
            const <Map>[];
    final directives =
        (study['directives'] as List?)?.whereType<Map>().toList() ??
            const <Map>[];
    final references =
        (study['references'] as List?)?.whereType<Map>().toList() ??
            const <Map>[];
    if (summary.isEmpty && points.isEmpty && outline.isEmpty)
      return const _CompactEmpty(
          icon: Icons.summarize_outlined,
          title: 'Aún no hay apuntes',
          detail:
              'Procesa la nota para generar apuntes organizados a partir de lo dicho por el orador.');
    final children = <Widget>[];
    if (summary.isNotEmpty) {
      children.add(Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
              color: ink, borderRadius: BorderRadius.circular(18)),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Row(children: [
              Icon(Icons.auto_stories_outlined,
                  color: Color(0xffc9baff), size: 18),
              SizedBox(width: 8),
              Text('APUNTE DE LA GRABACIÓN',
                  style: TextStyle(
                      color: Color(0xffc9baff),
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.1))
            ]),
            const SizedBox(height: 10),
            Text(summary,
                style: const TextStyle(
                    color: Colors.white, height: 1.5, fontSize: 16))
          ])));
    }
    if (directives.isNotEmpty) {
      children.add(_heading('Indicaciones del orador'));
      children.addAll(directives.map((item) => Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
              color: appSoftSurface(context),
              borderRadius: BorderRadius.circular(13),
              border: Border.all(color: Theme.of(context).dividerColor)),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary,
                    borderRadius: BorderRadius.circular(7)),
                child: Text('${item['time'] ?? '--:--'}',
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.onPrimary,
                        fontWeight: FontWeight.w800,
                        fontSize: 11))),
            const SizedBox(width: 10),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text('${item['instruction'] ?? ''}',
                      style: TextStyle(
                          color: appText(context),
                          fontWeight: FontWeight.w700)),
                  if ('${item['cue'] ?? ''}'.isNotEmpty)
                    Text('Señal: “${item['cue']}”',
                        style: const TextStyle(color: muted, fontSize: 12))
                ]))
          ]))));
    }
    if (points.isNotEmpty) {
      children.add(_heading('Puntos clave'));
      children.addAll(points.asMap().entries.map((entry) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
                width: 24,
                height: 24,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                    color: appSoftSurface(context),
                    borderRadius: BorderRadius.circular(8)),
                child: Text('${entry.key + 1}',
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.bold,
                        fontSize: 12))),
            const SizedBox(width: 10),
            Expanded(
                child: Text(entry.value,
                    style: TextStyle(color: appText(context), height: 1.35)))
          ]))));
    }
    if (outline.isNotEmpty) {
      children.add(_heading('Apuntes por tema'));
      children.addAll(outline.map((item) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: ExpansionTile(
              tilePadding: const EdgeInsets.symmetric(horizontal: 12),
              childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              backgroundColor: appSoftSurface(context),
              collapsedBackgroundColor: appSoftSurface(context),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              collapsedShape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              title: Text('${item['heading'] ?? ''}',
                  style: TextStyle(
                      color: appText(context), fontWeight: FontWeight.w700)),
              children: [
                Align(
                    alignment: Alignment.centerLeft,
                    child: Text('${item['details'] ?? ''}',
                        style: TextStyle(color: appText(context), height: 1.4)))
              ]))));
    }
    if (milestones.isNotEmpty) {
      children.add(_heading('Hitos de la grabación'));
      children.addAll(milestones.map((item) => ListTile(
          contentPadding: EdgeInsets.zero,
          leading: CircleAvatar(
              backgroundColor: appSoftSurface(context),
              child: Text('${item['time'] ?? ''}',
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontSize: 10,
                      fontWeight: FontWeight.w800))),
          title: Text('${item['title'] ?? ''}',
              style: TextStyle(
                  color: appText(context), fontWeight: FontWeight.w700)),
          subtitle: Text('${item['detail'] ?? ''}',
              style: const TextStyle(color: muted)))));
    }
    if (references.isNotEmpty) {
      children.add(_heading('Referencias relacionadas'));
      children.addAll(references.map((item) => Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              onTap: () {
                final uri = Uri.tryParse('${item['url'] ?? ''}');
                if (uri != null)
                  launchUrl(uri, mode: LaunchMode.externalApplication);
              },
              leading: CircleAvatar(
                  backgroundColor: appSoftSurface(context),
                  child: Text('${item['time'] ?? '↗'}',
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                          fontSize: 10,
                          fontWeight: FontWeight.w800))),
              title: Text('${item['title'] ?? ''}',
                  style: TextStyle(
                      color: appText(context), fontWeight: FontWeight.w700)),
              subtitle: Text('${item['connection'] ?? item['source'] ?? ''}',
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: muted)),
              trailing: const Icon(Icons.open_in_new, size: 18),
            ),
          )));
    }
    return ListView(
        padding: const EdgeInsets.only(bottom: 24), children: children);
  }
}

class CompactTranscriptView extends StatelessWidget {
  const CompactTranscriptView(
      {super.key,
      required this.insights,
      required this.loading,
      required this.onSeek});
  final Map<String, dynamic>? insights;
  final bool loading;
  final ValueChanged<double> onSeek;
  String _time(num? seconds) {
    final total = (seconds ?? 0).round();
    final hours = total ~/ 3600;
    final minutes = (total % 3600) ~/ 60;
    final secs = total % 60;
    return hours > 0
        ? '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}'
        : '${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const _TranscriptSkeleton();
    final text =
        (insights?['transcript'] ?? insights?['source_text']) as String? ?? '';
    final segments = (insights?['transcript_segments'] as List?)
            ?.whereType<Map>()
            .toList() ??
        const <Map>[];
    if (text.isEmpty)
      return const _CompactEmpty(
          icon: Icons.subject,
          title: 'Sin transcripción todavía',
          detail:
              'Cuando termine el procesamiento aparecerá aquí el texto completo.');
    final uncertain =
        segments.where((segment) => segment['kind'] == 'uncertain').length;
    final isMultiSpeaker = insights?['speaker_mode'] == 'multi';
    final speakerCount = (insights?['speaker_count'] as num?)?.toInt() ?? 1;
    final topicTitle = insights?['topic_title'] as String? ?? '';
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
              color: appSoftSurface(context),
              borderRadius: BorderRadius.circular(12)),
          child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 6,
              children: [
                const Icon(Icons.schedule_outlined, color: brand, size: 19),
                Text('Transcripción por tiempo',
                    style: TextStyle(
                        color: appText(context), fontWeight: FontWeight.w700)),
                _Pill(
                    label: isMultiSpeaker
                        ? '$speakerCount oradores'
                        : 'Orador principal'),
                _Pill(label: '${segments.length} bloques'),
                if (topicTitle.isNotEmpty) _Pill(label: topicTitle),
                if (uncertain > 0) _Pill(label: '$uncertain por revisar')
              ])),
      const SizedBox(height: 10),
      Expanded(
          child: segments.isEmpty
              ? SingleChildScrollView(
                  child: SelectableText(text,
                      style: TextStyle(
                          color: appText(context), fontSize: 15, height: 1.6)))
              : ListView.separated(
                  padding: const EdgeInsets.only(bottom: 24),
                  itemCount: segments.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final segment = segments[index];
                    final start = (segment['start'] as num?)?.toDouble() ?? 0;
                    final end = (segment['end'] as num?)?.toDouble() ?? start;
                    final isUncertain = segment['kind'] == 'uncertain';
                    final speaker = segment['speaker'] as String?;
                    return InkWell(
                      onTap: () => onSeek(start),
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                              color: isUncertain
                                  ? (isDarkTheme(context)
                                      ? const Color(0xff2c2620)
                                      : const Color(0xfffff8e8))
                                  : appSurface(context),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                  color: isUncertain
                                      ? const Color(0xffd9a441)
                                      : Theme.of(context).dividerColor)),
                          child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 5),
                                    decoration: BoxDecoration(
                                        color: appSoftSurface(context),
                                        borderRadius: BorderRadius.circular(8)),
                                    child: Text(_time(start),
                                        style: TextStyle(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .primary,
                                            fontWeight: FontWeight.w800,
                                            fontSize: 12))),
                                const SizedBox(width: 12),
                                Expanded(
                                    child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                      Row(children: [
                                        Expanded(
                                            child: Text(
                                                speaker ??
                                                    (isUncertain
                                                        ? 'Audio por revisar'
                                                        : 'Contenido hablado'),
                                                style: TextStyle(
                                                    color: appText(context),
                                                    fontWeight: FontWeight.w700,
                                                    fontSize: 12))),
                                        Text('${_time(start)}–${_time(end)}',
                                            style: const TextStyle(
                                                color: muted, fontSize: 11))
                                      ]),
                                      const SizedBox(height: 5),
                                      SelectableText('${segment['text'] ?? ''}',
                                          style: TextStyle(
                                              color: appText(context),
                                              height: 1.45))
                                    ])),
                                const SizedBox(width: 8),
                                Icon(Icons.play_circle_outline,
                                    color:
                                        Theme.of(context).colorScheme.primary),
                              ])),
                    );
                  })),
    ]);
  }
}

class CompactStudyView extends StatelessWidget {
  const CompactStudyView(
      {super.key, required this.insights, required this.loading});
  final Map<String, dynamic>? insights;
  final bool loading;
  @override
  Widget build(BuildContext context) {
    if (loading) return const _GeneratedStudySkeleton();
    final study = insights?['study'] as Map<String, dynamic>? ?? const {};
    final cards = (study['flashcards'] as List?)?.whereType<Map>().toList() ??
        const <Map>[];
    final quiz = (study['quiz'] as List?)
            ?.whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList() ??
        const <Map<String, dynamic>>[];
    if (cards.isEmpty && quiz.isEmpty)
      return const _CompactEmpty(
          icon: Icons.school_outlined,
          title: 'Material en preparación',
          detail:
              'Vuelve a procesar la nota para generar tarjetas y un examen.');
    return ListView(padding: const EdgeInsets.only(bottom: 24), children: [
      Row(children: [
        Expanded(
            child: Text('Entrenamiento del tema',
                style: TextStyle(
                    color: appText(context),
                    fontSize: 18,
                    fontWeight: FontWeight.w800))),
        _Pill(label: '${cards.length} tarjetas'),
        const SizedBox(width: 6),
        _Pill(label: '${quiz.length} preguntas')
      ]),
      if (quiz.isNotEmpty) ...[
        const SizedBox(height: 14),
        _QuizPractice(questions: quiz)
      ],
      if (cards.isNotEmpty) ...[
        const SizedBox(height: 18),
        const Text('Tarjetas de repaso',
            style: TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        ...cards.take(10).map((card) => Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ExpansionTile(
                title: Text('${card['question'] ?? ''}',
                    style: TextStyle(
                        color: appText(context), fontWeight: FontWeight.w700)),
                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                children: [
                  Align(
                      alignment: Alignment.centerLeft,
                      child: Text('${card['answer'] ?? ''}',
                          style:
                              TextStyle(color: appText(context), height: 1.4)))
                ])))
      ],
    ]);
  }
}

class _QuizPractice extends StatefulWidget {
  const _QuizPractice({required this.questions});
  final List<Map<String, dynamic>> questions;
  @override
  State<_QuizPractice> createState() => _QuizPracticeState();
}

class _QuizPracticeState extends State<_QuizPractice> {
  int index = 0;
  int score = 0;
  String? selected;
  bool answered = false;
  bool get finished => index >= widget.questions.length;
  bool _isCorrect(Map<String, dynamic> question, String option) {
    final answer = question['answer'];
    if (answer is num)
      return answer.toInt() ==
          ((question['options'] as List?)?.indexOf(option) ?? -1);
    return '$answer'.trim().toLowerCase() == option.trim().toLowerCase();
  }

  void _answer(String option) {
    if (answered || finished) return;
    final correct = _isCorrect(widget.questions[index], option);
    setState(() {
      selected = option;
      answered = true;
      if (correct) score += 100;
    });
  }

  void _next() => setState(() {
        index++;
        selected = null;
        answered = false;
      });
  void _restart() => setState(() {
        index = 0;
        score = 0;
        selected = null;
        answered = false;
      });
  @override
  Widget build(BuildContext context) {
    if (finished) {
      final maxScore = widget.questions.length * 100;
      final percent = maxScore == 0 ? 0 : ((score / maxScore) * 100).round();
      return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
              gradient: LinearGradient(
                  colors: appGradient(context, selectedPalette.value)),
              borderRadius: BorderRadius.circular(18)),
          child: Column(children: [
            const Icon(Icons.emoji_events_outlined,
                color: Colors.white, size: 38),
            const SizedBox(height: 8),
            Text('$score puntos',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w900)),
            Text(
                '$percent% de comprensión · ${widget.questions.length} preguntas',
                style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 14),
            OutlinedButton.icon(
                onPressed: _restart,
                style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white54)),
                icon: const Icon(Icons.refresh),
                label: const Text('Intentar nuevamente'))
          ]));
    }
    final question = widget.questions[index];
    final options =
        (question['options'] as List?)?.map((item) => '$item').toList() ??
            const <String>[];
    return Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
            color: appSoftSurface(context),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Theme.of(context).dividerColor)),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(
                child: Text(
                    'Pregunta ${index + 1} de ${widget.questions.length}',
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.w800))),
            _Pill(label: '$score pts')
          ]),
          const SizedBox(height: 8),
          LinearProgressIndicator(
              value: (index + 1) / widget.questions.length,
              minHeight: 6,
              borderRadius: BorderRadius.circular(8)),
          const SizedBox(height: 16),
          Text('${question['question'] ?? ''}',
              style: TextStyle(
                  color: appText(context),
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  height: 1.35)),
          const SizedBox(height: 13),
          ...options.map((option) {
            final correct = _isCorrect(question, option);
            final chosen = selected == option;
            final success = isDarkTheme(context)
                ? const Color(0xff75e0ad)
                : const Color(0xff176b49);
            final failure = isDarkTheme(context)
                ? const Color(0xffffb4ab)
                : const Color(0xffb3261e);
            Color? color;
            if (answered && correct) {
              color = success;
            } else if (answered && chosen) {
              color = failure;
            }
            return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: OutlinedButton(
                    onPressed: answered ? null : () => _answer(option),
                    style: OutlinedButton.styleFrom(
                        alignment: Alignment.centerLeft,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 13),
                        foregroundColor: color ?? appText(context),
                        disabledForegroundColor: color ?? appText(context),
                        side: BorderSide(
                            color: color ?? Theme.of(context).dividerColor),
                        backgroundColor: color?.withValues(alpha: .10)),
                    child: Row(children: [
                      Expanded(child: Text(option)),
                      if (answered && correct)
                        Icon(Icons.check_circle, color: success)
                      else if (answered && chosen)
                        Icon(Icons.cancel, color: failure)
                    ])));
          }),
          if (answered) ...[
            const SizedBox(height: 4),
            Text(
                _isCorrect(question, selected ?? '')
                    ? '¡Correcto! +100 puntos'
                    : 'Respuesta correcta: ${question['answer'] ?? ''}',
                style: TextStyle(
                    color: _isCorrect(question, selected ?? '')
                        ? (isDarkTheme(context)
                            ? const Color(0xff75e0ad)
                            : const Color(0xff176b49))
                        : appErrorText(context),
                    fontWeight: FontWeight.w800)),
            if ('${question['explanation'] ?? ''}'.isNotEmpty)
              Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text('${question['explanation']}',
                      style: TextStyle(color: appMutedText(context)))),
            const SizedBox(height: 10),
            Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                    onPressed: _next,
                    icon: const Icon(Icons.arrow_forward),
                    label: Text(index + 1 == widget.questions.length
                        ? 'Ver resultado'
                        : 'Siguiente')))
          ],
        ]));
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label});
  final String label;
  @override
  Widget build(BuildContext context) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
          color: appAccentSurface(context),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Theme.of(context).dividerColor)),
      child: Text(label,
          style: TextStyle(
              color: Theme.of(context).colorScheme.primary,
              fontSize: 11,
              fontWeight: FontWeight.w700)));
}

class _SkeletonBlock extends StatelessWidget {
  const _SkeletonBlock({
    this.width,
    required this.height,
    this.radius = 9,
  });
  final double? width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) => Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: isDarkTheme(context)
              ? (founderSkinEnabled.value
                  ? const Color(0xffe4b5ed).withOpacity(.11)
                  : Colors.white.withOpacity(.09))
              : const Color(0xff252033).withOpacity(.075),
          borderRadius: BorderRadius.circular(radius),
        ),
      );
}

class _SkeletonScope extends StatefulWidget {
  const _SkeletonScope({required this.label, required this.child});
  final String label;
  final Widget child;
  @override
  State<_SkeletonScope> createState() => _SkeletonScopeState();
}

class _SkeletonScopeState extends State<_SkeletonScope>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shimmer;

  @override
  void initState() {
    super.initState();
    _shimmer = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1450))
      ..repeat();
  }

  @override
  void dispose() {
    _shimmer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
        liveRegion: true,
        label: widget.label,
        child: ExcludeSemantics(
          child: AnimatedBuilder(
            animation: _shimmer,
            child: widget.child,
            builder: (context, child) {
              final offset = -1.8 + (_shimmer.value * 3.6);
              return ShaderMask(
                blendMode: BlendMode.srcATop,
                shaderCallback: (bounds) => LinearGradient(
                  begin: Alignment(offset - 1, -.15),
                  end: Alignment(offset + 1, .15),
                  colors: [
                    Colors.transparent,
                    (founderSkinEnabled.value && isDarkTheme(context)
                            ? const Color(0xffe6b9e1)
                            : Colors.white)
                        .withOpacity(isDarkTheme(context) ? .14 : .48),
                    Colors.transparent,
                  ],
                  stops: const [0.38, .5, .62],
                ).createShader(bounds),
                child: child,
              );
            },
          ),
        ),
      );
}

class _LibrarySkeleton extends StatelessWidget {
  const _LibrarySkeleton();

  @override
  Widget build(BuildContext context) => Frame(
        child: _SkeletonScope(
          label: 'Cargando temas y notas',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                const Expanded(child: _SkeletonBlock(height: 26, width: 215)),
                const SizedBox(width: 12),
                _SkeletonBlock(
                    width: MediaQuery.sizeOf(context).width < 560 ? 86 : 116,
                    height: 42,
                    radius: 13),
              ]),
              const SizedBox(height: 12),
              const _SkeletonBlock(width: 310, height: 12),
              const SizedBox(height: 22),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                      colors: appHeroGradient(context, selectedPalette.value)),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const _SkeletonBlock(width: 190, height: 18),
                      const SizedBox(height: 10),
                      const _SkeletonBlock(width: 270, height: 12),
                      const SizedBox(height: 18),
                      const _SkeletonBlock(width: 132, height: 36, radius: 12),
                    ]),
              ),
              const SizedBox(height: 18),
              const _SkeletonBlock(height: 48, radius: 14),
              const SizedBox(height: 22),
              Row(children: [
                const Expanded(child: _SkeletonBlock(width: 110, height: 19)),
                const SizedBox(width: 10),
                _SkeletonBlock(width: 68, height: 27, radius: 14),
              ]),
              const SizedBox(height: 11),
              LayoutBuilder(builder: (context, constraints) {
                final wide = constraints.maxWidth > 650;
                final cards = List.generate(
                    wide ? 2 : 1,
                    (_) => Expanded(
                          child: Container(
                            padding: const EdgeInsets.all(15),
                            decoration: BoxDecoration(
                              color: Theme.of(context).cardColor,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                  color: Theme.of(context).dividerColor),
                            ),
                            child: Row(children: [
                              const _SkeletonBlock(
                                  width: 42, height: 42, radius: 13),
                              const SizedBox(width: 12),
                              Expanded(
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                    const _SkeletonBlock(height: 13),
                                    const SizedBox(height: 8),
                                    _SkeletonBlock(
                                        width: wide ? 145 : 185, height: 10),
                                  ])),
                            ]),
                          ),
                        ));
                return Row(children: [
                  cards.first,
                  if (wide) ...[const SizedBox(width: 12), cards.last],
                ]);
              }),
              const SizedBox(height: 26),
              const _SkeletonBlock(width: 150, height: 19),
              const SizedBox(height: 12),
              const _SkeletonRow(),
              const SizedBox(height: 9),
              const _SkeletonRow(),
            ],
          ),
        ),
      );
}

class _SkeletonRow extends StatelessWidget {
  const _SkeletonRow({this.leading = true});
  final bool leading;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Theme.of(context).dividerColor),
        ),
        child: Row(children: [
          if (leading) ...[
            const _SkeletonBlock(width: 38, height: 38, radius: 12),
            const SizedBox(width: 12),
          ],
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                const _SkeletonBlock(width: 185, height: 12),
                const SizedBox(height: 8),
                _SkeletonBlock(
                    width: MediaQuery.sizeOf(context).width < 600 ? 205 : 340,
                    height: 9),
              ])),
        ]),
      );
}

class _StudyHubSkeleton extends StatelessWidget {
  const _StudyHubSkeleton();
  @override
  Widget build(BuildContext context) => Frame(
        title: 'Estudiar',
        child: _SkeletonScope(
          label: 'Preparando tarjetas y preguntas de estudio',
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                    colors: appHeroGradient(context, selectedPalette.value)),
                borderRadius: BorderRadius.circular(20),
              ),
              child: LayoutBuilder(builder: (context, constraints) {
                // The skeleton reserves room for its stat tiles as well as
                // the intro and illustration; switch to stacked layout sooner
                // than the live view to prevent tablet-width overflow.
                final compact = constraints.maxWidth < 760;
                final intro = Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const _SkeletonBlock(width: 120, height: 11),
                      const SizedBox(height: 10),
                      _SkeletonBlock(width: compact ? 210 : 265, height: 22),
                      const SizedBox(height: 9),
                      _SkeletonBlock(width: compact ? 250 : 310, height: 11),
                    ]);
                final stats = Row(children: [
                  for (var i = 0; i < 3; i++) ...[
                    if (i > 0) const SizedBox(width: 8),
                    Container(
                      width: 69,
                      height: 48,
                      decoration: BoxDecoration(
                          color: founderSkinEnabled.value
                              ? appAccentSurface(context)
                              : Colors.white.withOpacity(.17),
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ]
                ]);
                if (compact) {
                  return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        intro,
                        const SizedBox(height: 18),
                        const _SkeletonBlock(
                            width: 130, height: 110, radius: 18),
                        const SizedBox(height: 14),
                        stats,
                      ]);
                }
                return Row(children: [
                  Expanded(child: intro),
                  const SizedBox(width: 18),
                  const _SkeletonBlock(width: 130, height: 130, radius: 18),
                  const SizedBox(width: 15),
                  stats,
                ]);
              }),
            ),
            const SizedBox(height: 20),
            const _SkeletonBlock(width: 180, height: 20),
            const SizedBox(height: 12),
            const _SkeletonRow(),
            const SizedBox(height: 10),
            const _SkeletonRow(),
          ]),
        ),
      );
}

class _NoteSummarySkeleton extends StatelessWidget {
  const _NoteSummarySkeleton();
  @override
  Widget build(BuildContext context) => _SkeletonScope(
        label: 'Preparando el resumen de la nota',
        child: ListView(padding: EdgeInsets.zero, children: [
          Container(
            height: 105,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(17),
              border: Border.all(color: Theme.of(context).dividerColor),
            ),
            child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _SkeletonBlock(width: 180, height: 15),
                  SizedBox(height: 12),
                  _SkeletonBlock(height: 10),
                  SizedBox(height: 8),
                  _SkeletonBlock(width: 250, height: 10),
                ]),
          ),
          const SizedBox(height: 18),
          const _SkeletonBlock(width: 120, height: 17),
          const SizedBox(height: 10),
          const _SkeletonRow(),
          const SizedBox(height: 8),
          const _SkeletonRow(),
          const SizedBox(height: 8),
          const _SkeletonRow(),
        ]),
      );
}

class _TranscriptSkeleton extends StatelessWidget {
  const _TranscriptSkeleton();
  @override
  Widget build(BuildContext context) => _SkeletonScope(
        label: 'Preparando la transcripción con marcas de tiempo',
        child: ListView.separated(
          padding: const EdgeInsets.symmetric(vertical: 4),
          itemCount: 7,
          separatorBuilder: (_, __) => const SizedBox(height: 13),
          itemBuilder: (context, index) => Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 23,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: appAccentSurface(context),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: const _SkeletonBlock(width: 30, height: 8, radius: 4),
              ),
              const SizedBox(width: 13),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    _SkeletonBlock(
                        width: index % 3 == 0 ? 205 : null,
                        height: 11,
                        radius: 6),
                    const SizedBox(height: 7),
                    _SkeletonBlock(
                        width: index % 2 == 0 ? 260 : 190,
                        height: 10,
                        radius: 6),
                  ])),
            ],
          ),
        ),
      );
}

class _GeneratedStudySkeleton extends StatelessWidget {
  const _GeneratedStudySkeleton();
  @override
  Widget build(BuildContext context) => _SkeletonScope(
        label: 'Preparando flashcards y preguntas',
        child: ListView(children: [
          Container(
            height: 142,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: appAccentSurface(context),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Theme.of(context).dividerColor),
            ),
            child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _SkeletonBlock(width: 120, height: 11),
                  _SkeletonBlock(width: 260, height: 18),
                  _SkeletonBlock(width: 190, height: 12),
                ]),
          ),
          const SizedBox(height: 18),
          const _SkeletonBlock(width: 155, height: 17),
          const SizedBox(height: 10),
          const _SkeletonRow(leading: false),
          const SizedBox(height: 8),
          const _SkeletonRow(leading: false),
          const SizedBox(height: 20),
          const _SkeletonBlock(width: 115, height: 17),
          const SizedBox(height: 10),
          for (var i = 0; i < 3; i++) ...[
            const _SkeletonRow(),
            if (i < 2) const SizedBox(height: 8),
          ],
        ]),
      );
}

class _FounderPanelSkeleton extends StatelessWidget {
  const _FounderPanelSkeleton();
  @override
  Widget build(BuildContext context) => Frame(
        title: 'Founder',
        child: _SkeletonScope(
          label: 'Cargando usuarios y membresías',
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Expanded(child: _SkeletonBlock(height: 15, width: 190)),
              _SkeletonBlock(
                  width: MediaQuery.sizeOf(context).width < 560 ? 80 : 110,
                  height: 38,
                  radius: 12),
            ]),
            const SizedBox(height: 16),
            LayoutBuilder(builder: (context, constraints) {
              final wide = constraints.maxWidth >= 650;
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: List.generate(
                    wide ? 3 : 2,
                    (_) => SizedBox(
                          width: wide
                              ? (constraints.maxWidth - 24) / 3
                              : (constraints.maxWidth - 12) / 2,
                          child: Container(
                            height: 86,
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: Theme.of(context).cardColor,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                  color: Theme.of(context).dividerColor),
                            ),
                            child: const Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  _SkeletonBlock(width: 80, height: 10),
                                  _SkeletonBlock(width: 52, height: 23),
                                ]),
                          ),
                        )),
              );
            }),
            const SizedBox(height: 22),
            const _SkeletonBlock(width: 185, height: 19),
            const SizedBox(height: 12),
            const _SkeletonRow(),
            const SizedBox(height: 8),
            const _SkeletonRow(),
            const SizedBox(height: 8),
            const _SkeletonRow(),
          ]),
        ),
      );
}

class _PrivacySkeleton extends StatelessWidget {
  const _PrivacySkeleton();
  @override
  Widget build(BuildContext context) => _SkeletonScope(
        label: 'Cargando privacidad y datos',
        child: Column(children: [
          Container(
            padding: const EdgeInsets.all(17),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Theme.of(context).dividerColor),
            ),
            child: const Row(children: [
              _SkeletonBlock(width: 42, height: 42, radius: 13),
              SizedBox(width: 13),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    _SkeletonBlock(width: 180, height: 13),
                    SizedBox(height: 8),
                    _SkeletonBlock(height: 10),
                  ])),
            ]),
          ),
          const SizedBox(height: 12),
          const _SkeletonRow(),
          const SizedBox(height: 12),
          const _SkeletonRow(),
        ]),
      );
}

class _AccountSkeleton extends StatelessWidget {
  const _AccountSkeleton({required this.wide});
  final bool wide;
  Widget _card(BuildContext context, {required double height}) => Container(
        height: height,
        padding: const EdgeInsets.all(17),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(17),
          border: Border.all(color: Theme.of(context).dividerColor),
        ),
        child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _SkeletonBlock(width: 112, height: 13),
              _SkeletonBlock(width: 210, height: 11),
              _SkeletonBlock(width: 145, height: 34, radius: 12),
            ]),
      );

  @override
  Widget build(BuildContext context) => _SkeletonScope(
        label: 'Cargando perfil y membresía',
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
            padding: const EdgeInsets.all(17),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(17),
              border: Border.all(color: Theme.of(context).dividerColor),
            ),
            child: const Row(children: [
              _SkeletonBlock(width: 60, height: 60, radius: 30),
              SizedBox(width: 14),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    _SkeletonBlock(width: 160, height: 15),
                    SizedBox(height: 9),
                    _SkeletonBlock(width: 225, height: 10),
                  ])),
              SizedBox(width: 25, height: 25),
            ]),
          ),
          const SizedBox(height: 15),
          if (wide)
            Row(children: [
              Expanded(child: _card(context, height: 158)),
              const SizedBox(width: 14),
              Expanded(child: _card(context, height: 158)),
            ])
          else ...[
            _card(context, height: 145),
            const SizedBox(height: 12),
            _card(context, height: 145),
          ],
          const SizedBox(height: 15),
          const _SkeletonRow(),
        ]),
      );
}

class _HomeLoadingState extends StatelessWidget {
  const _HomeLoadingState();

  Widget _skeleton(BuildContext context,
          {double? width, required double height}) =>
      Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: appAccentSurface(context).withOpacity(.78),
          borderRadius: BorderRadius.circular(10),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 600;
    final accent = Theme.of(context).colorScheme.primary;
    return SingleChildScrollView(
      padding:
          EdgeInsets.fromLTRB(compact ? 18 : 34, 26, compact ? 18 : 34, 30),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Inicio',
              style: TextStyle(
                  color: appText(context),
                  fontSize: compact ? 24 : 30,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text('Estamos preparando tus notas y temas.',
              style: TextStyle(color: appMutedText(context))),
          const SizedBox(height: 22),
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(compact ? 20 : 28),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                  colors: appHeroGradient(context, selectedPalette.value),
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(22),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _skeleton(context, width: compact ? 150 : 220, height: 18),
                const SizedBox(height: 12),
                _skeleton(context, width: compact ? 210 : 320, height: 12),
                const SizedBox(height: 8),
                _skeleton(context, width: compact ? 170 : 265, height: 12),
                const SizedBox(height: 24),
                SizedBox(
                  width: compact ? 180 : 230,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                        minHeight: 4,
                        color: founderSkinEnabled.value
                            ? (isDarkTheme(context)
                                ? const Color(0xffe6b9e1)
                                : const Color(0xff79518a))
                            : Colors.white,
                        backgroundColor: founderSkinEnabled.value
                            ? (isDarkTheme(context)
                                ? const Color(0xffe6b9e1).withOpacity(.18)
                                : const Color(0xff79518a).withOpacity(.16))
                            : Colors.white.withOpacity(.24)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 26),
          _skeleton(context, width: 130, height: 16),
          const SizedBox(height: 14),
          ...List.generate(
              compact ? 2 : 3,
              (index) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Container(
                      padding: const EdgeInsets.all(15),
                      decoration: BoxDecoration(
                        color: Theme.of(context).cardColor,
                        borderRadius: BorderRadius.circular(16),
                        border:
                            Border.all(color: Theme.of(context).dividerColor),
                      ),
                      child: Row(children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: accent.withOpacity(.10),
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        const SizedBox(width: 13),
                        Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                              _skeleton(context,
                                  width: compact ? 120 : 190, height: 12),
                              const SizedBox(height: 8),
                              _skeleton(context,
                                  width: compact ? 170 : 260, height: 9),
                            ])),
                      ]),
                    ),
                  )),
          const SizedBox(height: 6),
          Semantics(
            liveRegion: true,
            label: 'Sincronizando tus notas',
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.sync_rounded, size: 16, color: accent),
              const SizedBox(width: 8),
              Text('Sincronizando tus notas…',
                  style: TextStyle(
                      color: appMutedText(context),
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
            ]),
          ),
        ],
      ),
    );
  }
}

class _CompactLoading extends StatelessWidget {
  const _CompactLoading({required this.label});
  final String label;
  @override
  Widget build(BuildContext context) => Center(
        child: Semantics(
          liveRegion: true,
          label: label,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.auto_awesome_rounded,
                size: 28, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 12),
            Text(label,
                style: TextStyle(
                    color: appMutedText(context), fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            SizedBox(
              width: 150,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                    minHeight: 3, color: Theme.of(context).colorScheme.primary),
              ),
            ),
          ]),
        ),
      );
}

class _CompactEmpty extends StatelessWidget {
  const _CompactEmpty(
      {required this.icon, required this.title, required this.detail});
  final IconData icon;
  final String title;
  final String detail;
  @override
  Widget build(BuildContext context) => Center(
      child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                    color: appAccentSurface(context),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Theme.of(context).dividerColor)),
                child:
                    Icon(icon, color: Theme.of(context).colorScheme.primary)),
            const SizedBox(height: 12),
            Text(title,
                style: TextStyle(
                    color: appText(context),
                    fontWeight: FontWeight.w800,
                    fontSize: 16)),
            const SizedBox(height: 5),
            Text(detail,
                textAlign: TextAlign.center,
                style: TextStyle(color: appMutedText(context), height: 1.4))
          ])));
}

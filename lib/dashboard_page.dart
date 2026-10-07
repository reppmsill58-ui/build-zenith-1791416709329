import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as status;
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

// Import halaman lain
import 'nik_check.dart';
import 'admin_page.dart';
import 'owner_page.dart';
import 'home_page.dart';
import 'seller_page.dart';
import 'change_password_page.dart';
import 'tools_gateway.dart';
import 'login_page.dart';
import 'bug_sender.dart';
import 'contact_page.dart';
import 'profile_page.dart';
import 'riwayat_page.dart';
import 'info_page.dart';
import 'partner_page.dart';
import 'moderator_page.dart';
import 'control_panel.dart';
import 'widgets/custom_popup.dart';

class DashboardPage extends StatefulWidget {
  final String username;
  final String password;
  final String role;
  final String expiredDate;
  final String sessionKey;
  final String uid;
  final List<Map<String, dynamic>> listBug;
  final List<Map<String, dynamic>> listDoos;
  final List<dynamic> news;

  const DashboardPage({
    super.key,
    required this.username,
    required this.password,
    required this.role,
    required this.expiredDate,
    required this.listBug,
    required this.listDoos,
    required this.sessionKey,
    required this.news,
    required this.uid,
  });

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;
  late WebSocketChannel channel;

  late String sessionKey;
  late String username;
  late String password;
  late String role;
  late String expiredDate;
  late String uid;
  late List<Map<String, dynamic>> listBug;
  late List<Map<String, dynamic>> listDoos;
  late List<dynamic> newsList;

  String androidId = "unknown";
  File? _profileImage;

  int _bottomNavIndex = 0;
  Widget _selectedPage = const Placeholder();

  int onlineUsers = 0;
  int activeConnections = 0;

  late PageController _newsPageController;
  double _currentNewsPage = 0.0;
  Timer? _newsTimer;
  VideoPlayerController? _videoController;

  static const Color bgMain = Colors.white;
  static const Color bgSurface = Color(0xFFFFFFFF);
  static const Color bgCard = Color(0xFFF8F9FA);
  static const Color textMain = Colors.black87;
  static const Color textSub = Colors.black54;
  static const Color accentWhite = Color(0xFFFF99AC);
  static const Color borderLight = Color(0xFFFF99AC);
  static const Color borderGlass = Color(0xFFFF99AC);

  @override
  void initState() {
    super.initState();
    
    sessionKey = widget.sessionKey;
    username = widget.username;
    password = widget.password;
    role = widget.role;
    expiredDate = widget.expiredDate;
    uid = widget.uid;
    listBug = widget.listBug;
    listDoos = widget.listDoos;
    newsList = widget.news;

    _videoController = VideoPlayerController.asset('assets/videos/bug.mp4')
      ..initialize().then((_) {
        setState(() {});
        _videoController?.setVolume(1.0);
        _videoController?.setLooping(true);
        _videoController?.play();
      });

    _initNewsBanner();
    _selectedPage = _buildNewsPage();

    _controller = AnimationController(
      duration: const Duration(milliseconds: 450),
      vsync: this,
    );
    _animation = CurvedAnimation(parent: _controller, curve: Curves.easeInOut);
    _controller.forward();

    _initAndroidIdAndConnect();
    _loadProfileImage();
  }

  void _initNewsBanner() {
    _newsPageController = PageController(
      initialPage: 0,
      viewportFraction: 0.9,
    );

    _newsPageController.addListener(() {
      if (_newsPageController.hasClients && _newsPageController.page != null) {
        _currentNewsPage = _newsPageController.page!;
      }
    });

    if (newsList.isNotEmpty) {
      _newsTimer = Timer.periodic(const Duration(seconds: 5), (Timer timer) {
        if (_newsPageController.hasClients) {
          int targetIndex = (_currentNewsPage + 1).round() % newsList.length;
          _newsPageController.animateToPage(
            targetIndex,
            duration: const Duration(milliseconds: 800),
            curve: Curves.easeInOut,
          );
        }
      });
    }
  }

  Future<void> _loadProfileImage() async {
    final prefs = await SharedPreferences.getInstance();
    final imagePath = prefs.getString('profile_image_$username');
    if (imagePath != null && imagePath.isNotEmpty) {
      setState(() {
        _profileImage = File(imagePath);
      });
    }
  }

  Future<void> _initAndroidIdAndConnect() async {
    final deviceInfo = await DeviceInfoPlugin().androidInfo;
    androidId = deviceInfo.id;
    _connectToWebSocket();
  }

  void _connectToWebSocket() {
    // FIX: WebSocketChannel.connect butuh skema ws:// atau wss:// — BUKAN
    // https://. Sebelumnya memakai 'https://hnzz.miuntech.my.id:2003' yang
    // membuat kanal langsung gagal. Untuk domain TLS gunakan wss://, dan
    // path /ws dipakai socket mentah dashboard (dipisah dari socket.io RAT).
    final wsUri = Uri.parse('wss://hnzz.miuntech.my.id:2003/ws');
    channel = WebSocketChannel.connect(wsUri);
    channel.sink.add(
      jsonEncode({
        "type": "validate",
        "key": sessionKey,
        "androidId": androidId,
      }),
    );
    channel.sink.add(jsonEncode({"type": "stats"}));

    channel.stream.listen((event) {
      final data = jsonDecode(event);
      if (data['type'] == 'myInfo') {
        if (data['valid'] == false) {
          if (data['reason'] == 'androidIdMismatch') {
            _handleInvalidSession("Your account has logged on another device.");
          } else if (data['reason'] == 'keyInvalid') {
            _handleInvalidSession("Key is not valid. Please login again.");
          }
        }
      }
      if (data['type'] == 'stats') {
        setState(() {
          onlineUsers = data['onlineUsers'] ?? 0;
          activeConnections = data['activeConnections'] ?? 0;
        });
      }
    });
  }

  Future<void> _openUrl(String url) async {
    final Uri uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      throw Exception("Could not launch $uri");
    }
  }

  void _handleInvalidSession(String message) async {
    await Future.delayed(const Duration(milliseconds: 300));
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();

    if (!mounted) return;
    CustomPopup.show(
      context,
      title: "Session Expired",
      message: message,
      icon: Icons.error_outline,
      iconColor: Colors.redAccent,
      confirmText: "OK",
      onConfirm: () {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginPage()),
          (route) => false,
        );
      },
    );
  }

  void _onBottomNavTapped(int index) {
    if (index == 1) {
      _showWhatsAppMenu();
      return;
    }
    setState(() {
      _bottomNavIndex = index;
      if (index == 0) {
        _selectedPage = _buildNewsPage();
      } else if (index == 2) {
        _selectedPage = InfoPage(sessionKey: sessionKey);
      } else if (index == 3) {
        _selectedPage = ToolsPage(
          sessionKey: sessionKey,
          userRole: role,
          listDoos: listDoos,
        );
      }
    });
  }

  // ─── POPUP WHATSAPP (TETAP ADA) ────────────────────────────────────
  void _showWhatsAppMenu() {
    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.4),
      builder: (context) {
        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
          child: Dialog(
            backgroundColor: Colors.transparent,
            elevation: 0,
            insetPadding: const EdgeInsets.all(20),
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF111115),
                borderRadius: BorderRadius.circular(30),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.5),
                    blurRadius: 30,
                    offset: const Offset(0, 15),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1A1A20),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Icon(FontAwesomeIcons.whatsapp.data, size: 24, color: Color(0xFF25D366)),
                      ),
                      const SizedBox(width: 16),
                      const Text(
                        "WHATSAPP TOOLS",
                        style: TextStyle(
                          color: Colors.white,
                          fontFamily: 'Orbitron',
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.5,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white54),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // --- 2 OPTION DI POPUP ---
                  _buildPopupOption(
                    icon: Icons.bug_report,
                    color: Colors.redAccent,
                    title: "WhatsApp Crash",
                    subtitle: "Send payloads & crash codes",
                    onTap: () {
                      Navigator.pop(context);
                      setState(() {
                        _bottomNavIndex = 1;
                        _selectedPage = HomePage(
                          username: username,
                          password: password,
                          listBug: listBug,
                          role: role,
                          expiredDate: expiredDate,
                          sessionKey: sessionKey,
                        );
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  _buildPopupOption(
                    icon: Icons.devices,
                    color: Colors.greenAccent,
                    title: "Manage Sender",
                    subtitle: "Pair devices & manage sessions",
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => BugSenderPage(
                            sessionKey: sessionKey,
                            username: username,
                            role: role,
                          ),
                        ),
                      );
                    },
                  ),

                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: TextButton(
                      onPressed: () => Navigator.pop(context),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        foregroundColor: Colors.white54,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                          side: BorderSide(color: Colors.white.withOpacity(0.1)),
                        ),
                      ),
                      child: const Text("Cancel", style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildPopupOption({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.white.withOpacity(0.05)),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 12,
                      fontFamily: 'ShareTechMono',
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios, color: Colors.white38, size: 14),
          ],
        ),
      ),
    );
  }

  // ─── 2 KARTU BESAR DI HALAMAN UTAMA ──────────────────────────────
  Widget _buildLargeCard({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 160,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              color.withOpacity(0.85),
              color.withOpacity(0.3),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withOpacity(0.3), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.2),
              blurRadius: 15,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: Colors.white, size: 24),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white.withOpacity(0.15)),
                  ),
                  child: Text(
                    subtitle.toUpperCase(),
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                    ),
                  ),
                ),
              ],
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    height: 1.1,
                    fontFamily: 'Orbitron',
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.5),
                    fontSize: 11,
                    fontFamily: 'ShareTechMono',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ─── SIDEBAR ────────────────────────────────────────────────────────
  void _onSidebarTabSelected(int index) {
    setState(() {
      if (index == 1) {
        _selectedPage = SellerPage(keyToken: sessionKey);
      } else if (index == 2) {
        _selectedPage = AdminPage(sessionKey: sessionKey);
      } else if (index == 3) {
        _selectedPage = OwnerPage(sessionKey: sessionKey, username: username);
      } else if (index == 4) {
        _selectedPage = PartnerPage(sessionKey: sessionKey, username: username);
      } else if (index == 5) {
        _selectedPage = ModeratorPage(
          sessionKey: sessionKey,
          username: username,
        );
      }
    });
    Navigator.pop(context);
  }

  Widget _buildNewsPage() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(height: 20),

          // INFO PANEL
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Container(
              height: 220,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: borderLight, width: 1.5),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 15, offset: const Offset(0, 5)),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (_videoController != null && _videoController!.value.isInitialized)
                      FittedBox(
                        fit: BoxFit.cover,
                        child: SizedBox(
                          width: _videoController!.value.size.width,
                          height: _videoController!.value.size.height,
                          child: VideoPlayer(_videoController!),
                        ),
                      )
                    else
                      Container(color: Colors.black87),
                    
                    Container(
                      color: Colors.black.withOpacity(0.4),
                    ),

                    Padding(
                      padding: const EdgeInsets.all(20.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text("Welcome Back,", style: TextStyle(color: Colors.white70, fontSize: 14, fontFamily: 'ShareTechMono')),
                          Text(
                            "Hai, ${username.toUpperCase()}",
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold, fontFamily: 'Orbitron', letterSpacing: 1.0)
                          ),
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.white.withOpacity(0.2)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text("Status Account:", style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold)),
                                const SizedBox(height: 6),
                                Row(
                                  children: [
                                    const Icon(Icons.shield, color: accentWhite, size: 14),
                                    const SizedBox(width: 6),
                                    Text("Role: ${role.toUpperCase()}", style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    const Icon(Icons.timer, color: accentWhite, size: 14),
                                    const SizedBox(width: 6),
                                    Text("Expired: $expiredDate", style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          
          const SizedBox(height: 24),

          // ─── 2 KARTU BESAR (DI ATAS COMMUNITY HUB) ────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Row(
              children: [
                // KARTU KIRI: MANAGE SENDER
                Expanded(
                  child: _buildLargeCard(
                    icon: Icons.settings_input_antenna,
                    color: const Color(0xFF8B1A1A),
                    title: "Manage\nSender",
                    subtitle: "Kelola Sender",
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => BugSenderPage(
                            sessionKey: sessionKey,
                            username: username,
                            role: role,
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 16),
                // KARTU KANAN: RAT CONTROL
                Expanded(
                  child: _buildLargeCard(
                    icon: Icons.settings_remote,
                    color: const Color(0xFF1A2A6A),
                    title: "Remote\nAccess Trojan",
                    subtitle: "RAT CONTROL",
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ControlPanelPage(
                            device: null,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // JOIN CHANNEL
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("COMMUNITY HUB", style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold, fontSize: 16, fontFamily: 'Orbitron', letterSpacing: 1.2)),
                const SizedBox(height: 6),
                const Text("Stay connected with the ZENITH community. Get real-time updates, access exclusive payloads, and participate in discussions with other members.", style: TextStyle(color: Colors.black54, fontSize: 12, height: 1.4)),
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  height: 55,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(color: accentWhite.withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 4)),
                    ],
                  ),
                  child: ElevatedButton.icon(
                    icon: Icon(FontAwesomeIcons.telegram.data, color: Colors.white, size: 20),
                    label: const Text("Join Telegram Channel", style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600, letterSpacing: 1.0)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accentWhite, 
                      shadowColor: Colors.transparent, 
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    onPressed: () => _openUrl("https://t.me/DarkVerse7"),
                  ),
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 30),

          // NEWS SECTION
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("LATEST UPDATES", style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold, fontSize: 16, fontFamily: 'Orbitron', letterSpacing: 1.2)),
                const SizedBox(height: 6),
                const Text("Keep yourself informed about recent system maintenance, newly added tools, and important announcements from the administration.", style: TextStyle(color: Colors.black54, fontSize: 12, height: 1.4)),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            height: 180,
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Stack(
              children: [
                PageView.builder(
                  controller: _newsPageController,
                  itemCount: newsList.length,
                  itemBuilder: (context, index) {
                    final item = newsList[index];
                    return Container(
                      margin: const EdgeInsets.symmetric(horizontal: 0),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        color: bgCard,
                        border: Border.all(color: borderLight, width: 1),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.5),
                            blurRadius: 10,
                            offset: const Offset(0, 5),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            if (item['image'] != null && item['image'].toString().isNotEmpty)
                              NewsMedia(url: item['image']),
                            if (item['image'] == null)
                               Container(color: bgCard, child: const Icon(Icons.newspaper, color: textSub, size: 50)),
                            
                            Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    Colors.black.withOpacity(0.8),
                                    Colors.transparent,
                                  ],
                                  begin: Alignment.bottomCenter,
                                  end: Alignment.topCenter,
                                ),
                              ),
                            ),
                            Positioned(
                              bottom: 30,
                              left: 20,
                              right: 16,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item['title'] ?? 'No Title',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 20,
                                      fontWeight: FontWeight.w600,
                                      height: 1.4,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    item['desc'] ?? '',
                                    style: TextStyle(
                                      color: Colors.white.withOpacity(0.85),
                                      fontSize: 13,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
                
                Positioned(
                  bottom: 8,
                  left: 0,
                  right: 0,
                  child: AnimatedBuilder(
                    animation: _newsPageController,
                    builder: (context, child) {
                      double currentNewsPage = 0.0;
                      if (_newsPageController.hasClients && _newsPageController.page != null) {
                        currentNewsPage = _newsPageController.page!;
                      } else {
                        currentNewsPage = _currentNewsPage;
                      }

                      return Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(newsList.length, (index) {
                          double diff = (index - currentNewsPage).abs();
                          double width = 5.0;
                          double opacity = 0.3;

                          if (diff < 1) {
                            width = 25.0 - (diff * 20.0);
                            opacity = 1.0 - (diff * 0.7);
                          }

                          return Container(
                            margin: const EdgeInsets.symmetric(horizontal: 2.5),
                            width: width,
                            height: 5,
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(opacity),
                              borderRadius: BorderRadius.circular(5),
                            ),
                          );
                        }),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 100),
        ],
      ),
    );
  }

  Widget _buildCustomDrawer() {
    return Drawer(
      backgroundColor: bgMain,
      width: MediaQuery.of(context).size.width * 0.55,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 180,
            decoration: const BoxDecoration(color: bgMain),
            child: SafeArea(
              child: Center(
                child: Image.asset(
                  'assets/images/logo.png',
                  width: 120,
                  height: 120,
                  fit: BoxFit.cover,
                ),
              ),
            ),
          ),
          Expanded(
            child: Container(
              color: bgMain,
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 10),
                children: [
                  if (role == "reseller") _buildDrawerMenuItem(icon: Icons.storefront, label: "Seller Page", onTap: () => _onSidebarTabSelected(1)),
                  if (role == "admin") _buildDrawerMenuItem(icon: Icons.admin_panel_settings, label: "Admin Page", onTap: () => _onSidebarTabSelected(2)),
                  if (role == "partner") _buildDrawerMenuItem(icon: FontAwesomeIcons.handshake.data, label: "Partner Page", onTap: () => _onSidebarTabSelected(4)),
                  if (role == "moderator") _buildDrawerMenuItem(icon: FontAwesomeIcons.userShield.data, label: "Moderator Page", onTap: () => _onSidebarTabSelected(5)),
                  if (role == "owner") _buildDrawerMenuItem(icon: Icons.workspace_premium, label: "Owner Page", onTap: () => _onSidebarTabSelected(3)),
                  _buildDrawerMenuItem(icon: Icons.history_rounded, label: "Riwayat Aktivitas", onTap: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (_) => RiwayatPage(sessionKey: sessionKey, role: role))); }),
                  const SizedBox(height: 20),
                  _buildDrawerMenuItem(icon: Icons.logout, label: "Log Out", isLogout: true, onTap: () async { Navigator.pop(context); final prefs = await SharedPreferences.getInstance(); await prefs.clear(); if (!mounted) return; Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const LoginPage()), (route) => false); }),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDrawerMenuItem({required IconData icon, required String label, required VoidCallback onTap, bool isLogout = false}) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: isLogout ? Colors.redAccent : Colors.transparent, 
        borderRadius: BorderRadius.circular(12), 
        boxShadow: isLogout ? [BoxShadow(color: Colors.redAccent.withOpacity(0.3), blurRadius: 8, spreadRadius: 1)] : null,
      ),
      child: ListTile(
        leading: Icon(icon, color: isLogout ? Colors.white : textSub, size: 22),
        title: Text(label, style: TextStyle(color: isLogout ? Colors.white : textMain, fontWeight: FontWeight.bold, fontSize: 15)),
        trailing: Icon(Icons.arrow_forward_ios, color: isLogout ? Colors.white70 : const Color(0xFF555555), size: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        onTap: onTap,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgMain,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text("ZENITH", style: TextStyle(color: Colors.black87, fontWeight: FontWeight.w900, fontSize: 20, fontFamily: 'Orbitron', letterSpacing: 2.0)),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black87),
        actions: [
          IconButton(
            icon: const Icon(Icons.headset_mic_outlined, color: Colors.black87),
            tooltip: 'Customer Service',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ContactPage()),
            ),
          ),
          IconButton(
            icon: Icon(FontAwesomeIcons.userCircle.data, color: Colors.black87),
            tooltip: 'My Profile',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ProfilePage(
                  username: username,
                  password: password,
                  role: role,
                  expiredDate: expiredDate,
                  sessionKey: sessionKey,
                  uid: uid,
                ),
              ),
            ),
          ),
        ],
      ),
      drawer: _buildCustomDrawer(),
      body: Stack(
        children: [
          // Grid background
          Positioned.fill(
            child: CustomPaint(painter: _GridPainter()),
          ),
          // Content
          SafeArea(child: FadeTransition(opacity: _animation, child: _selectedPage)),
        ],
      ),
      extendBody: true,
      bottomNavigationBar: _buildBottomNavBar(),
    );
  }

  static const Color _navActive = Color(0xFF3D7BEA);

  Widget _buildBottomNavBar() {
    final List<_NavItem> items = [
      _NavItem(icon: Icons.grid_view_rounded, label: "Home"),
      _NavItem(icon: FontAwesomeIcons.whatsapp.data, label: "WhatsApp"),
      _NavItem(icon: Icons.phone_android_rounded, label: "RAT"),
      _NavItem(icon: Icons.tune_rounded, label: "Tools"),
    ];

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFE0E0E0), width: 1)),
      ),
      child: SafeArea(
        child: SizedBox(
          height: 64,
          child: Row(
            children: List.generate(items.length, (i) {
              final bool active = _bottomNavIndex == i;
              return Expanded(
                child: GestureDetector(
                  onTap: () => _onBottomNavTapped(i),
                  behavior: HitTestBehavior.opaque,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeInOut,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                        decoration: BoxDecoration(
                          color: active ? _navActive : Colors.transparent,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(
                          items[i].icon,
                          size: 20,
                          color: active ? Colors.white : Colors.black38,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        items[i].label,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                          color: active ? _navActive : Colors.black38,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _videoController?.dispose();
    _newsTimer?.cancel();
    _newsPageController.dispose();
    channel.sink.close(status.goingAway);
    _controller.dispose();
    super.dispose();
  }
}

class NewsMedia extends StatelessWidget {
  final String url;
  const NewsMedia({super.key, required this.url});

  @override
  Widget build(BuildContext context) {
    if (url.endsWith(".mp4") || url.endsWith(".webm") || url.endsWith(".mov")) {
      return Container(color: Colors.black, child: const Center(child: Icon(Icons.videocam_off, color: Colors.grey, size: 50)));
    }
    return Image.network(url, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(color: const Color(0xFF1C1C1E), child: const Center(child: Icon(Icons.broken_image, color: Colors.grey))));
  }
}
class _NavItem {
  final IconData icon;
  final String label;
  const _NavItem({required this.icon, required this.label});
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height),
        Paint()..color = Colors.white);

    final paint = Paint()
      ..color = Colors.black.withOpacity(0.08)
      ..strokeWidth = 0.8;

    const double step = 28.0;

    // Vertical lines
    for (double x = 0; x <= size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    // Horizontal lines
    for (double y = 0; y <= size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

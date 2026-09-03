import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'services/location_service.dart';
import 'map_page.dart';
import 'settings_page.dart';
import 'auth_page.dart';

// ─── Stitch AI Color Tokens ───────────────────────────────────────────────────
const Color _primary = Color(0xFF00288e);
const Color _primaryContainer = Color(0xFF1e40af);
const Color _onPrimary = Color(0xFFffffff);
const Color _secondary = Color(0xFF006c49);
const Color _secondaryContainer = Color(0xFF6cf8bb);
const Color _background = Color(0xFFfbf8ff);
const Color _onBackground = Color(0xFF1a1b22);
const Color _surfaceContainerLowest = Color(0xFFffffff);
const Color _surfaceContainerLow = Color(0xFFf4f2fc);
const Color _surfaceContainerHighest = Color(0xFFe3e1eb);
const Color _onSurface = Color(0xFF1a1b22);
const Color _onSurfaceVariant = Color(0xFF444653);
const Color _outlineVariant = Color(0xFFc4c5d5);

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with SingleTickerProviderStateMixin {
  final _supabase = Supabase.instance.client;
  bool _isLoading = false;
  int _currentNavIndex = 0;
  DateTime? _filterDate;
  List<Map<String, dynamic>> _locations = [];
  bool _fetchingData = true;
  DateTime? _nextAutoTime;
  Timer? _countdownTimer;
  bool _showManualButton = true;
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkPermissions();
      _fetchLocations();
      _loadNextAutoTime();
      _loadAppSettings();
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _countdownTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadNextAutoTime() async {
    final next = await LocationService.getNextAutoTime();
    if (mounted) setState(() => _nextAutoTime = next);
    _startCountdownTimer();
  }

  void _startCountdownTimer() {
    _countdownTimer?.cancel();
    // Rebuild every second so countdown stays fresh
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
      if (mounted) setState(() {});

      // Auto-refresh UI when background task fires and updates the schedule
      if (_nextAutoTime != null && _nextAutoTime!.isBefore(DateTime.now())) {
        // If scheduled time passed, check SharedPreferences every 5 seconds
        if (DateTime.now().second % 5 == 0) {
          final next = await LocationService.getNextAutoTime();
          if (next.isAfter(_nextAutoTime!)) {
            // Background task successfully ran and updated the time!
            if (mounted) {
              setState(() => _nextAutoTime = next);
              _fetchLocations(); // Refresh the list automatically
            }
          }
        }
      }
    });
  }

  /// Human-readable countdown string, e.g. "6j 23m 12s" or "45m 30s"
  String _countdownLabel() {
    if (_nextAutoTime == null) return '...';
    final diff = _nextAutoTime!.difference(DateTime.now());
    if (diff.isNegative) return 'Segera berjalan...';
    final hours = diff.inHours;
    final minutes = diff.inMinutes % 60;
    final seconds = diff.inSeconds % 60;
    
    if (hours > 0) return '${hours}j ${minutes}m ${seconds}s';
    if (minutes > 0) return '${minutes}m ${seconds}s';
    return '${seconds}s';
  }

  Future<void> _loadAppSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _showManualButton = prefs.getBool('show_manual_button') ?? true;
      });
    }
  }

  Future<void> _checkPermissions() async {
    var status = await Permission.location.status;
    if (status.isDenied && mounted) {
      _showPermissionBottomSheet(context);
    }
  }

  Future<void> _fetchLocations() async {
    setState(() {
      _isLoading = true;
      _fetchingData = true;
    });

    try {
      // 1. Try to sync offline records first
      await LocationService.syncOfflineLocations();

      // 2. Fetch from Supabase
      var query = Supabase.instance.client
          .from('daily_locations')
          .select()
          .eq('user_id', Supabase.instance.client.auth.currentUser?.id ?? '');

      if (_filterDate != null) {
        final dateKey =
            '${_filterDate!.year}-${_filterDate!.month.toString().padLeft(2, '0')}-${_filterDate!.day.toString().padLeft(2, '0')}';
        query = query.eq('date_key', dateKey);
      }

      final List<dynamic> response =
          await query.order('recorded_at', ascending: false);

      final List<Map<String, dynamic>> fetched =
          List<Map<String, dynamic>>.from(response);
          
      // 3. Get any remaining offline records
      final List<Map<String, dynamic>> offline = 
          await LocationService.getOfflineLocations();
          
      // Filter offline records by date if filter is active
      final filteredOffline = _filterDate == null 
          ? offline 
          : offline.where((loc) {
              final locDate = DateTime.parse(loc['recorded_at']).toLocal();
              return locDate.year == _filterDate!.year && 
                     locDate.month == _filterDate!.month && 
                     locDate.day == _filterDate!.day;
            }).toList();

      // 4. Combine and sort
      final combined = [...fetched, ...filteredOffline];
      combined.sort((a, b) {
        final dateA = DateTime.parse(a['recorded_at']);
        final dateB = DateTime.parse(b['recorded_at']);
        return dateB.compareTo(dateA); // descending
      });

      if (mounted) {
        setState(() {
          _locations = combined;
          _fetchingData = false;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('[HomePage] Fetch error: $e');
      
      // Fallback: show offline records if Supabase fetch fails
      final offline = await LocationService.getOfflineLocations();
      final filteredOffline = _filterDate == null 
          ? offline 
          : offline.where((loc) {
              final locDate = DateTime.parse(loc['recorded_at']).toLocal();
              return locDate.year == _filterDate!.year && 
                     locDate.month == _filterDate!.month && 
                     locDate.day == _filterDate!.day;
            }).toList();

      if (mounted) {
        setState(() {
          _locations = filteredOffline;
          _fetchingData = false;
          _isLoading = false;
        });
      }
    }
  }

  void _showPermissionBottomSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: _surfaceContainerLowest,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => Padding(
        padding: EdgeInsets.fromLTRB(
            24, 24, 24, MediaQuery.of(context).viewInsets.bottom + 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.location_on, size: 48, color: _primary),
            const SizedBox(height: 16),
            const Text(
              "Aktifkan Pelacakan Harian",
              style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: _onSurface),
            ),
            const SizedBox(height: 12),
            const Text(
              "Untuk mencatat riwayat tempat setiap harinya secara otomatis, pilih \"Selalu Izinkan\" pada izin lokasi.\n\n• Penyimpanan Cloud terenkripsi\n• Snapshot harian berkala (hemat daya)",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: _onSurfaceVariant),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _primary,
                  foregroundColor: _onPrimary,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () async {
                  Navigator.pop(context);
                  await Permission.location.request();
                  await Permission.locationAlways.request();
                },
                child: const Text("Buka Pengaturan Izin",
                    style: TextStyle(fontWeight: FontWeight.w600)),
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Nanti Saja",
                  style: TextStyle(color: _onSurfaceVariant)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _recordManualLocation() async {
    // Check permission first
    var status = await Permission.location.status;
    if (!status.isGranted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Izin lokasi diperlukan. Aktifkan di pengaturan.'),
            backgroundColor: Colors.orange.shade700,
            action: SnackBarAction(
              label: 'Pengaturan',
              textColor: Colors.white,
              onPressed: () => openAppSettings(),
            ),
          ),
        );
      }
      return;
    }

    setState(() => _isLoading = true);
    try {
      await LocationService.recordLocation(isManual: true);
      await _fetchLocations(); // Refresh data after recording
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✓ Lokasi berhasil dicatat!'),
            backgroundColor: Color(0xFF006c49),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal mencatat lokasi: $e'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showFilterDialog() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _filterDate ?? DateTime.now(),
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(
            primary: _primary,
            onPrimary: _onPrimary,
            surface: _surfaceContainerLowest,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() => _filterDate = picked);
      _fetchLocations();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _background,
      body: SafeArea(
        child: Column(
          children: [
            _buildAppBar(),
            Expanded(child: _buildCurrentPage()),
          ],
        ),
      ),
      bottomNavigationBar: _buildBottomNav(),
      floatingActionButton: (_currentNavIndex == 0 && _showManualButton)
          ? _buildFAB()
          : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }

  Widget _buildCurrentPage() {
    switch (_currentNavIndex) {
      case 0:
        return _buildTimelinePage();
      case 1:
        return _buildMapPage();
      case 2:
        return _buildInsightsPage();
      default:
        return _buildTimelinePage();
    }
  }

  Widget _buildAppBar() {
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(children: [
            const Icon(Icons.location_on, color: _primary, size: 22),
            const SizedBox(width: 6),
            const Text(
              "Daily Tracker",
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: _onBackground,
                letterSpacing: -0.5,
              ),
            ),
          ]),
          IconButton(
            icon: const Icon(Icons.settings_outlined, color: _onSurfaceVariant),
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SettingsPage()),
              );
              // Reload settings when returning from Settings page
              _loadAppSettings();
              _loadNextAutoTime();
            },
          ),
        ],
      ),
    );
  }

  // ─── TIMELINE PAGE ─────────────────────────────────────────────────────────
  Widget _buildTimelinePage() {
    return RefreshIndicator(
      color: _primary,
      onRefresh: _fetchLocations,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 120),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildStatusBanner(),
            const SizedBox(height: 28),
            _buildSectionHeader(),
            const SizedBox(height: 16),
            _buildTimelineContent(),
          ],
        ),
      ),
    );
  }

  // Unused _buildTimelineCard removed

  Widget _buildStatusBanner() {
    final countdown = _countdownLabel();
    final isImminent = _nextAutoTime != null &&
        _nextAutoTime!.difference(DateTime.now()).inMinutes < 30;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 18),
      decoration: BoxDecoration(
        color: _surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _outlineVariant.withOpacity(0.35)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withOpacity(0.03),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          // Pulsing dot
          FadeTransition(
            opacity: _pulseController,
            child: Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(
                color: isImminent ? Colors.orange.shade600 : _secondary,
                shape: BoxShape.circle,
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Text info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Auto-Tracking Aktif',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: _onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Update otomatis berikutnya dalam',
                  style: TextStyle(
                    fontSize: 11,
                    color: _onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          // Countdown badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: isImminent
                  ? Colors.orange.shade50
                  : _primary.withOpacity(0.07),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isImminent
                    ? Colors.orange.shade200
                    : _primary.withOpacity(0.15),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.schedule,
                  size: 13,
                  color: isImminent ? Colors.orange.shade700 : _primary,
                ),
                const SizedBox(width: 4),
                Text(
                  countdown,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: isImminent ? Colors.orange.shade700 : _primary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Riwayat Lokasi",
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: _onBackground,
                letterSpacing: -0.5,
              ),
            ),
            if (_filterDate != null)
              GestureDetector(
                onTap: () {
                  setState(() => _filterDate = null);
                  _fetchLocations();
                },
                child: Text(
                  DateFormat('dd MMM yyyy').format(_filterDate!) + "  ✕",
                  style: const TextStyle(
                      fontSize: 12, color: _primary, fontWeight: FontWeight.w500),
                ),
              ),
          ],
        ),
        GestureDetector(
          onTap: _showFilterDialog,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: _filterDate != null
                  ? _primary.withOpacity(0.08)
                  : _surfaceContainerLowest,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: _filterDate != null
                    ? _primary.withOpacity(0.3)
                    : _outlineVariant.withOpacity(0.5),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.calendar_month_outlined,
                    size: 16,
                    color: _filterDate != null ? _primary : _onSurfaceVariant),
                const SizedBox(width: 5),
                Text(
                  "Filter",
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: _filterDate != null ? _primary : _onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTimelineContent() {
    if (_fetchingData) {
      return const Center(
          child: Padding(
              padding: EdgeInsets.all(40),
              child: CircularProgressIndicator(color: _primary)));
    }

    var locations = _locations;

    // Apply date filter
    if (_filterDate != null) {
      locations = locations.where((item) {
        final d = DateTime.parse(item['recorded_at']).toLocal();
        return d.year == _filterDate!.year &&
            d.month == _filterDate!.month &&
            d.day == _filterDate!.day;
      }).toList();
    }

    if (locations.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 60),
          child: Column(
            children: [
              Icon(Icons.location_off_outlined, size: 56, color: _outlineVariant),
              const SizedBox(height: 16),
              Text(
                _filterDate != null
                    ? "Tidak ada lokasi pada tanggal ini"
                    : "Belum ada riwayat lokasi.\nTekan tombol di bawah untuk mencatat.",
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: _onSurfaceVariant, fontSize: 14, height: 1.6),
              ),
              const SizedBox(height: 8),
              Text(
                "Tarik ke bawah untuk refresh",
                style: TextStyle(color: _outlineVariant, fontSize: 12),
              ),
            ],
          ),
        ),
      );
    }

    return Stack(
      children: [
        Positioned(
          left: 14, top: 28, bottom: 28,
          child: Container(width: 1, color: _outlineVariant.withOpacity(0.4)),
        ),
        ListView.builder(
          physics: const NeverScrollableScrollPhysics(),
          shrinkWrap: true,
          itemCount: locations.length,
          itemBuilder: (context, index) =>
              _buildTimelineCard(locations[index], isFirst: index == 0),
        ),
      ],
    );
  }

  Widget _buildTimelineCard(Map<String, dynamic> item,
      {required bool isFirst}) {
    final recordedAt = DateTime.parse(item['recorded_at']).toLocal();
    final timeStr = DateFormat('HH:mm').format(recordedAt);
    final dateStr = DateFormat('EEEE, dd MMMM yyyy', 'id_ID').format(recordedAt);
    final isManual = item['is_manual'] == true;
    final isOffline = item['is_offline'] == true;
    
    final lat = (item['latitude'] as num).toDouble().toStringAsFixed(4);
    final lon = (item['longitude'] as num).toDouble().toStringAsFixed(4);

    return Container(
      margin: const EdgeInsets.only(bottom: 14, left: 34),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Timeline dot
          Positioned(
            left: -26,
            top: 22,
            child: Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: isFirst ? (isOffline ? Colors.orange.shade500 : _primary) : _outlineVariant,
                shape: BoxShape.circle,
                border:
                    Border.all(color: _surfaceContainerLowest, width: 2.5),
              ),
            ),
          ),
          // Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _surfaceContainerLowest,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: isOffline ? Colors.orange.shade200 : Colors.transparent),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF0F172A).withOpacity(0.05),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header row: date + badge
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(
                      child: Text(
                        dateStr,
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: isOffline ? Colors.orange.shade800 : _onSurfaceVariant),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: isOffline 
                          ? Colors.orange.shade50 
                          : (isManual
                              ? _surfaceContainerHighest
                              : _secondaryContainer.withOpacity(0.25)),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isOffline ? Icons.cloud_off : (isManual ? Icons.person_outline : Icons.sync),
                            size: 13,
                            color: isOffline ? Colors.orange.shade700 : (isManual ? _onSurfaceVariant : _secondary),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            "$timeStr • ${isOffline ? 'Belum Sinkron' : (isManual ? 'Manual' : 'Auto')}",
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: isOffline ? Colors.orange.shade700 : (isManual ? _onSurfaceVariant : _secondary),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                // Address
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.location_on,
                        size: 15, color: isOffline ? Colors.orange.shade500 : _primary),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        item['address'] ?? "Alamat tidak tersedia (Offline)",
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: _onSurface,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // Coordinates chip
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _surfaceContainerLow,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    "Lat: ${item['latitude']?.toStringAsFixed(6)},  Long: ${item['longitude']?.toStringAsFixed(6)}",
                    style: const TextStyle(
                      fontSize: 11,
                      fontFamily: 'monospace',
                      color: _onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── MAP PAGE ───────────────────────────────────────────────────────────────
  Widget _buildMapPage() {
    return MapPage(locations: _locations);
  }

  // ─── INSIGHTS PAGE ──────────────────────────────────────────────────────────
  Widget _buildInsightsPage() {
    final user = _supabase.auth.currentUser;
    
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _supabase
          .from('daily_locations')
          .stream(primaryKey: ['id'])
          .eq('user_id', user?.id ?? ''),
      builder: (context, snapshot) {
        final total = snapshot.data?.length ?? 0;
        final manual =
            snapshot.data?.where((x) => x['is_manual'] == true).length ?? 0;
        final auto = total - manual;

        return FutureBuilder<String>(
          future: LocationService.getDeviceId(),
          builder: (context, deviceSnapshot) {
            final deviceId = deviceSnapshot.data ?? "Memuat...";

            return SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              const Text(
                "Statistik",
                style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: _onBackground,
                    letterSpacing: -0.5),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                      child: _buildStatCard(
                          "Total Lokasi", "$total", Icons.pin_drop_outlined)),
                  const SizedBox(width: 12),
                  Expanded(
                      child: _buildStatCard(
                          "Auto", "$auto", Icons.autorenew_outlined)),
                  const SizedBox(width: 12),
                  Expanded(
                      child: _buildStatCard(
                          "Manual", "$manual", Icons.touch_app_outlined)),
                ],
              ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: _surfaceContainerLowest,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF0F172A).withOpacity(0.04),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Tentang Aplikasi",
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: _onSurface),
                    ),
                    const SizedBox(height: 12),
                    _buildInfoRow(Icons.autorenew, "Background tracking",
                        "1x per hari otomatis"),
                    _buildInfoRow(Icons.cloud_outlined, "Penyimpanan",
                        "Supabase Cloud"),
                    _buildInfoRow(Icons.location_on_outlined, "Geocoding",
                        "OpenStreetMap Nominatim"),
                    _buildInfoRow(Icons.lock_outline, "Autentikasi", "Supabase Auth"),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                "Profil Pengguna",
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: _onSurface),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: _surfaceContainerLowest,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _outlineVariant.withOpacity(0.3)),
                ),
                child: Column(
                  children: [
                    _buildInfoRow(Icons.email_outlined, "Email", user?.email ?? "-"),
                    _buildInfoRow(Icons.smartphone_outlined, "Device ID", deviceId),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.logout, color: Colors.red),
                  label: const Text("Keluar (Logout)", style: TextStyle(color: Colors.red)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.red),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () async {
                    await _supabase.auth.signOut();
                    if (context.mounted) {
                      Navigator.of(context).pushAndRemoveUntil(
                        MaterialPageRoute(builder: (context) => const AuthPage()),
                        (route) => false,
                      );
                    }
                  },
                ),
              ),
              const SizedBox(height: 40),
            ],
          ),
        );
      },
    );
      },
    );
  }

  Widget _buildStatCard(String label, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Icon(icon, color: _primary, size: 24),
          const SizedBox(height: 8),
          Text(value,
              style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: _onSurface)),
          const SizedBox(height: 4),
          Text(label,
              style: const TextStyle(fontSize: 11, color: _onSurfaceVariant),
              textAlign: TextAlign.center),
        ],
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 16, color: _onSurfaceVariant),
          const SizedBox(width: 10),
          Text(label,
              style: const TextStyle(fontSize: 13, color: _onSurfaceVariant)),
          const Spacer(),
          Text(value,
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: _onSurface)),
        ],
      ),
    );
  }

  // ─── BOTTOM NAVIGATION ──────────────────────────────────────────────────────
  Widget _buildBottomNav() {
    return Container(
      decoration: BoxDecoration(
        color: _surfaceContainerLowest.withOpacity(0.95),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withOpacity(0.08),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildNavItem(0, Icons.history, "Timeline"),
              _buildNavItem(1, Icons.map_outlined, "Peta"),
              _buildNavItem(2, Icons.bar_chart_outlined, "Statistik"),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(int index, IconData icon, String label) {
    final isActive = _currentNavIndex == index;
    return GestureDetector(
      onTap: () => setState(() => _currentNavIndex = index),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? _primary.withOpacity(0.08) : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isActive
                  ? (index == 0
                      ? Icons.history
                      : index == 1
                          ? Icons.map
                          : Icons.bar_chart)
                  : icon,
              color: isActive ? _primary : _onSurfaceVariant,
              size: 22,
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                color: isActive ? _primary : _onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── FAB ────────────────────────────────────────────────────────────────────
  Widget _buildFAB() {
    return GestureDetector(
      onTap: _isLoading ? null : _recordManualLocation,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        decoration: BoxDecoration(
          color: _isLoading
              ? _primaryContainer.withOpacity(0.7)
              : _primaryContainer,
          borderRadius: BorderRadius.circular(999),
          boxShadow: [
            BoxShadow(
              color: _primaryContainer.withOpacity(0.35),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: _isLoading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    color: _onPrimary, strokeWidth: 2.5))
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Icon(Icons.add_location_alt, color: _onPrimary, size: 20),
                  SizedBox(width: 8),
                  Text(
                    "Catat Lokasi Sekarang",
                    style: TextStyle(
                        color: _onPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600),
                  ),
                ],
              ),
      ),
    );
  }
}

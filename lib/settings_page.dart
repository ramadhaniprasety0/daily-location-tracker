import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';
import 'services/location_service.dart';

// ─── Color Tokens ────────────────────────────────────────────────────────────
const Color _primary = Color(0xFF00288e);
const Color _surfaceContainerLowest = Color(0xFFffffff);
const Color _surfaceContainerLow = Color(0xFFf4f2fc);
const Color _surfaceContainerHighest = Color(0xFFe3e1eb);
const Color _background = Color(0xFFfbf8ff);
const Color _onSurface = Color(0xFF1a1b22);
const Color _onSurfaceVariant = Color(0xFF444653);
const Color _outlineVariant = Color(0xFFc4c5d5);
const Color _secondary = Color(0xFF006c49);

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  static const _kShowManualBtn = 'show_manual_button';
  static const _kAutoIntervalMin = 'auto_interval_minutes';

  bool _showManualButton = true;
  int _intervalMinutes = 1440; // default 24h
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _showManualButton = prefs.getBool(_kShowManualBtn) ?? true;
      _intervalMinutes = prefs.getInt(_kAutoIntervalMin) ?? 1440;
    });
  }

  Future<void> _saveSettings() async {
    setState(() => _isSaving = true);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kShowManualBtn, _showManualButton);
    await prefs.setInt(_kAutoIntervalMin, _intervalMinutes);

    // Re-register WorkManager with new interval
    await _reRegisterWorkManager();

    if (mounted) {
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✓ Pengaturan disimpan'),
          backgroundColor: Color(0xFF006c49),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _reRegisterWorkManager() async {
    await Workmanager().cancelAll();

    // WorkManager minimum is 15 minutes on Android
    final effectiveMinutes = _intervalMinutes < 15 ? 15 : _intervalMinutes;
    final delay = Duration(minutes: effectiveMinutes);

    await Workmanager().registerPeriodicTask(
      "dailyLocationTask",
      "dailyLocationFetch",
      frequency: Duration(minutes: effectiveMinutes),
      initialDelay: delay,
      existingWorkPolicy: ExistingPeriodicWorkPolicy.replace,
      constraints: Constraints(networkType: NetworkType.connected),
    );

    // Sync UI countdown with new WorkManager schedule
    await LocationService.scheduleNextAutoTime(DateTime.now().add(delay));
  }

  /// Show custom wheel-based duration picker
  Future<void> _pickDuration() async {
    int selectedHours = _intervalMinutes ~/ 60;
    int selectedMinutes = _intervalMinutes % 60;

    // Clamp to valid ranges
    if (selectedHours > 23) selectedHours = 23;
    if (selectedMinutes > 59) selectedMinutes = 59;

    final result = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _surfaceContainerLowest,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => _DurationPickerSheet(
        initialHours: selectedHours,
        initialMinutes: selectedMinutes,
      ),
    );

    if (result != null && result > 0) {
      setState(() => _intervalMinutes = result);
    }
  }

  String _formatInterval(int minutes) {
    if (minutes < 60) return '$minutes menit';
    final h = minutes ~/ 60;
    final m = minutes % 60;
    if (m == 0) return '$h jam';
    return '$h jam $m menit';
  }

  String _nextAutoLabel() {
    final now = DateTime.now();
    final next = now.add(Duration(minutes: _intervalMinutes));
    final h = next.hour.toString().padLeft(2, '0');
    final m = next.minute.toString().padLeft(2, '0');
    return 'Berikutnya sekitar pukul $h:$m';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _background,
      appBar: AppBar(
        backgroundColor: _surfaceContainerLowest,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: _onSurface),
          onPressed: () => Navigator.pop(context, true), // true = refresh
        ),
        title: const Text(
          'Pengaturan',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: _onSurface,
          ),
        ),
        actions: [
          _isSaving
              ? const Padding(
                  padding: EdgeInsets.all(16),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child:
                        CircularProgressIndicator(color: _primary, strokeWidth: 2),
                  ),
                )
              : TextButton(
                  onPressed: _saveSettings,
                  child: const Text('Simpan',
                      style: TextStyle(
                          color: _primary, fontWeight: FontWeight.w600)),
                ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // ─── Section: Tombol Manual ───────────────────────────────────────
          _sectionLabel('Tombol Catat Manual'),
          const SizedBox(height: 10),
          _settingCard(
            children: [
              _switchRow(
                icon: Icons.touch_app_outlined,
                iconColor: _primary,
                title: 'Tampilkan Tombol Catat Sekarang',
                subtitle:
                    'Tombol biru di bagian bawah layar Timeline',
                value: _showManualButton,
                onChanged: (v) => setState(() => _showManualButton = v),
              ),
            ],
          ),

          const SizedBox(height: 28),

          // ─── Section: Auto-Tracking ───────────────────────────────────────
          _sectionLabel('Jadwal Auto-Tracking'),
          const SizedBox(height: 10),
          _settingCard(
            children: [
              // Interval row (tappable)
              InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: _pickDuration,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: _secondary.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.timer_outlined,
                            color: _secondary, size: 20),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Interval Pencatatan Otomatis',
                              style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: _onSurface),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              _nextAutoLabel(),
                              style: const TextStyle(
                                  fontSize: 12, color: _onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: _primary.withOpacity(0.07),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: _primary.withOpacity(0.2)),
                        ),
                        child: Text(
                          _formatInterval(_intervalMinutes),
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: _primary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Icon(Icons.chevron_right,
                          color: _onSurfaceVariant, size: 20),
                    ],
                  ),
                ),
              ),

              Divider(height: 1, color: _outlineVariant.withOpacity(0.4)),

              // Info note
              Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline,
                        size: 14, color: _onSurfaceVariant),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Android membatasi background task minimum 15 menit. Interval di bawah 15 menit hanya berlaku saat aplikasi terbuka.',
                        style: TextStyle(
                            fontSize: 11,
                            color: _onSurfaceVariant,
                            height: 1.5),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 28),

          // ─── Section: Tindakan ────────────────────────────────────────────
          _sectionLabel('Tindakan'),
          const SizedBox(height: 10),
          _settingCard(
            children: [
              InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () async {
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Catat Lokasi Sekarang?'),
                      content: const Text(
                          'Lokasi Anda saat ini akan dicatat sebagai entri Auto.'),
                      actions: [
                        TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: const Text('Batal')),
                        TextButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            child: const Text('Catat',
                                style: TextStyle(color: _primary))),
                      ],
                    ),
                  );
                  if (confirmed == true && mounted) {
                    try {
                      await LocationService.recordLocation(isManual: false);
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('✓ Lokasi otomatis dicatat!'),
                            backgroundColor: _secondary,
                          ),
                        );
                      }
                    } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Gagal: $e'),
                            backgroundColor: Colors.red.shade700,
                          ),
                        );
                      }
                    }
                  }
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: _primary.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.gps_fixed,
                            color: _primary, size: 20),
                      ),
                      const SizedBox(width: 14),
                      const Expanded(
                        child: Text(
                          'Jalankan Auto-Tracking Sekarang',
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: _onSurface),
                        ),
                      ),
                      const Icon(Icons.chevron_right,
                          color: _onSurfaceVariant, size: 20),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _sectionLabel(String label) {
    return Text(
      label.toUpperCase(),
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: _onSurfaceVariant,
        letterSpacing: 0.8,
      ),
    );
  }

  Widget _settingCard({required List<Widget> children}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: _surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(children: children),
    );
  }

  Widget _switchRow({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: _onSurface)),
                const SizedBox(height: 2),
                Text(subtitle,
                    style: const TextStyle(
                        fontSize: 12, color: _onSurfaceVariant)),
              ],
            ),
          ),
          Switch.adaptive(
            value: value,
            onChanged: onChanged,
            activeColor: _primary,
          ),
        ],
      ),
    );
  }
}

// ─── Duration Picker Bottom Sheet ────────────────────────────────────────────
class _DurationPickerSheet extends StatefulWidget {
  final int initialHours;
  final int initialMinutes;

  const _DurationPickerSheet({
    required this.initialHours,
    required this.initialMinutes,
  });

  @override
  State<_DurationPickerSheet> createState() => _DurationPickerSheetState();
}

class _DurationPickerSheetState extends State<_DurationPickerSheet> {
  late int _selectedHours;
  late int _selectedMinutes;

  @override
  void initState() {
    super.initState();
    _selectedHours = widget.initialHours;
    _selectedMinutes = widget.initialMinutes;
  }

  int get _totalMinutes => _selectedHours * 60 + _selectedMinutes;

  String _formatPreview() {
    final total = _totalMinutes;
    if (total == 0) return 'Tidak valid (minimum 1 menit)';
    if (total < 60) return 'Setiap $total menit';
    final h = total ~/ 60;
    final m = total % 60;
    if (m == 0) return 'Setiap $h jam';
    return 'Setiap $h jam $m menit';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: _outlineVariant,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Pilih Interval Auto-Tracking',
            style: TextStyle(
                fontSize: 17, fontWeight: FontWeight.w700, color: _onSurface),
          ),
          const SizedBox(height: 6),
          Text(
            _formatPreview(),
            style: TextStyle(
              fontSize: 13,
              color: _totalMinutes > 0 ? _primary : Colors.red.shade600,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 24),

          // ─── Wheel Pickers ──────────────────────────────────────────────
          Container(
            height: 200,
            decoration: BoxDecoration(
              color: _surfaceContainerLow,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                // Hours wheel
                Expanded(
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 12, bottom: 4),
                        child: Text('Jam',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: _onSurfaceVariant)),
                      ),
                      Expanded(
                        child: CupertinoPicker(
                          scrollController: FixedExtentScrollController(
                              initialItem: _selectedHours),
                          itemExtent: 44,
                          onSelectedItemChanged: (i) =>
                              setState(() => _selectedHours = i),
                          selectionOverlay: _SelectionHighlight(),
                          children: List.generate(
                            24,
                            (i) => Center(
                              child: Text(
                                i.toString().padLeft(2, '0'),
                                style: const TextStyle(
                                  fontSize: 26,
                                  fontWeight: FontWeight.w600,
                                  color: _onSurface,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Separator
                Padding(
                  padding: const EdgeInsets.only(top: 24),
                  child: Text(':',
                      style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w700,
                          color: _onSurface)),
                ),

                // Minutes wheel
                Expanded(
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 12, bottom: 4),
                        child: Text('Menit',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: _onSurfaceVariant)),
                      ),
                      Expanded(
                        child: CupertinoPicker(
                          scrollController: FixedExtentScrollController(
                              initialItem: _selectedMinutes),
                          itemExtent: 44,
                          onSelectedItemChanged: (i) =>
                              setState(() => _selectedMinutes = i),
                          selectionOverlay: _SelectionHighlight(),
                          children: List.generate(
                            60,
                            (i) => Center(
                              child: Text(
                                i.toString().padLeft(2, '0'),
                                style: const TextStyle(
                                  fontSize: 26,
                                  fontWeight: FontWeight.w600,
                                  color: _onSurface,
                                ),
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

          const SizedBox(height: 24),

          // Quick presets
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _preset('1 mnt', 1),
              _preset('5 mnt', 5),
              _preset('15 mnt', 15),
              _preset('30 mnt', 30),
              _preset('1 jam', 60),
              _preset('6 jam', 360),
              _preset('12 jam', 720),
              _preset('24 jam', 1440),
            ],
          ),

          const SizedBox(height: 24),

          // Confirm button
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor:
                    _totalMinutes > 0 ? _primary : _outlineVariant,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: _totalMinutes > 0
                  ? () => Navigator.pop(context, _totalMinutes)
                  : null,
              child: Text(
                _totalMinutes > 0 ? 'Terapkan' : 'Pilih Durasi Valid',
                style:
                    const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _preset(String label, int minutes) {
    final isSelected = _totalMinutes == minutes;
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedHours = minutes ~/ 60;
          _selectedMinutes = minutes % 60;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? _primary : _surfaceContainerLowest,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? _primary : _outlineVariant.withOpacity(0.5),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: isSelected ? Colors.white : _onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

// ─── Custom selection overlay for CupertinoPicker ────────────────────────────
class _SelectionHighlight extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Expanded(child: SizedBox()),
        Container(height: 44, color: _primary.withOpacity(0.08)),
        const Expanded(child: SizedBox()),
      ],
    );
  }
}

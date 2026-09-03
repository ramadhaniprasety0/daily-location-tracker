import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class LocationService {
  static const _kLastAutoKey = 'last_auto_recorded_at';
  static const _kOfflineKey = 'offline_locations';

  /// Save the timestamp of the last auto-recording
  static Future<void> saveLastAutoTime(DateTime time) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kLastAutoKey, time.toIso8601String());
  }

  /// Get the timestamp of the last auto-recording (null if never)
  static Future<DateTime?> getLastAutoTime() async {
    final prefs = await SharedPreferences.getInstance();
    final str = prefs.getString(_kLastAutoKey);
    if (str == null) return null;
    return DateTime.parse(str);
  }

  /// Get DateTime of next scheduled auto-record.
  static Future<DateTime> getNextAutoTime() async {
    final prefs = await SharedPreferences.getInstance();
    
    // If explicitly scheduled (e.g. by Settings or last auto run)
    final explicitNextStr = prefs.getString('next_auto_time');
    if (explicitNextStr != null) {
      final explicitNext = DateTime.parse(explicitNextStr);
      if (explicitNext.isAfter(DateTime.now())) {
        return explicitNext;
      }
    }
    
    // Fallback: now + interval
    final intervalMinutes = prefs.getInt('auto_interval_minutes') ?? 1440;
    return DateTime.now().add(Duration(minutes: intervalMinutes));
  }

  /// Explicitly schedule the next auto-record time (used by Settings & WorkManager)
  static Future<void> scheduleNextAutoTime(DateTime nextTime) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('next_auto_time', nextTime.toIso8601String());
  }

  // ─── OFFLINE BUFFERING ──────────────────────────────────────────────────────

  static Future<void> saveOfflineLocation(Map<String, dynamic> record) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_kOfflineKey) ?? [];
    record['is_offline'] = true; // Mark for UI
    list.add(jsonEncode(record));
    await prefs.setStringList(_kOfflineKey, list);
  }

  static Future<List<Map<String, dynamic>>> getOfflineLocations() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_kOfflineKey) ?? [];
    return list.map((e) => jsonDecode(e) as Map<String, dynamic>).toList();
  }

  static Future<void> syncOfflineLocations() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_kOfflineKey) ?? [];
    if (list.isEmpty) return;

    List<String> remaining = [];
    for (String itemStr in list) {
      try {
        final record = jsonDecode(itemStr) as Map<String, dynamic>;
        final dbRecord = Map<String, dynamic>.from(record)..remove('is_offline');
        await Supabase.instance.client.from('daily_locations').insert(dbRecord);
      } catch (e) {
        debugPrint('[LocationService] Failed to sync offline record: $e');
        remaining.add(itemStr);
      }
    }
    
    await prefs.setStringList(_kOfflineKey, remaining);
  }

  // ────────────────────────────────────────────────────────────────────────────

  /// Get unique device ID (stored in SharedPreferences)
  static Future<String> getDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    String? deviceId = prefs.getString('device_id');
    if (deviceId == null) {
      // Generate a simple unique ID for this installation
      deviceId = 'dev_${DateTime.now().millisecondsSinceEpoch}_${math.Random().nextInt(99999)}';
      await prefs.setString('device_id', deviceId);
    }
    return deviceId;
  }

  /// Reverse geocode using OpenStreetMap Nominatim
  static Future<String?> _getAddress(double lat, double lon) async {
    try {
      final url = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse?format=json&lat=$lat&lon=$lon&zoom=16&addressdetails=1',
      );
      final response = await http.get(url, headers: {
        'User-Agent': 'DailyLocationTrackerApp/1.0',
        'Accept-Language': 'id',
      }).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['display_name'] as String?;
      }
    } catch (e) {
      debugPrint('[LocationService] Geocoding failed: $e');
    }
    return null;
  }

  /// Record the current GPS location to Supabase.
  /// Throws an exception on failure so the UI can show feedback.
  static Future<void> recordLocation({bool isManual = false}) async {
    debugPrint('[LocationService] Starting recordLocation (manual=$isManual)');

    // 1. Check & request permission
    LocationPermission permission = await Geolocator.checkPermission();
    debugPrint('[LocationService] Permission status: $permission');

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        throw Exception('Izin lokasi ditolak');
      }
    }
    if (permission == LocationPermission.deniedForever) {
      throw Exception('Izin lokasi diblokir permanen. Aktifkan di Pengaturan HP.');
    }

    // 2. Check if location service is enabled
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw Exception('GPS tidak aktif. Nyalakan GPS di HP Anda.');
    }

    // 3. Get current position
    debugPrint('[LocationService] Getting GPS position...');
    final position = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    ).timeout(const Duration(seconds: 30));
    debugPrint('[LocationService] Got position: ${position.latitude}, ${position.longitude}');

    // 4. Reverse geocode via Nominatim (may return null, non-critical)
    final address = await _getAddress(position.latitude, position.longitude);
    debugPrint('[LocationService] Address: $address');

    // 5. Build record matching Supabase schema
    final now = DateTime.now();
    final deviceId = await getDeviceId();
    final dateKey =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final dayNames = [
      'Senin', 'Selasa', 'Rabu', 'Kamis', 'Jumat', 'Sabtu', 'Minggu'
    ];
    final dayName = dayNames[now.weekday - 1];

    final record = {
      'device_id': deviceId,
      'user_id': Supabase.instance.client.auth.currentUser?.id,
      'latitude': position.latitude,
      'longitude': position.longitude,
      'address': address,
      'is_manual': isManual,
      'recorded_at': now.toUtc().toIso8601String(),
      'date_key': dateKey,
      'day_name': dayName,
    };

    debugPrint('[LocationService] Inserting record: $record');

    // 6. Insert into Supabase (with offline fallback)
    try {
      await Supabase.instance.client.from('daily_locations').insert(record);
      debugPrint('[LocationService] Record inserted successfully!');
      // Sync any pending offline records if we have connection
      await syncOfflineLocations();
    } catch (e) {
      debugPrint('[LocationService] Insert failed, buffering offline: $e');
      await saveOfflineLocation(record);
      if (isManual) {
        throw Exception('Offline: Lokasi disimpan lokal & akan disinkronkan nanti.');
      }
    }

    // 7. Save last auto timestamp (only for automatic recordings)
    if (!isManual) {
      await saveLastAutoTime(now);
      final prefs = await SharedPreferences.getInstance();
      final interval = prefs.getInt('auto_interval_minutes') ?? 1440;
      await scheduleNextAutoTime(now.add(Duration(minutes: interval)));
      debugPrint('[LocationService] Saved last auto time: $now, next: ${now.add(Duration(minutes: interval))}');
    }
  }
}

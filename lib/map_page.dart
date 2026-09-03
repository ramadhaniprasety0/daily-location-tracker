import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as latlng;
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ─── Stitch AI Color Tokens ───────────────────────────────────────────────────
const Color _primary = Color(0xFF00288e);
const Color _surfaceContainerLowest = Color(0xFFffffff);
const Color _surfaceContainerLow = Color(0xFFf4f2fc);
const Color _onSurface = Color(0xFF1a1b22);
const Color _onSurfaceVariant = Color(0xFF444653);
const Color _outlineVariant = Color(0xFFc4c5d5);
const Color _secondary = Color(0xFF006c49);

class MapPage extends StatefulWidget {
  final List<Map<String, dynamic>> locations;

  const MapPage({super.key, required this.locations});

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  final MapController _mapController = MapController();
  Map<String, dynamic>? _selectedLocation;
  bool _showPolyline = true;

  List<Map<String, dynamic>> get _sortedLocations {
    final sorted = List<Map<String, dynamic>>.from(widget.locations);
    sorted.sort((a, b) => DateTime.parse(a['recorded_at'])
        .compareTo(DateTime.parse(b['recorded_at'])));
    return sorted;
  }

  latlng.LatLng? get _centerPoint {
    if (widget.locations.isEmpty) return null;
    final lat = widget.locations
            .map((l) => (l['latitude'] as num).toDouble())
            .reduce((a, b) => a + b) /
        widget.locations.length;
    final lon = widget.locations
            .map((l) => (l['longitude'] as num).toDouble())
            .reduce((a, b) => a + b) /
        widget.locations.length;
    return latlng.LatLng(lat, lon);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.locations.isEmpty) {
      return _buildEmptyState();
    }

    final sorted = _sortedLocations;
    final polylinePoints =
        sorted.map((l) => latlng.LatLng(
          (l['latitude'] as num).toDouble(),
          (l['longitude'] as num).toDouble(),
        )).toList();
    final center = _centerPoint!;

    return Stack(
      children: [
        // ─── Map ───────────────────────────────────────────────────────────
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: center,
            initialZoom: 13,
            onTap: (_, __) => setState(() => _selectedLocation = null),
          ),
          children: [
            // OpenStreetMap tile layer
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.example.daily_location_tracker',
              maxZoom: 19,
            ),

            // Polyline connecting all points chronologically
            if (_showPolyline && polylinePoints.length > 1)
              PolylineLayer<Object>(
                polylines: [
                  Polyline(
                    points: polylinePoints,
                    strokeWidth: 2.5,
                    color: _primary.withOpacity(0.5),
                  ),
                ],
              ),

            // Markers
            MarkerLayer(
              markers: sorted.asMap().entries.map((entry) {
                final index = entry.key;
                final loc = entry.value;
                final isLatest = index == sorted.length - 1;
                final isSelected = _selectedLocation == loc;

                return Marker(
                  point: latlng.LatLng(
                    (loc['latitude'] as num).toDouble(),
                    (loc['longitude'] as num).toDouble(),
                  ),
                  width: isLatest ? 44 : 32,
                  height: isLatest ? 52 : 40,
                  child: GestureDetector(
                    onTap: () {
                      setState(() => _selectedLocation = loc);
                      _mapController.move(
                        latlng.LatLng(
                          (loc['latitude'] as num).toDouble(),
                          (loc['longitude'] as num).toDouble(),
                        ),
                        14,
                      );
                    },
                    child: Column(
                      children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: isLatest ? 36 : 28,
                          height: isLatest ? 36 : 28,
                          decoration: BoxDecoration(
                            color: isSelected
                                ? Colors.orange
                                : isLatest
                                    ? _primary
                                    : _primary.withOpacity(0.6),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.white,
                              width: isLatest ? 3 : 2,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: (isLatest ? _primary : Colors.black)
                                    .withOpacity(0.3),
                                blurRadius: 8,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          child: Icon(
                            isLatest ? Icons.my_location : Icons.location_on,
                            color: Colors.white,
                            size: isLatest ? 18 : 14,
                          ),
                        ),
                        // Triangle pointer
                        CustomPaint(
                          size: const Size(10, 6),
                          painter: _TrianglePainter(
                            color: isSelected
                                ? Colors.orange
                                : isLatest
                                    ? _primary
                                    : _primary.withOpacity(0.6),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ),

        // ─── Top Controls ──────────────────────────────────────────────────
        Positioned(
          top: 12,
          left: 12,
          right: 12,
          child: Row(
            children: [
              // Location count pill
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(999),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.12),
                      blurRadius: 12,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.location_on, color: _primary, size: 16),
                    const SizedBox(width: 6),
                    Text(
                      "${widget.locations.length} Lokasi",
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: _onSurface,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              // Toggle polyline button
              GestureDetector(
                onTap: () => setState(() => _showPolyline = !_showPolyline),
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: _showPolyline ? _primary : Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.12),
                        blurRadius: 12,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Icon(
                    Icons.route,
                    color: _showPolyline ? Colors.white : _onSurfaceVariant,
                    size: 20,
                  ),
                ),
              ),
            ],
          ),
        ),

        // ─── Zoom Controls ─────────────────────────────────────────────────
        Positioned(
          right: 12,
          bottom: _selectedLocation != null ? 220 : 24,
          child: Column(
            children: [
              _mapButton(Icons.add, () {
                _mapController.move(
                    _mapController.camera.center,
                    _mapController.camera.zoom + 1);
              }),
              const SizedBox(height: 8),
              _mapButton(Icons.remove, () {
                _mapController.move(
                    _mapController.camera.center,
                    _mapController.camera.zoom - 1);
              }),
              const SizedBox(height: 8),
              _mapButton(Icons.center_focus_strong, () {
                _mapController.move(center, 13);
              }),
            ],
          ),
        ),

        // ─── Info Card (when marker tapped) ───────────────────────────────
        if (_selectedLocation != null)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: _buildInfoCard(_selectedLocation!),
          ),
      ],
    );
  }

  Widget _mapButton(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.12),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Icon(icon, color: _onSurfaceVariant, size: 20),
      ),
    );
  }

  Widget _buildInfoCard(Map<String, dynamic> loc) {
    final recordedAt = DateTime.parse(loc['recorded_at']).toLocal();
    final dateStr =
        DateFormat('EEEE, dd MMMM yyyy', 'id_ID').format(recordedAt);
    final timeStr = DateFormat('HH:mm').format(recordedAt);
    final isManual = loc['is_manual'] == true;

    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 24,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: _outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 14),
          // Date & badge row
          Row(
            children: [
              const Icon(Icons.calendar_today_outlined,
                  size: 14, color: _onSurfaceVariant),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  "$dateStr • $timeStr",
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: _onSurfaceVariant,
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: isManual
                      ? const Color(0xFFe3e1eb)
                      : const Color(0xFF6cf8bb).withOpacity(0.25),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  isManual ? "Manual" : "Auto",
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: isManual ? _onSurfaceVariant : _secondary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Address
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.location_on, size: 16, color: _primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  loc['address'] ?? "Alamat tidak tersedia",
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: _onSurface,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Coordinates
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: _surfaceContainerLow,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              "Lat: ${loc['latitude']?.toStringAsFixed(6)},  Long: ${loc['longitude']?.toStringAsFixed(6)}",
              style: const TextStyle(
                fontSize: 11,
                fontFamily: 'monospace',
                color: _onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.map_outlined, size: 72, color: _outlineVariant),
          const SizedBox(height: 16),
          const Text(
            "Belum Ada Data Peta",
            style: TextStyle(
                fontSize: 18, fontWeight: FontWeight.w600, color: _onSurface),
          ),
          const SizedBox(height: 8),
          const Text(
            "Catat lokasi pertama Anda untuk melihat\nriwayat perjalanan di peta.",
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: _onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

// ─── Triangle painter for marker pointer ──────────────────────────────────────
class _TrianglePainter extends CustomPainter {
  final Color color;
  const _TrianglePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final path = ui.Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_TrianglePainter oldDelegate) =>
      oldDelegate.color != color;
}

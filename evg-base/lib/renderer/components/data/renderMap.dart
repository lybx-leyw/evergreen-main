/// HTML render: renderMap
import 'dart:convert';
import '../shared/html_helpers.dart';

String renderMap(Map<String, dynamic> comp) {
  final cfg = (comp['config'] as Map<String, dynamic>? ?? {})['map'] as Map<String, dynamic>? ?? {};
  final center = cfg['center'] as Map<String, dynamic>? ?? {};
  final lat = center['lat'] ?? '39.9042';
  final lng = center['lng'] ?? '116.4074';

  return '''
<div class="evg-comp evg-comp-map">
  <div class="evg-map-placeholder">
    <div class="evg-map-pin">📍</div>
    <div class="evg-map-coords">$lat, $lng</div>
    <div class="evg-map-zoom">
      <button>+</button><button>−</button>
    </div>
  </div>
</div>''';
}

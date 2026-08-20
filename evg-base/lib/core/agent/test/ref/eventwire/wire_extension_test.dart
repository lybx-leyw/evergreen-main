/// Port of reasonix/internal/eventwire/wire_extension_test.go.
///
/// Translation notes:
/// - JSON assertions use jsonEncode + substring checks as in the Go source.
/// - ExtensionFormField.Default (Go json.RawMessage) is carried as raw JSON
///   text in Dart; toJson decodes it back so the wire shape matches.
library;

import 'dart:convert';

import 'package:test/test.dart';

import '../../../ref/event/event.dart' as event;
import '../../../ref/eventwire/wire.dart' as wire;

void main() {
  group('ToWire extension surface payloads', () {
    test('status rides ExtensionStatus', () {
      final w = wire.toWire(event.Event()
        ..kind = event.Kind.extensionStatus
        ..extension = event.ExtensionSurfacePayload()
        ..pluginId = 'alpha'
        ..surfaceId = 's1'
        ..sessionId = 'sess'
        ..generation = 7
        ..kind = event.extensionSurfaceStatus
        ..status = event.ExtensionStatusView()
        ..label = 'working'
        ..detail = 'half'
        ..severity = 'warn'
        ..progress = 0.5);
      final s = jsonEncode(w.toJson());
      for (final want in [
        '"kind":"extension_status"',
        '"extension":{"pluginId":"alpha","surfaceId":"s1","sessionId":"sess","generation":7,"kind":"status"',
        '"status":{"label":"working","detail":"half","severity":"warn","progress":0.5}',
      ]) {
        expect(s, contains(want));
      }
    });

    test('card rides ExtensionSurface', () {
      final w = wire.toWire(event.Event()
        ..kind = event.Kind.extensionSurface
        ..extension = event.ExtensionSurfacePayload()
        ..pluginId = 'alpha'
        ..surfaceId = 'c1'
        ..kind = event.extensionSurfaceCard
        ..card = event.ExtensionCardView()
        ..title = 'T'
        ..markdown = '**m**'
        ..text = 'x'
        ..progress = 0.5
        ..fields = [
          event.ExtensionKeyValue()
            ..key = 'k'
            ..value = 'v',
        ]
        ..actions = [
          event.ExtensionActionRef()
            ..actionId = 'act1'
            ..label = 'go',
        ]);
      final s = jsonEncode(w.toJson());
      for (final want in [
        '"kind":"extension_surface"',
        '"kind":"card"',
        '"card":{"title":"T","markdown":"**m**","text":"x","fields":[{"key":"k","value":"v"}],"progress":0.5,"actions":[{"actionId":"act1","label":"go"}]}',
      ]) {
        expect(s, contains(want));
      }
    });

    test('form rides ExtensionSurface', () {
      final w = wire.toWire(event.Event()
        ..kind = event.Kind.extensionSurface
        ..extension = event.ExtensionSurfacePayload()
        ..pluginId = 'alpha'
        ..surfaceId = 'f1'
        ..kind = event.extensionSurfaceForm
        ..form = event.ExtensionFormView()
        ..title = 'f'
        ..message = 'm'
        ..fields = [
          event.ExtensionFormField()
            ..key = 'field1'
            ..label = 'L'
            ..kind = 'multiselect'
            ..options = ['a', 'b']
            ..$default = 'a'
            ..required = true,
        ]);
      final s = jsonEncode(w.toJson());
      for (final want in [
        '"kind":"extension_surface"',
        '"kind":"form"',
        '"form":{"title":"f","message":"m","fields":[{"key":"field1","label":"L","kind":"multiselect","options":["a","b"],"default":"a","required":true}]}',
      ]) {
        expect(s, contains(want));
      }
    });

    test('notification rides ExtensionSurface', () {
      final w = wire.toWire(event.Event()
        ..kind = event.Kind.extensionSurface
        ..extension = event.ExtensionSurfacePayload()
        ..pluginId = 'alpha'
        ..surfaceId = 'n1'
        ..kind = event.extensionSurfaceNotification
        ..notification = event.ExtensionNotificationView()
        ..title = 'n'
        ..body = 'b'
        ..severity = 'error');
      final s = jsonEncode(w.toJson());
      for (final want in [
        '"kind":"extension_surface"',
        '"kind":"notification"',
        '"notification":{"title":"n","body":"b","severity":"error"}',
      ]) {
        expect(s, contains(want));
      }
    });
  });

  group('ToWire extension nil payload', () {
    test('omits the extension field', () {
      final s = jsonEncode(wire
          .toWire(event.Event()..kind = event.Kind.extensionStatus)
          .toJson());
      expect(s, isNot(contains('"extension"')));
    });
  });
}

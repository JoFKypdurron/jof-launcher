import 'package:flutter_test/flutter_test.dart';
import 'package:joflauncher/services/server_tracker_service.dart';

void main() {
  group('ServerTrackerData', () {
    test('fromJson parses correctly with the actual API structure', () {
      final jsonResponse = {
        "status": "OK",
        "data": {
          "server": {
            "mapname": "MP/FFA3",
            "maxclients": "32",
            "status": "ONLINE",
            "statuscolor": "lime",
            "ip": "135.125.145.49",
            "port": "29070",
            "clients": 28
          },
          "players": [
            {"name": "^0Darth_^4^2^1Seraf"},
            {"name": "^2^^0jof^2'^0i^2.^7toad^2!"}
          ],
          "graphdata": [28, 22]
        }
      };

      // In the service, it should pass data['data'] to fromJson or handle it there.
      // Let's assume we update fromJson to take the whole 'data' object.
      final data = ServerTrackerData.fromJson(jsonResponse['data'] as Map<String, dynamic>);

      expect(data.online, isTrue);
      expect(data.map, equals('MP/FFA3'));
      expect(data.clients, equals(28));
      expect(data.maxClients, equals(32));
      expect(data.players, contains('^0Darth_^4^2^1Seraf'));
      expect(data.players, contains("^2^^0jof^2'^0i^2.^7toad^2!"));
      expect(data.players.length, equals(2));
    });

    test('fromJson handles offline status correctly', () {
      final jsonResponse = {
        "status": "OK",
        "data": {
          "server": {
            "mapname": "unknown",
            "maxclients": "32",
            "status": "OFFLINE",
            "statuscolor": "red",
            "ip": "135.125.145.49",
            "port": "29070",
            "clients": 0
          },
          "players": [],
          "graphdata": []
        }
      };

      final data = ServerTrackerData.fromJson(jsonResponse['data'] as Map<String, dynamic>);

      expect(data.online, isFalse);
      expect(data.clients, equals(0));
      expect(data.players, isEmpty);
    });
  });
}

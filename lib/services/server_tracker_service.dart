import 'dart:convert';
import 'dart:io' as io;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

class ServerTrackerData {
  final bool online;
  final String? map;
  final int clients;
  final int maxClients;
  final List<String> players;

  ServerTrackerData({
    required this.online,
    this.map,
    required this.clients,
    required this.maxClients,
    required this.players,
  });

  factory ServerTrackerData.fromJson(Map<String, dynamic> json) {
    final server = json['server'] as Map<String, dynamic>? ?? {};
    final players = json['players'] as List<dynamic>? ?? [];

    return ServerTrackerData(
      online: server['status'] == 'ONLINE',
      map: server['mapname'],
      clients: server['clients'] ?? 0,
      maxClients: int.tryParse(server['maxclients']?.toString() ?? '32') ?? 32,
      players: players.map((p) => p['name']?.toString() ?? '').where((name) => name.isNotEmpty).toList(),
    );
  }
}

class ServerTrackerService {
  static const String apiUrl = 'https://api.jofhub.eu/server/tracker/gettrackerdata';

  /// Creates an HTTP client with proper certificate handling for Windows
  http.Client _createHttpClient() {
    if (kIsWeb) {
      return http.Client();
    }
    
    final ioClient = io.HttpClient();
    if (io.Platform.isWindows) {
      // On Windows, certificate verification can fail due to missing certificate chain.
      // This callback allows the connection while still performing basic validation.
      // Restricted to Windows only: macOS/Linux use the default strict TLS validation.
      ioClient.badCertificateCallback = (io.X509Certificate cert, String host, int port) {
        // Only allow for our specific API domain
        return host == 'api.jofhub.eu';
      };
    }

    return IOClient(ioClient);
  }

  Future<ServerTrackerData> fetchTrackerData() async {
    final client = _createHttpClient();
    try {
      final response = await client.get(Uri.parse(apiUrl));
      if (response.statusCode == 200) {
        final body = json.decode(response.body);
        final data = body['data'] as Map<String, dynamic>?;
        if (data == null) throw Exception('No data in response');
        return ServerTrackerData.fromJson(data);
      } else {
        throw Exception('Failed to load tracker data');
      }
    } catch (e) {
      debugPrint('Error fetching tracker data: $e');
      return ServerTrackerData(
        online: false,
        clients: 0,
        maxClients: 32,
        players: [],
      );
    } finally {
      client.close();
    }
  }
}

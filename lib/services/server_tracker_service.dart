import 'dart:convert';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;

import 'secure_http_client.dart';

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

  http.Client _createHttpClient() => createSecureHttpClient();

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

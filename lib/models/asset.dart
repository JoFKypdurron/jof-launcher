class Asset {
  final int id;
  final String name;
  final int size;
  final String hash;
  final int groupId;
  final String description;
  final String targetFolder;
  final String localFolder;
  final DateTime lastUpdate;

  Asset({
    required this.id,
    required this.name,
    required this.size,
    required this.hash,
    required this.groupId,
    required this.description,
    required this.targetFolder,
    required this.localFolder,
    required this.lastUpdate,
  });

  factory Asset.fromJson(Map<String, dynamic> json) {
    return Asset(
      id: json['id'] is int ? json['id'] : int.tryParse(json['id']?.toString() ?? '0') ?? 0,
      name: json['name']?.toString() ?? '',
      size: json['size'] is int ? json['size'] : int.tryParse(json['size']?.toString() ?? '0') ?? 0,
      hash: json['hash']?.toString() ?? '',
      groupId: json['groupid'] is int ? json['groupid'] : int.tryParse(json['groupid']?.toString() ?? '0') ?? 0,
      description: json['description']?.toString() ?? '',
      targetFolder: json['targetfolder']?.toString() ?? '',
      localFolder: json['localfolder']?.toString() ?? '',
      lastUpdate: json['lastupdate'] != null 
          ? DateTime.parse(json['lastupdate'].toString()) 
          : DateTime.now(),
    );
  }

  String get downloadUrl => Uri.https('jofhub.eu', '/apps/cloud/repository/$localFolder/$name').toString();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Asset && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}

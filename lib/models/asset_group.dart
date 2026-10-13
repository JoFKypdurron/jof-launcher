import 'asset.dart';

class AssetGroup {
  final int id;
  final String name;
  final String description;
  final String category;
  final String targetFolder;
  final bool isRequired;
  final String? dependsOn;
  final String? paramstring;
  final List<Asset> assets;

  AssetGroup({
    required this.id,
    required this.name,
    required this.description,
    required this.category,
    required this.targetFolder,
    required this.assets,
    this.isRequired = false,
    this.dependsOn,
    this.paramstring,
  });

  factory AssetGroup.fromJson(Map<String, dynamic> json) {
    var assetList = (json['assets'] as List?) ?? [];
    List<Asset> assets = assetList.map((i) => Asset.fromJson(i)).toList();

    return AssetGroup(
      id: json['id'] is int ? json['id'] : int.tryParse(json['id']?.toString() ?? '0') ?? 0,
      name: json['name']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      category: json['category']?.toString() ?? '',
      targetFolder: json['targetfolder']?.toString() ?? '',
      isRequired: json['type']?.toString() == 'REQUIRED',
      dependsOn: json['dependson']?.toString(),
      paramstring: json['paramstring']?.toString(),
      assets: assets,
    );
  }
}

import 'package:flutter/services.dart';
import 'package:isar/isar.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sembast/sembast_io.dart';
import 'package:sembast/utils/value_utils.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sync_db/src/model.dart';
import 'package:sync_db/src/services/service_point.dart';
import 'package:sync_db/src/storages/transfer_map.dart';
import 'package:sync_db/src/sync_db.dart';
import 'package:universal_io/io.dart';
import 'package:universal_platform/universal_platform.dart';
import 'package:sembast/sembast.dart' as sembast;

class IsarDatabase {
  static const appVersionKey = 'app_version';
  Future<void> init(
    Map<CollectionSchema<dynamic>, Model Function()> models, {
    String dbAssetPath = 'assets/db',
    String? version,
    List<String>? manifest,
  }) async {
    models[ServicePointSchema] = () => ServicePoint();
    models[TransferMapSchema] = () => TransferMap();

    String? dir;
    if (!UniversalPlatform.isWeb) {
      // get document directory
      final documentPath = await getApplicationSupportDirectory();
      await documentPath.create(recursive: true);
      dir = documentPath.path;
    }

    final isar = await Isar.open(
      models.keys.toList(),
      directory: dir,
    );

    Sync.shared.db = isar;
    Sync.shared.modelHandlers = {
      for (var v in models.values) v().tableName: v()
    };
    models.values.forEach((element) {
      final instance = element();
      Sync.shared.modelInstances[instance.tableName] = () => instance;
    });

    // copy database
    if (dbAssetPath.isNotEmpty != true ||
        version?.isNotEmpty != true ||
        manifest?.isNotEmpty != true) {
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final oldVersion = prefs.getString(appVersionKey);
    if (oldVersion != version) {
      // do copy from asset
      final futures = <Future>[];
      for (final asset in manifest!) {
        if (asset.startsWith(dbAssetPath)) {
          final fileName = basename(asset);
          print('copy database $fileName');
          final targetPath = dir == null ? fileName : join(dir, fileName);
          futures.add(_copySnapshotTable(
              asset, targetPath, basenameWithoutExtension(asset)));
        }
      }

      await Future.wait(futures);
      await prefs.setString(appVersionKey, version!);
      print('copy done');
    }
  }

  Future<void> _copySnapshotTable(
      String assetPath, String targetPath, String tableName) async {
    try {
      final assetContent = await rootBundle.load(assetPath);
      final targetFile = File(targetPath);
      if (await targetFile.exists()) {
        await targetFile.delete();
      }
      final bytes = assetContent.buffer
          .asUint8List(assetContent.offsetInBytes, assetContent.lengthInBytes);
      await targetFile.writeAsBytes(bytes);
      final db = await databaseFactoryIo.openDatabase(targetPath);
      final store = sembast.StoreRef.main();
      final finder = sembast.Finder();
      final records = await store.find(db, finder: finder);
      final recordMaps = records
          .map((e) => Map<dynamic, dynamic>.from(cloneMap(e.value)))
          .toList();
      await db.close();
      print('close db $tableName, there are ${recordMaps.length} records');
      final modelHandler = Sync.shared.modelInstances[tableName];
      if (modelHandler == null) {
        print('model handler $tableName not exist');
        return;
      }

      await Sync.shared.db.writeTxn(() async {
        for (final record in recordMaps) {
          print('to save $tableName ${record['id']} ');
          final entry = modelHandler();
          await entry.init();
          await entry.setMap(record);
          print('prepare to save $tableName ${entry.id}');
          await entry.save(syncToService: false, runInTransaction: false);
          print('save done $tableName ${entry.id}');
        }
      });
    } catch (e, stacktrace) {
      Sync.shared.logger
          ?.e('Copy snapshot $assetPath failed $e', e, stacktrace);
    }
  }
}

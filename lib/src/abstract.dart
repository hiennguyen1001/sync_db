import 'package:flutter/foundation.dart';
import 'package:sync_db/sync_db.dart';

const statusKey = '_status';
const idKey = 'id';
const updatedKey = 'updatedAt';
const createdKey = 'createdAt';
const deletedKey = 'deletedAt';

abstract class UserSession {
  set token(String token);
  Future<void> forceRefresh();
  Future<List<ServicePoint>> servicePoints();
  Future<List<ServicePoint>> servicePointsForTable(String table);
  Future<bool> hasSignedIn();
  String get role;
  Future<void> signout();
}

abstract class Database {
  Future<void> save(Model model, {bool syncToService});

  Future<void> saveMap(String tableName, Map map, {dynamic transaction});

  bool hasTable(String tableName);

  dynamic all(String modelName, Function instantiateModel);

  dynamic find(String modelName, String id, Model model);
  dynamic findMap(String modelName, String id, {dynamic transaction});

  dynamic query<T>(Query query, {dynamic transaction});

  dynamic queryMap(Query query, {dynamic transaction});

  Future<void> delete(Model model);

  Future<void> deleteLocal(String modelName, String id);

  Future<void> runInTransaction(String tableName, Function action);

  /// clear all data in all tables
  Future<void> cleanDatabase();
}

abstract class Model extends ChangeNotifier {
  Database get database => Sync.shared.local;

  DateTime createdAt;
  DateTime deletedAt;
  String id;
  DateTime updatedAt;

  Map<String, dynamic> get map {
    var map = <String, dynamic>{};
    map[idKey] = id;
    if (createdAt != null) {
      map[createdKey] = createdAt.millisecondsSinceEpoch ~/ 1000;
    }

    if (updatedAt != null) {
      map[updatedKey] = updatedAt.millisecondsSinceEpoch ~/ 1000;
    }

    if (deletedAt != null) {
      map[deletedKey] = deletedAt.millisecondsSinceEpoch;
    }

    return map;
  }

  set map(Map<String, dynamic> map) {
    id = map[idKey];
    if (map[createdKey] is int) {
      createdAt = DateTime.fromMillisecondsSinceEpoch(map[createdKey] * 1000);
    }

    if (map[updatedAt] is int) {
      updatedAt = DateTime.fromMillisecondsSinceEpoch(map[updatedAt] * 1000);
    }

    if (map[deletedKey] is int) {
      deletedAt = DateTime.fromMillisecondsSinceEpoch(map[deletedKey]);
    }
  }

  String get tableName => throw UnimplementedError();

  Future<void> save({bool syncToService = true}) async =>
      await database.save(this, syncToService: syncToService);

  Future<void> delete() async {
    deletedAt = await NetworkTime.shared.now;
    await save();
  }

  Future<void> deleteAll() async {
    var now = (await NetworkTime.shared.now).millisecondsSinceEpoch;
    await database.runInTransaction(tableName, (transaction) async {
      var list =
          await database.queryMap(Query(tableName), transaction: transaction);
      for (var item in list) {
        item[deletedKey] = now;
        await database.saveMap(tableName, item, transaction: transaction);
      }
    });
  }

  @override
  String toString() {
    return map.toString();
  }
}

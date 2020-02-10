import "abstract.dart";
import "query.dart";
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sembast/sembast.dart' as Sembast;
import 'package:sembast/sembast_io.dart';
import 'package:better_uuid/uuid.dart';

class SembastDatabase extends Database {
  static SembastDatabase shared;
  Sync _sync;
  Map<String, Sembast.Database> _db = {};
  //Map<String, List<String>> _dateTimeKeyNames = {};

  /// Connects sync to the Sembest Database
  /// Opens up each table connected to each model, which is stored in a separate file.
  static Future<void> config(Sync sync, List<Model> models) async {
    shared = SembastDatabase();
    shared._sync = sync;

    // get the application documents directory
    final dir = await getApplicationDocumentsDirectory();
    // make sure it exists
    await dir.create(recursive: true);
    final store = Sembast.StoreRef.main();

    // Open all databases
    for (final model in models) {
      final name = model.runtimeType.toString();
      final dbPath = join(dir.path, name + ".db");
      shared._db[name] = await databaseFactoryIo.openDatabase(dbPath);

      // Warms up the database so it can work later (seems to be a bug in Sembast)
      await store.record("Cold start").put(shared._db[name], "Warm up");
      await store.record("Cold start").delete(shared._db[name]);
    }
  }

  Future<void> save(Model model) async {
    // Get DB
    final name = model.runtimeType.toString();
    final db = _db[name];
    final store = Sembast.StoreRef.main();

    // Set id and createdAt if new record. ID is a random UUID
    final create = (model.id == null) || (model.createdAt == null);
    if (create) {
      model.id = Uuid.v4().toString();
      model.createdAt = DateTime.now();
    }

    // Export model as map and convert DateTime to int
    model.updatedAt = DateTime.now();
    final map = model.export();
    for (final entry in map.entries) {
      if (entry.value is DateTime) {
        map[entry.key] = (entry.value as DateTime).millisecondsSinceEpoch;
      }
    }
    map["_status"] = create ? "created" : "updated";

    // Store and then start the sync
    await store.record(model.id).put(db, map);
    //_sync.syncWrite(name);
  }

  Future<void> delete(Model model) async {}

  /// Get all model instances in a table
  Future<List<Model>> all(String modelName, Function instantiateModel) async {
    final store = Sembast.StoreRef.main();
    var records = await store.find(_db[modelName], finder: Sembast.Finder());

    List<Model> models = [];
    for (final record in records) {
      final model = instantiateModel();
      model.import(_fixType(record.value));
      models.add(model);
    }
    return Future<List<Model>>.value(models);
  }

  /// Find model instance by id
  Future<Model> find(String modelName, String id, Model model) async {
    final store = Sembast.StoreRef.main();
    final record = await store.record(id).get(_db[modelName]);
    model.import(_fixType(record));
    return Future<Model>.value(model);
  }

  /// Query the table with the Query class
  Future<List<T>> query<T>(String tableName, Query query) async {
    final store = Sembast.StoreRef.main();
    List<T> results = [];
    var finder = Sembast.Finder();

    // parse condition query
    if (query.condition != null) {
      if (query.condition is String) {
        // expect condition format likes a > b
        List<String> conditions = query.condition.split(' ');
        if (conditions.length == 3) {
          switch (conditions[1].trim()) {
            case '<':
              finder.filter = Sembast.Filter.lessThan(
                  conditions[0].trim(), conditions[2].trim());
              break;
            case '<=':
              finder.filter = Sembast.Filter.lessThanOrEquals(
                  conditions[0].trim(), conditions[2].trim());
              break;
            case '>':
              finder.filter = Sembast.Filter.greaterThan(
                  conditions[0].trim(), conditions[2].trim());
              break;
            case '>=':
              finder.filter = Sembast.Filter.greaterThanOrEquals(
                  conditions[0].trim(), conditions[2].trim());
              break;
          }
        }
      } else if (query.condition is Map) {
        Map conditions = query.condition;
        // AND query conditions
        if (conditions.length > 1) {
          List<Sembast.Filter> filters = List<Sembast.Filter>();
          conditions.forEach((key, value) {
            filters.add(Sembast.Filter.equals(key, value));
          });

          finder.filter = Sembast.Filter.and(filters);
        } else {
          var entry = conditions.entries.toList()[0];
          finder.filter = Sembast.Filter.equals(entry.key, entry.value);
        }
      }
    }

    // query order
    if (query.ordering != null) {
      finder.sortOrder = Sembast.SortOrder(query.ordering);
    }

    final db = _db[tableName];
    var records = await store.find(db, finder: finder);
    for (var record in records) {
      final model = query.instantiateModel();
      model.import(_fixType(record.value));
      results.add(model);
    }

    return results;
  }

  Map<String, dynamic> _fixType(Map<String, dynamic> map) {
    Map<String, dynamic> copiedMap = {}..addAll(map);

    copiedMap["createdAt"] =
        DateTime.fromMillisecondsSinceEpoch(map["createdAt"] ?? 0);
    copiedMap["updatedAt"] =
        DateTime.fromMillisecondsSinceEpoch(map["updatedAt"] ?? 0);

    return copiedMap;
  }

  // Note on subscribe to changes from Sembast: https://github.com/tekartik/sembast.dart/blob/master/sembast/doc/new_api.md
}

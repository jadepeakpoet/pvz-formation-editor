import 'package:sqflite/sqflite.dart' as sqflite;

Future<dynamic> openMobileDatabase(String path) =>
    sqflite.openDatabase(path, singleInstance: false);

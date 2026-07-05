/// SharedPreferences 内存桩——纯 Dart，无需 Flutter。
library shared_preferences;

class SharedPreferences {
  final Map<String, dynamic> _data;

  SharedPreferences._(this._data);

  static Future<SharedPreferences> getInstance() async =>
      SharedPreferences._({});

  String? getString(String key) => _data[key] as String?;

  Future<bool> setString(String key, String value) async {
    _data[key] = value;
    return true;
  }

  bool? getBool(String key) => _data[key] as bool?;

  Future<bool> setBool(String key, bool value) async {
    _data[key] = value;
    return true;
  }

  Future<bool> remove(String key) async {
    _data.remove(key);
    return true;
  }

  bool containsKey(String key) => _data.containsKey(key);
}

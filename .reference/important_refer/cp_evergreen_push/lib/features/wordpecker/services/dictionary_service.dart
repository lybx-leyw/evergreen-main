import '../models/word_entry.dart';

/// Multi-dictionary lookup service for vocabulary definitions.
///
/// Ports the dictionary integration from app/js/components/wordpecker.js.
/// Supports up to 4 dictionary sources. Falls back gracefully when dictionary
/// JSON files are not available (shipped separately in vendor/dicts/).
class DictionaryService {
  /// Available dictionary names.
  static const availableDictionaries = ['cambridge', 'collins', 'webster', 'oxford'];

  /// Active dictionary selections.
  final Set<String> _activeDicts = {'cambridge'};

  Set<String> get activeDicts => Set.unmodifiable(_activeDicts);

  void setActiveDicts(Set<String> dicts) {
    _activeDicts.clear();
    _activeDicts.addAll(dicts.where((d) => availableDictionaries.contains(d)));
  }

  void addDict(String dict) {
    if (availableDictionaries.contains(dict)) {
      _activeDicts.add(dict);
    }
  }

  void removeDict(String dict) {
    _activeDicts.remove(dict);
  }

  /// Look up a word across all active dictionaries.
  /// Returns a map of dict_name → definition.
  ///
  /// In a full deployment, dictionary JSON files live in:
  ///   vendor/dicts/{dictName}/{first_letter}/{word}.json
  ///
  /// When dictionary files are absent (development / CI), this returns an
  /// empty map and the caller should fall back to EtymologyService (AI analysis).
  Future<Map<String, String>> lookup(String word, {List<String>? dicts}) async {
    final searchDicts = dicts ?? _activeDicts.toList();
    final result = <String, String>{};

    for (final dictName in searchDicts) {
      try {
        final definition = await _lookupInDict(word, dictName);
        if (definition != null) {
          result[dictName] = definition;
        }
      } catch (_) {
        // Dictionary file not available — skip this source.
        // The caller should fall back to EtymologyService (AI analysis).
      }
    }

    return result;
  }

  /// Attempt to read a definition from a pre-generated JSON dictionary file.
  /// Returns null if the file does not exist (not shipped with the app).
  Future<String?> _lookupInDict(String word, String dictName) async {
    // In a full deployment, the dictionary files are shipped alongside the app:
    //   vendor/dicts/cambridge/a/apple.json
    //   vendor/dicts/collins/a/apple.json
    // etc.
    //
    // These are large JSON files (~50MB each for 20K words) and are not
    // included in the Flutter project by default. They are generated offline
    // and placed in the app's assets or support directory.
    //
    // For now, always return null — the caller will use AI etymology instead.
    return null;
  }
}

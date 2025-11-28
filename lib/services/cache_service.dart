class CacheEntry<T> {
  CacheEntry(this.value, this.expiresAt);

  final T value;
  final DateTime expiresAt;

  bool get isValid => DateTime.now().isBefore(expiresAt);
}

class CacheService {
  final _store = <String, CacheEntry>{};

  T? get<T>(String key) {
    final entry = _store[key];
    if (entry == null) return null;
    if (!entry.isValid) {
      _store.remove(key);
      return null;
    }
    return entry.value as T;
  }

  void set<T>(String key, T value, Duration ttl) {
    _store[key] = CacheEntry<T>(value, DateTime.now().add(ttl));
  }

  void invalidate(String key) => _store.remove(key);

  void clear() => _store.clear();
}

final cache = CacheService();

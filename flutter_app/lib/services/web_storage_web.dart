import 'dart:js_interop';

@JS('window.localStorage.getItem')
external JSString? _getItem(JSString key);

@JS('window.localStorage.setItem')
external void _setItem(JSString key, JSString value);

String? readWebStorage(String key) {
  try {
    return _getItem(key.toJS)?.toDart;
  } catch (_) {
    return null;
  }
}

void writeWebStorage(String key, String value) {
  try {
    _setItem(key.toJS, value.toJS);
  } catch (_) {}
}

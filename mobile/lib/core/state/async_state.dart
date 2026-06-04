/// État asynchrone minimal — remplace `AsyncValue` de Riverpod.
///
/// Un contrôleur (`ChangeNotifier`) expose un `AsyncState<T>` et notifie ses
/// listeners à chaque transition (`loading` → `data` / `error`). Les écrans
/// réagissent via `when(...)` exactement comme avec `AsyncValue`.
enum AsyncStatus { idle, loading, data, error }

class AsyncState<T> {
  const AsyncState._(this.status, this._value, this.error);

  const AsyncState.idle() : this._(AsyncStatus.idle, null, null);
  const AsyncState.loading() : this._(AsyncStatus.loading, null, null);
  const AsyncState.data(T value) : this._(AsyncStatus.data, value, null);
  const AsyncState.error(Object error) : this._(AsyncStatus.error, null, error);

  final AsyncStatus status;
  final T? _value;
  final Object? error;

  bool get isLoading => status == AsyncStatus.loading;

  /// Pattern-matching sur l'état courant, calqué sur `AsyncValue.when`.
  R when<R>({
    required R Function() idle,
    required R Function() loading,
    required R Function(T value) data,
    required R Function(Object error) error,
  }) {
    return switch (status) {
      AsyncStatus.idle => idle(),
      AsyncStatus.loading => loading(),
      AsyncStatus.data => data(_value as T),
      AsyncStatus.error => error(this.error!),
    };
  }
}

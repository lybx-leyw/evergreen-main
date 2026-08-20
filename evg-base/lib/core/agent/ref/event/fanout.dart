part of 'event.dart';

class FanOut implements Sink {
  final List<Sink> sinks;

  FanOut(this.sinks);

  @override
  void emit(Event e) {
    for (final s in sinks) {
      if (s != null) s.emit(e);
    }
  }

  int get length => sinks.length;
}

import '../entities/live_stream.dart';

abstract class StreamRepository {
  Future<List<LiveStream>> listLiveStreams({int limit, int offset});
}

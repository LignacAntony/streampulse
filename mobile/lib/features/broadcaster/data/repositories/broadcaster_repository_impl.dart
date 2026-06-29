import '../../domain/entities/broadcaster_request.dart';
import '../../domain/repositories/broadcaster_repository.dart';
import '../datasources/broadcaster_remote_data_source.dart';
import '../mappers/broadcaster_dto_mappers.dart';

class BroadcasterRepositoryImpl implements BroadcasterRepository {
  BroadcasterRepositoryImpl(this._remote);

  final BroadcasterRemoteDataSource _remote;

  @override
  Future<BroadcasterRequest> requestBroadcaster({String message = ''}) async {
    final response = await _remote.create(message);
    return response.toEntity();
  }

  @override
  Future<BroadcasterRequest?> getMyRequest() async {
    final response = await _remote.getMine();
    return response?.toEntity();
  }
}

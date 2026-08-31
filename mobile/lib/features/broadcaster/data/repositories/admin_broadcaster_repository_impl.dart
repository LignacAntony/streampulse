import '../../domain/entities/admin_broadcaster_request.dart';
import '../../domain/repositories/admin_broadcaster_repository.dart';
import '../datasources/broadcaster_remote_data_source.dart';
import '../mappers/broadcaster_dto_mappers.dart';

class AdminBroadcasterRepositoryImpl implements AdminBroadcasterRepository {
  AdminBroadcasterRepositoryImpl(this._remote);

  final BroadcasterRemoteDataSource _remote;

  @override
  Future<List<AdminBroadcasterRequest>> list({String? status}) async {
    final requests = await _remote.listAdmin(status: status);
    return requests.map((dto) => dto.toEntity()).toList();
  }

  @override
  Future<void> approve(String id, {String? note}) => _remote.approve(id, note);

  @override
  Future<void> reject(String id, {String? note}) => _remote.reject(id, note);
}

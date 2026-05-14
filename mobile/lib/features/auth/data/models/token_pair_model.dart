import '../../domain/entities/token_pair.dart';

class TokenPairModel {
  const TokenPairModel({
    required this.accessToken,
    required this.refreshToken,
  });

  factory TokenPairModel.fromJson(Map<String, dynamic> json) {
    return TokenPairModel(
      accessToken: json['access_token'] as String,
      refreshToken: json['refresh_token'] as String,
    );
  }

  final String accessToken;
  final String refreshToken;

  TokenPair toEntity() => TokenPair(
        accessToken: accessToken,
        refreshToken: refreshToken,
      );
}

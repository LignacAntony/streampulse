OPENAPI_GENERATOR_IMAGE := openapitools/openapi-generator-cli:v7.23.0
OPENAPI_SPEC := /workspace/backend/internal/openapi/openapi.yaml
OPENAPI_CLIENT_OUT := /workspace/mobile/packages/streampulse_api

.PHONY: generate-openapi-client
generate-openapi-client:
	rm -rf mobile/packages/streampulse_api
	docker run --rm \
		-v "$(PWD):/workspace" \
		-w /workspace \
		$(OPENAPI_GENERATOR_IMAGE) generate \
		-i $(OPENAPI_SPEC) \
		-g dart-dio \
		-o $(OPENAPI_CLIENT_OUT) \
		--additional-properties=pubName=streampulse_api,pubLibrary=streampulse_api,pubVersion=0.1.0,pubDescription="Generated Dart/Dio client for the StreamPulse API",pubPublishTo=none,serializationLibrary=json_serializable,finalProperties=true,skipCopyWith=true \
		--global-property=apiDocs=false,apiTests=false,modelDocs=false,modelTests=false
	@grep -qF "sdk: '>=3.5.0 <4.0.0'" mobile/packages/streampulse_api/pubspec.yaml || { echo ">> generate-openapi-client: motif 'sdk' introuvable dans pubspec.yaml — le template openapi-generator a changé, mettre à jour le Makefile"; exit 1; }
	perl -0pi -e "s/sdk: '>=3\\.5\\.0 <4\\.0\\.0'/sdk: ^3.11.4/" mobile/packages/streampulse_api/pubspec.yaml
	@grep -qF "build_runner: any" mobile/packages/streampulse_api/pubspec.yaml || { echo ">> generate-openapi-client: motif 'build_runner: any' introuvable dans pubspec.yaml — template modifié, mettre à jour le Makefile"; exit 1; }
	perl -0pi -e "s/build_runner: any/build_runner: ^2.4.13/" mobile/packages/streampulse_api/pubspec.yaml
	@grep -qF "json_serializable: '^6.9.3'" mobile/packages/streampulse_api/pubspec.yaml || { echo ">> generate-openapi-client: motif 'json_serializable' introuvable dans pubspec.yaml — template modifié, mettre à jour le Makefile"; exit 1; }
	perl -0pi -e "s/json_serializable: '\\^6\\.9\\.3'/json_serializable: 6.8.0/" mobile/packages/streampulse_api/pubspec.yaml
	@grep -qF "deprecated_member_use_from_same_package: ignore" mobile/packages/streampulse_api/analysis_options.yaml || { echo ">> generate-openapi-client: motif 'analysis_options' introuvable — template modifié, mettre à jour le Makefile"; exit 1; }
	perl -0pi -e "s/deprecated_member_use_from_same_package: ignore/deprecated_member_use_from_same_package: ignore\\n    unused_import: ignore/" mobile/packages/streampulse_api/analysis_options.yaml
	cd mobile/packages/streampulse_api && dart pub get && dart run build_runner build --delete-conflicting-outputs
	dart format mobile/packages/streampulse_api/lib
	rm -rf mobile/packages/streampulse_api/.dart_tool mobile/packages/streampulse_api/pubspec.lock

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

.PHONY: loadtest
loadtest:
	cd backend && go test -tags loadtest -race -count=1 -run TestLoad -v -timeout 5m ./internal/streaming/loadtest/

# Mesure du coût CPU de N flux simultanés (STR-243) — modèle de dimensionnement
# et de coût du VPS, cf. ADR 044.
#
# SANS `-race`, à la différence de `loadtest` : le détecteur de données multiplie
# le temps CPU du code Go par un ordre de grandeur, sans toucher à celui des
# process ffmpeg. Un modèle de coût mesuré sous `-race` serait donc faux, et
# faux de façon asymétrique — le pire cas, celui qui ne se voit pas. Le test
# refuse de tourner dans cette configuration.
#
# Variables : LOADTEST_STREAMS (défaut 1,5,10,20), LOADTEST_BROADCAST_SECONDS
# (défaut 45). Compter ~15 min sur le balayage complet.
.PHONY: loadtest-cpu
loadtest-cpu:
	cd backend && go test -tags loadtest -count=1 -run TestStreamCPU -v -timeout 40m ./internal/streaming/loadtest/

# Preuve de fluidité 60 FPS sur appareil (STR-243), cf. docs/performance-mobile.md.
#
# `flutter drive` et non `flutter test` : seul le premier accepte `--profile`,
# et une mesure de trame en mode debug ne prouve rien (JIT sans optimisation).
# DEVICE est obligatoire — mesurer sur « le premier appareil venu » rendrait le
# chiffre ininterprétable ; `flutter devices` donne les identifiants.
.PHONY: frame-budget
frame-budget:
	@test -n "$(DEVICE)" || { echo ">> frame-budget: préciser DEVICE=<id> (voir 'flutter devices')"; exit 1; }
	cd mobile && flutter drive \
	  --driver=test_driver/integration_test.dart \
	  --target=integration_test/frame_budget_test.dart \
	  --profile -d $(DEVICE)

.PHONY: check-android-security
check-android-security:
	python3 scripts/check-android-network-security.py

.PHONY: check-legal-assets
check-legal-assets:
	python3 scripts/check-legal-assets.py

# L'index anglais des décisions promet d'être exhaustif : cette garde le vérifie.
.PHONY: check-adr-index
check-adr-index:
	python3 scripts/check-adr-index.py

.PHONY: check-dashboards
check-dashboards:
	python3 scripts/check-dashboards.py

# Couverture Go, unitaires seuls — informatif, ne fait jamais échouer.
#
# Seuil explicite à 0 : sans lui le script retomberait sur son défaut de 80 %,
# qu'une mesure sans `-tags integration` ne peut pas tenir — toute la couche
# repository reste non couverte. La cible échouait donc en prétendant le
# contraire, et rendait un rouge à qui voulait seulement lire un rapport.
.PHONY: coverage
coverage:
	cd backend && go test ./... -covermode=count -coverprofile=coverage.txt
	python3 scripts/check-coverage.py backend/coverage.txt 0

# Couverture Go, unitaires + intégration, avec la porte de qualité.
# Exige TEST_DATABASE_URL et un PostgreSQL joignable ; sans eux les tests
# d'intégration se sautent et le seuil ne sera pas tenu — ce n'est pas un faux
# négatif, c'est la mesure réelle de ce qui a tourné.
# Cf. l'en-tête de backend/internal/testsupport/pgtest.
.PHONY: coverage-gate
coverage-gate:
	@test -n "$$TEST_DATABASE_URL" || { \
	  echo ">> coverage-gate: TEST_DATABASE_URL non défini — les tests d'intégration se sauteraient"; \
	  echo ">> cf. docs/couverture-de-tests.md § 4"; exit 1; }
	cd backend && go test ./... -tags integration -covermode=count -coverprofile=coverage.txt
	python3 scripts/check-coverage.py backend/coverage.txt

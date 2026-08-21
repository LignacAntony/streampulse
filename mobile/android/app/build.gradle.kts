import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

/// Valeurs de signature : `key.properties` d'abord, environnement ensuite.
val keystoreProperties = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) FileInputStream(f).use { load(it) }
}

/// Une valeur vide compte comme absente.
///
/// `System.getenv` ne rend `null` que si la variable n'existe pas du tout. Or un
/// secret GitHub non défini mais référencé dans un bloc `env:` est bel et bien
/// exporté — avec la chaîne vide pour valeur. Un test `!= null` le prenait donc
/// pour un mot de passe valide : signature tentée avec un secret vide, build
/// cassé sur une erreur jarsigner qui ne nomme rien (revue PR #326).
///
/// `takeUnless { it.isBlank() }` ramène ce cas au seul qui soit vrai — la valeur
/// n'est pas utilisable — et laisse le repli en clé de debug faire son travail.
/// Appliqué aux DEUX sources : une propriété locale vide doit laisser passer
/// l'environnement, et non court-circuiter l'elvis avec une chaîne vide.
fun signingValue(propertyKey: String, envKey: String): String? =
    keystoreProperties.getProperty(propertyKey)?.takeUnless { it.isBlank() }
        ?: System.getenv(envKey)?.takeUnless { it.isBlank() }

val releaseStoreFile: String? = signingValue("storeFile", "ANDROID_KEYSTORE_PATH")
val releaseStorePassword: String? = signingValue("storePassword", "ANDROID_KEYSTORE_PASSWORD")
val releaseKeyAlias: String? = signingValue("keyAlias", "ANDROID_KEY_ALIAS")
val releaseKeyPassword: String? = signingValue("keyPassword", "ANDROID_KEY_PASSWORD")

/// Les quatre valeurs ET le fichier : une configuration partielle est traitée
/// comme une configuration absente. Signer à moitié n'existe pas.
val hasReleaseKeystore: Boolean =
    !releaseStoreFile.isNullOrBlank() &&
        !releaseStorePassword.isNullOrBlank() &&
        !releaseKeyAlias.isNullOrBlank() &&
        !releaseKeyPassword.isNullOrBlank() &&
        file(releaseStoreFile).exists()

// L'avertissement ne se déclenche que si une tâche de release est demandée :
// le rappeler à chaque `flutter run` en debug le rendrait invisible à force.
if (!hasReleaseKeystore &&
    gradle.startParameter.taskNames.any { it.contains("Release", ignoreCase = true) }
) {
    // logger.error et non logger.lifecycle : `flutter build` filtre la sortie
    // Gradle et n'en laisse passer que les niveaux warn/error. Un avertissement
    // émis en lifecycle n'atteignait personne — vérifié, il n'apparaissait pas
    // dans la sortie du build.
    logger.error(
        """
        |
        |  ⚠  Build de release signé avec la CLÉ DE DEBUG.
        |     L'artefact produit est utilisable pour un test local, mais il sera
        |     REFUSÉ par le Play Store et ne doit pas être distribué.
        |     Pour signer réellement : cf. docs/distribution-mobile.md.
        |
        """.trimMargin()
    )
}

flutter {
    source = "../.."
}

android {
    namespace = "fr.streampulse.streampulse"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "fr.streampulse.streampulse"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // Signature de release, en mode dégradé assumé.
    //
    // La clé de signature n'est pas dans le dépôt et n'y sera jamais : qui la
    // détient contrôle toutes les mises à jour futures de l'application, et la
    // perdre interdit définitivement de mettre à jour une application publiée
    // sous la même identité.
    //
    // Elle est donc lue, dans l'ordre : `android/key.properties` (poste de
    // développement), puis les variables d'environnement (CI). Quand aucune
    // n'est disponible, le build de release **retombe sur la clé de debug** au
    // lieu d'échouer — sans quoi `flutter run --release` deviendrait impossible
    // pour quiconque n'a pas la clé, c'est-à-dire pour toute l'équipe.
    //
    // Ce repli est bruyant à dessein : un APK signé en debug est refusé par le
    // Play Store, et un build qui « réussit » sans le dire est exactement le
    // piège dans lequel ce fichier était tombé.
    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                storeFile = file(releaseStoreFile!!)
                storePassword = releaseStorePassword
                keyAlias = releaseKeyAlias
                keyPassword = releaseKeyPassword
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasReleaseKeystore) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

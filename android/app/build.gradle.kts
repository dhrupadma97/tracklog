import java.io.File
import java.util.Base64

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Helper function to extract dart-define values passed via --dart-define=KEY=VALUE
fun extractDartDefine(key: String, defaultValue: String = ""): String {
    val dartDefines = project.findProperty("dart-defines") as? String ?: return defaultValue
    return try {
        dartDefines.split(",")
            .map { String(Base64.getDecoder().decode(it)) }
            .firstOrNull { it.startsWith("$key=") }
            ?.substringAfter("$key=")
            ?: defaultValue
    } catch (e: Exception) {
        defaultValue
    }
}

// Helper function to read values from env.json at the project root
fun readEnvJson(key: String, defaultValue: String = ""): String {
    return try {
        val envFile = File(rootProject.projectDir.parent, "env.json")
        if (envFile.exists()) {
            val content = envFile.readText()
            // Simple regex-based JSON parsing for string values
            val pattern = "\"$key\"\\s*:\\s*\"([^\"]*)\""
            val matchResult = Regex(pattern).find(content)
            matchResult?.groupValues?.getOrNull(1)?.takeIf { it.isNotBlank() } ?: defaultValue
        } else {
            defaultValue
        }
    } catch (e: Exception) {
        defaultValue
    }
}

android {
    namespace = "com.example.tracklog"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.example.tracklog"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // Try dart-define first (CI/CD), then fall back to env.json (local/APK builds)
        val googleMapsApiKey = extractDartDefine("GOOGLE_MAPS_API_KEY")
            .ifBlank { readEnvJson("GOOGLE_MAPS_API_KEY") }
        val supabaseUrl = extractDartDefine("SUPABASE_URL")
            .ifBlank { readEnvJson("SUPABASE_URL") }
        val supabaseAnonKey = extractDartDefine("SUPABASE_ANON_KEY")
            .ifBlank { readEnvJson("SUPABASE_ANON_KEY") }

        manifestPlaceholders["GOOGLE_MAPS_API_KEY"] = googleMapsApiKey

        // Inject as BuildConfig fields so Dart code can access them at runtime
        buildConfigField("String", "SUPABASE_URL", "\"$supabaseUrl\"")
        buildConfigField("String", "SUPABASE_ANON_KEY", "\"$supabaseAnonKey\"")
        buildConfigField("String", "GOOGLE_MAPS_API_KEY", "\"$googleMapsApiKey\"")
    }

    buildFeatures {
        buildConfig = true
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
    implementation("androidx.multidex:multidex:2.0.1")
    implementation("com.google.android.material:material:1.13.0")
    implementation("androidx.concurrent:concurrent-futures:1.3.0")
}

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

// Helper function to read values from env.json — tries multiple path strategies
fun readEnvJson(key: String, defaultValue: String = ""): String {
    return try {
        // Try multiple candidate locations for env.json
        val candidates = listOf(
            File(rootProject.projectDir.parent, "env.json"),          // <project>/env.json
            File(rootProject.projectDir, "env.json"),                  // <project>/android/env.json
            File(project.projectDir.parent.parent, "env.json"),        // two levels up
            File(System.getProperty("user.dir"), "env.json")           // working directory
        )
        val envFile = candidates.firstOrNull { it.exists() }
        if (envFile != null) {
            val content = envFile.readText()
            val pattern = "\"$key\"\\s*:\\s*\"([^\"]*)\""
            val matchResult = Regex(pattern).find(content)
            val value = matchResult?.groupValues?.getOrNull(1)?.takeIf { it.isNotBlank() }
            println("TrackLog Build: Found env.json at ${envFile.absolutePath}, $key=${if (value != null) "***" else "NOT FOUND"}")
            value ?: defaultValue
        } else {
            println("TrackLog Build: env.json not found in any candidate path")
            defaultValue
        }
    } catch (e: Exception) {
        println("TrackLog Build: Error reading env.json: ${e.message}")
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

        // Use resValue instead of manifestPlaceholders — more reliable embedding
        // The AndroidManifest.xml references @string/google_maps_key
        resValue("string", "google_maps_key", googleMapsApiKey)

        // Keep manifestPlaceholders as fallback
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

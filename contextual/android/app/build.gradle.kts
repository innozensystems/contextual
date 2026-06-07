plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.serialization") version "1.9.22"
    id("com.google.devtools.ksp")
    id("androidx.navigation.safeargs.kotlin")
}

android {
    namespace = "com.contextual"
    compileSdk = 34

    defaultConfig {
        applicationId = "com.contextual"
        minSdk = 26
        targetSdk = 34
        versionCode = 1
        versionName = "1.0"

        // Secrets are injected via environment variables in CI (never commit real credentials).
        // For local development, set SUPABASE_URL and SUPABASE_ANON_KEY in your shell or local.properties.
        val supabaseUrl = System.getenv("SUPABASE_URL") ?: ""
        val supabaseAnonKey = System.getenv("SUPABASE_ANON_KEY") ?: ""
        val proxyBaseUrl = System.getenv("PROXY_BASE_URL") ?: "http://localhost:8000"
        val proxyPins = System.getenv("PROXY_CERTIFICATE_PINS") ?: ""
        val proxyApiKey = System.getenv("PROXY_API_KEY") ?: ""

        buildConfigField("String", "SUPABASE_URL", "\"$supabaseUrl\"")
        buildConfigField("String", "SUPABASE_ANON_KEY", "\"$supabaseAnonKey\"")
        buildConfigField("String", "PROXY_BASE_URL", "\"$proxyBaseUrl\"")
        buildConfigField("String", "PROXY_CERTIFICATE_PINS", "\"$proxyPins\"")
        buildConfigField("String", "PROXY_API_KEY", "\"$proxyApiKey\"")
    }

    buildFeatures {
        viewBinding = true
        buildConfig = true
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }

    // Validate that secrets are injected before actual release builds.
    // Skipped in CI unless CI_RELEASE=true (set only in the deploy job).
    tasks.register("validateReleaseSecrets") {
        onlyIf { System.getenv("CI_RELEASE") == "true" }
        doLast {
            val supabaseUrl = System.getenv("SUPABASE_URL") ?: ""
            val supabaseAnonKey = System.getenv("SUPABASE_ANON_KEY") ?: ""
            require(supabaseUrl.isNotBlank()) {
                "SUPABASE_URL must be set via environment variable for release builds. " +
                "Do not commit real credentials to the repository."
            }
            require(supabaseAnonKey.isNotBlank()) {
                "SUPABASE_ANON_KEY must be set via environment variable for release builds. " +
                "Do not commit real credentials to the repository."
            }
        }
    }

    afterEvaluate {
        tasks.named("assembleRelease").configure {
            dependsOn("validateReleaseSecrets")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }
}

dependencies {
    implementation("androidx.core:core-ktx:1.12.0")
    implementation("androidx.appcompat:appcompat:1.6.1")
    implementation("com.google.android.material:material:1.11.0")
    implementation("androidx.constraintlayout:constraintlayout:2.1.4")
    implementation("androidx.lifecycle:lifecycle-viewmodel-ktx:2.7.0")
    implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.7.0")
    implementation("androidx.fragment:fragment-ktx:1.6.2")
    implementation("androidx.navigation:navigation-fragment-ktx:2.7.6")
    implementation("androidx.navigation:navigation-ui-ktx:2.7.6")
    implementation("androidx.recyclerview:recyclerview:1.3.2")
    implementation("androidx.swiperefreshlayout:swiperefreshlayout:1.1.0")

    // Supabase
    implementation(platform("io.github.jan-tennert.supabase:bom:2.5.0"))
    implementation("io.github.jan-tennert.supabase:postgrest-kt")
    implementation("io.github.jan-tennert.supabase:gotrue-kt")
    implementation("io.github.jan-tennert.supabase:realtime-kt")

    // Maps
    implementation("com.google.android.gms:play-services-maps:18.2.0")
    implementation("com.google.android.gms:play-services-location:21.0.1")

    // Networking
    implementation("io.ktor:ktor-client-android:2.3.7")
    implementation("io.ktor:ktor-client-okhttp:2.3.7")
    implementation("io.ktor:ktor-client-content-negotiation:2.3.7")
    implementation("io.ktor:ktor-serialization-kotlinx-json:2.3.7")

    // Serialization
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.6.2")

    // Google Play Services coroutines integration
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-play-services:1.7.3")

    // Testing
    testImplementation("junit:junit:4.13.2")
    testImplementation("io.mockk:mockk:1.13.9")
    testImplementation("org.jetbrains.kotlinx:kotlinx-coroutines-test:1.7.3")
    testImplementation("io.ktor:ktor-client-mock:2.3.7")
}

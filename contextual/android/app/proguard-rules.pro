# ProGuard rules for Contextual

# Suppress SLF4J missing implementation warning (Ktor/OkHttp transitive dependency)
-dontwarn org.slf4j.impl.StaticLoggerBinder

# Keep Kotlin serialization for proxy models
-keepclassmembers class com.contextual.service.ProxyService$* {
    *;
}

# Keep Supabase/Kotlinx serialization classes
-keepattributes *Annotation*
-keepclassmembers class kotlinx.serialization.json.** { *; }

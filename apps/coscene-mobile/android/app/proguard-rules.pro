# R8 rules for coscene. Flutter's own rules are added by its Gradle plugin.

# The method channel in MainActivity is reached by name from Dart.
-keep class com.vecvel.coscene.MainActivity { *; }

# flutter_secure_storage encrypts with Tink, which refers to annotation
# classes that are not on Android. They are compile-time only.
-dontwarn com.google.errorprone.annotations.**
-dontwarn javax.annotation.**
-dontwarn com.google.api.client.**
-dontwarn org.joda.time.**
-keep class com.google.crypto.tink.** { *; }

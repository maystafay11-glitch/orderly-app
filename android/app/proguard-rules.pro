# R8/ProGuard rules for the Orderly app.
#
# Flutter enables R8 (code shrinking) for release builds, and the ML Kit text
# recognition plugin references optional script recognizers that are NOT
# bundled with the Latin model we use (see the generated
# build/app/outputs/mapping/release/missing_rules.txt). Without these rules the
# release build fails with: "R8: Missing class com.google.mlkit.vision.text.chinese...".
-dontwarn com.google.mlkit.vision.text.chinese.ChineseTextRecognizerOptions$Builder
-dontwarn com.google.mlkit.vision.text.chinese.ChineseTextRecognizerOptions
-dontwarn com.google.mlkit.vision.text.devanagari.DevanagariTextRecognizerOptions$Builder
-dontwarn com.google.mlkit.vision.text.devanagari.DevanagariTextRecognizerOptions
-dontwarn com.google.mlkit.vision.text.japanese.JapaneseTextRecognizerOptions$Builder
-dontwarn com.google.mlkit.vision.text.japanese.JapaneseTextRecognizerOptions
-dontwarn com.google.mlkit.vision.text.korean.KoreanTextRecognizerOptions$Builder
-dontwarn com.google.mlkit.vision.text.korean.KoreanTextRecognizerOptions

# Keep the ML Kit entry points that the plugin resolves by class name.
-keep class com.google.mlkit.vision.text.** { *; }
-keep class com.google.mlkit.common.** { *; }

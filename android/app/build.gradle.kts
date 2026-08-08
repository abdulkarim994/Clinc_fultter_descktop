// م74 — استيراد صريح بدل التأهيل الكامل. في AGP 9 يوجد في نطاق السكربت
// كائن باسم `java` (امتداد Gradle) يحجب اسم الحزمة، فتفشل
// `java.util.Properties()` بـ«Unresolved reference 'util'».
// كُشف ببناء APK حقيقي — وهو بالضبط ما حذّرت منه وثيقة م68: تغييرات
// Gradle رُوجعت بالعين ولم تُبنَ، فبقي العطل كامناً حتى أول بناء إصدار.
import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.dental.clinic"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // نفس معرّف تطبيق Capacitor الأصلي — تثبيت الترقية يبقي مجلد بيانات
        // التطبيق نفسه فتقرأ أداة الترحيل قاعدة القديم مباشرة. يتطلب التوقيع
        // بمفتاح keystore الأصلي نفسه؛ وإلا فغيّر المعرّف (تثبيت جنباً إلى جنب)
        // واستعمل الترحيل عبر منتقي الملفات. التفاصيل: PACKAGING_AR.md.
        applicationId = "com.dental.clinic"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // م83 — أرضية صريحة لا موروثة. تشفيرُ مفتاح القاعدة في Keystore
        // (AES-GCM ملفوفاً بـRSA-OAEP) يتطلّب API 23، وقيمةُ فلاتر
        // الافتراضية اليوم 24 فالمتطلَّب مستوفى — لكن ترقية/تخفيض أدوات
        // تغيّرها بصمت، وحينها يفشل حفظ المفتاح على أجهزة قديمة فتُقفل
        // القاعدة. `maxOf` يحفظ الأرضية ويقبل أي رفع لاحق من فلاتر.
        //
        // م88 — الأرضية ترتفع إلى 24: حزمة `app_links` (عودة deep-link
        // لدخول Google عبر supabase_flutter) تشترط minSdk 24 في
        // build.gradle الخاص بها، وأرضية 23 هنا كانت ستُسقط بناء APK
        // بأكمله لو خفّضت أدواتُ فلاتر افتراضَها يوماً. أثر الرفع عملياً
        // صفر: أندرويد 6 (API 23) هاتفُ 2015 لا يخص أجهزة العيادات.
        minSdk = maxOf(flutter.minSdkVersion, 24)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // م68/دفعة ثانٍ-أ — أسرار التوقيع خارج المستودع.
    //
    //   كان مخزن التوقيع dental_dev.jks مضمّناً في المشروع وكلمتا مروره
    //   مكتوبتين هنا نصاً صريحاً، و**نسخة release توقَّع به**. من يملك
    //   الأرشيف يبني APK خبيثاً بنفس applicationId يقبله أندرويد ترقيةً في
    //   المكان بلا تحذير، فيرث مجلد البيانات كاملاً (قاعدة المرضى، رموز
    //   الجلسة، صور الأشعة). والتوزيع هنا بالتنصيب الجانبي بالتصميم — أي
    //   أن هذا هو بالضبط سيناريو الهجوم الواقعي لا احتمالاً نظرياً.
    //
    //   الآن: قيم مفتاح الإصدار تُقرأ من android/key.properties (مستثنى من
    //   git). وdebug وحده يقبل السقوط إلى مفتاح التطوير؛ أما النشر الحقيقي
    //   فيفشل **صراحةً** إن غاب المفتاح بدل أن يُوقَّع بمكشوف صامتاً.
    //
    //   ⚠ المفتاح القديم يجب اعتباره محروقاً — ولّد مخزناً جديداً واحفظه
    //     خارج المستودع. أثر تغيير المفتاح على الترقية في PACKAGING_AR.md.
    val keystorePropertiesFile = rootProject.file("key.properties")
    val hasReleaseKey = keystorePropertiesFile.exists()
    val keystoreProperties = Properties()
    if (hasReleaseKey) {
        FileInputStream(keystorePropertiesFile).use { stream ->
            keystoreProperties.load(stream)
        }
    }

    signingConfigs {
        // مفتاح التطوير: لـ debug فقط. بصمة ثابتة عبر أجهزة البناء كي
        // تُقبل الترقية أثناء التجربة (كان هذا مبرّره الأصلي في v48).
        // م77 — حُذفت كلمتا المرور النصّيتان المكشوفتان من هذا الملف.
        // (م77/ب: أزيل نصُّهما الحرفي حتى من هذا التعليق — حارس الأسرار في
        //  CI يمسح android/ بحثاً عنه، فكان يصطاد توثيقَ نفسه.)
        //
        // كانتا احتياطيَّين صامتَين: من يملك الأرشيف يملك المخزن وكلمته معاً،
        // فيبني حزمةً بمعرّف التطبيق نفسه موقَّعةً بالمفتاح نفسه — ويقبلها
        // أندرويد **ترقيةً في محلّها بلا تحذير**، فترث شيفرته دليل بيانات
        // المرضى كاملاً. والنسخة التجريبية الموزَّعة كانت توقَّع بهذا المفتاح.
        //
        // الآن يفشل البناء بصوت عالٍ إن غابت المتغيّرات — وهو السلوك نفسه
        // الذي يفرضه مسار الإصدار الحقيقي أدناه.
        create("dentalDev") {
            storeFile = file("dental_dev.jks")
            storePassword = System.getenv("DENTAL_DEV_STORE_PASSWORD")
                ?: throw GradleException(
                    "DENTAL_DEV_STORE_PASSWORD غير مضبوط — م77 أزال كلمة " +
                    "المرور النصّية. صدّر المتغيّرين قبل البناء التجريبي."
                )
            keyAlias = "dental"
            keyPassword = System.getenv("DENTAL_DEV_KEY_PASSWORD")
                ?: throw GradleException(
                    "DENTAL_DEV_KEY_PASSWORD غير مضبوط — م77 أزال كلمة " +
                    "المرور النصّية. صدّر المتغيّرين قبل البناء التجريبي."
                )
        }
        if (hasReleaseKey) {
            create("release") {
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
            }
        }
    }

    buildTypes {
        debug {
            // نسخة تجريبية جانبية: معرّف مختلف كي تُنصَّب بجانب التطبيق
            // الأصلي (com.dental.clinic) بلا تعارض توقيع. هوية release
            // تبقى المعرّف الأصلي (PACKAGING_AR.md).
            applicationIdSuffix = ".debug"
            // م77/ج — مخزن التطوير خارج المستودع بالتصميم، فبيئة CI النظيفة
            // لا تملكه وكان `validateSigningDebug` يفشل بها (كُشف بأول تشغيل
            // حقيقي لوظيفة «بناء أندرويد» على GitHub). بغيابه نسقط إلى توقيع
            // debug الافتراضي — يكفي غرضَ الوظيفة (إثبات الترجمة)؛ ومحلياً
            // حيث المخزن موجود تبقى البصمة الثابتة المعهودة لترقية التجربة.
            if (file("dental_dev.jks").exists()) {
                signingConfig = signingConfigs.getByName("dentalDev")
            }
        }
        release {
            // نسخة تجريبية بمعرّف جانبي: تُفعَّل بخاصية المشروع trialSuffix
            // (ORG_GRADLE_PROJECT_trialSuffix=true) — النشر الحقيقي بدونها
            // يبقى بالمعرّف الأصلي com.dental.clinic.
            val isTrial = project.hasProperty("trialSuffix")
            if (isTrial) {
                applicationIdSuffix = ".debug"
            }
            // م77/د — كان الرمي أدناه يقع في طور الضبط نفسه، وgradle يضبط
            // كل الأنواع حتى لبناء debug: فأي بيئة بلا key.properties وبلا
            // trialSuffix (بيئة CI النظيفة تحديداً) كانت تسقط قبل أن تبدأ.
            // القرار يبقى صاخباً كما صُمم (م68: لا توقيع بمكشوف صامتاً)
            // لكن في وقته الصحيح: عند طلب مهمة release فعلاً لا عند الضبط.
            val wantsRelease = gradle.startParameter.taskNames.any {
                it.contains("release", ignoreCase = true)
            }
            signingConfig = when {
                hasReleaseKey -> signingConfigs.getByName("release")
                // تجربة بمعرّف جانبي: المفتاح التجريبي مقبول هنا.
                isTrial -> signingConfigs.getByName("dentalDev")
                // نشر حقيقي مطلوب بلا مفتاح: نفشل بصوت عالٍ لا نوقّع بمكشوف.
                wantsRelease -> throw GradleException(
                    "لا يوجد android/key.properties — النشر الحقيقي يتطلب " +
                    "مفتاح توقيع خاصاً. أنشئ الملف بالحقول storeFile و" +
                    "storePassword وkeyAlias وkeyPassword (مستثنى من git)، " +
                    "أو ابنِ نسخة تجريبية بـ -PtrialSuffix=true."
                )
                // ضبطٌ عابر لغير مهام release (بناء debug مثلاً): لا توقيع
                // release يلزم هنا أصلاً — ولا release يُنتَج من هذا المسار.
                else -> null
            }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

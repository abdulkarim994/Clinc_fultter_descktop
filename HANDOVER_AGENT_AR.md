# 📘 دليل التعديل والبناء — تطبيق عيادة الأسنان (Flutter)
### وثيقة تسليمٍ كاملة لوكيلٍ جديد — آخر تحديث: **2026-08-22 (بعد م190)**

> هذه الوثيقة تُقرأ **وحدها** فيكمل الوكيل التالي بلا محادثةٍ سابقة. كل ما فيها
> مُجرَّبٌ في هذه الحاوية لا منقولاً من عادات المشاريع. مضمونها نفسه محفوظٌ في
> مهارة `dental-clinic-build` (مع الأسرار كحقول اعتماد) — فإن تعارضت الوثيقةُ
> والمهارة فالأحدث تاريخاً هو الحاكم.
>
> 🆕 **وكيلٌ جديد بلا مهارة؟** لا تنتظر شيئاً: سكربتات المهارة الخمسة **داخل
> المستودع** في `tool/agent/`، وبناءُ المهارة عندك خطوةُ نسخٍ واحدة — انظر
> **§16** في آخر الوثيقة. القيم السرّية وحدها تأتي من المالك عبر بطاقة
> المهارة (لا من هذه الوثيقة ولا من المحادثة).

---

## 1) المشروع في سطور

| البند | القيمة |
|---|---|
| المستودع | `https://github.com/abdulkarim994/Clinc_fultter_descktop` (عام)، فرع `main` |
| النوع | Flutter — عربي RTL — هاتف Android + كمبيوتر Windows |
| Flutter | **3.44.8 stable** (Dart **3.12.2**) — مثبَّت في `ci.yml` بنفس الرقم |
| الحزم | Riverpod 3 + SQLite (**sqlcipher**) + camera + gal + share_plus + supabase |
| **آخر ميلستون** | **م190** — أعمدة المعادلة في الأرباح السنوية · تناظر سجل التحاليل |
| **آخر دمج** | **PR #54 → `122669d`** (م189 `7db5279` / #53 · م188 `a4ff654` / #52) |
| **آخر APK مُسلَّم** | **2192** ⇒ التالي **2193** (الرقم يتزايد دائماً ولا يعود) |
| الحزمة الاختبارية | `com.dental.clinic.debug` — بصمة `0177de51f8657a62a044a0b651040c7d890fb0eb` |
| الحزمة الاختبارية | **1456** اختباراً خضراء + ~73 لقطةً ذهبية (GOLDENS-فقط) |
| Supabase | مشروع `Dentaldk` / ref `qajgqatflmiiwqznxfha` / eu-central-1 / PG 17 |

⚠️ **`pubspec` hooks تستعمل `source: sqlcipher` — ممنوع تغييرها** (يحرسها اختبار م83/ز).
وتعديلُ `pubspec.yaml` بأي سببٍ **يعيد تشغيل الهوك فيمحو زرعَ المكتبة** (انظر §3-أ).

---

## 2) الأسرار — في مهارةٍ جاهزة لا في المحادثة

مهارة **`dental-clinic-build`** فيها كل الأسرار كحقول اعتماد + سكربتات:

```
FetchSkillScripts({skillName:'dental-clinic-build'})            ← أولاً دائماً
RunWithCredentials({skillName:'dental-clinic-build',
  command:'bash skills/dental-clinic-build/restore_secrets.sh /agent/workspace/repo'})
```

يكتب `tool/cloud.env` و`tool/dev_keystore.env` و`android/app/dental_dev.jks` في
أماكنها ويتحقق من البصمة. الثلاثة في `.gitignore`، وفي CI **حارس أسرار** يفشل إن
وُجدت داخل المستودع.

📁 **نُسخةٌ من السكربتات الخمسة متتبَّعة في `tool/agent/`** (نصوصٌ بلا أي قيمة
سرّية — تقرأ متغيّرات البيئة فقط). فإن لم تكن المهارة عندك بعدُ، شغّلها من هناك
مباشرةً بعد تصدير الحقول، وابنِ المهارة لاحقاً (§16).

🔴 **قواعد أمنٍ لا تُكسر (عقد المالك):**
1. لا تطبع قيمة سرٍّ في المحادثة أبداً — ولا جزءاً منها.
2. لا تطلب من المالك لصق مفتاحٍ في المحادثة — بطاقة المهارة هي القناة الوحيدة.
3. تسليم ملفٍّ سرّيٍّ يكون بـ `SaveFile` فقط، ولا يُنشر أبداً بـ `PublishFilePublicly`.
4. المخزن القديم `dental_dev.jks.compromised` **محروق** (كلمته كانت منشورة) — لا يُستعمل.
5. مجلد سكربتات المهارة **يختفي بين الجولات** — أعد `FetchSkillScripts` كل جولة.

**تذكيرٌ معلَّق للمالك:** تدوير `GOOGLE_WEB_CLIENT_SECRET` ومفتاح Supabase العام.

---

## 3) تهيئة الحاوية

**حاوية جديدة (مرة واحدة، ~10 دقائق):**
```
RunWithCredentials({skillName:'dental-clinic-build',
  command:'bash skills/dental-clinic-build/setup_toolchain.sh'})
```
تُثبِّت gcc/make/cmake/openssl-devel + JDK 17 **Corretto** + شهادات الحاوية في
cacerts + Flutter 3.44.8 + Android SDK 36 + تبني sqlcipher من المصدر.

**ثم المستودع:**
```bash
git clone https://github.com/abdulkarim994/Clinc_fultter_descktop.git repo
export PATH="/agent/flutter/bin:$PATH" ANDROID_HOME=/agent/android-sdk
export JAVA_HOME=/usr/lib/jvm/java-17-amazon-corretto
cd repo && flutter pub get
bash ../skills/dental-clinic-build/seed_sqlcipher.sh .    # ← إلزامي
```

**التحقق:** `flutter analyze --fatal-warnings` ⇒ `No issues found`، ثم
`flutter test` ⇒ `All tests passed! +1456 ~73` (~13 دقيقة، مقيسة).

### 🔴 المصائد — كلها مُجرَّبة

**أ) فخ GLIBC — أكثر ما يهدر الوقت، ويتكرر.** الـ `.so` التي ينزّلها هوك حزمة
sqlite3 تطلب **GLIBC_2.38** والحاوية فيها **2.34**. والعَرَض **لا يذكر GLIBC
إطلاقاً**: عشراتُ الاختبارات تفشل باستثناءات Riverpod
(`ProviderContainer.read` / provider in error state) فتظنّ العلة في كودك.
العلاج: `seed_sqlcipher.sh` بعد **كل** `pub get` أو تعديلِ pubspec أو تطهيرِ
`.dart_tool/hooks_runner`. وانتبه: `flutter analyze` نفسه قد يُشغّل `pub get`.
وإن زُرعت في موضعٍ واحدٍ فقط، أعد الزرع بعد أول تشغيلٍ للاختبارات (المواضع
تُنشأ أثناءه) — المتوقَّع 3 مواضع لينكس مع تركِ مكتبتَي أندرويد بسلام.

**ب) بناء sqlcipher 4.7.0 صار autosetup:** `--enable-tempstore` **أُلغي**
(الأمر القديم يفشل بـ `Unknown option`) — الصحيح `--with-tempstore=yes`، ولا
خيار crypto مستقلاً (الأعلام عبر `CFLAGS`)، والهدف `make libsqlite3.so` ثم
إعادة التسمية إلى `libsqlcipher.so`.

**ج) اسم حزمة JDK:** لا وجود لـ `java-17-openjdk-devel` في AL2023 — الصحيح
`java-17-amazon-corretto-devel`. والاسم الخاطئ يُفشل **كل** معاملة dnf فلا
يُثبَّت gcc أيضاً (فشلٌ صامتٌ مربك).

**د) فخ pkill:** `pkill -f flutter_tester` داخل أمرٍ يحوي النص نفسه **يقتل
صدفتك** (exit 144 وصفر إخراج). والأصل أنه غير لازم: الحزمة كلها تكفيها 1.8GB
من 4GB. لقتل غرادل قبل البناء استعمل `pkill -x java`.

**هـ) `flutter test | tail` يخفي الفشل:** الأنبوب يُرجع خروجَ `tail` (صفراً
دائماً). استعمل `set -o pipefail` واكتب إلى ملفٍّ ثم اقرأ ذيله.

**و) بايثون الحاوية 3.9:** `tuple | None` غير مدعوم — استعمل `Optional`/`Tuple`.

---

## 4) قواعد الكود الإلزامية (عقد المالك)

1. **تعليقات عربية، معرّفات إنجليزية.** كل تعديل يبدأ بتعليق `// م<رقم> — ...`.
2. **صفر `print`/`debugPrint`.**
3. **الأعلام أرقام لا قيم منطقية:** `isBreak: 1` لا `true` (حارس grep في CI).
4. **كل الكتابات عبر المستودعات:** `upsertLocal` — تُختم dirty وتعبر المزامنة.
5. الحقول المرنة الجديدة تذهب لكتلة `data` — **لا تعديل لمخطط قاعدة البيانات**.
6. `BrandColors.*` **getters لا const** — لا تضعها داخل `const TextStyle`.
7. مفاتيح الاختبارات (`rec-*`, `appt-*`, `queue-*`, `prof-*`, `anal-reg-*`…) **عقد** — حافظ عليها.
8. التاريخ في النماذج بالأرقام اللاتينية `YYYY/MM/DD` (التخزين `YYYY-MM-DD`).
9. **اللغة مع المالك عربية دائماً** — بلا استثناء.

---

## 5) دورة الميلستون

```
1. خطة → موافقة المالك (بالعربية)
2. تنفيذ الكود
3. flutter analyze --fatal-warnings        ← No issues found
4. flutter test                            ← الحزمة كاملة خضراء (~13 د)
5. لقطات ذهبية: GOLDENS=1 flutter test <golden> --update-goldens
   → أرسل الصور للمالك
6. الرفع عبر GitHub MCP + PR + دمج squash
7. تحقق نسخة نظيفة: md5 لكل ملف مرفوع + analyze
8. بناء APK بالتحققات الخمس (§7) وتسليمه
```

🔴 **لا تنتظر CI أبداً** — المالك يراقبه بنفسه ويخبرك بالنتيجة.

**اللقطات الذهبية:** لا تعمل إلا بـ `GOLDENS=1` (تُتخطّى بالحزمة العادية —
ولذلك `~73`)، ومجلد `test/goldens/` في `.gitignore`. **فخ:** أول اختبارٍ ذهبيٍّ
بصور `Image.memory` يحتاج `precacheImage` داخل `t.runAsync` وإلا خرجت الفتحات
فارغة.

---

## 6) الرفع عبر GitHub MCP (لا بيانات git للدفع)

```
1. github__create_branch  {owner, repo, branch:"mXXX-وصف", from_branch:"main"}
2. لكل ملف: github__create_or_update_file عبر paramsFile
   {owner, repo, branch, path, message:"مXXX — وصف: <path>",
    content:"<نص الملف كما هو>",   ← ⚠️ نص عادي، ليس base64
    sha:"<blob sha>"}               ← يُحذف للملفات الجديدة
3. github__create_pull_request → github__merge_pull_request {merge_method:"squash"}
```

**التحذير الأهم (حادثة م165/ب):** `content` **نصٌّ عادي** — الخادم يرمّز بنفسه،
وbase64 يفسد الملف. **تحقق أن `size` في نتيجة الرفع = `wc -c` المحلي لكل ملف.**

blob SHA للملف المعدَّل: `git ls-tree -r origin/main | grep <filename>`
(المصدر هو **الفرع البعيد** لا المحلي — الرفع يبني عليه).

**قيود مُجرَّبة:**
- `github__push_files` يرجع **403** — ملفاً ملفاً فقط.
- ملفات `.github/workflows/` **مرفوضة** — تعديلها يدوي من المالك.
- **الثنائيات لا تُرفع إطلاقاً** (لا واجهة blob) — لذلك **أيقونات DENTSHINE
  الثلاثة عشر ما زالت غير مرفوعة** (آخر حزمة: `DENTSHINE_icons_m184.zip`
  المُسلَّمة في المحادثة). حتى يرفعها المالك يدوياً يبقى **بناء الويندوز
  بالأيقونة القديمة**، أما APK الذي نبنيه هنا فيحمل الأيقونة الصحيحة لأن
  ملفاتها موجودة في نسخة العمل المحلية (غير متتبَّعة).
- عند إضافة حزمة pub: ارفع أيضاً `pubspec.yaml` + `pubspec.lock` +
  `windows/flutter/generated_plugin_registrant.cc` + `generated_plugins.cmake`
  وإلا انكسر بناء الويندوز (درس م174).
- أدوات MCP تنقطع أحياناً جولةً كاملة («No such tool available») — أعد المحاولة.

**بعد كل دمج (إلزامي):**
```bash
rm -rf /tmp/verify && git clone --depth 1 <repo> /tmp/verify -q
# md5sum لكل ملف مرفوع: محلي مقابل /tmp/verify — كلها يجب أن تتطابق
```
⚠️ **لا تُشغّل `git reset --hard origin/main`** في نسخة العمل هذه: أيقونات
الأندرويد والويندوز الجديدة **موجودةٌ محلياً فقط** (ثنائيات غير مرفوعة)،
والإعادة القاسية تمحوها فيخرج APK بالأيقونة القديمة.

---

## 7) بناء APK التجريبي الموقَّع

```bash
cd repo
export JAVA_HOME=/usr/lib/jvm/java-17-amazon-corretto
export ANDROID_SDK_ROOT=/agent/android-sdk ANDROID_HOME=/agent/android-sdk
export PATH=/agent/flutter/bin:$JAVA_HOME/bin:$PATH
pkill -x java; rm -rf .dart_tool/hooks_runner build   # ← تطهيرٌ إلزامي بعد الزرع
flutter pub get
set -a; source tool/dev_keystore.env; source tool/cloud.env; set +a
ORG_GRADLE_PROJECT_trialSuffix=true ./tool/build_cloud.sh trial <BUILD_NUM>
```
المدة ~6-7 دقائق. الناتج: `build/app/outputs/flutter-apk/app-arm64-v8a-release.apk`
(نسلّم arm64 وحده).

### التحققات الخمس الإلزامية قبل أي تسليم
```bash
APK=build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
aapt2 dump badging $APK | grep ^package
#   1) versionName = 1.0.<BUILD_NUM>      2) name = com.dental.clinic.debug
apksigner verify --print-certs $APK | grep -i "SHA-1"
#   3) 0177de51f8657a62a044a0b651040c7d890fb0eb
unzip -p $APK lib/arm64-v8a/libsqlcipher.so | dd bs=1 skip=18 count=2 | od -An -tx1
#   4) b700 = AArch64 سليمة ✅ · 3e00 = x86-64 معطوبة ❌ · والحجم ~5,080,752 بايت
#   5) الأيقونة داخل الحزمة تطابق ic_launcher_foreground.png (فرق متوسط < 2)
```

🔴 **حادثة APK 2180 (2026-08-14):** التطبيق كان يفتح على شاشةٍ رمادية صامتة،
لأن النسخة الأولى من `seed_sqlcipher.sh` دهست **كل** مجلدات
`hooks_runner/download-*` بمكتبة لينكس x86-64 — بما فيها مكتبات **أندرويد** في
المخبأ المشترك، فحزمها غرادل. إشارةُ الإنذار التي فاتت: «زُرعت في 5 مواضع» بدل
اثنين. السكربت الآن يقرأ معمارية ELF ولا يلمس إلا x86-64، والتطهير قبل البناء
صار قاعدة.

⚠️ **لا مفتاح إنتاج:** البناء الحقيقي (`release` بلا لاحقة) **يفشل عمداً**
(قرار م68/م77: لا نشر بمفتاحٍ مكشوف). عند النشر الفعلي: مخزنٌ جديد +
`android/key.properties` + تحديث بصمة SHA-1 لعميل أندرويد في Google Cloud،
وحفظ المخزن فوراً — **فقدانه = استحالة تحديث التطبيق المنشور للأبد**.

---

## 8) الويندوز و CI

- **CI (`ci.yml`)**: analyze + الحزمة الكاملة + حارس الأعلام + حارس الأسرار.
- **بناء الويندوز (`windows-build.yml`)**: ينطلق تلقائياً عند الدمج في `main`.
- ⚠️ **`BUILD_NUM` داخله ثابتٌ نصّاً وما زال 2149** — تحديثه **يدوي من
  المالك** عبر واجهة GitHub (تذكيرٌ معلَّق له).
- الأيقونة في الويندوز: `windows/runner/resources/app_icon.ico` — **مُحدَّثةٌ
  محلياً فقط** (ثنائي) فلن تظهر في بناء CI قبل رفعها يدوياً.

---

## 9) خريطة الملفات

| الميزة | الملف |
|---|---|
| زيارة جديدة (نموذج مشترك) | `lib/features/records/add_record_screen.dart` (~3570 سطراً) |
| حافظ السجلات والتحاليل والبوابات | `lib/features/records/record_saver.dart` · `analysis_actions.dart` |
| بطاقة المريض | `lib/features/patients/patient_profile_screen.dart` |
| **هوية المريض والعزل (م181)** | `lib/features/patients/patients_logic.dart` — `IdentityIndex` · `identityOfRow` · `patientKeyFor` |
| الحجوزات هاتف / كمبيوتر | `lib/features/appointments/appointments_tab.dart` · `desktop/screens/appointments_desktop.dart` |
| دورة حياة الموعد (منطق نقي) | `lib/features/appointments/appt_lifecycle.dart` |
| نظام الدور (م177) | `lib/features/queue/queue_screen.dart` · `queue_add_sheet.dart` · `desktop/screens/queue_desktop.dart` |
| الأشعة | `lib/features/xrays/` (كاميرا · عارض · استوديو مقارنة · بطاقة + مقياس مساحة) |
| **الأرباح** | `lib/features/finance/profits_logic.dart` (النماذج: `MonthProfitRow`/`YearReport` بحقول `lab`/`analyses` و`net`/`netOff`/`afterLab`) · `profits_tables.dart` (الجداول + `showYearPnlFullSheet`) · `profits_section.dart` (هاتف) · `desktop/screens/profits_desktop.dart` |
| **التحاليل الثلاثية** | `lib/features/settings/analyses3.dart` (البوابة) · `finance/analyses_registry.dart` (السجل) · `analyses_filter.dart` |
| الخزينة/التركيبات | `lib/features/finance/treasury_logic.dart` · `treasury_tables.dart` |
| **المعالجات المقفلة (م181)** | `lib/core/locked_services.dart` |
| إدارة العيادات | `lib/features/settings/clinic_admin.dart` |
| الإعدادات | `lib/features/settings/settings_screen.dart` (~4725 سطراً) |
| الدخول والمصادقة | `lib/features/login/login_screen.dart` · `core/auth/*` · `data/cloud/gotrue_client.dart` |
| معالج ما بعد الدخول (م180) | `lib/features/auth/post_login_gate.dart` |
| مولّد الأيقونات (م182-184) | `tool/gen_icons.py` |
| ترحيلات Supabase | `supabase/migrations/` (آخرها `0066_delete_account_complete.sql`) |
| المزامنة | `lib/data/sync/*` — **لا تمسها إلا بطلبٍ صريح** |

---

## 10) حقائق تصميمية سارية (لا تنقضها)

- **العيادة إلزامية** عند التعدد؛ عيادةٌ واحدة ⇒ تلقائية بلا فلترة.
- دورة الموعد: النهائية تُختم `archivedOn` → أرشيف اليوم → حذفٌ بعد يومين
  بشواهد قبور. الحفظ الجديد `status: 'pending'`.
- الاستراحات `isBreak: 1` تمنع الحجز فوقها منعاً قاطعاً.
- هاتفٌ غير فارغٍ أقل من 10 أرقام ⇒ يُمنع الحفظ.
- **م173** زر الرجوع الهرمي: أي تبويب → الرئيسية؛ داخل عيادة → بوابة العيادات؛
  خزينة: تفاصيل حالة → التركيبات → الحركات → الخزينة.
- **م177** الحجز من بطاقة المريض: إن كان النظام «بالدور» يتحول تلقائياً للوحة
  الدور بورقةٍ معبأة. **طبقة بيانات الدور (quickAdd/مصالحة م56) لا تُمس.**
- الكاميرا الداخلية: هاتف فقط — المعاينة تعتمد إجبار الحاوية (`SizedBox.expand`)
  لا معادلات نسب (درس م173/ب-د).
- **م180** ميزة النِّسَب ثلاثية الدلالة (`ratesFeatureEnabled`): مطفأةٌ ⇒ نسبة
  الطبيب الحيّة صفر، واللقطات المجمَّدة القديمة **تبقى كما هي** (لقطةً-أولاً).
- **م181/أ** «تركيبات» معالجةٌ نظامية **مقفلة**: لا تُحذف في أي مكان، ولا سعر
  ثابت لها (`kVariablePriceLabel`) — ومربع سعرها محجوبٌ حتى في الإعدادات، مع
  تطهيرٍ تلقائي لأي سعرٍ قديم عبر `purgedLockedServicePrices`.
- **م181/ب** العزل الجذري للهوية: الاسم نفسه برقمٍ مختلف = ملفان مستقلان تماماً.
  الحلّ **قراءةً لا ترحيلاً**: `IdentityIndex` يورّث الهاتف عبر روابط
  (`debtId`/`recordId`/`prostheticId`/`analysisOf`) فتذوب الملفات الشبحية بلا
  كتابةٍ في البيانات.
- **م185** حذف الحساب: `delete_my_account()` في Supabase تُفرغ 9 جداول وتُخفي
  هوية أكواد التنشيط مع إبقاء `status='used'`، وFKs صارت `ON DELETE SET NULL`،
  وفيها `account_purge_gaps()` حارساً. مثبتٌ داخل معاملةٍ مُرجَعة (ROLLBACK).
- **م186** بطاقة الدخول **ثابتة الحجم** بين التبويبين (شرائحُ بارتفاعاتٍ ثابتة
  لا إظهارٌ وإخفاءٌ يُقلّص البطاقة)، واستعادةُ كلمة المرور **برمزٍ داخل
  التطبيق** (`/auth/v1/verify` type=recovery) لا برابطٍ من البريد.
- **م187** بوابة التحليل الثلاثي: **حجبٌ قاطع** حين الهوية مؤكَّدة (هاتف أو
  معرّفٌ حاملٌ للهاتف) في **أي عيادةٍ بالمركز**، و**تحذيرٌ قابل للتجاوز** حين
  التطابق بالاسم وحده (الصفُّ المُمضى يُوسم `triOverride: 1`).
  ⚠️ **معرّفٌ مشتقٌّ من الاسم (`n:اسم`) ليس إثباتَ هوية** — لذلك يُشترط
  `pid.startsWith('p:')` لليقين.
- **م187** الأرباح: قيمة المختبرات تُخصم **قبل** تقسيم النِّسَب، فصفّا «قيمة
  المختبرات» و«صافي بعد المختبرات» يجعلان الجدول متحقِّقاً من نفسه:
  `صافي بعد المختبرات = ربح الطبيب + ربح العيادة` حتماً.
- **م188** إيراد التحاليل الثلاثية **خاصٌّ بالعيادة**: لا يدخل «الإيراد» ولا
  «ربح الطبيب»، ويُضاف صفّاً تحت المصروفات ثم يُعاد جمع الصافي:
  `صافي ربح العيادة = حصة العيادة − المصروفات + التحاليل`.
  المصدر `analysesRevenue(records, period:)` — نفس قواعد بطاقة السجل (منعُ
  تكرارٍ بالمعرّف، و`incomeDate` يتقدّم على `date`) فلا يختلف رقمان.
  ⚠️ **لا تلمس شرط `isAnalysis` في `getMonthRecs`** — به تبقى التحاليل خارج
  قاعدة النِّسَب، وبإزالته تتضاعف وتُقسَم مع الطبيب.
- **م189** 🔑 **شكلٌ قانونيٌّ واحد للهاتف في فضاء الهوية**: `rowIdentityPhone`
  و`_pidPhone` كلاهما يمرّ على `normPhone`. كان الخام (`0919…`) يتعايش مع
  المسكوك في `patient_id` (`919…`) فيلد **ملفاً شبحاً** لنفس الشخص بصفر
  زيارات. والعرض يبقى بالرقم كما كُتب (`PatientAgg.phone` يقدّم الخام) —
  فالمفاتيح المشتقّة من هاتف العرض (المعلومات الطبية/الخطة/الأرشفة) لم تتغيّر.
  ⚠️ أي مقارنةٍ برقمٍ يكتبه المستخدم **تُطبَّع أولاً** (درس حارس التوأمة في
  `add_record_screen`: كان يقارن الخام بالقانوني فيسأل «سميّ جديد؟» للمريض نفسه).
- **م189** صفّ التحليل يُسكّ بهويته كاملة (هاتف + `patient_id`)، والبوابة
  والكاتب يقرآن الهاتف **الموروث** عبر `IdentityIndex.phoneOf` (معامل
  `phoneOfRow` في `lastTriAnalysisHit`) — فصفوف ما قبل م189 بلا هاتف تُحلّ
  عن زيارتها الأصل.
- **م189** الأرشفة **بالهوية**: مفتاح التحديد وحالة «مؤرشف» والدفعة كلها
  `medicalScopedKey(name, clinic, phone)` عبر `aggArchived`، مع **قراءةٍ
  متدرجة** تُبقي مفتاح «اسم|عيادة» القديم سارياً **للمجموعة غير المنقسمة
  وحدها** (فلا تُفقد أرشفة القدماء، ولا يجمع المفتاحُ القديم السميَّين).
- **م190** جدول الأرباح السنوي ([YearPnlTable]) نموذجان من مصدرٍ واحد بعلم
  `full`: الكامل تسعةُ أعمدة تنتهي بـ«صافي العيادة» **مظلَّلاً**، والمختصر
  للهاتف (إيرادٌ بعد المختبرات، بلا عمود مصروفات، وصافٍ شامل + علامة شرحٍ
  تفتح المعادلة بأرقام الصفّ). `showYearPnlFullSheet` تفتح الكامل بتمريرٍ
  أفقي من الهاتف. عمودا المختبرات/التحاليل يظهران **فقط حين لهما قيمة**.
- **م190** جداول السجل والأرباح: **نِسَبٌ (flex) واحدة للرأس والصفوف
  والتذييل** — لا عروضٌ ثابتة وسط أعمدةٍ متمددة (وإلا انكسر التناظر: بلاغ
  المالك). واختبارٌ يقيس تطابق مراكز الرؤوس والخلايا بأقل من بكسل.
- **م190** الاسم في سجل التحاليل يفتح ملف المريض بـ`identityOfRow(row, idx)`،
  وعمود الهاتف يردّ الشكل الخام من أي صفٍّ يشارك الهوية فلا يُعرض رقمٌ بلا
  صفر البدء.

---

## 11) عاداتٌ تكسر الاختبارات

- خط Ahem العريض ⇒ فيضاناتٌ لا تظهر على الجهاز؛ عالجها بـ
  `Expanded`/`Flexible`/`FittedBox`. تشخيص: استنسخ الاختبار مع
  `FlutterError.onError = dumpErrorToConsole`.
- SnackBars تصطف — صرّف الأولى (`pump(4-5s)`) قبل توقُّع الثانية.
- `FloatingActionButton`/`ShinyFab` بعد تبديل تبويب: `pumpAndSettle` قبل النقر.
- `MenuAnchor`/`MenuItemButton`: افتح ثم `pumpAndSettle`، وبعد النقر أعطِ
  إطاراً إضافياً — `onPressed` يتأخر لحين انغلاق القائمة.
- المسارات المدفوعة بالاختبار لا ترث `Directionality` — استعمل
  `MaterialApp(builder: (c, ch) => Directionality(rtl, ch!))`.
- «modify provider while building» ⇒ أجّل الكتابة بـ `addPostFrameCallback`.
- `TextEditingController` المستعمل في حواراتٍ: اجمعه في قائمةٍ وتخلّص منه مع
  الشاشة — وإلا «used after being disposed» أثناء حركة الإغلاق (درس م186).
- **`Expanded` داخل صفٍّ غير محدود العرض** (تمريرٌ أفقي أو `GestureDetector`
  يلفّ `Row`) ⇒ `RenderFlex ... unbounded width`. الحل: اجعل الغلاف نفسه
  `Expanded` (أو أعطِ العرضَ حدّاً بـ`SizedBox(width:)` قبل التمرير) —
  درس م190 عند جعل خلية «الصافي» قابلةً للضغط وورقةِ التكبير.
- **مفتاح إعداداتٍ غير مُدار:** `_tombs` في `kUnmanagedConfigKeys` — **لا
  يُكتَب ولا يُقرأ**؛ شواهد حذف الأوراق تولّدها المزامنة من فرق
  `configBase` (درس م181/أ: ساعةٌ ضائعة في تشخيص `tombs=null`).

---

## 12) سجل الميلستونات الأخيرة

| م | الوصف | PR |
|---|---|---|
| م177 | إعادة تنظيم الحجز بالدور | #38 |
| م178 | إعادة بناء قسم الأرباح: ثلاثة أقسام وجداول وتقرير سنوي | #39 |
| م179 | تنظيف الإعدادات + إصلاح محو سعر التحاليل | #40، #41 |
| م180 | إصلاح جلسة الموظفين + ميزة النِّسَب القابلة للإطفاء + معالج الإعداد وشاشة الدخول | #42، #43 |
| م181/أ | «تركيبات» معالجةٌ مقفلة بلا سعر | #44 |
| م181/ب | العزل الجذري لهوية المريض المتشابه | #45 |
| م182 | شعار DENTSHINE: أيقونة الجهازين + شاشة الدخول | #46 |
| م183 | أيقونةٌ بلا إطار (الشعار المجرّد على خلفيةٍ ممتدة) | #47 |
| م184 | التوسيط **البصري** للشعار (مركز ثقل ألفا×الإضاءة) | #48 |
| م185 | حذف الحساب بكل بياناته (ترحيل Supabase + حارس فجوات) | #49 |
| م186 | بطاقة دخولٍ ثابتة + تأكيد كلمة المرور + استعادةٌ برمز | #50 |
| م187 | هوية التحاليل بالهاتف + جدول السجل بهوية الحركات + قيمة المختبرات | #51 |
| م188 | إيراد التحاليل الثلاثية للعيادة + وثيقة التسليم | #52 |
| م189 | شكلٌ قانونيٌّ واحد للهاتف · عمود الهاتف في السجل · الأرشفة تعزل السميَّين | #53 |
| **م190** | **أعمدة المعادلة في الأرباح السنوية · تناظر أعمدة السجل · فتح ملف المريض منه** | **#54** |

**معلَّقٌ بطلب المالك:** توسعة قوالب استوديو المقارنة إلى عشرين (م175/ب) —
إضافةُ قالبٍ = إدخالُ بياناتٍ في `kCompareTemplates` فقط.

---

## 13) ما ليس في هذه الوثيقة — ولماذا

| السرّ | أين هو |
|---|---|
| مفتاح تشفير قاعدة البيانات | Keystore أندرويد / DPAPI ويندوز **داخل كل جهاز** — لا يغادر العتاد، وهذا جوهر حمايته |
| مفتاح إدارة Supabase (`sbp_…`) | حقلٌ في المهارة — لتعديل قوالب البريد آلياً (§14) |
| المخزن المحروق | `dental_dev.jks.compromised` — لا يُستعمل ولا يُنسخ |
| كلمات مرور حسابات المالك | معه — لا تُكتب في ملفٍّ أبداً |

---

## 14) قوالب بريد المصادقة (م186)

قوالب البريد تعيش في **طبقة إدارة Supabase** لا في قاعدة المشروع — لا يصلها
SQL ولا خادم MCP. المسار المؤتمت الوحيد: Management API بمفتاحٍ شخصي `sbp_…`:

```
RunWithCredentials({skillName:'dental-clinic-build',
  command:'bash skills/dental-clinic-build/update_recovery_template.sh'})
```
يقرأ `supabase/templates/recovery_email.html`، يطبّقه، ثم **يتحقق بقراءةٍ
راجعة** أن المخزَّن يحمل `{{ .Token }}` وبلا `{{ .ConfirmationURL }}`.
المفتاح يُنشأ بدقيقة من `supabase.com/dashboard/account/tokens`.
⚠️ يخوّل تعديل إعدادات المشروع كلها — يمرّ في ترويسة Authorization حصراً ولا
يُطبع ولا يُسجَّل.

---

## 15) حالة اللحظة (2026-08-22)

- كل شيءٍ حتى **م190** مدموج في `main`، والحزمة **1456** خضراء، والتحليل نظيف.
- آخر APK مُسلَّم: **2192** ⇒ التالي **2193**.
- **تذكيراتٌ معلَّقة على المالك:**
  1. رفع أيقونات DENTSHINE الثلاثة عشر يدوياً (`DENTSHINE_icons_m184.zip`)
     وإلا بقي بناء الويندوز بالأيقونة القديمة.
  2. تحديث `BUILD_NUM` في `windows-build.yml` (ما زال 2149).
  3. تدوير `GOOGLE_WEB_CLIENT_SECRET` ومفتاح Supabase العام.
  4. معلَّقٌ بطلبه من قبل: توسعة قوالب استوديو المقارنة إلى عشرين (م175/ب) —
     إضافةُ قالبٍ = إدخالُ بياناتٍ في `kCompareTemplates` فقط.

### أوّل ما تفعله في جولتك الأولى

```
1) FetchSkillScripts({skillName:'dental-clinic-build'})        ← المجلد يختفي بين الجولات
2) restore_secrets.sh ثم seed_sqlcipher.sh (§2، §3)
3) flutter analyze --fatal-warnings && flutter test            ← 1456 ~73 خضراء
4) اقرأ §10 (القرارات السارية) قبل لمس أي منطق — أكثرها مكتوبٌ بعد بلاغ مالكٍ
   حقيقي، ونقضُها يعيد علّةً كانت قد أُغلقت.
```

**عادةٌ يقدّرها المالك:** لا تُصلِح العَرَض — ابحث عن الجذر وأثبته بالبيانات
(كما في م189: الفرق بين `0919…` و`919…` في لقطةٍ واحدة)، ثم اكتب اختباراً
يحرس القرار، واذكر في التسليم **ما اكتشفتَه زيادةً على ما طُلب**.

---

## 16) بناء المهارة عندك — خمس دقائق

الوكيل الذي يستلم هذه الوثيقة يستطيع إعادة بناء مهارة `dental-clinic-build`
كاملةً بنفسه: **السكربتات في المستودع**، والوثيقة هي التوثيق، ولا يبقى إلا أن
يملأ المالكُ القيمَ السرّية في بطاقة المهارة.

### أ) السكربتات — جاهزةٌ في `tool/agent/`

| الملف | ما يفعله |
|---|---|
| `setup_toolchain.sh` | حاويةٌ جديدة من الصفر (~10 د): gcc/JDK 17 Corretto/شهادات cacerts/Flutter 3.44.8/Android SDK 36/بناء sqlcipher |
| `restore_secrets.sh` | يكتب `tool/cloud.env` و`tool/dev_keystore.env` و`android/app/dental_dev.jks` من متغيّرات البيئة ويتحقق من الأحجام والبصمة |
| `seed_sqlcipher.sh` | يزرع مكتبة لينكس للاختبارات — يقرأ معمارية ELF فلا يلمس مكتبات أندرويد (حادثة APK 2180) |
| `build_sqlcipher.sh` | يبني sqlcipher 4.7.0 بصيغة autosetup الجديدة |
| `update_recovery_template.sh` | يطبّق قالب بريد الاستعادة عبر Supabase Management API ويتحقق بقراءةٍ راجعة |

كلها **بلا أي قيمة سرّية**: تقرأ أسماء متغيّراتٍ فقط، فلذلك جاز تتبُّعها في git.

### ب) حقول الاعتماد الأحد عشر (أسماءٌ وأوصاف — **بلا قيم**)

| الحقل | النوع | ضروري | ملاحظة |
|---|---|---|---|
| `SUPABASE_URL` | نص | ✔ | مشروع `Dentaldk` — ref `qajgqatflmiiwqznxfha` |
| `SUPABASE_ANON_KEY` | سرّ | ✔ | المفتاح الحديث `sb_publishable_…` لا الـ JWT القديم (م84) |
| `SUPABASE_MGMT_TOKEN` | سرّ | — | `sbp_…` من `supabase.com/dashboard/account/tokens` — لقوالب البريد (م186) |
| `R2_WORKER` | نص | ✔ | عامل الأشعة على `workers.dev` |
| `PHONE_IDENTITY` | نص | ✔ | ⚠️ يطابق الإنتاج — تغييره يفصم هوية المرضى |
| `COLD_FETCH` | نص | ✔ | ⚠️ يطابق الإنتاج — لا يُغيَّر |
| `GOOGLE_WEB_CLIENT_ID` | نص | ✔ | ينتهي بـ `.apps.googleusercontent.com` |
| `GOOGLE_WEB_CLIENT_SECRET` | سرّ | — | للسجل فقط — يعيش في Supabase ← Auth ← Providers |
| `DENTAL_DEV_STORE_PASSWORD` | سرّ | ✔ | مخزن التطوير (2026-07-31) |
| `DENTAL_DEV_KEY_PASSWORD` | سرّ | ✔ | alias المفتاح: `dental` |
| `DENTAL_DEV_JKS_BASE64` | سرّ | ✔ | 3488 حرفاً — الملف 2616 بايت، البصمة تنتهي بـ `…890FB0EB` |

🔴 **القيم لا تُطلب في المحادثة ولا تُكتب في أي ملف** — بطاقةُ المهارة هي
القناة الوحيدة (قاعدة §2). ومن دون القيم تعمل كل خطوات التطوير والاختبار؛
ولا يتعطّل إلا بناءُ APK الموقَّع وقوالبُ البريد.

### ج) الخطوات

```
1) استنسخ المستودع، واقرأ هذه الوثيقة كاملة (§10 قبل أي منطق).
2) CreateSkill باسم dental-clinic-build:
   • documentation = هذه الوثيقة (أو ملخّصها + إرفاقها ملفاً)
   • scripts = ملفات tool/agent/*.sh الخمسة
   • credentialSchema = الجدول أعلاه (أسماءً وأوصافاً فقط)
3) اطلب من المالك ملء القيم في بطاقة المهارة — مرةً واحدة.
4) FetchSkillScripts ثم restore_secrets.sh ثم seed_sqlcipher.sh (§2، §3).
5) flutter analyze --fatal-warnings && flutter test  ⇒ 1456 ~73 خضراء.
```

بعدها تكون في نفس نقطة انطلاق الوكيل السابق حرفياً — بلا محادثةٍ ولا سياقٍ مفقود.

# Face Gallery Architectural Reference & Solutions Mapping

> **تاريخ التوثيق:** 31 أكتوبر 2026  
> **الهدف:** توثيق معماري شامل للحلول والتجارب المجربة في تطبيق **Face Gallery** (`d:\test\face gallary`) ومقارنتها بتطبيقنا الحالي **Your Gallery** (`D:\AndroidScan\gallary`)، وتحديد المسارات الدقيقة لكل ملف كود وموديل وخوارزمية للاستفادة منها مستقبلاً.

---

## 1. المسارات الرئيسية لتطبيق Face Gallery (`d:\test\face gallary`)

| الوصف | المسار على القرص |
|---|---|
| **المجلد الرئيسي للمشروع** | `d:\test\face gallary` |
| **دليل القرارات المعمارية (سجل شامل ADRs)** | `d:\test\face gallary\docs\DECISIONS.md` |
| **سياق المشروع وقواعد الذاكرة (CLAUDE.md)** | `d:\test\face gallary\CLAUDE.md` |
| **خطة العمل والمراحل (Project Plan)** | `d:\test\face gallary\docs\PROJECT_PLAN.md` |
| **المعمارية الأصلية الأوفلاين** | `d:\test\face gallary\Offline_Media_Recognition_Architecture.md` |
| **تعليمات البناء والتشغيل** | `d:\test\face gallary\BUILD.md` |
| **أدوات البايثون وسطح المكتب (FaceLab)** | `d:\test\face gallary\tools\facelab\` |
| **عقود الموديلات والـ Baselines** | `d:\test\face gallary\tools\artifacts\cartoon\baseline.md` |
| **سكريبت تصدير موديلات الأنمي** | `d:\test\face gallary\tools\facelab\export_characters_models.py` |

---

## 2. معضلة الأنمي والكرتون (Cartoon & Anime Face Recognition)

### 2.1 الوضع الحالي في Your Gallery
- **الملفات الحالية عندنا:**
  - `D:\AndroidScan\gallary\the app\drawn_faces.py`
  - `D:\AndroidScan\gallary\mobile\lib\domain\scan\drawn_faces.dart`
  - `D:\AndroidScan\gallary\mobile\lib\domain\scan\drawn_face_sweep.dart`
- **المنطق الحالي:**
  - تم حساب متجه اتجاهي موحد (Unit Mean) لـ 63 وجه كرتون عبر ArcFace (متجه 512 رقم مشفر Base64 في `DIRECTION_B64`).
  - أي وجه يكون الـ `cosine similarity` بين الـ embedding بتاعه والمتجه >= `0.20` يُعتبر وجه كرتون ويتم تجاهله تماماً في الـ People.
  - **القصور الحالي:** بيلقط ~90% من الأنمي، لكن الرسومات الواقعية (مانجا / Attack on Titan / شخصيات بتفاصيل بشرية دقيقة) بتفلت وتدخل People، بالإضافة إلى أن تمييز وتجميع شخصيات الكرتون في `Characters` معتمد على HumanArt وتوزيع ألوان ومظهر بدائي (160 رقم في `character-appearance@1`).

---

### 2.2 رحلة الحل في Face Gallery وتجارب الفشل السابقة
تطبيق Face Gallery مر بـ 12 مرحلة وتجربة (D-086 حتى D-132) مسجلة بالكامل في `docs/DECISIONS.md`:

#### أ. الفشل الأول: فلتر الألوان البدائي (`CartoonHeuristic.kt`)
- **المسار:** `d:\test\face gallary\app\src\main\java\com\facegallery\vision\CartoonHeuristic.kt`
- **الفكرة:** تصغير الوجه لـ 16×16 بكسل وحساب نسبة الألوان الفريدة (Unique Colors) ومعدل التشبع (Saturation).
- **النتيجة:** غير كافي تماماً بمفرده وبيفشل مع الصور ذات الخلفيات المتنوعة أو التدرجات الناعمة.

#### ب. الفشل الثاني (الكارثة D-097): المصنف العام (Photo vs Illustration Classifier)
- **القرار:** D-089 ثم D-097.
- **التجربة:** استخدام موديل ONNX يفحص كل وجه ويكتشف هل هو صورة أم رسمة.
- **الكارثة:** الموديل تدرب على بيانات اصطناعية، فكان يرى الصور الحقيقية ذات البشرة الناعمة أو الإضاءة الخافتة على أنها "رسمة"، مما أدى إلى **تفريغ تاب الأشخاص (People) تماماً ونقل كل البشر الحقيقيين لتاب الكرتون!**
- **الدرس المعماري المستفاد:** **ممنوع نهائياً وضع مصنف (Classifier) عام كـ Router رئيسي بين الحقيقي والكرتون.**

---

### 2.3 المعمارية الناجحة النهائية في Face Gallery (5 طبقات حماية)

#### الطبقة 1: التوجيه بناءً على الموديل الكاشف (Routing by Detector)
- **الملفات:**
  - `d:\test\face gallary\app\src\main\java\com\facegallery\vision\AnimeFaceDetector.kt`
  - `d:\test\face gallary\app\src\main\java\com\facegallery\vision\FacePipeline.kt`
- **الموديل المستخدم:**
  - `deepghs/anime_face_detection` (مبني على YOLOv8، بترخيص MIT مفتوح).
  - الموديل يدخل له صورة 640×640 ومخصص فقط للوجوه المرسومة.
- **القاعدة الذهبية:**
  - الوجه الذي يلتقطه `SCRFD` ⬅️ يذهب تلقائياً للأشخاص الحقيقيين (`People`).
  - الوجه الذي يلتقطه `AnimeFaceDetector` ⬅️ يذهب للشخصيات الكرتونية (`Characters`).
  - عدم وجود كشف أنمي يعني عدم وجود كرتون (بدون الحاجة لمصنفات ثانوية تفرغ الـ People).

#### الطبقة 2: حماية وجوه الأطفال الرضع (Baby-Face Veto - D-100)
- **الملفات:**
  - `d:\test\face gallary\app\src\main\java\com\facegallery\vision\FaceDedup.kt`
- **المشكلة:** بشرة الأطفال الرضع وعيونهم الكبيرة الواسعة كانت تجعل موديل الأنمي يلقطهم كأنهم كرتون ويدخلهم Characters!
- **الحل:**
  - تشغيل `SCRFD` بحد أدنى منخفض كـ Veto (`SCRFD_VETO_THRESH = 0.40`).
  - كشف الأنمي يُلغى فوراً (Veto) إذا تداخل معه كشف حقيقي من SCRFD بشرط:
    $$\text{IoU} \ge 0.50 \quad \text{OR} \quad \text{Containment} \ge 0.60$$
  - حيث الـ Containment يعني صندوق داخل الآخر بنسبة 60% فأكثر (لمنع ثغرة اختلاف أبعاد كشف الأنمي عن كشف البشر).

#### الطبقة 3: فض الاشتباك في الرسومات الواقعية والمانجا (Tie-Breaker - D-109)
- **الملفات:**
  - `d:\test\face gallary\app\src\main\java\com\facegallery\vision\IllustrationClassifier.kt`
- **الحالة:** كشف واقعي جداً لقطته SCRFD وفي نفس الوقت لقطه AnimeFaceDetector.
- **الحل:**
  - موديل `photo_vs_illustration.onnx` يُستدعى **فقط وحصرياً على مجموعة التقاطع (SCRFD ∩ Anime)**، ولا يُستدعى أبداً على الصور العادية.
  - لا يتم نقل الوجه من People إلى Characters إلا إذا تجاوز احتمال الرسم شرطاً صارماً:
    $$\text{DEMOTE\_THRESH} = 0.85 \quad (85\%)$$
  - وإذا لم تكن أوزان الموديل موجودة في التطبيق، يظل الباب آمناً وتظل الصورة في People.

#### الطبقة 4: استبعاد الشعارات والكلمات والشرائط (Aspect Ratio & Size Gates - D-117)
- **الملف:** `d:\test\face gallary\app\src\main\java\com\facegallery\vision\AnimeFaceDetector.kt` (الأسطر 90–97 و 140–146).
- **المشكلة:** التقاط كلمات وتكست مرسوم مثل "WAIFU" أو شعارات الألعاب كوجوه أنمي.
- **الحل الهندسي:**
  ```kotlin
  const val MIN_FACE_AR = 0.35f  // الحد الأدنى لنسبة العرض/الارتفاع
  const val MAX_FACE_AR = 1.8f   // الحد الأقصى (أي شريط عريض يتم استبعاده)
  const val MIN_FACE_PX = 20f    // استبعاد الأيقونات الصغيرة جداً
  const val DEFAULT_CONF = 0.55f // رفع عتبة الثقة من 0.307 إلى 0.55
  ```

#### الطبقة 5: التضمين والتجميع الدقيق للشخصيات (CCIP Character Embedding - D-099 & D-108)
- **الملفات:**
  - `d:\test\face gallary\app\src\main\java\com\facegallery\vision\CcipEmbedder.kt`
  - `d:\test\face gallary\app\src\main\java\com\facegallery\vision\CharacterAppearanceFeatures.kt`
  - `d:\test\face gallary\app\src\main\java\com\facegallery\cluster\CharacterClusterer.kt`
  - `d:\test\face gallary\app\src\main\java\com\facegallery\cluster\CharSimilarity.kt`
- **الهيكل المدمج (792 بُعداً):**
  1. **CCIP:** موديل `deepghs/ccip` (caformer-24، ترخيص OpenRAIL) يعطي متجه هوية أنمي حقيقي بحجم 768 بُعداً.
  2. **Outfit Hue:** استخراج هيستوجرام لألوان رداء الشخصية أسفل الوجه ($y_2 \to y_2 + 2.0h$) بحجم 16 بُعداً.
  3. **Hat/Hair Hue:** استخراج ألوان قبعة أو شعر الشخصية أعلى الوجه ($y_1 - 0.8h \to y_1$) بحجم 8 أبعاد.
- **حساب التشابه:**
  $$\text{Similarity} = 0.85 \times \text{CCIP} + 0.10 \times \text{Outfit} + 0.05 \times \text{Hat}$$
- **عتبات التجميع الصارمة لمنع الـ Mega-Clusters (D-122):**
  - $\tau_{\text{form}} = 0.80$ لإنشاء شخصية جديدة.
  - $\tau_{\text{assign}} = 0.70$ لضم وجه لشخصية موجودة.
  - شرط تصويت صوتين (2 votes) أو متوسط العناصر (Median) لمنع ربط شخصيات مختلفة في عنقود واحد (Anti-chaining).

---

## 3. مشاكل عامة وحلول معمارية أخرى خارج الأنمي

### 3.1 حل مشكلة انهيار الذاكرة OOM في المكتبات الكبيرة (D-131 & D-132)
- **المسار:** `d:\test\face gallary\app\src\main\java\com\facegallery\data\local\` و `PeopleRepository.kt`.
- **العَرَض:** كراش فوري عند وصول المكتبة لـ 34,000 وجه و 4,400 شخص على أجهزة سامسونج.
- **السبب الجذري:** استدعاء `.faces.isNotEmpty()` في الكويري كان يجبر قاعدة البيانات (ObjectBox) على سحب كائنات الوجوه بالكامل في الذاكرة ومحمل مع كل وجه متجه 512 + متجه 792 مظهر = استهلاك ~175 ميجابايت على الـ Main Thread.
- **الحل المطبق:**
  1. فصل بيانات المظهر في جدول جانبي `FaceCharAppearance` لا يُحمل إلا عند الحاجة.
  2. استبدال سحب الكائنات باستعلام خصائص خفيف (`PropertyQuery`) يسحب فقط `person_id` كأرقام `Long`، فانخفض استهلاك الوجه في الرام من 5.2KB إلى 2KB ومات الـ OOM تماماً.
- **الفائدة لمشروعنا:** تطبيق نفس العزل في استعلامات Drift و SQLCipher في Flutter، والتأكد من عدم جلب الـ `embedding` أو الـ `crops` في الـ Grid UI.

---

### 3.2 حل مشكلة المربعات الفارغة الشفافة في كاش الوجوه (D-129 Blank Preview Bug)
- **المسار:** `d:\test\face gallary\app\src\main\java\com\facegallery\ui\image\FaceCropRenderer.kt`
- **العَرَض:** ظهور كروت أشخاص بمربعات رمادية فارغة لا تتغير للأبد.
- **السبب:** عند حدوث خطأ مؤقت في فك التشفير (Decode glitch)، كان الكاش ينشئ صورة وهمية 1×1 بكسل شفافة ويحفظها في ملف الكاش ويخدمها بنجاح زائف دائم!
- **الحل:**
  1. الدالة ترجع `null` عند الفشل ولا تكتب أي شيء في الكاش.
  2. في قراءة الكاش: أي ملف حجمه 1×1 بكسل يُعامل فوراً كـ `Cache Miss`، مما يجعل الكاش يعالج نفسه ذاتياً (`Self-healing cache`).
- **المقارنة مع مشروعنا:** كود `CropCache.dart` عندنا سليم في الحجم (300MB LRU)، لكن يجب التأكد من إسقاط أي ناتج تالف أقل من 16×16 بكسل.

---

### 3.3 تتبع وجوه الفيديو وحماية قاعدة البيانات من التضخم (Track Compaction)
- **المسار:** `d:\test\face gallary\app\src\main\java\com\facegallery\track\`
- **العَرَض:** توليد آلاف الوجوه المكررة لنفس الشخص من فيديو واحد (كما حدث عندنا قبل v12 بـ 15,000 صف).
- **الحل في Face Gallery:**
  - بناء Track يربط الوجه عبر الفريمات (`IoU >= 0.3` مع فارق زمني <= 4 ثوانٍ و `cosine >= 0.65`).
  - تحديد سقف صارم: **بحد أقصى 5 وجوه فقط للـ Track الواحد**.
  - لا يُستبدل وجه قديم إلا إذا كان الوجه الجديد أعلى جودة بفارق واضح (+0.15).

---

### 3.4 العتبة الذكية المتكيفة وسجل التغذية الراجعة (Feedback Ledger - D-124 & D-125)
- **المسار:** `d:\test\face gallary\app\src\main\java\com\facegallery\cluster\PairCalibration.kt`
- **العَرَض:** عتبات التطابق الثابتة (مثل 0.40 أو 0.35) تكون صارمة جداً لبعض المستخدمين وضعيفة لآخرين.
- **الحل:**
  - جدول `IdentityFeedback`: يسجل كل قرار مستخدم (تأكيد أو رفض) كزوج حقيقي/مزيف.
  - حساب $\tau$ ديناميكي خاص بالجهاز ومكتبة المستخدم من خلال منحنى المعايرة المحلي (بمدى $\pm 0.05$).

---

### 3.5 منع عودة الوجوه المحذوفة عند إعادة المسح (Dismissal Index)
- **المسار:** `d:\test\face gallary\app\src\main\java\com\facegallery\vision\DismissalIndex.kt`
- **الحل:** حفظ بصمات المواقع أو الـ BBoxes للوجوه المرفوضة والمحذوفة لعدم إعادة إنشائها أثناء مسح الميديا مجدداً.

---

## 4. خطة التطبيق المقترحة لمشروع Your Gallery

| الأولوية | المهمة | الملفات المتأثرة عندنا | المرجع المقابل في Face Gallery |
|---|---|---|---|
| **1 (عاجل)** | إضافة شروط الأبعاد الهندسية (Aspect Ratio و Min Pixels) لمنع اللوجوهات والكتابات | `the app\analysis.py` و `drawn_faces.dart` | `AnimeFaceDetector.kt:decode` |
| **2 (متوسط)** | دمج فحص الـ Baby-Face مع الـ SCRFD Veto والتأكد من عدم حجب الأطفال الرضع | `the app\analysis.py` | `FaceDedup.kt:overlapsRealFace` |
| **3 (ترقية نوعية)** | إدخال موديل `deepghs/anime_face_detection` (YOLOv8 ONNX) كـ Router حقيقي بدل المتجه الفردي | `the app\mobile_api\engines.py` | `FacePipeline.kt` |
| **4 (تحسين المظهر)** | استبدال الـ 160-float appearance بموديل CCIP (768-d) لتجميع شخصيات الأنمي | `the app\analysis.py` | `CcipEmbedder.kt` |
| **5 (أمان الذاكرة)** | حماية كويريهات الموبايل (Drift) من تحميل الـ Embeddings أثناء تصفح الناس | `mobile\lib\data\db\` | D-131 / D-132 في `DECISIONS.md` |

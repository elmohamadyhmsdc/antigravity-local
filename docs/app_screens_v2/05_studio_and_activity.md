# 05 — الاستوديو والنشاط

المبدأ: الاستوديو = **إنشاء** (أدوات) + **مكتبتي** (نتائج/موديلات/datasets). النشاط (Scan + Jobs) = **شاشة واحدة عالمية** `/activity` — لا تتكرر في أي AppBar أو صف.

---

## ST1 — الاستوديو `/studio`
**القالب:** T1 · AppBar: "الاستوديو" · ⚙

`SegmentedBar`: **إنشاء ‖ مكتبتي**

### إنشاء
1. `ReadinessBanner` (PC غير مقترن / مشغول / الموديل ناقص) ← يوجّه إلى `/settings/computer` أو `/activity`.
2. أربع بطاقات أدوات `EntityCard(hero)` بترتيب ثابت:
   | الأداة | الوصف | Route |
   |---|---|---|
   | Reface | بدّل وجه في صورة/فيديو | `/studio/reface` |
   | Restyle | غيّر ملابس/مظهر | `/studio/restyle` |
   | Generate | ولّد صور بموديل شخص | `/studio/generate` |
   | Train | درّب موديل لشخص | `/studio/datasets/new` |
3. شريط **آخر النتائج** (أفقي، 6) + "عرض الكل" ← قسم "مكتبتي ▸ نتائج".

### مكتبتي
`FilterBar` chips: **نتائج ‖ موديلات ‖ Datasets** (chip واحد نشط) → `EntityGrid`:
- نتائج: `EntityCard(result)` + شارة الأداة (Reface/Restyle/Generate) ← ST8
- موديلات: `EntityCard(model)` + حالة (جاهز/يتدرب) ← ST9
- Datasets: `EntityCard(dataset)` ← ST6
- FAB حسب القسم: موديلات ← Generate · Datasets ← ST5 جديد.

> **مقصود:** مفيش صف "Activity" هنا ولا "Results" في AppBar. دول كانوا مكررين.

---

## قاعدة الـ Flows (ST2–ST7)
كلهم `FlowScaffold` ويتشاركوا:
- `Stepper` · `StickyActionBar` · `TargetPicker` · `IdentityPicker` · `JobSubmitBar` · `ReadinessBanner` · `AdvancedSection`.
- **مدخل ذكي:** لو الـ Query فيه `target` و`identity` كاملين → يقفز لخطوة المراجعة. لو ناقص → يبدأ من أول خطوة ناقصة.
- الخروج بتغييرات = `ConfirmSheet`.
- النجاح: `JobSubmitBar` يرسل ← Snackbar "بدأت المهمة · عرض النشاط" ← يرجع المستخدم لمصدر الدخول (الـ Viewer/الشخص) أو ST1.

---

## ST2 — Reface `/studio/reface`
Query: `target=media:ID[,det:ID]` · `person` · `face` · `identity`

| الخطوة | المحتوى |
|---|---|
| **1. الهدف** | `TargetPicker`: وسيط (صورة/فيديو) ← لو فيديو `VideoTrimmer` ← اختيار الوجه المستهدف من دوائر الوجوه (أو "كل الوجوه" مع تنبيه أن تبديل الفيديو يؤثر على كل الوجوه في المدى) |
| **2. الهوية** | `IdentityPicker`: شخص/شخصية (فلتر بحسب فضاء التضمين تلقائياً — ArcFace مع بشر / CCIP مع أنمي، ويمنع المزج) أو **طقم هوية** (3–5 صور) مع `IdentitySetEditor`، أو صور/فيديو مصدر (`reface-source-media`)، أو هوية **DFM مدرّبة** كطريقة مصدر اختيارية (لو موجودة) |
| **3. الخيارات والمراجعة** | **ملف الجودة:** Fast ‖ Balanced ‖ More detail (pipeline واحد موحّد، مفيش اختيار إصدار محرك) · **الاستعادة (Restoration):** تلقائي ‖ بدون ‖ موديل محدد، مع شرح لكل اختيار · `SwitchField` **كل الوجوه** (all-faces) · `SwitchField` **تعزيز الهوية** (identity boost) · معاينة · ملخص (هدف + هوية + مدة). **الخيارات الفعلية تبقى كما هي في `reface_options.dart` / `reface_screen.dart`** — الـ Flow يغيّر التنظيم مش الخيارات |
| **إرسال** | `JobSubmitBar` "ابدأ Reface" |

## ST3 — Restyle `/studio/restyle`
Query: `target=media:ID,det:ID`
1. **الهدف:** `TargetPicker` (جسم) + معاينة القناع (الأجزاء اللي هتتغير شفافة، الوجه والشعر والبشرة محفوظة).
2. **الوصف:** `PromptField` + presets ("فستان أحمر"، "بدلة"...).
3. **متقدم** (`AdvancedSection`): القوة · الخطوات.
→ `JobSubmitBar` "ابدأ Restyle".

## ST4 — Generate `/studio/generate`
Query: `model` · `media` (مرجع وضعية)
1. **الموديل:** `ModelPicker` (الجاهز فقط).
2. **الوصف:** `PromptField` (إيجابي + سلبي).
3. **وضعية مرجعية** (اختياري): `MediaPicker`.
4. **متقدم:** الأبعاد · CFG · الخطوات · Seed.
→ `JobSubmitBar` "ولّد".

## ST5 — بناء Dataset `/studio/datasets/new`
Query: `person` · `media`
1. **الشخص:** `PersonPicker` (أو مسبق).
2. **التجميع التلقائي:** يختار أفضل 15–30 وجه جودة؛ يعرضها `CropGrid` مع إمكانية الاستبعاد و"+ صور خارجية" (`MediaPicker`).
3. **حفظ** ← ST6.

## ST6 — محرر Dataset `/studio/datasets/:id`
**T3** · Header: اسم · عدد · ⋮ (إعادة تسمية · **تصدير zip** · حذف).
تبويبان: **الصور** (`CropGrid` + حذف + "+ صور") ‖ **الوصف** (قائمة captions قابلة للتعديل).
`QuickActions`: **درّب موديل** ← ST7.

## ST7 — التدريب `/studio/train?dataset=`
1. `DatasetPicker` (أو مسبق) · 2. الموديل الأساسي · 3. `StepperField` Epochs · `SliderField` Learning Rate (في `AdvancedSection`) · 4. "استئناف من آخر Epoch" لو موجود.
→ `JobSubmitBar` "ابدأ التدريب".

---

## ST8 — النتيجة `/studio/results/:id`
**القالب:** T5
- `CompareSlider` (قبل/بعد) للصور؛ فيديو: مشغلان متزامنان أو تبديل. `ExpandButton`.
- المنشأ (Provenance): الشخص · الموديل · الأداة · التاريخ · رابط للمهمة (A2).
- `QuickActions` (ثابتة): **حفظ في المعرض** · **مشاركة** · **تشغيل مرة أخرى** (يفتح الـ Flow بنفس المعاملات).
- ⋮: حذف (`ConfirmSheet` خطير يعرض التبعات: موديل/dataset مرتبط).

## ST9 — الموديل `/studio/models/:id`
**T3** · Header: اسم + trigger word · القاعدة · تاريخ · حجم.
`QuickActions`: **توليد** · **تدريب إضافي**. تبويبان: **النتائج** المصنوعة به ‖ **التدريب** (إحصائيات + Dataset المصدر).
⋮: إعادة تسمية · حذف.

---

## A1 — النشاط `/activity`
**القالب:** T2 · هذا هو **المكان الوحيد** لمراقبة الفحص والمهام.
AppBar: ← · "النشاط" · (إجراء: "مسح المنتهي").

`SegmentedBar`: **الآن ‖ السجل**

### الآن
1. **بطاقة الفحص** `ProgressCard(scan)` (تظهر لو فيه فحص):
   - المراحل الأربع: حصر/Hash → وجوه → أجسام/وضعيات → Embeddings/تجميع، كل واحدة بحالتها.
   - أزرار: **إيقاف مؤقت / استئناف** · "الملفات التي تعذر فحصها (N)" ← `FailedItemsSheet` (إعادة محاولة منفردة).
   - **نفس المكون** اللي في توسعة الـ `ActivityPill`.
2. **المهام الجارية والمنتظرة** `EntityList` من `ProgressCard(job)` (أيقونة النوع، العنوان، %، ETA) — إيقاف/إلغاء.

### السجل
`FilterBar`: الكل ‖ المكتملة ‖ الفاشلة. نقر على مهمة ← A2. فاشلة: `retry`. مكتملة: صورة مصغرة + `open` ← ST8.

## A2 — المهمة `/activity/:jobId`
**T3** · بيانات: ID · البداية/النهاية/المدة · المحرك والموديل · المعاملات.
تبويبان: **السجل** (SSE log مباشر) ‖ **المخرجات** (روابط ST8). `QuickActions`: `retry` / `cancel` / `runAgain`.

---

## ActivityPill (تذكير)
يظهر فوق الـ NavigationBar في كل التبويبات عند وجود نشاط. الضغط ← `/activity`. لو فشل شيء، يتحول للون التحذير حتى تفتحه.

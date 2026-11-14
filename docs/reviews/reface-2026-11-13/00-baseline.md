# تقرير خط البداية والتحقق من الإصلاحات الحالية (المرحلة 0)

التاريخ: 2026-11-13  
الحالة: منتهية وموثقة  
النطاق: Android Native (`D:\test\face gallary`) و Flutter (`mobile`) والسيرفر المشترك (`the app\mobile_api`).

---

## 1. ملخص حالة الإصلاحات السابقة

| الإصلاح / العنصر | موجود في المصدر | محمّل في السيرفر الحي | تم التحقق منه عمليًا | الملاحظات والقيود |
|---|---|---|---|---|
| تحرير محركات المسح قبل تشغيل Studio (`_release_scan_engines`) | نعم (`the app/mobile_api/studio_jobs.py:295, 370`) | غير محمّل (السيرفر غير مشتغل حالياً) | نعم (اختبار الوحدة `test_scan_engines_are_released_before_the_engine_runs`) | يمنع امتلاء VRAM في كروت 6GB بتفريغ InsightEngines تحت compute_lock |
| ضبط حدود الماسك لمنع تشوه الوجه والخلط (`mask_erode=0.0`, `mask_feather=0.02`) | نعم (`the app/face_compositor.py:114-115`) | غير محمّل (السيرفر غير مشتغل حالياً) | نعم (اختبارات `test_compositor.py` وقياس glintr100 في 2026-11-11) | قلل تسرب ملامح الوجه الأصلي من 0.28 إلى 0.11، ورفع الشبه من 0.53 إلى 0.68 |
| تدرج التركيز وترميز الفيديو بحسب Profile (Fast 16/medium, Balanced 14/medium, Detail 12/slow) | نعم (`the app/reface_config.py:6-10`) | غير محمّل (السيرفر غير مشتغل حالياً) | نعم (اختبارات 2026-11-09) | مطبق على مسار Unified في `reface.py` |
| فحص العمليات الحية ومنافذ السيرفر | نعم | السيرفر متوقف | تم الفحص | المنافذ 8443 و 8444 و 8445 لا تستمع حالياً ولا توجد عملية python تعمل في الخلفية |

---

## 2. مقارنة مساري الطلب: Android Native مقابل Flutter

### مسار التدفق:
- **Android Native**:
  `StudioScreen` ➔ `StudioViewModel.enqueueReface` ➔ `RefaceRequestBuilder.buildPayload` ➔ `DurableJobQueue.enqueue` ➔ `MobileApiClient` ➔ السيرفر (`/v1/jobs`).
- **Flutter**:
  `reface_screen.dart` ➔ `_submit()` ➔ `StudioRepository.enqueue` ➔ `StudioApi.enqueueInputs` ➔ `MobileApi` ➔ السيرفر (`/v1/jobs`).

### جدول الفروق الدلالية والخيارات بين التطبيقين:

| الخاصية / الخيار | Flutter (`mobile`) | Android Native (`D:\test\face gallary`) | الأثر الفعلي على النتيجة والتوافق |
|---|---|---|---|
| **نوع الـ Job (`type`)** | دائماً مسار Unified: `reface_image` أو `reface_video` | يعتمد على المحرك: `reface_image`/`reface_video` لـ `v3`، و `reface_image_v2`/`reface_video_v2` لـ `v2`، و `reface_image_dfm` لـ `dfm` | إذا اختار Native محرك v3 يعمل على نفس مسار Flutter Unified. الخيارات v2 و dfm خاصة بـ Native كمسارات قديمة/بديلة |
| **انتقاء وجوه المصدر (`source_faces`)** | يستخدم `StudioRepository.diverseSources` عبر خوارزمية `selectIdentity`: إقصاء الشواذ (Outliers) والتكرارات والتنويع حسب زاوية الرأس (Pose Diversity) | استعلام مباشر `ORDER BY quality_score DESC LIMIT 20` | Native يأخذ أعلى 20 وجهاً جودة حتى لو كانت كلها بنفس الزاوية أو لقطات متتالية، بينما Flutter يوفر عينات زوايا متنوعة تمنح تبديلاً أفضل في الزوايا الحادة |
| **تحديد وجوه الهدف (`target_faces` / `target_embeddings`)** | يدعم اختيار وجه محدد أو وجوه متعددة بدقة: يرسل `target_faces` (صناديق Bounding Boxes للصورة) و `encodeVideoTargetSelection` للفيديو | لا يدعم تحديد صناديق الهدف من الواجهة حالياً؛ يرسل وجوه المصدر فقط دون `target_faces` | في Native، السيرفر يبدل كل الوجوه التي تتطابق في الصورة أو الوجه الافتراضي، ولا يتيح للمستخدم استهداف شخص بعينه في لقطة متعددة الأشخاص |
| **إعداد الواقعية (`realism_preset`)** | يرسل `natural` أو `maximum_detail` أو `clean` | لا يرسله في `RefaceRequestBuilder` (السيرفر يستخدم `natural` كقيمة افتراضية) | تطابق سلوك الـ default، لكن Native يفتقد إمكانية اختيار `maximum_detail` للمستخدم |
| **وضع المعاينة السريعة (`preview`)** | يدعم `preview: true` (معاينة أول 3 ثوانٍ من الفيديو) | غير مدعوم في `RefaceOptions` أو في الـ ViewModel | لا يمكن لمستخدم Native طلب معاينة سريعة لـ 3 ثوانٍ قبل تشغيل الفيديو كاملاً |
| **قص الفيديو (`start_time` / `end_time`)** | يدعم `VideoTrimSelection` بالثواني ويرسلهما في الـ params | نموذج `VideoTrim` موجود في `RefaceRequestBuilder` لكن `StudioViewModel` لا يمرره (يبقى `null`) | في Native لا يستطيع المستخدم قص مقطع محدد من الفيديو داخل Studio |
| **ملف الجودة الافتراضي (`quality_profile`)** | `balanced` | `balanced` | متطابق |
| **تعزيز الهوية (`identity_boost`)** | `0.5` | `0.5` | متطابق |
| **المرمم (`restorer`)** | `auto` | `auto` | متطابق |
| **استخدام الماسك والمحجب (`parser` / `occluder`)** | `true` / `true` | `true` / `true` | متطابق |

---

## 3. خط الأساس للنظام والمحركات (Server Baseline)

1. **المسار الموحد في السيرفر (`the app/reface.py`)**:
   - المحرك الافتراضي: `RefaceEngineV3`.
   - محاذاة الوجه: القالب القياسي `_FFHQ_512` خماسي النقاط.
   - نموذج التبديل: `HyperSwap 1b` (`hyperswap_1b_fp16.onnx` أو `inswapper_128.onnx`).
   - المرممات المتاحة: `gpen_bfr_512`, `gpen_bfr_1024`, `codeformer`, `gfpgan_1.4`, `restoreformer_plus_plus`.
   - إعدادات الـ Compositor بعد إصلاح 2026-11-11:
     - `mask_erode = 0.0`
     - `mask_feather = 0.02`
     - `detail_transfer = 0.4` (natural) / `0.6` (maximum_detail)
     - `grain_match = 1.0`
     - `focus_match_strength = 0.5` (balanced) / `0.25` (detail) / `1.0` (fast)

2. **الذاكرة و VRAM**:
   - كارت الشاشة المرجعي للمشروع: NVIDIA RTX 4050 Laptop (6 GB VRAM).
   - مسار التفريغ: دالة `_release_scan_engines()` في `mobile_api/studio_jobs.py` تستدعي `ctx.engines.unload()` لتحرير محركات المسح قبل بدء عملية الـ Reface.
   - أثر الإصلاح: في 72 فريم 1080p بجودة Most detail، انخفض زمن الفريم من ~5971 ms (عند تكدس محركات المسح واللجوء لـ Shared Memory) إلى ~819 ms.

---

## 4. الفجوات التي يجب سدها بين Native و Flutter في المراحل اللاحقة

1. **انتقاء الوجوه المتنوعة في Native**: نقل منطق `selectIdentity` (outlier rejection + pose diversity) إلى Android Native ليتطابق مع ما تم إنجازه في Flutter، بدل أخذ أول 20 وجهاً بالجودة المجردة.
2. **تحديد وجوه الهدف في Native**: تفعيل تمرير صناديق الوجه المستهدف في الصور و vectors في الفيديو.
3. **تفعيل إعدادات المعاينة والقص في Native**: ربط `preview` و `videoTrim` في `StudioViewModel`.
4. **تأكيد جاهزية السيرفر للتشغيل**: إعطاء أمر التشغيل الصحيح للسيرفر المشترك عند بدء تجارب القياس (المرحلة 1).

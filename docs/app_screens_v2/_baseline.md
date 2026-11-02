# خط الأساس والتجهيز — المرحلة P0 (`_baseline.md`)

> **تاريخ القياس:** 2026-11-02
> **الفرع:** `main` (وفقاً لتوجيه المستخدم الصريح بالتنفيذ المباشر على main دون فروع منفصلة)
> **Commit التنسيق:** `838cdc5` (`style: format 28 dart files in mobile codebase`)
> **إصدار قاعدة البيانات (Schema):** v18

---

## 1. نتائج القياس الفعلي (Fresh Baseline Evidence)

| الفحص | الأداة | النتيجة | التفاصيل |
|---|---|---|---|
| **التحليل الساكن** | `flutter analyze` في `mobile/` | ✅ **0 issues** | نظيف تماماً (`No issues found!`, 145.0s) |
| **مجموعة الاختبارات** | `flutter test` في `mobile/` | ⚠️ **890 ناجح، 12 فاشل** | زمن التشغيل: 01:12، موزعة على 5 ملفات فقط |
| **تنسيق الكود** | `dart format` | ✅ **تم التنسيق** | 28 ملفاً تم تنسيقهم وعمل commit منفصل لهم (`838cdc5`) |
| **هيكل المجلدات الجديد** | مجلدات v2 | ✅ **تم الإنشاء** | `lib/ui/`, `lib/domain/actions/`, `lib/domain/corrections/` |

---

## 2. تشخيص الاختبارات الفاشلة الـ 12 الموروثة (Legacy Test Failures)

جميع الاختبارات الـ 12 الفاشلة ناتجة عن **تغييرات مقصودة في الواجهة والعقود** تمت في جلسات سابقة، بينما بقيت بعض ملفات الاختبار القديمة تتوقع واجهات أو مفاتيح أو سلوكيات سابقة:

### أ) `test/data/operation_contracts_test.dart` (فشل واحد)
- **اسم الاختبار:** `capabilities distinguish legacy unknown from installed model-aware paths`
- **السبب الفعلي:** الاختبار يتحقق من `current.supportsOperation('reface_reference', 'character', mediaType: 'video')` ويتوقع `isTrue`. لكن في fixture `Capabilities.operation_support.json`، العملية `reface_reference` للـ `character` مُعلّمة بأنها `"experimental": true`. دالة `supportsOperation` تفترض افتراضياً `allowExperimental = false` وبالتالي ترجع `false`.
- **المرحلة المسؤولة:** P0 / P1.
- **الحل:** تمرير `allowExperimental: true` للاختبار لمطابقة العقد المحدث.

### ب) `test/features/characters_test.dart` (فشلان)
1. **اسم الاختبار:** `character Reface entry requires a source face reference`
   - **السبب:** واجهة Reface تم توحيدها لمسار الـ 3 خطوات، والاختبار يبحث عن نص 'Hero' في مسار قديم.
2. **اسم الاختبار:** `characters are listed like people, apart from people, and open the same detail page`
   - **السبب:** الاختبار يتوقع وجود زر الاستوديو `person-use-studio` لشخصية أنمي (Hero). لكن بقرار تصميمي موثق ومقصود: `p.kind == 'person'` فقط هو من يظهر له زر الاستوديو (`Studio remains specific to real people`).
- **المرحلة المسؤولة:** P6a (الأشخاص والشخصيات).

### ج) `test/features/marks_ui_test.dart` (فشلان)
1. **اسم الاختبار:** `marking a tattoo stores the area, its position and the patch for the body's person`
2. **اسم الاختبار:** `a body nobody owns cannot be marked, and says why`
   - **السبب الفعلي:** كلا الاختبارين يحاولان الضغط على زر `action-mark-tattoo` داخل bottom sheet. الزر يقع عند الإحداثي Y=848 وهو خارج حدود الشاشة الافتراضية (الارتفاع 800)، فتفشل النقرة (`tap derived an Offset outside the bounds`). الاختبار يحتاج فقط `tester.ensureVisible` قبل الضغط.
- **المرحلة المسؤولة:** P6b (الوشوم والمراجعة).

### د) `test/features/people_simplified_ux_test.dart` (فشل واحد)
- **اسم الاختبار:** `character tools stay isolated and People works from a direct link`
- **السبب الفعلي:** الاختبار يفحص قائمة أدوات الشخصية (Hero) ويتوقع وجود زر `people-action-exportTraining`. ولكن كود `person_detail_screen.dart` يقيد تصدير التدريب صراحة للأشخاص الحقيقيين فقط (`if (p.kind == 'person')`).
- **المرحلة المسؤولة:** P6a (الأشخاص).

### هـ) `test/features/reface_reference_test.dart` (6 إخفاقات)
- **الاختبارات:**
  1. `choosing a character source after replace-all restores explicit target selection`
  2. `character target photo uses its explicitly selected normalized face box`
  3. `reference video preserves human target embedding without converting CCIP source`
  4. `reference video preserves character target embedding without converting CCIP source`
  5. `character source uses explicit pixels and blocks legacy PC`
  6. `character source uses explicit pixels and queues reference photo`
- **السبب الفعلي:** الاختبارات تعتمد على عناصر ومفاتيح قديمة (مثل `reface-target-kind-person` وخطوات قديمة) كانت موجودة قبل توحيد شاشة Reface إلى معالج موحد من 3 خطوات (`reface_options.dart`).
- **المرحلة المسؤولة:** P8a (الاستوديو وReface).

---

## 3. حسم الأسئلة المعمارية المفتوحة (بنود ◐ في `01_shared_components.md`)

تم فحص الكود المصدري وقاعدة البيانات بالتفصيل، والإجابات كالتالي:

1. **عضوية cluster الوضعية/الطقم (`body_pose_matches` و `body_outfit_matches`):**
   - **الواقع في الكود:** كلا الجدولين يحتويان على عمود `state` بقيم `auto` | `manual` | `rejected`.
   - **الحل:**
     - التأكيد (`confirm`): تحويل الحالة إلى `manual`.
     - الرفض (`reject`): تحويل الحالة إلى `rejected` (تمنع إعادة إضافتها تلقائياً).
     - فك الربط (`unlink`): حذف السطر أو تحويله إلى `auto` لإعادة التقييم التلقائي.
     - إعادة التعيين (`reassign`): رفض السجل الحالي وإدخال سطر جديد لـ `categoryId` المستهدف بحالة `manual`.

2. **الوشوم والعلامات (`BodyMarks`):**
   - **الواقع في الكود:** جدول `BodyMarks` يربط الشخص بـ `personId` (Cascade delete)، ويربط الجسم بـ `sourceBodyId` (SetNull delete)، وموقع الوشم `anchor` يُحسب نسبياً للنقاط التشريحية للجسم (`anchor keypoints` مثل المرفق والرسغ).
   - **الحل:** الـ `anchor` **مستقل تماماً** عن هوية الشخص وقائم على إحداثيات الجسم التشريحية؛ لذا يمكن نقل العلامة/الوشم لشخص آخر عبر تحديث `personId` ببساطة ويبقى الـ `anchor` صالحاً 100%.

3. **علاقة "جسم ≈ جسم" وفصلها (`notSamePerson` على الأجسام في الـ Track):**
   - **الواقع في الكود:** الرابط مشتق من اشتراك الأجسام في نفس الـ `track_id` و `link_method = event_outfit`.
   - **الحل:** عند تطبيق `notSamePerson` على جسمين في نفس المسار:
     - يتم فصل المسار بإعطاء الجسم وتوابعه اللاحقة `track_id` جديداً ومستقلاً.
     - يتم تسجيل زوج الاستبعاد في جدول `body_distinct` أو `body_overrides` (في Schema v19 بـ P2) لمنع دالة `expandTracks` أو التجميع التلقائي من إعادة دمجهم.

4. **الأدوات (`equipment_objects`):**
   - **الواقع في الكود:** مؤكد وجود الأعمدة `bboxX`, `bboxY`, `bboxW`, `bboxH` في الجدول.

5. **نطاق "هذه اللقطة" بعد دمج إطارات الفيديو (`VideoCompactor`):**
   - **الواقع في الكود:** عملية الـ Compaction تدمج إطارات المسار المتتالية في صف تمثيلي واحد داخل `bodies` وتشاركه صفوف `media_detections`.
   - **الحل:** لتجنب تعقيد تقسيم الصفوف التمثيلية وتضاربها مع `media_detections`، ينحصر نطاق `ScopePicker` للفيديو في خيارين نظيفين:
     1. **هذا الظهور / المسار (This appearance / track)**: يؤثر على الصف التمثيلي وإطاراته.
     2. **كل الفيديو (Whole video)**: يؤثر على جميع مسارات الشخص في هذا الفيديو.

---

## 4. خريطة الاختبارات والشاشات والمراحل (Test Migration Map)

| مجموعة الاختبارات الحالية | الشاشة الحالية المقابلة | الشاشة والمسار الجديد v2 | المرحلة المسؤولة |
|---|---|---|---|
| `library_test.dart`, `native_gallery_instant_test.dart` | `LibraryScreen` | L1: `/library` | **P5a** |
| `media_library_uri_test.dart`, `video_media_view_test.dart`, `viewer_gestures_test.dart`, `media_screen_native_player_test.dart` | `MediaScreen` | L3: `/media/:id` | **P5b** |
| `people_screen_test.dart`, `people_simplified_ux_test.dart`, `characters_test.dart` | `PeopleScreen` | P1: `/people` | **P6a** |
| `person_detail_screen_test.dart`, `person_media_test.dart` | `PersonDetailScreen` | P2: `/people/:id` | **P6a** |
| `identity_groups_test.dart` | `IdentityGroupsScreen` | P3: `/groups/:id` | **P6a** |
| `review_screen_test.dart`, `quick_review_test.dart` | `ReviewScreen` | P4: `/review` | **P6b** |
| `merge_screen_test.dart` | `MergeScreen` | P5: `/merge/:a/:b` | **P6b** |
| `organize_media_screen_test.dart` | `OrganizeMediaScreen` | P6: `/people/:id/files` | **P6b** |
| `marks_ui_test.dart` | `PersonMarksScreen` | P4 / L3 (Inspector) | **P6b** |
| `bodies_screen_test.dart`, `body_inspection_sheet_test.dart`, `pose_matching_precision_test.dart`, `body_universal_naming_test.dart` | `BodiesScreen` | E1: `/explore`, E2: `/explore/:kind` | **P7** |
| `reface_screen_test.dart`, `reface_reference_test.dart` | `RefaceScreen` | ST2: `/studio/reface` | **P8a** |
| `lora_screens_test.dart`, `studio_results_test.dart` | `LoraScreens`, `ResultsScreen` | ST1: `/studio`, ST4: `/studio/generate` | **P8b** |
| `settings_screen_test.dart`, `backup_screen_test.dart`, `app_lock_test.dart` | `SettingsScreen` | `/settings` | **P4** |
| `welcome_screen_test.dart`, `connection_screen_test.dart`, `qr_scan_test.dart` | `WelcomeScreen`, `ConnectionScreen` | O1: `/welcome`, O2: `/pair` | **P4** |

---

## 5. قائمة المفاتيح الرئيسية المستهدفة للحفظ (Key Inventory)

تلتزم المراحل بالحفاظ على هذه الـ Keys أو تحديث اختباراتها بوضوح:
- **المعرض:** `library-photos-tab`, `library-albums-tab`, `gallery-more`, `scan-indicator-idle`, `scan-indicator-active`.
- **العارض:** `media-view-details`, `media-open-native-player`, `media-open-native-player-bottom`, `video-mute-toggle`, `media-box-menu`.
- **الأشخاص:** `people-search`, `open-all-types`, `open-people`, `open-characters`, `person-menu`, `person-title`, `person-use-studio`, `tab-photos`, `tab-identity`, `tab-models`.
- **الأجسام والاستكشاف:** `tab-all`, `tab-poses`, `tab-outfits`, `tab-group-poses`, `tab-equipment`, `tab-areas`, `body-inspect-skeleton`, `body-inspect-areas`.
- **الاستوديو:** `reface-target`, `reface-all-faces`, `reface-quality-profile`, `reface-identity-boost`, `reface-preview`, `reface-next`.
- **المراجعة:** `review-tab-faces`, `review-tab-bodies`, `review-quick-button`, `review-compact-videos`.

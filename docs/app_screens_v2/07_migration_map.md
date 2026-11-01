# 07 — خريطة الانتقال والتنفيذ

## 1. من القديم إلى الجديد

كل شاشة/Sheet موجودة اليوم في `mobile/lib/features/` ← مكانها في v2.

| القديم | الجديد | ملاحظة |
|---|---|---|
| `WelcomeScreen` | O1 | |
| `QrScanScreen` + `ManualPairScreen` | O2 `/pair` (SegmentedBar) | دمج |
| `PermissionsScreen` | O3 | |
| `HomeScreen` | **يُحذف** | إحصائيات ← S3؛ Scan ← `ScanInviteStrip` + Activity؛ Review ← `ReviewInboxBanner`؛ Reface/Results ← Studio؛ Jobs ← Pill؛ Backup reminder ← S6؛ حالة PC ← S2 |
| `InsightsScreen` | S3 (قسم "نظرة عامة") | |
| `LibraryScreen` + `NativeGallery` | L1 | |
| `FolderScreen` | L2 | |
| `MediaScreen` + `VideoMediaView` | L3 | زر المشغل الخارجي في مكان واحد |
| (قائمة `_boxMenu`) | `EntityActionSheet(Face\|Body)` | |
| `ImagePreviewScreen` | L4 | |
| `PeopleScreen` (+ `/characters`) | P1 (`kind` segment) | |
| `PersonDetailScreen` | P2 | تبويب الأجسام يعيد استخدام E2 |
| `IdentityGroupsScreen` + `_GroupMediaScreen` | P1 (قسم مجموعات) + P3 | |
| `UnsortedScreen` | P4 `queue=unsorted` | |
| `ReviewScreen` / `QuickReviewScreen` / `ReviewEntryScreen` | P4 `queue=suggestions` + صفحة الطوابير | |
| `AlbumReviewScreen` | P4 `queue=suggestions&album=` | |
| `ReviewMediaViewer` | درج "قارن" داخل P4 + L3 | |
| `SimilarFacesScreen` | P4 `queue=similar` | |
| `MergeScreen` | P5 | |
| `OrganizePersonMediaScreen` | P6 | |
| `PersonMarksScreen` + `_MarkDialog` | P2 ▸ أجسام ▸ وشوم + E2 `marks` + `MarkEditor` | |
| `TrainingExportDialog` | ST6 `exportDataset` | |
| `DiscoverScreen` | E1 | |
| `BodiesScreen` (6 تبويبات) | E2 (`all/poses/outfits/groupPoses/equipment`) | تبويب Areas ما يتنقلش (08 §1 "خارج نطاق v2"، افتراض #7) |
| `EquipmentPhotoScreen` / `GroupPoseResultsScreen` | E3 | |
| `BodyInspectionSheet` | `BodyInspectSheet` | |
| `body_naming` dialogs / `_GroupNameDialog` ×2 | `NameSheet` | |
| `VideoActionsScreen` | E2 `kind=actions` | |
| `VideoActionDetailScreen` | E4 | |
| `ActionExampleScreen` | E5 | |
| `StudioScreen` | ST1 | |
| `RefaceScreen` (+ helpers) | ST2 | |
| `RestyleScreen` | **لا يتغير** | خارج نطاق v2 (08 §1): نفس الشاشة و`/restyle` ومدخلها في Studio |
| `LoraGenerateScreen` | ST4 | |
| `DatasetBuildScreen` | ST5 | |
| `DatasetScreen` | ST6 | |
| `LoraTrainScreen` | ST7 | |
| `LoraScreen` | ST1 ▸ مكتبتي (موديلات/Datasets) | |
| `ModelDetailScreen` | ST9 | |
| `ResultsScreen` | ST1 ▸ مكتبتي ▸ نتائج | |
| `ResultDetailScreen` | ST8 | |
| `JobsScreen` | A1 | |
| `JobDetailScreen` | A2 | |
| `RunningScanScreen` + `ScanProgressCard` | A1 (بطاقة الفحص) + `ActivityPill` | مكون واحد `ProgressCard(scan)` |
| `SourcesScreen` | S3 | |
| `AnalyzeScreen` | S3 "حلّل ملف..." | |
| `SettingsScreen` | S1 | |
| `ConnectionScreen` | S2 | |
| `BackgroundScreen` | S7 | |
| `StorageScreen` | S5 | |
| `BackupScreen` + `password_dialog` | S6 + `PasswordSheet` | |
| `AppLockGate` | S4 (الغلاف + الإعدادات) | |
| `PlaceholderScreen` | يُحذف | |

## 2. ما يُحذف صراحةً
- `HomeScreen` وزر "Overview" في قائمة المعرض و`Routes.home`.
- كل أيقونات "Activity"/"Results" في AppBars (Studio، Discover، Jobs، Library).
- صفوف Studio المكررة: "Models" / "Datasets" / "Activity" / "Results" كصفوف مستقلة تفتح `/lora` أو `/jobs`.
- قوائم ⋮ في جذور التبويبات (Library، People).
- كل `Navigator.of(context).push` (27 موضع) ← routes أو Sheets.
- `Routes.characters` كمسار مستقل (يصبح `/people?kind=character`).

## 3. Routes: القديم ← الجديد
| قديم | جديد | يتفعّل في |
|---|---|---|
| `/jobs`, `/jobs/:id` | `/activity`, `/activity/:jobId` | P3 |
| `/running-scan` | `/activity` (قسم الآن) | P4 |
| `/results`, `/results/:id` | `/studio?tab=library&type=results`, `/studio/results/:id` | `/results`: P8b · `/results/:id`: P3 |
| `/lora`, `/lora/model/:id` | `/studio?tab=library&type=models`, `/studio/models/:id` | `/lora`: P8b · `/lora/model/:id`: P3 |
| `/lora/build`, `/datasets/:id`, `/lora/train`, `/lora/generate` | `/studio/datasets/new`, `/studio/datasets/:id`, `/studio/train`, `/studio/generate` | P3 |
| `/reface?person=&face=&identity=&media=&target=` | `/studio/reface?person=&identity=&target=media:{media},det:{target}` (`face` يفضل مقروء) | P3 |
| `/restyle` | **يفضل زي ما هو** (خارج نطاق v2) | — |
| `/discover` | `/explore` (جذر التبويب) | P3 |
| `/bodies?personId=&similar=&colours=&tab=` | `/explore/:kind` بنفس الباراميترات، و`tab` يتترجم لـ `kind`: 0 all · 1 poses · 2 outfits · 3 groupPoses · 4 equipment. `tab=5` (Areas) حسب افتراض #7 | P7 |
| `/marks?personId=` | `/explore/marks?person=` | P7 |
| `/characters` | `/people?kind=character` | P6a |
| `/people/unsorted?kind=` | `/review?queue=unsorted&kind=` | P6b |
| `/review?view=&kind=` | `/review?queue=&kind=` (ترجمة قيم `view` لـ `queue` تتكتب في P6b من `ReviewEntryScreen`) | P6b |
| `/sources`, `/analyze?characters=`, `/insights` | `/settings/library` (`characters` يتنقل لقسم "حلّل ملف...") | P4 |
| `/connection` | `/settings/computer` | P3 |
| `/pair/scan`, `/pair/manual?host=&port=` | `/pair` (`host`/`port` يملوا اليدوي) | P4 |
| `/storage`, `/background`, `/backup` | `/settings/storage`, `/settings/background`, `/settings/backup` | P3 |
| `/home` | حذف | P9 |

(المسار القديم يفضل شغال لحد المرحلة المكتوبة في العمود الأخير، وبعدها يبقى `redirect` عشان أي deep link أو اختبار قديم. **P3 بيفعّل بس المسارات اللي الجديد فيها بيعرض نفس الشاشة القديمة**؛ الباقي بيجمع كذا شاشة أو محتاج سلوك مش موجود قبل مرحلته. الترتيب في `router.dart`: الثابت قبل المتغير، زي `/people/unsorted` قبل `/people/:id`.)

## 4. أخطاء التوثيق القديم المصححة
- كان يذكر `features/actions/` — الفعلي `features/video_actions/`.
- كان يعتبر `/characters` شاشة منفصلة.
- كان يضع Results ضمن Studio فقط، لكن الكود فيه أيضاً مدخل من Home وJobs وPerson وMedia.
- كان يصف 4 تبويبات في الـ nav بينما `AppShell` تعليقه يقول "Home, People, Library, Studio, Jobs" (تعليق قديم).

## 5. ترتيب التنفيذ المقترح (كل مرحلة قابلة للاختبار لوحدها)

> **النسخة التفصيلية المعتمدة في `08_implementation_plan.md`** (P0–P9، مع المهام والملفات والاختبارات). الجدول تحت ملخص قديم أولي.

| # | المرحلة | الناتج | اختبار القبول |
|---|---|---|---|
| 1 | **الأساس المشترك** | `ActionRegistry`, `EntityCard`, `CollectionView`, `NameSheet`, `ConfirmSheet`, `Pickers`, `ProgressCard`, `SelectionController/BulkActionBar` | Widget tests لكل مكون + golden للحالات الأربع |
| 2 | **الـ Shell والتنقل** | 4 تبويبات + `ActivityPill` + `TabRootScaffold` + routes الجديدة مع redirects | لا يوجد `Navigator.push`؛ كل route له redirect؛ قاعدة AppBar مفروضة باختبار |
| 3 | **Activity + Settings** | A1/A2 + S1–S7 (أبسط ويحرر الباقي من تكرار) | الفحص يتحكم من مكان واحد فقط |
| 4 | **Library + Viewer** | L1–L4 | 0ms reload؛ الإيماءات؛ زر المشغل الخارجي واحد |
| 5 | **People + Review** | P1–P6 | كل طوابير المراجعة تعمل من P4؛ Merge ذري |
| 6 | **Explore** | E1–E5 + `BodyInspectSheet` | قواعد مطابقة الوضعية بنفس النتائج؛ تقييد الشخص يعمل في P2 |
| 7 | **Studio** | ST1–ST9 | `Target` الموحد؛ القفز للخطوة المناسبة؛ الجاهزية |
| 8 | **حذف القديم** | حذف الملفات/الـ routes المهجورة | `flutter analyze` صفر، `flutter test` أخضر |

## 6. تغييرات قاعدة بيانات الهاتف المطلوبة (نموذج التصحيح الموحد)

الباقي في v2 شاشات فقط فوق بيانات موجودة. **ده الجزء الوحيد اللي يحتاج schema جديد** (مرجعه 01 §5.2، علامة 🆕). البيانات كلها على الهاتف، فمفيش تغيير في API الـ PC أو الـ contract.

| # | المطلوب | الحل المقترح | ملاحظات |
|---|---|---|---|
| 1 | جسم "ملوش صاحب" | `body_overrides` بمفتاح asset + box + وقت (مصدر الحقيقة) + `bodies.ownership` كـ cache | الموجود `body_rejections` بيرفض شخص محدد فقط، فمش كفاية |
| 2 | جسم "مش جسم أصلاً" | نفس `body_overrides` + `bodies.hidden` كـ cache، يستثنيه من كل العدادات والتجميع | الأجسام ملهاش `hidden` النهاردة (الوجوه عندها). 39 ملف بيقرأ `bodies` |
| 3 | فك ربط جسم بدون رفض | دالة `unlinkBody` بدون كتابة في `body_rejections` | |
| 4 | جسم ≈ جسم "ليسوا نفس الشخص" | جدول أزواج `body_distinct`، والـ redetect والـ compactor ينقلوه للصف الجديد، و`BodyLinkGuard` يفرضه في كل مسار كتابة ومنها الدمج | الرابط نفسه مشتق مش متخزّن؛ التعريف في P0 |
| 5 | وجه "ملوش صاحب" | `faces.ownership` + `face_overrides` بمفتاح asset + box + وقت | `review_dismissed` مش كفاية: `deletePerson` وتجاهل المراجعة بيكتبوه كمان. الصفوف القديمة ما تتحولش |
| 6 | تصحيح ظهور فيديو كامل | عمود `scope` في `body_overrides`/`face_overrides`، وصفوف الـ track تورث override نطاقه `track` | `expandTracks` الحالي للوجوه غير المعيّنة بس، فالنطاق تنفيذ جديد |

**خارج النطاق:** رفض/ملكية/فصل clusters المناطق (08 §1 "خارج نطاق v2").

كل بند يتنفذ بـ: migration لإصدار schema جديد · تحديث `app_database.g.dart` (`dart run build_runner build`) · إدراج الجدول في `backupTables` · احترامه في `grouping_inputs`/`plan_applier`/`photo_result_store`/`redetect`/`video_compactor` (على الهاتف؛ `person_linking` Python والـ contract مجمّد) · اختبارات تشمل "إعادة الفحص ما تمسحش التصحيح" · تحديث `docs/ANTIGRAVITY_HANDOFF.md`.
**يتأكد قبل البدء:** البنود ◐ في 01 §5.2 (عضوية الـ cluster، الوشوم، تعريف جسم ≈ جسم).

---

## 7. معايير قبول عامة (تُفحص آلياً قدر الإمكان)
1. `grep -rn "Navigator.of(context).push\|Navigator.push" mobile/lib/features` ← صفر نتائج (خارج استخدام داخلي لـ `showModalBottomSheet`).
2. لا ملف خارج `features/activity/` يستدعي `Routes.activity` إلا `ActivityPill` و S1 وSnackbar `JobSubmitBar`.
3. لا يوجد `AlertDialog`/`SimpleDialog` للتسمية أو التأكيد خارج `NameSheet`/`ConfirmSheet`.
4. كل `EntityActionSheet` يُبنى من `ActionRegistry` (اختبار يقارن بالمصفوفة في 01 §3).
5. كل شاشة من T1 تحقق قاعدة "≤ 1 إجراء + ⚙" (اختبار widget).
6. التنقل الداخلي: من أي شاشة إلى أي كيان **≤ 3 نقرات**.
7. اختبارات الـ Keys القديمة (مثل `studio-reface`, `welcome-scan-qr`) تُنقل أو تُحدّث مع الشاشة، لا تُحذف بدون بديل.
8. من أي صورة أو فيديو: كل عنصر مكتشف (وجه/جسم/أداة) وكل رابط بين عنصرين يوصله `CorrectionSheet` من `MediaInspector` في ≤ 2 نقرة، والنتيجة نفسها لو جيت من Person أو Explore أو P4.
9. اختبار لكل فعل تصحيح: بعد "ملوش صاحب" / "ليس هذا الشخص" / "ليسوا نفس الشخص" → إعادة فحص + إعادة تجميع + إعادة اكتشاف **ما بيرجعوش الربط**؛ و`Undo` بيرجّعه.
10. الفيديو: تصحيح بنطاق "هذا الظهور" يطبّق على كل إطارات الـ track ويفضل بعد إعادة فحص بإطارات مختلفة، وبنطاق "هذه اللقطة" يطبّق على ±500ms فقط (إزاي، أو هل النطاق ده هيفضل، يتحسم في P0 لأن الصف الواحد بيمثل كذا إطار بعد الـ compaction).

## 8. أسئلة مفتوحة (قرارات لازم تتأكد منها قبل التنفيذ)
0. ~~معنى "ملوش صاحب"~~ — **محسوم (2026-11-02):** العنصر يفضل ظاهر في المعرض والاستكشاف ومعلَّم "بدون مالك"، ويُستبعد من الربط التلقائي والاقتراحات والتدريب فقط. المستخدم يحدد صاحبه لاحقاً. التفاصيل في 01 §5.1 و04 (فلتر "بدون مالك").
1. **الوشوم في Explore:** هل تبقى "حسب الشخص" فقط (مثل الحالي) أم تُعرض مجمّعة؟ (الـ spec يفترض: تطلب شخص أولاً.)
2. **بحث عام:** هل نضيف بحث شامل (أشخاص + أنشطة + ألبومات) أعلى Explore؟ لم يُضف لأنه ليس feature موجود.
3. **تبويب الاستوديو "مكتبتي":** فصله إلى تبويب خامس "نتائجي"؟ الـ spec يبقيه داخل Studio للحفاظ على 4 تبويبات.
4. **تبويب Areas القديم:** يتشال نهائياً ولا يفضل في `bodies_screen.dart`؟ (08 افتراض #7، قبل P7.)

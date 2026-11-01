# 08 — خطة التنفيذ (للتنفيذ على مراحل في Antigravity)

> **الحالة:** خطة فقط — لا شيء منها اتنفّذ. كل مرحلة = **جلسة مستقلة** في Antigravity.
> **المرجع:** باقي ملفات `docs/app_screens_v2/` (الـ spec). الخطة بتقول **إيه يتعمل وبأي ترتيب وإزاي نتأكد**؛ الـ spec بيقول **الشكل النهائي**.
> **أساس الواقع (2026-11-02):** schema الهاتف `currentSchemaVersion = 18`، قياس فعلي: **890 اختبار Flutter ناجح و12 فاشل** في 5 ملفات (`reface_reference` 6، `characters` 2، `marks_ui` 2، `people_simplified_ux` 1، `operation_contracts` 1)، و`flutter analyze` نضيف، و`lib/features/` فيه 78 ملف وملفات كبيرة (`media_screen.dart` 1614 سطر، `reface_screen.dart` 1485، `lora_screens.dart` 1442، `person_detail_screen.dart` 1089، `people_screen.dart` 1071، `review_screen.dart` 938، `bodies_screen.dart` 931).

---

## 0. إزاي تشغّل الخطة

1. **افتح جلسة جديدة لكل مرحلة** (مش كلها في جلسة واحدة) — كل مرحلة مكتوبة بحيث تفهمها لوحدها.
2. أول رسالة في الجلسة (انسخها وغيّر رقم المرحلة):

```text
نفّذ المرحلة P{N} من docs/app_screens_v2/08_implementation_plan.md §3.
اقرأ بالترتيب: CLAUDE.md ← docs/ANTIGRAVITY_HANDOFF.md (أول 40 سطر + فقرة "Screens redesign spec v2")
← docs/app_screens_v2/README.md ← الملفات المذكورة في "للقراءة" بالمرحلة.
التزم بالقواعد العامة في §1 (ومنها "خارج نطاق v2") وبالنطاق (داخل/خارج) حرفياً. لا تبدأ مرحلة تانية.
مسموح لك تشغّل داخل mobile/: flutter analyze / test / gen-l10n، dart run build_runner build،
dart format، dart fix --apply. وgit branch / add / commit على فرع المرحلة بس. أي أمر تاني اسألني عنه.
في الآخر: dart format + dart fix + flutter analyze (صفر) + flutter test، حدّث الـ handoff، اعمل commit على فرع المرحلة،
وارجع بتقرير: اللي اتعمل / اللي اتختبر فعلاً / اللي اتأجل أو فشل (بدون تجميل).
```

3. **الترتيب والاعتماد:**

```
P0 ─┬─► P1 ─► P3 ─┬─► P4
    │             └─► P5a ─┬─► P5b ─► P5c ─► P6a ─┬─► P6b
    │                      │                      └─► P7
    │                      └─► P8a ─► P8b
    └─► P2  (لازم يخلص قبل P5c)
                              كلهم ─► P9
```
| المرحلة | الحجم | تعتمد على | ممكن بالتوازي مع |
|---|---|---|---|
| P0 خط الأساس | S | — | — |
| P1 الأساس المشترك | L | P0 | **P2** |
| P2 طبقة التصحيحات (schema v19) | L | P0 | **P1 / P3** |
| P3 الـ Shell والتنقل | M | P1 | P2 |
| P4 النشاط + الإعدادات + البداية | M | P3 | P5* / P6* / P7 / P8* |
| P5a المعرض + الألبوم | M | P3 | P4 |
| P5b عارض الوسائط | L | P5a | P4 / P8* |
| P5c المفتش + شاشة التصحيح | L | P5b, P2 | P4 / P8* |
| P6a الأشخاص + الشخص + المجموعات | L | P5c | P4 / P8* |
| P6b المراجعة + الدمج + التنظيم + الوشوم | L | P6a | P4 / P7 / P8* |
| P7 الاستكشاف | L | P6a | P4 / P6b / P8* |
| P8a الاستوديو + Reface | L | P5a | P4 / P5b / P5c / P6* / P7 |
| P8b LoRA + النتائج + الموديلات | L | P8a | P4 / P5b / P5c / P6* / P7 |
| P9 التنظيف والتدقيق | M | الكل | — |

> **التوازي اختياري.** أسلم مسار: تسلسلي. لو هتوازي: كل جلسة في worktree/فرع مستقل يبدأ من commit المرحلة اللي بتعتمد عليها. نقاط الدمج: `app_en.arb` و`router.dart` والملفات المولّدة المتتبَّعة (`app_localizations*.dart` و`app_database.g.dart`). الملفات المولّدة ما تتحلّش يدوياً: بعد الدمج يتعاد توليدها. (P3 بيجهّز `router.dart` بحيث كل مرحلة بعده تبدّل `builder` فقط.)

---

## 1. القواعد العامة (تنطبق على كل مرحلة)

### بيئة وأمان
1. **الهاتف:** لا تشغيل/تثبيت/تجربة على الهاتف أو الـ emulator. فقط `flutter analyze` و`flutter test` على الـ PC. تجربة الهاتف يعملها المستخدم على الـ APK بعد ما تقول "خلصت".
2. **حزم:** لا إضافة أو ترقية في `pubspec.yaml` بدون موافقة صريحة. لا تغيير في Android native (`mobile/android/`) إلا لو المرحلة بتقول.
3. **الـ contract مع الـ PC:** `the app/mobile_api/contract/` لا يتغير في أي مرحلة. كل بيانات المستخدم على الهاتف.
4. **بيانات المستخدم الحقيقية:** الاختبارات على قاعدة in-memory (`test/support/harness.dart` → `appTest`/`TestEnv`) فقط. لا لمس لأي مكتبة/وسائط حقيقية.
5. **Git:** الـ spec اتعمله commit في `f9f79b8`. أي تعديل لاحق عليه أو على الـ handoff لازم يتعمله commit بموافقة المستخدم قبل P0، وإلا أي worktree جديد مش هيشوفه. فرع لكل مرحلة `v2/pN-<name>` يبدأ من commit المرحلة اللي بتعتمد عليها، وcommit واحد آخر المرحلة على فرعها (افتراض #8). لا push ولا merge على `main` إلا بطلب المستخدم. لو لقيت في شجرة العمل تغييرات مش تبعك، لا تلمسها.

### جودة
6. **بعد كل مرحلة:** `dart format lib test && dart fix --apply` ثم `flutter analyze` = **صفر** (حتى الـ infos) ثم `flutter test` كله أخضر ما عدا الموروث المسجّل في `_baseline.md` (P0). أي اختبار أحمر موروث يتسجل في التقرير ولا يتخفى، وأي أحمر جديد يوقف المرحلة. (28 ملف غير منسّق حالياً، فـ P0 ينسّقهم في commit منفصل عشان ما يدخلوش في diff مرحلة تانية.)
7. **Characterization قبل إعادة الهيكلة:** لأي شاشة كبيرة هتتفكك، شغّل اختباراتها الحالية الأول وسجّل النتيجة، وبعد التغيير لازم تفضل خضراء (أو تتنقل/تتحدّث بقصد وتتوثق).
8. **كل مكون جديد** له widget test يغطي: الحالات (loading/empty/error/content/selecting لو قائمة)، text scale 2.0 على عرض 320dp بدون overflow، `Semantics` للأزرار الأيقونية، وأهداف لمس ≥ 48dp.
9. **Keys:** الاختبارات الحالية معتمدة على Keys (≈437 key فريد في `features/`). لا تحذف Key قبل ما تنقل اختباره؛ لو الاسم اتغير حدّث الاثنين وسجّل التغيير في التقرير.
10. **schema:** أي تعديل في `lib/data/db/tables.dart` ← `dart run build_runner build` وتتضمّن `app_database.g.dart` في التغيير + migration test + إدراج في `.agbackup`.
11. **l10n:** كل نص ظاهر للمستخدم **بالإنجليزي** في `lib/l10n/app_en.arb` ثم `flutter gen-l10n` (الـ placeholders بترتيب تعريفها في الـ ARB). لا نصوص hard-coded جديدة، ولا نصوص عربية في الواجهة. *(قرار محسوم — افتراض #1 تحت.)*

### معمارية (ثابتة في كل المراحل)
12. **مواقع الكود الجديد:** `lib/ui/` (مكونات عرض مشتركة) · `lib/domain/actions/` (Registry) · `lib/domain/corrections/` (التصحيحات) · `lib/features/<screen>/` (الشاشات). `features/shared/*` الحالية تفضل شغالة (تُغلَّف أو تُعاد تصديرها) لحد P9.
13. **Strangler:** الشاشات القديمة تفضل موجودة ومربوطة لحد ما مرحلتها تبدّلها؛ الحذف النهائي في **P9** فقط (إلا لو المرحلة تنصّ). **كل مرحلة تفعّل redirects صفوفها في 07 §3 (عمود "يتفعّل في") مع نفس التغيير اللي بيبدّل الشاشة، مش قبله،** وتضيف حالاتها في `router_test`.
14. **التنقل:** صفر `Navigator.push` في أي كود جديد أو معدّل؛ الـ Sheets بـ `showModalBottomSheet` فقط؛ لا `AlertDialog`/`SimpleDialog` للتسمية أو التأكيد (استخدم `NameSheet`/`ConfirmSheet`). الاستثناءات المسموحة بس: حوارات التقدم وتأكيد الـ pairing/بصمة الشهادة، وأي تأكيد أمني يتنقل لـ Sheet لازم يفضل الإغلاق بالسحب أو بالضغط برّه معناه رفض.
15. **الإجراءات:** أي قائمة/Sheet/شريط تحديد تُبنى من `ActionRegistry`. ممنوع قائمة مكتوبة يدوياً.
16. **ملفات جديدة صغيرة:** لا ملف شاشة فوق ~600 سطر؛ فكّك بالاستخراج.

### خارج نطاق v2 (قرار 2026-11-02) — أقوى من باقي الـ spec لو اختلفوا
1. **ربط مناطق الجسم المكشوفة بالأشخاص:** لا جداول `cluster_rejections`/`cluster_distinct`، ولا `body_clusters.ownership` — **انتبه:** ده غير `bodies.ownership` بتاع P2 (الأخير **داخل النطاق**: مصدر حقيقة لـ"ملوش صاحب" على مستوى الجسم؛ أما `body_clusters.ownership` فهو ملكية الـ cluster المكشوف وده الخارج النطاق، لأن `body_clusters.personId` أصلاً cache مشتق من روابط الأجسام) — ولا `kind=areas` في Explore، ولا طبقة "مناطق" في الـ Viewer، ولا صف "منطقة/cluster ← شخص" في `CorrectionSheet`، ولا `assignPerson`/`rename` على منطقة. `body_areas.dart` و`exposed_matching.dart` ما يتطوروش (مستقبل التبويب القديم: افتراض #7).
2. **Restyle:** لا إعادة بناء ولا تحسين. `RestyleScreen` و`/restyle` ومدخله الحالي في Studio يفضلوا زي ما هم، وST3 والـ route `/studio/restyle` مش جزء من الخطة.
3. **الحارس الوحيد المسموح في الكود ده:** أي مسار بيكتب `bodies.person_id` أو `review_body_links` (ومنها `exposed_matching`) لازم يتخطى الأجسام `ownership='none'`/`hidden`، عشان تصحيح المستخدم ما يترجعش. **ويدخل في ده اشتقاق مالك الـ cluster المكشوف:** "ملوش صاحب" في P2 بيسيب `bodies.person_id` زي ما هو ويعتمد على إن القراءات تتخطى `none`/`hidden`، لكن استعلام المالك في `exposed_matching.recomputeOwner` (الـ `COALESCE(f.person_id, b.person_id)` اللي بيكتب `body_clusters.personId`) مش كتابة مباشرة في `bodies.person_id`/`review_body_links`، فمش مغطّى بنص الحارس حرفياً — وبعدين `publishSuggestions` يزرع `review_body_links` من الـ cache البايت. فلو تبويب Areas فضل (افتراض #7)، لازم اشتقاق `body_clusters.personId` يتخطى `none`/`hidden` كمان. (الخطورة منخفضة دلوقتي لأن المسار كله ورا `body_clusters_enabled` وهو OFF افتراضياً؛ لو #7 حُسم بحذف التبويب في P9 النقطة دي بتلغى.)
4. **يفضل في النطاق:** علامة "حساس" لإخفاء الوسائط وقفلها، وتصحيحها (`userState`, `sensitiveOverride`).

### نقاط تحقق الهاتف (يعملها المستخدم على APK بيطلبه)
المراحل دي فيها سلوك الاختبارات على الـ PC ما تقدرش تثبته، فما تتبنيش عليها مراحل قبل ما المستخدم يأكد أو يقرر التأجيل:
- **بعد P2:** migration v19 على المكتبة الحقيقية، وهي اتجاه واحد. لازم `.agbackup` جديد قبل التثبيت (نسخة v19 ما تترجعش على APK أقدم).
- **بعد P3:** التنقل، الـ pairing وروابط `agmobile://`، والـ Pill.
- **بعد P5b:** الفيديو zero-copy، الإيماءات، والمشغل الخارجي.
- **بعد P8b:** مهام Reface وLoRA الفعلية.
- **قبل حذف P9:** قائمة التحقق الكاملة.

### التقرير (آخر كل جلسة، وفي الـ handoff)
- اللي اتعمل (ملفات رئيسية) · الاختبارات: **العدد الفعلي** اللي اتشغل ونجح (لا أرقام تقديرية) · اللي **لم يُختبر** (مثلاً سلوك على جهاز حقيقي) · أي ◐ اتأكد منه · أي انحراف عن الـ spec بسببه.

### افتراضات مفتوحة (تتأكد من المستخدم قبل P0 لو مختلفة)
| # | الافتراض | لو اختلف |
|---|---|---|
| 1 | ✅ **محسوم (2026-11-02): الواجهة إنجليزي فقط** (`app_en.arb`)؛ التسميات العربية في الـ spec وصف لا غير. 01 §2 عربي بس، فـ P0 يضيف عمود تسمية إنجليزية بإعادة استخدام مفاتيح ARB الموجودة (مثلاً "No owner"، "Not this person") | لو اتغير لاحقاً: مرحلة P10 منفصلة (ARB عربي + RTL + مراجعة كل الـ Layouts) |
| 2 | الوشوم في Explore تطلب شخص أولاً | تعديل صغير في P7 |
| 3 | مفيش بحث عام | — |
| 4 | "مكتبتي" (نتائج/موديلات/Datasets) داخل تبويب Studio | لو تبويب خامس: تعديل في P3/P8a/P8b |
| 5 | رسم **منطقة يدوية** في الـ Viewer ميزة جديدة؛ تتأجل لآخر P5c ويمكن إسقاطها | — |
| 6 | الـ Reface يحافظ على الخيارات الحالية (ملف جودة Fast/Balanced/More detail، الاستعادة، كل الوجوه، تعزيز الهوية)؛ الـ spec بيغيّر التنظيم مش الخيارات | — |
| 7 | تبويب Areas القديم (وراء `body_clusters_enabled`، مقفول افتراضياً) **ما يتنقلش**. لازم قرار قبل P7: يتشال نهائياً (توصية الريفيو) ولا يفضل في `bodies_screen.dart` القديم | لو فضل: `bodies_screen.dart` و`body_areas.dart` ما يتحذفوش في P9 |
| 8 | مسموح commit واحد آخر كل مرحلة على فرعها | لو لأ: التنفيذ تسلسلي في شجرة عمل واحدة، من غير توازي ولا فروع |
| 9 | S4 بينقل قفل التطبيق الحالي بس. مهلة القفل وPIN مش موجودين، وحماية لقطات الشاشة اتشالت بطلب المستخدم (الـ handoff) | لو عايزهم: مهام جديدة في P4 بطلب صريح |

---

## 2. جدول المخرجات النهائية للتحقق (يتتبع في P9)

| الفحص | الأمر / الطريقة | المتوقع |
|---|---|---|
| لا تنقل خارج الـ router | الأمر (أ) تحت الجدول | صفر، ما عدا الاستثناءات المكتوبة في `_baseline.md` (L4 `ImagePreview` overlay، حوار التقدم في `people_actions`) |
| لا Dialog للتسمية/التأكيد | الأمر (ب) تحت الجدول | صفر للتسمية والتأكيد؛ الباقي استثناءات قاعدة 14 بس |
| Activity في مكان واحد | الأمر (ج) تحت الجدول | `ActivityPill` + إعدادات + Snackbar `JobSubmitBar` + redirects فقط |
| 4 تبويبات | اختبار الـ Shell | 4 وجهات |
| AppBar جذور التبويبات | اختبار widget لكل T1 | ≤ 1 إجراء + ⚙، بدون ⋮ |
| Registry = المصفوفة | اختبار `action_registry_matrix_test` | يطابق 01 §3 بعد تصحيحها في P0 |
| كل إجراء له تنفيذ | اختبار `action_dispatcher_test` | مفيش `ActionId` متاح في الـ Registry من غير handler |
| كتابة روابط الأجسام | اختبار `body_writers_guard_test` | كل مسار كتابة بيعدّي على `BodyLinkGuard` أو مستثنى بسبب مكتوب |
| كل فعل تصحيح | `correction_service_test` | يطابق 01 §5.2 |
| الصحة العامة | `flutter analyze` / `flutter test` | صفر issues / أخضر |

أوامر الفحص من جذر الريبو (`rg` مش `grep`، لأن الشيل الأساسي PowerShell):
```text
(أ) rg -n "MaterialPageRoute|PageRouteBuilder|avigator(\.of\([^)]*\))?\.push" mobile/lib/features mobile/lib/ui
(ب) rg -n "AlertDialog|SimpleDialog|showDialog" mobile/lib/features mobile/lib/ui
(ج) rg -n "Routes\.activity" mobile/lib
```

---

## 3. المراحل

### P0 — خط الأساس والتجهيز · (S)
**الهدف:** نعرف نقطة البداية بالأرقام ونحسم الغموض قبل ما نكتب كود.
**للقراءة:** `CLAUDE.md`، الـ handoff، `07_migration_map.md`، `01_shared_components.md` §5.2.

**المهام**
1. أنشئ الفرع `v2/p0-baseline` (بعد ما تتأكد إن الـ spec كله متعمله commit، قاعدة 5). نسّق الـ 28 ملف في commit منفصل من غير أي تغيير تاني.
2. شغّل `flutter analyze` و`flutter test` وسجّل: عدد الاختبارات، زمن التشغيل، وكل اختبار أحمر. المتوقع 12 فاشل (أول الملف؛ إخفاقات Restyle في الـ handoff تخص `the app/test_undress.py` مش Flutter).
3. **الـ 12 فاشل:** حدد لكل واحد السبب (كود اتكسر ولا اختبار قديم بعد redesign سابق) من غير ما تصلحه، وارجع للمستخدم بالقرار: يتصلح في P0 ولا يتسجل موروث. دي شبكة الأمان بتاعة P6a/P6b/P8a، فالتصليح هو الأفضل قبلها.
4. أنشئ `docs/app_screens_v2/_baseline.md` فيه: (أ) النتيجة فوق، (ب) جدول **اختبار ← الشاشة اللي بيغطيها ← المرحلة اللي هتنقله** (§4 نقطة بداية)، (ج) قائمة الـ Keys لكل ملف شاشة، (د) استثناءات فحوص §2.
5. **تحقق من بنود ◐** في 01 §5.2 بقراءة الكود وسجّل الجواب في `_baseline.md`:
   - عضوية cluster الوضعية/الطقم: `body_pose_matches.state` و`body_outfit_matches` (مفيش جدول `pose_tags`). إزاي تتعدّل؟
   - الوشوم/العلامات: `BodyMarks.personId` مطلوب وCascade (`domain/marks/body_marks.dart`, `mark_tattoo.dart`). هل ينفع تتنقل بين أشخاص، والـ `anchor` يفضل صالح؟
   - **"جسم ≈ جسم":** مش رابط متخزّن؛ مشتق من `trackId` و`linkMethod = event_outfit`. عرّف بالظبط: `notSamePerson` على جسمين في نفس الـ track يعمل إيه، وازاي `expandTracks` ما يرجعش ينشر التصحيح عليهم؟
   - الأدوات: `equipment_objects` فيها x,y,w,h ✔ مؤكد بالقراءة.
   - **نطاق "هذه اللقطة" بعد الـ compaction:** في الفيديو الصف الواحد بيمثل كذا إطار (الباقي صفوف في `media_detections`)، فتغيير `person_id` على الصف بيأثر على كل إطاراته مش ±500ms بس. حدد إزاي اللقطة تتفصل (مثلاً صف جديد للإطارات دي) ولا النطاق ده يتشال من `ScopePicker`، وحدّث 01 و07 §7 حسب الجواب.
6. **صحّح 01 §2–§3 قبل ما تتحول لاختبار خلية بخلية** (وإلا الاختبار هيفرض فقد ميزات). قارن بالواجهة الفعلية (`_boxMenu`، قائمة AppBar وشيت التفاصيل في `media_screen.dart`، القوائم في `people_actions.dart`) وسجّل كل فرق:
   - امسح تكرار `notThisPerson`.
   - أضف `ActionId` لـ: `redetect`، تغيير نوع الملف كله (`_fileKindMenu`، النهارده "—" في عمود Photo)، المشغل الخارجي، `box-equipment`، إجراءات الألبوم (تضمين/استبعاد من الفحص، مراجعة، تحليل).
   - أضف أعمدة Album وGroup وAction، وطابق QuickActions الشخص بين P6a والمصفوفة، وQuickActions الجسم بين 04 (`BodyInspectSheet`) والمصفوفة.
   - أضف عمود تسمية إنجليزية (افتراض #1).
7. أنشئ الهيكل الفاضي: `lib/ui/`, `lib/domain/actions/`, `lib/domain/corrections/` (ملف `.gitkeep` أو README صغير).

**الاختبارات:** لا جديد.
**معايير الإنجاز:** `_baseline.md` موجود بالأرقام الفعلية وإجابات الـ ◐ وقرار المستخدم في الـ 12 فاشل؛ 01 §2–§3 و§5.2 متحدّثين حسب الإجابات.

---

### P1 — الأساس المشترك · (L) · بالتوازي مع P2
**الهدف:** كل المكونات المشتركة في 01 جاهزة ومختبرة **بدون** تغيير أي شاشة موجودة.
**للقراءة:** `01_shared_components.md` كاملاً، `README.md` §5–6، `features/shared/{screen_layout,empty_state,person_picker,crop_image,image_preview}.dart`، `core/theme.dart`، `test/support/harness.dart`.
**خارج النطاق:** أي شاشة، أي router، الـ pickers اللي بتحتاج بيانات P5/P8 (MediaPicker، ModelPicker، DatasetPicker، TargetPicker، IdentityPicker، JobSubmitBar).

**المهام**
1. **`lib/domain/actions/`** (Dart صرف، قابل للاختبار بدون Flutter):
   - `entity_ref.dart`: `sealed class EntityRef` (media, face, body, sensitiveRegion, equipment, person, group, cluster(kind,id), album, result, job, model, dataset, action). أنواع الـ cluster: pose, outfit, groupPose, equipment, mark, action فقط.
   - `action_id.dart`: enum بكل صفوف 01 §2 (بما فيها `confirmLink, unlink, notThisPerson, belongsToNoOne, notARealThing, notSamePerson, changeKind, setSensitivity, addEquipment`).
   - `action_registry.dart`: `ActionSpec{id, group, icon, labelKey, isAvailable(ActionContext)}`، المجموعات بالترتيب: **عرض → تعريف → بحث → إنشاء → إدارة → خطر**، و`quickActionsFor(entity)` (QA) و`sheetFor(entity)`.
   - `ActionContext`: نوع الكيان، النوع (person/character)، media كيف (video؟)، حالة الربط (له شخص؟ ملوش صاحب؟)، توفر الـ PC، التحديد المتعدد.
   - **التنفيذ:** الـ Registry بيوصف الإجراء بس. `lib/ui/actions/action_dispatcher.dart` فيه handler واحد لكل `ActionId` (`(BuildContext, WidgetRef, EntityRef, ActionContext) → Future<void>`)، وكل مرحلة بتسجّل handlers شاشاتها. `EntityActionSheet` و`QuickActions` و`BulkActionBar` بيستدعوه، وممنوع `switch` على `ActionId` جوه شاشة. الإجراء اللي لسه مالوش handler ما يظهرش.
2. **`lib/ui/` — scaffolds:** `tab_root_scaffold.dart` (يفرض: عنوان + ≤ 1 إجراء + ⚙، ولا ⋮ — يرمي assert في debug لو اتخالف)، `detail_scaffold.dart`، `flow_scaffold.dart` (يلف `GuidedWorkflow` الحالي + حماية الخروج)، `sheet_scaffold.dart`، `settings_scaffold.dart` + `setting_group.dart` + `setting_tile.dart` (nav/switch/value/action/danger).
3. **ذرّات:** `thumb.dart`، `crop.dart` (يلف `CropImage` + `ImageExpand` الموجود، باسم `ExpandButton` في الـ spec، في ركن ثابت)، `avatar.dart` (يلف `PersonAvatar`)، `info_chip.dart`، `progress_bar.dart`.
4. **`entity_card.dart`:** صيغ `grid/row/hero`، حالات `normal/selected/disabled/busy`، `visual` ∈ Thumb|Crop|Avatar|CropStack(3)|Icon.
5. **القوائم:** `collection_controller.dart` (بحث، ترتيب، فلاتر، وضع عرض، حالة، تحديد؛ بياناته من `CollectionSource<T>` بيدعم التحميل بالصفحات، لأن المعرض بيقرا 120 عنصر في الصفحة)، `collection_view.dart`، `filter_bar.dart` + `filter_sheet.dart` + `FilterSpec`، `segmented_bar.dart`، `media_grid.dart`/`crop_grid.dart` (واجهة فقط + تنفيذ على قوائم عامة؛ ربط البيانات الحقيقية في P5a/P6a/P7).
6. **التحديد:** `selection_controller.dart`، `selection_top_bar.dart`، `bulk_action_bar.dart` (≤ 4 ظاهرة + "المزيد"، مبنية من الـ Registry على **تقاطع** الأنواع المحددة).
7. **الإجراءات:** `entity_action_sheet.dart` (من الـ Registry)، `quick_actions.dart`.
8. **Sheets:** `name_sheet.dart`، `confirm_sheet.dart` (عادي + خطر مع قائمة التبعات)، `undo_snackbar.dart`، `searchable_list_sheet.dart`، pickers: `person_picker.dart` (يلف الموجود في `features/shared/person_picker.dart` ويحافظ على نفس الـ API)، `face_picker.dart`، `group_picker.dart`.
9. **الحالات:** `empty_state.dart` بـ `kind` (first-run/no-results/no-permission/no-pc)، `error_state.dart`، `readiness_banner.dart` (من `serverStatusProvider`)، `progress_card.dart` (`ProgressCardData` موحدة: scan | job — بيانات فقط، الربط الفعلي في P3/P4).
10. **عارضات:** `compare_slider.dart` (صور) — الباقي (`DetectionOverlay`, `VideoPlayer`) يتحرك في P5b.
11. **تجربة على شاشة حقيقية (Pilot):** حوّل `features/storage/storage_screen.dart` (391 سطر، S5) لـ `SettingsScaffold` + `ConfirmSheet` بنفس السلوك واختباراته خضراء، عشان API الأساس يتجرب على استخدام فعلي. **وPilot تاني للقوائم:** شبكة `ResultsScreen` (في `results_screen.dart`) تتحول لـ `CollectionView` + `EntityCard(result)` بنفس السلوك وبنفس الـ Key `result-{id}`، مع كتابة اختبار characterization ليها الأول لأن مفيش اختبار بيشير لها بالاسم. أول استخدام كامل بالتحديد في P5a، وتعديل الـ API وقتها مسموح.

**الاختبارات (`test/ui/`, `test/domain/actions/`)**
- `action_registry_matrix_test.dart`: مصفوفة 01 §3 + التكميلية كبيانات في الاختبار، تقارنها بالـ Registry خلية خلية.
- `tab_root_scaffold_test.dart` (assert لو أكتر من إجراء أو ⋮)، `collection_view_test.dart` (الحالات الخمس)، `bulk_action_bar_test.dart` (≤ 4 + المزيد، تقاطع الأنواع)، `entity_card_test.dart`، `name_sheet_test.dart`، `confirm_sheet_test.dart`، `selection_controller_test.dart`، `action_dispatcher_test.dart`، `collection_source_test.dart` (تحميل صفحات)، text-scale 2.0 على كل مكون.

**معايير الإنجاز:** كل ما فوق موجود ومختبر؛ **لا ملف في `features/` اتغير** غير شاشتي الـ Pilot (وimports لو لزم)؛ `flutter analyze` صفر؛ عدد الاختبارات الكلي ≥ خط الأساس + الجديد.

---

### P2 — طبقة التصحيحات (schema v19) · (L) · بالتوازي مع P1
**الهدف:** كل أفعال التصحيح (01 §5) تشتغل على مستوى البيانات والمنطق، مع ضمان إن التجميع/إعادة الفحص ما يلغيهاش. **بدون UI.**
**للقراءة:** `01_shared_components.md` §5، `07_migration_map.md` §6، `lib/data/db/{tables,app_database}.dart`، `lib/data/repositories/{people_repository,review_repository,kind_corrections,face_suppression_store,sensitive_store}.dart`، `lib/domain/grouping/*`، `lib/domain/scan/{photo_result_store,redetect,video_compactor,video_tracks}.dart`، `lib/domain/pose/exposed_matching.dart` (للحارس بس)، `lib/domain/marks/body_marks.dart`، `lib/domain/backup/backup_service.dart`، `test/data/schema_v16_test.dart`، `test/domain/{backup_v16_test,face_corrections_test}.dart`، `test/data/kind_corrections_test.dart`.
**قرار محسوم:** "ملوش صاحب" = العنصر **يفضل ظاهر** بشارة "بدون مالك"، ويُستبعد من الربط التلقائي والاقتراحات والتدريب فقط. "مش حقيقي" هو الوحيد اللي يتخفى.

**المهام**
1. **Schema v19** (`currentSchemaVersion = 19`، migration من 18 بدون فقد بيانات):
   - `body_overrides(id, asset_id, x, y, w, h, timestamp_ms, ownership, hidden, scope)`: **مصدر الحقيقة** لـ"ملوش صاحب" و"مش جسم أصلاً"، بنفس مفتاح `kind_overrides` (asset + box + وقت)، عشان يعيش بعد مسح صف الجسم أو إعادة استيراد الوسيط. مطابقة الصندوق بـ `sameDetectionBox`. `scope` ∈ `single | track`. في الفيديو يتكتب سطر لكل ظهور في `media_detections` مش للصف بس (زي `FaceSuppressionStore.remember`).
   - `bodies`: `ownership TEXT NULL` (`'none'` أو NULL) + `hidden BOOL DEFAULT false`: **cache للاستعلام فقط**، يتعاد تطبيقه من `body_overrides` بعد أي كتابة أجسام.
   - `body_distinct(body_a, body_b)` PK على الزوج المرتب (FK cascade). الـ cascade بيمسحه مع الصف، فـ redetect وcompactor لازم ينقلوه للصف الجديد قبل المسح.
   - `faces`: `ownership TEXT NULL` (`'none'` أو NULL). **`review_dismissed` مش معناه "ملوش صاحب"**: `deletePerson` وتجاهل المراجعة بيكتبوه كمان. الـ migration يسيب `ownership` فاضي لكل الصفوف القديمة، فمفيش وجه قديم ياخد الشارة لوحده.
   - `face_overrides(id, asset_id, x, y, w, h, timestamp_ms, ownership, scope)`: نفس دور `body_overrides` لـ"ملوش صاحب" على الوجوه. (`face_suppressions` بيغطي قرارات الحذف بس.)
   - (أي تعديل تاني يظهر من نتيجة P0 §5 يتسجّل هنا قبل التنفيذ).
2. `dart run build_runner build` + تحديث `app_database.g.dart`.
3. **`lib/domain/corrections/`:**
   - `correction_target.dart`: sealed — `FaceLink, BodyLink, BodyPair, EquipmentOwner, SensitiveRegion, PoseMembership, PersonPair, ActionSuggestion`.
   - `correction_verb.dart`: `reassign, notThisPerson, belongsToNoOne, notARealThing, notSamePerson, unlink, confirm`.
   - `correction_scope.dart`: `single | track | cluster | wholeVideo` (+ تسامح `videoCorrectionToleranceMs` للقطة، حسب جواب P0). **`track` تنفيذ جديد للوجوه والأجسام:** `expandTracks` الحالي للوجوه بس وبيرجّع `person_id IS NULL` بس، فمينفعش لتصحيح ربط غلط. النطاق = صفوف نفس `track_id` في نفس الوسيط اللي رابطها الحالي هو نفس الرابط اللي بيتصحح (نفس `person_id`).
   - `correction_service.dart`: `allowedVerbs(target)` (يطابق جدول 01 §5.2 بالظبط)، `preview(correction) → CorrectionPreview{items, mediaCount}`، `apply(correction) → CorrectionResult{undoToken}`، `undo(token)`.
   - لكل خلية ● في الجدول: **استدعاء الدالة الموجودة** (لا إعادة كتابة): `assignFaces`, `rejectFaces`, `dismissFaces`, `clearAssignments`, `linkBody`, `rejectBody`, `acceptBodyLink`/`rejectBodyLink`, `markDistinct`, `kind_corrections`, حالات equipment/pose-membership/sensitive.
   - **"ملوش صاحب" لوجه:** `dismissFaces` لوحدها مش بتفك `person_id`، فالفعل = `clearAssignments` + `dismissFaces` + `ownership='none'` + سطر `face_overrides` في transaction واحدة (بالترتيب ده، لأن `clearAssignments` بيصفّر `review_dismissed`). `reassign` يشيل `ownership` وسطر الـ override.
   - لكل 🆕: تنفيذ جديد فوق الجداول، ومنها `unlinkBody` بدون كتابة في `body_rejections`.
   - **Undo:** الدوال الموجودة بترجّع `Future<void>` (و`dismissFaces` بتمسح `review_matches`)، فالـ service ياخد snapshot للصفوف المتأثرة قبل التطبيق في نفس الـ transaction، و`undo` يرجّعها. الـ token في الذاكرة بس. لو صف اتغير بعد التطبيق (مثلاً `GroupingRunner` اشتغل)، `undo` يقول إنه تعذر بدل ما يكتب فوق التغيير.
4. **احترام التصحيحات في كل المنطق التلقائي** (هنا أخطر جزء):
   - **التجميع:** `person_linking` كود Python على الـ PC والـ contract مجمّد (قاعدة 3)، فكل الفرض على الهاتف: `grouping_inputs.bodies()` ما يبعتش أجسام `ownership='none'`/`hidden`، و`plan_applier.applyBodyPlan` يتحقق منهم في الـ SQL، ويرفض أي ربط يخلي جسمين من `body_distinct` عند نفس الشخص.
   - **كل مسار يكتب `bodies.person_id` أو `review_body_links`:** يتخطى `none`/`hidden` (ومنها `exposed_matching`، حارس بس). أي اقتراح قائم للجسم في `review_body_links` يتمسح وقت التصحيح.
   - **`BodyLinkGuard` واحد في `lib/domain/corrections/`** بيحكم `none`/`hidden` و`body_distinct`:
     - **التلقائي** (`plan_applier`، `video_compactor`، `body_marks.publishSuggestions`، `kind_corrections` وهو بينفّذ `targetPersonId`، وأي مسار تاني): ما يكتبش لو فيه تعارض.
     - **اليدوي** (`linkBody`، `reassign`): قرار المستخدم أقوى، فالـ Sheet تنبّه، والتطبيق يمسح زوج `body_distinct` المتعارض.
     - **الدمج** (`people_repository.dart:639` بينقل كل أجسام الشخص): الجسم المتعارض من الشخص المدموج يفضل بدون شخص، والعدد يظهر في معاينة P5 من `distinctConflicts(a, b)`.
   - **`redetect.dart`:** بيرجّع للأجسام `person_id` بس. أضف استرجاع `body_rejections` (ثغرة موجودة النهارده، موجودة للوجوه بس) و`body_distinct`، وأعد تطبيق `body_overrides`. وللوجوه: انقل `ownership` مع `hidden`/`review_dismissed`.
   - **`video_compactor.dart`:** بينقل `body_rejections` للصف الباقي. أضف `body_distinct`، والصفوف اللي تختلف في `ownership`/`hidden` ما تتدمجش (ضيفهم في مقارنة الدمج زي `flags` بتاع الوجوه، و`ownership` في `flags` الوجوه نفسها).
   - **`photo_result_store.dart`:** إعادة الفحص بتطابق بـ IoU وبتعمل insert لو ملقتش. الصف الجديد يتطبق عليه `body_overrides` (وللوجوه `face_overrides`) في نفس الـ transaction. **في الفيديو:** لو صف في الـ track طابق override نطاقه `track`، باقي صفوف الـ track تورثه، حتى لو إعادة الفحص جابت إطارات برّه ±500ms من الأصل.
   - **backfills** (`embedding/sensitive/garment/outline`): ما تمسحش التصحيحات، وما تشتغلش على `hidden`.
   - **`hidden` في كل قراءة:** 39 ملف بيقرأ `bodies` (منهم 10 في `features/`). راجعهم كلهم بقائمة في التقرير، واستخدم مساعد استعلام مركزي للأجسام الظاهرة. "ملوش صاحب" يفضل ظاهر، و`hidden` بس هو اللي يتخفى، والاستثناء الوحيد طابور `excluded`.
   - **`domain/export` + بناء الـ datasets:** استبعاد "ملوش صاحب"/"hidden" من التدريب.
5. **استعلامات للـ UI** (`corrections_queries.dart`): `excluded()` (وجوه `ownership='none'`، وجوه متجاهَلة: `review_dismissed` من غير `ownership`، أجسام none/hidden، رفض مع اسم الشخص، أدوات rejected…) مع عدّاد؛ `noOwner(kind)` (للفلتر في Explore)؛ `linksForMedia(mediaId)` (يبني `LinkRow`s: جسم←شخص + المصدر `linkMethod`، جسم≈جسم بنفس الـ track/الطقم، أداة←مالك).
6. **النسخ الاحتياطي:** الجداول الجديدة في `backupTables` (قائمة صريحة، والترتيب مهم للـ FK: بعد `bodies`)، والاستعادة، ورفض نسخة بـ schema أعلى كما هو الحال. نسخة v18 لازم تترجع على v19 (الأعمدة الناقصة تاخد default).

**الاختبارات**
- `test/data/schema_v19_test.dart`: migration 18→19 يحفظ كل البيانات (استخدم fixture قاعدة v18 زي `schema_v16_test`).
- `test/domain/correction_service_test.dart`: لكل (نوع رابط × فعل) من 01 §5.2: مسموح/ممنوع صح + الأثر على الـ DB + `preview` يعد صح + `undo` يرجّع الحالة بالكامل + نطاقات الفيديو (track / ±500ms).
- **اختبارات "ما يرجعش":** بعد `belongsToNoOne`/`notThisPerson`/`notSamePerson`/`notARealThing` → شغّل `GroupingRunner` + إعادة اكتشاف + إعادة فحص + compactor + backfill ← الربط **ما يرجعش** والتصحيح يفضل على الصف الجديد. ومنهم اختبار لـ `rejectBody` بعد redetect (بيفشل النهارده)، واختبار فيديو: تصحيح بنطاق `track` يفضل بعد إعادة فحص بإطارات في توقيتات مختلفة.
- `test/domain/body_writers_guard_test.dart`: يدوّر في `lib/` على كتابات `bodies.person_id` و`review_body_links`، ويفشل لو ظهر مسار جديد مش معدّي على `BodyLinkGuard` ومش في قائمة استثناء بسبب مكتوب.
- **`body_distinct`:** الدمج بيسيب الجسم المتعارض بدون شخص، و`distinctConflicts` بيعدّ صح، و`linkBody` اليدوي بيمسح الزوج، والمسارات التلقائية ما بتكتبش.
- **`faces.ownership`:** `deletePerson` وتجاهل المراجعة ما بيدّوش شارة "بدون مالك"، وmigration 18→19 ما بيحوّلش `review_dismissed` القديم.
- **Undo:** يرجّع الحالة بالكامل، بما فيها `review_matches`، ويرفض لو الصف اتغير بعد التطبيق.
- `test/domain/backup_v19_test.dart`: ذهاب وإياب كامل + استعادة نسخة v18.
- `hidden`: جسم مخفي ما يظهرش في العدادات والشبكات والمطابقة والتدريب، و"ملوش صاحب" يظهر.
- استعلامات `excluded/noOwner/linksForMedia`.

**معايير الإنجاز:** كل خلية في 01 §5.2 ● أو 🆕-منفّذة؛ لا تغيير في أي شاشة غير شرط `hidden` في استعلاماتها؛ كل اختبارات الـ grouping والـ backup القديمة خضراء؛ الـ handoff متحدّث بإصدار schema الجديد.

---

### P3 — الـ Shell والتنقل · (M)
**الهدف:** الهيكل الجديد (4 تبويبات + ActivityPill + كل الـ routes النهائية) شغّال، والشاشات القديمة لسه هي اللي بتتعرض.
**للقراءة:** `README.md` §3–6، `core/router.dart`، `app.dart`، `features/shell/app_shell.dart`، `lib/library_providers.dart` (`scanProgressProvider`)، `lib/studio_providers.dart` (`jobsProvider`, `jobTrackerProvider`)، `features/scan/scan_progress_card.dart`، `features/jobs/jobs_screen.dart`.

**المهام**
1. **`core/router.dart`:** عرّف الـ routes النهائية (README §4) كلها. لكل route جديد `builder` يشير مؤقتاً إلى **الشاشة القديمة المقابلة** (جدول 07 §1) أو `PlaceholderScreen`، بحيث المراحل بعدها تبدّل الـ builder فقط. **في P3 تتفعّل بس الـ redirects اللي عمودها في 07 §3 هو P3**: مسار قديم واحد ← مسار جديد واحد بيعرض نفس الشاشة القديمة، **بترجمة الباراميترات**. أي redirect بيجمع كذا شاشة في مسار واحد أو محتاج سلوك مش موجود في الشاشة القديمة (زي `/sources` و`/analyze` و`/insights`، أو `/results` ← `/studio?tab=`، أو `/people/unsorted`) يفضل مساره القديم شغال لحد المرحلة اللي بتبني بديله.
   - **المسارات اللي هتدخل الـ shell:** مواضع `context.push` القديمة عليها تتحول `go`/`goBranch` في المرحلة اللي بتفعّل الـ redirect، وشاشة الجذر لازم تقرا الـ query كل مرة تدخلها، مش في أول build بس، لأن الـ branch محفوظ في `IndexedStack`. الحفاظ على: روابط `agmobile://`، `leave()`، وتنقل ما بعد الـ pairing.
   - **`/pair`:** الـ redirect الحالي بيفحص `location.startsWith('/pair/')`، وده مش هيطابق `/pair` الجديد، فالمستخدم مش هيروح permissions بعد الربط. عدّل الشرط وغطّيه باختبار. (`Routes.isOnboarding` مش مستخدم في الـ redirect أصلاً؛ حدّثه أو احذفه.)
   - **ترتيب الـ routes الثابتة قبل المتغيرة:** `/people/unsorted` قبل `/people/:id` (بيعمل `int.parse`)، `/explore/actions/:id` قبل `/explore/:kind/:id`، `/studio/datasets/new` قبل `/studio/datasets/:id`.
   - **`/restyle`** يفضل زي ما هو (خارج النطاق).
2. **`domain/targets/target_ref.dart`:** `TargetRef` (media + detection اختياري) مع parse/serialize لـ `target=media:ID[,det:ID]` + `person` + `identity` + دعم الباراميترات القديمة (`media`, `target`, `face`, `person`, `identity`) كقراءة فقط. بتُستخدم في P5/P8.
3. **`features/shell/app_shell.dart`:** 4 وجهات (Library, People, **Explore**, Studio).
4. **`ui/activity_pill.dart` + `activity_state_provider`:** يدمج `scanProgressProvider` + `jobsProvider` (+ فشل لم يُشاهد) في حالة واحدة: `idle | scanning(n/m) | job(type,%) | multiple(+k) | failed`. الضغط → `/activity`. يظهر بس لما فيه نشاط.
   - **مكانه:** الـ shell بيحتوي 4 جذور بس، و`/people/:id` و`/media/:id` وباقي الشاشات براه، والـ routes التفصيلية تفضل top-level من غير نقلها لـ branches. نفس الـ widget بيتعرض في مكانين، ومفيش `Stack` فوق الـ Navigator، لأنه كان هيغطي الـ modal sheets والـ Snackbar و`StickyActionBar`:
     - **الجذور:** جوه `AppShell` فوق الـ `NavigationBar` مباشرة.
     - **باقي الشاشات:** `ActivityPillHost` جوه `AppLockGate` في `MaterialApp.router(builder:)` (`AppLockGate(child: ActivityPillHost(child: child))`، عشان ما يظهرش على شاشة القفل)، بيعمل `Column[Expanded(child), Pill]` فيحجز مساحته، ويشيل الـ padding السفلي من الـ child ويحطه تحت الـ Pill.
     - **الـ Host فوق الـ Router:** مفيش `GoRouter.of(context)` هناك، فبياخد الـ `GoRouter` كـ parameter وبيسمع `routerDelegate` عشان يعرف المسار وينقل لـ `/activity`.
     - **مخفي في:** onboarding والـ Viewer والـ Flows و`/activity`، ولما الكيبورد مفتوح. والضغط يتقفل طول ما فيه `PopupRoute` مفتوح (`NavigatorObserver`).
5. فرض قاعدة "⚙ في كل جذر تبويب": `TabRootScaffold` يتطبق في P4–P8 على كل جذر؛ هنا بس نوصّل الـ gear route.

**الاختبارات:** `test/core/router_test.dart` (كل redirect مفعّل في P3 صح مع الباراميترات؛ كل مسار قديم لسه ما اتفعّلش بيفتح شاشته القديمة؛ بعد الربط من `/pair` يروح permissions؛ رابط `agmobile://`)، `test/features/shell_test.dart` (4 وجهات؛ الـ Pill في كل حالاته، ظاهر في شاشة تفصيلية ومخفي في الـ Viewer وعلى شاشة القفل؛ ما بيغطيش modal sheet أو Snackbar أو `StickyActionBar`؛ الضغط يروح `/activity`)، `target_ref_test.dart`، تحديث `widget_test.dart` وأي اختبار بيستخدم `Routes.home/jobs/results/lora/...`.
**معايير الإنجاز:** التطبيق يفتح على 4 تبويبات؛ كل deep link قديم بيوصل لنفس الشاشة القديمة بنفس البيانات؛ ولا شاشة اتغيرت ولا بقت غير متاحة.

---

### P4 — النشاط + الإعدادات + البداية · (M)
**الهدف:** A1/A2 و S1–S7 و O1–O3. الفحص يتحكم فيه من مكان واحد.
**للقراءة:** `05_studio_and_activity.md` (A1/A2)، `06_settings_onboarding.md` كاملاً، الملفات: `features/jobs/jobs_screen.dart`، `features/scan/{scan_progress_card,sources_screen,video_scan_details,redetect_flow}.dart`، `features/analyze/*`، `features/insights/insights_screen.dart`، `features/settings/*`، `features/storage/storage_screen.dart`، `features/backup/*`، `features/privacy/app_lock.dart`، `features/onboarding/*`، `features/home/home_screen.dart`.
**خارج النطاق:** حذف الشاشات القديمة (P9).

**المهام**
1. **A1** `features/activity/activity_screen.dart` (الآن ‖ السجل): `ProgressCard(scan)` (المراحل الأربع، إيقاف/استئناف، "الملفات اللي تعذر فحصها" → `FailedItemsSheet`) + قائمة `ProgressCard(job)` بإجراءات من الـ Registry (`cancel/retry/open`). استخرج منطق `ScanProgressCard`/`RunningScanScreen` إلى مصدر بيانات `ProgressCardData`. A1 هو مكان عرض البطاقة الوحيد؛ الـ Pill شريط بس، وضغطه يروح `/activity`.
2. **A2** تفاصيل المهمة (نقل `JobDetailScreen`): بيانات، سجل SSE، مخرجات، `retry/cancel/runAgain`.
3. **S1** `settings_screen.dart` → `SettingsScaffold` بالمجموعات في 06. **S2** (من `connection_screen.dart` + `resource_panel.dart`). **S3** (دمج `sources_screen` + `analyze_screen/controller` + `insights_screen` + إحصائيات Home: نظرة عامة، المصادر، أفعال الفحص، "حلّل ملف..."). **S4** (نفس السلوك الحالي: مفتاح قفل التطبيق بمصادقة النظام؛ `AppLockGate` يفضل غلاف. المهلة وPIN وحماية لقطات الشاشة مش موجودين النهارده، فمش جزء من P4: افتراض #9). **S5** storage. **S6** backup (+ تذكير آخر نسخة > 14 يوم بدل بانر Home). **S7** background.
4. **O1/O2/O3:** Welcome، `/pair` واحدة بـ `SegmentedBar` (QR ‖ يدوي) بنفس `PairingController`، Permissions. روابط `agmobile://pair` تروح O2 بالبيانات مملوءة.
5. استبدال `Navigator.push` اللي في الملفات دي بـ routes/Sheets. تطبيق `NameSheet/ConfirmSheet` مكان الـ dialogs (`password_dialog` يتحول لـ `PasswordSheet`).
6. تحويل `builder`s الجديدة في `router.dart` للشاشات الجديدة، وتفعيل redirects صفوف P4 في 07 §3 (ومنها `/sources` و`/analyze` و`/insights` و`/running-scan` و`/pair/*`).

**الاختبارات (انقل/حدّث):** `scan_and_settings_test`, `running_scan_test`, `resources_test`, `connection_screen_test`, `background_test`, `backup_password_test`, `onboarding_test`, `analyze_test`, `video_scan_details_test`, `home_test` (يتحول لاختبار ما بقاش في Home وإن محتواه اتوزع)، + جديد: `activity_screen_test` (إيقاف/استئناف/إعادة/إلغاء، تصفية السجل)، `settings_hub_test`.
**معايير الإنجاز:** الفحص يُتحكم فيه من `/activity` فقط؛ لا أيقونة Activity في أي AppBar جديد؛ كل S* شغّال بـ SettingsScaffold. (بدء الفحص من `ScanInviteStrip` معيار P5a، ولحد وقتها المدخل القديم يفضل شغال.)

---

### P5a — المعرض والألبوم · (M)
**الهدف:** L1, L2 + `MediaPicker`.
**للقراءة:** `02_library_and_viewer.md` (L1–L2)، `features/library/{library_screen,native_gallery,media_grid}.dart`، `test/features/{library_test,native_gallery_instant_test,gallery_first_test,gallery_first_preview_test}.dart`.
**المهام**
1. `library_screen.dart` → `TabRootScaffold` (عنوان، فلتر، ⚙) + `SegmentedBar` (الصور ‖ الألبومات) + `FilterBar`/`FilterSheet` (نوع، حالة فحص، تاريخ، شخص) + `ScanInviteStrip`.
2. حافظ حرفياً على: **0ms reload** (cache Riverpod)، تجميع بالتاريخ، **كثافة 3/4/5 بالقرص**، الاختيار المتعدد.
3. Albums: `EntityGrid` من `EntityCard(album)`؛ L2 (من `FolderScreen`) مع ⋮ (تضمين/استبعاد من الفحص، مراجعة الألبوم → `/review?queue=suggestions&album=`، تحليل الألبوم).
4. `BulkActionBar`: مشاركة · تحليل الآن · إضافة لمجموعة تدريب (تظهر فقط لو الدالة موجودة؛ وإلا تتأجل لـ P8b) · المزيد.
5. `ui/pickers/media_picker.dart` (single/multi، صور ‖ ألبومات) — يُستخدم في P8a وP8b.
6. حالات: no-permission / limited / first-run.
**الاختبارات:** المذكورة فوق منقولة + `media_picker_test`، `scan_invite_strip_test`.
**الإنجاز:** نفس سلوك المعرض الحالي من منظور المستخدم + الشكل الجديد؛ الفحص يُبدأ من `ScanInviteStrip` ومدخل الفحص القديم في الـ AppBar اتشال.

---

### P5b — عارض الوسائط · (L)
**الهدف:** L3 على هيكل جديد (طبقات، شريط سفلي، سياق) بدون المفتش (P5c).
**للقراءة:** `02_library_and_viewer.md` (L3, L4)، `features/media/{media_screen,video_media_view}.dart`، `features/shared/{image_preview,media_target}.dart`، `features/bodies/body_inspection_sheet.dart`، `data/platform/native_video_player.dart` (لا يتغير)، اختبارات: `viewer_gestures_test, media_screen_native_player_test, video_media_view_test, media_target_test, image_preview_test, outline_overlay_test, body_overlay_painter_test, review_viewer_test`.
**المهام**
1. فكّ `media_screen.dart` (1614 سطر) إلى: `media_viewer_screen.dart`، `media_chrome.dart`، `layers_popover.dart`، `detection_overlay.dart` (استخراج الرسّامات الحالية)، `media_page_item.dart`. `video_media_view.dart` يفضل.
2. **حافظ على:** تشغيل zero-copy بـ `contentUri`، التشغيل التلقائي عند الوصول، الصامت افتراضياً، التمرير الأفقي، الإيماءات (نقرة/نقرتين/سحب)، `MediaCollectionContext`، فتح المشغل الخارجي. (`MediaCollectionContext` يفضل `{ids, loadMore}` عبر `state.extra` ويتضاف له `source` بس؛ الفتح من deep link يفضل بباراميترات `/media/:id` الحالية.)
3. زر **طبقات** (وجوه · أجسام · هيكل · أدوات؛ الافتراضي وجوه + أجسام). الطبقة غير المتاحة تظهر معطّلة بسبب.
4. الشريط السفلي: **مشاركة · استوديو · (تكبير/Lens أو مشغل خارجي)** + **مكان محجوز** لشريط الـ Peek (يتركب في P5c). زر "تفاصيل" يتشال بعد P5c؛ مؤقتاً يفتح الشيت الحالي.
5. استبدال `_boxMenu` بـ `EntityActionSheet` من الـ Registry (وجه/جسم) — **كل الإجراءات الحالية موجودة** (assign, reject, kind, group-pose, equipment, similar-pose/colours, name-pose/outfit, mark-tattoo, delete, reface/restyle-target مع قيد إطار الفيديو؛ `restyle-target` بنفس باراميترات `/restyle` الحالية). وكمان قائمة الـ AppBar وشيت التفاصيل: `redetect`، نوع الملف كله (`_fileKindMenu`).
6. محدد العنصر عند التداخل (وجه داخل جسم).
7. `ImagePreview` (L4): تبديل مقصوص/الأصل + Lens فقط.
8. تحويل `Navigator.push` (equipment screen وغيره) إلى routes، وتمرير `TargetRef` للاستوديو.
**الاختبارات:** كل المذكورة خضراء بعد النقل + `layers_popover_test` + `entity_action_sheet_from_viewer_test` (كل الإجراءات القديمة ظاهرة تحت نفس الشروط).
**الإنجاز:** لا فقد لأي إيماءة/إجراء موجود؛ ملف الشاشة ≤ ~600 سطر.

---

### P5c — المفتش وشاشة التصحيح · (L)
**الهدف:** `MediaInspector` + `CorrectionSheet` — "كل الأدوات في مكان واحد" و"صحّح أي ربط".
**للقراءة:** `02_library_and_viewer.md` §L3a، `01_shared_components.md` §5، مخرجات P2 (`correction_service`, `corrections_queries`)، `features/bodies/{body_inspection_sheet,body_naming}.dart`، `features/marks/mark_tattoo.dart`، `features/scan/redetect_flow.dart`، `domain/scan/video_tracks.dart`.
**المهام**
1. `features/inspector/media_inspector.dart`: `DraggableScrollableSheet` بثلاث نقاط (Peek/Half/Full) — نفس اللوحة للصورة والفيديو. **Peek:** chips لكل عنصر (Avatar/Crop/أيقونة) بحدود ملونة حسب حالة الربط (ثابت/تلقائي/غير معيّن/بدون مالك) + شارة "N روابط تلقائية".
2. الأقسام: **اللي في الصورة** (`DetectionRow`s مجمّعة: لكل شخص / غير معيّن / ملوش صاحب) · **الروابط** (`LinkRow`s من `linksForMedia`) · **الأنشطة والوشوم** · **إنشاء** (على العنصر المحدد أو الوسيط كله) · **معلومات** (+ analyzeNow + "أعد اكتشاف لهذا الوسيط" عبر `redetect_flow`).
3. **`correction_sheet.dart`:** الأفعال المسموحة من `allowedVerbs(target)` فقط، `ScopePicker`، معاينة الأثر (`preview`) إجبارية لو > عنصر، `apply`، `UndoSnackbar` (≥ 8 ثواني)، `undo`.
4. **الفيديو:** `video_track_strip.dart` فوق الـ scrubber (الظهورات بالأسماء؛ نقر = قفز + تحديد)، المربعات متزامنة مع الوقت، `ScopePicker` (اللقطة / الظهور كله افتراضي / الفيديو كله)، Restyle معطّل لإطار فيديو مع السبب.
5. نقل `BodyInspectSheet` إلى `features/inspector/body_inspect_sheet.dart` (مع re-export من المسار القديم)، وتحويل قوائمه لـ Registry، والتسمية (`nameBodyPose/Outfit/GroupPose`) إلى `NameSheet`. زر `toggle-area-btn` وإجراءات `exposed-*` ما يدخلوش الـ Registry وما يتطوروش (خارج النطاق). **`MarkEditor` يتبني هنا** من `_MarkDialog` في `mark_tattoo.dart` كـ Sheet، وP6b بيستخدمه.
6. شارات "بدون مالك" على Peek/الصفوف وفي أي شبكة وسائط ملف فيها عنصر كده (اختياري خفيف).
7. **(آخر المرحلة، قابلة للإسقاط)** "حدد منطقة" يدوياً بالضغط المطول: رسم مستطيل ← وشم / أداة.
8. إزالة زر "تفاصيل" القديم وربط الشريط السفلي بالمفتش.
**الاختبارات (`test/features/inspector/`):** لكل نوع رابط الـ Sheet تعرض بالظبط أفعال 01 §5.2؛ تطبيق كل فعل يغيّر الـ DB صح؛ Undo؛ نطاقات الفيديو؛ Peek chips بحالاتها؛ إعادة تجميع بعد التصحيح ما تلغيهوش (تكامل مع P2)؛ + نقل `body_inspection_sheet_test`.
**الإنجاز:** من أي صورة/فيديو: أي عنصر/رابط يوصله `CorrectionSheet` في ≤ 2 نقرة، والنتيجة نفسها لو جيت من Person/Explore/Review.

---

### P6a — الأشخاص والشخص والمجموعات · (L)
**الهدف:** شاشات P1–P3 في 03. تعتمد على `CorrectionSheet` من P5c.
**للقراءة:** `03_people_and_review.md` (P1–P3)، `features/people/*`، `data/repositories/{people_repository,identity_groups}.dart`، اختبارات: `people_test, people_actions_test, people_simplified_ux_test, characters_test, identity_groups_ux_test, identity_set_editor_test`.
**المهام**
1. **P1** `people_screen.dart` → `TabRootScaffold` + `SegmentedBar` (أشخاص ‖ شخصيات ‖ مجموعات) + `ReviewInboxBanner` + `EntityGrid` + FAB "+" + تحديد (دمج، نقل لمجموعة، تنظيم، حذف). شيل الـ ⋮ القديم.
2. **P2** `person_detail_screen.dart` (1089) → `DetailScaffold` + `DetailHeader` (Avatar، اسم بـ `NameSheet`، شارات، QuickActions: Reface · درّب موديل · وسائطه، ⋮) + 4 تبويبات (الوسائط · الوجوه · الأجسام · الاستوديو).
   - **تبويب الأجسام:** مؤقتاً يحمّل `BodiesScreen(personId)` الحالي؛ يتبدّل بـ `ExploreCollectionView(person:)` في P7.
   - تبويب الوجوه: `CropGrid` + `CorrectionSheet` + chip "المرفوضة" للتراجع.
3. **P3** مجموعات: `identity_groups_screen.dart` → قسم داخل P1 + شاشة `/groups/:id` (أعضاء ‖ وسائط).
4. إزالة كل `Navigator.push` وكل dialogs التسمية/التأكيد في الملفات دي.

**الاختبارات:** المذكورة منقولة + `people_segments_test`، `person_tabs_test`.
**الإنجاز:** ولا ⋮ في جذر الأشخاص؛ كل قدرات الشخص القديمة موجودة في التبويبات الأربعة.

---

### P6b — المراجعة والدمج والتنظيم والوشوم · (L)
**الهدف:** شاشات P4–P6 في 03 + الوشوم.
**للقراءة:** `03_people_and_review.md` (P4–P6 والوشوم)، `features/review/*`، `features/people/{unsorted_screen,people_actions,organize_media_screen}.dart`، `features/merge/merge_screen.dart`، `features/marks/*`، `data/repositories/review_repository.dart`، اختبارات: `review_test, quick_review_test, review_viewer_test, marks_ui_test`.
**المهام**
1. **P4 مركز المراجعة** `features/review_hub/` يدمج `review_screen`, `quick_review_screen`, `album_review_screen`, `unsorted_screen`, `SimilarFacesScreen` (في `people_actions.dart`), `review_media_viewer`: الطوابير `unsorted · suggestions · duplicates · bodyLinks · similar · excluded`. `suggestions` = `SwipeDeck` (يمين/يسار/أعلى **+ أزرار ظاهرة** للإتاحة) + درج "قارن". `excluded` من `corrections_queries.excluded()` مع التراجع.
2. **P5** Merge (T4، ومعاينته تعرض عدد `distinctConflicts`)، **P6** Organize Files (`/people/:id/files` و`/groups/:id/files`) بنفس الـ Journal الحالي.
3. `person_marks_screen` → تبويب وشوم/استكشاف + `MarkEditor` الجاهز من P5c. `TrainingExportDialog` يتحول لإجراء `exportDataset` (يتوصل في P8b) — مؤقتاً يفضل شغّال.
4. إزالة كل `Navigator.push` وكل dialogs التسمية/التأكيد في الملفات دي.
**الاختبارات:** المذكورة منقولة + `review_hub_test` (كل طابور + Undo + سحب وأزرار).
**الإنجاز:** كل طوابير المراجعة من `/review` فقط؛ الدمج ذري كما هو.

---

### P7 — الاستكشاف · (L)
**الهدف:** E1–E5 + `ExploreCollectionView` (يُستخدم داخل Person▸الأجسام).
**للقراءة:** `04_explore.md` كاملاً، `features/bodies/*` (bodies_screen 931، equipment_screens، group_pose_screens، pose_visuals، body_naming)، `features/video_actions/video_actions_screen.dart` (818)، `features/marks/*`، `domain/pose/*` (**منطق المطابقة لا يتغير**)، اختبارات: `bodies_screen_test, body_universal_naming_test, group_pose_ux_test, actions_screen_test, marks_ui_test`.
**خارج النطاق:** `kind=areas` و`body_areas.dart` و`body_areas_test` (افتراض #7)؛ §1 أقوى من 04 في ده.
**المهام**
1. **E1** `features/explore/explore_screen.dart` (3 أقسام: الأجسام · الأشياء · الحركة) بدل `discover_screen.dart`، العدّادات و3 Crops لكل بطاقة.
2. **E2** `explore_collection_screen.dart` + **`ExploreCollectionView`** عام بـ واجهة `CollectionKind` وتنفيذات: `all, poses, outfits, groupPoses, equipment, marks, actions` (`features/explore/kinds/`) — كل واحد يستخدم نفس منطق/Providers الحاليين (لا تغيير في `domain/pose`).
3. فلاتر كل نوع (جدول 04)، chip **"بدون مالك"** (من `noOwner(kind)`)، chip "مشابه لـ…"، كتالوج الشكل البصري (Posture/Arms/Orientation) كـ chips لنوع `poses`.
4. **E3** cluster: تسمية، "ينتمي إلى"، `MediaGrid`/`CropGrid`، تحديد (remove/نقل/dataset) + **صحّح الربط** عبر `CorrectionSheet` مع معاينة الأثر.
5. **E4/E5** تفاصيل النشاط ومحرر المثال (تفكيك `video_actions_screen.dart`) — قبول/رفض الاقتراحات، قص 3ث–دقيقتين، المشاركين.
6. `BodyInspectSheet` جاهز من P5c؛ كل التسمية عبر `NameSheet`؛ إزالة `Navigator.push` وتحويل `EquipmentPhotoScreen`/`GroupPoseResultsScreen` لـ routes.
7. مدخل Person▸الأجسام يتبدّل بـ `ExploreCollectionView(person:)` (تعديل صغير في ملف P6a).
**الاختبارات:** المذكورة منقولة + `explore_kinds_test` (كل نوع: فلاتر، حالات، فتح cluster، تسمية)، `no_owner_filter_test`، `pose_matching` القديمة بدون تغيير.
**الإنجاز:** نفس نتائج المطابقة الحالية (قواعد الاتجاه/الانحناء/العتبة)، ونفس القدرات: تسمية وضعيات/أطقم/جماعي/أدوات/وشوم، أنشطة.

---

### P8a — الاستوديو وReface · (L)
**الهدف:** ST1 وST2 + مكونات الـ Flow. **Restyle (ST3) خارج النطاق:** `restyle_screen.dart` ما يتعدلش، ومدخله في ST1 يفضل فاتح `/restyle` زي ما هو.
**للقراءة:** `05_studio_and_activity.md` (ST1, ST2)، `features/studio/*`، `features/reface/*` (reface_screen 1485 + helpers)، `data/repositories/{studio_repository,identity_repository}.dart`، الـ handoff (فقرات Reface الموحّد 2026-10-30)، اختبارات: `studio_test, contextual_studio_test, reface_*_test (all_faces, direct_identity, options, reference, trimmer), redesign_screens_test, redesign_ux_test`.
**المهام**
1. **مكونات الـ Flow (`lib/ui/flow/`):** `target_picker.dart` (من `reface_media`, `reface_faces`, `reface_video_trimmer`: وسيط + اختيار وجه/جسم + قص)، `identity_picker.dart` (من `reface_face_choices` + أطقم الهوية)، `job_submit_bar.dart` (جاهزية → إرسال → Snackbar "عرض النشاط"، لا ينتقل تلقائياً)، `video_trimmer.dart`. (`model_picker.dart` و`dataset_picker.dart` في P8b.)
2. **ST1** `studio_screen.dart` → `TabRootScaffold` + `SegmentedBar` (إنشاء ‖ مكتبتي): بطاقات الأدوات (منها مدخل Restyle الحالي بنفس الـ Key `studio-restyle`) + آخر النتائج + chips (نتائج ‖ موديلات ‖ Datasets) تفتح الشاشات القديمة لحد P8b. **شيل** صفوف Activity/Results/Models/Datasets/LoRA المكررة.
3. **ST2 Reface** 3 خطوات على `FlowScaffold` مع القفز للخطوة المناسبة من `TargetRef`/`identity`. **الخيارات والسلوك كما هي** (ملف الجودة، الاستعادة، كل الوجوه، تعزيز الهوية، معاينة، اكتشاف الوجوه، أطقم الهوية، DFM كمصدر اختياري). لا تغيير في أنواع المهام (`reface_image/reface_video` + `quality_profile`).
4. إزالة `Navigator.push` وdialogs في الملفات دي.
**الاختبارات:** المذكورة منقولة بنفس سيناريوهاتها (خصوصاً reface_*) + `studio_hub_test`, `flow_jump_ahead_test`, `job_submit_bar_test`.
**الإنجاز:** مهام Reface تتبعت بنفس الـ payloads (اختبارات الـ DTO والـ contract تفضل خضراء)؛ مفيش Activity/Results مكررين في Studio.

---

### P8b — LoRA والنتائج والموديلات · (L)
**الهدف:** ST4–ST9 ومكتبتي.
**للقراءة:** `05_studio_and_activity.md` (ST4–ST9)، `features/lora/lora_screens.dart` (1442)، `features/results/results_screen.dart`، `features/people/training_export_*`، `data/repositories/{studio_repository,lora_repository}.dart`، اختبارات: `lora_model_anchor_test, lora_identity_parity_test, privacy_and_lora_test`.
**المهام**
1. `model_picker.dart` و`dataset_picker.dart` في `lib/ui/flow/`.
2. **ST4 Generate** و**ST5/ST6/ST7** (تقسيم `lora_screens.dart` إلى ملفات: build، dataset editor، train، generate، model detail، library) على `FlowScaffold`/`DetailScaffold`. `exportDataset` (zip) داخل ST6.
3. **مكتبتي:** chips (نتائج ‖ موديلات ‖ Datasets) بدمج `results_screen` و`LoraScreen`.
4. **ST8 النتيجة** (`CompareSlider`، المنشأ، حفظ في المعرض/مشاركة/تشغيل مرة أخرى `runAgain`، حذف بـ `ConfirmSheet` يعرض التبعات). **ST9 الموديل**.
5. تفعيل `addToDataset` من المعرض/المفتش (لو اتأجل في P5a) عبر `DatasetPicker` (من المفتش بعد دمج P5c).
6. إزالة `Navigator.push` وdialogs في الملفات دي.
**الاختبارات:** المذكورة منقولة بنفس سيناريوهاتها.
**الإنجاز:** نفس مهام LoRA تتبعت بنفس الـ payloads؛ النتائج والموديلات والـ Datasets بيتها الوحيد "مكتبتي".

---

### P9 — التنظيف والتدقيق النهائي · (M)
**المهام**
0. **قبل أي حذف:** المستخدم يعدّي قائمة تحقق الهاتف تحت على APK فيه الشاشات الجديدة، ويأكد. الحذف بعد كده بس.
1. احذف الشاشات/الملفات القديمة اللي اتبدلت (جدول 07 §1 + §2): `home_screen.dart`, `discover_screen.dart`, `bodies_screen.dart` (حسب قرار افتراض #7؛ لو تبويب Areas فضل، لا تحذفه ولا `body_areas.dart`), `review_*` القديمة, `unsorted_screen.dart`, `identity_groups_screen.dart`, `jobs_screen.dart` (القديم), `results_screen.dart` (القديم), `lora_screens.dart` (القديم), `placeholder_screen.dart`، إلخ، وأي `export`/re-export مؤقت. **لا تلمس** `restyle_screen.dart` ولا مساره.
2. احذف الـ redirects اللي ملهاش داعي (أبقِ روابط خارجية متوقعة) و`Routes.home`.
3. نفّذ جدول §2 فوق بالكامل وسجّل النتائج الفعلية.
4. تدقيق إتاحة: تكبير الخط 2.0، أهداف اللمس، `Semantics`، الشاشات الصغيرة 320dp.
5. حدّث: `docs/app_screens/` (قديم) → أضف في أعلى كل ملف "مستبدل بـ app_screens_v2" أو احذف المجلد بموافقة المستخدم؛ `CLAUDE.md` (قسم mobile: الأرقام، المسارات، schema 19)؛ الـ handoff.
6. APK release: **لا تبنِ/تثبّت** إلا بطلب المستخدم؛ جهّز قائمة تحقق يدوية للهاتف (أدناه).

**قائمة تحقق الهاتف (يعملها المستخدم):** المعرض (سرعة الفتح، الكثافة، الفيديو والمشغل الخارجي) · المفتش وتصحيح ربط وجه/جسم وUndo · "ملوش صاحب" يفضل ظاهر · الفحص من `/activity` والـ Pill · Reface صورة/فيديو · نسخ احتياطي واستعادة (schema 19) · قفل التطبيق · الأشخاص والمراجعة · الاستكشاف والمطابقة.

---

## 4. خريطة الاختبارات الحالية ← المرحلة

| الاختبار | المرحلة |
|---|---|
| `onboarding_test`, `connection_screen_test`, `background_test`, `backup_password_test`, `scan_and_settings_test`, `running_scan_test`, `resources_test`, `analyze_test`, `video_scan_details_test`, `home_test` | P4 |
| `library_test`, `native_gallery_instant_test`, `gallery_first_test`, `gallery_first_preview_test` | P5a |
| `viewer_gestures_test`, `media_screen_native_player_test`, `video_media_view_test`, `media_target_test`, `image_preview_test`, `outline_overlay_test`, `body_overlay_painter_test` | P5b |
| `body_inspection_sheet_test` | P5c |
| `people_test`, `people_actions_test`, `people_simplified_ux_test`, `characters_test`, `identity_groups_ux_test`, `identity_set_editor_test` | P6a |
| `review_test`, `quick_review_test`, `review_viewer_test`, `marks_ui_test` | P6b |
| `bodies_screen_test`, `body_universal_naming_test`, `group_pose_ux_test`, `actions_screen_test` | P7 |
| `studio_test`, `contextual_studio_test`, `reface_all_faces_test`, `reface_direct_identity_test`, `reface_options_test`, `reface_reference_test`, `reface_trimmer_test` | P8a |
| `lora_model_anchor_test`, `lora_identity_parity_test`, `privacy_and_lora_test` | P8b |
| `body_areas_test` | لا يتنقل (افتراض #7) |
| `redesign_screens_test`, `redesign_ux_test`, `video_and_insights_test`, `widget_test` | يُفحص كل واحد في P0 ويُوزَّع (مختلط) |
| `test/data/*`, `test/domain/*` | تبقى؛ تتأثر في P2 فقط (`app_database_test`, `grouping_*`, `backup_*`, `identity_*`) |

*(التوزيع النهائي يتأكد في P0 من محتوى كل ملف، مش من الاسم.)*

---

## 5. المخاطر وإزاي نتعامل معاها

| الخطر | التخفيف |
|---|---|
| تفكيك ملفات ضخمة يكسر سلوك دقيق (إيماءات، فيديو، Reface) | Characterization tests أولاً (قاعدة 7)، تفكيك بالاستخراج بدون تغيير منطق، مرحلة لكل شاشة كبيرة |
| تصحيح المستخدم يضيع مع إعادة الفحص/التجميع | `body_overrides` و`face_overrides` بمفتاح asset + box ونطاق `track` للفيديو، `BodyLinkGuard`، P2 بند 4، اختبارات "ما يرجعش" |
| شاشات قديمة تبقى غير متاحة بين المراحل | كل redirect يتفعّل مع مرحلة شاشته (07 §3)، و`router_test` بيغطي المسارات اللي لسه ما اتفعّلتش |
| migration v19 على المكتبة الحقيقية اتجاه واحد | `.agbackup` قبل التثبيت + نقطة تحقق الهاتف بعد P2 + اختبار migration واستعادة v18 |
| حذف الكود القديم قبل ما يتأكد الجديد على الهاتف | قائمة التحقق قبل حذف P9، مش بعده |
| مكونات P1 تتبني على تخمين من غير مستخدم حقيقي | Pilot على S5 وشبكة النتائج في P1، وتعديل الـ API مسموح عند أول استخدام |
| تعارض دمج على `router.dart` / `app_en.arb` | P3 يسجل كل الـ routes من الأول؛ كل مرحلة تلتزم بمنطقة مفاتيح ARB خاصة بيها (prefix) |
| فقد ميزة موجودة أثناء الدمج | جدول 07 §1 + اختبار "كل الإجراءات القديمة ظاهرة" في P5b + قائمة تحقق الهاتف |
| الواجهة إنجليزي بينما الـ spec عربي | محسوم: الواجهة إنجليزي. الـ spec العربي وصف؛ التسميات الإنجليزية في عمود جديد في 01 §2 (P0) |

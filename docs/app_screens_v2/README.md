# Your Gallery — الشاشات v2 (إعادة تصميم من الصفر)

> **الحالة:** مواصفات (Spec) فقط — لم يُغيَّر أي كود.
> **يحل محل:** `docs/app_screens/` (التوثيق القديم يصف الوضع الحالي بما فيه من تكرار).
> **الفكرة:** نفس الـ features بالكامل، لكن الشاشات مكتوبة كأننا نبني التطبيق من أول وجديد: كل شاشة لها غرض واحد، وكل Action معرَّف مرة واحدة، وكل Component مشترك له اسم ومكان واحد.

## الملفات

| الملف | المحتوى |
|---|---|
| **README.md** (هذا الملف) | المشاكل الحالية، المبادئ، خريطة التنقل، جدول الشاشات النهائي، قوالب الشاشات، قواعد الـ AppBar |
| [01_shared_components.md](./01_shared_components.md) | **كتالوج الـ Components المشتركة** + سجل الـ Actions (Action Registry) + المصفوفة (Entity × Action) |
| [02_library_and_viewer.md](./02_library_and_viewer.md) | المعرض، الألبوم، عارض الوسائط، التفاصيل، المعاينة الكاملة |
| [03_people_and_review.md](./03_people_and_review.md) | الأشخاص، الشخص، المجموعات، مركز المراجعة، الدمج، تنظيم الملفات |
| [04_explore.md](./04_explore.md) | الاستكشاف: وضعيات/ملابس/جماعية/أدوات/مناطق/وشوم/أنشطة |
| [05_studio_and_activity.md](./05_studio_and_activity.md) | الاستوديو (Reface/Restyle/Generate/Train)، النتائج، الموديلات، النشاط والمهام |
| [06_settings_onboarding.md](./06_settings_onboarding.md) | البداية (Welcome/Pair/Permissions) والإعدادات بكل أقسامها |
| [07_migration_map.md](./07_migration_map.md) | خريطة الانتقال: كل شاشة قديمة ← مكانها الجديد، ما سيُحذف، تغييرات الـ schema، معايير القبول |
| [08_implementation_plan.md](./08_implementation_plan.md) | **خطة التنفيذ على مراحل (P0–P9)** لتشغيلها في Antigravity: لكل مرحلة الملفات، المهام، الاختبارات، ومعايير الإنجاز |

---

## 1. المشاكل الموجودة (من الكود الفعلي، مش من التوثيق)

| # | المشكلة | الدليل في الكود |
|---|---|---|
| 1 | نفس الوجهة موجودة في أماكن كتير | `Routes.jobs` مستدعاة من **10** ملفات، `Routes.results` من **7**، `Routes.lora` من **6**، `Routes.reface` من **7** |
| 2 | صفوف مختلفة بتفتح نفس الشاشة | في `studio_screen.dart`: "LoRA" و"Models" و"Datasets" الثلاثة → `/lora`. و"Activity" مرتين (AppBar + صف)، و"Results" مرتين (AppBar + صف) |
| 3 | شاشة Home مكررة ومش في الـ nav | `home_screen.dart` فيها: حالة الـ PC + إحصائيات + Scan + Review + Reface + Results + Jobs + Insights + Settings — وبتتفتح من قائمة المعرض باسم "Overview" |
| 4 | الـ AppBar عشوائي | المعرض: فلتر + فحص + قائمة فيها (Scan / Activity / Settings / Overview). الأشخاص: تحديد + قائمة فيها (مجموعات / مراجعة / أجسام / ...). الاستكشاف: أيقونة Activity. الاستوديو: Activity + Results |
| 5 | تنقل خارج الـ router | **27** موضع `Navigator.of(context).push(...)` في `features/` (غير `shared/`) — مش deep-linkable ومش بيحترم الـ back stack |
| 6 | شاشات متشابهة بتعمل حاجات مختلفة | مراجعة الوجوه: `ReviewScreen` + `QuickReviewScreen` + `AlbumReviewScreen` + `UnsortedScreen` + `SimilarFacesScreen`. الأجسام: `BodiesScreen` (6 تبويبات) + `EquipmentPhotoScreen` + `GroupPoseResultsScreen` + `Discover` |
| 7 | إعادة التسمية بـ 6 طرق | `_NameDialog`, `_GroupNameDialog` (×2 في ملفين), `rename-pose`, `rename-outfit`, `rename-cluster`, rename الشخص |
| 8 | الربط بالـ PC موزع | `WelcomeScreen` + `QrScanScreen` + `ManualPairScreen` + `ConnectionScreen` |
| 9 | تحكم الفحص موزع | `SourcesScreen` + `RunningScanScreen` + `AnalyzeScreen` + `ScanProgressCard` (في 3 شاشات) + إحصائيات `Insights` |
| 10 | التوثيق القديم لا يطابق الكود | يذكر `features/actions/` (غير موجود — الفعلي `features/video_actions/`)، ويذكر `/characters` كشاشة منفصلة وهي نفس `PeopleScreen(kind:)` |

---

## 2. المبادئ (قواعد غير قابلة للتفاوض)

1. **مفهوم واحد = شاشة واحدة = بيت واحد.** (النشاط في `/activity` فقط، النتائج في Studio فقط، الإعدادات في `/settings` فقط).
2. **الاختصارات (Shortcuts) مسموحة فقط من داخل سياق الكيان** — مثلاً "Reface" يظهر من الشخص أو من الوجه أو من الوسيط (ويحمل معه الـ Target)، لكن **لا يظهر** كأيقونة عامة في AppBar شاشة ليست متعلقة.
3. **كل Action يتعرّف مرة واحدة** في `ActionRegistry` (اسم، أيقونة، شروط ظهور، النتيجة). أي قائمة/Sheet/شريط تحديد بتبنى منه — مفيش قائمة مكتوبة بإيدك.
4. **كل قائمة = `CollectionView` واحدة** (بحث/ترتيب/فلاتر/تحديد/حالات). شبكة الأشخاص وشبكة الوضعيات وقائمة النتائج بنفس السلوك.
5. **كل إعادة تسمية = `NameSheet` واحد.** كل اختيار شخص = `PersonPicker` واحد. كل تأكيد خطير = `ConfirmSheet` واحد.
6. **كل التنقل عبر `go_router`** (صفر `Navigator.push`)، والـ Sheets فقط هي اللي تتفتح بـ `showModalBottomSheet`.
7. **أنواع الشاشات 7 فقط** (قوالب T1–T7 تحت)، وأي شاشة جديدة لازم تختار واحد منهم.
8. **التقدم/النشاط الجاري ليه مكان واحد:** `ActivityPill` (عالمي) ← `/activity`. مفيش بطاقات تقدم مكررة في Home وLibrary وJobs.

---

## 3. خريطة التنقل

```
App
 ├─ Onboarding (قبل أول استخدام)
 │    /welcome  ─►  /pair  ─►  /permissions  ─►  /library
 │
 ├─ AppShell  (4 تبويبات + ActivityPill فوق الـ NavigationBar)
 │    1. المعرض     /library        ─ /library/album/:id ─ /media/:id
 │    2. الأشخاص    /people         ─ /people/:id ─ /groups/:id ─ /review ─ /merge/:a/:b ─ /people/:id/files
 │    3. استكشاف    /explore        ─ /explore/:kind ─ /explore/:kind/:id ─ /explore/actions/:id[/example]
 │    4. الاستوديو  /studio         ─ /studio/{reface,restyle,generate,train,datasets/new}
 │                                  ─ /studio/{results,models,datasets}/:id
 │
 ├─ /activity ─ /activity/:jobId          (من الـ Pill أو من الإعدادات؛ مش تبويب)
 └─ /settings ─ /settings/{computer,library,privacy,storage,backup,background}
                                          (⚙ في كل تبويب)
```

**4 تبويبات بس.** لا Home، لا Jobs، لا Results كتبويبات.

---

## 4. جدول الشاشات النهائي

| ID | الشاشة | Route | القالب | ملف الشرح |
|---|---|---|---|---|
| O1 | Welcome | `/welcome` | T6 | 06 |
| O2 | Pair (QR ‖ يدوي) | `/pair` | T4 | 06 |
| O3 | Permissions | `/permissions` | T4 | 06 |
| L1 | Library (صور ‖ ألبومات) | `/library` | T1 | 02 |
| L2 | Album | `/library/album/:id` | T2 | 02 |
| L3 | Media Viewer | `/media/:id` | T5 | 02 |
| L4 | Image Preview (تكبير + Lens) | overlay | T5 | 02 |
| P1 | People (أشخاص ‖ شخصيات ‖ مجموعات) | `/people` | T1 | 03 |
| P2 | Person | `/people/:id` | T3 | 03 |
| P3 | Group | `/groups/:id` | T3 | 03 |
| P4 | Review Hub | `/review` | T2 | 03 |
| P5 | Merge | `/merge/:a/:b` | T4 | 03 |
| P6 | Organize Files | `/people/:id/files` | T4 | 03 |
| E1 | Explore | `/explore` | T1 | 04 |
| E2 | Collection (حسب النوع) | `/explore/:kind` | T2 | 04 |
| E3 | Cluster | `/explore/:kind/:id` | T2 | 04 |
| E4 | Action Detail | `/explore/actions/:id` | T3 | 04 |
| E5 | Action Example Editor | `/explore/actions/:id/example` | T4 | 04 |
| ST1 | Studio (إنشاء ‖ مكتبتي) | `/studio` | T1 | 05 |
| ST2 | Reface | `/studio/reface` | T4 | 05 |
| ST3 | Restyle | `/studio/restyle` | T4 | 05 |
| ST4 | Generate | `/studio/generate` | T4 | 05 |
| ST5 | Dataset Build | `/studio/datasets/new` | T4 | 05 |
| ST6 | Dataset Editor | `/studio/datasets/:id` | T3 | 05 |
| ST7 | Train | `/studio/train` | T4 | 05 |
| ST8 | Result | `/studio/results/:id` | T5 | 05 |
| ST9 | Model | `/studio/models/:id` | T3 | 05 |
| A1 | Activity (الآن ‖ السجل) | `/activity` | T2 | 05 |
| A2 | Job | `/activity/:jobId` | T3 | 05 |
| S1 | Settings | `/settings` | T6 | 06 |
| S2 | Computer (الاتصال + الجاهزية) | `/settings/computer` | T6 | 06 |
| S3 | Library & Scan | `/settings/library` | T6 | 06 |
| S4 | Privacy & Lock | `/settings/privacy` | T6 | 06 |
| S5 | Storage | `/settings/storage` | T6 | 06 |
| S6 | Backup | `/settings/backup` | T6 | 06 |
| S7 | Background & Battery | `/settings/background` | T6 | 06 |

**الإجمالي: 37 شاشة** (كان 68+ سطحاً)، بالإضافة إلى Sheets مشتركة معرّفة في 01.

الشخصيات (Anime) مش شاشة منفصلة: هي `kind=character` في نفس P1/P2/P4. الأوجه غير المصنفة، الاقتراحات، التكرارات، الوجوه المشابهة — كلها **طوابير (queues)** داخل P4.

---

## 5. قوالب الشاشات (Screen Templates)

| القالب | الاستخدام | الهيكل الثابت |
|---|---|---|
| **T1 TabRoot** | جذر تبويب | AppBar(عنوان، ≤ 1 إجراء أساسي، ⚙) → `SegmentedBar` اختياري → محتوى → (FAB واحد كحد أقصى) |
| **T2 Collection** | أي قائمة/شبكة | AppBar(رجوع، عنوان، فلتر) → `FilterBar` → `CollectionView` → `BulkActionBar` عند التحديد |
| **T3 Detail** | كيان له هوية | `DetailHeader` (صورة، اسم قابل للتعديل، شارات، 2–3 أزرار + ⋮) → `TabBar` ≤ 4 → محتوى كل تبويب = `CollectionView` |
| **T4 Flow** | معالج/نموذج متعدد الخطوات | `Stepper` → محتوى الخطوة → `StickyActionBar` (رجوع/التالي أو إرسال) |
| **T5 Viewer** | عرض محتوى بملء الشاشة | خلفية سوداء، Chrome قابل للإخفاء، أدوات علوية وسفلية ثابتة |
| **T6 Settings** | إعدادات وقوائم نصية | `SettingGroup`s من `SettingTile`s، لا Cards مزخرفة |
| **T7 Sheet** | قرار/اختيار سريع | `SheetScaffold`: عنوان، محتوى، زر أساسي واحد + ثانوي |

---

## 6. قواعد الـ AppBar والتنقل

### جذر التبويب (T1)
- الترتيب الثابت من اليمين (RTL: اليسار) للنهاية: **[إجراء خاص بالتبويب (اختياري، واحد فقط)] [⚙ إعدادات]**.
- **ممنوع** قائمة ⋮ في جذر التبويب. أي فعل ثانوي إما `SegmentedBar` أو FAB أو داخل سياق الكيان.
- الإجراء الخاص بالتبويب: المعرض = فلتر، الأشخاص = بحث، استكشاف = لا شيء (البحث في E2)، الاستوديو = لا شيء.

### الشاشات الداخلية (T2/T3/T4)
- `[← رجوع] [عنوان] … [≤ 2 إجراء مباشر] [⋮ اختياري]`.
- الـ ⋮ يحتوي أفعال **هذا الكيان** فقط (إعادة تسمية، حذف، نقل...). **ممنوع** يحتوي روابط لتبويبات/شاشات أخرى.

### الرجوع (Back)
- `leave(context, fallback)` الموجودة حالياً هي القاعدة: pop لو في stack وإلا `go(fallback)` حيث fallback = جذر التبويب الأب.
- الـ Flow (T4) بيسأل قبل الخروج لو فيه تغييرات غير محفوظة.

### Deep link / تمرير السياق
- كل Flow بياخد **`Target`** واحد موحد بدل 5 باراميترات مختلفة:
  `target=media:{id}[,det:{id}]` + `person={id}` + `identity={id}` — يتحلل في `TargetPicker`/`IdentityPicker` ويُملأ مسبقاً ويقفز للخطوة المناسبة.
- السياق اللي بيمر للـ Viewer (`MediaCollectionContext`) معرَّف مرة: `ids` + `loadMore` + `source ∈ {library, album, person, cluster, result, search}`.

### الـ ActivityPill
- شريط رفيع فوق الـ NavigationBar في الجذور وأسفل الشاشة في الشاشات التفصيلية، بيحجز مساحته ومش بيغطي أي عنصر. يظهر فقط لما يكون فيه فحص شغال أو مهمة جارية أو فشل لم يُشاهد.
- المحتوى: أيقونة النوع + نص ("يفحص 340/1200" أو "Reface 62%") + عدد إضافي. الضغط → `/activity`.
- هو **المدخل الوحيد** لتقدم الفحص والمهام من الشاشات الأخرى. لا أيقونة Activity في أي AppBar.

# 01 — الـ Components المشتركة وسجل الـ Actions

كل شاشة في الملفات 02–06 تتكون **فقط** من العناصر المعرّفة هنا. لو شاشة محتاجة عنصر مش موجود: يتضاف هنا الأول.

---

## 1. الكتالوج

### A) هياكل الشاشات (Scaffolds)
| Component | الاستخدام | ملاحظات |
|---|---|---|
| `TabRootScaffold` | T1 | يفرض قاعدة الـ AppBar (≤ 1 إجراء + ⚙). `ActivityPill` مش جواه: بيتعرض من `AppShell` في الجذور ومن `ActivityPillHost` في باقي الشاشات (08 P3) |
| `DetailScaffold` | T2/T3 | AppBar بـ ≤ 2 إجراء + ⋮، يدعم `TabBar` |
| `FlowScaffold` | T4 | `Stepper` + `StickyActionBar`، حماية الخروج |
| `ViewerScaffold` | T5 | immersive، Chrome toggle بنقرة |
| `SheetScaffold` | T7 | عنوان + محتوى + زر أساسي واحد |
| `SettingsScaffold` | T6 | `SettingGroup`s |

### B) العناصر البصرية الذرّية
| Component | وصف | الاستخدامات |
|---|---|---|
| `Thumb` | مصغرة وسيط (صورة/فيديو + مدة + شارة فحص) | كل شبكات الوسائط |
| `Crop` | قص وجه/جسم/أداة/منطقة بمسار نسبي + زر `ExpandButton` | الوجوه، الأجسام، الأدوات، المناطق، الوشوم |
| `Avatar` | دائرة وجه نموذجي + نقطة حالة اختيارية | أشخاص، شخصيات، مجموعات، "من في الصورة" |
| `Badge` / `InfoChip` | شارة نص/أيقونة (نوع، مجموعة، جودة، حالة) | في كل البطاقات |
| `ProgressBar` | تقدم محدد/غير محدد + ETA | الفحص والمهام |

### C) البطاقة الموحدة `EntityCard`
بطاقة واحدة بثلاث صيغ (`grid` / `row` / `hero`) بدل بطاقة لكل كيان:

```
EntityCard(
  visual:   Thumb | Crop | Avatar | CropStack(3) | Icon,
  title:    String (قابل للتعديل عبر NameSheet لو editable),
  subtitle: String?   // "42 صورة · 3 فيديو"
  badges:   List<Badge>,
  state:    normal | selected | disabled | busy(progress),
  trailing: Widget? | actions → EntityActionSheet
)
```
تُستخدم لـ: **Person, Character, Group, Album, Source, Pose, Outfit, GroupPose, Equipment, Area, Mark, Action, Model, Dataset, Result, Job**.
→ كل ما سبق شكلهم واحد ويتصرفوا بنفس الطريقة (نقر = فتح، ضغط مطول = تحديد، ⋮ = قائمة الـ Registry).

### D) القوائم والشبكات
| Component | وصف |
|---|---|
| `CollectionView<T>` | الحاوية الوحيدة للقوائم: `SearchField` + `SortMenu` + `FilterBar` + `ViewMode(grid/list)` + الحالات الأربع + التحديد. يأخذ `CollectionController<T>` فوق `CollectionSource<T>` بيدعم التحميل بالصفحات |
| `MediaGrid` | شبكة وسائط: تجميع بالتاريخ أو مسطّحة، كثافة 3/4/5 بالقرص، `Thumb`، تحديد، فتح الـ Viewer بسياق |
| `CropGrid` | نفس `MediaGrid` لكن لـ `Crop`s (وجوه/أجسام)، يدعم فرز الجودة |
| `EntityGrid` / `EntityList` | `CollectionView` فوق `EntityCard` |
| `FilterBar` | صف chips أفقي (نشطة فقط + زر "فلاتر") + `FilterSheet` موحد. الفلاتر معرّفة بـ `FilterSpec` لكل نوع |
| `SegmentedBar` | تبديل 2–3 أقسام في أعلى الشاشة (بدل تبويبات لما المحتوى من نفس النوع) |

### E) التحديد والعمليات الجماعية
| Component | وصف |
|---|---|
| `SelectionController` | يدخل بالضغط المطول، يخرج بالرجوع/×؛ يتتبع أنواع العناصر المحددة |
| `SelectionTopBar` | يستبدل الـ AppBar: عدد المحدد، تحديد الكل، × |
| `BulkActionBar` | شريط سفلي: **أقصى 4 إجراءات ظاهرة + "المزيد"**، مبني من `ActionRegistry` بحسب نوع المحدد |

### F) الإجراءات (الأهم لحل "العشوائية")
| Component | وصف |
|---|---|
| `ActionRegistry` | جدول واحد لكل الإجراءات (القسم 2) |
| `EntityActionSheet(entity)` | الـ Sheet الوحيدة لقائمة إجراءات أي كيان. مجموعات ثابتة الترتيب: **عرض → تعريف → بحث → إنشاء → إدارة → خطر** |
| `QuickActions(entity)` | أول 3–5 إجراءات ذات الأولوية للكيان كأزرار ظاهرة (في `DetailHeader` أو أسفل الـ Viewer) |
| `ActionDispatcher` | handler واحد لكل `ActionId`. الـ Registry بيوصف الإجراء، والـ Dispatcher بينفذه، والشاشة ما تكتبش `switch` (08 P1) |
| `MediaInspector` | **لوحة الأدوات الكاملة لأي صورة/فيديو** (Peek/Half/Full): اللي في الوسيط، الروابط، الأنشطة، إنشاء، معلومات. هي المكان الوحيد لتصحيح الربط من داخل وسيط (02 §L3a) |
| `DetectionRow` | صف عنصر مكتشف: `Crop` + عنوان + مصدر الربط + زر "صحّح" + ⋮ |
| `LinkRow` | صف رابط بين عنصرين (جسم ← شخص، جسم ≈ جسم، منطقة ← شخص، أداة ← مالك) + "تأكيد" + "صحّح" |
| `CorrectionSheet(link)` | **الـ Sheet الوحيدة لتصحيح أي ربط** (القسم 5): نفس الأفعال لكل أنواع الروابط، مع نطاق ومعاينة الأثر و Undo |
| `ScopePicker` | اختيار نطاق التصحيح في الفيديو: هذه اللقطة ‖ هذا الظهور (افتراضي) ‖ كل الفيديو |

### G) الـ Pickers (كلها Sheets بنفس الأساس `SearchableListSheet`)
| Picker | يرجّع | ملاحظات |
|---|---|---|
| `PersonPicker` | `Person?` / "جديد" | فلتر kind (شخص/شخصية/الكل)، يعرض الأوجه، زر "شخص جديد" |
| `MediaPicker` | `List<Media>` | نفس `MediaGrid`، تبويب صور ‖ ألبومات، single/multi |
| `FacePicker` | `Face` | وجوه شخص أو وسيط، مرتبة بالجودة |
| `GroupPicker` | `Group?` | + إنشاء مجموعة |
| `ModelPicker` | `LoraModel` | الجاهزة فقط |
| `DatasetPicker` | `Dataset` | |

### H) المحررات والتأكيدات
| Component | وصف |
|---|---|
| `NameSheet` | **إعادة تسمية أي شيء** (شخص، مجموعة، وضعية، طقم، وضعية جماعية، أداة، منطقة، وشم، نشاط، موديل، dataset). حقل واحد + اقتراحات اختيارية + حفظ |
| `ConfirmSheet` | تأكيد عادي، أو **خطير**: يعرض قائمة التبعات ("سيُحذف 3 نتائج مرتبطة") وزر أحمر |
| `UndoSnackbar` | بعد أي إجراء قابل للتراجع (إخفاء، رفض، نقل) |
| `PromptField` | نص الوصف + سلبي + presets (Restyle/Generate) |
| `SliderField`, `SegmentedField`, `SwitchField`, `StepperField` | حقول النماذج الموحدة |
| `AdvancedSection` | قسم قابل للطي لأي إعدادات متقدمة |

### I) الحالات والتغذية الراجعة
| Component | وصف |
|---|---|
| `EmptyState(kind)` | `kind` ∈ {first-run, no-results, no-permission, no-pc} — نص + إجراء واحد |
| `ErrorState` | رسالة + إعادة محاولة (يحل محل `RetryState`) |
| `LoadingBox` / `Skeleton` | |
| `StatusNotice` | رسالة سياقية (info/warn/error) |
| `ReadinessBanner` | حالة الـ PC + الموديلات المطلوبة للأداة الحالية؛ يوجّه إلى `/settings/computer` |
| `ProgressCard(job|scan)` | **بطاقة واحدة** لتقدم الفحص والمهام: أيقونة، عنوان، مراحل، %، ETA، أزرار (إيقاف/استئناف/إلغاء/إعادة) |
| `ActivityPill` | الشريط العالمي (README §6) |

### J) العارضات
| Component | وصف |
|---|---|
| `ImageViewer` | تكبير بالقرص ونقرتين، تمرير بين العناصر |
| `VideoPlayer` | zero-copy عبر `contentUri`، تشغيل تلقائي عند الوصول، صامت افتراضياً (`mute` toggle)، scrubber، "فتح بالمشغل الخارجي" |
| `ExpandButton` → `ImagePreview` | شاشة كاملة: تبديل (مقصوص ‖ الأصل)، Google Lens. موجود على كل `Crop`/نتيجة |
| `DetectionOverlay` | رسم مربعات وجوه/أجسام + هيكل 17 نقطة + منطقة. **مجموعة طبقات** `layers ⊆ {faces, bodies, skeleton, areas, equipment}` (اختيار متعدد، الافتراضي وجوه + أجسام). نقر على أي عنصر مرسوم → `EntityActionSheet` لنوعه |
| `CompareSlider` | قبل/بعد (صور) أو مشغلين متزامنين (فيديو) |

### K) مكونات الـ Flows
| Component | وصف |
|---|---|
| `Stepper` | مؤشر الخطوات (1/3) مع إمكانية الرجوع لخطوة سابقة |
| `StickyActionBar` | أسفل الشاشة: ثانوي (رجوع) + أساسي (التالي/ابدأ) |
| `TargetPicker` | وسيط (`MediaPicker`) + اختيار وجه/جسم مستهدف + قص الفيديو (`VideoTrimmer`). **يستخدمه** Reface وRestyle وGenerate (مرجع الوضعية) وDataset Build |
| `IdentityPicker` | شخص/شخصية أو "طقم هوية" (`IdentitySetEditor`)، يمنع المزج بين ArcFace وCCIP |
| `JobSubmitBar` | يتحقق من `ReadinessBanner` ثم يرسل ثم Snackbar "شوف في النشاط" |
| `VideoTrimmer` | شريط مدى زمني (حد أدنى/أقصى حسب الأداة) + معاينة |

### L) الإعدادات
| Component | وصف |
|---|---|
| `SettingGroup` | عنوان قسم + مجموعة صفوف |
| `SettingTile` | أنواع: `nav` (→ شاشة)، `switch`، `value` (يعرض قيمة + يفتح Sheet)، `action`، `danger` |

---

## 2. سجل الإجراءات `ActionRegistry`

كل صف يعرّف: `id`، الأيقونة، التسمية العربية، التسمية الإنجليزية (ARB)، الشرط، والنتيجة. الأسماء ثابتة في كل التطبيق.

| المجموعة | id | التسمية (AR) | التسمية (EN) | النتيجة |
|---|---|---|---|---|
| **عرض** | `open` | فتح | Open | يفتح شاشة الكيان |
| | `info` | تفاصيل | Details | يفتح `MediaInspector` (Half) |
| | `expand` | تكبير / Lens | Expand / Lens | `ImagePreview` |
| | `openPhoto` | فتح الصورة الأصلية | Open original | Viewer بالسياق |
| | `openNativePlayer` | مشغل خارجي | Open in player | مشغل النظام (Android Intent) |
| **تعريف** | `rename` | إعادة تسمية | Rename | `NameSheet` |
| | `assignPerson` | تعيين لشخص | Assign to person | `PersonPicker` ← يكتب |
| | `setCover` | اجعله الصورة الرئيسية | Set as cover | Exemplar |
| | `moveToGroup` | نقل لمجموعة | Move to group | `GroupPicker` |
| | `markTattoo` | تعليم وشم/علامة | Mark tattoo | `MarkEditor` sheet |
| | `confirmLink` | تأكيد الربط | Confirm link | يثبّت الربط التلقائي كـ manual |
| | `unlink` | فك الربط (رجوع للتلقائي) | Unlink | بدون رفض؛ التجميع ممكن يربطه تاني |
| | `notThisPerson` | ليس هذا الشخص | Not this person | رفض الزوج (عنصر، شخص) ويُتذكّر |
| | `belongsToNoOne` | ملوش صاحب | Belongs to no one | استبعاد صريح من أي ربط/اقتراح/تجميع |
| | `notARealThing` | مش وجه/جسم/أداة أصلاً | Not a real detection | اكتشاف خاطئ، يُخفى |
| | `notSamePerson` | ليسوا نفس الشخص | Not same person | يفصل عنصرين/مجموعتين (distinct) |
| | `changeKind` | تغيير النوع (شخص ↔ شخصية) | Change figure kind | يصحح `figure` للمربع |
| | `changeFileKind` | نوع الملف كله | Change file kind | يغير وضع الفحص للملف (تلقائي/شخص/شخصية) |
| | `setSensitivity` | حساسة / ليست حساسة | Set sensitive | يكتب `sensitiveOverride` |
| | `addEquipment` | إضافة أداة يدوياً | Add equipment | رسم مربع + `NameSheet` |
| | `boxEquipment` | صندوق أداة | Equipment box | معاينة/تحديد صندوق الأداة |
| | `namePose` / `nameOutfit` / `nameGroupPose` | تسمية الوضعية/الطقم/التشكيل | Name pose / outfit / group | `NameSheet` + يحفظ كـ cluster |
| **بحث** | `similarPose` | وضعية مشابهة | Similar pose | `/explore/all?similar=` (مطابقة صارمة) |
| | `similarColours` | ألوان مشابهة | Similar colours | `/explore/all?colours=` |
| | `similarFaces` | وجوه مشابهة | Similar faces | `/review?queue=similar&face=` |
| | `personMedia` | وسائط هذا الشخص | Person media | Collection مقيّدة |
| **إنشاء** | `refaceThis` | Reface بهذا الهدف | Reface target | `/studio/reface?target=` |
| | `refaceWith` | Reface بهذه الهوية | Reface with identity | `/studio/reface?identity=` |
| | `restyleThis` | Restyle لهذا الجسم | Restyle body | `/studio/restyle?target=` |
| | `generateWith` | توليد بهذا الموديل | Generate with model | `/studio/generate?model=` |
| | `addToDataset` | إضافة لمجموعة تدريب | Add to dataset | `DatasetPicker` / dataset جديد |
| | `trainModel` | تدريب موديل | Train model | `/studio/datasets/new?person=` |
| | `runAgain` | تشغيل مرة أخرى بتعديل | Run again | يفتح الـ Flow بنفس المعاملات |
| **إدارة** | `share` | مشاركة | Share | Android share sheet |
| | `saveToGallery` | حفظ في المعرض | Save to gallery | MediaStore |
| | `merge` | دمج مع... | Merge with... | `/merge/:a/:b` |
| | `organizeFiles` | تنظيم الملفات | Organize files | `/people/:id/files` |
| | `exportDataset` | تصدير مجموعة التدريب | Export training | zip |
| | `analyzeNow` | تحليل الآن | Analyze now | يضيف للطابور بأولوية |
| | `redetect` | إعادة الفحص | Redetect | يعيد كشف الوجوه والأجسام للملف |
| | `albumIncludeScan` | تضمين في الفحص | Include in scan | يضيف الألبوم لنطاق الفحص |
| | `albumExcludeScan` | استبعاد من الفحص | Exclude from scan | يستبعد الألبوم من الفحص |
| | `albumReview` | مراجعة الألبوم | Review album | `/review?album=` |
| | `albumAnalyze` | تحليل الألبوم | Analyze album | يحلل وسائط الألبوم في الاستوديو |
| | `pause` / `resume` / `cancel` / `retry` | تحكم بالمهام | Pause / Resume / Cancel / Retry | للفحص والمهام |
| **خطر** | `remove` | إزالة من هنا | Remove | (وجه من شخص، عنصر من cluster...) |
| | `delete` | حذف | Delete | `ConfirmSheet` خطير + Undo لو أمكن |

---

## 3. مصفوفة الكيان × الإجراء

● = متاح · ○ = متاح بشرط · — = غير متاح · **QA** = من الأزرار السريعة (`QuickActions`)

| الإجراء | Media | Face | Body | Person | Album | Group | Action | Cluster* | Result | Job | Model | Dataset |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| open | ● | ● (→Person) | ● (→Inspect) | ● | ● | ● | ● | ● | ● | ● | ● | ● |
| info | **QA** | ● | ● | — | — | — | ● | — | ● | ● | ● | ● |
| expand | ● | ● | ● | ● (avatar) | — | — | — | ● | ● | — | — | — |
| openPhoto | — | ● | **QA** | — | — | — | ● | — | ○ (المصدر) | — | — | — |
| openNativePlayer | ● (فيديو) | — | — | — | — | — | — | — | — | — | — | — |
| rename | — | — | — | **QA** | — | **QA** | **QA** | **QA** | — | — | ● | ● |
| assignPerson | — | **QA** | ○ (ربط) | — | — | — | — | ○ Area/Mark | — | — | — | — |
| notThisPerson | — | ● | ○ | — | — | — | — | — | — | — | — | — |
| setCover | — | ● | — | — | — | — | — | — | — | — | — | — |
| moveToGroup | — | — | — | ● | — | — | — | — | — | — | — | — |
| markTattoo | — | — | **QA** | — | — | — | — | — | — | — | — | — |
| namePose / nameOutfit | — | — | **QA** | — | — | — | — | — | — | — | — | — |
| similarPose / Colours | — | — | **QA** | — | — | — | — | — | — | — | — | — |
| similarFaces | — | ● | — | — | — | — | — | — | — | — | — | — |
| personMedia | — | — | — | ● | — | — | — | — | — | — | — | — |
| refaceThis | ● | **QA** | ● | — | — | — | — | — | — | — | — | — |
| refaceWith | — | ○ | — | **QA** | — | — | — | — | — | — | — | — |
| restyleThis | ● | — | **QA** | — | — | — | — | — | — | — | — | — |
| generateWith | — | — | — | ○ | — | — | — | — | — | — | **QA** | — |
| addToDataset | ● | ● | — | ● | — | — | — | — | — | — | — | — |
| trainModel | — | — | — | **QA** | — | — | — | — | — | — | — | **QA** |
| runAgain | — | — | — | — | — | — | — | — | **QA** | ○ | — | — |
| share | **QA** | — | — | — | — | — | — | — | **QA** | — | — | — |
| saveToGallery | — | — | — | — | — | — | — | — | **QA** | — | — | — |
| merge | — | — | — | ● | — | — | — | — | — | — | — | — |
| organizeFiles | — | — | — | ● | — | ● | — | — | — | — | — | — |
| exportDataset | — | — | — | — | — | — | — | — | — | — | — | ● |
| analyzeNow | ● | — | — | — | ● | — | — | — | — | — | — | — |
| redetect | ● | — | — | — | — | — | — | — | — | — | — | — |
| albumIncludeScan | — | — | — | — | ● | — | — | — | — | — | — | — |
| albumExcludeScan | — | — | — | — | ● | — | — | — | — | — | — | — |
| albumReview | — | — | — | — | ● | — | — | — | — | — | — | — |
| albumAnalyze | — | — | — | — | ● | — | — | — | — | — | — | — |
| pause/resume/cancel/retry | — | — | — | — | — | — | — | — | — | ● | — | — |
| remove | — | ● (من الشخص) | — | — | — | — | ● (عنصر) | ● (عنصر) | — | — | — | ● (صورة) |
| delete | — | ● | — | ● | — | ● | ● | ○ | ● | ○ (مسح) | ● | ● |

\* Cluster = وضعية/طقم/تشكيل جماعي/أداة/منطقة/وشم/نشاط/مجموعة.

### مصفوفة تكميلية: عناصر داخل الصورة (من الـ Viewer)

| الإجراء | Face | Body | Area | Equipment | Photo (كلها) |
|---|---|---|---|---|---|
| nameGroupPose | — | ○ (لما ≥ 2 أجسام) | — | — | ● |
| changeKind | ● | ● | — | — | — |
| changeFileKind | — | — | — | — | ● |
| rename | — | — | **QA** | **QA** | — |
| assignPerson | **QA** | ○ | ● (ينتمي إلى) | ● (المالك) | — |
| setSensitivity | — | — | ● | — | ● (override للصورة) |
| markTattoo | — | **QA** | ● | — | — |
| addEquipment | — | — | — | ● | ● (يدوي) |
| boxEquipment | — | — | — | ● | — |
| similarPose / similarColours | — | **QA** | — | — | — |
| remove (رفض) | ● | — | ○ | ● | — |

---

## 4. أنماط التفاعل الموحدة

### الحالات الأربع لأي قائمة
`loading` (Skeleton) → `empty` (EmptyState بنوعه + إجراء واحد) → `error` (ErrorState + إعادة) → `content`. زائد `selecting` فوق `content`.

### التحديد
- ضغط مطول يدخل التحديد، نقر يبدّل، زر الرجوع يخرج.
- `BulkActionBar` تعرض **الإجراءات المشتركة بين كل الأنواع المحددة** من الـ Registry.

### التأكيد
- إجراء قابل للتراجع (إخفاء، رفض، نقل) ← تنفيذ فوري + `UndoSnackbar`.
- إجراء غير قابل للتراجع (حذف نتيجة، حذف شخص، استعادة نسخة) ← `ConfirmSheet` خطير مع قائمة التبعات.

### التسمية
- كل عنوان قابل للتعديل يظهر بأيقونة قلم صغيرة؛ النقر عليه يفتح `NameSheet` — **نفس السلوك في الشخص والمجموعة والوضعية والطقم والموديل**.

### التكبير
- كل `Crop` ونتيجة فيها `ExpandButton` في ركن ثابت (أسفل-يمين). هو الطريق الوحيد لـ `ImagePreview` ومنه Google Lens.

### إرسال المهام
- كل زر "ابدأ" في Flow = `JobSubmitBar`: يتحقق من الجاهزية، يرفع، يعرض Snackbar "بدأت — عرض النشاط"، ويبقى المستخدم في مكانه (أو يرجع لنقطة الدخول). **لا ينتقل تلقائياً** لشاشة Jobs.

---

## 5. نموذج التصحيح الموحد (Correction Model)

**المطلوب:** من أي صورة أو فيديو أقدر أقول "الربط ده غلط" وأصلحه — سواء وجه، جسم، منطقة، أداة، أو **رابط بين عنصرين** (مثلاً جسمين مربوطين ببعض على إنهم نفس الشخص، وأنا أقول "لا، دول مش تبع حد"). **نفس الأفعال ونفس الـ Sheet لكل الأنواع.**

### 5.1 الأفعال (تظهر كلها في `CorrectionSheet`، والمتاح منها يتحدد بنوع الرابط)

| الفعل | المعنى | يُتذكّر؟ |
|---|---|---|
| `reassign` | انقله لشخص تاني / شخص جديد (`PersonPicker`) | يصير manual |
| `notThisPerson` | ليس هذا الشخص تحديداً | زوج (عنصر، شخص) — التجميع التلقائي لا يعيده |
| `belongsToNoOne` | **ملوش صاحب** — لا لهذا الشخص ولا لغيره | **صريح**: لا يُربط ولا يُقترح ولا يدخل cluster لأي شخص ولا يدخل التدريب. **يفضل ظاهراً** في المعرض والاستكشاف والمفتش بشارة "بدون مالك" (مش مخفي)، ويقدر المستخدم يحدد صاحبه بعدين بـ `reassign` في أي وقت (يصير manual ويتشال الاستبعاد) |
| `notARealThing` | ده مش وجه/جسم/أداة أصلاً (اكتشاف خاطئ) | يُخفى ولا يتحسب (**هذا الوحيد اللي بيتشال من العرض**، وبيتراجع عنه من طابور المستبعد) |
| `notSamePerson` | العنصران/المجموعتان **ليسوا نفس الشخص** | زوج (أ، ب) |
| `unlink` | فك الربط ورجوعه للتلقائي | لا — ممكن يتربط تاني |
| `confirm` | الربط صح، ثبّته | يصير manual ومحمي من إعادة التجميع |

### 5.2 الأنواع × الأفعال

● = موجود في الكود (تحققت) · 🆕 = **جديد، يحتاج تغيير بيانات** · — = لا ينطبق

| نوع الرابط | reassign | notThisPerson | belongsToNoOne | notARealThing | notSamePerson | unlink | confirm |
|---|---|---|---|---|---|---|---|
| **وجه ← شخص** | ● `assignFaces` | ● `rejectFaces` (جدول `face_rejections`) | 🆕 `clearAssignments` + `dismissFaces` + `faces.ownership` — `review_dismissed` لوحده مش كفاية لأن `deletePerson` وتجاهل المراجعة بيكتبوه كمان | ● حذف/إخفاء الوجه | — | ● `clearAssignments` | ● |
| **جسم ← شخص** (وجه/ملابس/وجه ضعيف/يدوي) | ● `linkBody` | ● `rejectBody` (جدول `body_rejections`) | 🆕 `bodies.ownership = 'none'` | 🆕 `bodies.ownership = 'hidden'` | — | 🆕 (الموجود `rejectBody` بيفك + بيسجل رفض) | ● `acceptBodyLink` |
| **جسم ≈ جسم** (نفس الظهور/الطقم/الـ track) | — | — | 🆕 للاتنين مع بعض | — | 🆕 فصل الـ track + تسجيل `body_distinct` لمنع إعادة الضم بـ `expandTracks` | 🆕 | ● (استبقاء الـ track المشترك) |
| **أداة ← مالك** | ● (المالك `bodyId` اختياري) | — | ● (مالك فاضي) | ● حالة `rejected` | — | ● | ● حالة `manual` |
| **منطقة حساسة** | — | — | — | ● `userState = dismissed` | — | — | ● `confirmed` / `sensitiveOverride` |
| **عضوية cluster وضعية/طقم** | ● (حذف أو `state='rejected'`) | — | — | ● حالة `rejected` في `body_pose_matches` / `body_outfit_matches` (لا تُضاف تاني) | — | ● (`state='auto'`) | ● `state='manual'` |
| **شخص ↔ شخص** | ● `merge` | — | — | — | ● `markDistinct` (`person_distinct`) | — | — |
| **وجه: شخص ↔ شخصية** | ● `kind_corrections` | — | — | — | — | — | — |
| **اقتراح نشاط** | — | — | — | ● رفض | — | — | ● قبول |

> **ملاحظة الفيديو بعد الـ Compaction:** نظراً لأن ضغط الفيديو (`VideoCompactor`) يدمج إطارات المسار المتتالية في صف تمثيلي واحد داخل `bodies` وتشاركه صفوف `media_detections`، فإن نطاقات `ScopePicker` للفيديو تنحصر نظيفاً في: (1) **هذا الظهور / المسار (This appearance / track)** و(2) **كل الفيديو (Whole video)**، لتفادي تشتت الصفوف المضغوطة.
>
> ربط clusters المناطق المكشوفة بالأشخاص خارج نطاق v2 (08 §1)، فمالوش صف هنا، وعمود Area في المصفوفة التكميلية (§3) ينطبق منه `setSensitivity` بس.
>
> أي 🆕 معناه: **تغيير في قاعدة بيانات الهاتف** (جدول أو عمود + migration + إدراجه في `.agbackup` + اختبارات). ملخصها في `07_migration_map.md` §6.

### 5.3 شكل `CorrectionSheet`
```
[ Crop العنصر ] [ الرابط الحالي: "جسم ٣ ← أحمد · من الملابس" ]
─────────────────────────────────────────
 • انقله لشخص تاني…            (reassign)
 • ده مش أحمد                    (notThisPerson)
 • ده ملوش صاحب                  (belongsToNoOne)
 • ده مش جسم أصلاً                (notARealThing)
 • دول مش نفس الشخص             (notSamePerson)      ← لما الرابط بين عنصرين
 • فك الربط (رجوع للتلقائي)     (unlink)
 • تأكيد الربط                    (confirm)
─────────────────────────────────────────
 [نطاق: ○ هذا العنصر ● كل عناصر نفس الظهور/الـ cluster ○ كل الفيديو]   ← ScopePicker
 [ معاينة الأثر: "هيتأثر ٧ عناصر في ٣ صور" ]
                                   [ تطبيق ]
```
- الأفعال غير المنطبقة على نوع الرابط **لا تظهر** (من الجدول فوق).
- **معاينة الأثر** إجبارية لو التصحيح هيأثر على أكتر من عنصر (cluster، ظهور فيديو، مجموعة أجسام) — يعرض العدد قبل التطبيق.
- بعد التطبيق: `UndoSnackbar` (≥ 8 ثواني). التراجع يرجّع الحالة السابقة بالكامل (الرفض/الاستبعاد يتشالوا).

### 5.4 قواعد ثابتة
1. **قرار المستخدم أقوى من أي تجميع تلقائي.** إعادة الفحص، رفع `scanVersion`، إعادة الاكتشاف، الـ backfill، وإعادة التجميع **لا تمسح ولا تتخطى** أي تصحيح؛ لما يرجع اكتشاف نفس المربع تتربط به التصحيحات عبر `sameDetectionBox`.
2. **كل ما استبعدته يفضل ظاهر وقابل للتراجع:** طابور `excluded` في P4 (03) + قسم "ملوش صاحب" في `MediaInspector`.
3. **التصحيح ينتشر للتوابع:** تصحيح جسم أو وجه بيصححه في كل إطارات نفس الظهور (🆕 نطاق `track` في 08 P2؛ `expandTracks` الموجود للوجوه غير المعيّنة بس)، وتصحيح cluster بيصحح أعضاءه بعد معاينة الأثر.
4. **النسخ الاحتياطي:** كل جداول التصحيح تدخل في `.agbackup` وتستعاد.
5. **نفس السلوك من أي مدخل:** `CorrectionSheet` بتفتح من `MediaInspector` أو من Person ▸ الوجوه أو من Explore أو من P4 — والنتيجة واحدة.

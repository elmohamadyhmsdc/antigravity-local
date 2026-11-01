# مراجعة الاحتفاظ بالميزات وصحة المسارات

التاريخ: 1 نوفمبر 2026. النطاق: مراجعة تصميم فقط. الحالة النهائية: **مراجعة تغطية الميزات وصحة الـInventory مكتملة؛ التنفيذ وترحيل البيانات والتحقق من التطبيق مراحل لاحقة.**

راجعت [التصور الأساسي](../../gallery-first-mobile-concept-2026-11-01.md)، [عقود المسارات والحالات](flows-and-states.md)، والنسخة النهائية من [screen inventory](screen-inventory.json)، اعتمادًا على فحص المصدر السابق وقراءات محدودة لتأكيد النقاط أدناه. لم تتغير ملفات التطبيق، ولم يُشغّل shell أو build أو tests.

## نتيجة المراجعة

خريطة Gallery / People / Discover / Studio متسقة مع الجاليري كنقطة بداية، وتغطي عائلات الميزات القائمة. راجعت تعديلات R01–R06 في JSON النهائي وأصبحت ممثلة بوضوح في تعريف الأسطح. لا توجد ملاحظة parity مفتوحة من هذه الجولة. فحص مطابقة الصور المرسومة نفسها، أحجامها ووضوح عناصرها منفصل ويظل ضمن مراجعة الرسم.

فحص البنية النهائي: **68 سطحًا**، دون IDs مكررة أو parentId/backTo مفقودة، ولكل سطح فعل أساسي ومحتوى وحالات. هذا فحص وثيقة، ولا يثبت navigation أو feature parity داخل التطبيق.

## إغلاق الملاحظات الست

| المرجع | ما تحقق في JSON النهائي | الحالة |
|---|---|---|
| R01 — equipment-editor | الإضافة اليدوية تحفظ label وowner/shared دون رسم منطقة جديدة؛ أزيل وعد رسم box غير موجود | مغلقة في التصميم |
| R02 — identity-merge | اختيار surviving identity، ومراجعة الأثر على LoRAs/Datasets/results/marks، مع تمييز فجوة التنفيذ وعدم وعد undo شامل | مغلقة في تعريف المسار؛ سياسة البيانات مطلوبة قبل التنفيذ |
| R03 — result-viewer deletion | أضيف variant لتأكيد حذف artifact يذكر same-ID model/dataset والملفات المتأثرة؛ لا يُعامل كل حذف كصورة فقط | مغلقة في التصميم |
| R04 — result-viewer comparison | Before/After فقط بوجود مصدر؛ text-only generation بلا Before؛ source/output expansion مشروطان بوجودهما | مغلقة في التصميم |
| R05 — backup-restore | Encryption on by default، كلمة مرور وتأكيد عند التشفير، وplaintext opt-out صريح؛ بقي نطاق النسخة واضحًا | مغلقة في التصميم |
| R06 — Reface | Image entry يملأ target؛ Person entry يملأ source فقط بعد Use this identity؛ DFM يمكن أن يتجاوز real-face source؛ مراجعة الأدوار واضحة | مغلقة في التصميم |

ملاحظة للرسم: نصوص قيود التنفيذ داخل identity-merge مثل «Current merge does not automatically preserve every artifact link» و«Mark deletion and orphaned links must be resolved before implementation» هي ملاحظات للفريق؛ لا تُعرض كنص منتج للمستخدم. سطح الدمج المرئي يعرض الشخص الباقي والعناصر المتأثرة والنتيجة المقصودة. أُبلغ المسؤول عن الرسم بهذه النقطة.

## المجالات التي بقيت متميزة

| المجال | ما تم الحفاظ عليه في التصور | قيد التنفيذ |
|---|---|---|
| الأصل والتحليل | Gallery يشمل الأصول المتاحة قبل Scan، والمجلد لا يبدأ التحليل | يحتاج طبقة أصول مستقلة؛ Library الحالية تبدأ من media المعروفة في DB |
| الأشخاص في الصورة | MediaDetections ← ظهور ← شخص | لا الاعتماد على Faces.mediaId وحدها، كي لا تختفي occurrences مرتبطة بوجه سابق |
| هوية الوجه المحفوظة | IdentitySet اختيار وجوه مرجعية حقيقية | ليست LoRA أو DFM أو embedding model |
| LoRA للشخص | صفحة الشخص/الموديلات ومدخل من الصورة وأداة التوليد | لا زر Reface مباشر لوزن LoRA؛ verified portrait identity مسار تحقق مستقل |
| DFM ومحركات مشتركة | إعدادات الأداة وجاهزية PC | لا توجد علاقة شخص↔DFM دائمة؛ لا نسبه بالاسم |
| الموديل والـDataset والنتيجة | كل artifact له تفاصيل ومدخل ونوع وحالة | lineage لا يُستنتج من الاسم أو personId وحده |
| Backup | الفهرس والتصحيحات والأصول الخاصة المشمولة والتشفير والاستعادة | لا نسخ شامل لصور MediaStore؛ PC credentials لا تنتقل |

## الاحتفاظ بالميزات: نتيجة المقارنة

- Gallery/folders/photo/video/details/target selection والتكبير/original-crop/Lens لها أسطح واضحة، مع local/unscanned/permission/missing-source states.
- People/Characters، الوجوه غير المصنفة، الهوية/الوجوه/الأجسام/العلامات، مجموعات الهوية، الأدوات والتحديد الجماعي، review السريع والمتقدم، merge/split/distinct وتصحيح الاكتشاف لها مداخل. تبقى معاينة crop والأصل المرتبط به جزءًا من مسار المقارنة.
- Discover يغطي poses/outfits/colours/group poses/equipment/marks/body areas والفئات المحفوظة. الحدود photo-only وwhole-group comparison وexperimental opt-in واضحة، دون semantic search أو garment filters غير معايرة.
- Studio يغطي Reface ومصادره وأهدافه، Restyle ومراجعه، datasets/captions/include-exclude/export، التدريب، generation والمراجع، الموديلات والهوية المتحققة، النتائج والفيديو/المقارنة/الحفظ/المشاركة. سلوك multi-angle الحالي يجب أن يستمر حتى إن لم يكن toggle مستقلًا؛ المصدر يرسل multi_angle=true في lora_screens.dart:829.
- Activity يحافظ على scan/jobs/history/progress/ETA/pause/resume/retry/lost والـevents. إزالة Jobs من bottom navigation لا تمحو مدخله أو أدواته.
- التشغيل يحافظ على sources/settings/quality/grouping/outline retry/standalone analysis/Insights، PC pairing/QR/manual/LAN readiness، background/battery، storage، encrypted backup/restore، app lock، وتنظيم الملفات الفعلية بمعاينة وتسوية.

لا حاجة لشاشة مستقلة لكل حالة؛ sheets/dialog variants مقبولة عندما يكون الدخول والعودة والأثر واضحين. اعتماد الـInventory لا يعفي التنفيذ من الاحتفاظ بضوابط الأداة الحالية في قسم Advanced مناسب عند استخدام progressive disclosure.

## متطلبات التنفيذ والتحقق اللاحقة

1. تنفيذ طبقة تصفح الأصول المستقلة عن التحليل وحفظ سياق العودة، دون فقد الإذن أو مضاعفة سجلات الهوية.
2. تثبيت وتنفيذ سياسة merge/split/delete للـLoRAs/Datasets/Results/Jobs/marks؛ الرسم يحدد الأثر المقصود، لكنه لا يصلح آلية الدمج الحالية.
3. بناء provenance الصريحة للمصدر/المهمة/الموديل/الـDataset وترحيل المعلوم فقط. النتائج القديمة بلا علاقة لا تكتسب علاقة من الاسم أو التشابه.
4. تأكيد artifact deletion بالنطاق الحقيقي، والحفاظ على تمييز original/crop/private snapshot. قيمة originalPath وحدها ليست إثبات مصدر مختلف: صور التوليد الحالية قد تحفظ output نفسه فيها.
5. كل model/result/job «جاهز/مكتمل» يأتي بعد التحقق والحفظ المحلي، ثم ACK. manual pause وتصحيحات الرفض وقفل التجميع تبقى محترمة.
6. تطبيق encrypted-by-default backup ونطاقه الحقيقي، واستبدال Restore الصريح، وحفظ private results حتى تصدير متعمد.
7. مراجعة السيناريوهات A01–A20 في [عقود المسارات](flows-and-states.md) على الـprototype، ثم اختبارات التطبيق المناسبة وقت التنفيذ. لا يُدعى أنها اختُبرت على جهاز في مرحلة التصميم.

أدلة المصدر للنقاط الحساسة: equipment_library.dart:71–99؛ people_repository.dart:505–618؛ data/db/tables.dart:517–577 وBodyMarks:622؛ studio_repository.dart:196–209؛ domain/jobs/artifact_store.dart:126–135؛ features/backup/backup_screen.dart:37 و267؛ the app/mobile_api/studio_jobs.py:42–44. جميع المسارات تحت mobile/lib إلا مسار الخادم المذكور صراحة.

**المنجز: عقد تصميم يغطي الميزات والمسارات مع إغلاق ملاحظات الـInventory. غير المنجز في هذه المرحلة: إعادة بناء التطبيق، migrations، الاختبارات التشغيلية، أو إصدار جديد.**

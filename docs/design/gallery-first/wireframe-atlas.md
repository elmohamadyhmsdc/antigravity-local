# Wireframe atlas · Gallery first

تاريخ الرسم: 1 نوفمبر 2026. **رسومات بنيوية للمراجعة، وليست تعديلًا للتطبيق.**

عدد الأسطح الأساسية: **68**؛ لكل سطح SVG مستقل قابل للتحرير وPNG بحجم **390 × 844**. توجد حالتان إضافيتان للمقارنة مع أصل ولتأكيد حذف نتيجة تدريب. الصور والوجوه والأسماء والأرقام أمثلة توضيحية ثابتة، وليست بيانات المستخدم.

[المسار الأساسي](wireframes/boards/core-path.png) · [فهرس البيانات](screen-inventory.json) · [مواصفات الرسم](design-system.md) · [Manifest](wireframes/manifest.json)

تُظهر كل لوحة أول إطار مفيد من الشاشة. عبارة Scroll توضح استمرار المحتوى؛ النص الكامل للأقسام والأفعال والحالات موجود تحت كل مدخل أدناه حتى لا تخفي الرسومات المختصرة أي وظيفة. المسار الأساسي ينتهي بتوليد LoRA دون أصل؛ لذلك لا يظهر Before/After في تلك النتيجة. المقارنة مع الأصل لها رسم منفصل.

## لوحات المراجعة

| اللوحة | الأسطح |
|---|---|
| [atlas-01](wireframes/boards/atlas-01.png) | welcome-gallery · media-permission · gallery-photos · gallery-folders · folder-media · gallery-filters |
| [atlas-02](wireframes/boards/atlas-02.png) | photo-viewer · video-viewer · media-details · target-picker · detection-actions · image-preview |
| [atlas-03](wireframes/boards/atlas-03.png) | discover-home · discover-bodies · discover-categories · category-editor · similarity-results · group-poses |
| [atlas-04](wireframes/boards/atlas-04.png) | equipment-browser · equipment-editor · body-areas · people-collection · unassigned-faces · person-media |
| [atlas-05](wireframes/boards/atlas-05.png) | person-identity · person-models · person-actions · face-selection · person-assignment · identity-merge |
| [atlas-06](wireframes/boards/atlas-06.png) | identity-groups · organize-media · training-export · person-marks · mark-editor · quick-review |
| [atlas-07](wireframes/boards/atlas-07.png) | review-hub · album-review · review-comparison · studio-home · reface-target · reface-source |
| [atlas-08](wireframes/boards/atlas-08.png) | reface-options · identity-set-editor · restyle · training-library · dataset-build · dataset-editor |
| [atlas-09](wireframes/boards/atlas-09.png) | lora-training · model-details · lora-generate · activity-center · scan-details · job-details |
| [atlas-10](wireframes/boards/atlas-10.png) | results-gallery · result-viewer · analysis-sources · analysis-settings · analyze-single · library-insights |
| [atlas-11](wireframes/boards/atlas-11.png) | settings-home · pc-connection · pair-qr · pair-manual · background-settings · storage-settings |
| [atlas-12](wireframes/boards/atlas-12.png) | backup-restore · app-lock |

## فهرس الشاشات

| # | الشاشة | السطح | المعاينة |
|---|---|---|---|
| 01 | Your Gallery · `welcome-gallery` | screen | [PNG](wireframes/screens/welcome-gallery.png) · [SVG](wireframes/screens/welcome-gallery.svg) |
| 02 | Photo access · `media-permission` | dialog | [PNG](wireframes/screens/media-permission.png) · [SVG](wireframes/screens/media-permission.svg) |
| 03 | Gallery · `gallery-photos` | screen | [PNG](wireframes/screens/gallery-photos.png) · [SVG](wireframes/screens/gallery-photos.svg) |
| 04 | Folders · `gallery-folders` | tab | [PNG](wireframes/screens/gallery-folders.png) · [SVG](wireframes/screens/gallery-folders.svg) |
| 05 | Folder · `folder-media` | screen | [PNG](wireframes/screens/folder-media.png) · [SVG](wireframes/screens/folder-media.svg) |
| 06 | Filter media · `gallery-filters` | sheet | [PNG](wireframes/screens/gallery-filters.png) · [SVG](wireframes/screens/gallery-filters.svg) |
| 07 | Photo · `photo-viewer` | screen | [PNG](wireframes/screens/photo-viewer.png) · [SVG](wireframes/screens/photo-viewer.svg) |
| 08 | Video · `video-viewer` | screen | [PNG](wireframes/screens/video-viewer.png) · [SVG](wireframes/screens/video-viewer.svg) |
| 09 | Photo details · `media-details` | sheet | [PNG](wireframes/screens/media-details.png) · [SVG](wireframes/screens/media-details.svg) |
| 10 | Choose target · `target-picker` | sheet | [PNG](wireframes/screens/target-picker.png) · [SVG](wireframes/screens/target-picker.svg) |
| 11 | Detection actions · `detection-actions` | sheet | [PNG](wireframes/screens/detection-actions.png) · [SVG](wireframes/screens/detection-actions.svg) |
| 12 | Image preview · `image-preview` | screen | [PNG](wireframes/screens/image-preview.png) · [SVG](wireframes/screens/image-preview.svg) |
| 13 | Discover · `discover-home` | screen | [PNG](wireframes/screens/discover-home.png) · [SVG](wireframes/screens/discover-home.svg) |
| 14 | Bodies · `discover-bodies` | screen | [PNG](wireframes/screens/discover-bodies.png) · [SVG](wireframes/screens/discover-bodies.svg) |
| 15 | Poses and outfits · `discover-categories` | tab | [PNG](wireframes/screens/discover-categories.png) · [SVG](wireframes/screens/discover-categories.svg) |
| 16 | Edit category · `category-editor` | sheet | [PNG](wireframes/screens/category-editor.png) · [SVG](wireframes/screens/category-editor.svg) |
| 17 | Similar results · `similarity-results` | screen | [PNG](wireframes/screens/similarity-results.png) · [SVG](wireframes/screens/similarity-results.svg) |
| 18 | Group poses · `group-poses` | screen | [PNG](wireframes/screens/group-poses.png) · [SVG](wireframes/screens/group-poses.svg) |
| 19 | Equipment · `equipment-browser` | screen | [PNG](wireframes/screens/equipment-browser.png) · [SVG](wireframes/screens/equipment-browser.svg) |
| 20 | Edit equipment · `equipment-editor` | sheet | [PNG](wireframes/screens/equipment-editor.png) · [SVG](wireframes/screens/equipment-editor.svg) |
| 21 | Body area similarity · `body-areas` | screen | [PNG](wireframes/screens/body-areas.png) · [SVG](wireframes/screens/body-areas.svg) |
| 22 | People · `people-collection` | screen | [PNG](wireframes/screens/people-collection.png) · [SVG](wireframes/screens/people-collection.svg) |
| 23 | Unassigned faces · `unassigned-faces` | screen | [PNG](wireframes/screens/unassigned-faces.png) · [SVG](wireframes/screens/unassigned-faces.svg) |
| 24 | Person · `person-media` | screen | [PNG](wireframes/screens/person-media.png) · [SVG](wireframes/screens/person-media.svg) |
| 25 | Identity · `person-identity` | tab | [PNG](wireframes/screens/person-identity.png) · [SVG](wireframes/screens/person-identity.svg) |
| 26 | Models · `person-models` | tab | [PNG](wireframes/screens/person-models.png) · [SVG](wireframes/screens/person-models.svg) |
| 27 | Person actions · `person-actions` | sheet | [PNG](wireframes/screens/person-actions.png) · [SVG](wireframes/screens/person-actions.svg) |
| 28 | Choose faces · `face-selection` | screen | [PNG](wireframes/screens/face-selection.png) · [SVG](wireframes/screens/face-selection.svg) |
| 29 | Who is this? · `person-assignment` | sheet | [PNG](wireframes/screens/person-assignment.png) · [SVG](wireframes/screens/person-assignment.svg) |
| 30 | Merge people · `identity-merge` | screen | [PNG](wireframes/screens/identity-merge.png) · [SVG](wireframes/screens/identity-merge.svg) |
| 31 | Identity groups · `identity-groups` | screen | [PNG](wireframes/screens/identity-groups.png) · [SVG](wireframes/screens/identity-groups.svg) |
| 32 | Organize original files · `organize-media` | screen | [PNG](wireframes/screens/organize-media.png) · [SVG](wireframes/screens/organize-media.svg) |
| 33 | Export training images · `training-export` | dialog | [PNG](wireframes/screens/training-export.png) · [SVG](wireframes/screens/training-export.svg) |
| 34 | Marks and tattoos · `person-marks` | screen | [PNG](wireframes/screens/person-marks.png) · [SVG](wireframes/screens/person-marks.svg) |
| 35 | Mark a tattoo · `mark-editor` | screen | [PNG](wireframes/screens/mark-editor.png) · [SVG](wireframes/screens/mark-editor.svg) |
| 36 | Quick review · `quick-review` | screen | [PNG](wireframes/screens/quick-review.png) · [SVG](wireframes/screens/quick-review.svg) |
| 37 | Review · `review-hub` | screen | [PNG](wireframes/screens/review-hub.png) · [SVG](wireframes/screens/review-hub.svg) |
| 38 | Review person photos · `album-review` | screen | [PNG](wireframes/screens/album-review.png) · [SVG](wireframes/screens/album-review.svg) |
| 39 | Compare references · `review-comparison` | sheet | [PNG](wireframes/screens/review-comparison.png) · [SVG](wireframes/screens/review-comparison.svg) |
| 40 | Studio · `studio-home` | screen | [PNG](wireframes/screens/studio-home.png) · [SVG](wireframes/screens/studio-home.svg) |
| 41 | Reface · Target · `reface-target` | screen | [PNG](wireframes/screens/reface-target.png) · [SVG](wireframes/screens/reface-target.svg) |
| 42 | Reface · Source identity · `reface-source` | screen | [PNG](wireframes/screens/reface-source.png) · [SVG](wireframes/screens/reface-source.svg) |
| 43 | Reface · Review and run · `reface-options` | screen | [PNG](wireframes/screens/reface-options.png) · [SVG](wireframes/screens/reface-options.svg) |
| 44 | Saved identity set · `identity-set-editor` | sheet | [PNG](wireframes/screens/identity-set-editor.png) · [SVG](wireframes/screens/identity-set-editor.svg) |
| 45 | Restyle · `restyle` | screen | [PNG](wireframes/screens/restyle.png) · [SVG](wireframes/screens/restyle.svg) |
| 46 | Datasets and models · `training-library` | screen | [PNG](wireframes/screens/training-library.png) · [SVG](wireframes/screens/training-library.svg) |
| 47 | Build dataset · `dataset-build` | screen | [PNG](wireframes/screens/dataset-build.png) · [SVG](wireframes/screens/dataset-build.svg) |
| 48 | Dataset editor · `dataset-editor` | screen | [PNG](wireframes/screens/dataset-editor.png) · [SVG](wireframes/screens/dataset-editor.svg) |
| 49 | Train LoRA · `lora-training` | screen | [PNG](wireframes/screens/lora-training.png) · [SVG](wireframes/screens/lora-training.svg) |
| 50 | LoRA model · `model-details` | screen | [PNG](wireframes/screens/model-details.png) · [SVG](wireframes/screens/model-details.svg) |
| 51 | Generate with LoRA · `lora-generate` | screen | [PNG](wireframes/screens/lora-generate.png) · [SVG](wireframes/screens/lora-generate.svg) |
| 52 | Activity · `activity-center` | screen | [PNG](wireframes/screens/activity-center.png) · [SVG](wireframes/screens/activity-center.svg) |
| 53 | Analysis progress · `scan-details` | screen | [PNG](wireframes/screens/scan-details.png) · [SVG](wireframes/screens/scan-details.svg) |
| 54 | Job details · `job-details` | screen | [PNG](wireframes/screens/job-details.png) · [SVG](wireframes/screens/job-details.svg) |
| 55 | Private results · `results-gallery` | screen | [PNG](wireframes/screens/results-gallery.png) · [SVG](wireframes/screens/results-gallery.svg) |
| 56 | Result · `result-viewer` | screen | [PNG](wireframes/screens/result-viewer.png) · [SVG](wireframes/screens/result-viewer.svg) |
| 57 | Analysis sources · `analysis-sources` | screen | [PNG](wireframes/screens/analysis-sources.png) · [SVG](wireframes/screens/analysis-sources.svg) |
| 58 | Analysis settings · `analysis-settings` | screen | [PNG](wireframes/screens/analysis-settings.png) · [SVG](wireframes/screens/analysis-settings.svg) |
| 59 | Analyze a photo · `analyze-single` | screen | [PNG](wireframes/screens/analyze-single.png) · [SVG](wireframes/screens/analyze-single.svg) |
| 60 | Library insights · `library-insights` | screen | [PNG](wireframes/screens/library-insights.png) · [SVG](wireframes/screens/library-insights.svg) |
| 61 | Settings · `settings-home` | screen | [PNG](wireframes/screens/settings-home.png) · [SVG](wireframes/screens/settings-home.svg) |
| 62 | PC connection · `pc-connection` | screen | [PNG](wireframes/screens/pc-connection.png) · [SVG](wireframes/screens/pc-connection.svg) |
| 63 | Scan pairing code · `pair-qr` | screen | [PNG](wireframes/screens/pair-qr.png) · [SVG](wireframes/screens/pair-qr.svg) |
| 64 | Pair manually · `pair-manual` | screen | [PNG](wireframes/screens/pair-manual.png) · [SVG](wireframes/screens/pair-manual.svg) |
| 65 | Background activity · `background-settings` | screen | [PNG](wireframes/screens/background-settings.png) · [SVG](wireframes/screens/background-settings.svg) |
| 66 | Storage · `storage-settings` | screen | [PNG](wireframes/screens/storage-settings.png) · [SVG](wireframes/screens/storage-settings.svg) |
| 67 | Backup and restore · `backup-restore` | screen | [PNG](wireframes/screens/backup-restore.png) · [SVG](wireframes/screens/backup-restore.svg) |
| 68 | App lock · `app-lock` | dialog | [PNG](wireframes/screens/app-lock.png) · [SVG](wireframes/screens/app-lock.svg) |

## حالات إضافية

- [نتيجة تعديل مع Before/After](wireframes/screens/result-source-comparison.png) · [SVG](wireframes/screens/result-source-comparison.svg): تُعرض المقارنة فقط مع وجود مصدر متاح.
- [تأكيد حذف نتيجة تدريب](wireframes/screens/result-delete-confirmation.png) · [SVG](wireframes/screens/result-delete-confirmation.svg): مثال واضح يذكر نتيجة التدريب والموديل والملفات المتأثرة قبل التأكيد، دون مصطلحات معرّفات داخلية.

## محتوى كل سطح وحالاته

`origin` يعني العودة لنقطة الدخول مع الصورة والتوقيت والفلتر والتحديد والتمرير واللوحة الحالية. الجذور الأربعة وحدها تحمل التنقل الرئيسي؛ التفاصيل والأدوات لا تضيف NavigationBar ثانية.

### 01 · Your Gallery · welcome-gallery

تعريف قصير يوصّل المستخدم لصور الهاتف قبل ربط الكمبيوتر.

النوع: **screen**. العائلة: entry. المدخل الرئيسي: `Root`. الرجوع: `gallery-photos`.

الفعل الرئيسي: **Open gallery**.

[PNG](wireframes/screens/welcome-gallery.png) · [SVG قابل للتحرير](wireframes/screens/welcome-gallery.svg)

الأقسام بالترتيب:

- **Your photos first** (preview): Browse photos and folders؛ Find people in your library؛ Create with linked tools.

أفعال ثانوية: Photo access information.

الحالات المطلوب احترامها: First launch؛ Returning user skips welcome.

### 02 · Photo access · media-permission

طلب إذن الصور وتوضيح الصور المحدودة أو المرفوضة دون ربط الكمبيوتر.

النوع: **dialog**. العائلة: entry. المدخل الرئيسي: `welcome-gallery`. الرجوع: `gallery-photos`.

الفعل الرئيسي: **Allow photo access**.

[PNG](wireframes/screens/media-permission.png) · [SVG قابل للتحرير](wireframes/screens/media-permission.svg)

الأقسام بالترتيب:

- **Choose what to share** (summary): All permitted photos and videos؛ Selected photos on supported Android versions.

أفعال ثانوية: Continue with limited access؛ Open Android settings.

الحالات المطلوب احترامها: Not requested؛ Limited access؛ Access denied؛ No permitted media.

### 03 · Gallery · gallery-photos

بداية التطبيق تعرض كل الصور والفيديوهات المسموح بها مستقلة عن الفحص والكمبيوتر.

النوع: **screen**. العائلة: gallery. المدخل الرئيسي: `Root`. الرجوع: `origin`.

الفعل الرئيسي: **Open photo**.

[PNG](wireframes/screens/gallery-photos.png) · [SVG قابل للتحرير](wireframes/screens/gallery-photos.svg)

الأقسام بالترتيب:

- **Gallery view** (tabs): Photos؛ Folders.
- **Recent media** (grid): Date groups؛ Photo thumbnails؛ Video duration؛ Analysis status only when relevant.

أفعال ثانوية: Filters؛ Activity؛ Settings؛ Switch to folders.

الحالات المطلوب احترامها: Loading device media؛ No photos؛ Limited access؛ Photos not analyzed؛ Offline browsing؛ Missing thumbnail.

### 04 · Folders · gallery-folders

عرض مجلدات الهاتف الحقيقية بأغلفتها وأعدادها دون تشغيل الفحص بمجرد فتحها.

النوع: **tab**. العائلة: gallery. المدخل الرئيسي: `gallery-photos`. الرجوع: `gallery-photos`.

الفعل الرئيسي: **Open folder**.

[PNG](wireframes/screens/gallery-folders.png) · [SVG قابل للتحرير](wireframes/screens/gallery-folders.svg)

الأقسام بالترتيب:

- **Gallery view** (tabs): Photos؛ Folders.
- **Device folders** (grid): Folder cover؛ Folder name؛ Media count.

أفعال ثانوية: Back to photos؛ Manage analysis sources؛ Private results shortcut is labelled in-app.

الحالات المطلوب احترامها: Loading folders؛ No accessible folders؛ Limited access.

### 05 · Folder · folder-media

عرض وسائط المجلد مع الاحتفاظ بالمكان عند الرجوع من الصورة.

النوع: **screen**. العائلة: gallery. المدخل الرئيسي: `gallery-folders`. الرجوع: `gallery-folders`.

الفعل الرئيسي: **Open photo**.

[PNG](wireframes/screens/folder-media.png) · [SVG قابل للتحرير](wireframes/screens/folder-media.svg)

الأقسام بالترتيب:

- **Folder context** (summary): Current folder name؛ Media count.
- **Photos and videos** (grid): Date groups؛ Photo thumbnails؛ Video duration.

أفعال ثانوية: Analyze this folder؛ Folder analysis options؛ Filters.

الحالات المطلوب احترامها: Empty folder؛ Limited access؛ Original moved or removed؛ Offline browsing.

### 06 · Filter media · gallery-filters

تصفية الصور بالأنواع وحالة التحليل والأشخاص بالوظائف المدعومة فقط.

النوع: **sheet**. العائلة: gallery. المدخل الرئيسي: `gallery-photos`. الرجوع: `origin`.

الفعل الرئيسي: **Show matching media**.

[PNG](wireframes/screens/gallery-filters.png) · [SVG قابل للتحرير](wireframes/screens/gallery-filters.svg)

الأقسام بالترتيب:

- **Media filters** (fields): All / Photos / Videos؛ All / Analyzed / Not analyzed / Failed؛ Has faces؛ Choose a person.

أفعال ثانوية: Clear filters.

الحالات المطلوب احترامها: Default filters؛ Active filters؛ No matching media؛ Person filter needs analyzed data.

### 07 · Photo · photo-viewer

الصورة تملأ الشاشة والسحب لأعلى أو زر التفاصيل يفتح الأشخاص والأدوات.

النوع: **screen**. العائلة: viewer. المدخل الرئيسي: `gallery-photos`. الرجوع: `origin`.

الفعل الرئيسي: **Open details**.

[PNG](wireframes/screens/photo-viewer.png) · [SVG قابل للتحرير](wireframes/screens/photo-viewer.svg)

الأقسام بالترتيب:

- **Current photo** (preview): Fit entire image؛ Pinch and double-tap zoom؛ Swipe horizontally within current collection.
- **Visible controls** (list): Back؛ Details؛ Tools؛ Detection overlays toggle.

أفعال ثانوية: Google Lens؛ Show detections؛ Hide controls؛ Expand original.

الحالات المطلوب احترامها: Original available؛ Thumbnail fallback clearly labelled؛ Original missing؛ Not analyzed؛ No detections؛ Zoomed image blocks paging gesture.

### 08 · Video · video-viewer

نفس عارض الجاليري مع التشغيل والأشخاص في الإطار الحالي وتوقيت اللقطات.

النوع: **screen**. العائلة: viewer. المدخل الرئيسي: `gallery-photos`. الرجوع: `origin`.

الفعل الرئيسي: **Play or pause**.

[PNG](wireframes/screens/video-viewer.png) · [SVG قابل للتحرير](wireframes/screens/video-viewer.svg)

الأقسام بالترتيب:

- **Current video** (preview): Playback controls؛ Seek timeline؛ Current time and duration.
- **Analysis context** (list): People in current analyzed frame؛ All people detected in video؛ Open referenced timestamp.

أفعال ثانوية: Details؛ Tools؛ Show detections؛ Open Reface.

الحالات المطلوب احترامها: Playing؛ Paused؛ Seeking؛ Partially analyzed؛ Original missing؛ Photo-only group and equipment tools unavailable.

### 09 · Photo details · media-details

لوحة السحب لأعلى تربط الأشخاص المختارين بموديلاتهم والإجراءات ونتائج الصورة.

النوع: **sheet**. العائلة: viewer. المدخل الرئيسي: `photo-viewer`. الرجوع: `origin`.

الفعل الرئيسي: **Open person**.

[PNG](wireframes/screens/media-details.png) · [SVG قابل للتحرير](wireframes/screens/media-details.svg)

الأقسام بالترتيب:

- **People here** (list): Known people open their profiles؛ Unknown person: Who is this?؛ Separate reassignment control.
- **Selected person** (summary): Selected identity؛ Linked trained LoRAs؛ Training status is not a ready model.
- **Tools and related work** (list): Reface؛ Restyle؛ Use in dataset؛ Find similar؛ Related results when explicitly linked.
- **File and analysis** (summary): Date and folder؛ Analysis status؛ Advanced file details.

أفعال ثانوية: Choose another person؛ Analyze photo؛ Detection corrections؛ Google Lens.

الحالات المطلوب احترامها: No analysis؛ No people found؛ Unknown people؛ Multiple people require a target؛ No linked model؛ Unlinked older result؛ Offline saved details.

### 10 · Choose target · target-picker

اختيار الشخص أو الوجه أو الجسم المقصود داخل الصورة قبل أي أداة تعتمد عليه.

النوع: **sheet**. العائلة: viewer. المدخل الرئيسي: `media-details`. الرجوع: `origin`.

الفعل الرئيسي: **Use selected target**.

[PNG](wireframes/screens/target-picker.png) · [SVG قابل للتحرير](wireframes/screens/target-picker.svg)

الأقسام بالترتيب:

- **Current media** (preview): Selected face or body highlight.
- **Detected targets** (list): Face and body crops؛ Known name or Unknown؛ Timestamp for video target.

أفعال ثانوية: Analyze missing detections؛ Cancel.

الحالات المطلوب احترامها: Single target؛ Multiple targets؛ No targets؛ Body-only appearance؛ Video frame context.

### 11 · Detection actions · detection-actions

تصحيح ظهور محدد دون الخلط بين حذف الاكتشاف وحذف الملف الأصلي.

النوع: **sheet**. العائلة: viewer. المدخل الرئيسي: `media-details`. الرجوع: `origin`.

الفعل الرئيسي: **Open person or assign**.

[PNG](wireframes/screens/detection-actions.png) · [SVG قابل للتحرير](wireframes/screens/detection-actions.svg)

الأقسام بالترتيب:

- **Selected detection** (preview): Crop with original-media expansion.
- **Identity correction** (list): Open person؛ Assign / Create person؛ Reject this identity؛ Change Person / Character؛ Ignore false detection؛ Delete detection.
- **Body tools** (list): Similar pose / Colours / Body area؛ Name pose / Outfit؛ Mark tattoo؛ Group pose / Equipment on photos.

أفعال ثانوية: Redetect photo؛ Open original؛ Google Lens.

الحالات المطلوب احترامها: Face detection؛ Body detection؛ Known identity؛ Unknown identity؛ Video disables photo-only tools؛ Confirmation names the affected record.

### 12 · Image preview · image-preview

عارض موحد لتوسيع الأصل أو القصاصة مع الحفاظ على سلوك الاختيار في الشاشة السابقة.

النوع: **screen**. العائلة: viewer. المدخل الرئيسي: `photo-viewer`. الرجوع: `origin`.

الفعل الرئيسي: **View image**.

[PNG](wireframes/screens/image-preview.png) · [SVG قابل للتحرير](wireframes/screens/image-preview.svg)

الأقسام بالترتيب:

- **Image** (preview): Full image fit؛ Pinch / Pan / Double-tap zoom؛ Original / Crop switch when available.

أفعال ثانوية: Reset zoom؛ Google Lens؛ Back.

الحالات المطلوب احترامها: Original available؛ Crop only؛ Original unavailable؛ Decode error؛ Lens unavailable.

### 13 · Discover · discover-home

مدخل بصري لميزات الأجسام والوضعيات والملابس والمجموعات والمعدات والعلامات الموجودة.

النوع: **screen**. العائلة: discover. المدخل الرئيسي: `Root`. الرجوع: `origin`.

الفعل الرئيسي: **Choose discovery type**.

[PNG](wireframes/screens/discover-home.png) · [SVG قابل للتحرير](wireframes/screens/discover-home.svg)

الأقسام بالترتيب:

- **Browse visually** (grid): Bodies and poses؛ Outfits and colours؛ Group poses؛ Equipment؛ Saved person marks.
- **Context** (list): Choose a saved example or category؛ Results retain the target crop and original.

أفعال ثانوية: Activity؛ Open body area tools.

الحالات المطلوب احترامها: No analyzed bodies؛ Offline saved categories؛ Required analysis unavailable.

### 14 · Bodies · discover-bodies

تصفح الأجسام وقصر النتائج على شخص عند الدخول من ملفه.

النوع: **screen**. العائلة: discover. المدخل الرئيسي: `discover-home`. الرجوع: `discover-home`.

الفعل الرئيسي: **Open body**.

[PNG](wireframes/screens/discover-bodies.png) · [SVG قابل للتحرير](wireframes/screens/discover-bodies.svg)

الأقسام بالترتيب:

- **Browse** (tabs): All؛ Poses؛ Outfits؛ Group poses؛ Equipment.
- **Refine results** (fields): Supported pose tags؛ Outfit colours؛ Person scope.
- **Body crops** (grid): Target crop؛ Identity when known؛ Open original photo.

أفعال ثانوية: Find similar pose؛ Find similar colours؛ Name pose or outfit؛ Experimental body areas.

الحالات المطلوب احترامها: Loading؛ No bodies؛ No matching filters؛ Person-scoped؛ Feature not analyzed.

### 15 · Poses and outfits · discover-categories

عرض فئات الوضعيات والملابس وأمثلتها المحفوظة مع الوصول للتعديل.

النوع: **tab**. العائلة: discover. المدخل الرئيسي: `discover-bodies`. الرجوع: `discover-bodies`.

الفعل الرئيسي: **Open category**.

[PNG](wireframes/screens/discover-categories.png) · [SVG قابل للتحرير](wireframes/screens/discover-categories.svg)

الأقسام بالترتيب:

- **Saved categories** (tabs): Poses؛ Outfits.
- **Examples** (grid): Illustrated pose choices؛ Reference crops؛ Category name and count.

أفعال ثانوية: Edit saved category؛ Choose a reference body؛ Clear filters.

الحالات المطلوب احترامها: Pose mode؛ Outfit mode؛ No saved categories؛ No matching bodies.

### 16 · Edit category · category-editor

تسمية وضعية أو ملابس من مثال مع مراجعة الأعضاء وتعديلهم قبل الحفظ.

النوع: **sheet**. العائلة: discover. المدخل الرئيسي: `discover-categories`. الرجوع: `origin`.

الفعل الرئيسي: **Save category**.

[PNG](wireframes/screens/category-editor.png) · [SVG قابل للتحرير](wireframes/screens/category-editor.svg)

الأقسام بالترتيب:

- **Reference** (preview): Selected body crop؛ Open original.
- **Category** (fields): Pose or outfit name؛ Current person scope.
- **Included examples** (grid): Preview matches؛ Untick unsuitable examples.

أفعال ثانوية: Cancel؛ Delete saved category.

الحالات المطلوب احترامها: New pose؛ New outfit؛ Editing existing category؛ No selected examples.

### 17 · Similar results · similarity-results

نتائج التشابه تحتفظ بالجسم أو العلامة المستهدفة ومسار الرجوع للصورة.

النوع: **screen**. العائلة: discover. المدخل الرئيسي: `discover-home`. الرجوع: `origin`.

الفعل الرئيسي: **Open original media**.

[PNG](wireframes/screens/similarity-results.png) · [SVG قابل للتحرير](wireframes/screens/similarity-results.svg)

الأقسام بالترتيب:

- **Search reference** (preview): Pose / Outfit colour / Body area / Mark / Group example.
- **Current criteria** (summary): Supported comparison type؛ Person scope if selected.
- **Matches** (grid): Target crops or full group photo؛ Open original؛ Identity if known.

أفعال ثانوية: Change reference؛ Clear criteria؛ Review identity for a mark match.

الحالات المطلوب احترامها: Loading؛ No matches؛ Missing reference؛ Offline saved results؛ Mark results show It is them / Not them؛ No automatic identity assignment.

### 18 · Group poses · group-poses

اختيار أمثلة جماعية وفلاتر الهندسة والحركة والمعدات للصور فقط.

النوع: **screen**. العائلة: discover. المدخل الرئيسي: `discover-home`. الرجوع: `discover-home`.

الفعل الرئيسي: **Show matching photos**.

[PNG](wireframes/screens/group-poses.png) · [SVG قابل للتحرير](wireframes/screens/group-poses.svg)

الأقسام بالترتيب:

- **Visual group examples** (grid): Two to six people؛ Named group actions؛ Saved group reference.
- **Match criteria** (fields): Whole-group geometry؛ Detected members count؛ Equipment filter.
- **Comparison scope** (summary): All detected group members are compared؛ Crowd subset selection is unavailable.

أفعال ثانوية: Use current group photo؛ Open matching original.

الحالات المطلوب احترامها: No group photos؛ No matches؛ Photo-only feature؛ Incomplete detections affect results.

### 19 · Equipment · equipment-browser

عرض المعدات المرصودة واليدوية والبحث عن صورها مع توضيح المالك المشترك أو غير المؤكد.

النوع: **screen**. العائلة: discover. المدخل الرئيسي: `discover-home`. الرجوع: `discover-home`.

الفعل الرئيسي: **Open equipment matches**.

[PNG](wireframes/screens/equipment-browser.png) · [SVG قابل للتحرير](wireframes/screens/equipment-browser.svg)

الأقسام بالترتيب:

- **Equipment filters** (fields): Equipment label؛ Person scope / Shared owner.
- **Detected equipment** (grid): Object crop؛ Label؛ Owner or Shared.

أفعال ثانوية: Edit label or owner؛ Reject detection؛ Add equipment manually؛ Analyze equipment in a photo.

الحالات المطلوب احترامها: Not analyzed؛ Loading؛ No equipment؛ Unclear owner remains shared؛ Photo-only feature.

### 20 · Edit equipment · equipment-editor

تصحيح تسمية المعدة ومالكها أو إضافة تسمية يدوية بلا رسم منطقة جديدة.

النوع: **sheet**. العائلة: discover. المدخل الرئيسي: `equipment-browser`. الرجوع: `origin`.

الفعل الرئيسي: **Save correction**.

[PNG](wireframes/screens/equipment-editor.png) · [SVG قابل للتحرير](wireframes/screens/equipment-editor.svg)

الأقسام بالترتيب:

- **Photo context** (preview): Current photo؛ Existing equipment detection when available.
- **Equipment** (fields): Label؛ Owner person / Shared.
- **Manual addition** (summary): Saves a label and owner without drawing a new region.

أفعال ثانوية: Reject automatic detection؛ Cancel.

الحالات المطلوب احترامها: Edit detection؛ Manual addition؛ Ambiguous owner؛ Analysis unavailable.

### 21 · Body area similarity · body-areas

بحث مشابه لمناطق الجسم مع إبقاء التجميع التجريبي اختياريًا ومغلقًا افتراضيًا.

النوع: **screen**. العائلة: discover. المدخل الرئيسي: `discover-bodies`. الرجوع: `discover-bodies`.

الفعل الرئيسي: **Find similar photos**.

[PNG](wireframes/screens/body-areas.png) · [SVG قابل للتحرير](wireframes/screens/body-areas.svg)

الأقسام بالترتيب:

- **Body areas** (tabs): Chest؛ Lower body.
- **Reference body** (preview): Choose an available body crop.
- **Experimental groups** (list): Group body areas: off by default؛ Sample crops and assigned person only when enabled؛ Assign unclaimed bodies after explicit confirmation.

أفعال ثانوية: Choose reference؛ Toggle experimental groups؛ Review bridge suggestions.

الحالات المطلوب احترامها: Feature not analyzed؛ No matches؛ Experimental grouping off؛ Experimental grouping on؛ Existing rejections remain respected.

### 22 · People · people-collection

مكتبة الأشخاص والشخصيات مع البحث والترتيب والمجموعات والتحديد الجماعي الحالي.

النوع: **screen**. العائلة: people. المدخل الرئيسي: `Root`. الرجوع: `origin`.

الفعل الرئيسي: **Open person**.

[PNG](wireframes/screens/people-collection.png) · [SVG قابل للتحرير](wireframes/screens/people-collection.svg)

الأقسام بالترتيب:

- **Collection** (tabs): People؛ Characters.
- **Find people** (fields): Name or identity group search؛ Most faces / Name / Newest؛ All / Favourites / Pinned / Hidden؛ Identity group filter.
- **Identities** (grid): Cover image؛ Name؛ Face count؛ Review prompt when pending.

أفعال ثانوية: Unassigned faces؛ Review؛ Manage identity groups؛ Select / Select all / Invert؛ Collection tools.

الحالات المطلوب احترامها: People mode؛ Characters mode؛ Empty library؛ No matching people؛ Hidden filter active؛ Selection mode؛ Search restored after collection switch.

### 23 · Unassigned faces · unassigned-faces

تجميع الوجوه غير المنسوبة وتعيينها أو إنشاء أشخاص من تحديد متعدد.

النوع: **screen**. العائلة: people. المدخل الرئيسي: `people-collection`. الرجوع: `people-collection`.

الفعل الرئيسي: **Assign selected faces**.

[PNG](wireframes/screens/unassigned-faces.png) · [SVG قابل للتحرير](wireframes/screens/unassigned-faces.svg)

الأقسام بالترتيب:

- **Unassigned faces** (grid): Selectable face crops؛ Original expansion؛ Real people or characters context.

أفعال ثانوية: Create person؛ Ignore false faces؛ Convert Person / Character؛ Select all / Invert.

الحالات المطلوب احترامها: No unassigned faces؛ Selection mode؛ Unknown character faces؛ Source missing.

### 24 · Person · person-media

ملف الشخص يبدأ بصوره وفيديوهاته الأصلية بدل شبكة الوجوه.

النوع: **screen**. العائلة: person. المدخل الرئيسي: `people-collection`. الرجوع: `origin`.

الفعل الرئيسي: **Open photo**.

[PNG](wireframes/screens/person-media.png) · [SVG قابل للتحرير](wireframes/screens/person-media.svg)

الأقسام بالترتيب:

- **Person** (summary): Cover image and name؛ Identity group؛ Review prompt when pending.
- **Person** (tabs): Media؛ Identity؛ Models.
- **Photos and videos** (grid): Original media containing this person؛ Photo / Video filters.

أفعال ثانوية: Use in Reface for real people؛ Person actions؛ Review suggestions.

الحالات المطلوب احترامها: Named person؛ Unnamed person؛ Character profile؛ No linked originals؛ Offline browsing؛ Original missing.

### 25 · Identity · person-identity

مراجع الوجوه والأجسام والعلامات والتصحيحات الخاصة بالشخص مع توضيح أنها ليست موديلات تدريب.

النوع: **tab**. العائلة: person. المدخل الرئيسي: `person-media`. الرجوع: `person-media`.

الفعل الرئيسي: **Open faces**.

[PNG](wireframes/screens/person-identity.png) · [SVG قابل للتحرير](wireframes/screens/person-identity.svg)

الأقسام بالترتيب:

- **Identity references** (list): Faces؛ Bodies؛ Saved identity sets؛ Marks and tattoos.
- **Face crops** (grid): Current cover؛ Quality-aware face previews؛ Open original at timestamp.

أفعال ثانوية: Add or split faces؛ Choose cover؛ Review suggestions؛ Face selection actions؛ Redetect person media.

الحالات المطلوب احترامها: No faces؛ Character has restricted Studio source tools؛ Identity set empty؛ Source unavailable.

### 26 · Models · person-models

عرض موديلات LoRA وبيانات التدريب التابعة للشخص والمهام التي لم تصبح موديلًا جاهزًا.

النوع: **tab**. العائلة: person. المدخل الرئيسي: `person-media`. الرجوع: `person-media`.

الفعل الرئيسي: **Open model**.

[PNG](wireframes/screens/person-models.png) · [SVG قابل للتحرير](wireframes/screens/person-models.svg)

الأقسام بالترتيب:

- **Trained LoRAs** (list): Saved model name or trigger word؛ Local ready state؛ Generate / Share / Build identity.
- **Datasets and training** (list): Related datasets؛ Active or failed training jobs؛ Prepare new dataset.

أفعال ثانوية: Build dataset؛ Open dataset؛ View results with known person link.

الحالات المطلوب احترامها: No models؛ No datasets؛ Training running؛ Training paused or failed؛ Ready model available؛ Unknown training provenance is labelled.

### 27 · Person actions · person-actions

كل عمليات الشخص المخفية حاليًا مرتبة حسب التنظيم والتصحيح والتصدير دون فقد أي إجراء.

النوع: **sheet**. العائلة: person. المدخل الرئيسي: `person-media`. الرجوع: `origin`.

الفعل الرئيسي: **Choose action**.

[PNG](wireframes/screens/person-actions.png) · [SVG قابل للتحرير](wireframes/screens/person-actions.svg)

الأقسام بالترتيب:

- **Frequent actions** (list): Rename؛ Add faces؛ Choose cover / Best cover؛ Merge؛ Review suggestions.
- **Organize** (list): Favourite / Pin / Hide؛ Assign identity group؛ Organize original files؛ Lock automatic grouping؛ Convert Person / Character.
- **Correct and export** (list): Split faces؛ Mark two identities distinct؛ Redetect؛ Marks / Bodies؛ Share crops / Training export؛ Details / Delete identity.

أفعال ثانوية: Close.

الحالات المطلوب احترامها: Single person؛ Multiple selected people؛ Characters restrict unsupported actions؛ Destructive action states its scope.

### 28 · Choose faces · face-selection

اختيار الوجوه لإضافة أو فصل أو تصحيح أو تصدير الهوية مع بقاء الأصل قابلًا للفتح.

النوع: **screen**. العائلة: person. المدخل الرئيسي: `person-identity`. الرجوع: `origin`.

الفعل الرئيسي: **Apply selected action**.

[PNG](wireframes/screens/face-selection.png) · [SVG قابل للتحرير](wireframes/screens/face-selection.svg)

الأقسام بالترتيب:

- **Selection purpose** (summary): Add / Split / Choose cover / Saved identity set؛ Selected count.
- **Face references** (grid): Selectable crops؛ Open original؛ Face quality details.

أفعال ثانوية: Select all / Invert؛ Assign / Create person؛ Reject identity؛ Remove assignment؛ Hide / Show؛ Ignore / Delete detection؛ Save / Share crop؛ Use in Reface for real faces؛ Find similar faces؛ Detection details.

الحالات المطلوب احترامها: Single selection؛ Multiple selection؛ No selected faces؛ Original missing؛ Person / Character context.

### 29 · Who is this? · person-assignment

تعيين ظهور أو مجموعة وجوه لشخص موجود أو إنشاء هوية جديدة دون استنتاج تلقائي.

النوع: **sheet**. العائلة: person. المدخل الرئيسي: `media-details`. الرجوع: `origin`.

الفعل الرئيسي: **Assign person**.

[PNG](wireframes/screens/person-assignment.png) · [SVG قابل للتحرير](wireframes/screens/person-assignment.svg)

الأقسام بالترتيب:

- **Selected appearance** (preview): Face or body crop؛ Original preview.
- **Choose identity** (fields): Search current collection؛ Existing identity؛ New identity name for face-based creation.

أفعال ثانوية: Create person from face؛ Keep unknown؛ Cancel.

الحالات المطلوب احترامها: Existing identity selected؛ Creating new person؛ Body links to existing identity؛ Characters collection؛ No matching identity.

### 30 · Merge people · identity-merge

مقارنة هويتين قبل الدمج مع دعم تمييزهما كشخصين مختلفين.

النوع: **screen**. العائلة: person. المدخل الرئيسي: `person-media`. الرجوع: `origin`.

الفعل الرئيسي: **Choose survivor and confirm merge**.

[PNG](wireframes/screens/identity-merge.png) · [SVG قابل للتحرير](wireframes/screens/identity-merge.svg)

الأقسام بالترتيب:

- **Compare identities** (preview): Identity A cover and name؛ Identity B cover and name.
- **Reference evidence** (grid): Faces from both identities؛ Open original media.
- **Decision** (summary): Merge matching identities؛ Keep separate and mark distinct.
- **Merge impact** (summary): Choose surviving identity؛ Review affected LoRAs, datasets, results and marks؛ Confirm how each linked item is kept؛ Original files stay in place.

أفعال ثانوية: Choose another identity؛ Mark distinct؛ Cancel.

الحالات المطلوب احترامها: Merge candidate؛ No suitable second identity؛ Confirmation required؛ No promise of universal undo؛ Impact review required for linked artifacts.

### 31 · Identity groups · identity-groups

إدارة مجموعات الأشخاص داخل التطبيق مع فصلها عن المجلدات الفعلية.

النوع: **screen**. العائلة: people. المدخل الرئيسي: `people-collection`. الرجوع: `people-collection`.

الفعل الرئيسي: **Open group**.

[PNG](wireframes/screens/identity-groups.png) · [SVG قابل للتحرير](wireframes/screens/identity-groups.svg)

الأقسام بالترتيب:

- **Groups** (list): Group name؛ Member count؛ People / Characters context.
- **Group actions** (fields): Create or rename group؛ Assign selected identities؛ Remove group membership.

أفعال ثانوية: View ungrouped identities؛ Open member media؛ Delete group.

الحالات المطلوب احترامها: No groups؛ Empty group؛ Filtered collection؛ Deleting a group does not delete originals.

### 32 · Organize original files · organize-media

معاينة خطة نقل الأصول إلى فولدرات الأشخاص ثم تسوية النتيجة بقرار صريح.

النوع: **screen**. العائلة: person. المدخل الرئيسي: `person-actions`. الرجوع: `origin`.

الفعل الرئيسي: **Review and apply move plan**.

[PNG](wireframes/screens/organize-media.png) · [SVG قابل للتحرير](wireframes/screens/organize-media.svg)

الأقسام بالترتيب:

- **Selected identities** (summary): People included؛ Destination folder strategy.
- **Move preview** (list): Original file؛ Proposed destination؛ Conflicts or missing files.
- **Operation result** (list): Completed moves؛ Skipped or failed moves؛ Reconcile moved originals.

أفعال ثانوية: Cancel plan؛ Review failures؛ Refresh media links.

الحالات المطلوب احترامها: Preparing plan؛ Preview ready؛ File conflict؛ Permission unavailable؛ Partial completion؛ No files eligible.

### 33 · Export training images · training-export

تصدير صور تدريب الشخص بالخيارات الحالية دون تشغيل تدريب تلقائي.

النوع: **dialog**. العائلة: person. المدخل الرئيسي: `person-actions`. الرجوع: `origin`.

الفعل الرئيسي: **Export selected images**.

[PNG](wireframes/screens/training-export.png) · [SVG قابل للتحرير](wireframes/screens/training-export.svg)

الأقسام بالترتيب:

- **Export scope** (summary): Current person؛ Eligible faces and bodies.
- **Export options** (fields): Include faces؛ Include bodies؛ Face output size؛ Body long-side size؛ Maximum samples per video.

أفعال ثانوية: Stop export؛ Share completed ZIP؛ Close without stopping export.

الحالات المطلوب احترامها: Planning؛ Exporting؛ Packing ZIP؛ Nothing eligible؛ Missing or small samples skipped؛ Completed؛ Cancelled؛ Failed.

### 34 · Marks and tattoos · person-marks

إدارة العلامات المحفوظة للشخص والبحث عن ظهورها في صور أخرى ومراجعة التطابقات.

النوع: **screen**. العائلة: person. المدخل الرئيسي: `person-identity`. الرجوع: `person-identity`.

الفعل الرئيسي: **Search other photos**.

[PNG](wireframes/screens/person-marks.png) · [SVG قابل للتحرير](wireframes/screens/person-marks.svg)

الأقسام بالترتيب:

- **Saved marks** (grid): Mark patch؛ Body segment؛ Optional label.
- **Match decisions** (list): Strong / Possible matches؛ It is them / Not them؛ Open original.

أفعال ثانوية: Add mark from a body؛ Delete saved mark؛ Expand original or patch.

الحالات المطلوب احترامها: No saved marks؛ Searching؛ No matches؛ Possible matches only؛ Source patch missing.

### 35 · Mark a tattoo · mark-editor

تحديد مستطيل العلامة على الجسم الأصلي واختيار الجزء وحفظها للشخص.

النوع: **screen**. العائلة: person. المدخل الرئيسي: `detection-actions`. الرجوع: `origin`.

الفعل الرئيسي: **Save mark**.

[PNG](wireframes/screens/mark-editor.png) · [SVG قابل للتحرير](wireframes/screens/mark-editor.svg)

الأقسام بالترتيب:

- **Mark region** (preview): Original body image؛ Draw or adjust rectangle.
- **Mark details** (fields): Body segment؛ Optional label؛ Assigned person.

أفعال ثانوية: Reset rectangle؛ Cancel؛ Open full image.

الحالات المطلوب احترامها: No region selected؛ Region too small؛ Body identity needed؛ Original unavailable؛ Ready to save.

### 36 · Quick review · quick-review

مراجعة اقتراح واحد في كل مرة مع نعم ولا وغير متأكد دون فقد طرق المراجعة الحالية.

النوع: **screen**. العائلة: review. المدخل الرئيسي: `people-collection`. الرجوع: `origin`.

الفعل الرئيسي: **Answer review question**.

[PNG](wireframes/screens/quick-review.png) · [SVG قابل للتحرير](wireframes/screens/quick-review.svg)

الأقسام بالترتيب:

- **Evidence** (preview): Highlighted original or crops؛ Reference identity images.
- **Question** (summary): Match / Group / Duplicate / Body link؛ Reason including outfit, mark or experimental cluster.
- **Answers** (list): Yes؛ No؛ Not sure؛ Choose or name person for a group.

أفعال ثانوية: Open original؛ Expand references؛ Advanced review؛ Compare identities.

الحالات المطلوب احترامها: Pending question؛ No pending reviews؛ Saved offline evidence؛ Not sure snoozes until new evidence؛ Character review mode.

### 37 · Review · review-hub

القوائم المتقدمة للمطابقات والمجموعات والتكرارات وروابط الأجسام والملابس مع التأكيدات الجماعية.

النوع: **screen**. العائلة: review. المدخل الرئيسي: `people-collection`. الرجوع: `people-collection`.

الفعل الرئيسي: **Open review item**.

[PNG](wireframes/screens/review-hub.png) · [SVG قابل للتحرير](wireframes/screens/review-hub.svg)

الأقسام بالترتيب:

- **Review queues** (tabs): Matches؛ Groups؛ Duplicates؛ Body and outfit links.
- **Pending evidence** (list): Target and suggested identity؛ Reference photos؛ Accept / Reject / Assign.
- **Bulk actions** (summary): Accept all applicable matches؛ Create all eligible groups؛ Accept all applicable body links.

أفعال ثانوية: Quick review؛ Open reference comparison؛ Compact video faces؛ Confirm bulk action.

الحالات المطلوب احترامها: No pending items؛ Offline stored plan؛ Large queue؛ Bulk confirmation؛ People / Characters mode.

### 38 · Review person photos · album-review

مراجعة الاقتراحات المرتبطة بشخص أو ألبومه مع الاحتفاظ بالصور المرجعية.

النوع: **screen**. العائلة: review. المدخل الرئيسي: `person-media`. الرجوع: `person-media`.

الفعل الرئيسي: **Review selected suggestion**.

[PNG](wireframes/screens/album-review.png) · [SVG قابل للتحرير](wireframes/screens/album-review.svg)

الأقسام بالترتيب:

- **Person context** (summary): Person cover and name؛ Pending suggestion count.
- **Suggested media** (grid): Highlighted candidate in original؛ Known reference photos.

أفعال ثانوية: Accept / Reject؛ Who is this?؛ Expand photo؛ Open full review.

الحالات المطلوب احترامها: No pending suggestions؛ Offline evidence؛ Original missing؛ Multiple detections in photo.

### 39 · Compare references · review-comparison

مقارنة الصور المرجعية بالهدف وفتح الأصل أو القصاصة دون قبول الاقتراح تلقائيًا.

النوع: **sheet**. العائلة: review. المدخل الرئيسي: `review-hub`. الرجوع: `origin`.

الفعل الرئيسي: **Return to decision**.

[PNG](wireframes/screens/review-comparison.png) · [SVG قابل للتحرير](wireframes/screens/review-comparison.svg)

الأقسام بالترتيب:

- **Candidate and references** (preview): Highlighted target؛ Reference photos؛ Original / Crop choice.
- **Evidence** (summary): Suggested identity؛ Existing reason and confidence when advanced review is enabled.

أفعال ثانوية: Expand image؛ Google Lens؛ Open person؛ Back.

الحالات المطلوب احترامها: Single reference؛ Multiple references؛ Missing original keeps crop؛ No automatic decision on expansion.

### 40 · Studio · studio-home

بدء الأدوات بدون صورة محددة وإدارة التدريب والنتائج مع وصول واضح للنشاط.

النوع: **screen**. العائلة: studio. المدخل الرئيسي: `Root`. الرجوع: `origin`.

الفعل الرئيسي: **Choose a tool**.

[PNG](wireframes/screens/studio-home.png) · [SVG قابل للتحرير](wireframes/screens/studio-home.svg)

الأقسام بالترتيب:

- **Create** (grid): Reface؛ Restyle؛ LoRA training and generation.
- **Your work** (list): Datasets and trained LoRAs؛ Private results؛ Activity and active jobs.

أفعال ثانوية: Choose from Gallery or Files؛ PC connection when a tool needs it.

الحالات المطلوب احترامها: Ready؛ PC offline؛ Engine unavailable؛ No saved work؛ Current jobs continue in Activity.

### 41 · Reface · Target · reface-target

تحديد الوسيط والشخص المستهدف للاستبدال قبل اختيار هوية المصدر.

النوع: **screen**. العائلة: studio. المدخل الرئيسي: `studio-home`. الرجوع: `origin`.

الفعل الرئيسي: **Continue to source identity**.

[PNG](wireframes/screens/reface-target.png) · [SVG قابل للتحرير](wireframes/screens/reface-target.svg)

الأقسام بالترتيب:

- **Step 1 of 3** (summary): Step 1 of 3: Target؛ Target: who will be replaced؛ Image entry pre-fills target media.
- **Target media** (preview): Choose Gallery or Files؛ Photo or video preview؛ Video trim handles and times.
- **Target identities** (grid): Detected face crops؛ Grouped video identities؛ Selected target highlight.

أفعال ثانوية: Detect faces؛ Detect current video frame؛ Expand target؛ Change media.

الحالات المطلوب احترامها: No target media؛ Analyzing faces؛ No faces؛ Multiple target people؛ Trim changed invalidates stale analysis؛ Legacy restrictions follow supported engine.

### 42 · Reface · Source identity · reface-source

اختيار هوية الشخص البديل منفصلة بوضوح عن وجوه الهدف.

النوع: **screen**. العائلة: studio. المدخل الرئيسي: `reface-target`. الرجوع: `reface-target`.

الفعل الرئيسي: **Continue to options**.

[PNG](wireframes/screens/reface-source.png) · [SVG قابل للتحرير](wireframes/screens/reface-source.svg)

الأقسام بالترتيب:

- **Step 2 of 3: Identity** (summary): Source: the identity to use؛ Person entry pre-fills source only after Use this identity؛ Image entry pre-fills target, not source.
- **Choose source** (list): Library person؛ Saved identity set؛ Multiple Gallery photos or videos؛ Verified LoRA identity when available.
- **Source references** (grid): Selected face poses؛ Grouped imported identities؛ Appearance count.

أفعال ثانوية: Import source media؛ Choose detected imported identity؛ Save identity set؛ Choose available DFM and bypass face source.

الحالات المطلوب احترامها: Library empty still allows imports؛ Multiple imported identities require choice؛ No usable source face؛ Character is not an ArcFace source؛ Unsupported LoRA identity unavailable؛ DFM path may continue without source faces.

### 43 · Reface · Review and run · reface-options

مراجعة المصدر والهدف والمحرك والجودة قبل إرسال العملية مع بقاء الضوابط المتقدمة.

النوع: **screen**. العائلة: studio. المدخل الرئيسي: `reface-source`. الرجوع: `reface-source`.

الفعل الرئيسي: **Run Reface**.

[PNG](wireframes/screens/reface-options.png) · [SVG قابل للتحرير](wireframes/screens/reface-options.svg)

الأقسام بالترتيب:

- **Step 3 of 3** (summary): Step 3 of 3: Review؛ Target person and media؛ Source identity or selected DFM؛ Selected video range.
- **Engine and quality** (fields): Available V2 / V3 / DFM options؛ Restorer and fidelity؛ Mask and occlusion controls؛ Identity and output quality settings.
- **Run choices** (list): Preview when supported؛ Full output؛ Private result.

أفعال ثانوية: Back to source؛ Advanced options؛ PC readiness.

الحالات المطلوب احترامها: Ready؛ PC offline؛ Engine unavailable؛ DFM unavailable؛ Uploading؛ Validation failed؛ Preview completed.

### 44 · Saved identity set · identity-set-editor

حفظ اختيار وجوه مرجعية باسم واضح للشخص دون تسميته موديل LoRA مدرب.

النوع: **sheet**. العائلة: person. المدخل الرئيسي: `person-identity`. الرجوع: `origin`.

الفعل الرئيسي: **Save identity set**.

[PNG](wireframes/screens/identity-set-editor.png) · [SVG قابل للتحرير](wireframes/screens/identity-set-editor.svg)

الأقسام بالترتيب:

- **Reference set** (fields): Set name؛ Source person.
- **Selected faces** (grid): Reference face poses؛ Add or remove selected faces.

أفعال ثانوية: Choose faces؛ Delete saved set؛ Cancel.

الحالات المطلوب احترامها: New set؛ Editing set؛ No usable faces؛ Character source restriction.

### 45 · Restyle · restyle

تعديل الصورة مع تحديد الوجه والمراجع والمعلمات المتاحة وإظهار قدرات الكمبيوتر الفعلية.

النوع: **screen**. العائلة: studio. المدخل الرئيسي: `studio-home`. الرجوع: `origin`.

الفعل الرئيسي: **Run Restyle**.

[PNG](wireframes/screens/restyle.png) · [SVG قابل للتحرير](wireframes/screens/restyle.svg)

الأقسام بالترتيب:

- **Target photo** (preview): Current viewer photo when provided؛ Selected face highlight؛ Expand original.
- **Restyle request** (fields): Prompt؛ Face and padding؛ Strength.
- **References** (grid): Up to four reference images؛ Add or remove reference.
- **Advanced** (fields): Negative prompt؛ Seed and steps؛ Optional refinement when available.

أفعال ثانوية: Choose another photo؛ Change selected face؛ PC readiness.

الحالات المطلوب احترامها: No photo؛ Analyzing؛ No face selected؛ PC offline؛ Base engine unavailable؛ Refinement unavailable؛ Submitting؛ Validation error.

### 46 · Datasets and models · training-library

قائمة التدريب العامة تفرق بين Dataset وLoRA ومهمة تدريب لم تكتمل.

النوع: **screen**. العائلة: studio. المدخل الرئيسي: `studio-home`. الرجوع: `studio-home`.

الفعل الرئيسي: **Open dataset or model**.

[PNG](wireframes/screens/training-library.png) · [SVG قابل للتحرير](wireframes/screens/training-library.svg)

الأقسام بالترتيب:

- **Training library** (tabs): Datasets؛ Trained LoRAs.
- **Saved artifacts** (list): Person or Unlinked؛ Trigger word؛ Dataset image count or model availability.
- **Training activity** (summary): Running / Paused / Failed jobs are separate from ready models.

أفعال ثانوية: Build dataset؛ Generate with LoRA؛ Share model؛ Build verified identity؛ Open activity.

الحالات المطلوب احترامها: No datasets؛ No models؛ Orphaned person link؛ Loading saved artifacts؛ Offline browsing.

### 47 · Build dataset · dataset-build

تجهيز صور وفيديوهات التدريب لشخص معلوم مع trigger word وخيارات التكرار الحالية.

النوع: **screen**. العائلة: studio. المدخل الرئيسي: `training-library`. الرجوع: `origin`.

الفعل الرئيسي: **Build dataset**.

[PNG](wireframes/screens/dataset-build.png) · [SVG قابل للتحرير](wireframes/screens/dataset-build.svg)

الأقسام بالترتيب:

- **Identity and naming** (fields): Choose person؛ Trigger word؛ Repeats.
- **Training inputs** (grid): Gallery photos؛ Video input؛ Selected input previews.

أفعال ثانوية: Add photos؛ Add video؛ Expand input؛ Remove selected input.

الحالات المطلوب احترامها: No person؛ No inputs؛ PC needed to build؛ Preparing؛ Submitting؛ Input error.

### 48 · Dataset editor · dataset-editor

مراجعة الصور وكابتشن كل عنصر وتضمينه أو استبعاده ثم التدريب أو التصدير.

النوع: **screen**. العائلة: studio. المدخل الرئيسي: `training-library`. الرجوع: `origin`.

الفعل الرئيسي: **Train with this dataset**.

[PNG](wireframes/screens/dataset-editor.png) · [SVG قابل للتحرير](wireframes/screens/dataset-editor.svg)

الأقسام بالترتيب:

- **Dataset** (summary): Associated person؛ Trigger word؛ Included / Total images.
- **Training images** (grid): Image preview؛ Include or exclude؛ Editable caption.

أفعال ثانوية: Edit caption؛ Expand image؛ Export dataset.

الحالات المطلوب احترامها: Loading؛ Empty dataset؛ Fewer than five included images disables training؛ Offline editing؛ Export error.

### 49 · Train LoRA · lora-training

ضبط تدريب LoRA على Dataset محدد دون وعد باستئناف أي خطوة غير مدعومة.

النوع: **screen**. العائلة: studio. المدخل الرئيسي: `dataset-editor`. الرجوع: `origin`.

الفعل الرئيسي: **Start training**.

[PNG](wireframes/screens/lora-training.png) · [SVG قابل للتحرير](wireframes/screens/lora-training.svg)

الأقسام بالترتيب:

- **Training source** (summary): Selected dataset؛ Linked person.
- **Training settings** (fields): Base checkpoint؛ Epochs.
- **Advanced** (fields): Network dimension؛ Resolution؛ Learning rate.

أفعال ثانوية: Choose another dataset؛ PC readiness؛ Open training activity.

الحالات المطلوب احترامها: No dataset؛ No base checkpoint؛ Engine unavailable؛ Ready؛ Submitting؛ Resume uses supported epoch checkpoint.

### 50 · LoRA model · model-details

عرض LoRA محلي جاهز واستخدامه وعلاقاته المعروفة دون اختلاق إصدار أو تاريخ تدريب قديم.

النوع: **screen**. العائلة: studio. المدخل الرئيسي: `training-library`. الرجوع: `origin`.

الفعل الرئيسي: **Generate images**.

[PNG](wireframes/screens/model-details.png) · [SVG قابل للتحرير](wireframes/screens/model-details.svg)

الأقسام بالترتيب:

- **Trained LoRA** (summary): Trigger word or saved model name؛ Linked person or Unlinked؛ Local model file availability.
- **Known relationships** (list): Source dataset when explicitly linked؛ Training job when known؛ Generated results when linked.
- **Model actions** (list): Generate؛ Share model file؛ Build verified identity.

أفعال ثانوية: Open person؛ Open dataset؛ Open training job؛ View results.

الحالات المطلوب احترامها: Ready local model؛ Model file missing؛ Person link missing؛ Unknown historical provenance؛ Identity not built؛ PC needed for generation.

### 51 · Generate with LoRA · lora-generate

اختيار LoRA وقاعدة التوليد والنص والمرجع مع الاحتفاظ بسياق الشخص والصورة.

النوع: **screen**. العائلة: studio. المدخل الرئيسي: `model-details`. الرجوع: `origin`.

الفعل الرئيسي: **Generate**.

[PNG](wireframes/screens/lora-generate.png) · [SVG قابل للتحرير](wireframes/screens/lora-generate.svg)

الأقسام بالترتيب:

- **Model** (summary): Selected LoRA؛ Linked person؛ Base checkpoint.
- **Generation** (fields): Prompt؛ Image count؛ Seed.
- **Optional reference** (preview): Current image can be a reference؛ Composition / Style / Both.

أفعال ثانوية: Change LoRA؛ Add or replace reference؛ Expand reference؛ PC readiness.

الحالات المطلوب احترامها: No ready model؛ No base checkpoint؛ Engine unavailable؛ Ready؛ Submitting؛ Reference missing.

### 52 · Activity · activity-center

يجمع الفحص والمهام وسجلها بدل تبويب Jobs المنفصل دون فقد العمليات.

النوع: **screen**. العائلة: activity. المدخل الرئيسي: `studio-home`. الرجوع: `origin`.

الفعل الرئيسي: **Open current operation**.

[PNG](wireframes/screens/activity-center.png) · [SVG قابل للتحرير](wireframes/screens/activity-center.svg)

الأقسام بالترتيب:

- **Activity** (tabs): Analysis؛ Studio jobs؛ History.
- **Operations** (list): Current stage and progress؛ Paused or failed state؛ Estimated time when available.

أفعال ثانوية: Open analysis details؛ Open job details؛ Open result؛ Return to gallery.

الحالات المطلوب احترامها: No activity؛ Running scan؛ Queued jobs؛ Manually paused؛ PC offline؛ Completed history.

### 53 · Analysis progress · scan-details

تفاصيل الفحص وإعداداته والملفات الفاشلة مع احترام الإيقاف اليدوي والاستئناف.

النوع: **screen**. العائلة: activity. المدخل الرئيسي: `activity-center`. الرجوع: `activity-center`.

الفعل الرئيسي: **Pause or resume analysis**.

[PNG](wireframes/screens/scan-details.png) · [SVG قابل للتحرير](wireframes/screens/scan-details.svg)

الأقسام بالترتيب:

- **Current pass** (summary): Analyzed / Remaining / Failed؛ Current file preview؛ Current stage.
- **Queue details** (list): Photo and video progress؛ Selected album scope؛ Failed media with retry؛ Video checkpoint details.

أفعال ثانوية: Retry failed media؛ Manage sources؛ Open current media؛ Analysis options.

الحالات المطلوب احترامها: Enumerating؛ Analyzing؛ Offline waiting؛ User paused؛ Failed item؛ Completed؛ Maintenance blocks work.

### 54 · Job details · job-details

حالة المهمة والمراحل والوقت والتفاصيل المناسبة للتدريب أو Reface والنتيجة المحفوظة.

النوع: **screen**. العائلة: activity. المدخل الرئيسي: `activity-center`. الرجوع: `activity-center`.

الفعل الرئيسي: **Open result or resume**.

[PNG](wireframes/screens/job-details.png) · [SVG قابل للتحرير](wireframes/screens/job-details.svg)

الأقسام بالترتيب:

- **Job status** (summary): Uploading / Queued / Running / Paused؛ Downloading / Completed / Failed / Lost؛ Progress and estimated time.
- **Operation details** (list): Type and source person؛ Stage / Epoch / Step where available؛ Reface actual swaps / Skips / Failures؛ Recorded warnings and event history.

أفعال ثانوية: Pause؛ Resume / Retry؛ Remove job with confirmation؛ Open result.

الحالات المطلوب احترامها: Uploading؛ Queued؛ Running؛ Paused؛ Downloading؛ Completed؛ Failed؛ Lost؛ Offline recovery.

### 55 · Private results · results-gallery

شبكة النتائج الخاصة مع المفضلة والنوع دون نشرها تلقائيًا في معرض الهاتف.

النوع: **screen**. العائلة: results. المدخل الرئيسي: `studio-home`. الرجوع: `origin`.

الفعل الرئيسي: **Open result**.

[PNG](wireframes/screens/results-gallery.png) · [SVG قابل للتحرير](wireframes/screens/results-gallery.svg)

الأقسام بالترتيب:

- **Result filters** (fields): All / Favourites؛ Photos / Videos.
- **Saved results** (grid): Output preview؛ Creation time؛ Result type.

أفعال ثانوية: Open related job؛ Create new result.

الحالات المطلوب احترامها: No results؛ No filter matches؛ Offline local results؛ Missing private output.

### 56 · Result · result-viewer

عرض نتيجة صورة أو فيديو والمقارنة والأصل والعلاقات المعروفة مع الحفظ أو المشاركة الصريحة.

النوع: **screen**. العائلة: results. المدخل الرئيسي: `results-gallery`. الرجوع: `origin`.

الفعل الرئيسي: **Save to gallery**.

[PNG](wireframes/screens/result-viewer.png) · [SVG قابل للتحرير](wireframes/screens/result-viewer.svg)

الأقسام بالترتيب:

- **Output** (preview): Photo or video player؛ Before / After only when a source exists؛ Text-only generation has no Before view؛ Separate source and output expansion when present.
- **Source and tools** (summary): Linked source media when known؛ Job / Person / Model when linked؛ Private original snapshot when source is missing.

أفعال ثانوية: Share؛ Favourite؛ Open original؛ Open related job؛ Delete private result؛ Open Reface.

الحالات المطلوب احترامها: Photo result؛ Video result؛ Original missing keeps snapshot؛ Older unlinked source labelled؛ Output missing؛ Export cancelled؛ Share failed؛ Artifact-aware delete confirmation lists any same-ID model or dataset and files.

### 57 · Analysis sources · analysis-sources

اختيار مجلدات التحليل مختلف عن تصفح المجلدات في Gallery.

النوع: **screen**. العائلة: settings. المدخل الرئيسي: `settings-home`. الرجوع: `origin`.

الفعل الرئيسي: **Start analysis**.

[PNG](wireframes/screens/analysis-sources.png) · [SVG قابل للتحرير](wireframes/screens/analysis-sources.svg)

الأقسام بالترتيب:

- **Device albums** (list): All media or selected albums؛ Media count؛ Illustrated album flag for a chosen real folder.
- **Current scope** (summary): Selected albums؛ Current scan state.

أفعال ثانوية: Analysis options؛ Open activity؛ Open folder without analyzing.

الحالات المطلوب احترامها: No albums chosen؛ Access limited؛ No accessible media؛ Active scan restricts changes؛ PC connection needed.

### 58 · Analysis settings · analysis-settings

إعدادات الصور والأجسام والفيديو والتجميع والجودة والمراجعة المتقدمة مع الحفاظ على القدرات الحالية.

النوع: **screen**. العائلة: settings. المدخل الرئيسي: `analysis-sources`. الرجوع: `origin`.

الفعل الرئيسي: **Save analysis preferences**.

[PNG](wireframes/screens/analysis-settings.png) · [SVG قابل للتحرير](wireframes/screens/analysis-settings.svg)

الأقسام بالترتيب:

- **Inputs** (fields): Include videos؛ Adaptive sampling or frame interval؛ Detect bodies؛ Maximum image side.
- **Identity grouping** (fields): Strict / Balanced / Loose؛ Quality threshold؛ Sort now.
- **Maintenance** (list): Retry missing outlines؛ Advanced review evidence؛ Photo-only / Experimental capabilities remain labelled.

أفعال ثانوية: Manage sources؛ Open analysis status؛ Retry outline processing.

الحالات المطلوب احترامها: Saved؛ Scan running restricts inputs؛ PC offline؛ Outline retry running؛ No pending outlines.

### 59 · Analyze a photo · analyze-single

تجربة اكتشاف مستقلة للصورة أو للشخصيات دون اشتراط إضافتها لمكتبة الأشخاص.

النوع: **screen**. العائلة: settings. المدخل الرئيسي: `settings-home`. الرجوع: `origin`.

الفعل الرئيسي: **Choose photo**.

[PNG](wireframes/screens/analyze-single.png) · [SVG قابل للتحرير](wireframes/screens/analyze-single.svg)

الأقسام بالترتيب:

- **Analysis input** (preview): Selected photo؛ Face and body overlays.
- **Detected faces** (grid): Crop؛ Identity suggestions when available؛ Open full image.

أفعال ثانوية: Analyze another photo؛ Person / Character mode؛ Explicitly assign detected identity.

الحالات المطلوب احترامها: No photo؛ Analyzing؛ PC offline؛ No faces؛ Error with retry؛ Characters mode.

### 60 · Library insights · library-insights

إحصاءات التغطية والجودة ومداخل الملفات غير المصنفة والفحص بعيدًا عن بداية الجاليري.

النوع: **screen**. العائلة: settings. المدخل الرئيسي: `settings-home`. الرجوع: `settings-home`.

الفعل الرئيسي: **Open relevant library view**.

[PNG](wireframes/screens/library-insights.png) · [SVG قابل للتحرير](wireframes/screens/library-insights.svg)

الأقسام بالترتيب:

- **Library coverage** (summary): Photos / Videos / People؛ Analyzed / Remaining / Failed؛ Face quality and grouping coverage.
- **Follow up** (list): Unassigned faces؛ Analysis sources؛ People with most appearances.

أفعال ثانوية: Start analysis؛ Open person؛ Open unassigned faces.

الحالات المطلوب احترامها: No library data؛ Partial analysis؛ Offline local statistics.

### 61 · Settings · settings-home

تجميع الإعدادات التشغيلية والخصوصية وأدوات المكتبة مع مدخل من الجاليري.

النوع: **screen**. العائلة: settings. المدخل الرئيسي: `gallery-photos`. الرجوع: `origin`.

الفعل الرئيسي: **Open settings category**.

[PNG](wireframes/screens/settings-home.png) · [SVG قابل للتحرير](wireframes/screens/settings-home.svg)

الأقسام بالترتيب:

- **Library** (list): Analysis sources and options؛ Analyze a photo؛ Library insights.
- **Privacy and storage** (list): App lock؛ Storage and cleanup؛ Encrypted backup and restore.
- **Device** (list): PC connection and resource readiness؛ Background and battery settings.

أفعال ثانوية: Back to gallery.

الحالات المطلوب احترامها: Local settings available offline؛ Paired PC؛ No paired PC.

### 62 · PC connection · pc-connection

ربط الكمبيوتر عند الحاجة والتحقق من الاتصال والموارد والمحركات المتاحة.

النوع: **screen**. العائلة: settings. المدخل الرئيسي: `settings-home`. الرجوع: `origin`.

الفعل الرئيسي: **Find or connect to PC**.

[PNG](wireframes/screens/pc-connection.png) · [SVG قابل للتحرير](wireframes/screens/pc-connection.svg)

الأقسام بالترتيب:

- **Saved connection** (summary): PC name and verified identity؛ Connected / Offline / Busy.
- **Pairing choices** (list): Scan QR code؛ Enter address manually؛ Find PCs on local network.
- **Resource readiness** (list): Advertised engine readiness؛ Shared base checkpoints؛ Available DFM models؛ Storage and device resource checks.
- **Network help** (summary): Reachable PC endpoints؛ Phone local addresses؛ Connection diagnostics.

أفعال ثانوية: Retry discovery؛ Use a matching saved-PC endpoint؛ Forget PC؛ Return to pending tool.

الحالات المطلوب احترامها: Never paired؛ Discovering؛ Connected؛ Busy؛ Offline؛ Certificate or identity mismatch؛ Engine missing.

### 63 · Scan pairing code · pair-qr

قراءة كود ربط الكمبيوتر ثم العودة للأداة التي طلبت الاتصال.

النوع: **screen**. العائلة: settings. المدخل الرئيسي: `pc-connection`. الرجوع: `pc-connection`.

الفعل الرئيسي: **Scan QR code**.

[PNG](wireframes/screens/pair-qr.png) · [SVG قابل للتحرير](wireframes/screens/pair-qr.svg)

الأقسام بالترتيب:

- **Camera scanner** (preview): Pairing QR target.
- **Pairing verification** (summary): Detected PC address؛ Certificate identity confirmation when required.

أفعال ثانوية: Enter manually؛ Cancel.

الحالات المطلوب احترامها: Camera permission needed؛ Scanning؛ Invalid code؛ Expired code؛ Pairing failed؛ Paired.

### 64 · Pair manually · pair-manual

إدخال عنوان الكمبيوتر والكود والتحقق من بصمة الشهادة ضمن مسار الربط الحالي.

النوع: **screen**. العائلة: settings. المدخل الرئيسي: `pc-connection`. الرجوع: `pc-connection`.

الفعل الرئيسي: **Pair with PC**.

[PNG](wireframes/screens/pair-manual.png) · [SVG قابل للتحرير](wireframes/screens/pair-manual.svg)

الأقسام بالترتيب:

- **PC address** (fields): Host؛ Port؛ Pairing code.
- **Verify connection** (summary): Certificate fingerprint؛ Server identity.

أفعال ثانوية: Scan QR instead؛ Cancel.

الحالات المطلوب احترامها: Empty fields؛ Invalid address؛ Connection failed؛ Fingerprint confirmation؛ Code expired؛ Paired.

### 65 · Background activity · background-settings

إدارة عمل الفحص والمهام في الخلفية ومساعدة إعدادات البطارية دون تشغيل مهمة موقوفة.

النوع: **screen**. العائلة: settings. المدخل الرئيسي: `settings-home`. الرجوع: `settings-home`.

الفعل الرئيسي: **Open Android battery settings**.

[PNG](wireframes/screens/background-settings.png) · [SVG قابل للتحرير](wireframes/screens/background-settings.svg)

الأقسام بالترتيب:

- **Background state** (summary): Foreground work state؛ Notification and battery permission state.
- **Keep work running** (list): Battery optimization guidance؛ Relevant Android settings؛ Current scan or job progress.

أفعال ثانوية: Open activity؛ Refresh status.

الحالات المطلوب احترامها: No active work؛ Background work active؛ Battery restriction؛ Notification permission denied؛ User paused remains paused.

### 66 · Storage · storage-settings

عرض استخدام التخزين والتنظيف بالخيارات الحالية مع فصل المؤقت عن النتائج المحفوظة.

النوع: **screen**. العائلة: settings. المدخل الرئيسي: `settings-home`. الرجوع: `settings-home`.

الفعل الرئيسي: **Review cleanup**.

[PNG](wireframes/screens/storage-settings.png) · [SVG قابل للتحرير](wireframes/screens/storage-settings.svg)

الأقسام بالترتيب:

- **Storage use** (summary): Private crops؛ Saved results and models؛ Temporary files.
- **Cleanup actions** (list): Clean orphaned leftovers؛ Delete temporary data؛ Optional removal of saved items with confirmation.

أفعال ثانوية: Refresh storage؛ Open backup.

الحالات المطلوب احترامها: Calculating؛ No leftovers؛ Cleanup ready؛ Active operations restrict cleanup؛ Confirmation؛ Partial cleanup failure.

### 67 · Backup and restore · backup-restore

إنشاء نسخة مشفرة أو استعادة بعد معاينة المحتوى والتأكيد مع توضيح نطاق النسخة.

النوع: **screen**. العائلة: settings. المدخل الرئيسي: `settings-home`. الرجوع: `settings-home`.

الفعل الرئيسي: **Create backup**.

[PNG](wireframes/screens/backup-restore.png) · [SVG قابل للتحرير](wireframes/screens/backup-restore.svg)

الأقسام بالترتيب:

- **Backup actions** (list): Create and share backup؛ Choose backup to inspect and restore.
- **Encryption** (fields): Encrypt backup: on by default؛ Password and confirmation for encrypted backup؛ Plaintext backup requires explicit opt-out.
- **Included content** (summary): App index and private derived artifacts؛ Device originals are not all copied؛ PC credentials are not transferred.

أفعال ثانوية: Inspect selected backup؛ Restore after explicit confirmation؛ Cancel operation.

الحالات المطلوب احترامها: Idle؛ Creating؛ Share cancelled؛ Inspecting؛ Password required؛ Invalid backup؛ Restore confirmation؛ Restoring؛ Completed؛ Failure.

### 68 · App lock · app-lock

تفعيل أو فك قفل التطبيق بالمصادقة الحالية مع استمرار إعداد التقاط الشاشة الذي اختاره المستخدم.

النوع: **dialog**. العائلة: settings. المدخل الرئيسي: `settings-home`. الرجوع: `origin`.

الفعل الرئيسي: **Authenticate and continue**.

[PNG](wireframes/screens/app-lock.png) · [SVG قابل للتحرير](wireframes/screens/app-lock.svg)

الأقسام بالترتيب:

- **App access** (summary): Device credential or supported authentication؛ Lock enabled state.
- **Controls** (list): Enable app lock؛ Disable app lock؛ Unlock current session.

أفعال ثانوية: Cancel.

الحالات المطلوب احترامها: Lock disabled؛ Authentication required؛ Unlock failed؛ Unlocked؛ System credential screen.

## التحقق وحدود التسليم

- تم توليد 68 شاشة ونسختين لحالات النتائج، جميعها 390 × 844، مع 12 لوحة لا تتجاوز ست شاشات في الواحدة. المسار الأساسي ثلاث شاشات في الصف.
- فُحصت لوحات ممثلة بصريًا: Gallery والتفاصيل والشخص والموديلات وReface والمراجعة والإعدادات، ثم لوحة التصحيحات كاملة للمسار الأساسي.
- روجعت حدود النصوص وحجم الخط ووجود ملفات SVG/PNG، الفصل بين المصدر والهدف، التشفير الافتراضي، حذف artifact، والمقارنة المشروطة بوجود مصدر.
- هذه ليست تجربة Android فعلية ولا اختبارًا لحجم نص كبير أو RTL أو Light/Dark أو اللمس؛ الحالات موثقة للمرحلة التالية.
- قيود بيانات الدمج والروابط القديمة تبقى ملاحظات تنفيذ في وثائق المفهوم والتكافؤ؛ الواجهة المقترحة تعرض العواقب المفهومة للمستخدم.

يمكن إعادة إنتاج الصور من `wireframes/render-wireframes.cjs` باستخدام Node والمكتبة المحلية المثبتة؛ لم يُشغّل أي shell أو build أو اختبار للتطبيق ضمن هذا الرسم.

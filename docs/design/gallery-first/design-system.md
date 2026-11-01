# النظام البصري للـwireframes: Gallery first

التاريخ: 1 نوفمبر 2026. الحالة: مواصفات رسم low/mid-fidelity للموبايل، وليست تعديلًا للتطبيق أو اعتمادًا لميزات جديدة.

مرجع البنية: [التصور المختار](../../gallery-first-mobile-concept-2026-11-01.md). التنقل المعتمد: **Gallery / People / Discover / Studio**. داخل Gallery: **Photos / Folders**. داخل الشخص: **Media / Identity / Models**. الوثائق بالعربية؛ النص الظاهر داخل الشاشات بالإنجليزية اتساقًا مع التطبيق الحالي. لا تعتبر هذه المرحلة إضافة دعم عربي أو RTL.

## 1. المبدأ الذي يحكم الرسم

الصور هي المحتوى الأساسي. يبدأ التطبيق بشبكة الصور، ويكشف التفاصيل والهوية والأدوات عند الحاجة. لا توجد dashboard افتتاحية، ولا إحصاءات أو حالة كمبيوتر كبيرة تزاحم أول صف صور. Discover يعرض أمثلة بصرية فعلية ومعايير مدعومة؛ Studio مكان الأدوات والـDatasets والموديلات والنتائج. يحتفظ كل مدخل بسياق الصورة أو الشخص الذي بدأ منه.

نستخدم لغة Android و Material 3 الحالية: system typography، AppBar، NavigationBar، tabs، bottom sheets، قوائم، وحقول مألوفة. لا زجاج ضبابي ولا gradients أو textures زخرفية، ولا إطار بطاقة حول كل جزء. لا texture أو tint يغطي الصورة نفسها. البنية تبدأ من الموجود في mobile/lib/core/theme.dart و features/shared/screen_layout.dart، مع دفء أهدأ للخلفيات وإعطاء مساحة أكبر للصور. هذه قيم مقترحة للرسم؛ لم تتغير ثيمات Flutter الحالية.

## 2. وحدات القياس وإطار الشاشات

كل القياسات التالية **dp**، والنص **sp عند text scale 1.0**. مرجع الرسم 390 × 844. شريط الحالة 24 و gesture inset سفلي 24 مجرد قيم مرجعية في اللوحات؛ التنفيذ يقرأ system insets الفعلية ولا يثبت هذه القيم.

| العنصر | القيمة الأساسية | قاعدة التكيف |
|---|---:|---|
| عرض مرجعي | 390 | تحقق أيضًا عند 320 و 360 و 412 |
| AppBar | 56 حد أدنى، بعد status inset | يرتفع مع النص إذا لزم، والعنوان لا يصطدم بالأزرار |
| NavigationBar رئيسي | 80، بعده bottom safe inset | أربعة destinations فقط؛ labels ظاهرة دائمًا |
| حافة محتوى القوائم والفورم | 20 يمينًا ويسارًا | 16 عند عرض 320 عند الحاجة؛ نفس الحافة داخل الشاشة |
| الحد الأدنى لأي touch target | 48 × 48 | لا تتداخل المساحات الفعلية للضغط |
| أيقونة عادية | 24 × 24 | 20 في صف metadata غير تفاعلي فقط |
| زر أساسي | 52 ارتفاعًا كحد أدنى | محتوى وزيادة ارتفاع عند التفاف النص؛ عرض كامل للفورم |
| زر ثانوي / text button | 48 ارتفاعًا كحد أدنى | لا يُصغر بسبب قصر النص |
| حقل single-line | 56 كحد أدنى | label ظاهر، ومساحة مستقلة للخطأ والمساعدة |
| prompt متعدد السطور | 120 كحد أدنى | ينمو ثم يتمرر محتوى الشاشة، لا يقطع النص |
| list row بنص واحد | 56 كحد أدنى | سطران 72؛ الوصف الطويل يرفع الصف تلقائيًا |
| شريط إجراء سفلي | 12 أعلى وأسفل + زر 52 | يضاف safe inset؛ محتوى الصفحة يأخذ نفس المساحة من الأسفل |
| حافة bottom sheet العليا | radius 24 | بقيّة اللوحات لا تقلد شكل الـsheet |
| drag handle مرئي | 32 × 4 | داخل منطقة سحب بارتفاع 32 على الأقل، مع زر بديل |
| divider | 1 | للفصل البنيوي فقط، وليس إطارًا لكل صف |

سلم المسافات: **4 / 8 / 12 / 16 / 20 / 24 / 32**. العلاقة بين label وقيمته 4؛ العناصر داخل مجموعة 8 أو 12؛ أقسام المحتوى 24؛ فصل قسم رئيسي 32 عند الحاجة. لا نضيف card padding فوق page padding بطريقة تضيق الصورة أو الفورم بلا سبب.

## 3. الألوان والوضوح

الأخضر لون الإجراء والاختيار. بقية الأسطح neutrals دافئة ومطفأة؛ الصور تحمل التنوع البصري. الأحمر استثناء وظيفي للأخطاء والحذف، وليس لون قسم أو زينة. الحالات الأخرى تُفهم بالنص والأيقونة، دون توزيع ألوان على كل feature.

| Token | Light | Dark | الاستخدام |
|---|---|---|---|
| canvas | #F7F6F2 | #171A17 | خلفية التطبيق |
| surface | #FFFFFF | #20251F | sheet، form section عند الضرورة، NavigationBar |
| subtle | #EDECE6 | #2A3028 | فصل لطيف، thumbnail fallback، حالة غير مختارة |
| text | #242823 | #ECEDE7 | النص الأساسي |
| secondary | #62675F | #B6BDAF | التاريخ والوصف والمساعدة |
| divider | #DCDDD5 | #454D41 | فواصل زخرفية غير لازمة لفهم control |
| control outline | #7A8274 | #87937F | حدود الحقول أو controls التي تعتمد على الحد للتمييز |
| action | #286653 | #A4D5BD | زر أساسي، تركيز، حالة اختيار |
| on action | #FFFFFF | #12382C | نص فوق action |
| selected surface | #DDEBE2 | #2D4F40 | اختيار tab/chip/context |
| on selected | #1E4A3B | #BFE6D1 | نص الاختيار |
| error text | #B3261E | #FFB4AB | خطأ أو فعل حذف صريح |
| viewer canvas | #101310 | #101310 | صورة/فيديو على مساحة مظلمة في الوضعين |
| viewer text | #F4F6F1 | #F4F6F1 | نص أدوات العارض |

فحص حسابي للقيم المقترحة، قبل وضع أي صورة: text/canvas يحقق 13.84:1 Light و 14.90:1 Dark؛ secondary/canvas يحقق 5.36:1 و 9.10:1؛ on-action/action يحقق 6.74:1 و 7.88:1؛ on-selected/selected يحقق 8.13:1 و 6.71:1. الهدف 4.5:1 للنص العادي و 3:1 للأجزاء الوظيفية غير النصية. فواصل divider الخفيفة لا تُستخدم وحدها لإظهار حدود control أو الاختيار. فوق الصور نستخدم control background معتمًا أو scrim محليًا كافيًا؛ لا نعتمد على طبيعة الصورة لتحقيق contrast.

يستخدم selected state علامة/أيقونة ونصًا بالإضافة للون. disabled action له سبب قريب ومقروء؛ لا نخفي سبب التعطيل داخل tooltip أو نعالج النص كله ب opacity ضعيفة.

## 4. الخط والنصوص

خط Android النظامي الحالي؛ Roboto في رسومات المرجع. لا تنزيل خطوط ولا نظام خطوط جديد. لا serif أو display type داخل تطبيق الصور.

| الدور | الحجم / line height | الوزن | مثال |
|---|---|---|---|
| عنوان collection رئيسي | 28 / 34 | 600 | Gallery، Discover |
| عنوان شاشة داخلية | 22 / 28 | 600 | Nadia، Model details |
| عنوان قسم | 18 / 24 | 600 | People in this photo |
| عنوان صف / body | 16 / 24 | 400 أو 500 | اسم موديل، وصف قصير |
| label / button / tab | 14 / 20 | 500 أو 600 | Photos، Generate images |
| metadata | 12 / 16 | 400 | التاريخ، عدد العناصر، file type |
| bottom navigation | 12 / 16 | 500؛ المختار 600 | Gallery / People / Discover / Studio |

لا نص وظيفي أصغر من 12. الأرقام والتوقيت داخل progress و video تستخدم tabular figures. الاسم الطويل يلتف أو يتم اقتطاعه بصريًا مع إمكانية رؤية الاسم الكامل في التفاصيل؛ لا يُخفض font size ليلائم المساحة. لا عنوان ووصف تعليمي طويل أعلى كل شاشة؛ العنوان والمحتوى يكفيان عند وضوح الوظيفة.

مصطلحات ثابتة: **Gallery, Photos, Folders, People, Characters, Discover, Studio, Activity, Media, Identity, Models, Datasets, Results, Details, Tools**. تبقى أسماء الأدوات الحالية Reface و Restyle. نفصل **Source identity** عن **Target person**؛ و**Saved identity** عن **Trained model**. حالات الموديل المستورد: **Ready on this phone / File unavailable** بحسب الملف الفعلي، وليس Ready اعتمادًا على وجود سجل فقط. **Training / Paused / Failed** حالات مهمة تدريب وتظهر في قسم **Training tasks** مستقل، ولا تدخل قائمة **Trained models** قبل نجاح التدريب والاستيراد المحلي.

## 5. هيكل التنقل

الجذر يعرض أربعة destinations بالترتيب المعتمد، أيقونة فوق label، والمساحة موزعة بالتساوي. لا زر Create عائم أو destination خامس. Activity فعل عام بأيقونة وعداد عند وجود عمليات؛ Studio يحتوي مدخلًا واضحًا له أيضًا. Settings مدخل معروف في overflow العام؛ لا يحتاج أن يزاحم كل AppBar بزر منفصل.

| الشاشة | الأعلى | الأسفل | السلوك |
|---|---|---|---|
| Gallery | عنوان، Search/Filter، Activity، More بحسب السعة | NavigationBar | Photos/Folders مباشرة أسفل العنوان؛ Photos افتراضية |
| People | عنوان، Search، More؛ Activity إذا اتسع | NavigationBar | People/Characters واضحان؛ Review مدخل بعداد |
| Discover | عنوان، اختيار معيار أو reference عند الدخول بسياق | NavigationBar | أقسام بصرية مدعومة، ثم نتائج داخل الوجهة |
| Studio | عنوان و Activity | NavigationBar | أدوات، Models/Datasets/Results؛ لا dashboard أرقام |
| Person / Model / Dataset / form / job / result | Back، عنوان، action ثانوي أو More | شريط إجراء عند الحاجة | تُفتح كمسارات تفصيلية فوق الجذر؛ لا NavigationBar مزدوج |
| Image/video viewer | Back، عدد/تاريخ مختصر، More | أدوات العارض فقط | لا NavigationBar؛ الصورة هي المساحة الرئيسية |

الـAppBar عند 390 لا يحمل أكثر من ثلاثة targets بعد العنوان؛ إذا ازدحم، ينتقل الأقل تكرارًا إلى More. Search أيقونة تفتح سطح البحث بدل إضافة حقل فوق كل شبكة دون حاجة. Filters الحالية تبقى صريحة، مع Active filter summary و Clear filters عند تطبيقها. Discover ليس بحثًا لغويًا مفتوحًا ولا prompt box.

تبديل Photos/Folders ارتفاعه 48 حد أدنى، بحد سفلي أو indicator واضح، وليس نصين باهتين. عند العودة للجذر يستمر التبويب الداخلي وموضع التمرير؛ بداية التشغيل الافتراضية Photos. فتح Folder أو Person أو Discover result ثم Back يعيد نفس القائمة والفلتر والموضع. هذه عقود التنقل المقترحة وليست ادعاءً بأنها مطبقة حاليًا.

## 6. الشبكات والصور والمحتوى

### Gallery

Photo grid أربعة أعمدة عند 320–412، مربعات cropped للمعاينة، gap2 وبدون حافة خارجية. عند 390 يكون كل tile96dp. لا radius لكل صورة ولا borders ولا captions تستهلك مساحة الشبكة. group header للتاريخ بنص 14 وحواف 20 و padding رأسي 12. الـviewer دائمًا يعرض الأصل كاملًا باستخدام fit؛ قص الـthumbnail لا يحدد قص الأصل.

الفيديو يحمل رمزًا ومدة صغيرة داخل pill داكنة أسفل المعاينة. كل tile هدف ضغط مستقل. اختيار عدة عناصر له mode صريح و checkmarks؛ لا نجعل النقر والاختيار نفس الفعل. لا نرسم عمليات نقل/حذف/مشاركة جماعية جديدة إلا لما تسمح به الميزات المعتمدة. حالة الفحص لا تصبح شارة على كل thumbnail بشكل افتراضي؛ تظهر عند استعمال scan filter أوفتح التفاصيل.

Folders: عمودان بحافة 20 و gap12؛ الغلاف 4:3، radius12، واسم 16 وعدد 12 أسفله. منطقة النص 48 كحد أدنى وتنمو حسب الاسم؛ كله عنصر فتح واحد، ولا checkbox فحص على غلاف الفولدر. More داخل الفولدر يفتح Analyze folder و Scan settings. قائمة Folders تمثل الألبومات/المجلدات التي يكشفها النظام؛ ليست file explorer حرًا.

### People

ثلاثة أعمدة عند 390 للغلاف المربع radius12؛ gap12، الحواف 20. الاسم 14، وتعداد الوسائط 12 عند توفره. pin/favorite/hide مؤشرات صغيرة بنص بديل؛ لا أزرار متداخلة داخل الصورة. زر More أو long press يفتح action sheet نفسها؛ Select mode له مدخل ظاهر. عند 320 أو text scale كبير يصبح عمودين، ثم قائمة إذا لزم.

ضابط محتوى بصري: كل tile في **Person · Media** يجب أن يظهر فيه الشخص نفسه فعليًا، بما في ذلك الصور الجماعية. لا نستخدم landscapes أوصورًا لا تحتويه لملء الشبكة. معاينات **Datasets** المعروضة مع موديل شخص تُمثّل هوية ذلك الشخص؛ لا صور غير مرتبطة أوlandscapes بوصفها عينات تدريب. عند غياب أصل أوcrop نرسم fallback صريحًا بدل صورة توحي بارتباط غير موجود.

### Discover

أمثلة أوأقسام بصرية بعرض عمودين عند 390؛ عنوان قصير وتفسير محدد عند الحاجة. يمكن استعمال أمثلة pose/skeleton وظيفية بدل صور لا تتوفر. الأقسام القائمة: Poses / Outfits & colours / Group poses / Equipment / Marks؛ Body areas يظهر كأداة مشروطة بقدرتها وحدودها، و experimental grouping يظهر فقط بحالة تفعيله الصحيحة. لا icon wall ملون.

نتائج body-based search تحافظ على body crop وال reference ومعيار التشابه ومدخل Open original. لا نستبدلها بشبكة صور كاملة تفقد أي جسم قورن. نتائج group/equipment صور فقط. العناصر غير المعايرة لا تظهر كفلاتر مؤكدة.

### Studio

ثلاثة مداخل أدوات واضحة بصفتها rows أو sections، وليست مجموعة كروت ضخمة: Reface، Restyle، Character LoRA. تليها Models / Datasets / Results ومتابعة المهام. قائمة **Trained models** تحتوي الموديلات المستوردة فقط. مهام التدريب الجارية أوالمتوقفة أوالفاشلة تظهر في **Training tasks** مستقل. كل model row يحمل cover اختياري 48–64، اسمًا، مالكًا أو base عند الحاجة، ونوع/حالة حقيقية. مشاركة الموديل في More واضحة؛ Dataset ليس model و Saved identity ليس model.

## 7. العارض ولوحة الصورة

الـviewer على canvas مظلمة في Light/Dark. الصورة fit داخل مساحة العرض، بدون card أو shadow أو corner radius. إخفاء الأدوات بنقرة لا يغير الصورة أو zoom. الـAppBar ارتفاعه 56، وأيقوناته داخل targets48 على surface داكنة أو scrim محلي؛ لا نص أبيض فوق صورة غير معروفة التباين.

Toolbar سفلي 72 حد أدنى فوق system inset، بأفعال targets48: **Details / Tools / Lens**. لكل فعل label، و More في الأعلى لباقي الأفعال. share/save أوعمليات الأصل تظهر حيث يدعمها السلوك الحالي. لا NavigationBar رئيسية داخل العارض.

| حالة اللوحة | الهندسة المرجعية | المحتوى |
|---|---|---|
| Closed | الصورة كاملة في المساحة المتاحة مع toolbar | Details ظاهر؛ لا صف أشخاص دائم يقلل مساحة الصورة |
| Summary | نحو 44% من الارتفاع المتاح؛ بحد أقصى 360 في مرجع 390×844 | handle، عنوان Details، People in this photo، و context قصير |
| Expanded | حتى 90% من الارتفاع المتاح، مع احترام status/safe area | تفاصيل قابلة للتمرير مع close واضح؛ لا sheet داخل sheet |

النسب تصف snap positions، وليست ارتفاعات إجبارية. عند text scale1.8–2.0 أو landscape تفتح Details شبه كاملة أوكصفحة كاملة، بدل ضغط المحتوى. يتمرر expanded content، ولا يختفي آخر فعل خلف gesture bar.

- السحب لأعلى من طرف العارض السفلي أو Details يفتح اللوحة؛ زر Details بديل واضح. لا يتنافس السحب مع pinch/pan عندما تكون الصورة مكبرة.
- السحب أفقيًا عند fit ينتقل بين عناصر نفس folder/person/search. عند zoom أكبر من fit يتحرك المحتوى، ولا يقفز إلى صورة تالية.
- السحب لأسفل من handle يقلص اللوحة؛ التمرير داخل المحتوى لا يسحبها قبل وصوله للبداية. Back يغلق اللوحة، ثم يرجع للمصدر.
- فتح Person من اللوحة ثم Back يعيد نفس media وسياق panel والشخص المحدد عند انطباقه.
- الأشخاص أول قسم. الضغط على known person يفتح ملفه؛ Unknown يحمل Who is this? و Assign واضحًا. اختيار target أوزر context منفصل عن فتح ملف الشخص.
- الصورة الجماعية لا تختار شخصًا عشوائيًا. أدوات الشخص وموديلاته تعرض اسمه ومعاينته. الأداة تميز **Target person** عن **Source identity**.
- ترتيب expanded: People → Selected person/context → Tools → Models for [name] → Related results → File & analysis. العلاقات غير المحفوظة لا تُملأ بالتخمين.
- Detection markers مخفية افتراضيًا. Show detections يكشفها. هدف المراجعة المحدد له إطار 2 مع halo متباين و label؛ قد تُعتّم بقية الصورة في المراجعة فقط. إحداثيات العلامة تتبع الظهور الفعلي والإطار الصحيح.
- الفيديو يحتفظ بـplay/pause و seek والتوقيت والإطارات المحللة. **People in this frame** تختلف عن **People in this video**. معدات و group matching الصور لا تبدو كأنها تدعم الفيديو.

## 8. ملف الشخص

Header مضغوط داخل scroll: غلاف 64×64، اسم 22، metadata12، و More target48. لا portrait hero يطرد أول صف صور. توسيع الغلاف متاح بالزر المشترك. تحته tabs48 حد أدنى: **Media / Identity / Models**، و Review notice مختصر عند الحاجة.

| Tab | تركيب المحتوى | الأفعال |
|---|---|---|
| Media | شبكة الصور والفيديوهات الأصلية مع filter مختصر | فتح العارض في سياق الشخص والفلاتر المدعومة |
| Identity | مداخل ظاهرة: Faces / Bodies / Saved identities / Marks، ثم محتوى القسم | التصحيح، تحديد وجوه، أغلفة، مرجع، مشابه، وعلامات؛ لا تدفن الأقسام كلها في overflow |
| Models | Trained models المستوردة؛ ثم Training tasks مستقل، و Datasets | Open model / Generate images / Build dataset؛ و Share model من More |

Review يفتح من notice ومن Person tools حتى إذا كان العدد صفرًا. More منظم بعناوين **Organize / Matching & corrections / Photos & export / Remove**. العمليات تحافظ على نطاقها: حذف grouping ليس حذف original. تنظيم الملفات فعل مستقل صريح مع معاينة الخطة. People/Characters لا تغيران ما تقبله الأدوات من هويات.

## 9. الفورم والأدوات والمهام والنتائج

### Tool / dataset / training forms

عمود واحد بحواف 20 ومسافات 24 بين المجموعات. Context صغير في الأعلى يحدد المصدر والشخص والموديل إن وجد. preview واحد مفيد بعرض المحتوى وحد ارتفاع 220 بالمرجع، مع توسيع؛ لا نكرر نفس الصورة داخل عدة cards.

Reface يعرض خطوة واحدة من **ثلاث خطوات**: **Target → Identity → Review / options**، مع **Step n of 3** للمسار المعتاد. المثال في خطوة الهوية يحمل **2 of 3**. Source identity و Target person مسميان صراحة. في مسار DFM المدعوم الذي يوفر الهوية من الموديل، يُتجاوز اختيار Source identity المنفصل ولا نفرض مصدرًا وهميًا؛ تراجع الشاشة الهدف والموديل والخيارات، وتوضح المراحل الفعلية لهذا المسار. تحتفظ خطوات الفورم بالاختيارات الحالية. لا تظهر **Draft saved** بعد مغادرة الشاشة إذا لم توجد ميزة حفظ فعلية. Restyle و Generation يعرضان prompt والمراجع والمعلمات المتاحة؛ التفاصيل التقنية داخل Advanced options. Dataset editor يُظهر العدد المشمول والحد الأدنى الحقيقي، و captions و include/exclude والتصدير.

Sticky action واضح: **Next / Create / Start training / Generate images** حسب المرحلة. عند إرسال job لا يتكرر الإرسال. validation قرب الحقل، و summary قصير عند فشل الإرسال. غياب model أو offline له سبب وإجراء مناسب مثل Connect PC، دون مسح الاختيارات.

### Activity / job

Activity يجمع الفحص والوظائف مع أنواع واضحة؛ لا تسمى كل المراحل Uploading. مجموعات المهام الحالية محفوظة: **In progress / Queued / Paused / Failed / Completed**. الصف يعرض thumbnail48 ونوع العملية والمرحلة والتقدم إن كان معلومًا. job detail يعرض phase و progress و ETA المقاسة وسجل النشاط. الأفعال **Pause / Resume / Retry / Open result** تتبع الحالة، ولا تظهر كلها مفعلة معًا. الإيقاف اليدوي لا يُلغى تلقائيًا.

### Result

النتيجة هي الصورة الأكبر، مع **Before / After** أوالمقارنة الفعلية، ودعم الفيديو حيث ينطبق. Source / Person / Model روابط فقط عند وجود علاقة موثوقة. **Save to gallery** و**Share** أفعال صريحة، مع Favorite و More. نتيجة Dataset/Model تفتح artifact المناسب. نسخة المصدر الخاصة لا تسمى ملف الهاتف الأصلي إذا فُقد الأصل.

## 10. الحالات والرسائل والخصوصية

| الحالة | ما يراه المستخدم | الإجراء |
|---|---|---|
| أول دخول / إذن صور | شرح من سطرين؛ معاينة بسيطة لا تدعي عرض صور المستخدم | Allow photos؛ ربط PC لاحقًا |
| Limited access | حالة inline واضحة فوق الصور المتاحة | Manage access |
| Permission denied | سبب محدد؛ لا نقول إنه لا توجد صور | Allow photos أو Open settings حسب الحالة |
| Loading | placeholder بهندسة القائمة أوالشبكة، دون وميض زخرفي | إبقاء المحتوى المحفوظ المتاح |
| Empty library | لا وسائط متاحة بالفعل | الوصول أواختيار مصدر بحسب السبب |
| No filter results | معيار البحث ظاهر | Clear filters |
| Not analyzed | الصورة تفتح طبيعيًا، و Details تشرح غياب معلومات الأشخاص | Analyze photo وطلب PC عند الحاجة |
| No people found | نتيجة تحليل محددة وليست خطأ تحميل | Show detections أو Analyze again حيث يدعم |
| PC offline / busy / revoked | local content متاح؛ السبب قريب من الفعل المتأثر | Connect PC / View activity / Pair again حسب السبب |
| Missing model file | اسم model مع File unavailable؛ لا جاهزية زائفة | الاستعادة المدعومة أواختيار model آخر |
| Missing original | Saved crop أو Saved source copy باسمهما الحقيقي | فتح البديل المتاح دون ادعاء استرجاع الأصل |
| Failed job / load | رسالة مباشرة مع المحتوى المحفوظ | Retry؛ لا تحويل الفشل إلى قائمة فارغة |
| Destructive operation | وصف نوع البيانات والأثر والتأكيد الحالي | Cancel / Remove / Delete حسب النطاق |
| App lock | قفل منفصل قبل أي thumbnail خاص | Android authentication الحالية |

Snackbar للنجاح القصير أو Undo. الأخطاء التي تمنع التقدم inline ولا تختفي بعد ثوانٍ. لا Lens أومشاركة تلقائية. Results خاصة حتى يختار المستخدم Save to gallery أو Share. Backup يوضح التشفير والاستعادة ولا يوحي بأنه يحفظ كل صور الهاتف الأصلية.

## 11. النص الكبير والشاشات الضيقة والحركة

- مراجعة عند 320dp مع text scale1.8 و 2.0، و Keyboard مفتوحة، و Light/Dark، وأسماء أشخاص وموديلات طويلة، و landscape، وصلاحية صور محدودة.
- لا fixed height لصف عنوانه أووصفه متغير. قياسات الجدول حدود دنيا؛ targets48 والأزرار 52 لا تنكمش في dense layout.
- الصور تبقى صورية. عدد أعمدة People/Folders/Discover يقل عند ضيق caption أوالنص. labels أسفل NavigationBar تبقى مقروءة؛ ارتفاع bar يمكن أن يزيد إلى 104 أوأكثر عند الحاجة. الأهداف الأربعة لا تتداخل.
- local tabs تصبح scrollable عند الحاجة بدل تصغير الخط أوإخفاء الاختيار. لا carousels متداخلة للمحتوى الأساسي القابل للعرض عموديًا.
- scroll content يأخذ bottom padding مساويًا للـfixed bar مع safe inset. Keyboard ترفع شريط الإجراء أوتتيح scroll واضحًا، ولا تغطي الحقل أوالخطأ. Hardware Back يتبع سلوك النظام لإغلاق Keyboard والطبقات.
- screen reader يقرأ اسم الصورة/الشخص، الفيديو والوقت، selected state، والحالة. الأيقونة المستقلة لها accessible name. التوسيع والضغط المطول والسحب لها بدائل مرئية.
- Motion وظيفية فقط: sheet وانتقالات Android قابلة للمقاطعة. 180–300ms مرجع للتنقلات البسيطة، وليس للسحب المتبع للإصبع. احترام reduce motion؛ لا stagger للصور، ولا parallax أو loops. لا يؤخر animation ظهور المحتوى أوتنفيذ الفعل.

## 12. ثمانية تراكيب أساسية للمسار الأول

هذه ثماني **compositions** مرجعية. الحالات البديلة تُرسم منفصلة بحجم مقروء، ولا تُضغط داخل phone واحد. هذه القائمة تخدم رسم atlas، ولا تحدد عدد الشاشات النهائي.

| رقم | التركيب | محتوى 390×844 والعلاقة بما يليه |
|---|---|---|
| 01 | Gallery · Photos | status24، header56، Photos/Folders48، date group44، grid أربعة أعمدة gap2، nav80 مع inset24. بلا dashboard. Folders يبدل العرض؛ الصورة تفتح 03. |
| 02 | Gallery · Folders / folder | حالتان منفصلتان: folders عمودان مع أغلفة 4:3 وأسماء وأعداد؛ ثم folder content بنفس photo grid و Back و Camera و More. الفتح لا يبدأ scan؛ الصورة تفتح 03. |
| 03 | Photo viewer + Details | closed تعرض الصورة fit و toolbar. summary/expanded تعرض People in this photo. المعروف يفتح 04، Tools يحفظ target، و Models for [name] يوضح المالك. |
| 04 | Person · Media | Back وغلاف 64 واسم، ثم Media/Identity/Models48، و Review notice عند الحاجة وشبكة originals. Identity لها حالة منفصلة بمداخل Faces/Bodies/Saved identities/Marks. Models تفتح 05. |
| 05 | Person · Models | نفس header المضغوط، Models selected؛ قائمة Trained models للموديلات المستوردة، وقسم Training tasks مستقل للجاري والمتوقف والفاشل، ثم Datasets و Build dataset. موديل جاهز يفتح 06؛ Share model في More. |
| 06 | Model details → Generate | حالتان منفصلتان: owner/model/base/availability و Generate images؛ ثم composer بموديل و prompt ومراجع و Advanced options وزر Generate images. لا نخلط أدوار المصدر والهدف. الإرسال يفتح 07. |
| 07 | Activity · Job detail | Back وعنوان العملية، context المصدر والموديل، phase و progress و ETA عند معرفتها، السجل، وإجراء يتبع الحالة. النجاح يفتح 08؛ offline/paused يحافظان على السياق. |
| 08 | Result detail | ناتج كبير fit، Before/After عند توفر المصدر، روابط source/person/model الموثوقة، Save to gallery و Share و Favorite و More. Back يحافظ على stack؛ Open source يرجع للأصل المرتبط إن وجد. |

باقي atlas يحتاج جذور People و Discover و Studio، و permission/connection، و review/merge/unsorted، و datasets/training، و bodies/poses/group/equipment/marks، و settings/storage/backup وكل حالات concept و screen inventory. الثمانية تراكيب لا تحل محل مصفوفة الحفاظ على الميزات.

## 13. ضوابط رسم ومراجعة كل شاشة

1. عنوان محدد ومدخل خروج أورجوع واضح؛ لا dead end.
2. أول محتوى مفيد ظاهر عند 390×844 دون تمرير إن أمكن. الصور أكبر عنصر في شاشات المكتبة والعرض.
3. فعل أساسي واحد لكل مرحلة، مع مكان معلوم لكل الأفعال الثانوية.
4. كل زر له وجهة أوحالة موثقة. ما ليس موجودًا حاليًا يسمى proposal، ولا يعرض كقدرة جاهزة.
5. مراجعة بصرية للـLight/Dark والنص الكبير و insets. المواصفات لا تعني اختبار Android فعليًا.
6. لكل surface حالات loading/empty/error/permission/offline/missing حيث تنطبق. كل عملية تحترم نطاقها والخصوصية والتصحيحات المحفوظة.
7. تدقيق الهوية في الصور: كل Person media tile يحتوي الشخص، وكل model/dataset preview يعرض هويته، و Training tasks منفصلة عن Trained models. تدقيق Reface: ثلاث خطوات متسقة Target → Identity → Review / options، مع الاستثناء المدعوم لمسار DFM.

هذه الوثيقة تعرف لغة الرسم وتراكيبه فقط. لم تتغير ملفات Flutter أو API أوالبيانات، ولم يُشغل build أواختبار أوجهاز ضمن هذا التسليم.

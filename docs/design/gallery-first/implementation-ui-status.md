# Gallery-first UI implementation status

Gallery, People, Discover and Studio are retained navigation roots. Gallery pages through native MediaStore photos and folders before pairing, groups photos by date and registers loaded assets as browse-only when opening a viewer. Viewer paging carries the collection order and requests further pages lazily. Limited photo access has a management action; database analysis filters explicitly describe their indexed-media scope. Folder analysis uses a scoped pass without replacing saved scan sources, and active or paused work remains accessible.

The viewer uses a dark canvas, explicit share, tools and details, initially hidden detections, zoom-aware paging, swipe-up details, double-tap zoom and a labeled thumbnail fallback. Person-specific actions, models and related results use stored relationships. Contextual Reface and Restyle use the selected photo/detection with conservative fresh-face matching; target persons are never assigned as source identities. Dataset and generation forms accept contextual photos. Studio jobs persist verified media, identity, target, model, dataset and reference context locally; older jobs are not given invented links. Result deletion confirmation lists affected artifacts, and Save and Share are separate actions.

Person profiles start with original media and expose faces, bodies, suggestions, saved source identities, marks, trained models, training tasks and datasets. Reface uses Target, Source identity and Review / options. Discover retains pose, outfit, group, equipment, marks and opt-in experimental capabilities. Activity links to dedicated analysis progress and existing video stages and pause/resume. Shared theme tokens use the approved palette.

Final verification: **861 Flutter tests passed**, **zero analyzer issues**. Thirteen actual synthetic widget captures were refreshed and inspected; see [implementation report](implementation-report-2026-11-01.md). The captures include 390×844 screens and a 320 dp dark, large-text Discover screen. Physical-device, native permission/share and performance acceptance remain unverified; no APK build or installation was performed.

## Inventory coverage audit

This is a source audit, not device acceptance. “Partial” identifies material differences from the approved surface, even when the underlying feature remains reachable.

| # | Surface | Existing implementation / route | Coverage |
|---:|---|---|---|
| 1 | welcome-gallery | Direct Gallery startup | Implemented as a permission introduction before first access |
| 2 | media-permission | NativeGallery / photo_manager | Implemented with explanation, denied and limited-access states |
| 3 | gallery-photos | LibraryScreen / NativeGallery | Implemented with native paging, dates and agreed filters |
| 4 | gallery-folders | GalleryFolders | Implemented |
| 5 | folder-media | _FolderScreen / NativeGallery | Implemented with scoped analysis, count and type filter |
| 6 | gallery-filters | LibraryScreen | Implemented as a sheet; indexed-media scope is disclosed |
| 7 | photo-viewer | MediaScreen | Implemented with zoom, space-reclaiming chrome and labeled preview fallback |
| 8 | video-viewer | VideoMediaView | Implemented with frame/video people distinguished and explicit target choice |
| 9 | media-details | MediaScreen details sheet | Implemented with selected target, person tools, models, results and native filename/folder when available |
| 10 | target-picker | MediaScreen detection actions / Reface target step | Implemented through explicit highlighted selection and detection actions |
| 11 | detection-actions | MediaScreen._boxMenu | Implemented with existing corrections and body actions |
| 12 | image-preview | ImagePreviewScreen | Implemented |
| 13 | discover-home | DiscoverScreen | Implemented compact entries with available body crops, pose/group fallbacks and capability routes |
| 14 | discover-bodies | BodiesScreen | Implemented |
| 15 | discover-categories | _CategoryList | Implemented |
| 16 | category-editor | body_naming.dart | Implemented |
| 17 | similarity-results | BodiesScreen / mark matching | Implemented |
| 18 | group-poses | GroupPosesTab and group screens | Implemented |
| 19 | equipment-browser | EquipmentTab | Implemented |
| 20 | equipment-editor | EquipmentPhotoScreen | Implemented |
| 21 | body-areas | BodyAreasTab | Implemented; grouping remains opt-in |
| 22 | people-collection | PeopleScreen | Implemented |
| 23 | unassigned-faces | UnsortedScreen / FaceGrid | Implemented |
| 24 | person-media | PersonDetailScreen Media | Implemented with original grid and media-type filter |
| 25 | person-identity | PersonDetailScreen Identity | Implemented via nested sections and marks entry |
| 26 | person-models | _PersonModels | Implemented with training CTA, identity thumbnails, model status and nonempty datasets, tasks and person-linked results |
| 27 | person-actions | person action sheet | Implemented |
| 28 | face-selection | FaceGrid / ActionFacePicker | Implemented |
| 29 | person-assignment | pickPerson / resolveChoice | Implemented |
| 30 | identity-merge | MergeScreen | Implemented with both identities’ impact counts and preservation confirmation |
| 31 | identity-groups | IdentityGroupsScreen | Implemented |
| 32 | organize-media | OrganizeMediaScreen | Implemented |
| 33 | training-export | training_export_dialog.dart | Implemented |
| 34 | person-marks | PersonMarksScreen | Implemented |
| 35 | mark-editor | showMarkTattoo | Implemented |
| 36 | quick-review | QuickReviewScreen | Implemented |
| 37 | review-hub | ReviewScreen | Implemented |
| 38 | album-review | AlbumReviewScreen | Implemented |
| 39 | review-comparison | ReviewMediaViewer | Implemented |
| 40 | studio-home | StudioScreen | Implemented; model and dataset entries share library |
| 41 | reface-target | RefaceScreen step 1 | Implemented with conservative photo matching and explicit video target choice |
| 42 | reface-source | RefaceScreen step 2 | Implemented; source and target kept separate |
| 43 | reface-options | RefaceScreen step 3 | Implemented with advanced controls collapsed in review |
| 44 | identity-set-editor | _IdentitySetEditor | Implemented atomic saved identity editor |
| 45 | restyle | RestyleScreen | Implemented with contextual photo and target |
| 46 | training-library | LoraScreen | Implemented with dataset owner/count, tasks and model status |
| 47 | dataset-build | DatasetBuildScreen | Implemented contextual input and removal |
| 48 | dataset-editor | DatasetScreen | Implemented |
| 49 | lora-training | LoraTrainScreen | Implemented |
| 50 | model-details | ModelDetailScreen | Implemented with availability, actions and grouped verified dataset/job/result links |
| 51 | lora-generate | LoraGenerateScreen | Implemented with explicit model and optional photo reference |
| 52 | activity-center | JobsScreen | Implemented with scan progress summary and grouped jobs |
| 53 | scan-details | RunningScanScreen / ScanProgressCard | Implemented stages, scope, failed-item list and queue-only retry |
| 54 | job-details | JobDetailScreen | Implemented with verified context links |
| 55 | results-gallery | ResultsScreen | Implemented |
| 56 | result-viewer | ResultDetailScreen | Implemented with context/job links, missing-source label and artifact-aware deletion |
| 57 | analysis-sources | SourcesScreen | Implemented with source selection, settings and direct folder browse |
| 58 | analysis-settings | SourcesScreen / SettingsScreen | Implemented across two existing screens |
| 59 | analyze-single | AnalyzeScreen | Implemented |
| 60 | library-insights | InsightsScreen | Implemented |
| 61 | settings-home | SettingsScreen | Implemented |
| 62 | pc-connection | ConnectionScreen / ResourcePanel | Implemented with pairing, diagnostics and resource readiness |
| 63 | pair-qr | QrScanScreen | Implemented |
| 64 | pair-manual | ManualPairScreen | Implemented |
| 65 | background-settings | BackgroundScreen | Implemented |
| 66 | storage-settings | StorageScreen | Implemented |
| 67 | backup-restore | BackupScreen | Implemented |
| 68 | app-lock | AppLockGate / SettingsScreen | Implemented |

The “Implemented” entries identify current routes and actions, not proof that every visual detail or error state matches the concept. No APK build, installation or physical-device acceptance was performed in this UI session.

## User-named Actions extension

The shared Actions catalog is reachable from Discover, person profiles and photo/video Tools. A user chooses analyzed media, selects the participating people and names an activity or adds an example to an existing name. Photo examples compare spatial pose configurations; video examples use a chosen segment and temporal pose samples. Results show source media, timestamps for video, similarity and review state, and offer explicit accept/reject with participant, media and status filters. Labels describe events in media, not personal attributes. Missing usable poses are disclosed; older video analysis may require a rescan, and very fast motion between sampled frames is not captured.

Two focused UI tests passed for photo example creation and explicit suggestion review/filter controls. The refreshed opt-in previews include the synthetic catalog and action detail; the final combined suite passed 861 tests. No device acceptance is implied.

People and characters now share the People screen and profile, with an in-place kind filter and the same Actions, marks, body and Studio entry points. Dataset and Reface source pickers include both kinds; Reface reports a source/PC embedding-model mismatch and retains model compatibility validation. Focused People, character, Studio, Actions and identity-group tests passed (24), and a character Reface mismatch regression passed separately. Grouping and identity matching still respect the underlying embedding model spaces.

The shared collection defaults to All types. People / Anime Characters are in-place filters. Compatible mixed-kind bulk actions remain available; only operations that require a single embedding space are restricted. A combined review badge opens an explicit type choice with the same review workflow. The final source retains model validation before Reface submission.

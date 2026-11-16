# Anime face recovery — 2026-11-16

The source now offers Photo viewer → Detect → Anime face → Select face area → Scan this area → Confirm anime face → Save & Apply. The app must be rebuilt and the PC Mobile API restarted to use this change. Neither operation was performed in this task.

## Behaviour

- Illustrated-source analysis keeps its original whole-image pass and examines up to nine overlapping detail windows on images larger than 960 pixels. It merges overlapping hits and ignores fragments touching internal window edges. An optional detail-pass failure returns the successful whole-image detections. Existing candidate/acceptance scores, minimum face geometry, real-face vetoes, wrist/pose checks and background filtering remain in place. Ordinary mixed/photo sources retain the original detector pass. No scan version change or automatic library requeue was introduced.
- The explicit anime-face action uses the existing isolated scan worker. It scans the selected area with the anime model and extracts the existing 768-dimensional CCIP identity from the same portrait context as automatic character analysis. A miss retains the selected box, has detector score zero and is clearly described as a manual confirmation before saving. A full-image request never invents a face. Missing models and invalid identity output are errors.
- Selection uses a separate, unzoomed view of exactly the image bytes uploaded to the PC. The ROI is normalized against the fitted image, excluding surrounding blank space. The viewer requests up to 2560 pixels on the longest side. The new action is for photos; existing targeted video tools retain their scope.
- Saving validates model, vector, crop and bounds; writes the character face, crop, detection and per-face kind correction in a transaction; and refuses overlapping existing face boxes. An optional **new character name** creates a character identity. Leaving it blank leaves the face unassigned. A manually supplied box receives quality 0.70 as explicit user evidence, while its detector confidence remains zero; this is a heuristic, not a calibrated probability.
- Undo removes this addition and its crop/correction. A newly created identity is removed only while it has no remaining faces or bodies. Save errors stay visible in the confirmation sheet for retry. A later redetection preserves explicit face corrections even when the detector misses them, and a refined hit reuses an explicitly marked character face instead of adding another row at the same location.
- API: adds target_kind=anime_face, optional CCIP/crop/manual fields and a shared fixture. Other target kinds retain their wire format. Normalized ROI bounds now reject nonfinite/out-of-image/empty selections before inference.

## Actual verification

Source wiring, delimiter balance of 26 affected Python/Dart files, and fixture JSON/base64 were checked through in-process file tools. The fixture contains 3072 bytes of finite unit CCIP float32 values and a JPEG header. These are structural checks, not a Python parser, Dart analyzer or runtime test.

New/extended regressions cover scale recovery, duplicate suppression and tile limits, unchanged ordinary-photo routing, ROI coordinate mapping, manual misses, missing/invalid embeddings, request bounds, isolated worker transport/errors, atomic save/rollback/undo, character/human separation, repeated saves, accurate selection fitting and survival across redetection.

**Python/Flutter suites, formatting, static analysis, contract validator, APK build, live GPU accuracy/latency and actual-device acceptance were not run.** The standing terminal rule in [r.md](../the%20app/.agent/rules/r.md) requires commands to be supplied for the user to execute. Existing uncommitted work was preserved. No installed model, dependency, CUDA environment, live server, phone, real library, queue or checkpoint was changed. Actual recall/precision and the extra scan time remain unmeasured. Existing mixed-scene and false-wrist regressions must pass before deployment.

## User-run PowerShell validation

Run the PC suites from an empty scratch directory so importing desktop storage cannot read the real library. This selection excludes the existing test_detector_with_model test, which would load installed GPU models.

~~~powershell
$galleryApp = 'D:\AndroidScan\gallary\the app'
$galleryPython = Join-Path $galleryApp 'venv\Scripts\python.exe'
$galleryScratch = Join-Path $env:TEMP ('gallery-anime-check-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $galleryScratch | Out-Null
$galleryPreviousPythonPath = $env:PYTHONPATH
Push-Location $galleryScratch
try {
  $env:PYTHONPATH = $galleryApp
  & $galleryPython -c @'
import sys, unittest
names = ['test_anime_detector', 'test_targeted_anime', 'test_targeted_analysis',
         'test_character_detection', 'test_mobile_scan_worker', 'test_analysis',
         'test_mobile_api_contract', 'test_mobile_stateless']
def cases(suite):
    for item in suite:
        if isinstance(item, unittest.TestSuite):
            yield from cases(item)
        else:
            yield item
loaded = unittest.defaultTestLoader.loadTestsFromNames(names)
suite = unittest.TestSuite(t for t in cases(loaded) if not t.id().endswith('.test_detector_with_model'))
result = unittest.TextTestRunner(verbosity=2).run(suite)
sys.exit(0 if result.wasSuccessful() else 1)
'@
  if ($LASTEXITCODE -ne 0) { throw 'PC regression tests failed' }
  & $galleryPython (Join-Path $galleryApp 'mobile_api\contract\validate_contract.py')
  if ($LASTEXITCODE -ne 0) { throw 'API contract validation failed' }
} finally {
  Pop-Location
  $env:PYTHONPATH = $galleryPreviousPythonPath
}
~~~

Then validate Flutter from mobile:

~~~powershell
Set-Location 'D:\AndroidScan\gallary\mobile'
flutter test test/data/api/targeted_api_test.dart test/domain/corrections/targeted_detection_service_test.dart test/features/targeted_detect_ux_test.dart test/features/roi_selection_overlay_test.dart test/domain/redetect_test.dart test/domain/character_parity_test.dart test/domain/photo_result_store_test.dart test/features/viewer_gestures_test.dart test/contract_fixtures_test.dart
flutter analyze
~~~

Format only the changed Dart files if required. After the checks pass, build/install an updated APK and restart the PC API. Test an anime image that previously missed faces, a group illustration with small faces, an ordinary human photo, and a mixed photo with a drawing/poster. Confirm the selected crop, verify Save and Undo, and redetect the photo once to verify retention. No accuracy claim should be made until these examples have been checked.

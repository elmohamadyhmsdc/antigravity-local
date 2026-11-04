// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get imageExpand => 'Expand image';

  @override
  String get imagePreviewTitle => 'Image preview';

  @override
  String get imageResetZoom => 'Fit image to screen';

  @override
  String get imageUnavailable => 'This image is unavailable.';

  @override
  String get peopleCharacters => 'Characters';

  @override
  String get peopleSearchCharacters => 'Search characters';

  @override
  String get peopleOrganize => 'Organize';

  @override
  String get peopleMatching => 'Matching & corrections';

  @override
  String get peopleTools => 'Photos, export & tools';

  @override
  String get reviewPhotos => 'Review photos';

  @override
  String get reviewFullPhoto => 'Show full photo';

  @override
  String get reviewCrop => 'Show close-up';

  @override
  String get reviewNoPhotos => 'No photos are available for this suggestion.';

  @override
  String get reviewFaceHighlighted => 'Review the face inside the yellow box';

  @override
  String get reviewBodyHighlighted => 'Review the body inside the yellow box';

  @override
  String get reviewViewerHint =>
      'Swipe to see every photo. Pinch a photo to zoom. Use the crop button for a close-up.';

  @override
  String get reviewVideoHint =>
      'The video opens at the highlighted sample. Use the crop button for a close-up, or move to the next photo.';

  @override
  String get reviewOriginalMissing =>
      'The original is unavailable. This is the saved crop only.';

  @override
  String get reviewPreviousPhoto => 'Previous photo';

  @override
  String get reviewNextPhoto => 'Next photo';

  @override
  String get reviewFace => 'This face';

  @override
  String get reviewBody => 'This body';

  @override
  String reviewViewAll(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'View all $count photos',
      one: 'View photo',
    );
    return '$_temp0';
  }

  @override
  String reviewMatchQuestion(String name) {
    return 'Is this $name?';
  }

  @override
  String get reviewGroupQuestion => 'Are these the same person?';

  @override
  String get reviewMatchHelp =>
      'Open a photo to inspect it. Use the checkboxes to choose which faces to add or reject.';

  @override
  String get reviewGroupHelp =>
      'Review every photo and uncheck any face that does not belong. Then create a person or add the selected faces to someone you know.';

  @override
  String reviewOutfitQuestion(String name) {
    return 'Does this body belong to $name?';
  }

  @override
  String get reviewOutfitHelp =>
      'Check the highlighted body in the original and compare the identity evidence before deciding. Similar clothing alone is not an identity match.';

  @override
  String reviewYesPerson(String name) {
    return 'Yes, $name';
  }

  @override
  String get reviewNotPerson => 'No, someone else';

  @override
  String get reviewIncludeFace => 'Include this face';

  @override
  String get reviewReferencePhotos => 'Known photos';

  @override
  String peopleAction(String action) {
    String _temp0 = intl.Intl.selectLogic(action, {
      'selection': 'Select multiple',
      'open': 'Open person',
      'merge': 'Merge with…',
      'rename': 'Rename',
      'hide': 'Hide',
      'show': 'Show again',
      'pin': 'Pin to top',
      'unpin': 'Unpin',
      'favorite': 'Add to favorites',
      'unfavorite': 'Remove from favorites',
      'media': 'Photos and videos',
      'add': 'Add faces…',
      'split': 'Split into new person…',
      'suggestions': 'Review match suggestions',
      'distinct': 'Different from…',
      'lock': 'Lock automatic matching',
      'unlock': 'Unlock automatic matching',
      'studio': 'Use in Studio',
      'export': 'Export / share…',
      'details': 'Details',
      'cover': 'Change cover…',
      'bestCover': 'Choose best cover automatically',
      'chooseCover': 'Choose cover face…',
      'deletePerson': 'Delete person grouping',
      'dissolve': 'Dissolve person (faces go back to be sorted)',
      'original': 'Open original',
      'assign': 'Assign / move to person…',
      'create': 'Create new person…',
      'reject': 'Not this person',
      'remove': 'Remove from person…',
      'someoneElse': 'This is someone else',
      'notAFace': 'Not a face',
      'moveTo': 'Move to…',
      'unassign': 'Remove assignment',
      'similar': 'Find similar faces',
      'save': 'Save crop to gallery',
      'deleteFace': 'Delete detection',
      'ignore': 'Not a face / ignore detection',
      'hidden': 'Hidden',
      'all': 'All',
      'favorites': 'Favorites',
      'pinned': 'Pinned',
      'invert': 'Invert selection',
      'more': 'More actions',
      'done': 'Done',
      'undo': 'Undo',
      'updated': 'Updated',
      'noResults': 'No items in this view',
      'exportCrops': 'Face crops and details',
      'exportOriginals': 'Face crops and original media',
      'lockedNote':
          'Automatic matching cannot add faces or change derived body links for a locked person. Manual corrections remain available.',
      'dissolveNote':
          'Remove these people and send every face and body back to be sorted again: grouping and Review will consider them as if they were new. Nothing is hidden. Original photos and videos are kept.',
      'deletePersonNote':
          'Remove these person groupings and return their faces to Unsorted. Original photos and videos are kept.',
      'deleteFaceNote':
          'Remove these detections and their private crops. Rescanning will not recreate them. Original photos and videos are kept.',
      'mergeNote':
          'All selected people will be merged into the chosen person. Review the resulting name and cover before confirming.',
      'similarNote':
          'Similarity is a suggestion. Open an original or assign selected faces after checking them.',
      'emptyExport': 'No readable files were available to export.',
      'redetect': 'Detect faces / bodies again…',
      'toCharacters': 'Move to Characters',
      'toPeople': 'Move to People',
      'kindMoveNote':
          'The PC measures them again with the other model, so their files are scanned again first. Names are kept; until the scan finishes they are not shown.',
      'other': 'More actions',
    });
    return '$_temp0';
  }

  @override
  String kindMoved(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count files are scanned again',
      one: '1 file is scanned again',
      zero: 'Nothing to scan again',
    );
    return 'Moved. $_temp0.';
  }

  @override
  String get redetectTitle => 'Detect again';

  @override
  String get redetectNote =>
      'Looks harder than the scan: full resolution and lower thresholds, so small or partly hidden faces and bodies are found. The old boxes are replaced; names and decisions stay with the new box at the same place.';

  @override
  String get redetectFaces => 'Faces';

  @override
  String get redetectBodies => 'Bodies';

  @override
  String get redetectBoth => 'Faces and bodies';

  @override
  String redetectProgress(int done, int total) {
    return 'Detecting again… $done of $total photos';
  }

  @override
  String redetectDone(int faces, int bodies) {
    return 'Now $faces faces and $bodies bodies.';
  }

  @override
  String redetectVideosSkipped(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count videos were skipped: only photos can be detected again for now.',
      one: '1 video was skipped: only photos can be detected again for now.',
    );
    return '$_temp0';
  }

  @override
  String get boxIsCharacter => 'This is a character (drawn)';

  @override
  String get boxIsPerson => 'This is a real person';

  @override
  String get mediaKindTitle => 'Who is in this file?';

  @override
  String get mediaKindAuto => 'Decide automatically';

  @override
  String get mediaKindPeople => 'Real people only';

  @override
  String get mediaKindCharacters => 'Characters only (anime / cartoon)';

  @override
  String get mediaKindNote =>
      'Everything in the file is scanned again as you choose.';

  @override
  String peopleActionError(String reason) {
    return 'Could not complete the action: $reason';
  }

  @override
  String get videoOpening => 'Opening video…';

  @override
  String get videoLastRecorded =>
      'Last recorded progress · scan is not currently advancing';

  @override
  String get videoWaiting => 'Waiting for PC analysis…';

  @override
  String get videoVerifying => 'Verifying downloaded results…';

  @override
  String get videoFinishing => 'Finalizing video results…';

  @override
  String get videoStepPrepare => 'Prepare';

  @override
  String get videoStepUpload => 'Upload';

  @override
  String get videoStepAnalyze => 'Analyze';

  @override
  String get videoStepSave => 'Save';

  @override
  String get videoPrepareDetail =>
      'Reading the video on this phone and calculating its fingerprint before upload. Large videos take longer here.';

  @override
  String get videoUploadDetail =>
      'Sending the original video to your PC in resumable chunks. Analysis starts after the upload finishes.';

  @override
  String get videoUploadConfirming =>
      'Video bytes sent. Waiting for the PC to confirm the upload.';

  @override
  String get videoQueueDetail =>
      'The video request is on the PC. Waiting for the analysis worker to start or resume.';

  @override
  String get videoDecodeDetail =>
      'The PC is reading and decoding the next sampled frame.';

  @override
  String get videoInferenceDetail =>
      'The PC is detecting faces and people in the current sampled frame.';

  @override
  String get videoAnalyzeDetail =>
      'The PC is analyzing sampled frames. The video is still in progress even while new results are saved below.';

  @override
  String get videoDownloadDetail =>
      'Receiving the completed detections from your PC before saving them on this phone.';

  @override
  String get videoVerifyDetail =>
      'Checking the result file size and fingerprint before importing detections.';

  @override
  String get videoImportDetail =>
      'Saving verified detections and crops into this phone’s library.';

  @override
  String get videoFinishDetail =>
      'Finishing the result file and confirming the saved video. This can take a moment for large videos.';

  @override
  String videoStagePercent(int percent) {
    return '$percent% of this stage';
  }

  @override
  String get videoElapsed => 'Time on this video';

  @override
  String get videoFile => 'Video file';

  @override
  String get videoSource => 'Original video';

  @override
  String get videoStageElapsed => 'Time in this stage';

  @override
  String get videoBytesRead => 'Video data read';

  @override
  String get videoBytesSent => 'Video data sent';

  @override
  String get videoBytesReceived => 'Results received';

  @override
  String get videoTransferSpeed => 'Average transfer speed';

  @override
  String get videoStageRemaining => 'Estimated time left in this stage';

  @override
  String get videoMeasuring => 'Measuring…';

  @override
  String videoApproximate(String time) {
    return 'About $time';
  }

  @override
  String get videoPosition => 'Analyzed video position';

  @override
  String get videoSamplesAnalyzed => 'Samples processed (including skipped)';

  @override
  String get videoSampling => 'Sampling interval';

  @override
  String videoSamplingSeconds(String seconds) {
    return 'One frame every $seconds s';
  }

  @override
  String get videoLiveSaving =>
      'Available results are saved as the PC works. Counts below are for this video session.';

  @override
  String get videoSavedSamples => 'Samples saved on this phone';

  @override
  String get videoLiveDetections => 'New detections saved';

  @override
  String videoDetectionCounts(int faces, int bodies, int characters) {
    return '$faces faces · $bodies bodies · $characters characters';
  }

  @override
  String get videoSkippedSamples => 'Unreadable samples skipped';

  @override
  String get videoPcUpdate => 'Last PC response';

  @override
  String videoSecondsAgo(int seconds) {
    return '$seconds s ago';
  }

  @override
  String videoAwaitingUpdate(int seconds) {
    return 'No new progress for $seconds s. Waiting for the current operation to respond; you can pause the scan.';
  }

  @override
  String get videoLibraryProgress => 'Overall library progress';

  @override
  String scanItemsOf(int done, int total) {
    return '$done of $total items complete';
  }

  @override
  String get videoAdaptiveSampling => 'Automatic video sampling';

  @override
  String get videoAdaptiveSamplingHint =>
      'Short clips use closer samples; longer videos use wider intervals. About 0.5 s for a short clip and 5 s for a 40-minute video.';

  @override
  String get scanCurrentPhoto => 'Current photo';

  @override
  String get scanCurrentVideo => 'Current video frame';

  @override
  String get scanPreviewUnavailable => 'Preview unavailable';

  @override
  String get appTitle => 'Your Gallery';

  @override
  String get navHome => 'Home';

  @override
  String get navPeople => 'People';

  @override
  String get navLibrary => 'Library';

  @override
  String get navStudio => 'Studio';

  @override
  String get navJobs => 'Jobs';

  @override
  String get settings => 'Settings';

  @override
  String get cancel => 'Cancel';

  @override
  String get retry => 'Try again';

  @override
  String get back => 'Back';

  @override
  String comingInPhase(String phase) {
    return 'Coming in phase $phase';
  }

  @override
  String get peoplePlaceholder =>
      'Everyone found in your photos and videos, grouped by identity.';

  @override
  String get libraryPlaceholder =>
      'Your photos and videos, with who is in each one.';

  @override
  String get studioPlaceholder => 'Reface, Restyle and Character LoRA.';

  @override
  String get jobsPlaceholder =>
      'Running, queued, paused and finished GPU jobs.';

  @override
  String get settingsPlaceholder =>
      'Pairing, grouping strictness, scan defaults and app lock.';

  @override
  String get welcomeTitle => 'Connect to your PC';

  @override
  String get welcomeBody =>
      'Your Gallery does the heavy AI work on your Windows PC. Your photos, faces and results stay on this phone - the PC only computes.';

  @override
  String get welcomeSameWifi => 'Your phone and PC must be on the same Wi-Fi.';

  @override
  String get welcomeScan => 'Scan QR code';

  @override
  String get welcomeManual => 'Enter address manually';

  @override
  String get welcomeStep =>
      'On the PC, run run_mobile_api.bat. It opens a page with a QR code.';

  @override
  String get scanTitle => 'Scan the QR code';

  @override
  String get scanHint =>
      'Point the camera at the QR code on your PC\'s pairing page.';

  @override
  String get scanNotPairingCode => 'That is not a Your Gallery pairing code.';

  @override
  String get scanCameraDenied =>
      'Camera access is needed to scan the code. You can also enter the address manually.';

  @override
  String get scanEnterManually => 'Enter address manually';

  @override
  String get manualTitle => 'Enter the address';

  @override
  String get manualIntro =>
      'Type the address and pairing code shown on your PC\'s pairing page.';

  @override
  String get manualHostLabel => 'PC address';

  @override
  String get manualHostHint => '192.168.1.20';

  @override
  String get manualPortLabel => 'Port';

  @override
  String get manualCodeLabel => 'Pairing code';

  @override
  String get manualCodeHint => 'K7QM-3XRD';

  @override
  String get manualConnect => 'Connect';

  @override
  String get errHostEmpty => 'Enter the PC\'s address.';

  @override
  String get errHostInvalid => 'That is not a valid address.';

  @override
  String get errHostNotLan =>
      'The PC must be on your Wi-Fi (an address like 192.168.x.x or 10.x.x.x).';

  @override
  String get errPortInvalid => 'Enter a port between 1 and 65535.';

  @override
  String get errCodeInvalid =>
      'The code has 8 letters and digits, like K7QM-3XRD.';

  @override
  String get confirmFingerprintTitle => 'Is this your PC?';

  @override
  String get confirmFingerprintBody =>
      'Compare this fingerprint with the one on your PC\'s pairing page. Only continue if they are identical.';

  @override
  String get confirmFingerprintYes => 'They match - pair';

  @override
  String pairLinkTitle(String host) {
    return 'Pair with $host?';
  }

  @override
  String pairLinkBody(String host) {
    return 'A link asked this phone to pair with a PC at $host. Only continue if you started this on your own PC.';
  }

  @override
  String get pairLinkInvalid =>
      'That pairing link is not valid, or it does not point to a PC on your Wi-Fi.';

  @override
  String get pairLinkContinue => 'Pair';

  @override
  String pairingConnecting(String host) {
    return 'Connecting to $host…';
  }

  @override
  String get permissionsTitle => 'Permissions';

  @override
  String get permissionsIntro =>
      'Your Gallery asks only for what it needs. You can change these later in Android settings.';

  @override
  String get permMediaTitle => 'Photos and videos';

  @override
  String get permMediaWhy =>
      'To find faces in your library. Files are read in place and never copied or uploaded in full - only downscaled pictures are sent to your own PC.';

  @override
  String get permCameraTitle => 'Camera';

  @override
  String get permCameraWhy => 'Only to scan the pairing QR code.';

  @override
  String get permNotificationsTitle => 'Notifications';

  @override
  String get permNotificationsWhy =>
      'So you hear when a long job on your PC has finished.';

  @override
  String get permAllow => 'Allow';

  @override
  String get permGranted => 'Allowed';

  @override
  String get permBlocked => 'Blocked - open settings';

  @override
  String get permContinue => 'Continue';

  @override
  String get homeStatusChecking => 'Checking…';

  @override
  String homeStatusConnected(String name) {
    return '$name';
  }

  @override
  String homeStatusBusy(String name) {
    return '$name - busy';
  }

  @override
  String get homeStatusOffline => 'PC offline';

  @override
  String get homeStatusRevoked => 'Pairing revoked';

  @override
  String get homeStatusTooltip => 'Tap to check the connection';

  @override
  String homeBusyBanner(String job) {
    return 'Your PC\'s GPU is busy with a $job job.';
  }

  @override
  String get homeOfflineBanner =>
      'Cannot reach your PC. Is the server running and is this phone on the same Wi-Fi?';

  @override
  String get homeRevokedBanner =>
      'This phone was removed on the PC. Pair again to continue.';

  @override
  String get homePairAgain => 'Pair again';

  @override
  String get statPeople => 'People';

  @override
  String get statFaces => 'Faces';

  @override
  String get statPhotos => 'Photos';

  @override
  String get statVideos => 'Videos';

  @override
  String unsortedFaces(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count unsorted faces',
      one: '1 unsorted face',
      zero: 'No unsorted faces',
    );
    return '$_temp0';
  }

  @override
  String get emptyLibraryTitle => 'Your library is empty';

  @override
  String get emptyLibraryBody =>
      'Choose albums to scan and the people in your photos show up here. You can also test face detection on a single photo.';

  @override
  String get tryDetectionTitle => 'Detect faces in a photo';

  @override
  String get tryDetectionBody =>
      'Sends one downscaled photo to your PC and shows what it finds.';

  @override
  String get forgetPc => 'Forget this PC';

  @override
  String forgetPcTitle(String name) {
    return 'Forget $name?';
  }

  @override
  String get forgetPcBody =>
      'This phone will be unpaired. Everything in your library stays on the phone.';

  @override
  String get forgetPcConfirm => 'Forget';

  @override
  String get analyzeTitle => 'Detect faces';

  @override
  String get analyzePick => 'Choose a photo';

  @override
  String get analyzePickAnother => 'Choose another photo';

  @override
  String get analyzeIdle =>
      'Pick a photo from your gallery. It is downscaled and analysed on your PC; nothing is stored there.';

  @override
  String analyzing(String name) {
    return 'Analysing on $name…';
  }

  @override
  String analyzeFacesFound(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count faces found',
      one: '1 face found',
      zero: 'No faces found',
    );
    return '$_temp0';
  }

  @override
  String analyzeBodiesFound(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count bodies',
      one: '1 body',
      zero: 'no bodies',
    );
    return '$_temp0';
  }

  @override
  String analyzeSummary(
    String faces,
    String bodies,
    int width,
    int height,
    int ms,
  ) {
    return '$faces · $bodies · $width×$height · $ms ms';
  }

  @override
  String analyzeFaceTitle(int number) {
    return 'Face $number';
  }

  @override
  String analyzeFaceDetail(int pixels, String det) {
    return '$pixels px · detector $det';
  }

  @override
  String analyzeQuality(String tier, String score) {
    return '$tier $score';
  }

  @override
  String get analyzeMeetsGate => 'Would be saved';

  @override
  String get analyzeBelowGate => 'Too small or unclear - skipped';

  @override
  String get tierGreat => 'Great';

  @override
  String get tierGood => 'Good';

  @override
  String get tierFair => 'Fair';

  @override
  String get tierPoor => 'Poor';

  @override
  String get analyzeNoFaces => 'No faces were found in this photo.';

  @override
  String get gpuBusyMessage =>
      'Your PC\'s GPU is busy right now. Try again in a moment.';

  @override
  String get analyzeFailed => 'Analysis failed';

  @override
  String get startupErrorTitle => 'Your Gallery could not open its database';

  @override
  String get startupErrorBody =>
      'Your library is stored encrypted on this phone and could not be opened. Details:';

  @override
  String get accept => 'Accept';

  @override
  String acceptAllMatches(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count matches',
      one: '1 match',
    );
    return 'Accept all $_temp0';
  }

  @override
  String get acceptAllMatchesBody =>
      'Every suggested face is added to the person it looks like. You can still move faces afterwards.';

  @override
  String acceptAllOutfits(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count outfit matches',
      one: '1 outfit match',
    );
    return 'Accept all $_temp0';
  }

  @override
  String addFacesTo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count faces',
      one: '1 face',
    );
    return 'Add $_temp0';
  }

  @override
  String get addToPerson => 'Add to a person…';

  @override
  String get albumsHint =>
      'Choose the albums whose items should be scanned. Photos stay on this phone; only a downscaled copy of each is sent to your PC.';

  @override
  String get albumsTitle => 'Albums to scan';

  @override
  String get allPhotos => 'All photos';

  @override
  String get allowPhotoAccess => 'Allow photo access';

  @override
  String assignFacesTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count faces',
      one: '1 face',
    );
    return 'Move $_temp0 to…';
  }

  @override
  String get assignTo => 'Assign to…';

  @override
  String get backupDone => 'Backup created. Choose where to save it.';

  @override
  String backupFailed(String error) {
    return 'Backup problem: $error';
  }

  @override
  String get backupIntro =>
      'Your library, private results, datasets and trained LoRAs live on this phone. Export a backup to keep another copy; PC connections and active jobs are excluded.';

  @override
  String get backupKeepSafe =>
      'Backups are encrypted by default. Keep the password safe; it is never stored by the app. Older unencrypted backups can still be restored.';

  @override
  String backupLibrarySummary(int people, int faces, int photos) {
    return '$people people · $faces faces · $photos photos';
  }

  @override
  String get backupNow => 'Back up now';

  @override
  String get backupReminderBody =>
      'Your library exists only on this phone. Save a backup file somewhere safe.';

  @override
  String get backupReminderNever => 'You have never made a backup';

  @override
  String get backupReminderOld => 'Your last backup is more than 2 weeks old';

  @override
  String get backupSettingsHint => 'Save or restore your whole library';

  @override
  String get backupShareSubject => 'Your Gallery backup';

  @override
  String get backupStageCrops => 'Saving face pictures…';

  @override
  String get backupStageDatabase => 'Saving your library…';

  @override
  String get backupStageFinishing => 'Finishing…';

  @override
  String get backupStageRestoring => 'Restoring your library…';

  @override
  String get backupTitle => 'Backup & restore';

  @override
  String get backupWhatIsIncluded => 'What is in a backup';

  @override
  String get backupWhatIsIncludedBody =>
      'People, faces, body links, media records, corrections, grouping settings, saved identity sets, private results, datasets, captions and trained LoRAs. Your original gallery photos, PC connections and active jobs are excluded.';

  @override
  String get bodyBox => 'Body';

  @override
  String bodyLinkDetail(String method, int percent) {
    return '$method · $percent% sure';
  }

  @override
  String bodyLinkTitle(String person) {
    return 'Looks like $person';
  }

  @override
  String get chooseAlbums => 'Choose albums';

  @override
  String get chooseAlbumsFirst => 'Choose albums first';

  @override
  String get clearSelection => 'Clear selection';

  @override
  String get compare => 'Compare';

  @override
  String get coverChanged => 'Cover photo changed';

  @override
  String get create => 'Create';

  @override
  String createAllGroups(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count people',
      one: '1 person',
    );
    return 'Create $_temp0';
  }

  @override
  String get createPerson => 'Create person';

  @override
  String get delete => 'Delete';

  @override
  String get deleteFace => 'Delete this face';

  @override
  String get deleteFacesBody =>
      'The face pictures are removed from this phone. Your original photos are not touched.';

  @override
  String deleteFacesTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count faces',
      one: 'this face',
    );
    return 'Delete $_temp0?';
  }

  @override
  String get deletePerson => 'Delete person';

  @override
  String deletePersonBody(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Their $count faces become unsorted and stay out of automatic groups.',
      one: 'Their 1 face becomes unsorted and stays out of automatic groups.',
    );
    return '$_temp0 You can still assign them manually. Nothing else is deleted.';
  }

  @override
  String deletePersonTitle(String name) {
    return 'Delete $name?';
  }

  @override
  String get differentPeople => 'They are different people';

  @override
  String etaHours(int hours, int minutes) {
    return 'about $hours h $minutes min left';
  }

  @override
  String etaMinutes(int minutes) {
    return 'about $minutes min left';
  }

  @override
  String etaSeconds(int seconds) {
    return 'about $seconds s left';
  }

  @override
  String get faceBox => 'Face';

  @override
  String facesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count faces',
      one: '1 face',
      zero: 'No faces',
    );
    return '$_temp0';
  }

  @override
  String facesMoved(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count faces moved',
      one: '1 face moved',
    );
    return '$_temp0';
  }

  @override
  String facesRejected(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count faces removed from this person',
      one: '1 face removed from this person',
    );
    return '$_temp0';
  }

  @override
  String get filterAll => 'All';

  @override
  String get filterFailed => 'Failed';

  @override
  String get filterHasFaces => 'Has faces';

  @override
  String get filterNotScanned => 'Not scanned';

  @override
  String get filterPerson => 'Person';

  @override
  String get filterScanned => 'Scanned';

  @override
  String groupCardTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count faces',
      one: '1 face',
    );
    return 'New person? $_temp0';
  }

  @override
  String get hideBodies => 'Hide bodies';

  @override
  String get hideFaces => 'Hide faces';

  @override
  String keepPerson(String label) {
    return 'Keep $label';
  }

  @override
  String lastBackup(String date) {
    return 'Last backup: $date';
  }

  @override
  String get libraryEmptyBody =>
      'Scan your albums to find the faces in them. Your photos stay on this phone.';

  @override
  String get libraryEmptyTitle => 'No photos yet';

  @override
  String get linkManual => 'By hand';

  @override
  String get linkOutfit => 'Same outfit';

  @override
  String get linkWeakFace => 'Blurry face';

  @override
  String matchCardTitle(String person, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count faces look like them',
      one: '1 face looks like them',
    );
    return '$person · $_temp0';
  }

  @override
  String get merge => 'Merge';

  @override
  String mergeConfirmBody(String source, int count, String target) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count faces',
      one: '1 face',
    );
    return '$source ($_temp0) becomes part of $target, and $source disappears. You can still move faces back one by one.';
  }

  @override
  String get mergeConfirmTitle => 'Merge these people?';

  @override
  String mergeInto(String source, String target) {
    return 'Merge $source into $target';
  }

  @override
  String get mergeNotFlagged => 'Not flagged by your PC';

  @override
  String get mergeScoreHint => 'How alike your PC thinks the two people are';

  @override
  String get mergeTitle => 'Merge people';

  @override
  String get mergeWith => 'Merge with…';

  @override
  String mergedInto(String name) {
    return 'Merged into $name';
  }

  @override
  String needsReview(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count decisions need you',
      one: '1 decision needs you',
    );
    return '$_temp0';
  }

  @override
  String get neverBackedUp => 'No backup yet';

  @override
  String get newPerson => 'New person';

  @override
  String get noBodiesBody =>
      'Bodies are found next to faces and matched by outfit.';

  @override
  String get noBodiesTitle => 'No body shots yet';

  @override
  String get noFacesInPhoto => 'No faces were found in this photo.';

  @override
  String get noFacesYet => 'No faces yet';

  @override
  String get noPeopleBody =>
      'Scan your photos and the people in them show up here.';

  @override
  String get noPeopleTitle => 'No people yet';

  @override
  String get noPeopleYet => 'No people yet';

  @override
  String get noPhotoAccessBody =>
      'Your Gallery needs permission to read your photos before it can scan them.';

  @override
  String get noPhotoAccessTitle => 'No photo access';

  @override
  String get noPhotosMatch => 'No photos match these filters';

  @override
  String get noPhotosOfPerson => 'No photos of this person yet';

  @override
  String get noSuggestionsBody =>
      'Nothing needs your decision for this person right now.';

  @override
  String get noSuggestionsTitle => 'No suggestions';

  @override
  String get noUnsortedFaces => 'No unsorted faces';

  @override
  String get notAPerson => 'Not a person';

  @override
  String get notPaired => 'Not paired';

  @override
  String notPerson(String name) {
    return 'Not $name';
  }

  @override
  String get notScannedYet => 'This photo has not been scanned yet.';

  @override
  String notThem(int count) {
    return 'Not them ($count)';
  }

  @override
  String get notThisPerson => 'Not this person';

  @override
  String openPerson(String name) {
    return 'Open $name';
  }

  @override
  String get optionBodies => 'Find bodies';

  @override
  String get optionBodiesHint =>
      'Also detect people\'s bodies, so photos where a face is hidden can be matched by outfit.';

  @override
  String get optionImageSize => 'Picture size sent to your PC';

  @override
  String get optionImageSizeHint =>
      'Longest side. Bigger finds smaller faces but is slower.';

  @override
  String get outfitMatchesTitle => 'Same outfit';

  @override
  String get pause => 'Pause';

  @override
  String personFallbackName(int id) {
    return 'Person $id';
  }

  @override
  String get personGone => 'This person no longer exists.';

  @override
  String get personNameLabel => 'Name';

  @override
  String get personNameOptional => 'Optional';

  @override
  String get photoGone => 'Photo not found';

  @override
  String get photoGoneBody =>
      'The original is no longer on this phone. The faces found in it are still in your library.';

  @override
  String get photoTitle => 'Photo';

  @override
  String photosCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count photos',
      one: '1 photo',
    );
    return '$_temp0';
  }

  @override
  String get pickPersonTitle => 'Choose a person';

  @override
  String get possibleSamePerson => 'May be the same person';

  @override
  String qualityGateValue(String value) {
    return 'Minimum quality $value';
  }

  @override
  String get reject => 'Reject';

  @override
  String get rename => 'Rename';

  @override
  String get restore => 'Restore';

  @override
  String restoreConfirmBody(String date, int people, int faces, int photos) {
    return 'This replaces everything in the app with the backup from $date: $people people, $faces faces, $photos photos. Anything added since then is lost.';
  }

  @override
  String get restoreConfirmTitle => 'Replace your library?';

  @override
  String restoreDone(int people, int faces) {
    return 'Restored $people people and $faces faces.';
  }

  @override
  String get restoreFromBackup => 'Restore from a backup';

  @override
  String get resume => 'Resume';

  @override
  String reviewDecisions(int count) {
    return '$count to review';
  }

  @override
  String get reviewDuplicatesEmpty => 'No people look like duplicates';

  @override
  String get reviewGroupsEmpty => 'No new groups to review';

  @override
  String get reviewMatchesEmpty => 'No faces waiting to be matched';

  @override
  String get reviewOutfitsEmpty => 'No body identity matches to review';

  @override
  String reviewTabDuplicates(int count) {
    return 'Same person? ($count)';
  }

  @override
  String reviewTabGroups(int count) {
    return 'New people ($count)';
  }

  @override
  String reviewTabMatches(int count) {
    return 'Faces ($count)';
  }

  @override
  String reviewTabOutfits(int count) {
    return 'Bodies ($count)';
  }

  @override
  String get reviewTitle => 'Review';

  @override
  String reviewTitleCount(int count) {
    return 'Review ($count)';
  }

  @override
  String get save => 'Save';

  @override
  String get scanChannelDescription => 'Progress while your photos are scanned';

  @override
  String get scanChannelName => 'Library scan';

  @override
  String scanCountsLine(int done, int waiting, int failed) {
    return '$done scanned · $waiting waiting · $failed failed';
  }

  @override
  String get scanDone => 'Scan finished';

  @override
  String scanError(String message) {
    return 'The scan stopped: $message';
  }

  @override
  String scanFacesFound(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count new faces',
      one: '1 new face',
      zero: 'No new faces',
    );
    return '$_temp0';
  }

  @override
  String scanFacesLinked(int count) {
    return '$count seen before';
  }

  @override
  String scanFailedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count photos could not be read',
      one: '1 photo could not be read',
    );
    return '$_temp0';
  }

  @override
  String get scanFootnote =>
      'Scanning keeps going with the screen off. Photos already scanned are skipped, so you can run it again whenever new items arrive.';

  @override
  String scanFound(int count) {
    return '$count photos found';
  }

  @override
  String get scanLibrary => 'Scan library';

  @override
  String get scanLibraryHint => 'Find the faces in your items';

  @override
  String get scanModelMismatch =>
      'Your PC now uses a different face-recognition model than this library. Switch the PC back, or start a new library.';

  @override
  String get scanNoAccess =>
      'Photo access is off. Allow it in Android settings.';

  @override
  String get scanNoAlbums => 'No albums chosen.';

  @override
  String get scanNotPaired => 'Pair with your PC first.';

  @override
  String scanNotificationText(int done, int total, int faces) {
    return '$done/$total items · $faces faces';
  }

  @override
  String get scanNotificationTitle => 'Scanning your items';

  @override
  String get scanNow => 'Scan now';

  @override
  String get scanOffline =>
      'The PC could not be reached. Check that the server is running on the same Wi-Fi, then resume.';

  @override
  String get scanPaused => 'Scan paused';

  @override
  String get scanPausedUser => 'You paused the scan.';

  @override
  String get scanPcBusy =>
      'Your PC\'s GPU stayed busy for several minutes. Resume when its other job is done.';

  @override
  String scanPhotosOf(int done, int total) {
    return '$done of $total photos';
  }

  @override
  String get scanPreparing => 'Listing your photos…';

  @override
  String get scanRevoked =>
      'This phone was removed on the PC. Pair again to scan.';

  @override
  String get scanRunning => 'Scanning…';

  @override
  String get scanSorting => 'Sorting faces into people…';

  @override
  String scanSummary(int photos, int faces) {
    return '$photos photos scanned · $faces new faces';
  }

  @override
  String get scanWaiting => 'Waiting for your PC…';

  @override
  String get searchPeopleHint => 'Search people';

  @override
  String get selectAll => 'Select all';

  @override
  String selectedCount(int count) {
    return '$count selected';
  }

  @override
  String get setAsCover => 'Use as cover photo';

  @override
  String get settingsGrouping => 'Grouping';

  @override
  String get settingsPc => 'Your PC';

  @override
  String get settingsQualityGate => 'Face quality';

  @override
  String get settingsQualityGateHint =>
      'Faces below this quality are ignored. Raise it for cleaner groups, lower it to catch more faces. Applies to new scans.';

  @override
  String get settingsScanDefaults => 'Scanning';

  @override
  String get showBodies => 'Show bodies';

  @override
  String get showFaces => 'Show faces';

  @override
  String get searchGoogleLens => 'Search with Google Lens';

  @override
  String get googleLensError => 'Could not launch Google Lens';

  @override
  String similarityPercent(int percent) {
    return '$percent% alike';
  }

  @override
  String get sortBy => 'Sort';

  @override
  String sortDone(int assigned, int created, int review) {
    return 'Added $assigned faces to people, created $created people, $review to review';
  }

  @override
  String get sortMostFaces => 'Most faces';

  @override
  String get sortName => 'Name';

  @override
  String get sortNeedsPc => 'Pair with your PC to sort faces.';

  @override
  String get sortNewest => 'Newest';

  @override
  String get sortNow => 'Sort faces now';

  @override
  String get sortNowHint =>
      'Ask the PC to sort unsorted faces into people again';

  @override
  String get sorting => 'Sorting faces…';

  @override
  String get sourcesTitle => 'Sources & scan';

  @override
  String get strictnessBalanced => 'Balanced';

  @override
  String get strictnessBalancedHint =>
      'Recommended. Adds a face to a person only when it is clearly them.';

  @override
  String get strictnessLoose => 'Loose';

  @override
  String get strictnessLooseHint =>
      'Groups more faces automatically. Quicker, but may need more corrections.';

  @override
  String get strictnessStrict => 'Strict';

  @override
  String get strictnessStrictHint =>
      'Asks you about more faces. Fewer mistakes.';

  @override
  String suggestedFacesTitle(String name, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count faces may be $name',
      one: '1 face may be $name',
    );
    return '$_temp0';
  }

  @override
  String get tabBodies => 'Bodies';

  @override
  String tabFaces(int count) {
    return 'Faces ($count)';
  }

  @override
  String get tabPhotos => 'Photos';

  @override
  String get tabSuggestions => 'Suggestions';

  @override
  String get thisIsPerson => 'This is…';

  @override
  String get unsortedCardTitle => 'Unsorted';

  @override
  String get unsortedFace => 'Unsorted face';

  @override
  String unsortedFacesInPhoto(int count) {
    return '$count unsorted';
  }

  @override
  String get whoIsHere => 'Who is here';

  @override
  String get close => 'Close';

  @override
  String get allMedia => 'All photos & videos';

  @override
  String mediaCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count items',
      one: '1 item',
    );
    return '$_temp0';
  }

  @override
  String get includeVideos => 'Scan videos too';

  @override
  String get includeVideosHint =>
      'Videos upload to your paired PC. Progress resumes after interruptions.';

  @override
  String get videoFrameInterval => 'Sample video frames';

  @override
  String videoEverySeconds(String seconds) {
    return 'Every $seconds s';
  }

  @override
  String videoPreparing(int percent) {
    return 'Preparing video · $percent%';
  }

  @override
  String videoUploading(int percent) {
    return 'Uploading video · $percent%';
  }

  @override
  String videoAnalyzing(int percent) {
    return 'Analyzing video · $percent%';
  }

  @override
  String get videoDownloading => 'Downloading video detections…';

  @override
  String get videoImporting => 'Saving video detections on this phone…';

  @override
  String get videoTitle => 'Video';

  @override
  String get videoUnavailable => 'Video unavailable';

  @override
  String get videoUnavailableBody =>
      'The original may have been removed, access may have changed, or this format cannot be played.';

  @override
  String get videoPlay => 'Play';

  @override
  String get videoPause => 'Pause playback';

  @override
  String get videoDetectedFrames => 'Jump to a detected frame';

  @override
  String get videoNoDetections =>
      'No detections yet. Scan this video to find people.';

  @override
  String get insightsTitle => 'Library insights';

  @override
  String get insightsHint =>
      'Scan coverage, identified faces and people in your library.';

  @override
  String get insightsCoverage => 'Scan coverage';

  @override
  String insightsScanned(int done, int total) {
    return '$done of $total items scanned';
  }

  @override
  String get insightsFaces => 'Identified faces';

  @override
  String get insightsBodies => 'Identified bodies';

  @override
  String get insightsTopPeople => 'Most seen people';

  @override
  String insightsPersonMedia(int count) {
    return '$count media items';
  }

  @override
  String get insightsEmpty => 'Scan your library to see insights';

  @override
  String insightsAssigned(int identified, int total) {
    return '$identified of $total identified';
  }

  @override
  String get insightsUnsorted => 'Unsorted faces';

  @override
  String get insightsFailed => 'Items needing another scan';

  @override
  String get tabMedia => 'Photos & videos';

  @override
  String get studioTitle => 'Studio';

  @override
  String get studioHint => 'Create with your private library';

  @override
  String get studioNeedsPc =>
      'Connect to your paired PC to detect faces and start a new job.';

  @override
  String get studioBusyHint =>
      'The GPU is busy. New Studio jobs will wait in the queue.';

  @override
  String get refaceTitle => 'Reface';

  @override
  String get refaceHint => 'Swap a person into a photo or video';

  @override
  String get privateResults => 'Private results';

  @override
  String get privateResultsHint =>
      'Outputs stay inside Your Gallery until you choose to share them.';

  @override
  String get refaceTarget => 'Target';

  @override
  String get refaceIdentity => 'Source identity';

  @override
  String get refaceQuality => 'Engine & quality';

  @override
  String get refaceReview => 'Review & create';

  @override
  String get chooseTargetPhoto => 'Choose a photo';

  @override
  String get chooseTargetVideo => 'Choose a video';

  @override
  String get selectedTargetFaces => 'Choose the faces to swap';

  @override
  String get videoSwapsAllFaces =>
      'Video Reface swaps every detected face in the selected clip.';

  @override
  String get videoTrimStart => 'Start (seconds)';

  @override
  String get videoTrimEnd => 'End (seconds, optional)';

  @override
  String get selectSourcePerson => 'Choose source person';

  @override
  String get sourceFacesHint =>
      'Select clear faces of the same person. The best 20 are selected by default.';

  @override
  String get refaceHd => 'V3 · HD';

  @override
  String get refaceLegacy => 'V2';

  @override
  String get refacePro => 'Pro · DFM';

  @override
  String get refaceEngine => 'Engine';

  @override
  String get dfmModel => 'DFM model';

  @override
  String get refaceRestorer => 'Sharpening';

  @override
  String get restorerAuto => 'Automatic';

  @override
  String get restorerNatural => 'Sharp and natural';

  @override
  String get restorerExtraSharp => 'Extra sharp for big faces';

  @override
  String get restorerRebuild => 'Rebuilds blurry faces';

  @override
  String get restorerSmooth => 'Smooth and clean';

  @override
  String get restorerAlternative => 'Alternative finish';

  @override
  String get restorerNone => 'No sharpening';

  @override
  String get refacePreset => 'Skin finish';

  @override
  String get presetNatural => 'Natural (recommended)';

  @override
  String get presetDetail => 'Extra skin texture';

  @override
  String get presetClean => 'Smooth and clean';

  @override
  String get protectOcclusions => 'Protect glasses and occlusions';

  @override
  String get useFaceParser => 'Use face region mask';

  @override
  String get submitReface => 'Create Reface job';

  @override
  String get refaceReviewHint =>
      'The target is copied to private phone storage so this request survives closing the app. The PC uses temporary files and deletes them after this phone confirms the result is saved.';

  @override
  String get selectFaceRequired => 'Select at least one target face.';

  @override
  String get selectIdentityRequired =>
      'Choose a source person and at least one face.';

  @override
  String get chooseTargetRequired =>
      'Choose and detect a photo, or choose a video.';

  @override
  String get invalidTrimRange =>
      'Enter a valid trim range: end must be greater than start.';

  @override
  String get fileTooLarge => 'This file exceeds the PC upload limit.';

  @override
  String get studioNoEngine =>
      'No Reface engine is available. Check the models on your PC.';

  @override
  String get jobsEmpty => 'No Studio jobs yet';

  @override
  String get jobsEmptyHint =>
      'Start a Reface job from Studio. Progress and results will appear here.';

  @override
  String get jobDetails => 'Job details';

  @override
  String get jobPause => 'Pause';

  @override
  String get jobResume => 'Resume';

  @override
  String get jobRetry => 'Retry';

  @override
  String get jobRemove => 'Remove job';

  @override
  String get jobSync => 'Sync now';

  @override
  String get jobResult => 'Open result';

  @override
  String get statusUploading => 'Uploading';

  @override
  String get statusQueued => 'Queued';

  @override
  String get statusRunning => 'Running';

  @override
  String get statusPaused => 'Paused';

  @override
  String get statusDownloading => 'Saving result';

  @override
  String get statusCompleted => 'Completed';

  @override
  String get statusFailed => 'Failed';

  @override
  String get statusLost => 'PC job expired';

  @override
  String get resultEmpty => 'No private results yet';

  @override
  String get resultEmptyHint =>
      'Finished outputs are saved here automatically.';

  @override
  String get resultBefore => 'Before';

  @override
  String get resultAfter => 'After';

  @override
  String get resultCompare => 'Before / after';

  @override
  String get resultShare => 'Share output';

  @override
  String get resultFavourite => 'Favourite';

  @override
  String get resultDelete => 'Delete result';

  @override
  String get resultDeleteBody =>
      'Delete this private output and its comparison original from the phone?';

  @override
  String get jobRemoveBody =>
      'Remove this job and its temporary input? Saved results are kept.';

  @override
  String get next => 'Next';

  @override
  String get createAnother => 'Create another';

  @override
  String get allResults => 'All results';

  @override
  String get favouriteResults => 'Favourites';

  @override
  String get resultPhoto => 'Photo';

  @override
  String get resultVideo => 'Video';

  @override
  String get jobErrorHint =>
      'Your target remains on the phone. Reconnect or retry to continue.';

  @override
  String get useInStudio => 'Use in Studio';

  @override
  String get studioResultReady =>
      'Your result is ready and saved privately on this phone.';

  @override
  String get restyleTitle => 'Clothes restyle';

  @override
  String get restyleHint => 'Change clothing while protecting the face';

  @override
  String get restylePrompt => 'Describe the clothing';

  @override
  String get restyleDefaultPrompt =>
      'Photorealistic fashion photo, wearing an elegant blue tailored suit, natural fabric texture and folds, preserve the same person, pose, lighting and background';

  @override
  String get restyleNegative => 'Negative prompt';

  @override
  String get restyleNegativeDefault =>
      'nudity, underwear, deformed hands, bad anatomy, blurry, plastic skin, watermark';

  @override
  String get restyleStrength => 'Change strength';

  @override
  String get restyleFace => 'Protected face';

  @override
  String get restylePadding => 'Extra face protection';

  @override
  String get restyleReferences => 'Clothing references';

  @override
  String get addReference => 'Add a reference photo';

  @override
  String get restyleCreate => 'Create restyle job';

  @override
  String get engineUnavailable =>
      'This tool is unavailable on your PC. Check its environment and model files.';

  @override
  String get advancedOptions => 'Advanced options';

  @override
  String get seed => 'Seed (-1 = random)';

  @override
  String get steps => 'Steps';

  @override
  String get guidance => 'Guidance';

  @override
  String get refineOutput => 'Refine at original resolution';

  @override
  String get promptRequired => 'Describe the clothing before submitting.';

  @override
  String get loraTitle => 'Character LoRA';

  @override
  String get loraHint =>
      'Build a dataset, train a character and generate portraits';

  @override
  String get loraDatasetTitle => 'Character dataset';

  @override
  String get loraDatasetBuild => 'Build dataset';

  @override
  String get loraChoosePhotos => 'Choose training photos';

  @override
  String get loraPhotoHint =>
      'Choose 5–64 clear photos of the selected person. The PC matches that identity before cropping.';

  @override
  String get loraTrigger => 'Trigger word';

  @override
  String get loraTriggerHint =>
      '3–64 letters, digits or underscores; start with a letter';

  @override
  String get loraRepeats => 'Repeats per image';

  @override
  String get loraTrain => 'Train LoRA';

  @override
  String get loraGenerate => 'Generate portraits';

  @override
  String get loraNoDatasets => 'No character datasets yet';

  @override
  String get loraNoModels => 'No trained LoRAs yet';

  @override
  String get loraDatasetEditor => 'Edit dataset';

  @override
  String get loraCaption => 'Caption';

  @override
  String get loraIncluded => 'Include in training';

  @override
  String get loraExport => 'Export training zip';

  @override
  String get loraTrainHint =>
      'Training uses the included images and edited captions. The finished LoRA is saved on this phone.';

  @override
  String get loraEpochs => 'Epochs';

  @override
  String get loraDim => 'Network dimension';

  @override
  String get loraLearningRate => 'Learning rate';

  @override
  String get loraResolution => 'Resolution';

  @override
  String get loraBase => 'Look of the pictures';

  @override
  String get loraBaseRealistic => 'Realistic photos';

  @override
  String get loraBaseAnime => 'Anime and drawings';

  @override
  String get loraModel => 'Trained LoRA';

  @override
  String get loraCount => 'Number of portraits';

  @override
  String get loraPrompt => 'Portrait prompt';

  @override
  String loraDefaultPrompt(Object trigger) {
    return 'A natural studio portrait of $trigger person, neutral expression, realistic skin texture, soft daylight, fully clothed, photorealistic';
  }

  @override
  String get loraReferenceMode => 'Follow the reference';

  @override
  String get referenceComposition => 'Pose & composition';

  @override
  String get referenceStyle => 'Style & clothing';

  @override
  String get referenceBoth => 'Both';

  @override
  String get loraIdentity => 'Use generated portraits in Reface';

  @override
  String get loraBuildIdentity => 'Build Reface identity';

  @override
  String get loraIdentityHint =>
      'Generated faces are added only when they match the person’s real face identity.';

  @override
  String get loraIdentityReady => 'Reface identity saved';

  @override
  String get loraChooseDataset => 'Choose a dataset';

  @override
  String get loraMinImages => 'Include at least five images before training.';

  @override
  String get invalidForm => 'Check the form values and try again.';

  @override
  String get loraNoBase =>
      'No compatible base checkpoint is available on this PC.';

  @override
  String get privateArtifact => 'Private model or dataset';

  @override
  String get openDataset => 'Open dataset editor';

  @override
  String get openLora => 'Open Character LoRA';

  @override
  String get trainingDetails => 'Training progress';

  @override
  String get loss => 'Loss';

  @override
  String get epoch => 'Epoch';

  @override
  String get totalSteps => 'Steps';

  @override
  String get saveToGallery => 'Save to gallery';

  @override
  String get savedToGallery => 'Saved to gallery';

  @override
  String get storageTitle => 'Storage';

  @override
  String get appLockTitle => 'App lock';

  @override
  String get appLockHint =>
      'Use your phone’s screen lock when opening Your Gallery.';

  @override
  String get unlockApp => 'Unlock Your Gallery';

  @override
  String get unlockBody =>
      'Confirm your phone screen lock to open your private library.';

  @override
  String get unlockFailed =>
      'Unlock was cancelled, or a phone screen lock is not set up.';

  @override
  String get storageHint =>
      'Manage private outputs, datasets and trained models.';

  @override
  String get storageUsed => 'Private files';

  @override
  String get storageDeleteResults => 'Delete private results';

  @override
  String get storageDeleteDatasets => 'Delete datasets';

  @override
  String get storageDeleteLoras => 'Delete trained LoRAs';

  @override
  String get storageDeleteTemporary => 'Clean temporary files';

  @override
  String get storageConfirm =>
      'Delete the selected private files from this phone? Export a backup first if you want to keep them.';

  @override
  String get storageBusy =>
      'Pause scans and active Studio jobs before cleaning storage.';

  @override
  String get storageCleaned => 'Storage updated';

  @override
  String get connectionTitle => 'Connection help';

  @override
  String get connectionFix => 'Fix connection';

  @override
  String get connectionIntro =>
      'Connect locally over a router, either device\'s hotspot, or USB. Internet access is not required. If the PC address changes, search again without forgetting your pairing.';

  @override
  String get connectionFind => 'Find my PC on this network';

  @override
  String get connectionTest => 'Verify and save PC address';

  @override
  String get connectionPairAtAddress => 'Pair at this address';

  @override
  String get connectionRestored =>
      'Connected to the same verified PC. Your pairing and library are preserved.';

  @override
  String get connectionNothingFound =>
      'No PC answered local discovery. Check the current address in the PC dashboard and try it below. Discovery may be blocked even when direct connection works.';

  @override
  String get connectionVerifyFailed =>
      'The discovered addresses could not be verified as your paired PC. Check that the server is running and use its current address.';

  @override
  String get connectionFailed =>
      'Connection could not be completed. Check the server, local address and firewall settings below.';

  @override
  String get connectionInvalidAddress =>
      'Enter a private-network PC address and a port from 1 to 65535.';

  @override
  String get connectionPhoneAddresses => 'This phone\'s local addresses';

  @override
  String get connectionNoLan =>
      'No local Wi-Fi, hotspot or USB interface was found. Turn on the hotspot or connect to a local network. A cellular connection alone cannot reach the PC.';

  @override
  String get connectionPhoneHotspotTitle => 'Phone shares its hotspot';

  @override
  String get connectionPhoneHotspot =>
      'Connect the PC to this phone\'s hotspot. On the PC open Mobile Devices and use the PC\'s Wi-Fi address shown there. Keep the hotspot enabled; some phones turn it off automatically. Mobile data can stay enabled.';

  @override
  String get connectionPcHotspotTitle => 'PC shares its hotspot';

  @override
  String get connectionPcHotspot =>
      'Connect the phone to the PC hotspot. Use the hotspot adapter\'s PC address from Mobile Devices. It can differ from the PC\'s router or Ethernet address.';

  @override
  String get connectionRouterTitle => 'Router, guest Wi-Fi or VPN';

  @override
  String get connectionRouter =>
      'Use the same local network and allow the Python server through Windows Firewall. Guest isolation and some VPNs block device traffic; enable local-network access or use another local network. An Internet connection is not a connectivity test.';

  @override
  String get connectionUsbTitle => 'USB fallback';

  @override
  String get connectionUsb =>
      'Connect a USB cable, enable and authorize USB debugging, then run the command below on the PC. Use 127.0.0.1 and the PC server\'s port here. This avoids Wi-Fi isolation and uses no mobile data.';

  @override
  String get connectionPinSafety =>
      'Finding a device never changes the saved certificate or sends media to an unverified PC. If the PC certificate was replaced, confirm its new QR on the PC before pairing again.';

  @override
  String get backgroundTitle => 'Background work';

  @override
  String get backgroundIntro =>
      'Allow notifications and unrestricted battery use so scans, uploads and result downloads can continue when you leave the app or lock the screen. An ongoing notification shows when work is active.';

  @override
  String get backgroundSettingsHint => 'Keep work going with the screen off';

  @override
  String get backgroundLater => 'Continue for now';

  @override
  String get backgroundEnable => 'Allow background work';

  @override
  String get backgroundRefresh => 'Refresh status';

  @override
  String get backgroundNotifications => 'Progress notifications allowed';

  @override
  String get backgroundBattery => 'Battery use unrestricted';

  @override
  String get backgroundBatteryWarning =>
      'Battery optimization is on. Allow unrestricted battery so scanning continues when your screen is locked.';

  @override
  String get backgroundRunning => 'Background service is running';

  @override
  String get backgroundIdle => 'Ready to start when there is active work';

  @override
  String get backgroundOpenSettings => 'Open Android app settings';

  @override
  String get backgroundAndroidOnly =>
      'Background permissions are available on Android.';

  @override
  String get backgroundServiceFailed =>
      'Android could not start the background service. Keep the app open and check notifications and battery settings.';

  @override
  String get backgroundLimits =>
      'A force stop, phone shutdown or Android background time limit can stop phone work. Open the app to resume its saved queue. Some phones also require allowing auto-start in the manufacturer\'s battery settings. The PC must stay on and connected to the phone.';

  @override
  String get identitySaved => 'Saved identity sets';

  @override
  String get identitySave => 'Save selected faces';

  @override
  String get identityName => 'Identity set name';

  @override
  String get identityDelete => 'Delete identity set';

  @override
  String get identityDeleteBody =>
      'Remove this saved selection? The person and source faces will be kept.';

  @override
  String get backupEncryption => 'Encrypt backup';

  @override
  String get backupEncryptionHint =>
      'Protect this backup with a password. You will need it to restore on any phone.';

  @override
  String get backupPlaintextHint =>
      'This backup will be readable without a password. Keep it in a private location.';

  @override
  String get backupPasswordCreate => 'Protect your backup';

  @override
  String get backupPasswordEnter => 'Unlock backup';

  @override
  String get backupPasswordReminder =>
      'Keep your password somewhere safe. A forgotten password cannot be recovered.';

  @override
  String get backupPassword => 'Password';

  @override
  String get backupPasswordConfirm => 'Confirm password';

  @override
  String get backupPasswordVisibility => 'Show or hide password';

  @override
  String get backupPasswordLength => 'Use 12–1024 characters.';

  @override
  String get backupPasswordMismatch => 'The passwords do not match.';

  @override
  String get backupUnlock => 'Unlock';

  @override
  String get backupStageEncrypting => 'Encrypting backup…';

  @override
  String get backupStageDecrypting => 'Unlocking backup…';

  @override
  String get jobStage => 'Stage';

  @override
  String get jobEpoch => 'Epoch';

  @override
  String get jobTotalEpochs => 'Total epochs';

  @override
  String get jobStep => 'Step';

  @override
  String get jobTotalSteps => 'Total steps';

  @override
  String get jobLoss => 'Loss';

  @override
  String get jobSecondsPerStep => 'Seconds per step';

  @override
  String get jobHistory => 'Activity history';

  @override
  String jobTimeRemaining(String time) {
    return 'About $time remaining';
  }

  @override
  String jobHoursMinutes(int hours, int minutes) {
    return '$hours hr $minutes min';
  }

  @override
  String jobMinutes(int minutes) {
    return '$minutes min';
  }

  @override
  String get restyleRefineUnavailable =>
      'Optional SDXL refinement is not installed on this PC. Basic Restyle can run without it.';

  @override
  String get backupShareCancelled =>
      'Backup sharing was cancelled. Choose a destination to keep a copy outside this app.';

  @override
  String get refaceReference => 'Choose a photo of the person to replace';

  @override
  String get refaceReferenceHint =>
      'Select their face in a reference photo. Only matching people in the video will be replaced.';

  @override
  String get refaceAllVideoFaces => 'Replace all video faces instead';

  @override
  String get refaceAllFaces => 'Replace all faces';

  @override
  String refaceTakes(String time) {
    return 'Takes $time on your PC';
  }

  @override
  String get refaceQualityProfile => 'Quality or speed';

  @override
  String get refaceFast => 'Fast';

  @override
  String get refaceFastSummary => 'Quickest · skin a little soft';

  @override
  String get refaceFastDescription =>
      'The face is swapped and blended in, but not sharpened afterwards, so it can look slightly softer than the rest of the picture. You get the result soonest. Good for long videos and for trying things out.';

  @override
  String get refaceBalanced => 'Balanced';

  @override
  String get refaceBalancedSummary => 'Sharp and natural · recommended';

  @override
  String get refaceBalancedDescription =>
      'Sharpens the swapped face to match the rest of the picture and blends its edges carefully around hair, glasses and hands. The best everyday choice: clearly sharper than Fast for a modest wait.';

  @override
  String get refaceDetail => 'Most detail';

  @override
  String get refaceDetailSummary => 'Sharpest on big faces · slowest';

  @override
  String get refaceDetailDescription =>
      'Sharpens at double the resolution. You only see the difference on large close-up faces (roughly a quarter of the picture or more); on smaller faces it looks like Balanced but takes much longer.';

  @override
  String get refaceAutoSummary =>
      'The PC picks what fits the quality you chose';

  @override
  String refaceAutoStartsWith(String model) {
    return 'Right now: $model';
  }

  @override
  String get refaceAutoDescription =>
      'Fast uses no sharpening, Balanced uses the natural sharpening and Most detail uses the extra-sharp one. If a model is missing on the PC, it uses the closest one that is installed.';

  @override
  String get refaceOffSummary => 'Fastest · face a little soft';

  @override
  String get refaceOffDescription =>
      'The swapped face is blended in as it comes out, without a sharpening step. It finishes sooner, and the face can look slightly softer than the rest of the picture.';

  @override
  String get refaceGpen512Summary => 'Sharp and natural · recommended';

  @override
  String get refaceGpen512Description =>
      'Sharpens the face to match the picture and keeps the person recognisable. It was the sharpest and most faithful choice in our tests, for a small amount of extra time per face. (GPEN 512)';

  @override
  String get refaceGpen1024Summary => 'Extra sharp for big faces · slowest';

  @override
  String get refaceGpen1024Description =>
      'The same look at double the detail resolution. Only worth it for large close-up faces; for each face it takes about twice as long as the natural sharpening. (GPEN 1024)';

  @override
  String get refaceCodeformerSummary =>
      'Rebuilds blurry faces · can change the look';

  @override
  String get refaceCodeformerDescription =>
      'Re-draws faces that are blurry or low quality. Because it rebuilds features it can make the person look less like themselves, so compare a preview first. A little slower than the natural sharpening. (CodeFormer, with a fidelity balance between rebuilt detail and the original)';

  @override
  String get refaceGfpganSummary => 'Smooth and clean · a little faster';

  @override
  String get refaceGfpganDescription =>
      'Cleans and smooths the face and is quicker than the natural sharpening, with slightly less likeness in our tests. Try it when speed matters more than the last bit of resemblance. (GFPGAN 1.4)';

  @override
  String get refaceRestoreformerSummary => 'Alternative finish · slower';

  @override
  String get refaceRestoreformerDescription =>
      'Another way of sharpening. It takes longer than the natural sharpening; try it when the other finishes do not suit a particular face. (RestoreFormer++)';

  @override
  String get refaceOtherModelSummary => 'Provided by your PC';

  @override
  String get refaceOtherModelDescription =>
      'This option is installed on the PC. Its speed and look are not known here, so render a short preview to see what it does.';

  @override
  String get refaceRestorationIntro =>
      'After the swap, the face can be sharpened so it matches the rest of the picture. Pick by the look and the waiting time; the model name in brackets is only for reference.';

  @override
  String get refaceSpeedNote =>
      'Times are typical for your PC. Bigger photos, more faces or a busy PC take longer. A short preview shows the look before you commit to the full render.';

  @override
  String get refacePhotosIdentity => 'Source photos & videos';

  @override
  String get refaceTrainedIdentity => 'Trained identity model';

  @override
  String get refaceIdentityMethod => 'Identity source';

  @override
  String get refaceUnifiedUnavailable =>
      'Unified Reface is unavailable. Update the PC server and check its face-swap model.';

  @override
  String get refaceAllFacesHint =>
      'Use the source identity for everyone in this photo or video, including people who appear later. No target face selection is needed.';

  @override
  String get refacePreview => 'Render a preview';

  @override
  String get refacePreviewHint =>
      'Try these settings first. Video previews render up to 3 seconds; return here to adjust settings or start the full job.';

  @override
  String get refaceLegacyHint =>
      'V2 processes every video frame and keeps the selected people matched by identity. It uses automatic OpenCV enhancement and occlusion protection.';

  @override
  String get refaceDfmHint =>
      'The trained model supplies face detail; restoration is not applied.';

  @override
  String get refaceIdentityBoost => 'Likeness strength';

  @override
  String get refaceSwapped => 'Successful face swaps';

  @override
  String get refaceSkipped => 'Skipped faces';

  @override
  String get refaceFailed => 'Failed faces';

  @override
  String get chooseTargetMedia => 'Choose photo or video';

  @override
  String get refaceTrimHint =>
      'Drag the two handles to choose your clip. The preview follows the handle you move.';

  @override
  String get refaceTrimStart => 'Start';

  @override
  String get refaceTrimEnd => 'End';

  @override
  String get refaceTrimDuration => 'Selected clip';

  @override
  String get refaceTrimEarlier => 'Move one second earlier';

  @override
  String get refaceTrimLater => 'Move one second later';

  @override
  String get refaceTrimLoading =>
      'Wait for the video preview to load, then choose your clip.';

  @override
  String get refaceGallerySource => 'Gallery';

  @override
  String get refaceGallerySourceHint => 'Choose a gallery app on this device';

  @override
  String get refaceFilesSource => 'Files';

  @override
  String get refaceFilesSourceHint => 'Browse device folders and downloads';

  @override
  String get refaceTargetPeopleHint =>
      'Choose the people in this clip whose faces you want to replace. Faces are found in sampled frames; adjust the clip and scan again if someone is missing.';

  @override
  String get refaceFindingFaces => 'Finding faces in the selected clip…';

  @override
  String get refaceDetectVideoFaces => 'Find faces in this clip again';

  @override
  String get refaceAddSourceMedia => 'Add source photos or videos';

  @override
  String get refaceSourceMediaHint =>
      'Choose photos and videos of the person whose face you want to use. If several people are found, select one person below. You can add more files.';

  @override
  String get refaceSourceMedia => 'Selected source media';

  @override
  String get refaceClearSourceMedia => 'Clear selected source media';

  @override
  String refaceSourceMediaCount(int count) {
    return '$count source files analysed';
  }

  @override
  String get refaceReadingVideo => 'Reading video frames…';

  @override
  String get refaceDetectShownFrame => 'Find faces in the frame shown';

  @override
  String refaceFaceAppearances(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count appearances',
      one: '1 appearance',
    );
    return '$_temp0';
  }

  @override
  String get refaceVideoReadTimeout =>
      'Reading this video took too long. Try a shorter clip or choose the video again.';

  @override
  String refaceVideoPeopleFound(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count people found in this clip',
      one: '1 person found in this clip',
    );
    return '$_temp0';
  }

  @override
  String get homeIntro => 'A little more organized.';

  @override
  String get homeIntroHint => 'Find your people. Make something new.';

  @override
  String get homeOrganize => 'Your library';

  @override
  String get homeCreate => 'Make something yours';

  @override
  String get homeActivity => 'Pick up where you left off';

  @override
  String get studioIntro => 'What would you like to create?';

  @override
  String get studioTools => 'Choose a tool';

  @override
  String get studioSaved => 'Your creations';

  @override
  String get studioRefaceAction => 'Replace a face';

  @override
  String get studioRestyleAction => 'Try a new look';

  @override
  String get studioLoraAction => 'Create a character';

  @override
  String get studioRefaceDescription =>
      'Choose a photo or clip, then the person to replace.';

  @override
  String get studioRestyleDescription => 'Describe a new look for a photo.';

  @override
  String get studioLoraDescription =>
      'Build a character from photos, train it, then create.';

  @override
  String get clearFilters => 'Clear filters';

  @override
  String get peopleNoMatches => 'No people match your search';

  @override
  String get clearSearch => 'Clear search';

  @override
  String get jobsInProgress => 'In progress';

  @override
  String workflowProgress(int current, int total) {
    return 'Step $current of $total';
  }

  @override
  String get settingsLibrarySection => 'Library & scanning';

  @override
  String get settingsPrivacySection => 'Privacy & storage';

  @override
  String get settingsDeviceSection => 'PC & background activity';

  @override
  String get resultsNoMatches => 'No results match these filters';

  @override
  String get storageSavedTitle => 'Saved on your phone';

  @override
  String get storageCategories => 'Storage by category';

  @override
  String get storageManage => 'Manage saved files';

  @override
  String get storageModels => 'Character models';

  @override
  String get storageOther => 'Other files';

  @override
  String get storageTemporary => 'Temporary files';

  @override
  String get storageOriginalsHint =>
      'Your original photos and videos stay in the device gallery.';

  @override
  String get storageDatabase => 'Library database';

  @override
  String get storageCache => 'Cache and scratch files';

  @override
  String get storageLeftoversTitle => 'Leftover files';

  @override
  String get storageLeftoversNone =>
      'No leftover files found. Everything on this phone belongs to your library.';

  @override
  String storageLeftoversFound(String size) {
    return '$size of files no longer belong to anything in your library (old crops, finished downloads, scratch copies of videos).';
  }

  @override
  String get storageCleanLeftovers => 'Clean up leftovers';

  @override
  String get storageLeftoversConfirm =>
      'Delete only files that nothing in your library uses, plus old cache and scratch files? Your people, photos, results, datasets and trained models are not touched.';

  @override
  String storageLeftoversDone(String size) {
    return 'Freed $size';
  }

  @override
  String get reviewIntro =>
      'Open a photo to inspect the highlighted face or body, then decide who it belongs to.';

  @override
  String compactVideosBanner(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count videos still keep a face for every frame.',
      one: '1 video still keeps a face for every frame.',
    );
    return '$_temp0 Combine each appearance into one review item and free the space of the repeated crops.';
  }

  @override
  String get compactVideosAction => 'Combine frames';

  @override
  String compactVideosRunning(int done, int total) {
    return 'Combining video $done of $total…';
  }

  @override
  String compactVideosDone(int videos, int faces, int bodies) {
    return 'Combined $videos videos: $faces repeated faces and $bodies repeated bodies removed. Every frame is still recorded.';
  }

  @override
  String get permissionsHeadline => 'Make it work for you';

  @override
  String get manualHeadline => 'Connect by address';

  @override
  String get connectionHeadline => 'Find your PC';

  @override
  String get backgroundHeadline => 'Keep your work moving';

  @override
  String get backupHeadline => 'Keep your library safe';

  @override
  String get mergeHeadline => 'The same person?';

  @override
  String get mergeIntro =>
      'Compare the faces, then choose which profile to keep.';

  @override
  String get datasetEditorIntro => 'Choose the photos to train with';

  @override
  String get datasetEditorHint =>
      'Keep clear, varied views of the same person. Include at least 5 photos to start training.';

  @override
  String get loraTrainHeadline => 'Train your character';

  @override
  String get loraGenerateHeadline => 'Create with your character';

  @override
  String get analyzeHeadline => 'Who is in this photo?';

  @override
  String get loadFailedTitle => 'Could not load this screen';

  @override
  String get loadFailedBody =>
      'Your saved data has not changed. Try loading this screen again.';

  @override
  String get mediaPeopleHint =>
      'Tap a face to see or change who it belongs to.';

  @override
  String get jobProgressTitle => 'Progress';

  @override
  String get jobDetailsAdvanced => 'Processing details';

  @override
  String get resultsBrowseHint => 'Your creations, saved on this phone.';

  @override
  String get selectFaces => 'Select faces';

  @override
  String get storageRemoveSaved => 'Remove saved files';

  @override
  String get resourcesTitle => 'PC resources';

  @override
  String get resourcesSubtitle =>
      'RAM, GPU memory and storage on the PC doing your AI work.';

  @override
  String get resourcesUnavailable =>
      'Could not read PC resources. Connect to the PC and make sure its server supports resource monitoring.';

  @override
  String get resourcesUnknown => 'Unavailable';

  @override
  String get resourcesAppRam => 'Application RAM (all PC workers)';

  @override
  String get resourcesRamAvailable => 'System RAM available';

  @override
  String get resourcesSystemRam => 'System RAM usage';

  @override
  String get resourcesGpuTotal => 'Whole GPU VRAM used';

  @override
  String get resourcesAppVram => 'Application compute VRAM';

  @override
  String get resourcesDiskAvailable => 'PC workspace disk available';

  @override
  String get resourcesScratch => 'Server temporary files';

  @override
  String get resourcesStoragePartial =>
      'Folder size is still counting or partially unavailable.';

  @override
  String get resourcesProcessPartial =>
      'Some application processes could not be measured.';

  @override
  String get resourcesWaiting => 'Waiting for PC resources';

  @override
  String get resourcesScopeHint =>
      'These readings describe the PC, not this phone. Shared RAM pages may be counted more than once. Whole GPU usage includes other apps; application VRAM may be unavailable with the PC driver. Updates every 5 seconds while this panel is visible.';

  @override
  String get resourcesLimitsHint =>
      'Set optional admission thresholds in PC Settings → PC resources & protection. They delay new compute work; they are not hard memory caps for running tasks.';

  @override
  String get resourcesUpdated => 'Last sample';

  @override
  String get charactersTitle => 'Cartoon & anime characters';

  @override
  String get charactersScan => 'Scan illustrated characters';

  @override
  String get charactersScanHint =>
      'Mark anime or cartoon albums on Scan sources. Only those albums are scanned for characters; a clear real face there still goes to People.';

  @override
  String get charactersAlbumToggle => 'Anime / cartoon album';

  @override
  String charactersAlbumsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count anime or cartoon albums',
      one: '1 anime or cartoon album',
      zero: 'No anime or cartoon albums marked',
    );
    return '$_temp0';
  }

  @override
  String get charactersEmpty => 'No characters yet';

  @override
  String get charactersEmptyHint =>
      'Choose cartoon or anime albums in Scan sources and enable illustrated character scanning. Detection runs on the PC; your character library and appearance matching stay on this phone.';

  @override
  String get charactersAccuracyHint =>
      'Grouped by visual appearance. Different outfits, hidden bodies or similar designs can need correction. Open a group to name it or separate a mistaken match.';

  @override
  String get characterSeparate => 'Separate this character';

  @override
  String get characterName => 'Character name';

  @override
  String get characterOpenSource => 'Open source';

  @override
  String get charactersTestPhoto => 'Test a character photo';

  @override
  String get charactersTestHint =>
      'Test one illustration on the PC without saving it to your library. Bodies, hair, clothing and visual details are analysed; no human face is needed.';

  @override
  String characterFallback(int id) {
    return 'Character $id';
  }

  @override
  String characterSamples(int count) {
    return '$count appearances';
  }

  @override
  String charactersFound(int count) {
    return '$count character appearances found';
  }

  @override
  String get quickReviewTitle => 'Quick review';

  @override
  String quickReviewProgress(int current, int total) {
    return '$current of $total';
  }

  @override
  String get quickSeeAll => 'See all';

  @override
  String get quickYes => 'Yes';

  @override
  String get quickNo => 'No';

  @override
  String get quickNotSure => 'Not sure';

  @override
  String get quickSwipeHint => 'Swipe right for Yes, left for No';

  @override
  String get quickSamePerson => 'Same person?';

  @override
  String get quickWhoIsThis => 'Who is this?';

  @override
  String get quickWhoHint => 'Type a new name or pick someone';

  @override
  String get quickNewPersonHelper => 'Saves a new person';

  @override
  String quickAddToHelper(String name) {
    return 'Adds these faces to $name';
  }

  @override
  String quickGroupFaces(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count photos of this face',
      one: '1 photo of this face',
    );
    return '$_temp0';
  }

  @override
  String get quickByClothes => 'Recognised by clothes';

  @override
  String get quickByWeakFace => 'Recognised by a small or blurry face';

  @override
  String get quickByEventOutfit => 'Same outfit, same day';

  @override
  String get quickSnoozed =>
      'Saved for later. It comes back when new photos give more evidence.';

  @override
  String get quickAllDone => 'All caught up';

  @override
  String get quickAllDoneBody =>
      'New questions appear after the next scan or Sort now.';

  @override
  String quickAllDoneSnoozed(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count answers you weren\'t sure about are waiting until there is more evidence. See all to decide now.',
      one:
          '1 answer you weren\'t sure about is waiting until there is more evidence. See all to decide now.',
    );
    return '$_temp0';
  }

  @override
  String get likelihoodVeryLikely => 'Very likely';

  @override
  String get likelihoodLikely => 'Likely';

  @override
  String get likelihoodMaybe => 'Maybe';

  @override
  String get reviewAdvancedTitle => 'Advanced review details';

  @override
  String get reviewAdvancedBody =>
      'Show percentages and how bodies were linked, and open Review on all four lists instead of one question at a time';

  @override
  String peopleReviewBanner(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Help improve your groups · $count questions',
      one: 'Help improve your groups · 1 question',
    );
    return '$_temp0';
  }

  @override
  String get peopleReviewBannerBody =>
      'Quick yes / no answers, one photo at a time';

  @override
  String albumReviewBanner(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Review $count photos',
      one: 'Review 1 photo',
    );
    return '$_temp0';
  }

  @override
  String albumReviewBannerBody(String name) {
    return 'Photos that may also be $name';
  }

  @override
  String albumReviewTitle(String name) {
    return 'Is this $name?';
  }

  @override
  String albumReviewHelp(String name) {
    return 'Every photo starts ticked. Untick the ones that aren\'t $name, then tap Done. Long-press a photo to see it full size.';
  }

  @override
  String get albumReviewNone => 'Untick all';

  @override
  String albumReviewSummary(int add, int remove) {
    return '$add to add · $remove someone else';
  }

  @override
  String albumReviewSaved(int add, int remove) {
    return '$add added · $remove marked as someone else';
  }

  @override
  String get viewerUnknownPerson => 'Unknown';

  @override
  String get viewerReassign => 'Change who this is';

  @override
  String get exportTrainingTitle => 'Export for training';

  @override
  String exportTrainingHelp(String name) {
    return 'Cuts full-resolution pictures of $name from your original photos and videos (not the small previews) and zips them with a list of where each came from. Nothing is uploaded.';
  }

  @override
  String get exportTrainingFaces => 'Faces (square)';

  @override
  String get exportTrainingBodies => 'Bodies';

  @override
  String get exportTrainingFaceSize => 'Face size';

  @override
  String get exportTrainingBodySize => 'Body long side';

  @override
  String get exportTrainingPerVideo => 'Most pictures per video';

  @override
  String get exportTrainingStart => 'Start export';

  @override
  String get exportTrainingNeedKind => 'Choose faces, bodies or both.';

  @override
  String get exportTrainingPlanning => 'Choosing the pictures…';

  @override
  String exportTrainingRunning(int done, int total) {
    return 'Cutting $done of $total';
  }

  @override
  String get exportTrainingPacking => 'Building the zip…';

  @override
  String get exportTrainingStop => 'Stop';

  @override
  String get exportTrainingStopped =>
      'Stopped. Finished pictures are kept; start again to continue.';

  @override
  String exportTrainingDone(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pictures exported',
      one: '1 picture exported',
    );
    return '$_temp0';
  }

  @override
  String exportTrainingSkipped(int small, int missing, int failed) {
    return '$small too small · $missing originals unavailable · $failed failed';
  }

  @override
  String get exportTrainingNothing => 'No picture could be exported.';

  @override
  String exportTrainingFailed(String error) {
    return 'Export failed: $error';
  }

  @override
  String get exportTrainingShare => 'Share zip';

  @override
  String get exportTrainingNotification => 'Exporting training pictures';

  @override
  String get bodiesTitle => 'Bodies';

  @override
  String get bodiesTabAll => 'All';

  @override
  String get bodiesTabPoses => 'Poses';

  @override
  String get bodiesTabOutfits => 'Outfits';

  @override
  String get bodiesEmpty =>
      'No bodies to show. Scan photos that show people first.';

  @override
  String get bodiesPreparing => 'Preparing pose data…';

  @override
  String get bodiesSimilarTitle => 'Similar poses';

  @override
  String get bodiesClearFilter => 'Clear';

  @override
  String get bodiesNothingMatches => 'Nothing matches this filter.';

  @override
  String get poseTagLying => 'Lying';

  @override
  String get poseTagStanding => 'Standing';

  @override
  String get poseTagSitting => 'Sitting';

  @override
  String get poseTagArmsUp => 'Both arms up';

  @override
  String get poseTagOneArmUp => 'One arm up';

  @override
  String get poseTagArmsSpread => 'Arms spread';

  @override
  String get poseTagHandsOnHips => 'Hands on hips';

  @override
  String get poseTagFrontal => 'Facing the camera';

  @override
  String get poseTagProfile => 'Profile';

  @override
  String get poseTagBack => 'From behind';

  @override
  String get outfitColorWhite => 'White';

  @override
  String get outfitColorLightGrey => 'Light grey';

  @override
  String get outfitColorDarkGrey => 'Dark grey';

  @override
  String get outfitColorBlack => 'Black';

  @override
  String get outfitColorRed => 'Mostly red';

  @override
  String get outfitColorOrange => 'Mostly orange';

  @override
  String get outfitColorYellow => 'Mostly yellow';

  @override
  String get outfitColorGreen => 'Mostly green';

  @override
  String get outfitColorCyan => 'Mostly cyan';

  @override
  String get outfitColorBlue => 'Mostly blue';

  @override
  String get outfitColorPurple => 'Mostly purple';

  @override
  String get outfitColorPink => 'Mostly pink';

  @override
  String get bodyActionSimilarPose => 'Find similar pose';

  @override
  String get bodyActionNamePose => 'Name this pose';

  @override
  String get bodyActionNameOutfit => 'Name this outfit';

  @override
  String get bodyActionOpenPhoto => 'Open the photo';

  @override
  String get categoryNameHint => 'Name';

  @override
  String get categoryNamePoseTitle => 'Name this pose';

  @override
  String get categoryNameOutfitTitle => 'Name this outfit';

  @override
  String get categoryLowerOnly => 'Match the lower half only';

  @override
  String get categoryNoPose =>
      'This pose cannot be measured: the hips or shoulders are not visible.';

  @override
  String get categoryNoOutfit => 'This body has no outfit colours to compare.';

  @override
  String categoryPreviewTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count matches',
      one: '1 match',
    );
    return '$_temp0';
  }

  @override
  String get categoryPreviewHint =>
      'Untick the ones that do not belong. They are never added again.';

  @override
  String get categorySave => 'Save';

  @override
  String get categoryNone =>
      'Nothing saved yet. Open a body and name its pose or outfit.';

  @override
  String get categoryDelete => 'Delete this group';

  @override
  String get categoryRemoveBody => 'Remove from this group';

  @override
  String categoryBodyCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count bodies',
      one: '1 body',
    );
    return '$_temp0';
  }

  @override
  String get bodyActionSimilarExposed =>
      'Find similar photos of this body area';

  @override
  String get bodiesSimilarColoursTitle => 'Similar colours';

  @override
  String get bodyActionSimilarColours => 'Find similar colours';

  @override
  String get bodyActionMarkTattoo => 'Mark a tattoo';

  @override
  String get groupTagGroup => 'Group photos';

  @override
  String get groupTagLineup => 'Side by side';

  @override
  String get groupTagAllFacing => 'Everyone facing the camera';

  @override
  String get markTitle => 'Mark a tattoo';

  @override
  String get markNeedsPerson =>
      'Marking needs a body that belongs to a known person.';

  @override
  String get markNoSegment =>
      'No limb or torso area of this body can be measured.';

  @override
  String get markPickSegment => 'Where on the body?';

  @override
  String get markTapToPlace =>
      'Tap the tattoo on the picture, then set its size.';

  @override
  String get markSize => 'Size';

  @override
  String get markSave => 'Save mark';

  @override
  String get markSaved =>
      'Tattoo saved. Search for it from the person\'s page.';

  @override
  String get markPatchFailed => 'The original photo could not be read.';

  @override
  String get marksTitle => 'Tattoos';

  @override
  String get marksNone =>
      'No tattoos marked yet. Open a photo of this person, tap their body and choose Mark a tattoo.';

  @override
  String get marksSearch => 'Search other photos';

  @override
  String get marksSearching => 'Searching…';

  @override
  String get marksNoHits => 'No matching photos found.';

  @override
  String get marksNoServer => 'Connect to the PC to search.';

  @override
  String get marksYes => 'It is them';

  @override
  String get marksNo => 'Not them';

  @override
  String get marksStrong => 'Strong match';

  @override
  String get marksWeak => 'Possible match';

  @override
  String get marksDelete => 'Delete this mark';

  @override
  String get quickByTattoo => 'Matching tattoo';

  @override
  String get markSegRUpperArm => 'Right upper arm';

  @override
  String get markSegLUpperArm => 'Left upper arm';

  @override
  String get markSegRForearm => 'Right forearm';

  @override
  String get markSegLForearm => 'Left forearm';

  @override
  String get markSegRThigh => 'Right thigh';

  @override
  String get markSegLThigh => 'Left thigh';

  @override
  String get markSegRLowerLeg => 'Right lower leg';

  @override
  String get markSegLLowerLeg => 'Left lower leg';

  @override
  String get markSegChest => 'Chest';

  @override
  String get markSegAbdomen => 'Abdomen';

  @override
  String get markSegRibs => 'Ribs';

  @override
  String get markSegUpperBack => 'Upper back';

  @override
  String get markSegLowerBack => 'Lower back';

  @override
  String get markSegHips => 'Hips';

  @override
  String get bodiesTabAreas => 'Areas';

  @override
  String get clustersToggle => 'Group body areas (experimental)';

  @override
  String get clustersToggleNote =>
      'Groups photos that show the same body area, so a whole group can be given to a person with one tap. Turn it on only after checking the groups are right.';

  @override
  String get clustersEmpty =>
      'No groups yet. They appear once photos with exposed body areas have been scanned.';

  @override
  String clusterTitleChest(int id) {
    return 'Chest area · group $id';
  }

  @override
  String clusterTitleButtocks(int id) {
    return 'Lower-body area · group $id';
  }

  @override
  String get clusterAssign => 'Give this group to a person';

  @override
  String clusterBelongsTo(String name) {
    return 'Belongs to $name';
  }

  @override
  String clusterLinked(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count photos linked',
      one: '1 photo linked',
    );
    return '$_temp0';
  }

  @override
  String get clusterBridgeTitle => 'Photos show both groups';

  @override
  String clusterBridgeAction(int to, int bridges) {
    return 'Also give group $to to the same person ($bridges photos show both)';
  }

  @override
  String get quickByCluster => 'Same body area as photos of this person';

  @override
  String get outlineRetryTitle => 'Retry missing outlines';

  @override
  String outlineRetryPending(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count photos waiting.',
      one: '1 photo waiting.',
      zero: 'No photos waiting.',
    );
    return '$_temp0 Retry when PC memory is available; completed outlines are kept.';
  }

  @override
  String get groupPoseTab => 'Group poses';

  @override
  String get groupPoseIntro =>
      'Compare two to six people as one pose, including their positions and distance from each other. Name an action from a photo to find similar examples.';

  @override
  String get groupPoseName => 'Name group pose / action';

  @override
  String get groupPoseNameHint => 'e.g. Partner stretch';

  @override
  String get groupPoseNamingNote =>
      'Your name describes the action. Matching compares visible poses and spacing; it does not infer what people are doing.';

  @override
  String groupPosePeople(int count) {
    return '$count people';
  }

  @override
  String get groupPoseCannotMeasure =>
      'Use a photo with two to six detected people whose shoulders, hips and enough joints are visible. Overlapping or hidden bodies may need a clearer example.';

  @override
  String get groupPoseEmpty =>
      'No photos with two to six detected people yet. Scan photos with people together first.';

  @override
  String get groupPoseSaved => 'Saved group poses / actions';

  @override
  String get groupPoseChooseExample => 'Choose a photo with people together';

  @override
  String get groupPoseSimilar => 'Find similar group pose';

  @override
  String get groupPoseReference => 'Reference example';

  @override
  String get groupPoseResultsNote =>
      'Ranked by the whole group’s pose and arrangement. Open photos to check the matches. Equipment filters include editable detection suggestions.';

  @override
  String get bodiesTabEquipment => 'Equipment';

  @override
  String get bodiesSelectedExample => 'Use this body as the example';

  @override
  String get bodiesLoadFailed => 'Could not load these photos.';

  @override
  String get bodiesRetry => 'Try again';

  @override
  String get poseBrowseHint =>
      'See each pose before choosing it. Select a pose to view matching bodies.';

  @override
  String get posePostureTitle => 'Posture';

  @override
  String get poseArmsTitle => 'Arms';

  @override
  String get poseDirectionTitle => 'Camera direction';

  @override
  String get poseSavedTitle => 'Your named poses';

  @override
  String get equipmentAreaChest => 'Chest area';

  @override
  String get equipmentAreaLower => 'Lower-body area';

  @override
  String get equipmentAreaChestSimilar => 'Find similar chest areas';

  @override
  String get equipmentAreaLowerSimilar => 'Find similar lower-body areas';

  @override
  String get equipmentIntro =>
      'Equipment detected near people is a suggestion. Check the label and who it belongs to; nearby objects may not actually be in use.';

  @override
  String get equipmentDetectPending => 'Analyze pending photos';

  @override
  String get equipmentConnect =>
      'Connect to a PC with equipment recognition available. Detection waits while a scan is running.';

  @override
  String get equipmentEmpty =>
      'No equipment to show yet. Analyze photos, or open a body and choose Equipment.';

  @override
  String get equipmentReviewHint =>
      'Review equipment and the associated people';

  @override
  String get equipmentDetectPhoto => 'Detect equipment in this photo';

  @override
  String get equipmentDetecting =>
      'Recognizing equipment. The first photo may take a few minutes…';

  @override
  String get equipmentFailed =>
      'Equipment recognition failed. Check the PC connection and try again.';

  @override
  String get equipmentEdit => 'Correct equipment';

  @override
  String get equipmentReject => 'Remove this detection';

  @override
  String get equipmentOwner => 'Associated person';

  @override
  String get equipmentShared => 'Shared / not assigned';

  @override
  String equipmentPerson(int number) {
    return 'Person $number';
  }

  @override
  String get equipmentSuggested => 'Suggested';

  @override
  String get equipmentConfirmed => 'Confirmed';

  @override
  String get equipmentAdd => 'Add missed equipment';

  @override
  String get identityGroupsTitle => 'Groups';

  @override
  String get identityGroupsIntro =>
      'Keep people and characters in named groups, such as Family or One Piece. Groups organize your library without merging identities.';

  @override
  String get identityGroupsEmpty => 'No groups yet';

  @override
  String get identityGroupCreate => 'Create group';

  @override
  String get identityGroupNameHint => 'e.g. One Piece';

  @override
  String get identityGroupAssign => 'Set group';

  @override
  String get identityGroupUngrouped => 'No group';

  @override
  String get identityGroupAll => 'All groups';

  @override
  String get identityGroupDelete => 'Delete group (keep members)';

  @override
  String get identityGroupNameExists =>
      'That group name is already used. Choose a different name.';

  @override
  String get identityGroupNoMedia => 'No photos or videos in this group yet.';

  @override
  String identityGroupMembers(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count members',
      one: '1 member',
    );
    return '$_temp0';
  }

  @override
  String get organizeTitle => 'Move and rename originals';

  @override
  String get organizeIntro =>
      'Review the original photos and videos before moving them on this phone. Android will ask for permission. A running scan pauses during the move. Existing destination files are kept.';

  @override
  String get organizeNaming =>
      'Files use the person or character name, with separate image and video numbers. File types are preserved. Renaming helps organization; visual detection still uses the image or video.';

  @override
  String get organizeApply => 'Move selected originals';

  @override
  String get organizeWorking => 'Moving originals…';

  @override
  String get organizeResume => 'Review interrupted move';

  @override
  String get organizeLoadFailed =>
      'Could not prepare the move. Allow gallery access and use Android 10 or newer, then try again.';

  @override
  String get organizeInterrupted =>
      'The move was interrupted. Refresh, then review the interrupted move to check which files still need moving.';

  @override
  String get organizeNoFiles =>
      'No original photos or videos are linked to the selected identities.';

  @override
  String get organizeSharedHint =>
      'Some files show several selected identities. Choose one destination owner for each shared file.';

  @override
  String get organizeChooseOwner => 'Whose folder should contain this file?';

  @override
  String get organizeSelectNone => 'Select none';

  @override
  String organizeSelection(int images, int videos) {
    return '$images photos · $videos videos selected';
  }

  @override
  String organizeResult(int moved, int remaining) {
    String _temp0 = intl.Intl.pluralLogic(
      moved,
      locale: localeName,
      other: '$moved files organized',
      one: '1 file organized',
    );
    String _temp1 = intl.Intl.pluralLogic(
      remaining,
      locale: localeName,
      other: '$remaining files not moved',
      one: '1 file not moved',
    );
    return '$_temp0 · $_temp1';
  }

  @override
  String organizeStatus(String status) {
    String _temp0 = intl.Intl.selectLogic(status, {
      'ready': 'Ready to move',
      'already': 'Already organized',
      'choose_owner': 'Choose one destination owner',
      'missing': 'Original is unavailable',
      'stale_scan': 'File changed since detection. Scan it again first.',
      'stale': 'File changed after this preview. Refresh to review it.',
      'conflict':
          'A file with this name already exists. Nothing will be replaced.',
      'pending': 'An earlier move needs review first.',
      'moved': 'Moved',
      'cancelled': 'Cancelled — original kept',
      'denied': 'Android did not grant permission',
      'uncertain': 'Check interrupted move to confirm the current location',
      'unsupported': 'This file cannot be moved here',
      'other': 'Could not move this file',
    });
    return '$_temp0';
  }

  @override
  String get organizeCancelPending => 'Cancel remaining queued moves';

  @override
  String get masterOwner => 'Master';

  @override
  String get setAsMasterOwner => 'Set as primary file owner';

  @override
  String get setAsMasterOwnerSubtitle =>
      'Physical media file will be stored in this person\'s folder';

  @override
  String get autoSyncOrganizedFolders => 'Auto-sync organized folders';

  @override
  String get autoSyncOrganizedFoldersHint =>
      'Move files and metadata automatically when people change groups or corrections occur';

  @override
  String get moveWithoutAskingTitle => 'Move photos without asking';

  @override
  String get moveWithoutAskingOn =>
      'Allowed. People\'s folders are in “Your Gallery” on the phone\'s storage (outside DCIM), each photo keeps its .json file beside it, and photos move after a scan with no prompts, also in the background.';

  @override
  String get moveWithoutAskingOff =>
      'Not allowed yet. Without it Android asks before every batch of moves, the .json files cannot be saved and photos are not moved automatically. Tap, then switch on “Allow access to manage all files” for this app, once.';

  @override
  String get saveSidecarMetadata => 'Save sidecar metadata (.json)';

  @override
  String get saveSidecarMetadataHint =>
      'Save portable AI metadata alongside media for zero-rescan restoration';

  @override
  String get discoveryCompareHint =>
      'Compare the reference and result. Pinch either image to inspect the details.';

  @override
  String get discoveryCandidate => 'Result';

  @override
  String get discoverySkeleton => 'Skeleton';

  @override
  String get discoveryAreaGuide => 'Area guide';

  @override
  String discoverySimilarity(int percent) {
    return '$percent% visual similarity';
  }

  @override
  String discoveryCoverage(int percent) {
    return '$percent% shared keypoint coverage';
  }

  @override
  String get discoveryPosePrecision =>
      'Matches compare visible joints and individual limbs. A similarity score is not an identity confidence.';

  @override
  String get discoveryAreaPrecision =>
      'These are visual area matches, not proof of identity. The highlight is an approximate guide.';

  @override
  String get discoveryInspect => 'Inspect result';

  @override
  String get discoveryPoseIntro => 'Compare postures, arms and direction.';

  @override
  String get discoveryOutfitIntro =>
      'Find similar clothing from your saved examples. Colours do not identify a person.';

  @override
  String get discoverySearchSaved => 'Search saved examples';

  @override
  String get discoverySearchEquipment => 'Search equipment';

  @override
  String get discoverySearchAreas => 'Search areas or people';

  @override
  String get discoveryAreaIntro =>
      'Review similar visible regions, compare examples and organise them by person.';

  @override
  String discoveryMatches(int count) {
    return '$count results';
  }

  @override
  String get discoveryAllIntro =>
      'Choose a body to inspect its pose, find similar examples or save an outfit.';

  @override
  String get discoveryNoSearch => 'No saved examples match your search.';

  @override
  String get discoveryAreaAll => 'All regions';

  @override
  String get discoveryBrowse => 'Browse';

  @override
  String get discoveryColours => 'Colours';

  @override
  String get discoveryCompare => 'Compare';

  @override
  String get discoveryAreaMembers => 'Review all examples';

  @override
  String get discoveryRemoveMatch => 'Remove from this group';

  @override
  String get discoveryAreaRemoveHint =>
      'This example will stay out of area groups after rebuilding.';

  @override
  String get discoveryAreaRebuild => 'Refresh area groups';

  @override
  String get discoveryBent => 'Bent';
}

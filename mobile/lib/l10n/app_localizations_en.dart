// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

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
  String get reviewOutfitsEmpty => 'No outfit matches to review';

  @override
  String reviewTabDuplicates(int count) {
    return 'Duplicates ($count)';
  }

  @override
  String reviewTabGroups(int count) {
    return 'New groups ($count)';
  }

  @override
  String reviewTabMatches(int count) {
    return 'Matches ($count)';
  }

  @override
  String reviewTabOutfits(int count) {
    return 'Outfits ($count)';
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
  String get refaceRestorer => 'Face restoration';

  @override
  String get restorerAuto => 'Automatic';

  @override
  String get restorerNone => 'Off';

  @override
  String get refacePreset => 'Realism preset';

  @override
  String get presetNatural => 'Natural';

  @override
  String get presetDetail => 'Maximum detail';

  @override
  String get presetClean => 'Clean';

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
  String get loraBase => 'Base checkpoint';

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
  String get refaceQualityProfile => 'Quality & processing time';

  @override
  String get refaceFast => 'Fast';

  @override
  String get refaceFastSummary =>
      'Less extra processing · no restoration by default';

  @override
  String get refaceFastDescription =>
      'Uses the same Reface pipeline with restoration and face parsing off by default. A good starting point for long videos; fine face detail can be softer. Occlusion protection stays on.';

  @override
  String get refaceBalanced => 'Balanced';

  @override
  String get refaceBalancedSummary =>
      'Detail and processing cost · recommended starting point';

  @override
  String get refaceBalancedDescription =>
      'Adds face restoration and face-region blending. Automatic prefers GPEN 512 when installed, then an available alternative. More processing than Fast, with more restored detail.';

  @override
  String get refaceDetail => 'More detail';

  @override
  String get refaceDetailSummary =>
      'Larger face crops when available · more processing';

  @override
  String get refaceDetailDescription =>
      'Automatic prefers GPEN 1024 when installed, otherwise an available alternative. Useful for large close-up faces; higher resolution costs more processing and does not guarantee a closer likeness.';

  @override
  String get refaceAutoSummary => 'Uses the chosen quality profile';

  @override
  String refaceAutoStartsWith(String model) {
    return 'Starts with $model on this PC';
  }

  @override
  String get refaceAutoDescription =>
      'Uses the available default for the selected quality profile. Fast skips restoration; Balanced prefers GPEN 512; More detail prefers GPEN 1024. If needed, the PC uses another installed model.';

  @override
  String get refaceOffSummary => 'Least restoration work · raw swap detail';

  @override
  String get refaceOffDescription =>
      'Skips the restoration stage while still swapping faces. Reduces processing and keeps the raw swapped face; fine details can be softer.';

  @override
  String get refaceGpen512Summary => 'Balanced face detail · 512 px crop';

  @override
  String get refaceGpen512Description =>
      'A balanced starting point for restored face detail and processing cost in this app. Works on a 512 px face crop and generally needs less processing than GPEN 1024.';

  @override
  String get refaceGpen1024Summary =>
      'Higher face resolution · heavier processing';

  @override
  String get refaceGpen1024Description =>
      'Restores a 1024 px face crop. Can help large close-up faces, with more processing and memory than the 512 model. Higher resolution does not guarantee a better likeness.';

  @override
  String get refaceCodeformerSummary =>
      'Rebuild degraded detail · extra AI processing';

  @override
  String get refaceCodeformerDescription =>
      'Repairs degraded facial detail with a tradeoff between reconstructed detail and fidelity. It can change fine facial features, so compare a preview when likeness matters.';

  @override
  String get refaceGfpganSummary =>
      'General face restoration · extra AI processing';

  @override
  String get refaceGfpganDescription =>
      'Restores blurry or degraded facial detail using learned face patterns. Useful as an alternative look; compare a preview for both texture and likeness.';

  @override
  String get refaceRestoreformerSummary =>
      'Alternative face restoration · extra AI processing';

  @override
  String get refaceRestoreformerDescription =>
      'Reconstructs degraded facial detail using learned face information. Try it when other restorers do not suit the face; processing time and likeness depend on the input and PC.';

  @override
  String get refaceOtherModelSummary => 'PC-provided restoration model';

  @override
  String get refaceOtherModelDescription =>
      'This model is available on the PC. No speed or likeness comparison is defined here; use a short preview to compare it.';

  @override
  String get refaceRestorationIntro =>
      'Restoration improves face detail after swapping. Model sizes describe face crops, not the output photo or video resolution.';

  @override
  String get refaceSpeedNote =>
      'Processing time depends on the PC, frame size and number of faces. Compare a short preview for both detail and likeness.';

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
  String get refaceIdentityBoost => 'Identity strength';

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
  String get reviewIntro => 'Help your library recognize the right people.';

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
}

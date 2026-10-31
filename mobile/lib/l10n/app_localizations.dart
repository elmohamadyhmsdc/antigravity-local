import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[Locale('en')];

  /// No description provided for @reviewPhotos.
  ///
  /// In en, this message translates to:
  /// **'Review photos'**
  String get reviewPhotos;

  /// No description provided for @reviewFullPhoto.
  ///
  /// In en, this message translates to:
  /// **'Show full photo'**
  String get reviewFullPhoto;

  /// No description provided for @reviewCrop.
  ///
  /// In en, this message translates to:
  /// **'Show close-up'**
  String get reviewCrop;

  /// No description provided for @reviewNoPhotos.
  ///
  /// In en, this message translates to:
  /// **'No photos are available for this suggestion.'**
  String get reviewNoPhotos;

  /// No description provided for @reviewFaceHighlighted.
  ///
  /// In en, this message translates to:
  /// **'Review the face inside the yellow box'**
  String get reviewFaceHighlighted;

  /// No description provided for @reviewBodyHighlighted.
  ///
  /// In en, this message translates to:
  /// **'Review the body inside the yellow box'**
  String get reviewBodyHighlighted;

  /// No description provided for @reviewViewerHint.
  ///
  /// In en, this message translates to:
  /// **'Swipe to see every photo. Pinch a photo to zoom. Use the crop button for a close-up.'**
  String get reviewViewerHint;

  /// No description provided for @reviewVideoHint.
  ///
  /// In en, this message translates to:
  /// **'The video opens at the highlighted sample. Use the crop button for a close-up, or move to the next photo.'**
  String get reviewVideoHint;

  /// No description provided for @reviewOriginalMissing.
  ///
  /// In en, this message translates to:
  /// **'The original is unavailable. This is the saved crop only.'**
  String get reviewOriginalMissing;

  /// No description provided for @reviewPreviousPhoto.
  ///
  /// In en, this message translates to:
  /// **'Previous photo'**
  String get reviewPreviousPhoto;

  /// No description provided for @reviewNextPhoto.
  ///
  /// In en, this message translates to:
  /// **'Next photo'**
  String get reviewNextPhoto;

  /// No description provided for @reviewFace.
  ///
  /// In en, this message translates to:
  /// **'This face'**
  String get reviewFace;

  /// No description provided for @reviewBody.
  ///
  /// In en, this message translates to:
  /// **'This body'**
  String get reviewBody;

  /// No description provided for @reviewViewAll.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1 {View photo} other {View all {count} photos}}'**
  String reviewViewAll(int count);

  /// No description provided for @reviewMatchQuestion.
  ///
  /// In en, this message translates to:
  /// **'Is this {name}?'**
  String reviewMatchQuestion(String name);

  /// No description provided for @reviewGroupQuestion.
  ///
  /// In en, this message translates to:
  /// **'Are these the same person?'**
  String get reviewGroupQuestion;

  /// No description provided for @reviewMatchHelp.
  ///
  /// In en, this message translates to:
  /// **'Open a photo to inspect it. Use the checkboxes to choose which faces to add or reject.'**
  String get reviewMatchHelp;

  /// No description provided for @reviewGroupHelp.
  ///
  /// In en, this message translates to:
  /// **'Review every photo and uncheck any face that does not belong. Then create a person or add the selected faces to someone you know.'**
  String get reviewGroupHelp;

  /// No description provided for @reviewOutfitQuestion.
  ///
  /// In en, this message translates to:
  /// **'Does this body belong to {name}?'**
  String reviewOutfitQuestion(String name);

  /// No description provided for @reviewOutfitHelp.
  ///
  /// In en, this message translates to:
  /// **'This is a suggestion based on clothing or a weak face match. Check the highlighted body in the original before deciding.'**
  String get reviewOutfitHelp;

  /// No description provided for @reviewYesPerson.
  ///
  /// In en, this message translates to:
  /// **'Yes, {name}'**
  String reviewYesPerson(String name);

  /// No description provided for @reviewNotPerson.
  ///
  /// In en, this message translates to:
  /// **'No, someone else'**
  String get reviewNotPerson;

  /// No description provided for @reviewIncludeFace.
  ///
  /// In en, this message translates to:
  /// **'Include this face'**
  String get reviewIncludeFace;

  /// No description provided for @reviewReferencePhotos.
  ///
  /// In en, this message translates to:
  /// **'Known photos'**
  String get reviewReferencePhotos;

  /// No description provided for @peopleAction.
  ///
  /// In en, this message translates to:
  /// **'{action, select, selection {Select multiple} open {Open person} merge {Merge with…} rename {Rename} hide {Hide} show {Show again} pin {Pin to top} unpin {Unpin} favorite {Add to favorites} unfavorite {Remove from favorites} media {Photos and videos} add {Add faces…} split {Split into new person…} suggestions {Review match suggestions} distinct {Different from…} lock {Lock automatic matching} unlock {Unlock automatic matching} studio {Use in Studio} export {Export / share…} details {Details} cover {Change cover…} bestCover {Choose best cover automatically} chooseCover {Choose cover face…} deletePerson {Delete person grouping} original {Open original} assign {Assign / move to person…} create {Create new person…} reject {Not this person} remove {Remove from person…} someoneElse {This is someone else} notAFace {Not a face} moveTo {Move to…} unassign {Remove assignment} similar {Find similar faces} save {Save crop to gallery} deleteFace {Delete detection} ignore {Not a face / ignore detection} hidden {Hidden} all {All} favorites {Favorites} pinned {Pinned} invert {Invert selection} more {More actions} done {Done} undo {Undo} updated {Updated} noResults {No items in this view} exportCrops {Face crops and details} exportOriginals {Face crops and original media} lockedNote {Automatic matching cannot add faces or change derived body links for a locked person. Manual corrections remain available.} deletePersonNote {Remove these person groupings and return their faces to Unsorted. Original photos and videos are kept.} deleteFaceNote {Remove these detections and their private crops. Rescanning will not recreate them. Original photos and videos are kept.} mergeNote {All selected people will be merged into the chosen person. Review the resulting name and cover before confirming.} similarNote {Similarity is a suggestion. Open an original or assign selected faces after checking them.} emptyExport {No readable files were available to export.} other {More actions}}'**
  String peopleAction(String action);

  /// No description provided for @peopleActionError.
  ///
  /// In en, this message translates to:
  /// **'Could not complete the action: {reason}'**
  String peopleActionError(String reason);

  /// No description provided for @videoOpening.
  ///
  /// In en, this message translates to:
  /// **'Opening video…'**
  String get videoOpening;

  /// No description provided for @videoLastRecorded.
  ///
  /// In en, this message translates to:
  /// **'Last recorded progress · scan is not currently advancing'**
  String get videoLastRecorded;

  /// No description provided for @videoWaiting.
  ///
  /// In en, this message translates to:
  /// **'Waiting for PC analysis…'**
  String get videoWaiting;

  /// No description provided for @videoVerifying.
  ///
  /// In en, this message translates to:
  /// **'Verifying downloaded results…'**
  String get videoVerifying;

  /// No description provided for @videoFinishing.
  ///
  /// In en, this message translates to:
  /// **'Finalizing video results…'**
  String get videoFinishing;

  /// No description provided for @videoStepPrepare.
  ///
  /// In en, this message translates to:
  /// **'Prepare'**
  String get videoStepPrepare;

  /// No description provided for @videoStepUpload.
  ///
  /// In en, this message translates to:
  /// **'Upload'**
  String get videoStepUpload;

  /// No description provided for @videoStepAnalyze.
  ///
  /// In en, this message translates to:
  /// **'Analyze'**
  String get videoStepAnalyze;

  /// No description provided for @videoStepSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get videoStepSave;

  /// No description provided for @videoPrepareDetail.
  ///
  /// In en, this message translates to:
  /// **'Reading the video on this phone and calculating its fingerprint before upload. Large videos take longer here.'**
  String get videoPrepareDetail;

  /// No description provided for @videoUploadDetail.
  ///
  /// In en, this message translates to:
  /// **'Sending the original video to your PC in resumable chunks. Analysis starts after the upload finishes.'**
  String get videoUploadDetail;

  /// No description provided for @videoUploadConfirming.
  ///
  /// In en, this message translates to:
  /// **'Video bytes sent. Waiting for the PC to confirm the upload.'**
  String get videoUploadConfirming;

  /// No description provided for @videoQueueDetail.
  ///
  /// In en, this message translates to:
  /// **'The video request is on the PC. Waiting for the analysis worker to start or resume.'**
  String get videoQueueDetail;

  /// No description provided for @videoDecodeDetail.
  ///
  /// In en, this message translates to:
  /// **'The PC is reading and decoding the next sampled frame.'**
  String get videoDecodeDetail;

  /// No description provided for @videoInferenceDetail.
  ///
  /// In en, this message translates to:
  /// **'The PC is detecting faces and people in the current sampled frame.'**
  String get videoInferenceDetail;

  /// No description provided for @videoAnalyzeDetail.
  ///
  /// In en, this message translates to:
  /// **'The PC is analyzing sampled frames. The video is still in progress even while new results are saved below.'**
  String get videoAnalyzeDetail;

  /// No description provided for @videoDownloadDetail.
  ///
  /// In en, this message translates to:
  /// **'Receiving the completed detections from your PC before saving them on this phone.'**
  String get videoDownloadDetail;

  /// No description provided for @videoVerifyDetail.
  ///
  /// In en, this message translates to:
  /// **'Checking the result file size and fingerprint before importing detections.'**
  String get videoVerifyDetail;

  /// No description provided for @videoImportDetail.
  ///
  /// In en, this message translates to:
  /// **'Saving verified detections and crops into this phone’s library.'**
  String get videoImportDetail;

  /// No description provided for @videoFinishDetail.
  ///
  /// In en, this message translates to:
  /// **'Finishing the result file and confirming the saved video. This can take a moment for large videos.'**
  String get videoFinishDetail;

  /// No description provided for @videoStagePercent.
  ///
  /// In en, this message translates to:
  /// **'{percent}% of this stage'**
  String videoStagePercent(int percent);

  /// No description provided for @videoElapsed.
  ///
  /// In en, this message translates to:
  /// **'Time on this video'**
  String get videoElapsed;

  /// No description provided for @videoFile.
  ///
  /// In en, this message translates to:
  /// **'Video file'**
  String get videoFile;

  /// No description provided for @videoSource.
  ///
  /// In en, this message translates to:
  /// **'Original video'**
  String get videoSource;

  /// No description provided for @videoStageElapsed.
  ///
  /// In en, this message translates to:
  /// **'Time in this stage'**
  String get videoStageElapsed;

  /// No description provided for @videoBytesRead.
  ///
  /// In en, this message translates to:
  /// **'Video data read'**
  String get videoBytesRead;

  /// No description provided for @videoBytesSent.
  ///
  /// In en, this message translates to:
  /// **'Video data sent'**
  String get videoBytesSent;

  /// No description provided for @videoBytesReceived.
  ///
  /// In en, this message translates to:
  /// **'Results received'**
  String get videoBytesReceived;

  /// No description provided for @videoTransferSpeed.
  ///
  /// In en, this message translates to:
  /// **'Average transfer speed'**
  String get videoTransferSpeed;

  /// No description provided for @videoStageRemaining.
  ///
  /// In en, this message translates to:
  /// **'Estimated time left in this stage'**
  String get videoStageRemaining;

  /// No description provided for @videoMeasuring.
  ///
  /// In en, this message translates to:
  /// **'Measuring…'**
  String get videoMeasuring;

  /// No description provided for @videoApproximate.
  ///
  /// In en, this message translates to:
  /// **'About {time}'**
  String videoApproximate(String time);

  /// No description provided for @videoPosition.
  ///
  /// In en, this message translates to:
  /// **'Analyzed video position'**
  String get videoPosition;

  /// No description provided for @videoSamplesAnalyzed.
  ///
  /// In en, this message translates to:
  /// **'Samples processed (including skipped)'**
  String get videoSamplesAnalyzed;

  /// No description provided for @videoSampling.
  ///
  /// In en, this message translates to:
  /// **'Sampling interval'**
  String get videoSampling;

  /// No description provided for @videoSamplingSeconds.
  ///
  /// In en, this message translates to:
  /// **'One frame every {seconds} s'**
  String videoSamplingSeconds(String seconds);

  /// No description provided for @videoLiveSaving.
  ///
  /// In en, this message translates to:
  /// **'Available results are saved as the PC works. Counts below are for this video session.'**
  String get videoLiveSaving;

  /// No description provided for @videoSavedSamples.
  ///
  /// In en, this message translates to:
  /// **'Samples saved on this phone'**
  String get videoSavedSamples;

  /// No description provided for @videoLiveDetections.
  ///
  /// In en, this message translates to:
  /// **'New detections saved'**
  String get videoLiveDetections;

  /// No description provided for @videoDetectionCounts.
  ///
  /// In en, this message translates to:
  /// **'{faces} faces · {bodies} bodies · {characters} characters'**
  String videoDetectionCounts(int faces, int bodies, int characters);

  /// No description provided for @videoSkippedSamples.
  ///
  /// In en, this message translates to:
  /// **'Unreadable samples skipped'**
  String get videoSkippedSamples;

  /// No description provided for @videoPcUpdate.
  ///
  /// In en, this message translates to:
  /// **'Last PC response'**
  String get videoPcUpdate;

  /// No description provided for @videoSecondsAgo.
  ///
  /// In en, this message translates to:
  /// **'{seconds} s ago'**
  String videoSecondsAgo(int seconds);

  /// No description provided for @videoAwaitingUpdate.
  ///
  /// In en, this message translates to:
  /// **'No new progress for {seconds} s. Waiting for the current operation to respond; you can pause the scan.'**
  String videoAwaitingUpdate(int seconds);

  /// No description provided for @videoLibraryProgress.
  ///
  /// In en, this message translates to:
  /// **'Overall library progress'**
  String get videoLibraryProgress;

  /// No description provided for @scanItemsOf.
  ///
  /// In en, this message translates to:
  /// **'{done} of {total} items complete'**
  String scanItemsOf(int done, int total);

  /// No description provided for @videoAdaptiveSampling.
  ///
  /// In en, this message translates to:
  /// **'Automatic video sampling'**
  String get videoAdaptiveSampling;

  /// No description provided for @videoAdaptiveSamplingHint.
  ///
  /// In en, this message translates to:
  /// **'Short clips use closer samples; longer videos use wider intervals. About 0.5 s for a short clip and 5 s for a 40-minute video.'**
  String get videoAdaptiveSamplingHint;

  /// No description provided for @scanCurrentPhoto.
  ///
  /// In en, this message translates to:
  /// **'Current photo'**
  String get scanCurrentPhoto;

  /// No description provided for @scanCurrentVideo.
  ///
  /// In en, this message translates to:
  /// **'Current video frame'**
  String get scanCurrentVideo;

  /// No description provided for @scanPreviewUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Preview unavailable'**
  String get scanPreviewUnavailable;

  /// App name shown in the title bar and task switcher.
  ///
  /// In en, this message translates to:
  /// **'Your Gallery'**
  String get appTitle;

  /// No description provided for @navHome.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get navHome;

  /// No description provided for @navPeople.
  ///
  /// In en, this message translates to:
  /// **'People'**
  String get navPeople;

  /// No description provided for @navLibrary.
  ///
  /// In en, this message translates to:
  /// **'Library'**
  String get navLibrary;

  /// No description provided for @navStudio.
  ///
  /// In en, this message translates to:
  /// **'Studio'**
  String get navStudio;

  /// No description provided for @navJobs.
  ///
  /// In en, this message translates to:
  /// **'Jobs'**
  String get navJobs;

  /// No description provided for @settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get retry;

  /// No description provided for @back.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get back;

  /// Placeholder shown on screens that are not built yet.
  ///
  /// In en, this message translates to:
  /// **'Coming in phase {phase}'**
  String comingInPhase(String phase);

  /// No description provided for @peoplePlaceholder.
  ///
  /// In en, this message translates to:
  /// **'Everyone found in your photos and videos, grouped by identity.'**
  String get peoplePlaceholder;

  /// No description provided for @libraryPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'Your photos and videos, with who is in each one.'**
  String get libraryPlaceholder;

  /// No description provided for @studioPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'Reface, Restyle and Character LoRA.'**
  String get studioPlaceholder;

  /// No description provided for @jobsPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'Running, queued, paused and finished GPU jobs.'**
  String get jobsPlaceholder;

  /// No description provided for @settingsPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'Pairing, grouping strictness, scan defaults and app lock.'**
  String get settingsPlaceholder;

  /// No description provided for @welcomeTitle.
  ///
  /// In en, this message translates to:
  /// **'Connect to your PC'**
  String get welcomeTitle;

  /// No description provided for @welcomeBody.
  ///
  /// In en, this message translates to:
  /// **'Your Gallery does the heavy AI work on your Windows PC. Your photos, faces and results stay on this phone - the PC only computes.'**
  String get welcomeBody;

  /// No description provided for @welcomeSameWifi.
  ///
  /// In en, this message translates to:
  /// **'Your phone and PC must be on the same Wi-Fi.'**
  String get welcomeSameWifi;

  /// No description provided for @welcomeScan.
  ///
  /// In en, this message translates to:
  /// **'Scan QR code'**
  String get welcomeScan;

  /// No description provided for @welcomeManual.
  ///
  /// In en, this message translates to:
  /// **'Enter address manually'**
  String get welcomeManual;

  /// No description provided for @welcomeStep.
  ///
  /// In en, this message translates to:
  /// **'On the PC, run run_mobile_api.bat. It opens a page with a QR code.'**
  String get welcomeStep;

  /// No description provided for @scanTitle.
  ///
  /// In en, this message translates to:
  /// **'Scan the QR code'**
  String get scanTitle;

  /// No description provided for @scanHint.
  ///
  /// In en, this message translates to:
  /// **'Point the camera at the QR code on your PC\'s pairing page.'**
  String get scanHint;

  /// No description provided for @scanNotPairingCode.
  ///
  /// In en, this message translates to:
  /// **'That is not a Your Gallery pairing code.'**
  String get scanNotPairingCode;

  /// No description provided for @scanCameraDenied.
  ///
  /// In en, this message translates to:
  /// **'Camera access is needed to scan the code. You can also enter the address manually.'**
  String get scanCameraDenied;

  /// No description provided for @scanEnterManually.
  ///
  /// In en, this message translates to:
  /// **'Enter address manually'**
  String get scanEnterManually;

  /// No description provided for @manualTitle.
  ///
  /// In en, this message translates to:
  /// **'Enter the address'**
  String get manualTitle;

  /// No description provided for @manualIntro.
  ///
  /// In en, this message translates to:
  /// **'Type the address and pairing code shown on your PC\'s pairing page.'**
  String get manualIntro;

  /// No description provided for @manualHostLabel.
  ///
  /// In en, this message translates to:
  /// **'PC address'**
  String get manualHostLabel;

  /// No description provided for @manualHostHint.
  ///
  /// In en, this message translates to:
  /// **'192.168.1.20'**
  String get manualHostHint;

  /// No description provided for @manualPortLabel.
  ///
  /// In en, this message translates to:
  /// **'Port'**
  String get manualPortLabel;

  /// No description provided for @manualCodeLabel.
  ///
  /// In en, this message translates to:
  /// **'Pairing code'**
  String get manualCodeLabel;

  /// No description provided for @manualCodeHint.
  ///
  /// In en, this message translates to:
  /// **'K7QM-3XRD'**
  String get manualCodeHint;

  /// No description provided for @manualConnect.
  ///
  /// In en, this message translates to:
  /// **'Connect'**
  String get manualConnect;

  /// No description provided for @errHostEmpty.
  ///
  /// In en, this message translates to:
  /// **'Enter the PC\'s address.'**
  String get errHostEmpty;

  /// No description provided for @errHostInvalid.
  ///
  /// In en, this message translates to:
  /// **'That is not a valid address.'**
  String get errHostInvalid;

  /// No description provided for @errHostNotLan.
  ///
  /// In en, this message translates to:
  /// **'The PC must be on your Wi-Fi (an address like 192.168.x.x or 10.x.x.x).'**
  String get errHostNotLan;

  /// No description provided for @errPortInvalid.
  ///
  /// In en, this message translates to:
  /// **'Enter a port between 1 and 65535.'**
  String get errPortInvalid;

  /// No description provided for @errCodeInvalid.
  ///
  /// In en, this message translates to:
  /// **'The code has 8 letters and digits, like K7QM-3XRD.'**
  String get errCodeInvalid;

  /// No description provided for @confirmFingerprintTitle.
  ///
  /// In en, this message translates to:
  /// **'Is this your PC?'**
  String get confirmFingerprintTitle;

  /// No description provided for @confirmFingerprintBody.
  ///
  /// In en, this message translates to:
  /// **'Compare this fingerprint with the one on your PC\'s pairing page. Only continue if they are identical.'**
  String get confirmFingerprintBody;

  /// No description provided for @confirmFingerprintYes.
  ///
  /// In en, this message translates to:
  /// **'They match - pair'**
  String get confirmFingerprintYes;

  /// No description provided for @pairLinkTitle.
  ///
  /// In en, this message translates to:
  /// **'Pair with {host}?'**
  String pairLinkTitle(String host);

  /// No description provided for @pairLinkBody.
  ///
  /// In en, this message translates to:
  /// **'A link asked this phone to pair with a PC at {host}. Only continue if you started this on your own PC.'**
  String pairLinkBody(String host);

  /// No description provided for @pairLinkInvalid.
  ///
  /// In en, this message translates to:
  /// **'That pairing link is not valid, or it does not point to a PC on your Wi-Fi.'**
  String get pairLinkInvalid;

  /// No description provided for @pairLinkContinue.
  ///
  /// In en, this message translates to:
  /// **'Pair'**
  String get pairLinkContinue;

  /// No description provided for @pairingConnecting.
  ///
  /// In en, this message translates to:
  /// **'Connecting to {host}…'**
  String pairingConnecting(String host);

  /// No description provided for @permissionsTitle.
  ///
  /// In en, this message translates to:
  /// **'Permissions'**
  String get permissionsTitle;

  /// No description provided for @permissionsIntro.
  ///
  /// In en, this message translates to:
  /// **'Your Gallery asks only for what it needs. You can change these later in Android settings.'**
  String get permissionsIntro;

  /// No description provided for @permMediaTitle.
  ///
  /// In en, this message translates to:
  /// **'Photos and videos'**
  String get permMediaTitle;

  /// No description provided for @permMediaWhy.
  ///
  /// In en, this message translates to:
  /// **'To find faces in your library. Files are read in place and never copied or uploaded in full - only downscaled pictures are sent to your own PC.'**
  String get permMediaWhy;

  /// No description provided for @permCameraTitle.
  ///
  /// In en, this message translates to:
  /// **'Camera'**
  String get permCameraTitle;

  /// No description provided for @permCameraWhy.
  ///
  /// In en, this message translates to:
  /// **'Only to scan the pairing QR code.'**
  String get permCameraWhy;

  /// No description provided for @permNotificationsTitle.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get permNotificationsTitle;

  /// No description provided for @permNotificationsWhy.
  ///
  /// In en, this message translates to:
  /// **'So you hear when a long job on your PC has finished.'**
  String get permNotificationsWhy;

  /// No description provided for @permAllow.
  ///
  /// In en, this message translates to:
  /// **'Allow'**
  String get permAllow;

  /// No description provided for @permGranted.
  ///
  /// In en, this message translates to:
  /// **'Allowed'**
  String get permGranted;

  /// No description provided for @permBlocked.
  ///
  /// In en, this message translates to:
  /// **'Blocked - open settings'**
  String get permBlocked;

  /// No description provided for @permContinue.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get permContinue;

  /// No description provided for @homeStatusChecking.
  ///
  /// In en, this message translates to:
  /// **'Checking…'**
  String get homeStatusChecking;

  /// No description provided for @homeStatusConnected.
  ///
  /// In en, this message translates to:
  /// **'{name}'**
  String homeStatusConnected(String name);

  /// No description provided for @homeStatusBusy.
  ///
  /// In en, this message translates to:
  /// **'{name} - busy'**
  String homeStatusBusy(String name);

  /// No description provided for @homeStatusOffline.
  ///
  /// In en, this message translates to:
  /// **'PC offline'**
  String get homeStatusOffline;

  /// No description provided for @homeStatusRevoked.
  ///
  /// In en, this message translates to:
  /// **'Pairing revoked'**
  String get homeStatusRevoked;

  /// No description provided for @homeStatusTooltip.
  ///
  /// In en, this message translates to:
  /// **'Tap to check the connection'**
  String get homeStatusTooltip;

  /// No description provided for @homeBusyBanner.
  ///
  /// In en, this message translates to:
  /// **'Your PC\'s GPU is busy with a {job} job.'**
  String homeBusyBanner(String job);

  /// No description provided for @homeOfflineBanner.
  ///
  /// In en, this message translates to:
  /// **'Cannot reach your PC. Is the server running and is this phone on the same Wi-Fi?'**
  String get homeOfflineBanner;

  /// No description provided for @homeRevokedBanner.
  ///
  /// In en, this message translates to:
  /// **'This phone was removed on the PC. Pair again to continue.'**
  String get homeRevokedBanner;

  /// No description provided for @homePairAgain.
  ///
  /// In en, this message translates to:
  /// **'Pair again'**
  String get homePairAgain;

  /// No description provided for @statPeople.
  ///
  /// In en, this message translates to:
  /// **'People'**
  String get statPeople;

  /// No description provided for @statFaces.
  ///
  /// In en, this message translates to:
  /// **'Faces'**
  String get statFaces;

  /// No description provided for @statPhotos.
  ///
  /// In en, this message translates to:
  /// **'Photos'**
  String get statPhotos;

  /// No description provided for @statVideos.
  ///
  /// In en, this message translates to:
  /// **'Videos'**
  String get statVideos;

  /// No description provided for @unsortedFaces.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No unsorted faces} =1{1 unsorted face} other{{count} unsorted faces}}'**
  String unsortedFaces(int count);

  /// No description provided for @emptyLibraryTitle.
  ///
  /// In en, this message translates to:
  /// **'Your library is empty'**
  String get emptyLibraryTitle;

  /// No description provided for @emptyLibraryBody.
  ///
  /// In en, this message translates to:
  /// **'Choose albums to scan and the people in your photos show up here. You can also test face detection on a single photo.'**
  String get emptyLibraryBody;

  /// No description provided for @tryDetectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Detect faces in a photo'**
  String get tryDetectionTitle;

  /// No description provided for @tryDetectionBody.
  ///
  /// In en, this message translates to:
  /// **'Sends one downscaled photo to your PC and shows what it finds.'**
  String get tryDetectionBody;

  /// No description provided for @forgetPc.
  ///
  /// In en, this message translates to:
  /// **'Forget this PC'**
  String get forgetPc;

  /// No description provided for @forgetPcTitle.
  ///
  /// In en, this message translates to:
  /// **'Forget {name}?'**
  String forgetPcTitle(String name);

  /// No description provided for @forgetPcBody.
  ///
  /// In en, this message translates to:
  /// **'This phone will be unpaired. Everything in your library stays on the phone.'**
  String get forgetPcBody;

  /// No description provided for @forgetPcConfirm.
  ///
  /// In en, this message translates to:
  /// **'Forget'**
  String get forgetPcConfirm;

  /// No description provided for @analyzeTitle.
  ///
  /// In en, this message translates to:
  /// **'Detect faces'**
  String get analyzeTitle;

  /// No description provided for @analyzePick.
  ///
  /// In en, this message translates to:
  /// **'Choose a photo'**
  String get analyzePick;

  /// No description provided for @analyzePickAnother.
  ///
  /// In en, this message translates to:
  /// **'Choose another photo'**
  String get analyzePickAnother;

  /// No description provided for @analyzeIdle.
  ///
  /// In en, this message translates to:
  /// **'Pick a photo from your gallery. It is downscaled and analysed on your PC; nothing is stored there.'**
  String get analyzeIdle;

  /// No description provided for @analyzing.
  ///
  /// In en, this message translates to:
  /// **'Analysing on {name}…'**
  String analyzing(String name);

  /// No description provided for @analyzeFacesFound.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No faces found} =1{1 face found} other{{count} faces found}}'**
  String analyzeFacesFound(int count);

  /// No description provided for @analyzeBodiesFound.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{no bodies} =1{1 body} other{{count} bodies}}'**
  String analyzeBodiesFound(int count);

  /// No description provided for @analyzeSummary.
  ///
  /// In en, this message translates to:
  /// **'{faces} · {bodies} · {width}×{height} · {ms} ms'**
  String analyzeSummary(
    String faces,
    String bodies,
    int width,
    int height,
    int ms,
  );

  /// No description provided for @analyzeFaceTitle.
  ///
  /// In en, this message translates to:
  /// **'Face {number}'**
  String analyzeFaceTitle(int number);

  /// No description provided for @analyzeFaceDetail.
  ///
  /// In en, this message translates to:
  /// **'{pixels} px · detector {det}'**
  String analyzeFaceDetail(int pixels, String det);

  /// No description provided for @analyzeQuality.
  ///
  /// In en, this message translates to:
  /// **'{tier} {score}'**
  String analyzeQuality(String tier, String score);

  /// No description provided for @analyzeMeetsGate.
  ///
  /// In en, this message translates to:
  /// **'Would be saved'**
  String get analyzeMeetsGate;

  /// No description provided for @analyzeBelowGate.
  ///
  /// In en, this message translates to:
  /// **'Too small or unclear - skipped'**
  String get analyzeBelowGate;

  /// No description provided for @tierGreat.
  ///
  /// In en, this message translates to:
  /// **'Great'**
  String get tierGreat;

  /// No description provided for @tierGood.
  ///
  /// In en, this message translates to:
  /// **'Good'**
  String get tierGood;

  /// No description provided for @tierFair.
  ///
  /// In en, this message translates to:
  /// **'Fair'**
  String get tierFair;

  /// No description provided for @tierPoor.
  ///
  /// In en, this message translates to:
  /// **'Poor'**
  String get tierPoor;

  /// No description provided for @analyzeNoFaces.
  ///
  /// In en, this message translates to:
  /// **'No faces were found in this photo.'**
  String get analyzeNoFaces;

  /// No description provided for @gpuBusyMessage.
  ///
  /// In en, this message translates to:
  /// **'Your PC\'s GPU is busy right now. Try again in a moment.'**
  String get gpuBusyMessage;

  /// No description provided for @analyzeFailed.
  ///
  /// In en, this message translates to:
  /// **'Analysis failed'**
  String get analyzeFailed;

  /// No description provided for @startupErrorTitle.
  ///
  /// In en, this message translates to:
  /// **'Your Gallery could not open its database'**
  String get startupErrorTitle;

  /// No description provided for @startupErrorBody.
  ///
  /// In en, this message translates to:
  /// **'Your library is stored encrypted on this phone and could not be opened. Details:'**
  String get startupErrorBody;

  /// No description provided for @accept.
  ///
  /// In en, this message translates to:
  /// **'Accept'**
  String get accept;

  /// No description provided for @acceptAllMatches.
  ///
  /// In en, this message translates to:
  /// **'Accept all {count, plural, =1{1 match} other{{count} matches}}'**
  String acceptAllMatches(int count);

  /// No description provided for @acceptAllMatchesBody.
  ///
  /// In en, this message translates to:
  /// **'Every suggested face is added to the person it looks like. You can still move faces afterwards.'**
  String get acceptAllMatchesBody;

  /// No description provided for @acceptAllOutfits.
  ///
  /// In en, this message translates to:
  /// **'Accept all {count, plural, =1{1 outfit match} other{{count} outfit matches}}'**
  String acceptAllOutfits(int count);

  /// No description provided for @addFacesTo.
  ///
  /// In en, this message translates to:
  /// **'Add {count, plural, =1{1 face} other{{count} faces}}'**
  String addFacesTo(int count);

  /// No description provided for @addToPerson.
  ///
  /// In en, this message translates to:
  /// **'Add to a person…'**
  String get addToPerson;

  /// No description provided for @albumsHint.
  ///
  /// In en, this message translates to:
  /// **'Choose the albums whose items should be scanned. Photos stay on this phone; only a downscaled copy of each is sent to your PC.'**
  String get albumsHint;

  /// No description provided for @albumsTitle.
  ///
  /// In en, this message translates to:
  /// **'Albums to scan'**
  String get albumsTitle;

  /// No description provided for @allPhotos.
  ///
  /// In en, this message translates to:
  /// **'All photos'**
  String get allPhotos;

  /// No description provided for @allowPhotoAccess.
  ///
  /// In en, this message translates to:
  /// **'Allow photo access'**
  String get allowPhotoAccess;

  /// No description provided for @assignFacesTitle.
  ///
  /// In en, this message translates to:
  /// **'Move {count, plural, =1{1 face} other{{count} faces}} to…'**
  String assignFacesTitle(int count);

  /// No description provided for @assignTo.
  ///
  /// In en, this message translates to:
  /// **'Assign to…'**
  String get assignTo;

  /// No description provided for @backupDone.
  ///
  /// In en, this message translates to:
  /// **'Backup created. Choose where to save it.'**
  String get backupDone;

  /// No description provided for @backupFailed.
  ///
  /// In en, this message translates to:
  /// **'Backup problem: {error}'**
  String backupFailed(String error);

  /// No description provided for @backupIntro.
  ///
  /// In en, this message translates to:
  /// **'Your library, private results, datasets and trained LoRAs live on this phone. Export a backup to keep another copy; PC connections and active jobs are excluded.'**
  String get backupIntro;

  /// No description provided for @backupKeepSafe.
  ///
  /// In en, this message translates to:
  /// **'Backups are encrypted by default. Keep the password safe; it is never stored by the app. Older unencrypted backups can still be restored.'**
  String get backupKeepSafe;

  /// No description provided for @backupLibrarySummary.
  ///
  /// In en, this message translates to:
  /// **'{people} people · {faces} faces · {photos} photos'**
  String backupLibrarySummary(int people, int faces, int photos);

  /// No description provided for @backupNow.
  ///
  /// In en, this message translates to:
  /// **'Back up now'**
  String get backupNow;

  /// No description provided for @backupReminderBody.
  ///
  /// In en, this message translates to:
  /// **'Your library exists only on this phone. Save a backup file somewhere safe.'**
  String get backupReminderBody;

  /// No description provided for @backupReminderNever.
  ///
  /// In en, this message translates to:
  /// **'You have never made a backup'**
  String get backupReminderNever;

  /// No description provided for @backupReminderOld.
  ///
  /// In en, this message translates to:
  /// **'Your last backup is more than 2 weeks old'**
  String get backupReminderOld;

  /// No description provided for @backupSettingsHint.
  ///
  /// In en, this message translates to:
  /// **'Save or restore your whole library'**
  String get backupSettingsHint;

  /// No description provided for @backupShareSubject.
  ///
  /// In en, this message translates to:
  /// **'Your Gallery backup'**
  String get backupShareSubject;

  /// No description provided for @backupStageCrops.
  ///
  /// In en, this message translates to:
  /// **'Saving face pictures…'**
  String get backupStageCrops;

  /// No description provided for @backupStageDatabase.
  ///
  /// In en, this message translates to:
  /// **'Saving your library…'**
  String get backupStageDatabase;

  /// No description provided for @backupStageFinishing.
  ///
  /// In en, this message translates to:
  /// **'Finishing…'**
  String get backupStageFinishing;

  /// No description provided for @backupStageRestoring.
  ///
  /// In en, this message translates to:
  /// **'Restoring your library…'**
  String get backupStageRestoring;

  /// No description provided for @backupTitle.
  ///
  /// In en, this message translates to:
  /// **'Backup & restore'**
  String get backupTitle;

  /// No description provided for @backupWhatIsIncluded.
  ///
  /// In en, this message translates to:
  /// **'What is in a backup'**
  String get backupWhatIsIncluded;

  /// No description provided for @backupWhatIsIncludedBody.
  ///
  /// In en, this message translates to:
  /// **'People, faces, body links, media records, corrections, grouping settings, saved identity sets, private results, datasets, captions and trained LoRAs. Your original gallery photos, PC connections and active jobs are excluded.'**
  String get backupWhatIsIncludedBody;

  /// No description provided for @bodyBox.
  ///
  /// In en, this message translates to:
  /// **'Body'**
  String get bodyBox;

  /// No description provided for @bodyLinkDetail.
  ///
  /// In en, this message translates to:
  /// **'{method} · {percent}% sure'**
  String bodyLinkDetail(String method, int percent);

  /// No description provided for @bodyLinkTitle.
  ///
  /// In en, this message translates to:
  /// **'Looks like {person}'**
  String bodyLinkTitle(String person);

  /// No description provided for @chooseAlbums.
  ///
  /// In en, this message translates to:
  /// **'Choose albums'**
  String get chooseAlbums;

  /// No description provided for @chooseAlbumsFirst.
  ///
  /// In en, this message translates to:
  /// **'Choose albums first'**
  String get chooseAlbumsFirst;

  /// No description provided for @clearSelection.
  ///
  /// In en, this message translates to:
  /// **'Clear selection'**
  String get clearSelection;

  /// No description provided for @compare.
  ///
  /// In en, this message translates to:
  /// **'Compare'**
  String get compare;

  /// No description provided for @coverChanged.
  ///
  /// In en, this message translates to:
  /// **'Cover photo changed'**
  String get coverChanged;

  /// No description provided for @create.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get create;

  /// No description provided for @createAllGroups.
  ///
  /// In en, this message translates to:
  /// **'Create {count, plural, =1{1 person} other{{count} people}}'**
  String createAllGroups(int count);

  /// No description provided for @createPerson.
  ///
  /// In en, this message translates to:
  /// **'Create person'**
  String get createPerson;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @deleteFace.
  ///
  /// In en, this message translates to:
  /// **'Delete this face'**
  String get deleteFace;

  /// No description provided for @deleteFacesBody.
  ///
  /// In en, this message translates to:
  /// **'The face pictures are removed from this phone. Your original photos are not touched.'**
  String get deleteFacesBody;

  /// No description provided for @deleteFacesTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete {count, plural, =1{this face} other{{count} faces}}?'**
  String deleteFacesTitle(int count);

  /// No description provided for @deletePerson.
  ///
  /// In en, this message translates to:
  /// **'Delete person'**
  String get deletePerson;

  /// No description provided for @deletePersonBody.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Their 1 face becomes unsorted and stays out of automatic groups.} other{Their {count} faces become unsorted and stay out of automatic groups.}} You can still assign them manually. Nothing else is deleted.'**
  String deletePersonBody(int count);

  /// No description provided for @deletePersonTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete {name}?'**
  String deletePersonTitle(String name);

  /// No description provided for @differentPeople.
  ///
  /// In en, this message translates to:
  /// **'They are different people'**
  String get differentPeople;

  /// No description provided for @etaHours.
  ///
  /// In en, this message translates to:
  /// **'about {hours} h {minutes} min left'**
  String etaHours(int hours, int minutes);

  /// No description provided for @etaMinutes.
  ///
  /// In en, this message translates to:
  /// **'about {minutes} min left'**
  String etaMinutes(int minutes);

  /// No description provided for @etaSeconds.
  ///
  /// In en, this message translates to:
  /// **'about {seconds} s left'**
  String etaSeconds(int seconds);

  /// No description provided for @faceBox.
  ///
  /// In en, this message translates to:
  /// **'Face'**
  String get faceBox;

  /// No description provided for @facesCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No faces} =1{1 face} other{{count} faces}}'**
  String facesCount(int count);

  /// No description provided for @facesMoved.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 face moved} other{{count} faces moved}}'**
  String facesMoved(int count);

  /// No description provided for @facesRejected.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 face removed from this person} other{{count} faces removed from this person}}'**
  String facesRejected(int count);

  /// No description provided for @filterAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get filterAll;

  /// No description provided for @filterFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get filterFailed;

  /// No description provided for @filterHasFaces.
  ///
  /// In en, this message translates to:
  /// **'Has faces'**
  String get filterHasFaces;

  /// No description provided for @filterNotScanned.
  ///
  /// In en, this message translates to:
  /// **'Not scanned'**
  String get filterNotScanned;

  /// No description provided for @filterPerson.
  ///
  /// In en, this message translates to:
  /// **'Person'**
  String get filterPerson;

  /// No description provided for @filterScanned.
  ///
  /// In en, this message translates to:
  /// **'Scanned'**
  String get filterScanned;

  /// No description provided for @groupCardTitle.
  ///
  /// In en, this message translates to:
  /// **'New person? {count, plural, =1{1 face} other{{count} faces}}'**
  String groupCardTitle(int count);

  /// No description provided for @hideBodies.
  ///
  /// In en, this message translates to:
  /// **'Hide bodies'**
  String get hideBodies;

  /// No description provided for @keepPerson.
  ///
  /// In en, this message translates to:
  /// **'Keep {label}'**
  String keepPerson(String label);

  /// No description provided for @lastBackup.
  ///
  /// In en, this message translates to:
  /// **'Last backup: {date}'**
  String lastBackup(String date);

  /// No description provided for @libraryEmptyBody.
  ///
  /// In en, this message translates to:
  /// **'Scan your albums to find the faces in them. Your photos stay on this phone.'**
  String get libraryEmptyBody;

  /// No description provided for @libraryEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No photos yet'**
  String get libraryEmptyTitle;

  /// No description provided for @linkManual.
  ///
  /// In en, this message translates to:
  /// **'By hand'**
  String get linkManual;

  /// No description provided for @linkOutfit.
  ///
  /// In en, this message translates to:
  /// **'Same outfit'**
  String get linkOutfit;

  /// No description provided for @linkWeakFace.
  ///
  /// In en, this message translates to:
  /// **'Blurry face'**
  String get linkWeakFace;

  /// No description provided for @matchCardTitle.
  ///
  /// In en, this message translates to:
  /// **'{person} · {count, plural, =1{1 face looks like them} other{{count} faces look like them}}'**
  String matchCardTitle(String person, int count);

  /// No description provided for @merge.
  ///
  /// In en, this message translates to:
  /// **'Merge'**
  String get merge;

  /// No description provided for @mergeConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'{source} ({count, plural, =1{1 face} other{{count} faces}}) becomes part of {target}, and {source} disappears. You can still move faces back one by one.'**
  String mergeConfirmBody(String source, int count, String target);

  /// No description provided for @mergeConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Merge these people?'**
  String get mergeConfirmTitle;

  /// No description provided for @mergeInto.
  ///
  /// In en, this message translates to:
  /// **'Merge {source} into {target}'**
  String mergeInto(String source, String target);

  /// No description provided for @mergeNotFlagged.
  ///
  /// In en, this message translates to:
  /// **'Not flagged by your PC'**
  String get mergeNotFlagged;

  /// No description provided for @mergeScoreHint.
  ///
  /// In en, this message translates to:
  /// **'How alike your PC thinks the two people are'**
  String get mergeScoreHint;

  /// No description provided for @mergeTitle.
  ///
  /// In en, this message translates to:
  /// **'Merge people'**
  String get mergeTitle;

  /// No description provided for @mergeWith.
  ///
  /// In en, this message translates to:
  /// **'Merge with…'**
  String get mergeWith;

  /// No description provided for @mergedInto.
  ///
  /// In en, this message translates to:
  /// **'Merged into {name}'**
  String mergedInto(String name);

  /// No description provided for @needsReview.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 decision needs you} other{{count} decisions need you}}'**
  String needsReview(int count);

  /// No description provided for @neverBackedUp.
  ///
  /// In en, this message translates to:
  /// **'No backup yet'**
  String get neverBackedUp;

  /// No description provided for @newPerson.
  ///
  /// In en, this message translates to:
  /// **'New person'**
  String get newPerson;

  /// No description provided for @noBodiesBody.
  ///
  /// In en, this message translates to:
  /// **'Bodies are found next to faces and matched by outfit.'**
  String get noBodiesBody;

  /// No description provided for @noBodiesTitle.
  ///
  /// In en, this message translates to:
  /// **'No body shots yet'**
  String get noBodiesTitle;

  /// No description provided for @noFacesInPhoto.
  ///
  /// In en, this message translates to:
  /// **'No faces were found in this photo.'**
  String get noFacesInPhoto;

  /// No description provided for @noFacesYet.
  ///
  /// In en, this message translates to:
  /// **'No faces yet'**
  String get noFacesYet;

  /// No description provided for @noPeopleBody.
  ///
  /// In en, this message translates to:
  /// **'Scan your photos and the people in them show up here.'**
  String get noPeopleBody;

  /// No description provided for @noPeopleTitle.
  ///
  /// In en, this message translates to:
  /// **'No people yet'**
  String get noPeopleTitle;

  /// No description provided for @noPeopleYet.
  ///
  /// In en, this message translates to:
  /// **'No people yet'**
  String get noPeopleYet;

  /// No description provided for @noPhotoAccessBody.
  ///
  /// In en, this message translates to:
  /// **'Your Gallery needs permission to read your photos before it can scan them.'**
  String get noPhotoAccessBody;

  /// No description provided for @noPhotoAccessTitle.
  ///
  /// In en, this message translates to:
  /// **'No photo access'**
  String get noPhotoAccessTitle;

  /// No description provided for @noPhotosMatch.
  ///
  /// In en, this message translates to:
  /// **'No photos match these filters'**
  String get noPhotosMatch;

  /// No description provided for @noPhotosOfPerson.
  ///
  /// In en, this message translates to:
  /// **'No photos of this person yet'**
  String get noPhotosOfPerson;

  /// No description provided for @noSuggestionsBody.
  ///
  /// In en, this message translates to:
  /// **'Nothing needs your decision for this person right now.'**
  String get noSuggestionsBody;

  /// No description provided for @noSuggestionsTitle.
  ///
  /// In en, this message translates to:
  /// **'No suggestions'**
  String get noSuggestionsTitle;

  /// No description provided for @noUnsortedFaces.
  ///
  /// In en, this message translates to:
  /// **'No unsorted faces'**
  String get noUnsortedFaces;

  /// No description provided for @notAPerson.
  ///
  /// In en, this message translates to:
  /// **'Not a person'**
  String get notAPerson;

  /// No description provided for @notPaired.
  ///
  /// In en, this message translates to:
  /// **'Not paired'**
  String get notPaired;

  /// No description provided for @notPerson.
  ///
  /// In en, this message translates to:
  /// **'Not {name}'**
  String notPerson(String name);

  /// No description provided for @notScannedYet.
  ///
  /// In en, this message translates to:
  /// **'This photo has not been scanned yet.'**
  String get notScannedYet;

  /// No description provided for @notThem.
  ///
  /// In en, this message translates to:
  /// **'Not them ({count})'**
  String notThem(int count);

  /// No description provided for @notThisPerson.
  ///
  /// In en, this message translates to:
  /// **'Not this person'**
  String get notThisPerson;

  /// No description provided for @openPerson.
  ///
  /// In en, this message translates to:
  /// **'Open {name}'**
  String openPerson(String name);

  /// No description provided for @optionBodies.
  ///
  /// In en, this message translates to:
  /// **'Find bodies'**
  String get optionBodies;

  /// No description provided for @optionBodiesHint.
  ///
  /// In en, this message translates to:
  /// **'Also detect people\'s bodies, so photos where a face is hidden can be matched by outfit.'**
  String get optionBodiesHint;

  /// No description provided for @optionImageSize.
  ///
  /// In en, this message translates to:
  /// **'Picture size sent to your PC'**
  String get optionImageSize;

  /// No description provided for @optionImageSizeHint.
  ///
  /// In en, this message translates to:
  /// **'Longest side. Bigger finds smaller faces but is slower.'**
  String get optionImageSizeHint;

  /// No description provided for @outfitMatchesTitle.
  ///
  /// In en, this message translates to:
  /// **'Same outfit'**
  String get outfitMatchesTitle;

  /// No description provided for @pause.
  ///
  /// In en, this message translates to:
  /// **'Pause'**
  String get pause;

  /// No description provided for @personFallbackName.
  ///
  /// In en, this message translates to:
  /// **'Person {id}'**
  String personFallbackName(int id);

  /// No description provided for @personGone.
  ///
  /// In en, this message translates to:
  /// **'This person no longer exists.'**
  String get personGone;

  /// No description provided for @personNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get personNameLabel;

  /// No description provided for @personNameOptional.
  ///
  /// In en, this message translates to:
  /// **'Optional'**
  String get personNameOptional;

  /// No description provided for @photoGone.
  ///
  /// In en, this message translates to:
  /// **'Photo not found'**
  String get photoGone;

  /// No description provided for @photoGoneBody.
  ///
  /// In en, this message translates to:
  /// **'The original is no longer on this phone. The faces found in it are still in your library.'**
  String get photoGoneBody;

  /// No description provided for @photoTitle.
  ///
  /// In en, this message translates to:
  /// **'Photo'**
  String get photoTitle;

  /// No description provided for @photosCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 photo} other{{count} photos}}'**
  String photosCount(int count);

  /// No description provided for @pickPersonTitle.
  ///
  /// In en, this message translates to:
  /// **'Choose a person'**
  String get pickPersonTitle;

  /// No description provided for @possibleSamePerson.
  ///
  /// In en, this message translates to:
  /// **'May be the same person'**
  String get possibleSamePerson;

  /// No description provided for @qualityGateValue.
  ///
  /// In en, this message translates to:
  /// **'Minimum quality {value}'**
  String qualityGateValue(String value);

  /// No description provided for @reject.
  ///
  /// In en, this message translates to:
  /// **'Reject'**
  String get reject;

  /// No description provided for @rename.
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get rename;

  /// No description provided for @restore.
  ///
  /// In en, this message translates to:
  /// **'Restore'**
  String get restore;

  /// No description provided for @restoreConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'This replaces everything in the app with the backup from {date}: {people} people, {faces} faces, {photos} photos. Anything added since then is lost.'**
  String restoreConfirmBody(String date, int people, int faces, int photos);

  /// No description provided for @restoreConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Replace your library?'**
  String get restoreConfirmTitle;

  /// No description provided for @restoreDone.
  ///
  /// In en, this message translates to:
  /// **'Restored {people} people and {faces} faces.'**
  String restoreDone(int people, int faces);

  /// No description provided for @restoreFromBackup.
  ///
  /// In en, this message translates to:
  /// **'Restore from a backup'**
  String get restoreFromBackup;

  /// No description provided for @resume.
  ///
  /// In en, this message translates to:
  /// **'Resume'**
  String get resume;

  /// No description provided for @reviewDecisions.
  ///
  /// In en, this message translates to:
  /// **'{count} to review'**
  String reviewDecisions(int count);

  /// No description provided for @reviewDuplicatesEmpty.
  ///
  /// In en, this message translates to:
  /// **'No people look like duplicates'**
  String get reviewDuplicatesEmpty;

  /// No description provided for @reviewGroupsEmpty.
  ///
  /// In en, this message translates to:
  /// **'No new groups to review'**
  String get reviewGroupsEmpty;

  /// No description provided for @reviewMatchesEmpty.
  ///
  /// In en, this message translates to:
  /// **'No faces waiting to be matched'**
  String get reviewMatchesEmpty;

  /// No description provided for @reviewOutfitsEmpty.
  ///
  /// In en, this message translates to:
  /// **'No outfit matches to review'**
  String get reviewOutfitsEmpty;

  /// No description provided for @reviewTabDuplicates.
  ///
  /// In en, this message translates to:
  /// **'Same person? ({count})'**
  String reviewTabDuplicates(int count);

  /// No description provided for @reviewTabGroups.
  ///
  /// In en, this message translates to:
  /// **'New people ({count})'**
  String reviewTabGroups(int count);

  /// No description provided for @reviewTabMatches.
  ///
  /// In en, this message translates to:
  /// **'Faces ({count})'**
  String reviewTabMatches(int count);

  /// No description provided for @reviewTabOutfits.
  ///
  /// In en, this message translates to:
  /// **'Bodies ({count})'**
  String reviewTabOutfits(int count);

  /// No description provided for @reviewTitle.
  ///
  /// In en, this message translates to:
  /// **'Review'**
  String get reviewTitle;

  /// No description provided for @reviewTitleCount.
  ///
  /// In en, this message translates to:
  /// **'Review ({count})'**
  String reviewTitleCount(int count);

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @scanChannelDescription.
  ///
  /// In en, this message translates to:
  /// **'Progress while your photos are scanned'**
  String get scanChannelDescription;

  /// No description provided for @scanChannelName.
  ///
  /// In en, this message translates to:
  /// **'Library scan'**
  String get scanChannelName;

  /// No description provided for @scanCountsLine.
  ///
  /// In en, this message translates to:
  /// **'{done} scanned · {waiting} waiting · {failed} failed'**
  String scanCountsLine(int done, int waiting, int failed);

  /// No description provided for @scanDone.
  ///
  /// In en, this message translates to:
  /// **'Scan finished'**
  String get scanDone;

  /// No description provided for @scanError.
  ///
  /// In en, this message translates to:
  /// **'The scan stopped: {message}'**
  String scanError(String message);

  /// No description provided for @scanFacesFound.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No new faces} =1{1 new face} other{{count} new faces}}'**
  String scanFacesFound(int count);

  /// No description provided for @scanFacesLinked.
  ///
  /// In en, this message translates to:
  /// **'{count} seen before'**
  String scanFacesLinked(int count);

  /// No description provided for @scanFailedCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 photo could not be read} other{{count} photos could not be read}}'**
  String scanFailedCount(int count);

  /// No description provided for @scanFootnote.
  ///
  /// In en, this message translates to:
  /// **'Scanning keeps going with the screen off. Photos already scanned are skipped, so you can run it again whenever new items arrive.'**
  String get scanFootnote;

  /// No description provided for @scanFound.
  ///
  /// In en, this message translates to:
  /// **'{count} photos found'**
  String scanFound(int count);

  /// No description provided for @scanLibrary.
  ///
  /// In en, this message translates to:
  /// **'Scan library'**
  String get scanLibrary;

  /// No description provided for @scanLibraryHint.
  ///
  /// In en, this message translates to:
  /// **'Find the faces in your items'**
  String get scanLibraryHint;

  /// No description provided for @scanModelMismatch.
  ///
  /// In en, this message translates to:
  /// **'Your PC now uses a different face-recognition model than this library. Switch the PC back, or start a new library.'**
  String get scanModelMismatch;

  /// No description provided for @scanNoAccess.
  ///
  /// In en, this message translates to:
  /// **'Photo access is off. Allow it in Android settings.'**
  String get scanNoAccess;

  /// No description provided for @scanNoAlbums.
  ///
  /// In en, this message translates to:
  /// **'No albums chosen.'**
  String get scanNoAlbums;

  /// No description provided for @scanNotPaired.
  ///
  /// In en, this message translates to:
  /// **'Pair with your PC first.'**
  String get scanNotPaired;

  /// No description provided for @scanNotificationText.
  ///
  /// In en, this message translates to:
  /// **'{done}/{total} items · {faces} faces'**
  String scanNotificationText(int done, int total, int faces);

  /// No description provided for @scanNotificationTitle.
  ///
  /// In en, this message translates to:
  /// **'Scanning your items'**
  String get scanNotificationTitle;

  /// No description provided for @scanNow.
  ///
  /// In en, this message translates to:
  /// **'Scan now'**
  String get scanNow;

  /// No description provided for @scanOffline.
  ///
  /// In en, this message translates to:
  /// **'The PC could not be reached. Check that the server is running on the same Wi-Fi, then resume.'**
  String get scanOffline;

  /// No description provided for @scanPaused.
  ///
  /// In en, this message translates to:
  /// **'Scan paused'**
  String get scanPaused;

  /// No description provided for @scanPausedUser.
  ///
  /// In en, this message translates to:
  /// **'You paused the scan.'**
  String get scanPausedUser;

  /// No description provided for @scanPcBusy.
  ///
  /// In en, this message translates to:
  /// **'Your PC\'s GPU stayed busy for several minutes. Resume when its other job is done.'**
  String get scanPcBusy;

  /// No description provided for @scanPhotosOf.
  ///
  /// In en, this message translates to:
  /// **'{done} of {total} photos'**
  String scanPhotosOf(int done, int total);

  /// No description provided for @scanPreparing.
  ///
  /// In en, this message translates to:
  /// **'Listing your photos…'**
  String get scanPreparing;

  /// No description provided for @scanRevoked.
  ///
  /// In en, this message translates to:
  /// **'This phone was removed on the PC. Pair again to scan.'**
  String get scanRevoked;

  /// No description provided for @scanRunning.
  ///
  /// In en, this message translates to:
  /// **'Scanning…'**
  String get scanRunning;

  /// No description provided for @scanSorting.
  ///
  /// In en, this message translates to:
  /// **'Sorting faces into people…'**
  String get scanSorting;

  /// No description provided for @scanSummary.
  ///
  /// In en, this message translates to:
  /// **'{photos} photos scanned · {faces} new faces'**
  String scanSummary(int photos, int faces);

  /// No description provided for @scanWaiting.
  ///
  /// In en, this message translates to:
  /// **'Waiting for your PC…'**
  String get scanWaiting;

  /// No description provided for @searchPeopleHint.
  ///
  /// In en, this message translates to:
  /// **'Search people'**
  String get searchPeopleHint;

  /// No description provided for @selectAll.
  ///
  /// In en, this message translates to:
  /// **'Select all'**
  String get selectAll;

  /// No description provided for @selectedCount.
  ///
  /// In en, this message translates to:
  /// **'{count} selected'**
  String selectedCount(int count);

  /// No description provided for @setAsCover.
  ///
  /// In en, this message translates to:
  /// **'Use as cover photo'**
  String get setAsCover;

  /// No description provided for @settingsGrouping.
  ///
  /// In en, this message translates to:
  /// **'Grouping'**
  String get settingsGrouping;

  /// No description provided for @settingsPc.
  ///
  /// In en, this message translates to:
  /// **'Your PC'**
  String get settingsPc;

  /// No description provided for @settingsQualityGate.
  ///
  /// In en, this message translates to:
  /// **'Face quality'**
  String get settingsQualityGate;

  /// No description provided for @settingsQualityGateHint.
  ///
  /// In en, this message translates to:
  /// **'Faces below this quality are ignored. Raise it for cleaner groups, lower it to catch more faces. Applies to new scans.'**
  String get settingsQualityGateHint;

  /// No description provided for @settingsScanDefaults.
  ///
  /// In en, this message translates to:
  /// **'Scanning'**
  String get settingsScanDefaults;

  /// No description provided for @showBodies.
  ///
  /// In en, this message translates to:
  /// **'Show bodies'**
  String get showBodies;

  /// No description provided for @similarityPercent.
  ///
  /// In en, this message translates to:
  /// **'{percent}% alike'**
  String similarityPercent(int percent);

  /// No description provided for @sortBy.
  ///
  /// In en, this message translates to:
  /// **'Sort'**
  String get sortBy;

  /// No description provided for @sortDone.
  ///
  /// In en, this message translates to:
  /// **'Added {assigned} faces to people, created {created} people, {review} to review'**
  String sortDone(int assigned, int created, int review);

  /// No description provided for @sortMostFaces.
  ///
  /// In en, this message translates to:
  /// **'Most faces'**
  String get sortMostFaces;

  /// No description provided for @sortName.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get sortName;

  /// No description provided for @sortNeedsPc.
  ///
  /// In en, this message translates to:
  /// **'Pair with your PC to sort faces.'**
  String get sortNeedsPc;

  /// No description provided for @sortNewest.
  ///
  /// In en, this message translates to:
  /// **'Newest'**
  String get sortNewest;

  /// No description provided for @sortNow.
  ///
  /// In en, this message translates to:
  /// **'Sort faces now'**
  String get sortNow;

  /// No description provided for @sortNowHint.
  ///
  /// In en, this message translates to:
  /// **'Ask the PC to sort unsorted faces into people again'**
  String get sortNowHint;

  /// No description provided for @sorting.
  ///
  /// In en, this message translates to:
  /// **'Sorting faces…'**
  String get sorting;

  /// No description provided for @sourcesTitle.
  ///
  /// In en, this message translates to:
  /// **'Sources & scan'**
  String get sourcesTitle;

  /// No description provided for @strictnessBalanced.
  ///
  /// In en, this message translates to:
  /// **'Balanced'**
  String get strictnessBalanced;

  /// No description provided for @strictnessBalancedHint.
  ///
  /// In en, this message translates to:
  /// **'Recommended. Adds a face to a person only when it is clearly them.'**
  String get strictnessBalancedHint;

  /// No description provided for @strictnessLoose.
  ///
  /// In en, this message translates to:
  /// **'Loose'**
  String get strictnessLoose;

  /// No description provided for @strictnessLooseHint.
  ///
  /// In en, this message translates to:
  /// **'Groups more faces automatically. Quicker, but may need more corrections.'**
  String get strictnessLooseHint;

  /// No description provided for @strictnessStrict.
  ///
  /// In en, this message translates to:
  /// **'Strict'**
  String get strictnessStrict;

  /// No description provided for @strictnessStrictHint.
  ///
  /// In en, this message translates to:
  /// **'Asks you about more faces. Fewer mistakes.'**
  String get strictnessStrictHint;

  /// No description provided for @suggestedFacesTitle.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 face may be {name}} other{{count} faces may be {name}}}'**
  String suggestedFacesTitle(String name, int count);

  /// No description provided for @tabBodies.
  ///
  /// In en, this message translates to:
  /// **'Bodies'**
  String get tabBodies;

  /// No description provided for @tabFaces.
  ///
  /// In en, this message translates to:
  /// **'Faces ({count})'**
  String tabFaces(int count);

  /// No description provided for @tabPhotos.
  ///
  /// In en, this message translates to:
  /// **'Photos'**
  String get tabPhotos;

  /// No description provided for @tabSuggestions.
  ///
  /// In en, this message translates to:
  /// **'Suggestions'**
  String get tabSuggestions;

  /// No description provided for @thisIsPerson.
  ///
  /// In en, this message translates to:
  /// **'This is…'**
  String get thisIsPerson;

  /// No description provided for @unsortedCardTitle.
  ///
  /// In en, this message translates to:
  /// **'Unsorted'**
  String get unsortedCardTitle;

  /// No description provided for @unsortedFace.
  ///
  /// In en, this message translates to:
  /// **'Unsorted face'**
  String get unsortedFace;

  /// No description provided for @unsortedFacesInPhoto.
  ///
  /// In en, this message translates to:
  /// **'{count} unsorted'**
  String unsortedFacesInPhoto(int count);

  /// No description provided for @whoIsHere.
  ///
  /// In en, this message translates to:
  /// **'Who is here'**
  String get whoIsHere;

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// No description provided for @allMedia.
  ///
  /// In en, this message translates to:
  /// **'All photos & videos'**
  String get allMedia;

  /// No description provided for @mediaCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 item} other{{count} items}}'**
  String mediaCount(int count);

  /// No description provided for @includeVideos.
  ///
  /// In en, this message translates to:
  /// **'Scan videos too'**
  String get includeVideos;

  /// No description provided for @includeVideosHint.
  ///
  /// In en, this message translates to:
  /// **'Videos upload to your paired PC. Progress resumes after interruptions.'**
  String get includeVideosHint;

  /// No description provided for @videoFrameInterval.
  ///
  /// In en, this message translates to:
  /// **'Sample video frames'**
  String get videoFrameInterval;

  /// No description provided for @videoEverySeconds.
  ///
  /// In en, this message translates to:
  /// **'Every {seconds} s'**
  String videoEverySeconds(String seconds);

  /// No description provided for @videoPreparing.
  ///
  /// In en, this message translates to:
  /// **'Preparing video · {percent}%'**
  String videoPreparing(int percent);

  /// No description provided for @videoUploading.
  ///
  /// In en, this message translates to:
  /// **'Uploading video · {percent}%'**
  String videoUploading(int percent);

  /// No description provided for @videoAnalyzing.
  ///
  /// In en, this message translates to:
  /// **'Analyzing video · {percent}%'**
  String videoAnalyzing(int percent);

  /// No description provided for @videoDownloading.
  ///
  /// In en, this message translates to:
  /// **'Downloading video detections…'**
  String get videoDownloading;

  /// No description provided for @videoImporting.
  ///
  /// In en, this message translates to:
  /// **'Saving video detections on this phone…'**
  String get videoImporting;

  /// No description provided for @videoTitle.
  ///
  /// In en, this message translates to:
  /// **'Video'**
  String get videoTitle;

  /// No description provided for @videoUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Video unavailable'**
  String get videoUnavailable;

  /// No description provided for @videoUnavailableBody.
  ///
  /// In en, this message translates to:
  /// **'The original may have been removed, access may have changed, or this format cannot be played.'**
  String get videoUnavailableBody;

  /// No description provided for @videoPlay.
  ///
  /// In en, this message translates to:
  /// **'Play'**
  String get videoPlay;

  /// No description provided for @videoPause.
  ///
  /// In en, this message translates to:
  /// **'Pause playback'**
  String get videoPause;

  /// No description provided for @videoDetectedFrames.
  ///
  /// In en, this message translates to:
  /// **'Jump to a detected frame'**
  String get videoDetectedFrames;

  /// No description provided for @videoNoDetections.
  ///
  /// In en, this message translates to:
  /// **'No detections yet. Scan this video to find people.'**
  String get videoNoDetections;

  /// No description provided for @insightsTitle.
  ///
  /// In en, this message translates to:
  /// **'Library insights'**
  String get insightsTitle;

  /// No description provided for @insightsHint.
  ///
  /// In en, this message translates to:
  /// **'Scan coverage, identified faces and people in your library.'**
  String get insightsHint;

  /// No description provided for @insightsCoverage.
  ///
  /// In en, this message translates to:
  /// **'Scan coverage'**
  String get insightsCoverage;

  /// No description provided for @insightsScanned.
  ///
  /// In en, this message translates to:
  /// **'{done} of {total} items scanned'**
  String insightsScanned(int done, int total);

  /// No description provided for @insightsFaces.
  ///
  /// In en, this message translates to:
  /// **'Identified faces'**
  String get insightsFaces;

  /// No description provided for @insightsBodies.
  ///
  /// In en, this message translates to:
  /// **'Identified bodies'**
  String get insightsBodies;

  /// No description provided for @insightsTopPeople.
  ///
  /// In en, this message translates to:
  /// **'Most seen people'**
  String get insightsTopPeople;

  /// No description provided for @insightsPersonMedia.
  ///
  /// In en, this message translates to:
  /// **'{count} media items'**
  String insightsPersonMedia(int count);

  /// No description provided for @insightsEmpty.
  ///
  /// In en, this message translates to:
  /// **'Scan your library to see insights'**
  String get insightsEmpty;

  /// No description provided for @insightsAssigned.
  ///
  /// In en, this message translates to:
  /// **'{identified} of {total} identified'**
  String insightsAssigned(int identified, int total);

  /// No description provided for @insightsUnsorted.
  ///
  /// In en, this message translates to:
  /// **'Unsorted faces'**
  String get insightsUnsorted;

  /// No description provided for @insightsFailed.
  ///
  /// In en, this message translates to:
  /// **'Items needing another scan'**
  String get insightsFailed;

  /// No description provided for @tabMedia.
  ///
  /// In en, this message translates to:
  /// **'Photos & videos'**
  String get tabMedia;

  /// No description provided for @studioTitle.
  ///
  /// In en, this message translates to:
  /// **'Studio'**
  String get studioTitle;

  /// No description provided for @studioHint.
  ///
  /// In en, this message translates to:
  /// **'Create with your private library'**
  String get studioHint;

  /// No description provided for @studioNeedsPc.
  ///
  /// In en, this message translates to:
  /// **'Connect to your paired PC to detect faces and start a new job.'**
  String get studioNeedsPc;

  /// No description provided for @studioBusyHint.
  ///
  /// In en, this message translates to:
  /// **'The GPU is busy. New Studio jobs will wait in the queue.'**
  String get studioBusyHint;

  /// No description provided for @refaceTitle.
  ///
  /// In en, this message translates to:
  /// **'Reface'**
  String get refaceTitle;

  /// No description provided for @refaceHint.
  ///
  /// In en, this message translates to:
  /// **'Swap a person into a photo or video'**
  String get refaceHint;

  /// No description provided for @privateResults.
  ///
  /// In en, this message translates to:
  /// **'Private results'**
  String get privateResults;

  /// No description provided for @privateResultsHint.
  ///
  /// In en, this message translates to:
  /// **'Outputs stay inside Your Gallery until you choose to share them.'**
  String get privateResultsHint;

  /// No description provided for @refaceTarget.
  ///
  /// In en, this message translates to:
  /// **'Target'**
  String get refaceTarget;

  /// No description provided for @refaceIdentity.
  ///
  /// In en, this message translates to:
  /// **'Source identity'**
  String get refaceIdentity;

  /// No description provided for @refaceQuality.
  ///
  /// In en, this message translates to:
  /// **'Engine & quality'**
  String get refaceQuality;

  /// No description provided for @refaceReview.
  ///
  /// In en, this message translates to:
  /// **'Review & create'**
  String get refaceReview;

  /// No description provided for @chooseTargetPhoto.
  ///
  /// In en, this message translates to:
  /// **'Choose a photo'**
  String get chooseTargetPhoto;

  /// No description provided for @chooseTargetVideo.
  ///
  /// In en, this message translates to:
  /// **'Choose a video'**
  String get chooseTargetVideo;

  /// No description provided for @selectedTargetFaces.
  ///
  /// In en, this message translates to:
  /// **'Choose the faces to swap'**
  String get selectedTargetFaces;

  /// No description provided for @videoSwapsAllFaces.
  ///
  /// In en, this message translates to:
  /// **'Video Reface swaps every detected face in the selected clip.'**
  String get videoSwapsAllFaces;

  /// No description provided for @videoTrimStart.
  ///
  /// In en, this message translates to:
  /// **'Start (seconds)'**
  String get videoTrimStart;

  /// No description provided for @videoTrimEnd.
  ///
  /// In en, this message translates to:
  /// **'End (seconds, optional)'**
  String get videoTrimEnd;

  /// No description provided for @selectSourcePerson.
  ///
  /// In en, this message translates to:
  /// **'Choose source person'**
  String get selectSourcePerson;

  /// No description provided for @sourceFacesHint.
  ///
  /// In en, this message translates to:
  /// **'Select clear faces of the same person. The best 20 are selected by default.'**
  String get sourceFacesHint;

  /// No description provided for @refaceHd.
  ///
  /// In en, this message translates to:
  /// **'V3 · HD'**
  String get refaceHd;

  /// No description provided for @refaceLegacy.
  ///
  /// In en, this message translates to:
  /// **'V2'**
  String get refaceLegacy;

  /// No description provided for @refacePro.
  ///
  /// In en, this message translates to:
  /// **'Pro · DFM'**
  String get refacePro;

  /// No description provided for @refaceEngine.
  ///
  /// In en, this message translates to:
  /// **'Engine'**
  String get refaceEngine;

  /// No description provided for @dfmModel.
  ///
  /// In en, this message translates to:
  /// **'DFM model'**
  String get dfmModel;

  /// No description provided for @refaceRestorer.
  ///
  /// In en, this message translates to:
  /// **'Face restoration'**
  String get refaceRestorer;

  /// No description provided for @restorerAuto.
  ///
  /// In en, this message translates to:
  /// **'Automatic'**
  String get restorerAuto;

  /// No description provided for @restorerNone.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get restorerNone;

  /// No description provided for @refacePreset.
  ///
  /// In en, this message translates to:
  /// **'Realism preset'**
  String get refacePreset;

  /// No description provided for @presetNatural.
  ///
  /// In en, this message translates to:
  /// **'Natural'**
  String get presetNatural;

  /// No description provided for @presetDetail.
  ///
  /// In en, this message translates to:
  /// **'Maximum detail'**
  String get presetDetail;

  /// No description provided for @presetClean.
  ///
  /// In en, this message translates to:
  /// **'Clean'**
  String get presetClean;

  /// No description provided for @protectOcclusions.
  ///
  /// In en, this message translates to:
  /// **'Protect glasses and occlusions'**
  String get protectOcclusions;

  /// No description provided for @useFaceParser.
  ///
  /// In en, this message translates to:
  /// **'Use face region mask'**
  String get useFaceParser;

  /// No description provided for @submitReface.
  ///
  /// In en, this message translates to:
  /// **'Create Reface job'**
  String get submitReface;

  /// No description provided for @refaceReviewHint.
  ///
  /// In en, this message translates to:
  /// **'The target is copied to private phone storage so this request survives closing the app. The PC uses temporary files and deletes them after this phone confirms the result is saved.'**
  String get refaceReviewHint;

  /// No description provided for @selectFaceRequired.
  ///
  /// In en, this message translates to:
  /// **'Select at least one target face.'**
  String get selectFaceRequired;

  /// No description provided for @selectIdentityRequired.
  ///
  /// In en, this message translates to:
  /// **'Choose a source person and at least one face.'**
  String get selectIdentityRequired;

  /// No description provided for @chooseTargetRequired.
  ///
  /// In en, this message translates to:
  /// **'Choose and detect a photo, or choose a video.'**
  String get chooseTargetRequired;

  /// No description provided for @invalidTrimRange.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid trim range: end must be greater than start.'**
  String get invalidTrimRange;

  /// No description provided for @fileTooLarge.
  ///
  /// In en, this message translates to:
  /// **'This file exceeds the PC upload limit.'**
  String get fileTooLarge;

  /// No description provided for @studioNoEngine.
  ///
  /// In en, this message translates to:
  /// **'No Reface engine is available. Check the models on your PC.'**
  String get studioNoEngine;

  /// No description provided for @jobsEmpty.
  ///
  /// In en, this message translates to:
  /// **'No Studio jobs yet'**
  String get jobsEmpty;

  /// No description provided for @jobsEmptyHint.
  ///
  /// In en, this message translates to:
  /// **'Start a Reface job from Studio. Progress and results will appear here.'**
  String get jobsEmptyHint;

  /// No description provided for @jobDetails.
  ///
  /// In en, this message translates to:
  /// **'Job details'**
  String get jobDetails;

  /// No description provided for @jobPause.
  ///
  /// In en, this message translates to:
  /// **'Pause'**
  String get jobPause;

  /// No description provided for @jobResume.
  ///
  /// In en, this message translates to:
  /// **'Resume'**
  String get jobResume;

  /// No description provided for @jobRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get jobRetry;

  /// No description provided for @jobRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove job'**
  String get jobRemove;

  /// No description provided for @jobSync.
  ///
  /// In en, this message translates to:
  /// **'Sync now'**
  String get jobSync;

  /// No description provided for @jobResult.
  ///
  /// In en, this message translates to:
  /// **'Open result'**
  String get jobResult;

  /// No description provided for @statusUploading.
  ///
  /// In en, this message translates to:
  /// **'Uploading'**
  String get statusUploading;

  /// No description provided for @statusQueued.
  ///
  /// In en, this message translates to:
  /// **'Queued'**
  String get statusQueued;

  /// No description provided for @statusRunning.
  ///
  /// In en, this message translates to:
  /// **'Running'**
  String get statusRunning;

  /// No description provided for @statusPaused.
  ///
  /// In en, this message translates to:
  /// **'Paused'**
  String get statusPaused;

  /// No description provided for @statusDownloading.
  ///
  /// In en, this message translates to:
  /// **'Saving result'**
  String get statusDownloading;

  /// No description provided for @statusCompleted.
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get statusCompleted;

  /// No description provided for @statusFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get statusFailed;

  /// No description provided for @statusLost.
  ///
  /// In en, this message translates to:
  /// **'PC job expired'**
  String get statusLost;

  /// No description provided for @resultEmpty.
  ///
  /// In en, this message translates to:
  /// **'No private results yet'**
  String get resultEmpty;

  /// No description provided for @resultEmptyHint.
  ///
  /// In en, this message translates to:
  /// **'Finished outputs are saved here automatically.'**
  String get resultEmptyHint;

  /// No description provided for @resultBefore.
  ///
  /// In en, this message translates to:
  /// **'Before'**
  String get resultBefore;

  /// No description provided for @resultAfter.
  ///
  /// In en, this message translates to:
  /// **'After'**
  String get resultAfter;

  /// No description provided for @resultCompare.
  ///
  /// In en, this message translates to:
  /// **'Before / after'**
  String get resultCompare;

  /// No description provided for @resultShare.
  ///
  /// In en, this message translates to:
  /// **'Share output'**
  String get resultShare;

  /// No description provided for @resultFavourite.
  ///
  /// In en, this message translates to:
  /// **'Favourite'**
  String get resultFavourite;

  /// No description provided for @resultDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete result'**
  String get resultDelete;

  /// No description provided for @resultDeleteBody.
  ///
  /// In en, this message translates to:
  /// **'Delete this private output and its comparison original from the phone?'**
  String get resultDeleteBody;

  /// No description provided for @jobRemoveBody.
  ///
  /// In en, this message translates to:
  /// **'Remove this job and its temporary input? Saved results are kept.'**
  String get jobRemoveBody;

  /// No description provided for @next.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get next;

  /// No description provided for @createAnother.
  ///
  /// In en, this message translates to:
  /// **'Create another'**
  String get createAnother;

  /// No description provided for @allResults.
  ///
  /// In en, this message translates to:
  /// **'All results'**
  String get allResults;

  /// No description provided for @favouriteResults.
  ///
  /// In en, this message translates to:
  /// **'Favourites'**
  String get favouriteResults;

  /// No description provided for @resultPhoto.
  ///
  /// In en, this message translates to:
  /// **'Photo'**
  String get resultPhoto;

  /// No description provided for @resultVideo.
  ///
  /// In en, this message translates to:
  /// **'Video'**
  String get resultVideo;

  /// No description provided for @jobErrorHint.
  ///
  /// In en, this message translates to:
  /// **'Your target remains on the phone. Reconnect or retry to continue.'**
  String get jobErrorHint;

  /// No description provided for @useInStudio.
  ///
  /// In en, this message translates to:
  /// **'Use in Studio'**
  String get useInStudio;

  /// No description provided for @studioResultReady.
  ///
  /// In en, this message translates to:
  /// **'Your result is ready and saved privately on this phone.'**
  String get studioResultReady;

  /// No description provided for @restyleTitle.
  ///
  /// In en, this message translates to:
  /// **'Clothes restyle'**
  String get restyleTitle;

  /// No description provided for @restyleHint.
  ///
  /// In en, this message translates to:
  /// **'Change clothing while protecting the face'**
  String get restyleHint;

  /// No description provided for @restylePrompt.
  ///
  /// In en, this message translates to:
  /// **'Describe the clothing'**
  String get restylePrompt;

  /// No description provided for @restyleDefaultPrompt.
  ///
  /// In en, this message translates to:
  /// **'Photorealistic fashion photo, wearing an elegant blue tailored suit, natural fabric texture and folds, preserve the same person, pose, lighting and background'**
  String get restyleDefaultPrompt;

  /// No description provided for @restyleNegative.
  ///
  /// In en, this message translates to:
  /// **'Negative prompt'**
  String get restyleNegative;

  /// No description provided for @restyleNegativeDefault.
  ///
  /// In en, this message translates to:
  /// **'nudity, underwear, deformed hands, bad anatomy, blurry, plastic skin, watermark'**
  String get restyleNegativeDefault;

  /// No description provided for @restyleStrength.
  ///
  /// In en, this message translates to:
  /// **'Change strength'**
  String get restyleStrength;

  /// No description provided for @restyleFace.
  ///
  /// In en, this message translates to:
  /// **'Protected face'**
  String get restyleFace;

  /// No description provided for @restylePadding.
  ///
  /// In en, this message translates to:
  /// **'Extra face protection'**
  String get restylePadding;

  /// No description provided for @restyleReferences.
  ///
  /// In en, this message translates to:
  /// **'Clothing references'**
  String get restyleReferences;

  /// No description provided for @addReference.
  ///
  /// In en, this message translates to:
  /// **'Add a reference photo'**
  String get addReference;

  /// No description provided for @restyleCreate.
  ///
  /// In en, this message translates to:
  /// **'Create restyle job'**
  String get restyleCreate;

  /// No description provided for @engineUnavailable.
  ///
  /// In en, this message translates to:
  /// **'This tool is unavailable on your PC. Check its environment and model files.'**
  String get engineUnavailable;

  /// No description provided for @advancedOptions.
  ///
  /// In en, this message translates to:
  /// **'Advanced options'**
  String get advancedOptions;

  /// No description provided for @seed.
  ///
  /// In en, this message translates to:
  /// **'Seed (-1 = random)'**
  String get seed;

  /// No description provided for @steps.
  ///
  /// In en, this message translates to:
  /// **'Steps'**
  String get steps;

  /// No description provided for @guidance.
  ///
  /// In en, this message translates to:
  /// **'Guidance'**
  String get guidance;

  /// No description provided for @refineOutput.
  ///
  /// In en, this message translates to:
  /// **'Refine at original resolution'**
  String get refineOutput;

  /// No description provided for @promptRequired.
  ///
  /// In en, this message translates to:
  /// **'Describe the clothing before submitting.'**
  String get promptRequired;

  /// No description provided for @loraTitle.
  ///
  /// In en, this message translates to:
  /// **'Character LoRA'**
  String get loraTitle;

  /// No description provided for @loraHint.
  ///
  /// In en, this message translates to:
  /// **'Build a dataset, train a character and generate portraits'**
  String get loraHint;

  /// No description provided for @loraDatasetTitle.
  ///
  /// In en, this message translates to:
  /// **'Character dataset'**
  String get loraDatasetTitle;

  /// No description provided for @loraDatasetBuild.
  ///
  /// In en, this message translates to:
  /// **'Build dataset'**
  String get loraDatasetBuild;

  /// No description provided for @loraChoosePhotos.
  ///
  /// In en, this message translates to:
  /// **'Choose training photos'**
  String get loraChoosePhotos;

  /// No description provided for @loraPhotoHint.
  ///
  /// In en, this message translates to:
  /// **'Choose 5–64 clear photos of the selected person. The PC matches that identity before cropping.'**
  String get loraPhotoHint;

  /// No description provided for @loraTrigger.
  ///
  /// In en, this message translates to:
  /// **'Trigger word'**
  String get loraTrigger;

  /// No description provided for @loraTriggerHint.
  ///
  /// In en, this message translates to:
  /// **'3–64 letters, digits or underscores; start with a letter'**
  String get loraTriggerHint;

  /// No description provided for @loraRepeats.
  ///
  /// In en, this message translates to:
  /// **'Repeats per image'**
  String get loraRepeats;

  /// No description provided for @loraTrain.
  ///
  /// In en, this message translates to:
  /// **'Train LoRA'**
  String get loraTrain;

  /// No description provided for @loraGenerate.
  ///
  /// In en, this message translates to:
  /// **'Generate portraits'**
  String get loraGenerate;

  /// No description provided for @loraNoDatasets.
  ///
  /// In en, this message translates to:
  /// **'No character datasets yet'**
  String get loraNoDatasets;

  /// No description provided for @loraNoModels.
  ///
  /// In en, this message translates to:
  /// **'No trained LoRAs yet'**
  String get loraNoModels;

  /// No description provided for @loraDatasetEditor.
  ///
  /// In en, this message translates to:
  /// **'Edit dataset'**
  String get loraDatasetEditor;

  /// No description provided for @loraCaption.
  ///
  /// In en, this message translates to:
  /// **'Caption'**
  String get loraCaption;

  /// No description provided for @loraIncluded.
  ///
  /// In en, this message translates to:
  /// **'Include in training'**
  String get loraIncluded;

  /// No description provided for @loraExport.
  ///
  /// In en, this message translates to:
  /// **'Export training zip'**
  String get loraExport;

  /// No description provided for @loraTrainHint.
  ///
  /// In en, this message translates to:
  /// **'Training uses the included images and edited captions. The finished LoRA is saved on this phone.'**
  String get loraTrainHint;

  /// No description provided for @loraEpochs.
  ///
  /// In en, this message translates to:
  /// **'Epochs'**
  String get loraEpochs;

  /// No description provided for @loraDim.
  ///
  /// In en, this message translates to:
  /// **'Network dimension'**
  String get loraDim;

  /// No description provided for @loraLearningRate.
  ///
  /// In en, this message translates to:
  /// **'Learning rate'**
  String get loraLearningRate;

  /// No description provided for @loraResolution.
  ///
  /// In en, this message translates to:
  /// **'Resolution'**
  String get loraResolution;

  /// No description provided for @loraBase.
  ///
  /// In en, this message translates to:
  /// **'Base checkpoint'**
  String get loraBase;

  /// No description provided for @loraModel.
  ///
  /// In en, this message translates to:
  /// **'Trained LoRA'**
  String get loraModel;

  /// No description provided for @loraCount.
  ///
  /// In en, this message translates to:
  /// **'Number of portraits'**
  String get loraCount;

  /// No description provided for @loraPrompt.
  ///
  /// In en, this message translates to:
  /// **'Portrait prompt'**
  String get loraPrompt;

  /// No description provided for @loraDefaultPrompt.
  ///
  /// In en, this message translates to:
  /// **'A natural studio portrait of {trigger} person, neutral expression, realistic skin texture, soft daylight, fully clothed, photorealistic'**
  String loraDefaultPrompt(Object trigger);

  /// No description provided for @loraReferenceMode.
  ///
  /// In en, this message translates to:
  /// **'Follow the reference'**
  String get loraReferenceMode;

  /// No description provided for @referenceComposition.
  ///
  /// In en, this message translates to:
  /// **'Pose & composition'**
  String get referenceComposition;

  /// No description provided for @referenceStyle.
  ///
  /// In en, this message translates to:
  /// **'Style & clothing'**
  String get referenceStyle;

  /// No description provided for @referenceBoth.
  ///
  /// In en, this message translates to:
  /// **'Both'**
  String get referenceBoth;

  /// No description provided for @loraIdentity.
  ///
  /// In en, this message translates to:
  /// **'Use generated portraits in Reface'**
  String get loraIdentity;

  /// No description provided for @loraBuildIdentity.
  ///
  /// In en, this message translates to:
  /// **'Build Reface identity'**
  String get loraBuildIdentity;

  /// No description provided for @loraIdentityHint.
  ///
  /// In en, this message translates to:
  /// **'Generated faces are added only when they match the person’s real face identity.'**
  String get loraIdentityHint;

  /// No description provided for @loraIdentityReady.
  ///
  /// In en, this message translates to:
  /// **'Reface identity saved'**
  String get loraIdentityReady;

  /// No description provided for @loraChooseDataset.
  ///
  /// In en, this message translates to:
  /// **'Choose a dataset'**
  String get loraChooseDataset;

  /// No description provided for @loraMinImages.
  ///
  /// In en, this message translates to:
  /// **'Include at least five images before training.'**
  String get loraMinImages;

  /// No description provided for @invalidForm.
  ///
  /// In en, this message translates to:
  /// **'Check the form values and try again.'**
  String get invalidForm;

  /// No description provided for @loraNoBase.
  ///
  /// In en, this message translates to:
  /// **'No compatible base checkpoint is available on this PC.'**
  String get loraNoBase;

  /// No description provided for @privateArtifact.
  ///
  /// In en, this message translates to:
  /// **'Private model or dataset'**
  String get privateArtifact;

  /// No description provided for @openDataset.
  ///
  /// In en, this message translates to:
  /// **'Open dataset editor'**
  String get openDataset;

  /// No description provided for @openLora.
  ///
  /// In en, this message translates to:
  /// **'Open Character LoRA'**
  String get openLora;

  /// No description provided for @trainingDetails.
  ///
  /// In en, this message translates to:
  /// **'Training progress'**
  String get trainingDetails;

  /// No description provided for @loss.
  ///
  /// In en, this message translates to:
  /// **'Loss'**
  String get loss;

  /// No description provided for @epoch.
  ///
  /// In en, this message translates to:
  /// **'Epoch'**
  String get epoch;

  /// No description provided for @totalSteps.
  ///
  /// In en, this message translates to:
  /// **'Steps'**
  String get totalSteps;

  /// No description provided for @saveToGallery.
  ///
  /// In en, this message translates to:
  /// **'Save to gallery'**
  String get saveToGallery;

  /// No description provided for @savedToGallery.
  ///
  /// In en, this message translates to:
  /// **'Saved to gallery'**
  String get savedToGallery;

  /// No description provided for @storageTitle.
  ///
  /// In en, this message translates to:
  /// **'Storage'**
  String get storageTitle;

  /// No description provided for @appLockTitle.
  ///
  /// In en, this message translates to:
  /// **'App lock'**
  String get appLockTitle;

  /// No description provided for @appLockHint.
  ///
  /// In en, this message translates to:
  /// **'Use your phone’s screen lock when opening Your Gallery.'**
  String get appLockHint;

  /// No description provided for @unlockApp.
  ///
  /// In en, this message translates to:
  /// **'Unlock Your Gallery'**
  String get unlockApp;

  /// No description provided for @unlockBody.
  ///
  /// In en, this message translates to:
  /// **'Confirm your phone screen lock to open your private library.'**
  String get unlockBody;

  /// No description provided for @unlockFailed.
  ///
  /// In en, this message translates to:
  /// **'Unlock was cancelled, or a phone screen lock is not set up.'**
  String get unlockFailed;

  /// No description provided for @storageHint.
  ///
  /// In en, this message translates to:
  /// **'Manage private outputs, datasets and trained models.'**
  String get storageHint;

  /// No description provided for @storageUsed.
  ///
  /// In en, this message translates to:
  /// **'Private files'**
  String get storageUsed;

  /// No description provided for @storageDeleteResults.
  ///
  /// In en, this message translates to:
  /// **'Delete private results'**
  String get storageDeleteResults;

  /// No description provided for @storageDeleteDatasets.
  ///
  /// In en, this message translates to:
  /// **'Delete datasets'**
  String get storageDeleteDatasets;

  /// No description provided for @storageDeleteLoras.
  ///
  /// In en, this message translates to:
  /// **'Delete trained LoRAs'**
  String get storageDeleteLoras;

  /// No description provided for @storageDeleteTemporary.
  ///
  /// In en, this message translates to:
  /// **'Clean temporary files'**
  String get storageDeleteTemporary;

  /// No description provided for @storageConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete the selected private files from this phone? Export a backup first if you want to keep them.'**
  String get storageConfirm;

  /// No description provided for @storageBusy.
  ///
  /// In en, this message translates to:
  /// **'Pause scans and active Studio jobs before cleaning storage.'**
  String get storageBusy;

  /// No description provided for @storageCleaned.
  ///
  /// In en, this message translates to:
  /// **'Storage updated'**
  String get storageCleaned;

  /// No description provided for @connectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Connection help'**
  String get connectionTitle;

  /// No description provided for @connectionFix.
  ///
  /// In en, this message translates to:
  /// **'Fix connection'**
  String get connectionFix;

  /// No description provided for @connectionIntro.
  ///
  /// In en, this message translates to:
  /// **'Connect locally over a router, either device\'s hotspot, or USB. Internet access is not required. If the PC address changes, search again without forgetting your pairing.'**
  String get connectionIntro;

  /// No description provided for @connectionFind.
  ///
  /// In en, this message translates to:
  /// **'Find my PC on this network'**
  String get connectionFind;

  /// No description provided for @connectionTest.
  ///
  /// In en, this message translates to:
  /// **'Verify and save PC address'**
  String get connectionTest;

  /// No description provided for @connectionPairAtAddress.
  ///
  /// In en, this message translates to:
  /// **'Pair at this address'**
  String get connectionPairAtAddress;

  /// No description provided for @connectionRestored.
  ///
  /// In en, this message translates to:
  /// **'Connected to the same verified PC. Your pairing and library are preserved.'**
  String get connectionRestored;

  /// No description provided for @connectionNothingFound.
  ///
  /// In en, this message translates to:
  /// **'No PC answered local discovery. Check the current address in the PC dashboard and try it below. Discovery may be blocked even when direct connection works.'**
  String get connectionNothingFound;

  /// No description provided for @connectionVerifyFailed.
  ///
  /// In en, this message translates to:
  /// **'The discovered addresses could not be verified as your paired PC. Check that the server is running and use its current address.'**
  String get connectionVerifyFailed;

  /// No description provided for @connectionFailed.
  ///
  /// In en, this message translates to:
  /// **'Connection could not be completed. Check the server, local address and firewall settings below.'**
  String get connectionFailed;

  /// No description provided for @connectionInvalidAddress.
  ///
  /// In en, this message translates to:
  /// **'Enter a private-network PC address and a port from 1 to 65535.'**
  String get connectionInvalidAddress;

  /// No description provided for @connectionPhoneAddresses.
  ///
  /// In en, this message translates to:
  /// **'This phone\'s local addresses'**
  String get connectionPhoneAddresses;

  /// No description provided for @connectionNoLan.
  ///
  /// In en, this message translates to:
  /// **'No local Wi-Fi, hotspot or USB interface was found. Turn on the hotspot or connect to a local network. A cellular connection alone cannot reach the PC.'**
  String get connectionNoLan;

  /// No description provided for @connectionPhoneHotspotTitle.
  ///
  /// In en, this message translates to:
  /// **'Phone shares its hotspot'**
  String get connectionPhoneHotspotTitle;

  /// No description provided for @connectionPhoneHotspot.
  ///
  /// In en, this message translates to:
  /// **'Connect the PC to this phone\'s hotspot. On the PC open Mobile Devices and use the PC\'s Wi-Fi address shown there. Keep the hotspot enabled; some phones turn it off automatically. Mobile data can stay enabled.'**
  String get connectionPhoneHotspot;

  /// No description provided for @connectionPcHotspotTitle.
  ///
  /// In en, this message translates to:
  /// **'PC shares its hotspot'**
  String get connectionPcHotspotTitle;

  /// No description provided for @connectionPcHotspot.
  ///
  /// In en, this message translates to:
  /// **'Connect the phone to the PC hotspot. Use the hotspot adapter\'s PC address from Mobile Devices. It can differ from the PC\'s router or Ethernet address.'**
  String get connectionPcHotspot;

  /// No description provided for @connectionRouterTitle.
  ///
  /// In en, this message translates to:
  /// **'Router, guest Wi-Fi or VPN'**
  String get connectionRouterTitle;

  /// No description provided for @connectionRouter.
  ///
  /// In en, this message translates to:
  /// **'Use the same local network and allow the Python server through Windows Firewall. Guest isolation and some VPNs block device traffic; enable local-network access or use another local network. An Internet connection is not a connectivity test.'**
  String get connectionRouter;

  /// No description provided for @connectionUsbTitle.
  ///
  /// In en, this message translates to:
  /// **'USB fallback'**
  String get connectionUsbTitle;

  /// No description provided for @connectionUsb.
  ///
  /// In en, this message translates to:
  /// **'Connect a USB cable, enable and authorize USB debugging, then run the command below on the PC. Use 127.0.0.1 and the PC server\'s port here. This avoids Wi-Fi isolation and uses no mobile data.'**
  String get connectionUsb;

  /// No description provided for @connectionPinSafety.
  ///
  /// In en, this message translates to:
  /// **'Finding a device never changes the saved certificate or sends media to an unverified PC. If the PC certificate was replaced, confirm its new QR on the PC before pairing again.'**
  String get connectionPinSafety;

  /// No description provided for @backgroundTitle.
  ///
  /// In en, this message translates to:
  /// **'Background work'**
  String get backgroundTitle;

  /// No description provided for @backgroundIntro.
  ///
  /// In en, this message translates to:
  /// **'Allow notifications and unrestricted battery use so scans, uploads and result downloads can continue when you leave the app or lock the screen. An ongoing notification shows when work is active.'**
  String get backgroundIntro;

  /// No description provided for @backgroundSettingsHint.
  ///
  /// In en, this message translates to:
  /// **'Keep work going with the screen off'**
  String get backgroundSettingsHint;

  /// No description provided for @backgroundLater.
  ///
  /// In en, this message translates to:
  /// **'Continue for now'**
  String get backgroundLater;

  /// No description provided for @backgroundEnable.
  ///
  /// In en, this message translates to:
  /// **'Allow background work'**
  String get backgroundEnable;

  /// No description provided for @backgroundRefresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh status'**
  String get backgroundRefresh;

  /// No description provided for @backgroundNotifications.
  ///
  /// In en, this message translates to:
  /// **'Progress notifications allowed'**
  String get backgroundNotifications;

  /// No description provided for @backgroundBattery.
  ///
  /// In en, this message translates to:
  /// **'Battery use unrestricted'**
  String get backgroundBattery;

  /// No description provided for @backgroundRunning.
  ///
  /// In en, this message translates to:
  /// **'Background service is running'**
  String get backgroundRunning;

  /// No description provided for @backgroundIdle.
  ///
  /// In en, this message translates to:
  /// **'Ready to start when there is active work'**
  String get backgroundIdle;

  /// No description provided for @backgroundOpenSettings.
  ///
  /// In en, this message translates to:
  /// **'Open Android app settings'**
  String get backgroundOpenSettings;

  /// No description provided for @backgroundAndroidOnly.
  ///
  /// In en, this message translates to:
  /// **'Background permissions are available on Android.'**
  String get backgroundAndroidOnly;

  /// No description provided for @backgroundServiceFailed.
  ///
  /// In en, this message translates to:
  /// **'Android could not start the background service. Keep the app open and check notifications and battery settings.'**
  String get backgroundServiceFailed;

  /// No description provided for @backgroundLimits.
  ///
  /// In en, this message translates to:
  /// **'A force stop, phone shutdown or Android background time limit can stop phone work. Open the app to resume its saved queue. Some phones also require allowing auto-start in the manufacturer\'s battery settings. The PC must stay on and connected to the phone.'**
  String get backgroundLimits;

  /// No description provided for @identitySaved.
  ///
  /// In en, this message translates to:
  /// **'Saved identity sets'**
  String get identitySaved;

  /// No description provided for @identitySave.
  ///
  /// In en, this message translates to:
  /// **'Save selected faces'**
  String get identitySave;

  /// No description provided for @identityName.
  ///
  /// In en, this message translates to:
  /// **'Identity set name'**
  String get identityName;

  /// No description provided for @identityDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete identity set'**
  String get identityDelete;

  /// No description provided for @identityDeleteBody.
  ///
  /// In en, this message translates to:
  /// **'Remove this saved selection? The person and source faces will be kept.'**
  String get identityDeleteBody;

  /// No description provided for @backupEncryption.
  ///
  /// In en, this message translates to:
  /// **'Encrypt backup'**
  String get backupEncryption;

  /// No description provided for @backupEncryptionHint.
  ///
  /// In en, this message translates to:
  /// **'Protect this backup with a password. You will need it to restore on any phone.'**
  String get backupEncryptionHint;

  /// No description provided for @backupPlaintextHint.
  ///
  /// In en, this message translates to:
  /// **'This backup will be readable without a password. Keep it in a private location.'**
  String get backupPlaintextHint;

  /// No description provided for @backupPasswordCreate.
  ///
  /// In en, this message translates to:
  /// **'Protect your backup'**
  String get backupPasswordCreate;

  /// No description provided for @backupPasswordEnter.
  ///
  /// In en, this message translates to:
  /// **'Unlock backup'**
  String get backupPasswordEnter;

  /// No description provided for @backupPasswordReminder.
  ///
  /// In en, this message translates to:
  /// **'Keep your password somewhere safe. A forgotten password cannot be recovered.'**
  String get backupPasswordReminder;

  /// No description provided for @backupPassword.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get backupPassword;

  /// No description provided for @backupPasswordConfirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm password'**
  String get backupPasswordConfirm;

  /// No description provided for @backupPasswordVisibility.
  ///
  /// In en, this message translates to:
  /// **'Show or hide password'**
  String get backupPasswordVisibility;

  /// No description provided for @backupPasswordLength.
  ///
  /// In en, this message translates to:
  /// **'Use 12–1024 characters.'**
  String get backupPasswordLength;

  /// No description provided for @backupPasswordMismatch.
  ///
  /// In en, this message translates to:
  /// **'The passwords do not match.'**
  String get backupPasswordMismatch;

  /// No description provided for @backupUnlock.
  ///
  /// In en, this message translates to:
  /// **'Unlock'**
  String get backupUnlock;

  /// No description provided for @backupStageEncrypting.
  ///
  /// In en, this message translates to:
  /// **'Encrypting backup…'**
  String get backupStageEncrypting;

  /// No description provided for @backupStageDecrypting.
  ///
  /// In en, this message translates to:
  /// **'Unlocking backup…'**
  String get backupStageDecrypting;

  /// No description provided for @jobStage.
  ///
  /// In en, this message translates to:
  /// **'Stage'**
  String get jobStage;

  /// No description provided for @jobEpoch.
  ///
  /// In en, this message translates to:
  /// **'Epoch'**
  String get jobEpoch;

  /// No description provided for @jobTotalEpochs.
  ///
  /// In en, this message translates to:
  /// **'Total epochs'**
  String get jobTotalEpochs;

  /// No description provided for @jobStep.
  ///
  /// In en, this message translates to:
  /// **'Step'**
  String get jobStep;

  /// No description provided for @jobTotalSteps.
  ///
  /// In en, this message translates to:
  /// **'Total steps'**
  String get jobTotalSteps;

  /// No description provided for @jobLoss.
  ///
  /// In en, this message translates to:
  /// **'Loss'**
  String get jobLoss;

  /// No description provided for @jobSecondsPerStep.
  ///
  /// In en, this message translates to:
  /// **'Seconds per step'**
  String get jobSecondsPerStep;

  /// No description provided for @jobHistory.
  ///
  /// In en, this message translates to:
  /// **'Activity history'**
  String get jobHistory;

  /// No description provided for @jobTimeRemaining.
  ///
  /// In en, this message translates to:
  /// **'About {time} remaining'**
  String jobTimeRemaining(String time);

  /// No description provided for @jobHoursMinutes.
  ///
  /// In en, this message translates to:
  /// **'{hours} hr {minutes} min'**
  String jobHoursMinutes(int hours, int minutes);

  /// No description provided for @jobMinutes.
  ///
  /// In en, this message translates to:
  /// **'{minutes} min'**
  String jobMinutes(int minutes);

  /// No description provided for @restyleRefineUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Optional SDXL refinement is not installed on this PC. Basic Restyle can run without it.'**
  String get restyleRefineUnavailable;

  /// No description provided for @backupShareCancelled.
  ///
  /// In en, this message translates to:
  /// **'Backup sharing was cancelled. Choose a destination to keep a copy outside this app.'**
  String get backupShareCancelled;

  /// No description provided for @refaceReference.
  ///
  /// In en, this message translates to:
  /// **'Choose a photo of the person to replace'**
  String get refaceReference;

  /// No description provided for @refaceReferenceHint.
  ///
  /// In en, this message translates to:
  /// **'Select their face in a reference photo. Only matching people in the video will be replaced.'**
  String get refaceReferenceHint;

  /// No description provided for @refaceAllVideoFaces.
  ///
  /// In en, this message translates to:
  /// **'Replace all video faces instead'**
  String get refaceAllVideoFaces;

  /// No description provided for @refaceAllFaces.
  ///
  /// In en, this message translates to:
  /// **'Replace all faces'**
  String get refaceAllFaces;

  /// No description provided for @refaceQualityProfile.
  ///
  /// In en, this message translates to:
  /// **'Quality & processing time'**
  String get refaceQualityProfile;

  /// No description provided for @refaceFast.
  ///
  /// In en, this message translates to:
  /// **'Fast'**
  String get refaceFast;

  /// No description provided for @refaceFastSummary.
  ///
  /// In en, this message translates to:
  /// **'Less extra processing · no restoration by default'**
  String get refaceFastSummary;

  /// No description provided for @refaceFastDescription.
  ///
  /// In en, this message translates to:
  /// **'Uses the same Reface pipeline with restoration and face parsing off by default. A good starting point for long videos; fine face detail can be softer. Occlusion protection stays on.'**
  String get refaceFastDescription;

  /// No description provided for @refaceBalanced.
  ///
  /// In en, this message translates to:
  /// **'Balanced'**
  String get refaceBalanced;

  /// No description provided for @refaceBalancedSummary.
  ///
  /// In en, this message translates to:
  /// **'Detail and processing cost · recommended starting point'**
  String get refaceBalancedSummary;

  /// No description provided for @refaceBalancedDescription.
  ///
  /// In en, this message translates to:
  /// **'Adds face restoration and face-region blending. Automatic prefers GPEN 512 when installed, then an available alternative. More processing than Fast, with more restored detail.'**
  String get refaceBalancedDescription;

  /// No description provided for @refaceDetail.
  ///
  /// In en, this message translates to:
  /// **'More detail'**
  String get refaceDetail;

  /// No description provided for @refaceDetailSummary.
  ///
  /// In en, this message translates to:
  /// **'Larger face crops when available · more processing'**
  String get refaceDetailSummary;

  /// No description provided for @refaceDetailDescription.
  ///
  /// In en, this message translates to:
  /// **'Automatic prefers GPEN 1024 when installed, otherwise an available alternative. Useful for large close-up faces; higher resolution costs more processing and does not guarantee a closer likeness.'**
  String get refaceDetailDescription;

  /// No description provided for @refaceAutoSummary.
  ///
  /// In en, this message translates to:
  /// **'Uses the chosen quality profile'**
  String get refaceAutoSummary;

  /// No description provided for @refaceAutoStartsWith.
  ///
  /// In en, this message translates to:
  /// **'Starts with {model} on this PC'**
  String refaceAutoStartsWith(String model);

  /// No description provided for @refaceAutoDescription.
  ///
  /// In en, this message translates to:
  /// **'Uses the available default for the selected quality profile. Fast skips restoration; Balanced prefers GPEN 512; More detail prefers GPEN 1024. If needed, the PC uses another installed model.'**
  String get refaceAutoDescription;

  /// No description provided for @refaceOffSummary.
  ///
  /// In en, this message translates to:
  /// **'Least restoration work · raw swap detail'**
  String get refaceOffSummary;

  /// No description provided for @refaceOffDescription.
  ///
  /// In en, this message translates to:
  /// **'Skips the restoration stage while still swapping faces. Reduces processing and keeps the raw swapped face; fine details can be softer.'**
  String get refaceOffDescription;

  /// No description provided for @refaceGpen512Summary.
  ///
  /// In en, this message translates to:
  /// **'Balanced face detail · 512 px crop'**
  String get refaceGpen512Summary;

  /// No description provided for @refaceGpen512Description.
  ///
  /// In en, this message translates to:
  /// **'A balanced starting point for restored face detail and processing cost in this app. Works on a 512 px face crop and generally needs less processing than GPEN 1024.'**
  String get refaceGpen512Description;

  /// No description provided for @refaceGpen1024Summary.
  ///
  /// In en, this message translates to:
  /// **'Higher face resolution · heavier processing'**
  String get refaceGpen1024Summary;

  /// No description provided for @refaceGpen1024Description.
  ///
  /// In en, this message translates to:
  /// **'Restores a 1024 px face crop. Can help large close-up faces, with more processing and memory than the 512 model. Higher resolution does not guarantee a better likeness.'**
  String get refaceGpen1024Description;

  /// No description provided for @refaceCodeformerSummary.
  ///
  /// In en, this message translates to:
  /// **'Rebuild degraded detail · extra AI processing'**
  String get refaceCodeformerSummary;

  /// No description provided for @refaceCodeformerDescription.
  ///
  /// In en, this message translates to:
  /// **'Repairs degraded facial detail with a tradeoff between reconstructed detail and fidelity. It can change fine facial features, so compare a preview when likeness matters.'**
  String get refaceCodeformerDescription;

  /// No description provided for @refaceGfpganSummary.
  ///
  /// In en, this message translates to:
  /// **'General face restoration · extra AI processing'**
  String get refaceGfpganSummary;

  /// No description provided for @refaceGfpganDescription.
  ///
  /// In en, this message translates to:
  /// **'Restores blurry or degraded facial detail using learned face patterns. Useful as an alternative look; compare a preview for both texture and likeness.'**
  String get refaceGfpganDescription;

  /// No description provided for @refaceRestoreformerSummary.
  ///
  /// In en, this message translates to:
  /// **'Alternative face restoration · extra AI processing'**
  String get refaceRestoreformerSummary;

  /// No description provided for @refaceRestoreformerDescription.
  ///
  /// In en, this message translates to:
  /// **'Reconstructs degraded facial detail using learned face information. Try it when other restorers do not suit the face; processing time and likeness depend on the input and PC.'**
  String get refaceRestoreformerDescription;

  /// No description provided for @refaceOtherModelSummary.
  ///
  /// In en, this message translates to:
  /// **'PC-provided restoration model'**
  String get refaceOtherModelSummary;

  /// No description provided for @refaceOtherModelDescription.
  ///
  /// In en, this message translates to:
  /// **'This model is available on the PC. No speed or likeness comparison is defined here; use a short preview to compare it.'**
  String get refaceOtherModelDescription;

  /// No description provided for @refaceRestorationIntro.
  ///
  /// In en, this message translates to:
  /// **'Restoration improves face detail after swapping. Model sizes describe face crops, not the output photo or video resolution.'**
  String get refaceRestorationIntro;

  /// No description provided for @refaceSpeedNote.
  ///
  /// In en, this message translates to:
  /// **'Processing time depends on the PC, frame size and number of faces. Compare a short preview for both detail and likeness.'**
  String get refaceSpeedNote;

  /// No description provided for @refacePhotosIdentity.
  ///
  /// In en, this message translates to:
  /// **'Source photos & videos'**
  String get refacePhotosIdentity;

  /// No description provided for @refaceTrainedIdentity.
  ///
  /// In en, this message translates to:
  /// **'Trained identity model'**
  String get refaceTrainedIdentity;

  /// No description provided for @refaceIdentityMethod.
  ///
  /// In en, this message translates to:
  /// **'Identity source'**
  String get refaceIdentityMethod;

  /// No description provided for @refaceUnifiedUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Unified Reface is unavailable. Update the PC server and check its face-swap model.'**
  String get refaceUnifiedUnavailable;

  /// No description provided for @refaceAllFacesHint.
  ///
  /// In en, this message translates to:
  /// **'Use the source identity for everyone in this photo or video, including people who appear later. No target face selection is needed.'**
  String get refaceAllFacesHint;

  /// No description provided for @refacePreview.
  ///
  /// In en, this message translates to:
  /// **'Render a preview'**
  String get refacePreview;

  /// No description provided for @refacePreviewHint.
  ///
  /// In en, this message translates to:
  /// **'Try these settings first. Video previews render up to 3 seconds; return here to adjust settings or start the full job.'**
  String get refacePreviewHint;

  /// No description provided for @refaceLegacyHint.
  ///
  /// In en, this message translates to:
  /// **'V2 processes every video frame and keeps the selected people matched by identity. It uses automatic OpenCV enhancement and occlusion protection.'**
  String get refaceLegacyHint;

  /// No description provided for @refaceDfmHint.
  ///
  /// In en, this message translates to:
  /// **'The trained model supplies face detail; restoration is not applied.'**
  String get refaceDfmHint;

  /// No description provided for @refaceIdentityBoost.
  ///
  /// In en, this message translates to:
  /// **'Identity strength'**
  String get refaceIdentityBoost;

  /// No description provided for @refaceSwapped.
  ///
  /// In en, this message translates to:
  /// **'Successful face swaps'**
  String get refaceSwapped;

  /// No description provided for @refaceSkipped.
  ///
  /// In en, this message translates to:
  /// **'Skipped faces'**
  String get refaceSkipped;

  /// No description provided for @refaceFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed faces'**
  String get refaceFailed;

  /// No description provided for @chooseTargetMedia.
  ///
  /// In en, this message translates to:
  /// **'Choose photo or video'**
  String get chooseTargetMedia;

  /// No description provided for @refaceTrimHint.
  ///
  /// In en, this message translates to:
  /// **'Drag the two handles to choose your clip. The preview follows the handle you move.'**
  String get refaceTrimHint;

  /// No description provided for @refaceTrimStart.
  ///
  /// In en, this message translates to:
  /// **'Start'**
  String get refaceTrimStart;

  /// No description provided for @refaceTrimEnd.
  ///
  /// In en, this message translates to:
  /// **'End'**
  String get refaceTrimEnd;

  /// No description provided for @refaceTrimDuration.
  ///
  /// In en, this message translates to:
  /// **'Selected clip'**
  String get refaceTrimDuration;

  /// No description provided for @refaceTrimEarlier.
  ///
  /// In en, this message translates to:
  /// **'Move one second earlier'**
  String get refaceTrimEarlier;

  /// No description provided for @refaceTrimLater.
  ///
  /// In en, this message translates to:
  /// **'Move one second later'**
  String get refaceTrimLater;

  /// No description provided for @refaceTrimLoading.
  ///
  /// In en, this message translates to:
  /// **'Wait for the video preview to load, then choose your clip.'**
  String get refaceTrimLoading;

  /// No description provided for @refaceGallerySource.
  ///
  /// In en, this message translates to:
  /// **'Gallery'**
  String get refaceGallerySource;

  /// No description provided for @refaceGallerySourceHint.
  ///
  /// In en, this message translates to:
  /// **'Choose a gallery app on this device'**
  String get refaceGallerySourceHint;

  /// No description provided for @refaceFilesSource.
  ///
  /// In en, this message translates to:
  /// **'Files'**
  String get refaceFilesSource;

  /// No description provided for @refaceFilesSourceHint.
  ///
  /// In en, this message translates to:
  /// **'Browse device folders and downloads'**
  String get refaceFilesSourceHint;

  /// No description provided for @refaceTargetPeopleHint.
  ///
  /// In en, this message translates to:
  /// **'Choose the people in this clip whose faces you want to replace. Faces are found in sampled frames; adjust the clip and scan again if someone is missing.'**
  String get refaceTargetPeopleHint;

  /// No description provided for @refaceFindingFaces.
  ///
  /// In en, this message translates to:
  /// **'Finding faces in the selected clip…'**
  String get refaceFindingFaces;

  /// No description provided for @refaceDetectVideoFaces.
  ///
  /// In en, this message translates to:
  /// **'Find faces in this clip again'**
  String get refaceDetectVideoFaces;

  /// No description provided for @refaceAddSourceMedia.
  ///
  /// In en, this message translates to:
  /// **'Add source photos or videos'**
  String get refaceAddSourceMedia;

  /// No description provided for @refaceSourceMediaHint.
  ///
  /// In en, this message translates to:
  /// **'Choose photos and videos of the person whose face you want to use. If several people are found, select one person below. You can add more files.'**
  String get refaceSourceMediaHint;

  /// No description provided for @refaceSourceMedia.
  ///
  /// In en, this message translates to:
  /// **'Selected source media'**
  String get refaceSourceMedia;

  /// No description provided for @refaceClearSourceMedia.
  ///
  /// In en, this message translates to:
  /// **'Clear selected source media'**
  String get refaceClearSourceMedia;

  /// No description provided for @refaceSourceMediaCount.
  ///
  /// In en, this message translates to:
  /// **'{count} source files analysed'**
  String refaceSourceMediaCount(int count);

  /// No description provided for @refaceReadingVideo.
  ///
  /// In en, this message translates to:
  /// **'Reading video frames…'**
  String get refaceReadingVideo;

  /// No description provided for @refaceDetectShownFrame.
  ///
  /// In en, this message translates to:
  /// **'Find faces in the frame shown'**
  String get refaceDetectShownFrame;

  /// No description provided for @refaceFaceAppearances.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 appearance} other{{count} appearances}}'**
  String refaceFaceAppearances(int count);

  /// No description provided for @refaceVideoReadTimeout.
  ///
  /// In en, this message translates to:
  /// **'Reading this video took too long. Try a shorter clip or choose the video again.'**
  String get refaceVideoReadTimeout;

  /// No description provided for @refaceVideoPeopleFound.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 person found in this clip} other{{count} people found in this clip}}'**
  String refaceVideoPeopleFound(int count);

  /// No description provided for @homeIntro.
  ///
  /// In en, this message translates to:
  /// **'A little more organized.'**
  String get homeIntro;

  /// No description provided for @homeIntroHint.
  ///
  /// In en, this message translates to:
  /// **'Find your people. Make something new.'**
  String get homeIntroHint;

  /// No description provided for @homeOrganize.
  ///
  /// In en, this message translates to:
  /// **'Your library'**
  String get homeOrganize;

  /// No description provided for @homeCreate.
  ///
  /// In en, this message translates to:
  /// **'Make something yours'**
  String get homeCreate;

  /// No description provided for @homeActivity.
  ///
  /// In en, this message translates to:
  /// **'Pick up where you left off'**
  String get homeActivity;

  /// No description provided for @studioIntro.
  ///
  /// In en, this message translates to:
  /// **'What would you like to create?'**
  String get studioIntro;

  /// No description provided for @studioTools.
  ///
  /// In en, this message translates to:
  /// **'Choose a tool'**
  String get studioTools;

  /// No description provided for @studioSaved.
  ///
  /// In en, this message translates to:
  /// **'Your creations'**
  String get studioSaved;

  /// No description provided for @studioRefaceAction.
  ///
  /// In en, this message translates to:
  /// **'Replace a face'**
  String get studioRefaceAction;

  /// No description provided for @studioRestyleAction.
  ///
  /// In en, this message translates to:
  /// **'Try a new look'**
  String get studioRestyleAction;

  /// No description provided for @studioLoraAction.
  ///
  /// In en, this message translates to:
  /// **'Create a character'**
  String get studioLoraAction;

  /// No description provided for @studioRefaceDescription.
  ///
  /// In en, this message translates to:
  /// **'Choose a photo or clip, then the person to replace.'**
  String get studioRefaceDescription;

  /// No description provided for @studioRestyleDescription.
  ///
  /// In en, this message translates to:
  /// **'Describe a new look for a photo.'**
  String get studioRestyleDescription;

  /// No description provided for @studioLoraDescription.
  ///
  /// In en, this message translates to:
  /// **'Build a character from photos, train it, then create.'**
  String get studioLoraDescription;

  /// No description provided for @clearFilters.
  ///
  /// In en, this message translates to:
  /// **'Clear filters'**
  String get clearFilters;

  /// No description provided for @peopleNoMatches.
  ///
  /// In en, this message translates to:
  /// **'No people match your search'**
  String get peopleNoMatches;

  /// No description provided for @clearSearch.
  ///
  /// In en, this message translates to:
  /// **'Clear search'**
  String get clearSearch;

  /// No description provided for @jobsInProgress.
  ///
  /// In en, this message translates to:
  /// **'In progress'**
  String get jobsInProgress;

  /// No description provided for @workflowProgress.
  ///
  /// In en, this message translates to:
  /// **'Step {current} of {total}'**
  String workflowProgress(int current, int total);

  /// No description provided for @settingsLibrarySection.
  ///
  /// In en, this message translates to:
  /// **'Library & scanning'**
  String get settingsLibrarySection;

  /// No description provided for @settingsPrivacySection.
  ///
  /// In en, this message translates to:
  /// **'Privacy & storage'**
  String get settingsPrivacySection;

  /// No description provided for @settingsDeviceSection.
  ///
  /// In en, this message translates to:
  /// **'PC & background activity'**
  String get settingsDeviceSection;

  /// No description provided for @resultsNoMatches.
  ///
  /// In en, this message translates to:
  /// **'No results match these filters'**
  String get resultsNoMatches;

  /// No description provided for @storageSavedTitle.
  ///
  /// In en, this message translates to:
  /// **'Saved on your phone'**
  String get storageSavedTitle;

  /// No description provided for @storageCategories.
  ///
  /// In en, this message translates to:
  /// **'Storage by category'**
  String get storageCategories;

  /// No description provided for @storageManage.
  ///
  /// In en, this message translates to:
  /// **'Manage saved files'**
  String get storageManage;

  /// No description provided for @storageModels.
  ///
  /// In en, this message translates to:
  /// **'Character models'**
  String get storageModels;

  /// No description provided for @storageOther.
  ///
  /// In en, this message translates to:
  /// **'Other files'**
  String get storageOther;

  /// No description provided for @storageTemporary.
  ///
  /// In en, this message translates to:
  /// **'Temporary files'**
  String get storageTemporary;

  /// No description provided for @storageOriginalsHint.
  ///
  /// In en, this message translates to:
  /// **'Your original photos and videos stay in the device gallery.'**
  String get storageOriginalsHint;

  /// No description provided for @reviewIntro.
  ///
  /// In en, this message translates to:
  /// **'Open a photo to inspect the highlighted face or body, then decide who it belongs to.'**
  String get reviewIntro;

  /// No description provided for @permissionsHeadline.
  ///
  /// In en, this message translates to:
  /// **'Make it work for you'**
  String get permissionsHeadline;

  /// No description provided for @manualHeadline.
  ///
  /// In en, this message translates to:
  /// **'Connect by address'**
  String get manualHeadline;

  /// No description provided for @connectionHeadline.
  ///
  /// In en, this message translates to:
  /// **'Find your PC'**
  String get connectionHeadline;

  /// No description provided for @backgroundHeadline.
  ///
  /// In en, this message translates to:
  /// **'Keep your work moving'**
  String get backgroundHeadline;

  /// No description provided for @backupHeadline.
  ///
  /// In en, this message translates to:
  /// **'Keep your library safe'**
  String get backupHeadline;

  /// No description provided for @mergeHeadline.
  ///
  /// In en, this message translates to:
  /// **'The same person?'**
  String get mergeHeadline;

  /// No description provided for @mergeIntro.
  ///
  /// In en, this message translates to:
  /// **'Compare the faces, then choose which profile to keep.'**
  String get mergeIntro;

  /// No description provided for @datasetEditorIntro.
  ///
  /// In en, this message translates to:
  /// **'Choose the photos to train with'**
  String get datasetEditorIntro;

  /// No description provided for @datasetEditorHint.
  ///
  /// In en, this message translates to:
  /// **'Keep clear, varied views of the same person. Include at least 5 photos to start training.'**
  String get datasetEditorHint;

  /// No description provided for @loraTrainHeadline.
  ///
  /// In en, this message translates to:
  /// **'Train your character'**
  String get loraTrainHeadline;

  /// No description provided for @loraGenerateHeadline.
  ///
  /// In en, this message translates to:
  /// **'Create with your character'**
  String get loraGenerateHeadline;

  /// No description provided for @analyzeHeadline.
  ///
  /// In en, this message translates to:
  /// **'Who is in this photo?'**
  String get analyzeHeadline;

  /// No description provided for @loadFailedTitle.
  ///
  /// In en, this message translates to:
  /// **'Could not load this screen'**
  String get loadFailedTitle;

  /// No description provided for @loadFailedBody.
  ///
  /// In en, this message translates to:
  /// **'Your saved data has not changed. Try loading this screen again.'**
  String get loadFailedBody;

  /// No description provided for @mediaPeopleHint.
  ///
  /// In en, this message translates to:
  /// **'Tap a face to see or change who it belongs to.'**
  String get mediaPeopleHint;

  /// No description provided for @jobProgressTitle.
  ///
  /// In en, this message translates to:
  /// **'Progress'**
  String get jobProgressTitle;

  /// No description provided for @jobDetailsAdvanced.
  ///
  /// In en, this message translates to:
  /// **'Processing details'**
  String get jobDetailsAdvanced;

  /// No description provided for @resultsBrowseHint.
  ///
  /// In en, this message translates to:
  /// **'Your creations, saved on this phone.'**
  String get resultsBrowseHint;

  /// No description provided for @selectFaces.
  ///
  /// In en, this message translates to:
  /// **'Select faces'**
  String get selectFaces;

  /// No description provided for @storageRemoveSaved.
  ///
  /// In en, this message translates to:
  /// **'Remove saved files'**
  String get storageRemoveSaved;

  /// No description provided for @resourcesTitle.
  ///
  /// In en, this message translates to:
  /// **'PC resources'**
  String get resourcesTitle;

  /// No description provided for @resourcesSubtitle.
  ///
  /// In en, this message translates to:
  /// **'RAM, GPU memory and storage on the PC doing your AI work.'**
  String get resourcesSubtitle;

  /// No description provided for @resourcesUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Could not read PC resources. Connect to the PC and make sure its server supports resource monitoring.'**
  String get resourcesUnavailable;

  /// No description provided for @resourcesUnknown.
  ///
  /// In en, this message translates to:
  /// **'Unavailable'**
  String get resourcesUnknown;

  /// No description provided for @resourcesAppRam.
  ///
  /// In en, this message translates to:
  /// **'Application RAM (all PC workers)'**
  String get resourcesAppRam;

  /// No description provided for @resourcesRamAvailable.
  ///
  /// In en, this message translates to:
  /// **'System RAM available'**
  String get resourcesRamAvailable;

  /// No description provided for @resourcesSystemRam.
  ///
  /// In en, this message translates to:
  /// **'System RAM usage'**
  String get resourcesSystemRam;

  /// No description provided for @resourcesGpuTotal.
  ///
  /// In en, this message translates to:
  /// **'Whole GPU VRAM used'**
  String get resourcesGpuTotal;

  /// No description provided for @resourcesAppVram.
  ///
  /// In en, this message translates to:
  /// **'Application compute VRAM'**
  String get resourcesAppVram;

  /// No description provided for @resourcesDiskAvailable.
  ///
  /// In en, this message translates to:
  /// **'PC workspace disk available'**
  String get resourcesDiskAvailable;

  /// No description provided for @resourcesScratch.
  ///
  /// In en, this message translates to:
  /// **'Server temporary files'**
  String get resourcesScratch;

  /// No description provided for @resourcesStoragePartial.
  ///
  /// In en, this message translates to:
  /// **'Folder size is still counting or partially unavailable.'**
  String get resourcesStoragePartial;

  /// No description provided for @resourcesProcessPartial.
  ///
  /// In en, this message translates to:
  /// **'Some application processes could not be measured.'**
  String get resourcesProcessPartial;

  /// No description provided for @resourcesWaiting.
  ///
  /// In en, this message translates to:
  /// **'Waiting for PC resources'**
  String get resourcesWaiting;

  /// No description provided for @resourcesScopeHint.
  ///
  /// In en, this message translates to:
  /// **'These readings describe the PC, not this phone. Shared RAM pages may be counted more than once. Whole GPU usage includes other apps; application VRAM may be unavailable with the PC driver. Updates every 5 seconds while this panel is visible.'**
  String get resourcesScopeHint;

  /// No description provided for @resourcesLimitsHint.
  ///
  /// In en, this message translates to:
  /// **'Set optional admission thresholds in PC Settings → PC resources & protection. They delay new compute work; they are not hard memory caps for running tasks.'**
  String get resourcesLimitsHint;

  /// No description provided for @resourcesUpdated.
  ///
  /// In en, this message translates to:
  /// **'Last sample'**
  String get resourcesUpdated;

  /// No description provided for @charactersTitle.
  ///
  /// In en, this message translates to:
  /// **'Cartoon & anime characters'**
  String get charactersTitle;

  /// No description provided for @charactersScan.
  ///
  /// In en, this message translates to:
  /// **'Scan illustrated characters'**
  String get charactersScan;

  /// No description provided for @charactersScanHint.
  ///
  /// In en, this message translates to:
  /// **'For cartoon or anime albums. Scan bodies, hair, clothing and visual details instead of human faces. Select illustrated albums before scanning.'**
  String get charactersScanHint;

  /// No description provided for @charactersEmpty.
  ///
  /// In en, this message translates to:
  /// **'No characters yet'**
  String get charactersEmpty;

  /// No description provided for @charactersEmptyHint.
  ///
  /// In en, this message translates to:
  /// **'Choose cartoon or anime albums in Scan sources and enable illustrated character scanning. Detection runs on the PC; your character library and appearance matching stay on this phone.'**
  String get charactersEmptyHint;

  /// No description provided for @charactersAccuracyHint.
  ///
  /// In en, this message translates to:
  /// **'Grouped by visual appearance. Different outfits, hidden bodies or similar designs can need correction. Open a group to name it or separate a mistaken match.'**
  String get charactersAccuracyHint;

  /// No description provided for @characterSeparate.
  ///
  /// In en, this message translates to:
  /// **'Separate this character'**
  String get characterSeparate;

  /// No description provided for @characterName.
  ///
  /// In en, this message translates to:
  /// **'Character name'**
  String get characterName;

  /// No description provided for @characterOpenSource.
  ///
  /// In en, this message translates to:
  /// **'Open source'**
  String get characterOpenSource;

  /// No description provided for @charactersTestPhoto.
  ///
  /// In en, this message translates to:
  /// **'Test a character photo'**
  String get charactersTestPhoto;

  /// No description provided for @charactersTestHint.
  ///
  /// In en, this message translates to:
  /// **'Test one illustration on the PC without saving it to your library. Bodies, hair, clothing and visual details are analysed; no human face is needed.'**
  String get charactersTestHint;

  /// No description provided for @characterFallback.
  ///
  /// In en, this message translates to:
  /// **'Character {id}'**
  String characterFallback(int id);

  /// No description provided for @characterSamples.
  ///
  /// In en, this message translates to:
  /// **'{count} appearances'**
  String characterSamples(int count);

  /// No description provided for @charactersFound.
  ///
  /// In en, this message translates to:
  /// **'{count} character appearances found'**
  String charactersFound(int count);

  /// No description provided for @quickReviewTitle.
  ///
  /// In en, this message translates to:
  /// **'Quick review'**
  String get quickReviewTitle;

  /// No description provided for @quickReviewProgress.
  ///
  /// In en, this message translates to:
  /// **'{current} of {total}'**
  String quickReviewProgress(int current, int total);

  /// No description provided for @quickSeeAll.
  ///
  /// In en, this message translates to:
  /// **'See all'**
  String get quickSeeAll;

  /// No description provided for @quickYes.
  ///
  /// In en, this message translates to:
  /// **'Yes'**
  String get quickYes;

  /// No description provided for @quickNo.
  ///
  /// In en, this message translates to:
  /// **'No'**
  String get quickNo;

  /// No description provided for @quickNotSure.
  ///
  /// In en, this message translates to:
  /// **'Not sure'**
  String get quickNotSure;

  /// No description provided for @quickSwipeHint.
  ///
  /// In en, this message translates to:
  /// **'Swipe right for Yes, left for No'**
  String get quickSwipeHint;

  /// No description provided for @quickSamePerson.
  ///
  /// In en, this message translates to:
  /// **'Same person?'**
  String get quickSamePerson;

  /// No description provided for @quickWhoIsThis.
  ///
  /// In en, this message translates to:
  /// **'Who is this?'**
  String get quickWhoIsThis;

  /// No description provided for @quickWhoHint.
  ///
  /// In en, this message translates to:
  /// **'Type a new name or pick someone'**
  String get quickWhoHint;

  /// No description provided for @quickNewPersonHelper.
  ///
  /// In en, this message translates to:
  /// **'Saves a new person'**
  String get quickNewPersonHelper;

  /// No description provided for @quickAddToHelper.
  ///
  /// In en, this message translates to:
  /// **'Adds these faces to {name}'**
  String quickAddToHelper(String name);

  /// No description provided for @quickGroupFaces.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 photo of this face} other{{count} photos of this face}}'**
  String quickGroupFaces(int count);

  /// No description provided for @quickByClothes.
  ///
  /// In en, this message translates to:
  /// **'Recognised by clothes'**
  String get quickByClothes;

  /// No description provided for @quickByWeakFace.
  ///
  /// In en, this message translates to:
  /// **'Recognised by a small or blurry face'**
  String get quickByWeakFace;

  /// No description provided for @quickSnoozed.
  ///
  /// In en, this message translates to:
  /// **'Saved for later. It comes back when new photos give more evidence.'**
  String get quickSnoozed;

  /// No description provided for @quickAllDone.
  ///
  /// In en, this message translates to:
  /// **'All caught up'**
  String get quickAllDone;

  /// No description provided for @quickAllDoneBody.
  ///
  /// In en, this message translates to:
  /// **'New questions appear after the next scan or Sort now.'**
  String get quickAllDoneBody;

  /// No description provided for @quickAllDoneSnoozed.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 answer you weren\'t sure about is waiting until there is more evidence. See all to decide now.} other{{count} answers you weren\'t sure about are waiting until there is more evidence. See all to decide now.}}'**
  String quickAllDoneSnoozed(int count);

  /// No description provided for @likelihoodVeryLikely.
  ///
  /// In en, this message translates to:
  /// **'Very likely'**
  String get likelihoodVeryLikely;

  /// No description provided for @likelihoodLikely.
  ///
  /// In en, this message translates to:
  /// **'Likely'**
  String get likelihoodLikely;

  /// No description provided for @likelihoodMaybe.
  ///
  /// In en, this message translates to:
  /// **'Maybe'**
  String get likelihoodMaybe;

  /// No description provided for @reviewAdvancedTitle.
  ///
  /// In en, this message translates to:
  /// **'Advanced review details'**
  String get reviewAdvancedTitle;

  /// No description provided for @reviewAdvancedBody.
  ///
  /// In en, this message translates to:
  /// **'Show percentages and how bodies were linked, and open Review on all four lists instead of one question at a time'**
  String get reviewAdvancedBody;

  /// No description provided for @peopleReviewBanner.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Help improve your groups · 1 question} other{Help improve your groups · {count} questions}}'**
  String peopleReviewBanner(int count);

  /// No description provided for @peopleReviewBannerBody.
  ///
  /// In en, this message translates to:
  /// **'Quick yes / no answers, one photo at a time'**
  String get peopleReviewBannerBody;

  /// No description provided for @albumReviewBanner.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Review 1 photo} other{Review {count} photos}}'**
  String albumReviewBanner(int count);

  /// No description provided for @albumReviewBannerBody.
  ///
  /// In en, this message translates to:
  /// **'Photos that may also be {name}'**
  String albumReviewBannerBody(String name);

  /// No description provided for @albumReviewTitle.
  ///
  /// In en, this message translates to:
  /// **'Is this {name}?'**
  String albumReviewTitle(String name);

  /// No description provided for @albumReviewHelp.
  ///
  /// In en, this message translates to:
  /// **'Every photo starts ticked. Untick the ones that aren\'t {name}, then tap Done. Long-press a photo to see it full size.'**
  String albumReviewHelp(String name);

  /// No description provided for @albumReviewNone.
  ///
  /// In en, this message translates to:
  /// **'Untick all'**
  String get albumReviewNone;

  /// No description provided for @albumReviewSummary.
  ///
  /// In en, this message translates to:
  /// **'{add} to add · {remove} someone else'**
  String albumReviewSummary(int add, int remove);

  /// No description provided for @albumReviewSaved.
  ///
  /// In en, this message translates to:
  /// **'{add} added · {remove} marked as someone else'**
  String albumReviewSaved(int add, int remove);

  /// No description provided for @viewerUnknownPerson.
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get viewerUnknownPerson;

  /// No description provided for @viewerReassign.
  ///
  /// In en, this message translates to:
  /// **'Change who this is'**
  String get viewerReassign;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}

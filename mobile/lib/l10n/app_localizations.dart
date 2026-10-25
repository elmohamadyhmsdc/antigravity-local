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
  /// **'{count, plural, =1{Their 1 face becomes unsorted.} other{Their {count} faces become unsorted.}} Nothing else is deleted.'**
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
  /// **'Duplicates ({count})'**
  String reviewTabDuplicates(int count);

  /// No description provided for @reviewTabGroups.
  ///
  /// In en, this message translates to:
  /// **'New groups ({count})'**
  String reviewTabGroups(int count);

  /// No description provided for @reviewTabMatches.
  ///
  /// In en, this message translates to:
  /// **'Matches ({count})'**
  String reviewTabMatches(int count);

  /// No description provided for @reviewTabOutfits.
  ///
  /// In en, this message translates to:
  /// **'Outfits ({count})'**
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
  /// **'HD'**
  String get refaceHd;

  /// No description provided for @refaceLegacy.
  ///
  /// In en, this message translates to:
  /// **'Legacy'**
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
  /// **'Legacy uses automatic OpenCV enhancement and its own occlusion protection.'**
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

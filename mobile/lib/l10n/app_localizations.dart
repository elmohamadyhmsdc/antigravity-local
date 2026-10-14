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
  /// **'Antigravity'**
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
  /// **'Antigravity does the heavy AI work on your Windows PC. Your photos, faces and results stay on this phone - the PC only computes.'**
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
  /// **'That is not an Antigravity pairing code.'**
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
  /// **'Antigravity asks only for what it needs. You can change these later in Android settings.'**
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
  /// **'Antigravity could not open its database'**
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
  /// **'Choose the albums whose photos should be scanned. Photos stay on this phone; only a downscaled copy of each is sent to your PC.'**
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
  /// **'Your library lives only on this phone. A backup is one file you can keep in Files, Drive or on your PC; restoring it brings everything back exactly as it was.'**
  String get backupIntro;

  /// No description provided for @backupKeepSafe.
  ///
  /// In en, this message translates to:
  /// **'The backup file is not encrypted. Keep it somewhere private - it contains the faces of the people in your photos.'**
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
  /// **'Antigravity backup'**
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
  /// **'People, faces and their pictures, body links, which photos each person is in, your corrections and your grouping settings. Not included: your original photos (they stay in your gallery), the pairing with your PC and anything stored on the PC.'**
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
  /// **'Antigravity needs permission to read your photos before it can scan them.'**
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
  /// **'Scanning keeps going with the screen off. Photos already scanned are skipped, so you can run it again whenever new photos arrive.'**
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
  /// **'Find the faces in your photos'**
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
  /// **'{done}/{total} photos · {faces} faces'**
  String scanNotificationText(int done, int total, int faces);

  /// No description provided for @scanNotificationTitle.
  ///
  /// In en, this message translates to:
  /// **'Scanning your photos'**
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
  /// **'Who is in this photo'**
  String get whoIsHere;

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;
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

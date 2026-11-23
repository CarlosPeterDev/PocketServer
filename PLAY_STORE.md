# Publishing PocketServer on Google Play

Use **`PocketServer-android-play.aab`** from the GitHub Release. The GitHub-only `PocketServer-android*.apk` files
ask for "All files access" and the battery exemption, which Google Play restricts: do not upload those.

## Already handled in the code
- **No restricted permissions in the Play build**: no `MANAGE_EXTERNAL_STORAGE`, no `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`
  (stripped by `tool/patch_platforms.py strip-allfiles`; the app opens the battery settings page instead).
- No boot receiver / no `RECEIVE_BOOT_COMPLETED`, no unused multicast permission, cloud backup off (the config file holds server passwords).
- Foreground service type `specialUse` with the required subtype property; a notification is always shown while servers run.
- **Ads**: Google UMP consent form for EU/UK before any ad request, "Ad privacy choices" entry in Settings when required,
  ad content capped at PG, app-open ad only on the loading screen (never after the home screen), banner at the top away from buttons.
- **Privacy policy** shown on first launch (must be accepted), readable later in Settings, and in `PRIVACY.md`.
- Nothing starts (servers, ads, notification prompt) before the policy is accepted.
- Targets the latest Android SDK of the Flutter stable channel, 64-bit, AAB, version code = CI run number.

## Only you can do these (left open on purpose)
1. **Signing key.** `signing/pocketserver.jks` is committed with a public password: fine for test builds, **not for
   release**. Create your own upload key, keep it private and put it in GitHub secrets:
   `keytool -genkeypair -v -keystore upload.jks -alias upload -keyalg RSA -keysize 2048 -validity 10000`
   Enrol in *Play App Signing* when you create the app.
2. **Real AdMob ids.** Replace the Google test ids in `lib/ads.dart` (`AdIds`), the `APPLICATION_ID` meta-data in
   `tool/patch_platforms.py` and `GADApplicationIdentifier` (iOS). In AdMob, create the EU consent message (Privacy &
   messaging) and publish `app-ads.txt` on your developer website.
3. **Hosted privacy policy URL.** Play needs a public page. This works: `https://github.com/CarlosPeterDev/PocketServer/blob/main/PRIVACY.md`
   (better: enable GitHub Pages or put it on your own site). Put the same URL in the Play Console.

## Play Console answers (suggested, check them against the final app)
- **App access**: all functionality available without login.
- **Ads**: yes, the app contains ads.
- **Target audience**: 13+ / general; not designed for children.
- **Data safety**
  - The app itself sends nothing to your servers; files, passwords and settings stay on the device.
  - Declare what the **Google AdMob SDK** collects: *Device or other IDs* (advertising ID), and per Google's AdMob
    guidance also IP-derived approximate location, app interactions and diagnostics, for *Advertising*; data is shared with
    Google; encrypted in transit. Follow https://support.google.com/admob/answer/10970040 .
  - "Data deletion": no account, nothing stored by you.
- **Foreground service declaration** (Policy > App content): type *Special use*. Subtype text:
  `Local file sharing server (HTTP, FTP, FTPS) that the user starts and stops`. Explanation: the user switches file-sharing servers
  on; they must keep answering other devices on the local network while the screen is off; a notification is shown the whole time; stopping the
  servers stops the service. Play asks for a short screen recording that shows switching a server on, the notification, and a
  device connecting.
- **Content rating (IARC)**: no violence, sexual content, gambling or drugs. Answer "yes" to users sharing files with others
  (it is private, on the user's own network, not public).
- **Permissions shown to users**: Network (run the servers), Notifications (foreground service notice), Advertising ID (ads).

## Known limits of the Play build (be upfront in the listing)
- It can only share PocketServer's own folder (reachable through the web hub, FTP and WebDAV). Sharing any folder needs
  "All files access", which Play does not allow for this kind of app. A future option is the Storage Access Framework (a
  larger change: files are then read through the system instead of directly).
- On Android 11+ the app folder is under `Android/data/dev.carlospeter.pocketserver/files/PocketServer`, which phone file
  managers hide: users add files through the web hub or an FTP/WebDAV client.
- Not a legal review: have the privacy policy and Data safety form checked before you submit.

## Store listing draft
**Title**: PocketServer: Wi-Fi file share
**Short**: Share files with any device on your WiFi or hotspot: web, FTP, FTPS and WebDAV.
**Long**: PocketServer turns your phone into a private file box. Open your files from a laptop, TV or another phone on the same
WiFi or hotspot, with no cables, no cloud and no accounts with us. Web page, FTP / FTPS, WebDAV network drive, several servers
with their own folders, password protection, live dashboard, English and Arabic.
**العنوان**: PocketServer: مشاركة ملفات عبر الواي فاي
**وصف قصير**: شارك الملفات مع أي جهاز على نفس الواي فاي أو الهوت سبوت: ويب وFTP وFTPS وWebDAV.

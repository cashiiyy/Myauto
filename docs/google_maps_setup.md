# Google Maps Platform Setup Guide for MyAuto

This guide details the steps required to configure Google Maps Platform for the MyAuto Flutter application.

---

## 1. Prerequisites & Required Google Cloud API

For the immediate MyAuto mobility experience, only one API is required:
* **Maps SDK for Android** (Required)

### Future Optional APIs (Do NOT enable yet):
* Maps SDK for iOS (when building for Apple devices)
* Routes API (turn-by-turn navigation / traffic matrices)
* Geocoding API / Places API (if replacing Photon)
* Maps JavaScript API (if web build is targeted)

---

## 2. API Key Configuration

1. Go to the [Google Cloud Console](https://console.cloud.google.com/).
2. Select or create your MyAuto project.
3. Navigate to **APIs & Services** > **Credentials**.
4. Click **Create Credentials** > **API Key**.
5. Copy the generated API key.

---

## 3. Local Development Setup (Secure)

To prevent committing secrets, MyAuto uses Gradle `manifestPlaceholders` fed from `android/local.properties` (which is git-ignored).

1. Open `android/local.properties`.
2. Add your development API key:
   ```properties
   GOOGLE_MAPS_API_KEY=AIzaSy...YourDevApiKeyHere
   ```
3. Save the file. The Gradle build automatically injects this key into `AndroidManifest.xml` during compilation.

> Note: Never commit `android/local.properties` or hardcode API keys in Dart code or `AndroidManifest.xml`.

---

## 4. API Key Restrictions (Security Best Practice)

### Development Key Restrictions:
* **API Restrictions:** Restrict key to **Maps SDK for Android**.
* **Application Restrictions:** Set to **Android apps**.
* Add package name: `com.myauto.com`
* Add Debug SHA-1 certificate fingerprint:
  Run in terminal:
  ```bash
  keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey -storepass android -keypass android
  ```
  Copy the `SHA1` fingerprint and add it in Cloud Console.

### Production Key Restrictions:
* Create a dedicated production API key.
* Add Release SHA-1 fingerprint from your production upload keystore / Google Play App Signing key.
* Set package name: `com.myauto.com`.
* Configure budget alerts in **Google Cloud Billing** to monitor tile consumption.

---

## 5. Emulator Requirements

* Use an Android Virtual Device (AVD) configured with **Google APIs** or **Google Play Store** system image.
* Google Maps native rendering will fail or show a blank grid on pure AOSP images without Google Play Services.

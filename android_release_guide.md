# YATZY! Android Release & Packaging Guide

This guide details the step-by-step procedure to generate Android platform files, configure production settings, configure adaptive launcher icons, establish signing credentials, and compile the production APK / AAB (Android App Bundle) for the Google Play Store.

---

## 1. Platform Initialization

Since the code is structured cross-platform and does not contain native folders by default, you must generate the Android directories first. Run the following command from the root of the project:

```bash
flutter create --org app.opengames --project-name open_yatzy .
```

This will initialize the `android/` directory with standard configuration templates.

---

## 2. Configure Package Details & SDK Levels

Open `android/app/build.gradle` and configure the compile SDK, target SDK, and unique application ID.

1. **Locate the `android` block** and verify/update the SDK compile version:
   ```groovy
   android {
       compileSdkVersion 34 // Android 14
       ...
   }
   ```

2. **Locate the `defaultConfig` block** and configure your unique package identifier and SDK range:
   ```groovy
   defaultConfig {
       applicationId "app.opengames.yatzy"
       minSdkVersion 21        // Supports Android 5.0 (Lollipop) and above
       targetSdkVersion 34     // Android 14
       versionCode 1
       versionName "1.0.0"
   }
   ```

---

## 3. Configure Android Manifest (Vibration & App Name)

Open `android/app/src/main/AndroidManifest.xml` and add the vibration permission and set the application title.

1. **Add the Vibration Permission** under the root `<manifest>` tag, alongside any existing permissions:
   ```xml
   <uses-permission android:name="android.permission.VIBRATE"/>
   ```

2. **Update the Application Label** under the `<application>` tag:
   ```xml
   <application
       android:label="YATZY!"
       ...
   ```

---

## 4. App Launch Icons Generation

We have pre-configured `flutter_launcher_icons` in your `pubspec.yaml`. 

To generate high-resolution adaptive launcher icons for Android from the golden-yellow board game logo (`assets/images/logo.png`), run the following command:

```bash
flutter pub run flutter_launcher_icons:main
```

This will automatically generate adaptive and round icons and place them in the native Android mipmap resource directories.

---

## 5. Configure Android App Signing

To upload the app to the Google Play Store, the app must be signed with a release keystore.

### Step A: Generate Upload Keystore
Run the following command in terminal to generate a keystore file:

**On Windows (PowerShell):**
```powershell
keytool -genkey -v -keystore c:\Users\YOUR_USER_NAME\upload-keystore.jks -storetype JKS -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

**On macOS/Linux:**
```bash
keytool -genkey -v -keystore ~/upload-keystore.jks -storetype JKS -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

*(Note: Keep the keystore file secure and write down the password you entered.)*

### Step B: Create key.properties File
Create a file named `android/key.properties` with the following configuration (replace with your values and path):

```properties
storePassword=YOUR_KEYSTORE_PASSWORD
keyPassword=YOUR_KEY_PASSWORD
keyAlias=upload
storeFile=C:\\Users\\YOUR_USER_NAME\\upload-keystore.jks
```

### Step C: Configure build.gradle for Signing
Open `android/app/build.gradle` and add code to read the signing key property file.

Add the following block **before** the `android` block:

```groovy
def keystoreProperties = new Properties()
def keystorePropertiesFile = rootProject.file('key.properties')
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(new FileInputStream(keystorePropertiesFile))
}
```

Now, inside the `android` block, configure the signing configurations:

```groovy
android {
    ...
    signingConfigs {
        release {
            keyAlias keystoreProperties['keyAlias']
            keyPassword keystoreProperties['keyPassword']
            storeFile keystoreProperties['storeFile'] ? file(keystoreProperties['storeFile']) : null
            storePassword keystoreProperties['storePassword']
        }
    }

    buildTypes {
        release {
            signingConfig signingConfigs.release
            
            // Enable shrinking, obfuscation, and optimization
            minifyEnabled true
            shrinkResources true
            proguardFiles getDefaultProguardFile('proguard-android-optimize.txt'), 'proguard-rules.pro'
        }
    }
}
```

---

## 6. Build the Application

Once everything is configured, clean the build cache and run the release build commands:

```bash
flutter clean
flutter pub get
```

### Build APK (for local testing/direct installation)
```bash
flutter build apk --release
```
*Output path:* `build/app/outputs/flutter-apk/app-release.apk`

### Build App Bundle (AAB - for Play Store upload)
```bash
flutter build appbundle --release
```
*Output path:* `build/app/outputs/bundle/release/app-release.aab`

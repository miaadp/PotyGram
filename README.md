# PotyGram Mobile — Native Flutter Client (Android & Windows)

100% native, end-to-end encrypted messaging client for **PotyGram**, built with **Flutter** and **C libsodium** bindings.

---

## Architecture

| Layer | Implementation |
|---|---|
| **Language & Framework** | Flutter 3.x / Dart |
| **Cryptography** | `flutter_sodium` (direct C FFI bindings to official `libsodium` on ARM64/x86_64) |
| **Key Storage** | `flutter_secure_storage` (Android Keystore / EncryptedSharedPreferences) |
| **Local Cache** | SQLite (`sqflite`) for messages and conversations |
| **Networking** | `dio` with automatic CSRF, remember token headers, and token rotation |
| **Realtime Sync** | Adaptive short-polling service (`api.php?action=sync`) matching Web client |

---

## Cryptographic Protocol (Matches Web Client)

1. **Identity & Box Keys:**
   - X25519 asymmetric sealed box (`crypto_box_seal` / `crypto_box_seal_open`) for DM text and media keys.
2. **Signing Keys:**
   - Ed25519 detached signatures (`crypto_sign_detached` / `crypto_sign_verify_detached`) for login challenges, registration proofs, and outgoing message payloads.
3. **Account Backup Format:**
   - Exported as `<boxSecretKeyHex> | sign:<signSecretKeyHex>` (identical to the web client).

---

## Cloud Build & APK Generation (GitHub Actions)

This repository includes an automated CI workflow at `.github/workflows/build-apk.yml`.

### How to get the compiled APK:
1. Push your commits to GitHub.
2. Go to **Actions** tab in your GitHub repository.
3. Select **Build Android APK** and click **Run workflow** (or let it run automatically on push).
4. When complete (~3–4 minutes), download the compiled **`potygram-release-apk`** from the Artifacts section!

---

## Local Development (Optional)

If you have Flutter and Android SDK installed locally:
```bash
cd flutter_app
flutter pub get
flutter run
```

To build a release APK locally:
```bash
flutter build apk --release
```
The APK will be located at `build/app/outputs/flutter-apk/app-release.apk`.

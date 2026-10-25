#!/usr/bin/env python3
import os
import glob

def main():
    # 1. Detect installed NDK version
    android_home = os.environ.get('ANDROID_HOME', '')
    ndk_ver = ''
    if android_home:
        ndk_dirs = sorted(glob.glob(os.path.join(android_home, 'ndk', '*')))
        if ndk_dirs:
            ndk_ver = os.path.basename(ndk_dirs[-1])
            print(f"Detected Android NDK version: {ndk_ver}")

    # 2. Update AndroidManifest.xml
    manifest_path = 'android/app/src/main/AndroidManifest.xml'
    if os.path.exists(manifest_path):
        print("Configuring AndroidManifest.xml...")
        with open(manifest_path, 'r', encoding='utf-8') as f:
            content = f.read()
        perms = '''
    <uses-permission android:name="android.permission.INTERNET"/>
    <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE"/>
    <uses-permission android:name="android.permission.RECORD_AUDIO"/>
    <uses-permission android:name="android.permission.VIBRATE"/>
'''
        if '<uses-permission' not in content:
            content = content.replace('<application', perms + '\n    <application', 1)
            with open(manifest_path, 'w', encoding='utf-8') as f:
                f.write(content)

    # 3. Update app build.gradle
    for fname in ['android/app/build.gradle', 'android/app/build.gradle.kts']:
        if os.path.exists(fname):
            print(f"Configuring {fname}...")
            with open(fname, 'r', encoding='utf-8') as f:
                c = f.read()
            c = c.replace('flutter.minSdkVersion', '24')
            c = c.replace('minSdk = flutter.minSdkVersion', 'minSdk = 24')
            c = c.replace('minSdkVersion flutter.minSdkVersion', 'minSdkVersion 24')
            if ndk_ver:
                c = c.replace('flutter.ndkVersion', f'"{ndk_ver}"')
            with open(fname, 'w', encoding='utf-8') as f:
                f.write(c)

    print("Android configuration complete.")

if __name__ == '__main__':
    main()

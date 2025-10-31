# 🚀 달빛 배달부 루나 - 퍼블리싱 가이드

게임을 웹과 앱으로 배포하는 완벽한 가이드입니다!

---

## 📱 옵션 1: Android APK 배포 (가장 쉬움!)

### ✅ **장점**
- 🎯 가장 빠르고 간단한 배포 방법
- 📦 APK 파일 하나로 누구나 설치 가능
- 💰 무료 배포 (스토어 수수료 없음)
- 🔧 업데이트 자유로움

### 📦 **APK 빌드 방법**

```bash
# 프로젝트 디렉토리로 이동
cd /home/user/flutter_app

# Release APK 빌드 (프로덕션용)
flutter build apk --release

# 빌드 완료 후 APK 위치:
# build/app/outputs/flutter-apk/app-release.apk
```

### 📤 **배포 방법**

**방법 1: 직접 공유**
- APK 파일을 Google Drive, Dropbox, WeTransfer 등에 업로드
- 공유 링크를 친구들에게 전달
- 안드로이드 기기에서 다운로드 후 설치

**방법 2: GitHub Releases**
- GitHub 저장소에 APK 업로드
- Release 태그 생성 (예: v1.0.0)
- 누구나 다운로드 가능

**방법 3: 자체 웹사이트**
- 본인 웹사이트에 APK 파일 호스팅
- 다운로드 버튼 제공

### ⚠️ **설치 시 주의사항**

사용자가 APK를 설치할 때:
1. **"출처를 알 수 없는 앱"** 경고 표시됨
2. 설정 → 보안 → "알 수 없는 출처" 허용 필요
3. 이것은 정상적인 과정입니다 (Play Store 외부 앱)

---

## 🌐 옵션 2: 웹 배포 (초간단!)

### ✅ **장점**
- 🌍 모든 플랫폼에서 접근 가능 (Windows, Mac, Android, iOS)
- 🔗 링크만 공유하면 바로 플레이
- 📱 설치 불필요
- 🆓 완전 무료 호스팅 가능

### 🏗️ **웹 빌드 방법**

```bash
# 프로젝트 디렉토리로 이동
cd /home/user/flutter_app

# Release 웹 빌드
flutter build web --release

# 빌드 완료 후 웹 파일 위치:
# build/web/
```

### 🌐 **무료 호스팅 옵션**

#### **1. GitHub Pages (추천! 완전 무료)**

**단계:**
1. GitHub 저장소 생성
2. `build/web` 폴더 내용을 저장소에 푸시
3. Settings → Pages → Source: main branch 선택
4. 완료! URL: `https://yourusername.github.io/repo-name`

**명령어:**
```bash
cd /home/user/flutter_app/build/web
git init
git add .
git commit -m "Deploy game"
git remote add origin https://github.com/YOUR_USERNAME/YOUR_REPO.git
git push -u origin main
```

#### **2. Netlify (가장 쉬움!)**

**단계:**
1. https://netlify.com 접속 (무료)
2. "Add new site" → "Deploy manually"
3. `build/web` 폴더를 드래그 앤 드롭
4. 완료! 자동으로 URL 생성 (예: `https://your-game.netlify.app`)

**특징:**
- ✅ 드래그 앤 드롭만으로 배포
- ✅ 자동 HTTPS 제공
- ✅ 무료 CDN (빠른 로딩)
- ✅ 커스텀 도메인 연결 가능

#### **3. Vercel (개발자 친화적)**

**단계:**
1. https://vercel.com 접속 (무료)
2. GitHub 저장소 연결
3. Build settings: 없음 (이미 빌드됨)
4. Output directory: `build/web`
5. 완료!

#### **4. Firebase Hosting (Google 제공)**

**단계:**
```bash
# Firebase CLI 설치
npm install -g firebase-tools

# Firebase 로그인
firebase login

# 프로젝트 초기화
cd /home/user/flutter_app
firebase init hosting

# 설정:
# - Public directory: build/web
# - Single-page app: Yes
# - Overwrite index.html: No

# 배포
firebase deploy --only hosting

# 완료! URL: https://your-project.firebase.app
```

---

## 🏪 옵션 3: Google Play Store 배포 (공식!)

### ✅ **장점**
- 🏆 공식 앱 스토어 (신뢰도 높음)
- 🔄 자동 업데이트
- 📊 다운로드 통계
- 💰 수익화 가능 (광고, 인앱 구매)

### ⚠️ **단점**
- 💵 개발자 등록 비용: $25 (평생 1회)
- ⏰ 심사 시간: 1~3일
- 📋 정책 준수 필요

### 📦 **Play Store 배포 단계**

#### **1. App Bundle 빌드**
```bash
cd /home/user/flutter_app

# AAB 파일 빌드 (Play Store 필수 형식)
flutter build appbundle --release

# 빌드 완료 후 AAB 위치:
# build/app/outputs/bundle/release/app-release.aab
```

#### **2. 키 서명 생성**
```bash
# 키스토어 생성 (앱 서명용)
keytool -genkey -v -keystore ~/upload-keystore.jks \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -alias upload

# 정보 입력:
# - 비밀번호 설정 (기억하세요!)
# - 이름, 조직, 국가 등 입력
```

#### **3. 앱 서명 설정**

`android/key.properties` 파일 생성:
```properties
storePassword=<키스토어 비밀번호>
keyPassword=<키 비밀번호>
keyAlias=upload
storeFile=<키스토어 파일 경로>
```

`android/app/build.gradle.kts` 수정:
```kotlin
// key.properties 파일 로드
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    // ...
    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties["keyAlias"] as String
            keyPassword = keystoreProperties["keyPassword"] as String
            storeFile = file(keystoreProperties["storeFile"] as String)
            storePassword = keystoreProperties["storePassword"] as String
        }
    }
    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
        }
    }
}
```

#### **4. Google Play Console 설정**

1. **개발자 계정 등록**: https://play.google.com/console
   - $25 결제 (평생 사용)
   - 개인정보 입력

2. **새 앱 만들기**
   - 앱 이름: "달빛 배달부 루나"
   - 기본 언어: 한국어
   - 앱/게임 선택: 게임
   - 무료/유료 선택: 무료

3. **스토어 등록 정보 작성**
   - 앱 설명 (짧은 설명, 자세한 설명)
   - 스크린샷 (최소 2장, 휴대전화용)
   - 아이콘 (512x512 PNG)
   - 기능 그래픽 (1024x500 PNG)

4. **콘텐츠 등급 설정**
   - 설문 작성 (폭력성, 성적 콘텐츠 등)
   - 게임은 일반적으로 "3세 이상"

5. **개인정보 보호정책**
   - 개인정보를 수집하지 않으면 "아니요" 선택
   - Firebase 사용 시 정책 URL 필요

6. **AAB 업로드**
   - 프로덕션 → 새 출시 만들기
   - `app-release.aab` 파일 업로드
   - 출시 노트 작성

7. **심사 제출**
   - 모든 항목 체크 완료
   - "심사 제출" 클릭
   - 1~3일 내 결과 통보

---

## 🍎 옵션 4: iOS App Store (선택사항)

### ⚠️ **요구사항**
- 💻 **Mac 필수** (Windows/Linux에서 빌드 불가)
- 💰 Apple Developer 계정: $99/년
- ⏰ 심사 시간: 1~7일

### 📦 **iOS 빌드 방법 (Mac에서)**
```bash
# Xcode 프로젝트 열기
open ios/Runner.xcworkspace

# Xcode에서:
# 1. Team 선택 (Apple Developer 계정)
# 2. Bundle Identifier 설정
# 3. Product → Archive
# 4. Distribute App → App Store Connect
```

---

## 🎯 **추천 배포 순서**

### **초보자 (가장 쉬운 순서)**
1. ✅ **웹 배포 (Netlify)** - 5분 완료
2. ✅ **Android APK 직접 공유** - 친구들에게 테스트
3. 📱 Play Store 배포 고려 (다운로드 많으면)

### **본격 배포 (최고의 도달)**
1. 🌐 **웹 배포** - 모든 플랫폼 접근
2. 📱 **Play Store** - Android 공식 배포
3. 🍎 **App Store** - iOS 사용자 지원

---

## 📊 **배포 옵션 비교**

| 옵션 | 난이도 | 비용 | 시간 | 도달범위 |
|------|--------|------|------|---------|
| **웹 (Netlify)** | ⭐ 매우 쉬움 | 무료 | 5분 | 전세계 모든 기기 |
| **APK 직접 공유** | ⭐⭐ 쉬움 | 무료 | 10분 | Android만 |
| **GitHub Pages** | ⭐⭐ 쉬움 | 무료 | 15분 | 전세계 모든 기기 |
| **Play Store** | ⭐⭐⭐ 보통 | $25 (1회) | 3~5일 | Android (공식) |
| **App Store** | ⭐⭐⭐⭐⭐ 어려움 | $99/년 | 1주일 | iOS (공식) |

---

## 🚀 **지금 당장 시작하기 (5분 안에!)**

### **가장 빠른 방법: Netlify 웹 배포**

1. ✅ 이미 빌드된 파일 사용: `/home/user/flutter_app/build/web`
2. ✅ https://netlify.com 접속
3. ✅ "Add new site" → "Deploy manually"
4. ✅ `build/web` 폴더 드래그 앤 드롭
5. ✅ 완료! 링크 받기

**또는 Android APK 빌드:**
```bash
cd /home/user/flutter_app
flutter build apk --release

# 완료! APK 다운로드:
# build/app/outputs/flutter-apk/app-release.apk
```

---

## 💡 **추가 팁**

### **게임 업데이트 방법**
- 웹: 다시 빌드 후 호스팅 업데이트
- APK: 새 버전 공유 (버전 코드 증가 필요)
- Play Store: 새 AAB 업로드 (자동 업데이트)

### **버전 관리**
`pubspec.yaml`에서 버전 수정:
```yaml
version: 1.0.0+1  # 1.0.0 = 버전명, +1 = 버전코드
```

### **Firebase 설정 주의**
- 웹 배포 시: `firebase_options.dart`의 Web 설정 필요
- Android 배포 시: `google-services.json` 필요

---

## 🎉 **성공적인 퍼블리싱을 응원합니다!**

어떤 방법을 선택하시겠어요? 도움이 필요하면 말씀해주세요! 🚀

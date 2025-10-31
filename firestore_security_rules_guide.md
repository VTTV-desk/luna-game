# 🔥 Firestore 보안 규칙 설정 가이드

## 문제 상황
현재 Firestore 보안 규칙이 모든 접근을 차단하고 있어, 게임 데이터를 저장하거나 불러올 수 없습니다.

## 해결 방법: Firebase Console에서 보안 규칙 업데이트

### 1단계: Firebase Console 접속
1. 🌐 브라우저에서 Firebase Console 열기: **https://console.firebase.google.com/**
2. 프로젝트 선택: **moonlight-delivery-luna**

### 2단계: Firestore Database 메뉴 이동
1. 왼쪽 메뉴에서 **"빌드(Build)"** 섹션 찾기
2. **"Firestore Database"** 클릭

### 3단계: 보안 규칙 탭 열기
1. 상단 탭에서 **"규칙(Rules)"** 클릭
2. 현재 규칙 확인 (아마도 `allow read, write: if false;` 상태)

### 4단계: 새 보안 규칙 적용
아래 규칙을 복사하여 붙여넣고 **"게시(Publish)"** 버튼 클릭:

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    
    // 📊 점수 컬렉션 - 모든 사용자가 읽기/쓰기 가능
    match /scores/{scoreId} {
      allow read: if true;
      allow write: if true;
    }
    
    // 📈 통계 컬렉션 - 모든 사용자가 읽기/쓰기 가능
    match /stats/{statId} {
      allow read: if true;
      allow write: if true;
    }
  }
}
```

### 5단계: 게임 테스트
1. 브라우저를 새로고침 (Ctrl+Shift+R 또는 F5)
2. 게임을 플레이하고 게임 오버 화면 확인
3. 글로벌 통계가 정상적으로 표시되는지 확인:
   - 🏆 글로벌 순위
   - 📊 상위 몇 %
   - 📈 오늘 플레이 숫자
   - 📊 누적 플레이 숫자

## 🔒 보안 참고사항

**현재 규칙 (개발/테스트용)**:
- ✅ 빠른 개발과 테스트에 적합
- ⚠️ 모든 사용자가 데이터를 읽고 쓸 수 있음

**프로덕션 배포 시 권장 규칙**:
```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    
    // 점수는 모두 읽기 가능, 인증된 사용자만 쓰기
    match /scores/{scoreId} {
      allow read: if true;
      allow create: if request.auth != null;
      allow update, delete: if request.auth != null && 
                              request.auth.uid == resource.data.user_id;
    }
    
    // 통계는 읽기만 가능
    match /stats/{statId} {
      allow read: if true;
      allow write: if false; // Cloud Functions로만 업데이트
    }
  }
}
```

## 문제 해결

### Firebase 초기화 오류가 계속되면:
1. 브라우저 콘솔 확인 (F12 → Console 탭)
2. Firebase 관련 오류 메시지 확인
3. API 키가 정확한지 확인 (main.dart 31-42번째 줄)

### 데이터가 저장되지 않으면:
1. Firebase Console → Firestore Database → 데이터 탭에서 컬렉션 확인
2. `scores` 및 `stats` 컬렉션이 생성되었는지 확인
3. 브라우저 콘솔에서 "🔥 Saving score to Firebase..." 로그 확인

## 추가 도움말

**Firebase 프로젝트 URL**: https://console.firebase.google.com/project/moonlight-delivery-luna

게임 URL: https://5060-i5giwy62dl654cnerxavj-c07dda5e.sandbox.novita.ai

---
*생성 일시: 2025-10-28*
*프로젝트: 달빛 배달부 루나 (Moonlight Delivery Luna)*

#!/usr/bin/env python3
"""
Firebase Firestore 보안 규칙 설정 스크립트
Permission Denied 에러를 해결하기 위해 개발 모드 규칙 적용
"""

import json
import subprocess
import sys

def set_firestore_rules():
    """Firestore 보안 규칙을 개발 모드로 설정"""
    
    # 개발 모드 보안 규칙 (모든 읽기/쓰기 허용)
    rules = """rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    // 모든 컬렉션에 대해 읽기/쓰기 허용 (개발 모드)
    match /{document=**} {
      allow read, write: if true;
    }
  }
}"""
    
    print("=" * 60)
    print("🔥 Firebase Firestore 보안 규칙 설정")
    print("=" * 60)
    print()
    print("📋 다음 규칙을 Firebase Console에서 설정해주세요:")
    print()
    print(rules)
    print()
    print("=" * 60)
    print("📍 설정 방법:")
    print("=" * 60)
    print("1. Firebase Console 접속: https://console.firebase.google.com/")
    print("2. 프로젝트 선택")
    print("3. 왼쪽 메뉴에서 'Firestore Database' 클릭")
    print("4. 상단 탭에서 '규칙(Rules)' 클릭")
    print("5. 위의 규칙을 복사해서 붙여넣기")
    print("6. '게시(Publish)' 버튼 클릭")
    print()
    print("✅ 규칙 적용 후 게임을 다시 시작해주세요!")
    print("=" * 60)
    
    # firestore.rules 파일로 저장
    with open('/home/user/flutter_app/firestore.rules', 'w') as f:
        f.write(rules)
    
    print()
    print("💾 규칙이 firestore.rules 파일로 저장되었습니다.")
    print()

if __name__ == "__main__":
    set_firestore_rules()

// 🔥 Firebase JS Stub for non-web platforms (Android, iOS)
// This file provides empty implementations for platforms that don't support web APIs

/// Stub: Firebase는 웹이 아닌 플랫폼에서는 사용하지 않음
bool isFirebaseInitialized() => false;

/// Stub: 점수 추가 (아무 작업도 하지 않음)
Future<void> addScore({
  required String playerId,
  required String playerName,
  required int score,
  required int candies,
  required int monstersKilled,
  required String date,
}) async {
  // Android/iOS에서는 Firebase 사용 안함
}

/// Stub: 통계 증가 (아무 작업도 하지 않음)
Future<void> incrementStat({
  required String docPath,
  required Map<String, dynamic> data,
}) async {
  // Android/iOS에서는 Firebase 사용 안함
}

/// Stub: TOP 점수 조회 (빈 리스트 반환)
Future<List<Map<String, dynamic>>> getTopScores({int limit = 10}) async {
  return [];
}

/// Stub: 글로벌 통계 조회 (빈 데이터 반환)
Future<Map<String, dynamic>> getGlobalStats({required int myBestScore}) async {
  return {
    'my_rank': 0,
    'total_players': 0,
    'top_percentage': 0,
    'today_players': 0,
  };
}

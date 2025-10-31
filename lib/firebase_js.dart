// 🔥 JavaScript Firebase SDK interop for Flutter Web
// This file provides Dart bindings to JavaScript Firebase SDK

import 'dart:js_interop';
import 'dart:js_util' as js_util;

/// JavaScript Firebase 초기화 상태 확인
bool isFirebaseInitialized() {
  try {
    final firebase = js_util.getProperty(js_util.globalThis, 'firebase');
    if (firebase == null) return false;
    
    final apps = js_util.getProperty(firebase, 'apps');
    return apps != null && js_util.getProperty(apps, 'length') > 0;
  } catch (e) {
    print('⚠️ Firebase check error: $e');
    return false;
  }
}

/// Firestore에 점수 추가 (확장 가능한 시스템)
Future<void> addScore({
  required String playerId,
  required String playerName,
  required int score,
  required int candies,
  required int monstersKilled,
  required String date,
}) async {
  try {
    final firebase = js_util.getProperty(js_util.globalThis, 'firebase');
    final firestore = js_util.callMethod(firebase, 'firestore', []);
    
    // FieldValue 준비
    final firestoreClass = js_util.getProperty(firebase, 'firestore');
    final fieldValue = js_util.getProperty(firestoreClass, 'FieldValue');
    final serverTimestamp = js_util.callMethod(fieldValue, 'serverTimestamp', []);
    
    // 1️⃣ scores 컬렉션에 모든 게임 기록 저장 (히스토리용)
    final scoresCollection = js_util.callMethod(firestore, 'collection', ['scores']);
    final scoreData = js_util.jsify({
      'player_id': playerId,
      'player_name': playerName,
      'score': score,
      'candies': candies,
      'monsters_killed': monstersKilled,
      'timestamp': serverTimestamp,
      'date': date,
    });
    
    await js_util.promiseToFuture(
      js_util.callMethod(scoresCollection, 'add', [scoreData])
    );
    print('🔥 Score added to Firebase');
    
    // 2️⃣ players 컬렉션에서 플레이어의 최고 점수 업데이트 (리더보드용)
    final playerDoc = js_util.callMethod(firestore, 'doc', ['players/$playerId']);
    final playerSnapshot = await js_util.promiseToFuture(
      js_util.callMethod(playerDoc, 'get', [])
    );
    
    final exists = js_util.getProperty(playerSnapshot, 'exists') as bool;
    
    if (!exists) {
      // 새로운 플레이어 - 문서 생성
      final newPlayerData = js_util.jsify({
        'player_id': playerId,
        'player_name': playerName,
        'best_score': score,
        'candies': candies,
        'monsters_killed': monstersKilled,
        'total_games': 1,
        'first_played': serverTimestamp,
        'last_played': serverTimestamp,
      });
      
      await js_util.promiseToFuture(
        js_util.callMethod(playerDoc, 'set', [newPlayerData])
      );
      print('🆕 New player created: $playerName ($score)');
      
    } else {
      // 기존 플레이어 - 최고 점수 비교 후 업데이트
      final playerData = js_util.callMethod(playerSnapshot, 'data', []);
      final currentBestScore = js_util.getProperty(playerData, 'best_score') as int? ?? 0;
      
      if (score > currentBestScore) {
        // 🏆 새로운 최고 점수!
        final updateData = js_util.jsify({
          'player_name': playerName,
          'best_score': score,
          'candies': candies,
          'monsters_killed': monstersKilled,
          'total_games': js_util.callMethod(fieldValue, 'increment', [1]),
          'last_played': serverTimestamp,
        });
        
        final mergeOption = js_util.jsify({'merge': true});
        await js_util.promiseToFuture(
          js_util.callMethod(playerDoc, 'set', [updateData, mergeOption])
        );
        print('🏆 New best score for $playerName: $currentBestScore → $score');
        
      } else {
        // 최고 점수 아님 - 게임 횟수와 마지막 플레이 시간만 업데이트
        final updateData = js_util.jsify({
          'total_games': js_util.callMethod(fieldValue, 'increment', [1]),
          'last_played': serverTimestamp,
        });
        
        final mergeOption = js_util.jsify({'merge': true});
        await js_util.promiseToFuture(
          js_util.callMethod(playerDoc, 'set', [updateData, mergeOption])
        );
        print('📊 Game count updated for $playerName (best: $currentBestScore)');
      }
    }
    
  } catch (e) {
    print('❌ Failed to add score: $e');
    rethrow;
  }
}

/// 통계 증가 (increment)
Future<void> incrementStat({
  required String docPath,
  required Map<String, dynamic> data,
}) async {
  try {
    print('🔍 incrementStat called with:');
    print('   docPath: $docPath');
    print('   data: $data');
    
    final firebase = js_util.getProperty(js_util.globalThis, 'firebase');
    final firestore = js_util.callMethod(firebase, 'firestore', []);
    final doc = js_util.callMethod(firestore, 'doc', [docPath]);
    
    // FieldValue.increment() 사용
    final firestoreClass = js_util.getProperty(firebase, 'firestore');
    final fieldValue = js_util.getProperty(firestoreClass, 'FieldValue');
    
    // 🔧 FIX: 문서 존재 여부 확인 후 초기화
    print('🔍 Checking if document exists...');
    final snapshot = await js_util.promiseToFuture(
      js_util.callMethod(doc, 'get', [])
    );
    // exists는 속성이지 메서드가 아님!
    final exists = js_util.getProperty(snapshot, 'exists') as bool;
    print('🔍 Document exists: $exists');
    
    // data의 숫자 값을 increment로 변환
    final incrementData = <String, dynamic>{};
    for (var entry in data.entries) {
      if (entry.value is int) {
        if (!exists) {
          // 🆕 문서가 없으면 초기값으로 설정
          incrementData[entry.key] = entry.value;
          print('🔍 Setting initial value: ${entry.key} = ${entry.value}');
        } else {
          // 문서가 있으면 increment 사용
          incrementData[entry.key] = js_util.callMethod(fieldValue, 'increment', [entry.value]);
          print('🔍 Incrementing: ${entry.key} by ${entry.value}');
        }
      } else {
        incrementData[entry.key] = entry.value;
        print('🔍 Setting non-int value: ${entry.key} = ${entry.value}');
      }
    }
    
    // serverTimestamp 추가 (last_updated용)
    if (docPath.contains('total')) {
      incrementData['last_updated'] = js_util.callMethod(fieldValue, 'serverTimestamp', []);
      print('🔍 Added serverTimestamp for last_updated');
    }
    
    final jsData = js_util.jsify(incrementData);
    final mergeOption = js_util.jsify({'merge': true});
    
    print('🔍 Calling Firestore set with merge...');
    await js_util.promiseToFuture(
      js_util.callMethod(doc, 'set', [jsData, mergeOption])
    );
    
    print('🔥 Stats updated: $docPath (${exists ? "incremented" : "initialized"})');
  } catch (e) {
    print('❌ Failed to update stats: $e');
    print('❌ Error type: ${e.runtimeType}');
    print('❌ Full error: ${e.toString()}');
    rethrow;
  }
}

/// TOP 점수 조회 (하이브리드 시스템 - 인덱스 없이도 작동)
Future<List<Map<String, dynamic>>> getTopScores({int limit = 10}) async {
  try {
    final firebase = js_util.getProperty(js_util.globalThis, 'firebase');
    final firestore = js_util.callMethod(firebase, 'firestore', []);
    
    // 🔄 players 컬렉션 먼저 시도 (최적화된 방식)
    try {
      final playersCollection = js_util.callMethod(firestore, 'collection', ['players']);
      var playersQuery = js_util.callMethod(playersCollection, 'orderBy', ['best_score', 'desc']);
      playersQuery = js_util.callMethod(playersQuery, 'limit', [limit]);
      
      final playersSnapshot = await js_util.promiseToFuture(
        js_util.callMethod(playersQuery, 'get', [])
      );
      
      final playersDocs = js_util.getProperty(playersSnapshot, 'docs') as List;
      
      if (playersDocs.isNotEmpty) {
        print('🔥 Loaded ${playersDocs.length} players from Firebase (optimized)');
        
        final List<Map<String, dynamic>> topScores = [];
        for (final doc in playersDocs) {
          final data = js_util.callMethod(doc, 'data', []);
          final playerName = js_util.getProperty(data, 'player_name') as String? ?? '익명';
          final bestScore = js_util.getProperty(data, 'best_score') as int? ?? 0;
          final candies = js_util.getProperty(data, 'candies') as int? ?? 0;
          
          topScores.add({
            'name': playerName,
            'score': bestScore,
            'candies': candies,
          });
        }
        
        return topScores;
      }
    } catch (indexError) {
      print('⚠️ Players collection index not ready, falling back to scores collection');
      print('⚠️ Error: $indexError');
    }
    
    // 📋 Fallback: scores 컬렉션 사용 (인덱스 필요 없음)
    final scoresCollection = js_util.callMethod(firestore, 'collection', ['scores']);
    var scoresQuery = js_util.callMethod(scoresCollection, 'orderBy', ['score', 'desc']);
    scoresQuery = js_util.callMethod(scoresQuery, 'limit', [500]); // 충분히 많이 가져오기
    
    final scoresSnapshot = await js_util.promiseToFuture(
      js_util.callMethod(scoresQuery, 'get', [])
    );
    
    final scoresDocs = js_util.getProperty(scoresSnapshot, 'docs') as List;
    print('🔥 Loaded ${scoresDocs.length} scores from Firebase (fallback mode)');
    
    final Map<String, Map<String, dynamic>> bestScores = {};
    
    for (final doc in scoresDocs) {
      final data = js_util.callMethod(doc, 'data', []);
      final playerId = js_util.getProperty(data, 'player_id') as String;
      final score = js_util.getProperty(data, 'score') as int;
      final playerName = js_util.getProperty(data, 'player_name') as String? ?? '익명';
      final candies = js_util.getProperty(data, 'candies') as int? ?? 0;
      
      if (!bestScores.containsKey(playerId) || 
          bestScores[playerId]!['score'] < score) {
        bestScores[playerId] = {
          'name': playerName,
          'score': score,
          'candies': candies,
        };
      }
    }
    
    final sortedScores = bestScores.values.toList()
      ..sort((a, b) => (b['score'] as int).compareTo(a['score'] as int));
    
    return sortedScores.take(limit).toList();
    
  } catch (e) {
    print('❌ Failed to load scores: $e');
    return [];
  }
}

/// 글로벌 통계 조회 (하이브리드 시스템)
Future<Map<String, dynamic>> getGlobalStats({required int myBestScore}) async {
  try {
    print('🔍 getGlobalStats() called from firebase_js.dart');
    final firebase = js_util.getProperty(js_util.globalThis, 'firebase');
    final firestore = js_util.callMethod(firebase, 'firestore', []);
    
    // 1. 전체 플레이어 수 (stats/total - 읽기 실패하면 -1 반환)
    int totalPlayers = -1; // -1은 "Firebase 데이터 없음" 표시
    try {
      final totalDoc = js_util.callMethod(firestore, 'doc', ['stats/total']);
      final totalSnapshot = await js_util.promiseToFuture(
        js_util.callMethod(totalDoc, 'get', [])
      );
      final totalData = js_util.callMethod(totalSnapshot, 'data', []);
      totalPlayers = totalData != null 
          ? (js_util.getProperty(totalData, 'total_players') as int? ?? -1)
          : -1;
      print('🔍 Firebase total_players: $totalPlayers');
    } catch (e) {
      print('⚠️ Failed to read stats/total: $e');
      totalPlayers = -1;
    }
    
    // 2. 오늘 플레이어 수 (읽기 실패하면 -1 반환)
    int todayPlayers = -1;
    try {
      final today = DateTime.now().toIso8601String().split('T')[0];
      final dailyDoc = js_util.callMethod(firestore, 'doc', ['stats/daily_$today']);
      final dailySnapshot = await js_util.promiseToFuture(
        js_util.callMethod(dailyDoc, 'get', [])
      );
      final dailyData = js_util.callMethod(dailySnapshot, 'data', []);
      todayPlayers = dailyData != null
          ? (js_util.getProperty(dailyData, 'players') as int? ?? -1)
          : -1;
      print('🔍 Firebase today_players: $todayPlayers');
    } catch (e) {
      print('⚠️ Failed to read daily stats: $e');
      todayPlayers = -1;
    }
    
    // 3. 내 순위 계산 (하이브리드: players 시도 후 scores로 fallback)
    int myRank = 1;
    
    try {
      // 먼저 players 컬렉션 시도
      final playersCollection = js_util.callMethod(firestore, 'collection', ['players']);
      var query = js_util.callMethod(playersCollection, 'where', ['best_score', '>', myBestScore]);
      final higherSnapshot = await js_util.promiseToFuture(
        js_util.callMethod(query, 'get', [])
      );
      final higherDocs = js_util.getProperty(higherSnapshot, 'docs') as List;
      myRank = higherDocs.length + 1;
    } catch (e) {
      // Fallback: scores 컬렉션 사용
      print('⚠️ Using scores collection for rank calculation');
      try {
        final scoresCollection = js_util.callMethod(firestore, 'collection', ['scores']);
        var query = js_util.callMethod(scoresCollection, 'where', ['score', '>', myBestScore]);
        final higherSnapshot = await js_util.promiseToFuture(
          js_util.callMethod(query, 'get', [])
        );
        final higherDocs = js_util.getProperty(higherSnapshot, 'docs') as List;
        myRank = higherDocs.length + 1;
      } catch (e2) {
        print('⚠️ Failed to calculate rank: $e2');
        myRank = -1; // 순위 계산 실패
      }
    }
    
    // 4. 상위 %
    final topPercentage = (totalPlayers > 0 && myRank > 0)
        ? ((myRank / totalPlayers) * 100).toInt() 
        : 0;
    
    print('🔍 Firebase stats result: total=$totalPlayers, today=$todayPlayers, rank=$myRank');
    
    return {
      'my_rank': myRank,
      'total_players': totalPlayers,
      'top_percentage': topPercentage,
      'today_players': todayPlayers,
    };
    
  } catch (e) {
    print('❌ Failed to load stats: $e');
    // -1 반환하여 main.dart에서 로컬 데이터 사용하도록 함
    return {
      'my_rank': -1,
      'total_players': -1,
      'top_percentage': 0,
      'today_players': -1,
    };
  }
}

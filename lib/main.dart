import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:flame/game.dart';
import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame/collisions.dart';

import 'package:audioplayers/audioplayers.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'dart:convert' show json;

// 🌐 웹 플랫폼용 SharedPreferences 플러그인 등록
import 'package:shared_preferences_web/shared_preferences_web.dart'
    if (dart.library.io) 'package:shared_preferences/shared_preferences.dart';

// 🔥 Firebase JavaScript interop (웹 전용)
import 'firebase_js.dart' if (dart.library.io) 'firebase_js_stub.dart' as firebase_js;

// 🔥 Firebase 초기화 상태 추적
bool _isFirebaseInitialized = false;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // 🌐 웹 플랫폼에서만 Firebase 및 SharedPreferences 초기화
  if (kIsWeb) {
    // 🔥 Firebase JavaScript SDK 상태 확인
    await Future.delayed(const Duration(milliseconds: 500)); // SDK 로드 대기
    _isFirebaseInitialized = firebase_js.isFirebaseInitialized();
    print('🔥 Firebase JS SDK status: $_isFirebaseInitialized');
  }
  
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Black Cat Delivery',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6B4FA0), // 보라색
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const GamePage(),
    );
  }
}

class GamePage extends StatefulWidget {
  const GamePage({super.key});

  @override
  State<GamePage> createState() => _GamePageState();
}

class _GamePageState extends State<GamePage> with WidgetsBindingObserver {
  late BlackCatDeliveryGame game;

  @override
  void initState() {
    super.initState();
    game = BlackCatDeliveryGame();
    // 🎯 앱 생명주기 관찰자 등록
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    // 🎯 앱 생명주기 관찰자 제거
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    
    // 🎵 앱이 백그라운드로 가면 음악 일시정지
    if (state == AppLifecycleState.paused || 
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      if (kDebugMode) debugPrint('🎵 App paused/inactive - Stopping all music');
      game._pauseAllMusic();
    } 
    // 🎵 앱이 포그라운드로 돌아오면 음악 재개 (게임이 진행 중일 때만)
    else if (state == AppLifecycleState.resumed) {
      if (kDebugMode) debugPrint('🎵 App resumed - Resuming music if game active');
      if (!game.gameOver && !game.isPaused) {
        game._resumeAllMusic();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: AspectRatio(
            aspectRatio: 16 / 9, // 🎮 고정 비율 16:9
            child: GameWidget(
              game: game,
              overlayBuilderMap: {
                'gameOver': (context, game) => GameOverOverlayWidget(game: game as BlackCatDeliveryGame),
                'leaderboard': (context, game) => LeaderboardOverlayWidget(game: game as BlackCatDeliveryGame),
                'nicknameInput': (context, game) => NicknameInputOverlayWidget(game: game as BlackCatDeliveryGame),
              },
            ),
          ),
        ),
      ),
    );
  }
}

class BlackCatDeliveryGame extends FlameGame
    with HasCollisionDetection, KeyboardEvents {
  // ✅ TapDetector 제거: 모든 터치는 GameUI에서 처리
  late PlayerCat player;
  late GameUI gameUI;
  late Moon moon; // 🌕 달 참조
  
  int score = 0;
  int candies = 0;
  int passedCandies = 0; // 🎯 지나간 사탕 개수 (수집 여부 무관)
  int moonFragments = 0;
  int health = 3;
  int maxHealth = 5; // ❤️ 최대 하트 5개
  double gameSpeed = 200.0;
  double baseSpeed = 200.0; // 🎯 기본 속도
  bool gameOver = false;
  bool isPaused = false; // ⏸️ 일시정지 상태
  bool showTutorial = true; // 📖 튜토리얼 표시
  bool showInstructions = true; // 📋 게임 시작 전 안내 화면
  bool isInvincible = false; // ⭐ 무적 상태
  double invincibilityTimer = 0.0; // 무적 타이머
  int lastMegaCandyAt = 0; // 🍭 마지막으로 왕사탕을 출현시킨 사탕 개수
  
  // 🎯 몬스터 처치 시스템
  int monstersKilled = 0; // 총 처치한 몬스터 수
  bool isCandyMagnetActive = false; // 사탕 자석 효과 활성화
  
  // 🍭 왕사탕 랜덤 효과 시스템
  String currentPowerUp = ''; // 현재 활성화된 파워업
  double powerUpTimer = 0.0; // 파워업 타이머
  bool isSuperJumpActive = false; // 🚀 슈퍼 점프
  bool isLightningSpeedActive = false; // ⚡ 번개 속도
  bool isStarBlessingActive = false; // 🌟 별의 축복 (무한 사탕)
  bool isRageModeActive = false; // 🔥 분노 모드
  double starBlessingTimer = 0.0; // 별의 축복 사탕 생성 타이머
  double rageModeTimer = 0.0; // 분노 모드 발사 타이머
  
  // 🎃 허수아비 보스 시스템
  bool isBossActive = false; // 보스 활성 중
  int lastBossAt = 0; // 마지막 보스 출현 사탕 개수
  
  // 🍇 너프 사탕 시스템
  String currentNerf = ''; // 현재 활성화된 너프
  double nerfTimer = 0.0; // 너프 타이머
  bool isSlowMotion = false; // 🐌 슬로우 모션
  bool isJumpReduced = false; // 🔻 점프력 감소
  bool isPowerUpBlocked = false; // 🔥 왕사탕 블록
  
  // 🏆 랭킹 시스템 (로컬 저장소)
  String? playerId; // 플레이어 고유 ID
  String playerName = '익명'; // 플레이어 닉네임
  int myBestScore = 0; // 내 최고 점수
  int myRank = 0; // 내 랭킹
  List<Map<String, dynamic>> localLeaderboard = []; // 로컬 랭킹
  bool showLeaderboard = false; // 리더보드 표시 여부
  bool showNicknameInput = false; // 닉네임 입력 화면 표시
  
  // 🎵 배경 음악 (단일 인스턴스)
  final AudioPlayer bgMusicPlayer = AudioPlayer(); // 메인 배경음악
  final AudioPlayer invincibilityMusicPlayer = AudioPlayer(); // 무적 모드 음악
  final AudioPlayer bossMusicPlayer = AudioPlayer(); // 보스 전투 음악
  
  // 🎵 효과음 풀 (동시 재생 지원 - 모바일 최적화)
  final List<AudioPlayer> jumpSoundPool = []; // 점프 효과음 풀 (3개)
  final List<AudioPlayer> candySoundPool = []; // 사탕 효과음 풀 (5개)
  final List<AudioPlayer> megaCandySoundPool = []; // 왕사탕 효과음 풀 (3개)
  final List<AudioPlayer> monsterKillSoundPool = []; // 몬스터 처치 효과음 풀 (5개)
  final List<AudioPlayer> damageSoundPool = []; // 피해 효과음 풀 (2개)
  final AudioPlayer gameOverSoundPlayer = AudioPlayer(); // 게임오버 효과음 (단일)
  
  bool musicStarted = false; // 음악 시작 여부 (사용자 인터랙션 후)
  String currentMusicMode = 'normal'; // 'normal', 'invincibility', 'boss'
  
  final random = math.Random();
  double obstacleTimer = 0;
  double obstacleInterval = 2.0;
  
  double candyTimer = 0;
  double candyInterval = 1.5;

  @override
  Color backgroundColor() => const Color(0xFF1A1333); // 어두운 보라색 배경

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    
    // 🏆 플레이어 정보 초기화
    await _initializePlayer();

    // 🎨 게임 이미지들 미리 로드 (rootBundle 사용)
    try {
      if (kDebugMode) {
        debugPrint('🔍 Pre-loading game images from rootBundle...');
      }
      
      // 고양이 이미지 로드
      final catData = await rootBundle.load('assets/images/cat.png');
      final catBytes = catData.buffer.asUint8List();
      final catCodec = await ui.instantiateImageCodec(catBytes);
      final catFrame = await catCodec.getNextFrame();
      images.add('cat', catFrame.image);
      
      // 마녀 이미지 로드
      final witchData = await rootBundle.load('assets/images/witch.png');
      final witchBytes = witchData.buffer.asUint8List();
      final witchCodec = await ui.instantiateImageCodec(witchBytes);
      final witchFrame = await witchCodec.getNextFrame();
      images.add('witch', witchFrame.image);
      
      // 🔥 불꽃 해골 이미지 로드
      final fireData = await rootBundle.load('assets/images/fire.png');
      final fireBytes = fireData.buffer.asUint8List();
      final fireCodec = await ui.instantiateImageCodec(fireBytes);
      final fireFrame = await fireCodec.getNextFrame();
      images.add('fire', fireFrame.image);
      
      // 🔥 불꽃 발사체 이미지 로드
      final fireballData = await rootBundle.load('assets/images/fireball.png');
      final fireballBytes = fireballData.buffer.asUint8List();
      final fireballCodec = await ui.instantiateImageCodec(fireballBytes);
      final fireballFrame = await fireballCodec.getNextFrame();
      images.add('fireball', fireballFrame.image);
      
      // 🍭 왕사탕 이미지 로드
      final megaCandyData = await rootBundle.load('assets/images/mega_candy.png');
      final megaCandyBytes = megaCandyData.buffer.asUint8List();
      final megaCandyCodec = await ui.instantiateImageCodec(megaCandyBytes);
      final megaCandyFrame = await megaCandyCodec.getNextFrame();
      images.add('mega_candy', megaCandyFrame.image);
      
      // 👻 유령 이미지 로드
      final ghostData = await rootBundle.load('assets/images/ghost.png');
      final ghostBytes = ghostData.buffer.asUint8List();
      final ghostCodec = await ui.instantiateImageCodec(ghostBytes);
      final ghostFrame = await ghostCodec.getNextFrame();
      images.add('ghost', ghostFrame.image);
      
      // 🎃 허수아비 보스 이미지 로드
      final scarecrowData = await rootBundle.load('assets/images/scarecrow.png');
      final scarecrowBytes = scarecrowData.buffer.asUint8List();
      final scarecrowCodec = await ui.instantiateImageCodec(scarecrowBytes);
      final scarecrowFrame = await scarecrowCodec.getNextFrame();
      images.add('scarecrow', scarecrowFrame.image);
      
      if (kDebugMode) {
        debugPrint('✅ Game images pre-loaded successfully via rootBundle!');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Failed to pre-load game images: $e');
      }
    }

    // Add background stars
    for (int i = 0; i < 50; i++) {
      add(Star(
        position: Vector2(
          random.nextDouble() * size.x,
          random.nextDouble() * size.y,
        ),
      ));
    }

    // Add moon
    moon = Moon(position: Vector2(size.x * 0.8, size.y * 0.15));
    add(moon);
    
    // 🏰 Add Halloween background buildings (촘촘하게 배치)
    for (int i = 0; i < 10; i++) {
      add(HalloweenBuilding(
        position: Vector2(i * 200.0, size.y * 0.75), // 200픽셀 간격으로 촘촘하게
        buildingType: i % 4, // 4가지 건물 타입 순환
      ));
    }
    
    // 🕯️ Add street lamps (좌우 양쪽에 고정)
    add(StreetLamp(position: Vector2(size.x * 0.15, size.y * 0.75))); // 왼쪽
    add(StreetLamp(position: Vector2(size.x * 0.85, size.y * 0.75))); // 오른쪽

    // Add ground
    add(Ground(position: Vector2(0, size.y * 0.75)));

    // Add player (지면 레벨에 배치 - 장애물과 같은 높이)
    player = PlayerCat(position: Vector2(size.x * 0.2, size.y * 0.72));
    add(player);

    // Add UI
    gameUI = GameUI();
    add(gameUI);
    
    // 📋 안내 화면 추가 (최상위 레이어)
    add(InstructionsOverlay());
    
    // 🎵 음악 설정 (사용자 인터랙션 후 재생)
    _setupBackgroundMusic();
  }
  
  Future<void> _setupBackgroundMusic() async {
    try {
      // 메인 배경음악 (신나고 박진감 있는 할로윈 음악)
      await bgMusicPlayer.setReleaseMode(ReleaseMode.loop);
      await bgMusicPlayer.setVolume(0.2); // 20% 볼륨 (낮춤)
      
      // 무적 모드 음악 (빠르고 신나는)
      await invincibilityMusicPlayer.setReleaseMode(ReleaseMode.loop);
      await invincibilityMusicPlayer.setVolume(0.25);
      
      // 보스 전투 음악 (위기감)
      await bossMusicPlayer.setReleaseMode(ReleaseMode.loop);
      await bossMusicPlayer.setVolume(0.25);
      
      // 🎯 효과음 풀 생성 (동시 재생 지원 - 모바일 최적화)
      // 📱 모바일 안정성을 위해 풀 크기 증가!
      
      // 점프 효과음 풀 (5개 → 모바일 연속 점프 지원)
      for (int i = 0; i < 5; i++) {
        final player = AudioPlayer();
        await player.setVolume(0.3);
        await player.setReleaseMode(ReleaseMode.release);
        jumpSoundPool.add(player);
      }
      
      // 사탕 효과음 풀 (8개 → 모바일 빠른 수집 지원)
      for (int i = 0; i < 8; i++) {
        final player = AudioPlayer();
        await player.setVolume(0.15);
        await player.setReleaseMode(ReleaseMode.release);
        candySoundPool.add(player);
      }
      
      // 왕사탕 효과음 풀 (5개 → 모바일 안정성 향상)
      for (int i = 0; i < 5; i++) {
        final player = AudioPlayer();
        await player.setVolume(0.4);
        await player.setReleaseMode(ReleaseMode.release);
        megaCandySoundPool.add(player);
      }
      
      // 몬스터 처치 효과음 풀 (8개 → 모바일 연속 처치 지원)
      for (int i = 0; i < 8; i++) {
        final player = AudioPlayer();
        await player.setVolume(0.35);
        await player.setReleaseMode(ReleaseMode.release);
        monsterKillSoundPool.add(player);
      }
      
      // 피해 효과음 풀 (4개 → 모바일 연속 피격 지원)
      for (int i = 0; i < 4; i++) {
        final player = AudioPlayer();
        await player.setVolume(0.5);
        await player.setReleaseMode(ReleaseMode.release);
        damageSoundPool.add(player);
      }
      
      // 게임오버 효과음 (단일)
      await gameOverSoundPlayer.setVolume(0.6);
      await gameOverSoundPlayer.setReleaseMode(ReleaseMode.release);
      
      if (kDebugMode) debugPrint('🎵 All music & sound effect pools ready (Mobile optimized!)');
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Failed to setup music: $e');
    }
  }
  
  // 🎯 효과음 풀에서 라운드 로빈 방식으로 재생 (모바일 최적화)
  final Map<String, int> _poolIndices = {}; // 각 풀마다 독립적인 인덱스
  
  void _playFromPool(List<AudioPlayer> pool, String audioPath) {
    if (pool.isEmpty) return;
    
    try {
      // 각 풀마다 독립적인 인덱스 관리 (더 균등한 분배)
      final currentIndex = _poolIndices[audioPath] ?? 0;
      final player = pool[currentIndex % pool.length];
      _poolIndices[audioPath] = (currentIndex + 1) % pool.length;
      
      // 🚀 비동기 없이 즉시 재생 (모바일 성능 최적화)
      // stop()과 play()를 동기적으로 처리하여 대기 시간 제거
      player.stop().then((_) {
        player.play(AssetSource(audioPath)).catchError((e) {
          if (kDebugMode) debugPrint('❌ Sound play error: $e');
        });
      }).catchError((e) {
        // stop 실패 시에도 재생 시도
        player.play(AssetSource(audioPath)).catchError((e) {
          if (kDebugMode) debugPrint('❌ Sound play error: $e');
        });
      });
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Failed to play sound from pool: $e');
    }
  }
  
  Future<void> _startBackgroundMusic() async {
    if (musicStarted) return;
    
    try {
      await bgMusicPlayer.play(AssetSource('audio/halloween_upbeat_bg.mp3'));
      musicStarted = true;
      currentMusicMode = 'normal';
      if (kDebugMode) debugPrint('🎵 Upbeat Halloween background music started!');
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Failed to play music: $e');
    }
  }
  
  // 🎵 무적 모드 음악 시작
  Future<void> _startInvincibilityMusic() async {
    try {
      // 기존 음악 중지
      await bgMusicPlayer.pause();
      await bossMusicPlayer.pause();
      
      // 무적 모드 음악 재생
      await invincibilityMusicPlayer.play(AssetSource('audio/invincibility_music.mp3'));
      currentMusicMode = 'invincibility';
      
      if (kDebugMode) debugPrint('🎵 Invincibility music started!');
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Failed to play invincibility music: $e');
    }
  }
  
  // 🎵 보스 전투 음악 시작
  Future<void> _startBossMusic() async {
    try {
      // 기존 음악 중지
      await bgMusicPlayer.pause();
      await invincibilityMusicPlayer.pause();
      
      // 보스 음악 재생
      await bossMusicPlayer.play(AssetSource('audio/boss_battle_music.mp3'));
      currentMusicMode = 'boss';
      
      if (kDebugMode) debugPrint('🎵 Boss battle music started!');
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Failed to play boss music: $e');
    }
  }
  
  // 🎵 정상 배경음악으로 복귀
  Future<void> _resumeNormalMusic() async {
    try {
      // 다른 음악 중지
      await invincibilityMusicPlayer.pause();
      await bossMusicPlayer.pause();
      
      // 메인 음악 재생/재개
      if (musicStarted) {
        await bgMusicPlayer.resume();
      }
      currentMusicMode = 'normal';
      
      if (kDebugMode) debugPrint('🎵 Normal background music resumed!');
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Failed to resume normal music: $e');
    }
  }

  // 🎵 모든 음악 일시정지 (앱이 백그라운드로 갈 때)
  void _pauseAllMusic() {
    try {
      bgMusicPlayer.pause();
      invincibilityMusicPlayer.pause();
      bossMusicPlayer.pause();
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Failed to pause music: $e');
    }
  }
  
  // 🎵 음악 재개 (앱이 포그라운드로 돌아올 때)
  void _resumeAllMusic() {
    try {
      if (musicStarted && !isPaused) {
        if (currentMusicMode == 'normal') {
          bgMusicPlayer.resume();
        } else if (currentMusicMode == 'invincibility') {
          invincibilityMusicPlayer.resume();
        } else if (currentMusicMode == 'boss') {
          bossMusicPlayer.resume();
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Failed to resume music: $e');
    }
  }

  void togglePause() {
    isPaused = !isPaused;
    if (isPaused) {
      pauseEngine();
      // 모든 음악 일시정지
      _pauseAllMusic();
    } else {
      resumeEngine();
      // 현재 모드에 맞는 음악 재개
      _resumeAllMusic();
    }
  }

  @override
  void update(double dt) {
    super.update(dt);
    
    // 📋 안내 화면이 표시 중이거나 게임오버, 일시정지 상태면 게임 진행 정지
    if (showInstructions || gameOver || isPaused) return;

    // ⭐ 무적 타이머 업데이트
    if (isInvincible) {
      invincibilityTimer -= dt;
      if (invincibilityTimer <= 0) {
        isInvincible = false;
        invincibilityTimer = 0.0;
        player.isInvincible = false; // 플레이어 무적 상태도 해제
        // 🎵 무적 모드 종료 - 정상 음악으로 복귀
        _resumeNormalMusic();
        if (kDebugMode) debugPrint('⭐ Invincibility ended');
      }
    }
    
    // 🍭 파워업 타이머 업데이트
    _updatePowerUps(dt);
    
    // 🍇 너프 타이머 업데이트
    _updateNerfs(dt);

    // Update score
    score += (dt * 10).toInt();

    // 🎯 120의 배수마다 속도 10% 증가
    final speedMultiplier = 1.0 + ((passedCandies ~/ 120) * 0.1);
    gameSpeed = baseSpeed * speedMultiplier;

    // 🎃 보스 출현 체크 (지나간 사탕 50의 배수)
    if (passedCandies > 0 && passedCandies % 50 == 0 && lastBossAt != passedCandies && !isBossActive) {
      lastBossAt = passedCandies;
      spawnBoss();
      // 🎵 보스 음악 시작
      _startBossMusic();
      if (kDebugMode) debugPrint('🎃 BOSS SPAWNED at passed candy count: $passedCandies');
    }
    
    // 보스가 활성 중이면 일반 장애물 안 나옴
    if (!isBossActive) {
      // Spawn obstacles
      obstacleTimer += dt;
      if (obstacleTimer >= obstacleInterval) {
        obstacleTimer = 0;
        obstacleInterval = 1.5 + random.nextDouble() * 1.5;
        spawnObstacle();
      }

      // Spawn candies
      candyTimer += dt;
      if (candyTimer >= candyInterval) {
        candyTimer = 0;
        candyInterval = 1.0 + random.nextDouble();
        spawnCandy();
      }
    }
  }

  void spawnObstacle() {
    // 🎯 난이도 기반 장애물 선택
    // 0~5: 유령만
    // 5~15: 유령 + 보통 마녀
    // 15~30: 유령 + 다양한 속도 마녀
    // 30~60: 유령 + 마녀 + 불꽃 해골
    // 60+: 유령 + 마녀 + 불꽃 해골 + 파동 마녀
    
    if (passedCandies < 5) {
      // 0~5개: 유령만
      add(Obstacle(
        position: Vector2(size.x + 50, size.y * 0.72),
        type: 'ghost',
        speed: gameSpeed,
        groundY: size.y * 0.72,
      ));
    } else if (passedCandies < 15) {
      // 5~15개: 유령 + 보통 마녀
      if (random.nextDouble() < 0.6) {
        // 60% 유령
        add(Obstacle(
          position: Vector2(size.x + 50, size.y * 0.72),
          type: 'ghost',
          speed: gameSpeed,
          groundY: size.y * 0.72,
        ));
      } else {
        // 40% 보통 마녀
        final skyHeight = 0.30 + random.nextDouble() * 0.30;
        add(Obstacle(
          position: Vector2(size.x + 50, size.y * skyHeight),
          type: 'witch',
          speed: gameSpeed, // 보통 속도
          groundY: size.y * 0.72,
        ));
      }
    } else if (passedCandies < 30) {
      // 15~30개: 유령 + 다양한 속도 마녀
      if (random.nextDouble() < 0.5) {
        // 50% 유령
        add(Obstacle(
          position: Vector2(size.x + 50, size.y * 0.72),
          type: 'ghost',
          speed: gameSpeed,
          groundY: size.y * 0.72,
        ));
      } else {
        // 50% 다양한 속도 마녀
        final skyHeight = 0.30 + random.nextDouble() * 0.30;
        final witchType = random.nextInt(3); // 느림, 보통, 빠름
        double witchSpeed;
        
        if (witchType == 0) {
          witchSpeed = gameSpeed * 0.5; // 느림
        } else if (witchType == 1) {
          witchSpeed = gameSpeed; // 보통
        } else {
          witchSpeed = gameSpeed * 2.0; // 빠름
        }
        
        add(Obstacle(
          position: Vector2(size.x + 50, size.y * skyHeight),
          type: 'witch',
          speed: witchSpeed,
          groundY: size.y * 0.72,
        ));
      }
    } else if (passedCandies < 60) {
      // 30~60개: 유령 + 마녀 + 불꽃 해골
      final obstacleType = random.nextDouble();
      
      if (obstacleType < 0.4) {
        // 40% 유령
        add(Obstacle(
          position: Vector2(size.x + 50, size.y * 0.72),
          type: 'ghost',
          speed: gameSpeed,
          groundY: size.y * 0.72,
        ));
      } else if (obstacleType < 0.7) {
        // 30% 다양한 속도 마녀
        final skyHeight = 0.30 + random.nextDouble() * 0.30;
        final witchType = random.nextInt(3);
        double witchSpeed;
        
        if (witchType == 0) {
          witchSpeed = gameSpeed * 0.5;
        } else if (witchType == 1) {
          witchSpeed = gameSpeed;
        } else {
          witchSpeed = gameSpeed * 2.0;
        }
        
        add(Obstacle(
          position: Vector2(size.x + 50, size.y * skyHeight),
          type: 'witch',
          speed: witchSpeed,
          groundY: size.y * 0.72,
        ));
      } else {
        // 30% 불꽃 해골
        add(Obstacle(
          position: Vector2(size.x + 50, size.y * 0.72),
          type: 'fire',
          speed: gameSpeed,
          groundY: size.y * 0.72,
        ));
      }
    } else {
      // 60개 이상: 유령 + 마녀 + 불꽃 해골 + 파동 마녀
      final obstacleType = random.nextDouble();
      
      if (obstacleType < 0.3) {
        // 30% 유령
        add(Obstacle(
          position: Vector2(size.x + 50, size.y * 0.72),
          type: 'ghost',
          speed: gameSpeed,
          groundY: size.y * 0.72,
        ));
      } else if (obstacleType < 0.6) {
        // 30% 다양한 속도 마녀 (파동 포함)
        final skyHeight = 0.30 + random.nextDouble() * 0.30;
        final witchType = random.nextInt(4); // 느림, 보통, 빠름, 파동
        double witchSpeed;
        bool wavingMotion = false;
        
        if (witchType == 0) {
          witchSpeed = gameSpeed * 0.5;
        } else if (witchType == 1) {
          witchSpeed = gameSpeed;
        } else if (witchType == 2) {
          witchSpeed = gameSpeed * 2.0;
        } else {
          witchSpeed = gameSpeed;
          wavingMotion = true; // 파동 마녀!
        }
        
        add(Obstacle(
          position: Vector2(size.x + 50, size.y * skyHeight),
          type: 'witch',
          speed: witchSpeed,
          wavingMotion: wavingMotion,
          initialY: size.y * skyHeight,
          groundY: size.y * 0.72,
        ));
      } else {
        // 40% 불꽃 해골
        add(Obstacle(
          position: Vector2(size.x + 50, size.y * 0.72),
          type: 'fire',
          speed: gameSpeed,
          groundY: size.y * 0.72,
        ));
      }
    }
  }
  
  void spawnBoss() {
    isBossActive = true;
    add(ScarecrowBoss(
      position: Vector2(size.x + 150, size.y * 0.72),
      gameSpeed: gameSpeed,
    ));
    if (kDebugMode) debugPrint('🎃 Scarecrow Boss spawned!');
  }

  void spawnCandy() {
    // 🎯 지나간 사탕 개수 증가
    passedCandies++;
    
    // 🍭 사탕 20개마다 왕사탕 출현! (20, 40, 60, 80...) - 딱 1번만!
    final shouldSpawnMega = candies > 0 && candies % 20 == 0 && lastMegaCandyAt != candies;
    
    if (shouldSpawnMega) {
      lastMegaCandyAt = candies; // 이번 20의 배수에서 왕사탕 출현 기록
      add(MegaCandy(
        position: Vector2(
          size.x + 50,
          // 더 넓은 높이 범위: 0.35 ~ 0.65
          size.y * (0.35 + random.nextDouble() * 0.30),
        ),
        speed: gameSpeed * 0.7, // 왕사탕은 조금 느리게
      ));
      if (kDebugMode) debugPrint('🍭 MEGA CANDY spawned!');
    } else {
      // 🍇 보라색 너프 사탕 (3:1 비율)
      final isNerfCandy = random.nextInt(4) == 0; // 25% 확률 (4분의 1)
      
      if (isNerfCandy) {
        add(PurpleCandy(
          position: Vector2(
            size.x + 50,
            size.y * (0.35 + random.nextDouble() * 0.30),
          ),
          speed: gameSpeed,
        ));
        if (kDebugMode) debugPrint('🍇 PURPLE NERF CANDY spawned!');
      } else {
        add(Candy(
          position: Vector2(
            size.x + 50,
            // 고양이가 4중 점프로 닿을 수 있는 높이: 0.35 ~ 0.65 (더 넓은 범위!)
            size.y * (0.35 + random.nextDouble() * 0.30),
          ),
          speed: gameSpeed,
        ));
      }
    }
  }

  // ✅ 모든 터치 이벤트는 GameUI.onTapDown()에서 처리
  // onTap()을 제거하여 이벤트가 GameUI로 전달되도록 함

  @override
  KeyEventResult onKeyEvent(
    KeyEvent event,
    Set<LogicalKeyboardKey> keysPressed,
  ) {
    if (event is KeyDownEvent) {
      // 🎵 첫 번째 키 입력에서 음악 시작 (브라우저 정책)
      _startBackgroundMusic();
      
      // ⏸️ ESC 키로 일시정지/재개
      if (event.logicalKey == LogicalKeyboardKey.escape && !gameOver) {
        togglePause();
        return KeyEventResult.handled;
      }
      
      // 🔄 게임 오버 상태에서 스페이스바로 재시작 (리더보드가 열려있지 않을 때만)
      if (gameOver && event.logicalKey == LogicalKeyboardKey.space && 
          !showLeaderboard && !showNicknameInput) {
        if (kDebugMode) debugPrint('🔄 Restarting game from keyboard');
        resetGame();
        return KeyEventResult.handled;
      }
      
      // 🔄 스페이스바로 일시정지/재개 (게임 오버가 아닐 때)
      if (!gameOver && event.logicalKey == LogicalKeyboardKey.space) {
        togglePause();
        return KeyEventResult.handled;
      }

      // 게임 진행 중 조작 (일시정지 중이 아닐 때만)
      if (!gameOver && !isPaused) {
        // 튜토리얼 닫기
        if (showTutorial) {
          showTutorial = false;
        }
        
        if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
          player.jump();
          return KeyEventResult.handled;
        } else if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
          player.fastFall();
          return KeyEventResult.handled;
        } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
          player.moveLeft();
          return KeyEventResult.handled;
        } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
          player.moveRight();
          return KeyEventResult.handled;
        }
      }
    }

    return KeyEventResult.ignored;
  }

  void collectCandy() {
    candies++;
    score += 10;
    
    // 🎵 사탕 먹기 효과음 (풀에서 재생 - 동시 재생 지원)
    _playFromPool(candySoundPool, 'audio/candy_collect.mp3');
    
    // ❤️ 사탕 20개마다 하트 추가 (최대 5개)
    if (candies % 20 == 0 && health < maxHealth) {
      health++;
      
      // 🎵 하트 획득 효과음 (왕사탕 효과음 재사용 - 풀에서 재생)
      _playFromPool(megaCandySoundPool, 'audio/mega_candy_powerup.mp3');
      
      // 🌕 달이 크고 환하게 빛나는 이펙트!
      moon.triggerGlow();
      
      // 🐱 고양이도 동시에 반짝이는 이펙트!
      player.triggerHeartGlow();
      
      if (kDebugMode) {
        debugPrint('❤️ Heart gained! Health: $health/$maxHealth');
        debugPrint('🌕 Moon glows brightly!');
        debugPrint('🐱 Cat sparkles too!');
      }
    }
  }
  
  void collectMegaCandy() {
    score += 100; // 왕사탕은 100점!
    
    if (kDebugMode) debugPrint('🍭 Mega Candy collected! Score +100');
    
    // 🎵 왕사탕 효과음 (풀에서 재생 - 동시 재생 지원)
    _playFromPool(megaCandySoundPool, 'audio/mega_candy_powerup.mp3');
    
    // 🚫 왕사탕 무효화 중이면 파워업 발동 안됨!
    if (isPowerUpBlocked) {
      if (kDebugMode) debugPrint('🚫 Power-up BLOCKED! Mega candy has no effect. (isPowerUpBlocked: $isPowerUpBlocked)');
      
      // 🚫 왕사탕 무효화 시각적 피드백 (X 표시 효과)
      add(BlockedPowerUpEffect(position: player.position.clone()));
      
      return;
    }
    
    if (kDebugMode) debugPrint('🍭 Activating random power-up...');
    
    // 🍭 랜덤 파워업 효과 발동!
    _activateRandomPowerUp();
  }

  void collectMoonFragment() {
    moonFragments++;
    score += 50;
  }
  
  // 🎯 몬스터 처치 (점프 공격 성공 시 호출)
  void killMonster({bool isBoss = false}) {
    monstersKilled++;
    
    // 보스는 100점, 일반 몬스터는 10점
    final points = isBoss ? 100 : 10;
    score += points;
    
    if (kDebugMode) {
      debugPrint('🎯 ${isBoss ? "BOSS" : "Monster"} killed! Total: $monstersKilled, Score +$points');
    }
  }
  
  // 🍭 랜덤 파워업 효과 활성화
  void _activateRandomPowerUp() {
    // 5가지 랜덤 효과 중 하나 선택
    final effects = ['invincible', 'magnet', 'super_jump', 'lightning', 'star_blessing', 'rage_mode'];
    final selectedEffect = effects[random.nextInt(effects.length)];
    
    currentPowerUp = selectedEffect;
    
    switch (selectedEffect) {
      case 'invincible':
        _activateInvincibility();
        break;
      case 'magnet':
        _activateCandyMagnet();
        break;
      case 'super_jump':
        _activateSuperJump();
        break;
      case 'lightning':
        _activateLightningSpeed();
        break;
      case 'star_blessing':
        _activateStarBlessing();
        break;
      case 'rage_mode':
        _activateRageMode();
        break;
    }
  }
  
  // 파워업 타이머 업데이트
  void _updatePowerUps(double dt) {
    // 파워업 타이머 감소
    if (powerUpTimer > 0) {
      powerUpTimer -= dt;
      
      if (powerUpTimer <= 0) {
        _deactivatePowerUp();
      }
    }
    
    // 🌟 별의 축복 - 지속적인 사탕 생성
    if (isStarBlessingActive) {
      starBlessingTimer += dt;
      if (starBlessingTimer >= 0.3) { // 0.3초마다 사탕 생성
        starBlessingTimer = 0.0;
        _spawnBonusCandy();
      }
    }
    
    // 🔥 분노 모드 - 자동 불꽃 발사
    if (isRageModeActive) {
      rageModeTimer += dt;
      if (rageModeTimer >= 0.5) { // 0.5초마다 불꽃 발사
        rageModeTimer = 0.0;
        _shootPlayerFireball();
      }
    }
  }
  
  // ⭐ 무적 모드
  void _activateInvincibility() {
    isInvincible = true;
    invincibilityTimer = 10.0; // invincibilityTimer도 설정!
    powerUpTimer = 10.0;
    player.activateInvincibility();
    _startInvincibilityMusic();
    
    if (kDebugMode) {
      debugPrint('⭐ INVINCIBILITY activated! (10s)');
      debugPrint('   game.isInvincible: $isInvincible');
      debugPrint('   player.isInvincible: ${player.isInvincible}');
      debugPrint('   invincibilityTimer: $invincibilityTimer');
    }
  }
  
  // 🧲 사탕 자석
  void _activateCandyMagnet() {
    isCandyMagnetActive = true;
    
    // 화면의 모든 좋은 사탕만 고양이 쪽으로 끌어당김
    children.whereType<Candy>().forEach((candy) {
      candy.attractToPlayer(player.position);
    });
    
    children.whereType<MegaCandy>().forEach((megaCandy) {
      megaCandy.attractToPlayer(player.position);
    });
    
    // 🚫 보라색 사탕(디버프)은 자석 효과에서 제외!
    // 자석은 좋은 사탕만 끌어당기므로 디버프 캔디는 무시
    if (kDebugMode) debugPrint('🧲 Candy magnet ignores purple debuff candies');
    
    // 자석 효과 종료 (1초 후)
    Future.delayed(const Duration(seconds: 1), () {
      isCandyMagnetActive = false;
      if (kDebugMode) debugPrint('🧲 Candy magnet deactivated');
    });
    
    if (kDebugMode) debugPrint('🧲 CANDY MAGNET activated! (1s) - Only good candies!');
  }
  
  // 🚀 슈퍼 점프
  void _activateSuperJump() {
    isSuperJumpActive = true;
    powerUpTimer = 10.0;
    
    if (kDebugMode) debugPrint('🚀 SUPER JUMP activated! 2x jump power + 8 jumps! (10s)');
  }
  
  // ⚡ 번개 속도
  void _activateLightningSpeed() {
    isLightningSpeedActive = true;
    powerUpTimer = 10.0;
    
    if (kDebugMode) debugPrint('⚡ LIGHTNING SPEED activated! 5x speed! (10s)');
  }
  
  // 🌟 별의 축복 (무한 사탕)
  void _activateStarBlessing() {
    isStarBlessingActive = true;
    powerUpTimer = 5.0; // 5초만 지속 (너무 강력해서)
    starBlessingTimer = 0.0;
    
    if (kDebugMode) debugPrint('🌟 STAR BLESSING activated! Infinite candies! (5s)');
  }
  
  // 🔥 분노 모드 (자동 공격)
  void _activateRageMode() {
    isRageModeActive = true;
    powerUpTimer = 10.0;
    rageModeTimer = 0.0;
    
    if (kDebugMode) debugPrint('🔥 RAGE MODE activated! Auto-attack fireballs! (10s)');
  }
  
  // 파워업 효과 종료
  void _deactivatePowerUp() {
    // 개별 효과 종료
    if (isInvincible) {
      isInvincible = false;
      invincibilityTimer = 0.0; // 타이머도 초기화
      player.isInvincible = false; // 플레이어 무적 상태도 해제
      _resumeNormalMusic();
      if (kDebugMode) debugPrint('⭐ Invincibility ended');
    }
    
    if (isSuperJumpActive) {
      isSuperJumpActive = false;
      if (kDebugMode) debugPrint('🚀 Super Jump ended');
    }
    
    if (isLightningSpeedActive) {
      isLightningSpeedActive = false;
      if (kDebugMode) debugPrint('⚡ Lightning Speed ended');
    }
    
    if (isStarBlessingActive) {
      isStarBlessingActive = false;
      if (kDebugMode) debugPrint('🌟 Star Blessing ended');
    }
    
    if (isRageModeActive) {
      isRageModeActive = false;
      if (kDebugMode) debugPrint('🔥 Rage Mode ended');
    }
    
    powerUpTimer = 0.0;
    currentPowerUp = '';
  }
  
  // 🌟 보너스 사탕 생성 (별의 축복)
  void _spawnBonusCandy() {
    add(Candy(
      position: Vector2(
        size.x + 50,
        size.y * (0.35 + random.nextDouble() * 0.30),
      ),
      speed: gameSpeed,
    ));
  }
  
  // 🔥 플레이어 불꽃탄 발사 (분노 모드)
  void _shootPlayerFireball() {
    add(PlayerFireball(
      position: player.position.clone() + Vector2(60, 0),
      speed: 600.0,
    ));
  }
  
  // 🍇 보라색 너프 사탕 수집
  void collectPurpleCandy() {
    // 점수는 그대로 획득
    score += 10;
    
    // 랜덤 너프 효과 발동!
    _activateRandomNerf();
  }
  
  // 🍇 랜덤 너프 효과 활성화
  void _activateRandomNerf() {
    // 3가지 랜덤 너프 중 하나 선택
    final nerfs = ['slow_motion', 'jump_reduced', 'powerup_blocked'];
    final selectedNerf = nerfs[random.nextInt(nerfs.length)];
    
    currentNerf = selectedNerf;
    
    switch (selectedNerf) {
      case 'slow_motion':
        _activateSlowMotion();
        break;
      case 'jump_reduced':
        _activateJumpReduced();
        break;
      case 'powerup_blocked':
        _activatePowerUpBlocked();
        break;
    }
  }
  
  // 🐌 슬로우 모션 (7초)
  void _activateSlowMotion() {
    isSlowMotion = true;
    nerfTimer = 7.0;
    
    if (kDebugMode) debugPrint('🐌 SLOW MOTION activated! Speed reduced 50% (7s)');
  }
  
  // 🔻 점프력 감소 (8초)
  void _activateJumpReduced() {
    isJumpReduced = true;
    nerfTimer = 8.0;
    
    if (kDebugMode) debugPrint('🔻 JUMP REDUCED activated! Jump power 60% (8s)');
  }
  
  // 🚫 왕사탕 무효화 (10초)
  void _activatePowerUpBlocked() {
    isPowerUpBlocked = true;
    nerfTimer = 10.0;
    
    if (kDebugMode) debugPrint('🚫 POWERUP BLOCKED activated! Mega candies won\'t work for 10s');
  }
  
  // 너프 타이머 업데이트
  void _updateNerfs(double dt) {
    // 너프 타이머 감소
    if (nerfTimer > 0) {
      nerfTimer -= dt;
      
      if (nerfTimer <= 0) {
        _deactivateNerf();
      }
    }
  }
  
  // 너프 효과 종료
  void _deactivateNerf() {
    // 개별 효과 종료
    if (isSlowMotion) {
      isSlowMotion = false;
      if (kDebugMode) debugPrint('🐌 Slow Motion ended');
    }
    
    if (isJumpReduced) {
      isJumpReduced = false;
      if (kDebugMode) debugPrint('🔻 Jump Reduced ended');
    }
    
    if (isPowerUpBlocked) {
      isPowerUpBlocked = false;
      if (kDebugMode) debugPrint('🚫 PowerUp Block ended');
    }
    
    nerfTimer = 0.0;
    currentNerf = '';
  }

  // 🏆 플레이어 정보 초기화
  Future<void> _initializePlayer() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // 플레이어 ID 로드 또는 생성
      playerId = prefs.getString('player_id');
      if (playerId == null) {
        playerId = DateTime.now().millisecondsSinceEpoch.toString();
        await prefs.setString('player_id', playerId!);
        if (kDebugMode) debugPrint('🆔 New player ID created: $playerId');
      }
      
      // 닉네임 로드
      playerName = prefs.getString('player_name') ?? '익명';
      if (kDebugMode) debugPrint('👤 Player name loaded: $playerName');
      
      // 최고 점수 로드
      await _loadBestScore();
      
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Failed to initialize player: $e');
    }
  }
  
  // 🏆 내 최고 점수 로드 (로컬)
  Future<void> _loadBestScore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      myBestScore = prefs.getInt('best_score') ?? 0;
      
      // 로컬 랭킹 로드
      await _loadLocalLeaderboard();
      
      if (kDebugMode) debugPrint('🏆 Best score loaded: $myBestScore');
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Failed to load best score: $e');
    }
  }
  
  // 🏆 로컬 저장소에 점수 저장
  Future<void> _saveScoreToLeaderboard() async {
    try {
      print('💾 _saveScoreToLeaderboard() STARTED - Score: $score, Player: $playerName');
      
      final prefs = await SharedPreferences.getInstance();
      final playTime = (score / 10).toInt();
      
      print('💾 Creating leaderboard entry...');
      
      // 로컬 랭킹에 추가
      localLeaderboard.add({
        'player_id': playerId,
        'player_name': playerName,
        'score': score,
        'monsters_killed': monstersKilled,
        'candies_collected': candies,
        'play_date': DateTime.now().millisecondsSinceEpoch,
        'survived_seconds': playTime,
      });
      
      print('💾 Entry added to localLeaderboard. Total entries: ${localLeaderboard.length}');
      
      // 점수순 정렬
      localLeaderboard.sort((a, b) => (b['score'] as int).compareTo(a['score'] as int));
      
      // 상위 100개만 유지
      if (localLeaderboard.length > 100) {
        localLeaderboard = localLeaderboard.take(100).toList();
      }
      
      print('💾 Saving to SharedPreferences...');
      
      // SharedPreferences에 저장
      await _saveLocalLeaderboard();
      
      print('💾 SharedPreferences save complete!');
      
      // 최고 점수 업데이트
      if (score > myBestScore) {
        myBestScore = score;
        await prefs.setInt('best_score', myBestScore);
        print('💾 Best score updated: $myBestScore');
      }
      
      // 내 랭킹 계산
      await _calculateMyRank();
      
      print('🏆 Score saved successfully! Total entries: ${localLeaderboard.length}');
      
      // 🔥 Firebase 글로벌 리더보드에도 저장
      await _saveScoreToFirebase();
      
      if (kDebugMode) {
        debugPrint('🏆 Score saved to local leaderboard: $score');
      }
      
    } catch (e, stackTrace) {
      print('❌ CRITICAL ERROR in _saveScoreToLeaderboard: $e');
      print('❌ Stack trace: $stackTrace');
      if (kDebugMode) {
        debugPrint('❌ Failed to save score: $e');
      }
    }
  }
  
  // 🔥 Firebase 글로벌 리더보드에 점수 저장
  Future<void> _saveScoreToFirebase() async {
    try {
      // Firebase가 초기화되지 않았으면 건너뛰기
      if (!_isFirebaseInitialized) {
        print('⚠️ Firebase not initialized, skipping save');
        return;
      }
      
      print('🔥 Saving score to Firebase...');
      
      if (kIsWeb) {
        // 🌐 웹에서는 JavaScript Firebase SDK 사용
        final today = DateTime.now().toIso8601String().split('T')[0];
        
        // 1. 점수 저장
        await firebase_js.addScore(
          playerId: playerId!,
          playerName: playerName,
          score: score,
          candies: candies,
          monstersKilled: monstersKilled,
          date: today,
        );
        
        // 2. 일일 통계 증가
        print('📊 Incrementing daily stats for: stats/daily_$today');
        await firebase_js.incrementStat(
          docPath: 'stats/daily_$today',
          data: {
            'date': today,
            'players': 1, // JavaScript에서 increment 처리
          },
        );
        print('✅ Daily stats incremented successfully');
        
        // 3. 전체 통계 증가
        print('📊 Incrementing total stats for: stats/total');
        await firebase_js.incrementStat(
          docPath: 'stats/total',
          data: {
            'total_players': 1, // JavaScript에서 increment 처리
          },
        );
        print('✅ Total stats incremented successfully');
        
        print('🔥 Firebase save complete!');
      }
      
    } catch (e, stackTrace) {
      print('❌ Firebase save failed: $e');
      print('❌ Stack trace: $stackTrace');
      // Firebase 에러는 무시하고 계속 진행 (로컬 저장은 이미 완료됨)
    }
  }
  
  // 🏆 내 랭킹 계산 (로컬)
  Future<void> _calculateMyRank() async {
    try {
      // 플레이어별 최고 점수만 추출
      final Map<String, int> playerBestScores = {};
      
      for (var entry in localLeaderboard) {
        final pid = entry['player_id'] as String;
        final sc = entry['score'] as int;
        
        if (!playerBestScores.containsKey(pid) || playerBestScores[pid]! < sc) {
          playerBestScores[pid] = sc;
        }
      }
      
      // 내 점수보다 높은 플레이어 수 세기
      int higherPlayers = 0;
      for (var score in playerBestScores.values) {
        if (score > myBestScore) {
          higherPlayers++;
        }
      }
      
      myRank = higherPlayers + 1;
      if (kDebugMode) debugPrint('🏆 My rank: #$myRank');
      
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Failed to calculate rank: $e');
    }
  }
  
  // 🏆 로컬 랭킹 로드
  Future<void> _loadLocalLeaderboard() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? data = prefs.getString('local_leaderboard');
      
      if (data != null && data.isNotEmpty) {
        // JSON 문자열을 리스트로 변환
        final List<dynamic> decoded = json.decode(data);
        localLeaderboard = decoded.map((item) => Map<String, dynamic>.from(item)).toList();
        print('🏆 Local leaderboard loaded: ${localLeaderboard.length} entries');
      } else {
        localLeaderboard = [];
        print('🏆 No saved leaderboard data found - starting fresh');
      }
      
      if (kDebugMode) debugPrint('🏆 Local leaderboard loaded: ${localLeaderboard.length} entries');
    } catch (e) {
      localLeaderboard = [];
      print('❌ Failed to load local leaderboard: $e');
      if (kDebugMode) debugPrint('❌ Failed to load local leaderboard: $e');
    }
  }
  
  // 🏆 로컬 랭킹 저장
  Future<void> _saveLocalLeaderboard() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // 리스트를 JSON 문자열로 변환
      final String encoded = json.encode(localLeaderboard);
      
      // SharedPreferences에 저장
      await prefs.setString('local_leaderboard', encoded);
      
      print('💾 Local leaderboard saved: ${localLeaderboard.length} entries');
      if (kDebugMode) debugPrint('🏆 Local leaderboard saved: ${localLeaderboard.length} entries');
    } catch (e) {
      print('❌ Failed to save local leaderboard: $e');
      if (kDebugMode) debugPrint('❌ Failed to save local leaderboard: $e');
    }
  }
  
  // 🔥 Firebase 글로벌 리더보드 조회
  Future<List<Map<String, dynamic>>> getTopScores({int limit = 10}) async {
    try {
      print('🔥 getTopScores() called - Firebase initialized: $_isFirebaseInitialized');
      
      // Firebase가 초기화되지 않았으면 로컬 데이터 사용
      if (!_isFirebaseInitialized) {
        print('⚠️ Firebase not initialized, using local leaderboard');
        final localScores = await _getLocalTopScores(limit: limit);
        print('📋 Local leaderboard: ${localScores.length} entries');
        return localScores;
      }
      
      print('🔥 Loading global leaderboard from Firebase...');
      
      if (kIsWeb) {
        // 🌐 웹에서는 JavaScript Firebase SDK 사용
        return await firebase_js.getTopScores(limit: limit);
      }
      
      // 다른 플랫폼에서는 로컬 사용
      return _getLocalTopScores(limit: limit);
      
    } catch (e, stackTrace) {
      print('❌ Firebase leaderboard load failed: $e');
      print('❌ Stack trace: $stackTrace');
      // Firebase 실패 시 로컬 데이터 사용
      return _getLocalTopScores(limit: limit);
    }
  }
  
  // 🏆 로컬 TOP 10 랭킹 조회 (Firebase 실패 시 백업)
  Future<List<Map<String, dynamic>>> _getLocalTopScores({int limit = 10}) async {
    try {
      // 플레이어별 최고 점수만 추출
      final Map<String, Map<String, dynamic>> bestScores = {};
      
      for (var entry in localLeaderboard) {
        final playerId = entry['player_id'] as String;
        final score = entry['score'] as int;
        
        if (!bestScores.containsKey(playerId) || 
            bestScores[playerId]!['score'] < score) {
          bestScores[playerId] = {
            'name': entry['player_name'], // 🔥 필드명 수정: player_name → name
            'score': score,
            'monsters_killed': entry['monsters_killed'],
            'candies': entry['candies_collected'], // 🔥 필드명 수정: candies_collected → candies
          };
        }
      }
      
      // 정렬 및 상위 N개만 반환
      final sortedScores = bestScores.values.toList()
        ..sort((a, b) => (b['score'] as int).compareTo(a['score'] as int));
      
      return sortedScores.take(limit).toList();
      
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Failed to load leaderboard: $e');
      return [];
    }
  }
  
  // 🔥 글로벌 통계 조회 (순위, 상위 %, 방문자 수)
  Future<Map<String, dynamic>> getGlobalStats() async {
    try {
      // Firebase가 초기화되지 않았으면 로컬 데이터 사용
      if (!_isFirebaseInitialized) {
        print('⚠️ Firebase not initialized, using local stats');
        return _calculateLocalStats();
      }
      
      print('🔥 Loading global stats from Firebase...');
      
      if (kIsWeb) {
        try {
          // 🌐 웹에서는 JavaScript Firebase SDK 사용
          final stats = await firebase_js.getGlobalStats(myBestScore: myBestScore);
          
          print('🔍 Firebase stats received: $stats');
          
          // Firebase에서 유효하지 않은 데이터(-1, 0) 반환 시 로컬 데이터 사용
          final totalPlayers = stats['total_players'] as int? ?? -1;
          final todayPlayers = stats['today_players'] as int? ?? -1;
          
          // 🌍 항상 Firebase 글로벌 통계 사용 (모든 디바이스에서 동일한 통계)
          if (totalPlayers > 0 || todayPlayers >= 0) {
            print('✅ Using Firebase global stats - Total: $totalPlayers, Today: $todayPlayers');
            return stats;
          } else {
            print('⚠️ Firebase returned no data, using local stats as fallback');
            return _calculateLocalStats();
          }
        } catch (e) {
          print('❌ Firebase error: $e - Using local stats instead');
          return _calculateLocalStats();
        }
      }
      
      // 다른 플랫폼에서는 로컬 데이터 사용
      return _calculateLocalStats();
      
    } catch (e, stackTrace) {
      print('❌ Stats load failed: $e');
      print('❌ Stack trace: $stackTrace');
      
      // 에러 시 로컬 데이터 사용
      return _calculateLocalStats();
    }
  }
  
  // 📊 로컬 리더보드 기반 통계 계산
  Map<String, dynamic> _calculateLocalStats() {
    try {
      print('📊 _calculateLocalStats() called');
      print('   localLeaderboard.length: ${localLeaderboard.length}');
      
      // 누적 플레이 수 = 전체 기록 수
      final totalPlayers = localLeaderboard.length;
      
      // 오늘 플레이 수 = 오늘 날짜로 저장된 기록 수
      final now = DateTime.now();
      print('   Current DateTime: $now');
      print('   Year: ${now.year}, Month: ${now.month}, Day: ${now.day}');
      
      final todayStart = DateTime(now.year, now.month, now.day);
      final todayStartMs = todayStart.millisecondsSinceEpoch;
      
      print('   Today start: $todayStart');
      print('   Today start ms: $todayStartMs');
      
      int todayPlayers = 0;
      for (final entry in localLeaderboard) {
        // play_date는 밀리초 타임스탬프
        final playDate = entry['play_date'] as int? ?? 0;
        final playDateTime = DateTime.fromMillisecondsSinceEpoch(playDate);
        
        print('   Entry play_date: $playDate -> $playDateTime');
        
        if (playDate >= todayStartMs) {
          todayPlayers++;
        }
      }
      
      print('   Today players count: $todayPlayers');
      
      // 내 순위 계산 (최고 점수 기준)
      int myRank = 1;
      for (final entry in localLeaderboard) {
        final entryScore = entry['score'] as int? ?? 0;
        if (entryScore > myBestScore) {
          myRank++;
        }
      }
      
      // 상위 퍼센트
      final topPercentage = totalPlayers > 0 
          ? ((myRank / totalPlayers) * 100).toInt() 
          : 0;
      
      print('📊 Local stats calculated:');
      print('   Total players: $totalPlayers (전체 기록 수)');
      print('   Today players: $todayPlayers (오늘 기록 수)');
      print('   My rank: $myRank');
      print('   Top percentage: $topPercentage%');
      
      return {
        'my_rank': myRank,
        'total_players': totalPlayers,
        'top_percentage': topPercentage,
        'today_players': todayPlayers,
      };
    } catch (e) {
      print('❌ Failed to calculate local stats: $e');
      return {
        'my_rank': 0,
        'total_players': 0,
        'top_percentage': 0,
        'today_players': 0,
      };
    }
  }
  
  // 👤 닉네임 저장
  Future<void> saveNickname(String nickname) async {
    try {
      print('👤 saveNickname() CALLED - New name: $nickname, Old name: $playerName');
      
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('player_name', nickname);
      playerName = nickname;
      
      print('👤 Nickname saved successfully: $nickname');
      
      if (kDebugMode) debugPrint('👤 Nickname saved: $nickname');
    } catch (e, stackTrace) {
      print('❌ CRITICAL ERROR in saveNickname: $e');
      print('❌ Stack trace: $stackTrace');
      if (kDebugMode) debugPrint('❌ Failed to save nickname: $e');
    }
  }

  void takeDamage() {
    // 🚨 CRITICAL: 게임 오버 상태면 데미지 무시!
    if (gameOver) {
      print('⚠️ takeDamage() ignored - game is already over');
      return;
    }
    
    // ⭐ 무적 상태면 데미지 무시 (왕사탕 무적)
    if (isInvincible) {
      if (kDebugMode) debugPrint('⭐ Damage ignored - Invincible!');
      return;
    }
    
    // 🛡️ 피격 후 무적 시간 동안 데미지 무시
    if (player.isHitInvincible) {
      if (kDebugMode) debugPrint('🛡️ Damage ignored - Hit invincibility!');
      return;
    }
    
    health--;
    print('💔 takeDamage() - health: $health');
    
    // 🎵 피해 효과음 재생 (풀에서 재생 - 동시 피격 지원)
    _playFromPool(damageSoundPool, 'audio/damage_sound.wav');
    if (kDebugMode) debugPrint('🎵 Damage sound played!');
    
    // 💔 피격 시 깜빡이는 효과 시작
    player.isHitBlinking = true;
    player.hitBlinkTimer = 0.0;
    player.hitBlinkCount = 0;
    player.isVisible = true; // 초기 상태는 보이는 상태
    
    // 🛡️ 피격 후 2초 무적 시간 활성화
    player.isHitInvincible = true;
    player.hitInvincibilityTimer = 0.0;
    if (kDebugMode) debugPrint('🛡️ Hit invincibility activated for 2 seconds!');
    
    if (health <= 0) {
      endGame();
    }
  }

  void endGame() {
    // 🚨 이미 게임 오버 상태면 중복 실행 방지!
    if (gameOver) {
      print('⚠️ endGame() ignored - already game over');
      return;
    }
    
    print('💀💀💀 endGame() CALLED! 💀💀💀');
    gameOver = true;
    
    // 🎵 모든 음악 즉시 중지
    _pauseAllMusic();
    
    // 💀 게임오버 효과음 재생 (왕왕왕왕~ 기운 빠지는 소리)
    try {
      gameOverSoundPlayer.stop(); // 혹시 모를 이전 재생 중지
      gameOverSoundPlayer.play(AssetSource('audio/game_over_defeat.mp3'));
      if (kDebugMode) debugPrint('💀 Game Over defeat sound played!');
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Failed to play game over sound: $e');
    }
    
    // ✅ Flutter 위젯 오버레이로 게임 오버 화면 표시
    overlays.add('gameOver');
    print('💀 GameOver overlay ADDED!');
    
    // 🏆 점수 저장은 백그라운드에서 처리
    _saveScoreToLeaderboard().catchError((e) {
      if (kDebugMode) debugPrint('❌ Failed to save score: $e');
    });
  }
  
  // 📋 게임 시작 (안내 화면에서 터치 시 호출)
  void startGame() {
    showInstructions = false;
    // 🎵 배경 음악 시작
    _startBackgroundMusic();
    if (kDebugMode) debugPrint('🎮 Game started!');
  }
  
  @override
  void onRemove() {
    // 게임 종료 시 모든 오디오 플레이어 정리
    bgMusicPlayer.dispose();
    invincibilityMusicPlayer.dispose();
    bossMusicPlayer.dispose();
    
    // 🎯 효과음 풀의 모든 플레이어 정리
    for (final player in jumpSoundPool) {
      player.dispose();
    }
    for (final player in candySoundPool) {
      player.dispose();
    }
    for (final player in megaCandySoundPool) {
      player.dispose();
    }
    for (final player in monsterKillSoundPool) {
      player.dispose();
    }
    for (final player in damageSoundPool) {
      player.dispose();
    }
    
    gameOverSoundPlayer.dispose();
    super.onRemove();
  }

  void resetGame() {
    print('🔄🔄🔄 resetGame() CALLED! 🔄🔄🔄');
    
    // 🚨 CRITICAL: gameOver를 먼저 false로 설정해서 충돌 감지 중단!
    gameOver = false;
    print('🔄 gameOver set to FALSE');
    
    score = 0;
    candies = 0;
    passedCandies = 0; // 🎯 지나간 사탕 리셋
    monstersKilled = 0; // 👾 몬스터 처치 수 리셋
    moonFragments = 0;
    health = 3;
    gameSpeed = 200.0;
    baseSpeed = 200.0;
    isPaused = false; // ⏸️ 일시정지 해제
    showTutorial = false; // 📖 튜토리얼 다시 보여주기
    isInvincible = false;
    invincibilityTimer = 0.0;
    lastMegaCandyAt = 0;
    isBossActive = false;
    lastBossAt = 0;
    showLeaderboard = false; // 🏆 리더보드 닫기
    showNicknameInput = false; // ✏️ 닉네임 입력 닫기
    
    // 🍭 파워업 상태 초기화
    currentPowerUp = '';
    powerUpTimer = 0.0;
    isSuperJumpActive = false;
    isLightningSpeedActive = false;
    isStarBlessingActive = false;
    isRageModeActive = false;
    starBlessingTimer = 0.0;
    rageModeTimer = 0.0;
    isCandyMagnetActive = false;
    
    // 🍇 너프 상태 초기화
    currentNerf = '';
    nerfTimer = 0.0;
    isSlowMotion = false;
    isJumpReduced = false;
    isPowerUpBlocked = false;
    
    // ✅ resumeEngine() 제거 - 이미 엔진이 실행 중임 (pauseEngine을 호출하지 않았으므로)
    print('🔄 Engine already running, skipping resumeEngine()');
    
    // 🎵 정상 배경음악으로 복귀
    if (musicStarted) _resumeNormalMusic();
    
    print('🔄 Removing overlays...');
    // ✅ Flutter 위젯 오버레이 제거
    overlays.remove('gameOver');
    overlays.remove('leaderboard');
    overlays.remove('nicknameInput');
    print('🔄 All overlays removed');
    
    print('🔄 Removing ALL game objects FIRST (before player reset)...');
    // 🚨 CRITICAL: 적과 장애물을 먼저 제거해야 플레이어 리셋 시 충돌이 안 일어남!
    
    // ✅ toList()로 복사 후 제거 (즉시 실행 보장)
    final obstaclesList = children.whereType<Obstacle>().toList();
    final candiesList = children.whereType<Candy>().toList();
    final megaCandiesList = children.whereType<MegaCandy>().toList();
    final bossesList = children.whereType<ScarecrowBoss>().toList();
    final fireballsList = children.whereType<Fireball>().toList();
    final playerFireballsList = children.whereType<PlayerFireball>().toList();
    final purpleCandiesList = children.whereType<PurpleCandy>().toList();
    
    print('🔄 Found objects to remove:');
    print('   - Obstacles: ${obstaclesList.length}');
    print('   - Candies: ${candiesList.length}');
    print('   - Mega Candies: ${megaCandiesList.length}');
    print('   - Bosses: ${bossesList.length}');
    print('   - Fireballs: ${fireballsList.length}');
    print('   - Player Fireballs: ${playerFireballsList.length}');
    print('   - Purple Candies: ${purpleCandiesList.length}');
    
    // 🗑️ 즉시 제거
    for (final obstacle in obstaclesList) {
      obstacle.removeFromParent();
    }
    for (final candy in candiesList) {
      candy.removeFromParent();
    }
    for (final megaCandy in megaCandiesList) {
      megaCandy.removeFromParent();
    }
    for (final boss in bossesList) {
      boss.removeFromParent();
    }
    for (final fireball in fireballsList) {
      fireball.removeFromParent();
    }
    for (final playerFireball in playerFireballsList) {
      playerFireball.removeFromParent();
    }
    for (final purpleCandy in purpleCandiesList) {
      purpleCandy.removeFromParent();
    }
    
    print('🔄 All game objects removed!');
    
    print('🔄 Resetting player (enemies cleared)...');
    // 플레이어 위치 및 상태 리셋
    final playerStartY = size.y * 0.72;
    player.position.x = size.x * 0.2; // 화면 왼쪽 20% 위치
    player.position.y = playerStartY;
    player.velocityY = 0;
    player.velocityX = 0;
    player.isOnGround = true;
    player.jumpCount = 0;
    player.groundY = playerStartY; // groundY도 리셋
    
    // 플레이어 시각 효과 초기화
    player.isHitBlinking = false;
    player.hitBlinkCount = 0;
    player.hitBlinkTimer = 0.0;
    player.isVisible = true;
    player.isInvincible = false;
    player.isHitInvincible = false;
    player.isHeartGlowing = false;
    player.heartGlowTimer = 0.0;
    player.heartGlowIntensity = 0.0;
    player.hitInvincibilityTimer = 0.0;
    player.blinkTimer = 0.0;
    
    print('🔄 Player reset - position: (${player.position.x}, ${player.position.y})');
    
    // 🕐 타이머 초기화
    obstacleTimer = 0;
    candyTimer = 0;
    
    print('🔄 Timers reset - obstacleTimer: $obstacleTimer, candyTimer: $candyTimer');
    
    print('🔄 Game reset COMPLETE! gameOver=$gameOver');
  }
}

// Player Cat Component
class PlayerCat extends SpriteComponent with CollisionCallbacks {
  PlayerCat({required super.position})
      : super(
          size: Vector2(120, 120), // 🐱 1.5배 크기 (80 -> 120)
          anchor: Anchor.center,
        );

  double velocityY = 0;
  double velocityX = 0;
  final double gravity = 980;
  final double jumpStrength = -550; // 🚀 더 높은 점프력 (-450 -> -550)
  final double moveSpeed = 300;
  bool isOnGround = true;
  double groundY = 0;
  int jumpCount = 0;
  final int maxJumps = 4; // 4중점프!
  
  // ⭐ 무적 상태 번쩍번쩍 효과
  bool isInvincible = false;
  double blinkTimer = 0.0;
  bool isVisible = true;
  
  // ❤️ 하트 획득 시 반짝이는 효과
  bool isHeartGlowing = false;
  double heartGlowTimer = 0.0;
  double heartGlowIntensity = 0.0;
  
  // 💔 피격 시 깜빡이는 효과
  bool isHitBlinking = false;
  double hitBlinkTimer = 0.0;
  int hitBlinkCount = 0;
  final int maxHitBlinks = 6; // 3번 깜빡임 (켜짐/꺼짐 * 3 = 6)
  
  // 🛡️ 피격 후 무적 시간
  bool isHitInvincible = false; // 피격 후 무적 상태
  double hitInvincibilityTimer = 0.0; // 무적 시간 타이머
  final double hitInvincibilityDuration = 2.0; // 2초 무적

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    groundY = position.y;
    
    // 🎨 미리 로드된 고양이 이미지 사용
    try {
      if (kDebugMode) {
        debugPrint('🔍 Loading cat sprite from game cache...');
      }
      
      // 게임 엔진에서 미리 로드한 이미지 가져오기 (단순 키 이름만)
      final gameEngine = parent as BlackCatDeliveryGame;
      final catImage = gameEngine.images.fromCache('cat');
      sprite = Sprite(catImage);
      
      // 투명도 보존을 위한 Paint 설정
      paint = Paint()
        ..filterQuality = FilterQuality.high
        ..isAntiAlias = true;
      
      if (kDebugMode) {
        debugPrint('✅ Cat sprite created with transparency!');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Failed to create cat sprite: $e');
      }
    }
    
    // 실제 고양이 몸통에 맞는 작은 hitbox (더 정확한 충돌 감지)
    add(RectangleHitbox(
      size: Vector2(size.x * 0.5, size.y * 0.6), // 이미지에 맞게 조정
      position: Vector2(size.x * 0.25, size.y * 0.2), // 중앙 정렬
    ));
  }
  
  void activateInvincibility() {
    isInvincible = true;
    blinkTimer = 0.0;
  }
  
  void triggerHeartGlow() {
    isHeartGlowing = true;
    heartGlowTimer = 0.0;
    heartGlowIntensity = 1.0;
  }
  
  @override
  void render(Canvas canvas) {
    // 💔 피격 시 깜빡임 - 반투명 처리
    if (isHitBlinking && !isVisible) {
      paint.color = Colors.white.withValues(alpha: 0.3);
    } else {
      paint.color = Colors.white.withValues(alpha: 1.0);
    }
    
    // ❤️ 하트 획득 시 반짝이는 후광 효과 (먼저 그리기)
    if (isHeartGlowing && heartGlowIntensity > 0) {
      final glowPaint = Paint()
        ..color = Color.fromARGB(
          (heartGlowIntensity * 200).toInt(),
          255, 215, 0, // 황금색
        )
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 15);
      canvas.drawCircle(
        Offset(size.x / 2, size.y / 2),
        size.x / 2 + (heartGlowIntensity * 20),
        glowPaint,
      );
    }
    
    // ⭐ 무적 상태일 때 요란한 반짝임 효과! (먼저 그리기)
    if (isInvincible) {
      // 3겹 후광 효과 (빨강, 노랑, 흰색)
      final colors = [
        Color.fromARGB(isVisible ? 220 : 120, 255, 50, 50),    // 빨강
        Color.fromARGB(isVisible ? 220 : 120, 255, 215, 0),  // 노랑
        Color.fromARGB(isVisible ? 220 : 120, 255, 255, 255), // 흰색
      ];
      
      for (int i = 0; i < 3; i++) {
        final glowPaint = Paint()
          ..color = colors[i]
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 30.0 - (i * 5));
        canvas.drawCircle(
          Offset(size.x / 2, size.y / 2),
          size.x / 2 + 50 - (i * 10),
          glowPaint,
        );
      }
      
      // 반짝이는 별 효과 (8방향)
      if (isVisible) {
        final starPaint = Paint()
          ..color = const Color(0xFFFFFF00)
          ..style = PaintingStyle.fill;
        
        for (int i = 0; i < 8; i++) {
          final angle = (i * math.pi / 4) + (blinkTimer * 3);
          final distance = size.x / 2 + 40;
          final x = size.x / 2 + math.cos(angle) * distance;
          final y = size.y / 2 + math.sin(angle) * distance;
          
          // 큰 별 그리기
          final path = Path();
          for (int j = 0; j < 5; j++) {
            final starAngle = (j * 2 * math.pi / 5) - math.pi / 2;
            final radius = j.isEven ? 12.0 : 6.0;
            final px = x + math.cos(starAngle) * radius;
            final py = y + math.sin(starAngle) * radius;
            if (j == 0) {
              path.moveTo(px, py);
            } else {
              path.lineTo(px, py);
            }
          }
          path.close();
          canvas.drawPath(path, starPaint);
        }
      }
    }
    
    // 이미지 렌더링 (효과 위에 그려짐)
    super.render(canvas);
    
    // 이미지가 로드되지 않았을 경우 간단한 원으로 표시
    if (sprite == null) {
      final paint = Paint()..color = const Color(0xFFF5F5F5);
      canvas.drawCircle(
        Offset(size.x / 2, size.y / 2),
        size.x / 2,
        paint,
      );
      
      // 눈
      final eyePaint = Paint()..color = Colors.black;
      canvas.drawCircle(Offset(size.x * 0.4, size.y * 0.4), 3, eyePaint);
      canvas.drawCircle(Offset(size.x * 0.6, size.y * 0.4), 3, eyePaint);
    }
  }

  void jump() {
    final game = findGame() as BlackCatDeliveryGame?;
    if (game == null) return;
    
    // 🚀 슈퍼 점프 모드: 8단 점프 + 2배 점프력
    final maxJumpCount = game.isSuperJumpActive ? 8 : maxJumps;
    
    // 🔻 점프력 감소 너프: 60% 점프력
    double basePower = game.isSuperJumpActive ? jumpStrength * 2 : jumpStrength;
    double jumpPower = game.isJumpReduced ? basePower * 0.6 : basePower;
    
    // 🐌 슬로우 모션 너프: 점프력도 50% 감소 (체감 가능하도록)
    if (game.isSlowMotion) {
      jumpPower *= 0.5;
    }
    
    // ⭐ 무적 버프: 점프력 30% 증가
    if (game.isInvincible) {
      jumpPower *= 1.3;
    }
    
    if (jumpCount < maxJumpCount) {
      velocityY = jumpPower;
      isOnGround = false;
      jumpCount++;
      
      // 🎵 점프 효과음 (풀에서 재생 - 동시 재생 지원)
      game._playFromPool(game.jumpSoundPool, 'audio/jump_sound.mp3');
    }
  }

  void fastFall() {
    if (!isOnGround) {
      final game = findGame() as BlackCatDeliveryGame?;
      double fallSpeed = 600.0; // 기본 빠른 낙하 속도
      
      // 🐌 슬로우 모션 너프: 낙하 속도도 50% 감소 (체감 가능하도록)
      if (game != null && game.isSlowMotion) {
        fallSpeed *= 0.5;
      }
      
      // ⭐ 무적 버프: 낙하 속도 30% 증가
      if (game != null && game.isInvincible) {
        fallSpeed *= 1.3;
      }
      
      velocityY = fallSpeed;
    }
  }

  void moveLeft() {
    velocityX = -moveSpeed;
  }

  void moveRight() {
    velocityX = moveSpeed;
  }

  @override
  void update(double dt) {
    super.update(dt);

    final game = findGame() as BlackCatDeliveryGame?;
    if (game == null) return;
    
    // ⭐ 무적 상태 업데이트
    isInvincible = game.isInvincible;
    if (isInvincible) {
      blinkTimer += dt;
      // 0.1초마다 깜빡임 (피격 깜빡임보다 우선)
      if (blinkTimer >= 0.1) {
        blinkTimer = 0.0;
        isVisible = !isVisible;
      }
      // 무적 중에는 피격 깜빡임 중단
      isHitBlinking = false;
      hitBlinkCount = 0;
    } else {
      // 무적이 아닐 때만 피격 깜빡임 처리
      if (!isHitBlinking) {
        isVisible = true;
      }
    }
    
    // ❤️ 하트 획득 시 반짝이는 효과 (1초 동안)
    if (isHeartGlowing) {
      heartGlowTimer += dt;
      heartGlowIntensity = 1.0 - (heartGlowTimer / 1.0).clamp(0.0, 1.0);
      
      if (heartGlowTimer >= 1.0) {
        isHeartGlowing = false;
        heartGlowIntensity = 0.0;
      }
    }
    
    // 🛡️ 피격 후 무적 시간 타이머 업데이트
    if (isHitInvincible) {
      hitInvincibilityTimer += dt;
      if (hitInvincibilityTimer >= hitInvincibilityDuration) {
        isHitInvincible = false;
        hitInvincibilityTimer = 0.0;
        if (kDebugMode) debugPrint('🛡️ Hit invincibility ended');
      }
    }
    
    // 💔 피격 시 깜빡이는 효과 업데이트 (무적이 아닐 때만)
    if (isHitBlinking && !isInvincible) {
      hitBlinkTimer += dt;
      // 0.15초마다 깜빡임 토글
      if (hitBlinkTimer >= 0.15) {
        hitBlinkTimer = 0.0;
        isVisible = !isVisible;
        hitBlinkCount++;
        
        if (hitBlinkCount >= maxHitBlinks) {
          isHitBlinking = false;
          isVisible = true;
          hitBlinkCount = 0;
        }
      }
    }

    // Apply gravity (슬로우 모션과 무적 버프 영향)
    double gravityMultiplier = 1.0;
    
    // 🐌 슬로우 모션 너프: 중력도 50% 감소 (낙하 속도 느려짐)
    if (game.isSlowMotion) {
      gravityMultiplier *= 0.5;
    }
    
    // ⭐ 무적 버프: 중력 30% 증가 (빠른 낙하)
    if (game.isInvincible) {
      gravityMultiplier *= 1.3;
    }
    
    velocityY += gravity * gravityMultiplier * dt;
    position.y += velocityY * dt;

    // Apply horizontal movement (⭐ 무적 3배, ⚡ 번개속도 5배, 🐌 슬로우 50%)
    double speedMultiplier = 1.0;
    if (isInvincible) {
      speedMultiplier = 3.0;
    } else if (game.isLightningSpeedActive) {
      speedMultiplier = 5.0;
    }
    
    // 🐌 슬로우 모션 너프: 50% 속도 감소
    if (game.isSlowMotion) {
      speedMultiplier *= 0.5;
    }
    
    position.x += velocityX * speedMultiplier * dt;

    // Limit horizontal movement
    if (position.x < 50) {
      position.x = 50;
    } else if (position.x > game.size.x - 50) {
      position.x = game.size.x - 50;
    }

    // Friction
    velocityX *= 0.9;

    // Ground collision
    if (position.y >= groundY) {
      position.y = groundY;
      velocityY = 0;
      isOnGround = true;
      jumpCount = 0; // 지면에 닿으면 점프 카운트 리셋
    }
  }

  @override
  void onCollision(Set<Vector2> intersectionPoints, PositionComponent other) {
    super.onCollision(intersectionPoints, other);
    
    final game = findGame()! as BlackCatDeliveryGame;
    
    if (other is Obstacle) {
      // 🦘 점프 공격: 고양이가 위에서 내려오면서 몬스터를 밟으면 몬스터만 죽음!
      final isJumpAttack = velocityY > 0 && position.y < other.position.y;
      
      if (isJumpAttack) {
        // 위에서 밟았다! 몬스터만 죽고 고양이는 안전
        game.killMonster(); // 🎯 몬스터 처치 카운트 & 점수 추가
        
        // 💥 폭발 이펙트 생성
        game.add(ExplosionEffect(
          position: other.position.clone(),
        ));
        
        // 🎵 몬스터 처치 효과음 (풀에서 재생 - 동시 재생 지원)
        game._playFromPool(game.monsterKillSoundPool, 'audio/monster_pop.mp3');
        
        other.removeFromParent();
        // 작은 점프 효과
        velocityY = jumpStrength * 0.5;
        if (kDebugMode) debugPrint('🦘 Jump attack! Monster killed!');
      } else {
        // 옆이나 아래에서 충돌 - 일반 충돌 처리
        // ⭐ 무적 상태면 장애물 충돌 무시!
        if (!game.isInvincible) {
          if (kDebugMode) {
            debugPrint('💥 Hit obstacle!');
            debugPrint('   game.isInvincible: ${game.isInvincible}');
            debugPrint('   player.isInvincible: $isInvincible');
          }
          game.takeDamage();
          other.removeFromParent();
          if (kDebugMode) debugPrint('💔 Health now: ${game.health}');
        } else {
          // 무적 상태에서는 장애물 제거 + 점수 획득!
          if (kDebugMode) {
            debugPrint('⭐ Invincible collision!');
            debugPrint('   game.isInvincible: ${game.isInvincible}');
            debugPrint('   player.isInvincible: $isInvincible');
          }
          game.killMonster(); // 🎯 무적 상태에서도 몬스터 처치 점수!
          
          // 💥 무적 상태 몬스터 처치도 폭발 효과
          game.add(ExplosionEffect(
            position: other.position.clone(),
          ));
          
          other.removeFromParent();
          if (kDebugMode) debugPrint('⭐ Monster destroyed! +10 points');
        }
      }
    } else if (other is Candy) {
      game.collectCandy();
      other.removeFromParent();
    } else if (other is MegaCandy) {
      game.collectMegaCandy();
      other.removeFromParent();
      if (kDebugMode) debugPrint('🍭 Mega Candy collected! Invincibility activated!');
    } else if (other is PurpleCandy) {
      game.collectPurpleCandy();
      other.removeFromParent();
      if (kDebugMode) debugPrint('🍇 Purple Nerf Candy collected! Debuff activated!');
    }
  }
}

// Obstacle Component
class Obstacle extends PositionComponent with CollisionCallbacks {
  final String type;
  final double speed;
  final bool wavingMotion; // 📈📉 위아래 움직임 여부
  Sprite? witchSprite;
  Sprite? fireSprite; // 🔥 불꽃 해골 스프라이트
  Sprite? ghostSprite; // 👻 유령 스프라이트
  
  double waveTimer = 0; // 파동 타이머
  double initialY = 0; // 초기 Y 위치
  final double groundY; // 지상 레벨
  double fireballTimer = 0; // 🔥 불꽃 발사 타이머
  final double fireballInterval = 3.0; // 3초마다 발사

  Obstacle({
    required Vector2 position,
    required this.type,
    required this.speed,
    this.wavingMotion = false, // 기본값: 직선 이동
    double? initialY, // 초기 Y 위치 (옵션)
    required this.groundY, // 지상 레벨 (필수)
  }) : initialY = initialY ?? position.y,
       super(
         position: position,
          size: type == 'witch' 
              ? Vector2(120, 135)  // 🧙‍♀️ 마녀 1.5배 크기 (80x90 -> 120x135)
              : type == 'fire'
                  ? Vector2(100, 120)  // 🔥 불꽃 해골은 2배 크기!
                  : type == 'ghost'
                      ? Vector2(75, 90)  // 👻 유령 1.5배 크기 (50x60 -> 75x90)
                      : Vector2(50, 60), // 다른 장애물은 기본 크기
          anchor: Anchor.center,
        );

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    
    // 🧙‍♀️ 마녀일 경우 이미지 로드
    if (type == 'witch') {
      try {
        final gameEngine = parent as BlackCatDeliveryGame;
        final witchImage = gameEngine.images.fromCache('witch');
        witchSprite = Sprite(witchImage);
        
        if (kDebugMode) {
          debugPrint('✅ Witch sprite loaded successfully!');
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('❌ Failed to load witch sprite: $e');
        }
      }
    }
    
    // 🔥 불꽃 해골일 경우 이미지 로드
    if (type == 'fire') {
      try {
        final gameEngine = parent as BlackCatDeliveryGame;
        final fireImage = gameEngine.images.fromCache('fire');
        fireSprite = Sprite(fireImage);
        
        if (kDebugMode) {
          debugPrint('✅ Fire sprite loaded successfully!');
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('❌ Failed to load fire sprite: $e');
        }
      }
    }
    
    // 👻 유령일 경우 이미지 로드
    if (type == 'ghost') {
      try {
        final gameEngine = parent as BlackCatDeliveryGame;
        final ghostImage = gameEngine.images.fromCache('ghost');
        ghostSprite = Sprite(ghostImage);
        
        if (kDebugMode) {
          debugPrint('✅ Ghost sprite loaded successfully!');
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('❌ Failed to load ghost sprite: $e');
        }
      }
    }
    
    // 장애물 타입별로 정확한 크기의 hitbox 설정
    if (type == 'pumpkin') {
      // 호박: 타원형이므로 약간 작게
      add(RectangleHitbox(
        size: Vector2(size.x * 0.7, size.y * 0.7),
        position: Vector2(size.x * 0.15, size.y * 0.15),
      ));
    } else if (type == 'ghost') {
      // 유령: 몸통만
      add(RectangleHitbox(
        size: Vector2(size.x * 0.6, size.y * 0.65),
        position: Vector2(size.x * 0.2, size.y * 0.1),
      ));
    } else if (type == 'fire') {
      // 불: 불꽃 중심부만
      add(RectangleHitbox(
        size: Vector2(size.x * 0.5, size.y * 0.7),
        position: Vector2(size.x * 0.25, size.y * 0.15),
      ));
    } else if (type == 'witch') {
      // 마녀: 몸통과 빗자루
      add(RectangleHitbox(
        size: Vector2(size.x * 0.65, size.y * 0.6),
        position: Vector2(size.x * 0.175, size.y * 0.2),
      ));
    }
  }

  @override
  void update(double dt) {
    super.update(dt);
    
    // 수평 이동
    position.x -= speed * dt;
    
    // 📈📉 파동 운동 (위아래 움직임) - 지상 레벨까지는 내려오지 못함
    if (wavingMotion && type == 'witch') {
      waveTimer += dt;
      // sin 함수로 부드러운 위아래 움직임 (진폭: 80픽셀, 주기: 1.5초로 더 빠르게)
      final waveOffset = math.sin(waveTimer * math.pi * 1.3) * 80;
      final targetY = initialY + waveOffset;
      
      // 🛡️ 지상 레벨(고양이 위치)보다 50픽셀 위까지만 내려옴
      final minY = groundY - 50; // 지상 레벨 - 50픽셀
      position.y = targetY.clamp(initialY - 80, minY);
      
      if (kDebugMode && waveTimer < 0.1) {
        debugPrint('📈📉 Waving witch: targetY=$targetY, actualY=${position.y}, groundY=$groundY');
      }
    }
    
    // 🔥 불꽃 해골이 3초마다 불꽃 발사
    if (type == 'fire') {
      fireballTimer += dt;
      if (fireballTimer >= fireballInterval) {
        fireballTimer = 0;
        _shootFireball();
      }
    }

    if (position.x < -50) {
      removeFromParent();
    }
  }
  
  // 🔥 불꽃 발사 메서드
  void _shootFireball() {
    final gameEngine = parent as BlackCatDeliveryGame;
    gameEngine.add(Fireball(
      position: position.clone(), // 현재 위치에서 발사
      speed: 400.0, // 빠른 속도
    ));
    
    if (kDebugMode) {
      debugPrint('🔥 Fire skull shoots fireball!');
    }
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);

    switch (type) {
      case 'pumpkin':
        _drawPumpkin(canvas);
        break;
      case 'ghost':
        // 👻 유령은 스프라이트로 렌더링 (투명도 보존)
        if (ghostSprite != null) {
          final transparentPaint = Paint()
            ..filterQuality = FilterQuality.high
            ..isAntiAlias = true;
          
          canvas.save();
          ghostSprite!.render(
            canvas,
            size: size,
            overridePaint: transparentPaint,
          );
          canvas.restore();
        } else {
          // 이미지 로드 실패 시 기존 방식으로 그리기
          _drawGhost(canvas);
        }
        break;
      case 'fire':
        // 🔥 불꽃 해골은 스프라이트로 렌더링 (투명도 보존)
        if (fireSprite != null) {
          final transparentPaint = Paint()
            ..filterQuality = FilterQuality.high
            ..isAntiAlias = true;
          
          canvas.save();
          fireSprite!.render(
            canvas,
            size: size,
            overridePaint: transparentPaint,
          );
          canvas.restore();
        } else {
          // 이미지 로드 실패 시 기존 방식으로 그리기
          _drawFire(canvas);
        }
        break;
      case 'witch':
        // 마녀는 스프라이트로 렌더링 (투명도 보존)
        if (witchSprite != null) {
          final transparentPaint = Paint()
            ..filterQuality = FilterQuality.high
            ..isAntiAlias = true;
          
          canvas.save();
          witchSprite!.render(
            canvas,
            size: size,
            overridePaint: transparentPaint,
          );
          canvas.restore();
        } else {
          // 이미지 로드 실패 시 기존 방식으로 그리기
          _drawWitch(canvas);
        }
        break;
    }
  }

  void _drawPumpkin(Canvas canvas) {
    final paint = Paint()..color = const Color(0xFFFF8C00);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(size.x / 2, size.y / 2),
        width: size.x,
        height: size.y,
      ),
      paint,
    );

    // Eyes
    final eyePaint = Paint()..color = const Color(0xFF1A1A1A);
    canvas.drawCircle(Offset(size.x * 0.35, size.y * 0.4), 4, eyePaint);
    canvas.drawCircle(Offset(size.x * 0.65, size.y * 0.4), 4, eyePaint);
  }

  void _drawGhost(Canvas canvas) {
    final paint = Paint()..color = const Color(0xFFEEEEEE);
    
    final path = Path()
      ..moveTo(size.x / 2, 0)
      ..cubicTo(0, 0, 0, size.y * 0.5, 0, size.y * 0.7)
      ..lineTo(0, size.y)
      ..lineTo(size.x * 0.25, size.y * 0.85)
      ..lineTo(size.x * 0.5, size.y)
      ..lineTo(size.x * 0.75, size.y * 0.85)
      ..lineTo(size.x, size.y)
      ..lineTo(size.x, size.y * 0.7)
      ..cubicTo(size.x, size.y * 0.5, size.x, 0, size.x / 2, 0)
      ..close();
    
    canvas.drawPath(path, paint);

    // Eyes
    final eyePaint = Paint()..color = const Color(0xFF1A1A1A);
    canvas.drawCircle(Offset(size.x * 0.35, size.y * 0.3), 4, eyePaint);
    canvas.drawCircle(Offset(size.x * 0.65, size.y * 0.3), 4, eyePaint);
  }

  void _drawFire(Canvas canvas) {
    final paint1 = Paint()..color = const Color(0xFFFF4500);
    final paint2 = Paint()..color = const Color(0xFFFFD700);

    // Outer flame
    final path1 = Path()
      ..moveTo(size.x / 2, 0)
      ..quadraticBezierTo(size.x, size.y * 0.3, size.x * 0.8, size.y)
      ..lineTo(size.x * 0.2, size.y)
      ..quadraticBezierTo(0, size.y * 0.3, size.x / 2, 0)
      ..close();
    canvas.drawPath(path1, paint1);

    // Inner flame
    final path2 = Path()
      ..moveTo(size.x / 2, size.y * 0.2)
      ..quadraticBezierTo(size.x * 0.7, size.y * 0.4, size.x * 0.6, size.y * 0.8)
      ..lineTo(size.x * 0.4, size.y * 0.8)
      ..quadraticBezierTo(size.x * 0.3, size.y * 0.4, size.x / 2, size.y * 0.2)
      ..close();
    canvas.drawPath(path2, paint2);
  }

  void _drawWitch(Canvas canvas) {
    // 빗자루 (갈색)
    final broomPaint = Paint()..color = const Color(0xFF8B4513);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(size.x * 0.1, size.y * 0.55, size.x * 0.6, 6),
        const Radius.circular(3),
      ),
      broomPaint,
    );

    // 빗자루 빗질 부분 (노란색)
    final bristlePaint = Paint()
      ..color = const Color(0xFFDAA520)
      ..style = PaintingStyle.fill;
    for (int i = 0; i < 5; i++) {
      final path = Path()
        ..moveTo(size.x * 0.65 + i * 3, size.y * 0.55)
        ..lineTo(size.x * 0.7 + i * 4, size.y * 0.7)
        ..lineTo(size.x * 0.67 + i * 3, size.y * 0.55)
        ..close();
      canvas.drawPath(path, bristlePaint);
    }

    // 마녀 몸통 (검은 망토)
    final bodyPaint = Paint()..color = const Color(0xFF1A1A1A);
    final bodyPath = Path()
      ..moveTo(size.x * 0.5, size.y * 0.3)
      ..quadraticBezierTo(size.x * 0.3, size.y * 0.4, size.x * 0.25, size.y * 0.6)
      ..lineTo(size.x * 0.75, size.y * 0.6)
      ..quadraticBezierTo(size.x * 0.7, size.y * 0.4, size.x * 0.5, size.y * 0.3)
      ..close();
    canvas.drawPath(bodyPath, bodyPaint);

    // 마녀 얼굴 (초록색)
    final facePaint = Paint()..color = const Color(0xFF90EE90);
    canvas.drawCircle(
      Offset(size.x * 0.5, size.y * 0.35),
      size.x * 0.15,
      facePaint,
    );

    // 마녀 모자 (검정 + 보라)
    final hatPaint = Paint()..color = const Color(0xFF1A1A1A);
    // 모자 테두리
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(size.x * 0.5, size.y * 0.25),
        width: size.x * 0.4,
        height: size.y * 0.08,
      ),
      hatPaint,
    );
    // 모자 꼭대기
    final hatTopPath = Path()
      ..moveTo(size.x * 0.4, size.y * 0.25)
      ..lineTo(size.x * 0.47, size.y * 0.05)
      ..lineTo(size.x * 0.53, size.y * 0.05)
      ..lineTo(size.x * 0.6, size.y * 0.25)
      ..close();
    canvas.drawPath(hatTopPath, hatPaint);

    // 모자 띠 (보라색)
    final bandPaint = Paint()..color = const Color(0xFF6B4FA0);
    canvas.drawRect(
      Rect.fromLTWH(size.x * 0.4, size.y * 0.23, size.x * 0.2, size.y * 0.04),
      bandPaint,
    );

    // 눈 (빨간색 - 사악한 느낌)
    final eyePaint = Paint()..color = const Color(0xFFFF0000);
    canvas.drawCircle(Offset(size.x * 0.45, size.y * 0.35), 3, eyePaint);
    canvas.drawCircle(Offset(size.x * 0.55, size.y * 0.35), 3, eyePaint);

    // 코 (길고 뾰족한)
    final nosePaint = Paint()..color = const Color(0xFF7CBA7C);
    final nosePath = Path()
      ..moveTo(size.x * 0.5, size.y * 0.37)
      ..lineTo(size.x * 0.45, size.y * 0.42)
      ..lineTo(size.x * 0.5, size.y * 0.4)
      ..close();
    canvas.drawPath(nosePath, nosePaint);
  }
}

// Candy Component
class Candy extends PositionComponent with CollisionCallbacks {
  final double speed;
  
  // 🧲 자석 효과 관련 변수
  bool isBeingAttracted = false;
  Vector2? targetPosition;

  Candy({
    required super.position,
    required this.speed,
  }) : super(
          size: Vector2(30, 30),
          anchor: Anchor.center,
        );

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    
    // 사탕은 원형이므로 CircleHitbox 사용 (더 정확한 충돌)
    add(CircleHitbox(
      radius: size.x * 0.4, // 80% 크기
      position: Vector2(size.x * 0.1, size.y * 0.1),
    ));
  }

  // 🧲 자석 효과 활성화
  void attractToPlayer(Vector2 playerPos) {
    isBeingAttracted = true;
    // targetPosition은 초기화만 하고, update에서 실시간으로 플레이어 추적
  }

  @override
  void update(double dt) {
    super.update(dt);
    
    // 🧲 자석 효과가 활성화되면 플레이어 쪽으로 빠르게 이동
    if (isBeingAttracted) {
      final game = findGame()! as BlackCatDeliveryGame;
      
      // 🎯 실시간으로 플레이어 위치 추적 (고정된 위치가 아님!)
      final playerPos = game.player.position;
      final direction = playerPos - position;
      final distance = direction.length;
      
      if (distance > 10) {
        // 플레이어 쪽으로 빠르게 이동 (실시간 추적)
        direction.normalize();
        position += direction * 1200 * dt; // 매우 빠른 속도로 추적
      } else {
        // 플레이어에게 도달하면 제거 (자동 수집)
        game.collectCandy();
        removeFromParent();
      }
    } else {
      // 일반 이동
      position.x -= speed * dt;

      if (position.x < -50) {
        removeFromParent();
      }
    }
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);

    // 왼쪽 포장지 날개 (빨강-흰색 스트라이프)
    final leftWrapperPaint = Paint()..color = const Color(0xFFFF6B6B);
    final leftWrapperPath = Path()
      ..moveTo(size.x * 0.1, size.y * 0.5)
      ..quadraticBezierTo(
        0,
        size.y * 0.3,
        size.x * 0.05,
        size.y * 0.2,
      )
      ..quadraticBezierTo(
        size.x * 0.15,
        size.y * 0.35,
        size.x * 0.3,
        size.y * 0.4,
      )
      ..lineTo(size.x * 0.3, size.y * 0.6)
      ..quadraticBezierTo(
        size.x * 0.15,
        size.y * 0.65,
        size.x * 0.05,
        size.y * 0.8,
      )
      ..quadraticBezierTo(
        0,
        size.y * 0.7,
        size.x * 0.1,
        size.y * 0.5,
      )
      ..close();
    canvas.drawPath(leftWrapperPath, leftWrapperPaint);

    // 오른쪽 포장지 날개 (빨강-흰색 스트라이프)
    final rightWrapperPaint = Paint()..color = const Color(0xFFFF6B6B);
    final rightWrapperPath = Path()
      ..moveTo(size.x * 0.9, size.y * 0.5)
      ..quadraticBezierTo(
        size.x,
        size.y * 0.3,
        size.x * 0.95,
        size.y * 0.2,
      )
      ..quadraticBezierTo(
        size.x * 0.85,
        size.y * 0.35,
        size.x * 0.7,
        size.y * 0.4,
      )
      ..lineTo(size.x * 0.7, size.y * 0.6)
      ..quadraticBezierTo(
        size.x * 0.85,
        size.y * 0.65,
        size.x * 0.95,
        size.y * 0.8,
      )
      ..quadraticBezierTo(
        size.x,
        size.y * 0.7,
        size.x * 0.9,
        size.y * 0.5,
      )
      ..close();
    canvas.drawPath(rightWrapperPath, rightWrapperPaint);

    // 중앙 사탕 본체 (핑크색)
    final candyPaint = Paint()..color = const Color(0xFFFF69B4);
    canvas.drawOval(
      Rect.fromLTWH(size.x * 0.3, size.y * 0.35, size.x * 0.4, size.y * 0.3),
      candyPaint,
    );

    // 사탕 하이라이트 (빛 반사)
    final highlightPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.6)
      ..style = PaintingStyle.fill;
    canvas.drawOval(
      Rect.fromLTWH(size.x * 0.4, size.y * 0.4, size.x * 0.15, size.y * 0.1),
      highlightPaint,
    );

    // 포장지 흰색 스트라이프 (왼쪽)
    final stripePaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 2;
    canvas.drawLine(
      Offset(size.x * 0.08, size.y * 0.35),
      Offset(size.x * 0.15, size.y * 0.45),
      stripePaint,
    );
    canvas.drawLine(
      Offset(size.x * 0.08, size.y * 0.65),
      Offset(size.x * 0.15, size.y * 0.55),
      stripePaint,
    );

    // 포장지 흰색 스트라이프 (오른쪽)
    canvas.drawLine(
      Offset(size.x * 0.92, size.y * 0.35),
      Offset(size.x * 0.85, size.y * 0.45),
      stripePaint,
    );
    canvas.drawLine(
      Offset(size.x * 0.92, size.y * 0.65),
      Offset(size.x * 0.85, size.y * 0.55),
      stripePaint,
    );
  }
}

// Background Star Component
class Star extends PositionComponent {
  Star({required super.position})
      : super(
          size: Vector2(2, 2),
        );

  double twinkleTimer = 0;
  double opacity = 1.0;

  @override
  void update(double dt) {
    super.update(dt);
    twinkleTimer += dt;
    opacity = 0.5 + math.sin(twinkleTimer * 3) * 0.5;
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    final paint = Paint()
      ..color = const Color(0xFFFFD700).withValues(alpha: opacity);
    canvas.drawCircle(
      Offset(size.x / 2, size.y / 2),
      size.x / 2,
      paint,
    );
  }
}

// Moon Component
class Moon extends PositionComponent {
  double glowIntensity = 0.0; // 빛나는 강도 (0.0 ~ 1.0)
  double glowTimer = 0.0; // 빛나는 애니메이션 타이머
  bool isGlowing = false; // 빛나는 중인지 여부
  
  Moon({required super.position})
      : super(
          size: Vector2(80, 80),
          anchor: Anchor.center,
        );

  // 🌕 하트 획득 시 빛나는 효과
  void triggerGlow() {
    isGlowing = true;
    glowTimer = 0.0;
    glowIntensity = 1.0;
  }

  @override
  void update(double dt) {
    super.update(dt);
    
    // 빛나는 애니메이션 (1초 동안 점점 어두워짐)
    if (isGlowing) {
      glowTimer += dt;
      glowIntensity = 1.0 - (glowTimer / 1.0).clamp(0.0, 1.0);
      
      if (glowTimer >= 1.0) {
        isGlowing = false;
        glowIntensity = 0.0;
      }
    }
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);

    final game = findGame()! as BlackCatDeliveryGame;
    
    // 하트 개수에 따라 달 크기 조정 (3~5개 하트 → 80~120 픽셀)
    final healthRatio = (game.health - 3).clamp(0, 2) / 2.0; // 0.0 ~ 1.0
    final moonSize = 80.0 + (healthRatio * 40.0); // 80 ~ 120
    final moonRadius = moonSize / 2;

    // 빛나는 후광 효과
    if (glowIntensity > 0) {
      final glowPaint = Paint()
        ..color = Color.fromARGB(
          (glowIntensity * 150).toInt(),
          255, 255, 200,
        )
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 20);
      canvas.drawCircle(
        Offset(size.x / 2, size.y / 2),
        moonRadius + (glowIntensity * 30), // 빛나는 크기
        glowPaint,
      );
    }

    // 하트 개수에 따라 달 밝기 조정
    final brightness = 0xFFFFE4B5 + (healthRatio * 0x00001A4A).toInt();
    final paint = Paint()..color = Color(brightness.clamp(0xFFFFE4B5, 0xFFFFFFFF));
    
    canvas.drawCircle(
      Offset(size.x / 2, size.y / 2),
      moonRadius,
      paint,
    );

    // Moon craters (크기에 맞춰 조정)
    final craterScale = moonSize / 80.0;
    final craterPaint = Paint()..color = const Color(0xFFFFD89B);
    canvas.drawCircle(
      Offset(size.x * 0.3, size.y * 0.3), 
      8 * craterScale, 
      craterPaint
    );
    canvas.drawCircle(
      Offset(size.x * 0.6, size.y * 0.5), 
      6 * craterScale, 
      craterPaint
    );
    canvas.drawCircle(
      Offset(size.x * 0.4, size.y * 0.7), 
      5 * craterScale, 
      craterPaint
    );
  }
}

// 🏠 Halloween Residential Building Component (1~2층 주택가)
class HalloweenBuilding extends PositionComponent {
  final int buildingType;
  double scrollSpeed = 30.0; // 느린 스크롤 속도 (패럴랙스 효과)
  
  HalloweenBuilding({
    required Vector2 position,
    required this.buildingType,
  }) : super(
    position: position,
    size: Vector2(200, 200), // 더 좁은 주택 (연달아 배치)
    anchor: Anchor.bottomLeft,
  );
  
  @override
  void update(double dt) {
    super.update(dt);
    
    // 느리게 왼쪽으로 스크롤 (패럴랙스 효과)
    position.x -= scrollSpeed * dt;
    
    // 화면 밖으로 나가면 오른쪽 끝으로 이동
    final game = findGame()! as BlackCatDeliveryGame;
    if (position.x < -size.x) {
      position.x = game.size.x + 200;
    }
  }
  
  @override
  void render(Canvas canvas) {
    super.render(canvas);
    
    // 한밤중 불꺼진 건물 실루엣 (매우 어둡게)
    final buildingPaint = Paint()
      ..color = const Color(0xFF0A0515).withValues(alpha: 0.9) // 거의 검은색에 가까운 어두운 보라색
      ..style = PaintingStyle.fill;
    
    // 불꺼진 창문 (짙은 회색)
    final windowPaint = Paint()
      ..color = const Color(0xFF2A2A2A).withValues(alpha: 0.7) // 짙은 회색 창문
      ..style = PaintingStyle.fill;
    
    switch (buildingType) {
      case 0:
        _drawSmallHouse(canvas, buildingPaint, windowPaint);
        break;
      case 1:
        _drawTwoStoryHouse(canvas, buildingPaint, windowPaint);
        break;
      case 2:
        _drawCottage(canvas, buildingPaint, windowPaint);
        break;
      case 3:
        _drawTownhouse(canvas, buildingPaint, windowPaint);
        break;
    }
  }
  
  // 🏠 1층 작은 집
  void _drawSmallHouse(Canvas canvas, Paint buildingPaint, Paint windowPaint) {
    // 메인 건물 (1층)
    canvas.drawRect(
      Rect.fromLTWH(50, size.y - 100, 120, 100),
      buildingPaint,
    );
    
    // 삼각 지붕
    final roofPath = Path()
      ..moveTo(40, size.y - 100)
      ..lineTo(110, size.y - 150)
      ..lineTo(180, size.y - 100)
      ..close();
    canvas.drawPath(roofPath, buildingPaint);
    
    // 굴뚝
    canvas.drawRect(
      Rect.fromLTWH(140, size.y - 140, 15, 30),
      buildingPaint,
    );
    
    // 불꺼진 창문들 (짙은 회색)
    canvas.drawRect(Rect.fromLTWH(70, size.y - 75, 25, 30), windowPaint);
    canvas.drawRect(Rect.fromLTWH(125, size.y - 75, 25, 30), windowPaint);
  }
  
  // 🏠 2층 집
  void _drawTwoStoryHouse(Canvas canvas, Paint buildingPaint, Paint windowPaint) {
    // 1층
    canvas.drawRect(
      Rect.fromLTWH(60, size.y - 120, 140, 120),
      buildingPaint,
    );
    
    // 2층 (약간 작게)
    canvas.drawRect(
      Rect.fromLTWH(80, size.y - 200, 100, 80),
      buildingPaint,
    );
    
    // 지붕
    final roofPath = Path()
      ..moveTo(70, size.y - 200)
      ..lineTo(130, size.y - 240)
      ..lineTo(190, size.y - 200)
      ..close();
    canvas.drawPath(roofPath, buildingPaint);
    
    // 불꺼진 창문들 (짙은 회색)
    // 1층 창문
    canvas.drawRect(Rect.fromLTWH(80, size.y - 90, 25, 30), windowPaint);
    canvas.drawRect(Rect.fromLTWH(155, size.y - 90, 25, 30), windowPaint);
    // 2층 창문
    canvas.drawRect(Rect.fromLTWH(95, size.y - 175, 20, 25), windowPaint);
    canvas.drawRect(Rect.fromLTWH(145, size.y - 175, 20, 25), windowPaint);
  }
  
  // 🏠 오두막
  void _drawCottage(Canvas canvas, Paint buildingPaint, Paint windowPaint) {
    // 메인 건물 (작고 낮은 집)
    canvas.drawRect(
      Rect.fromLTWH(40, size.y - 90, 100, 90),
      buildingPaint,
    );
    
    // 경사 지붕
    final roofPath = Path()
      ..moveTo(30, size.y - 90)
      ..lineTo(90, size.y - 140)
      ..lineTo(150, size.y - 90)
      ..close();
    canvas.drawPath(roofPath, buildingPaint);
    
    // 작은 굴뚝
    canvas.drawRect(
      Rect.fromLTWH(110, size.y - 130, 12, 25),
      buildingPaint,
    );
    
    // 불꺼진 창문들 (짙은 회색)
    canvas.drawRect(Rect.fromLTWH(55, size.y - 65, 20, 25), windowPaint);
    canvas.drawRect(Rect.fromLTWH(95, size.y - 65, 20, 25), windowPaint);
  }
  
  // 🏠 연립주택
  void _drawTownhouse(Canvas canvas, Paint buildingPaint, Paint windowPaint) {
    // 좌측 집
    canvas.drawRect(
      Rect.fromLTWH(30, size.y - 110, 70, 110),
      buildingPaint,
    );
    
    // 우측 집
    canvas.drawRect(
      Rect.fromLTWH(100, size.y - 120, 70, 120),
      buildingPaint,
    );
    
    // 좌측 지붕
    final leftRoofPath = Path()
      ..moveTo(25, size.y - 110)
      ..lineTo(65, size.y - 145)
      ..lineTo(105, size.y - 110)
      ..close();
    canvas.drawPath(leftRoofPath, buildingPaint);
    
    // 우측 지붕
    final rightRoofPath = Path()
      ..moveTo(95, size.y - 120)
      ..lineTo(135, size.y - 160)
      ..lineTo(175, size.y - 120)
      ..close();
    canvas.drawPath(rightRoofPath, buildingPaint);
    
    // 불꺼진 창문들 (짙은 회색)
    // 좌측 집
    canvas.drawRect(Rect.fromLTWH(45, size.y - 80, 20, 25), windowPaint);
    canvas.drawRect(Rect.fromLTWH(70, size.y - 80, 20, 25), windowPaint);
    // 우측 집
    canvas.drawRect(Rect.fromLTWH(115, size.y - 90, 20, 25), windowPaint);
    canvas.drawRect(Rect.fromLTWH(140, size.y - 90, 20, 25), windowPaint);
  }
}

// 🕯️ Street Lamp Component (가로등 - 고정 위치)
class StreetLamp extends PositionComponent {
  double flickerTimer = 0;
  double flickerIntensity = 1.0;
  
  StreetLamp({required Vector2 position})
      : super(
          position: position,
          size: Vector2(40, 150),
          anchor: Anchor.bottomCenter,
        );
  
  @override
  void update(double dt) {
    super.update(dt);
    
    // 불꽃이 살짝 깜빡이는 효과
    flickerTimer += dt;
    flickerIntensity = 0.85 + (math.sin(flickerTimer * 5) * 0.15);
  }
  
  @override
  void render(Canvas canvas) {
    super.render(canvas);
    
    // 가로등 기둥 (어두운 철제)
    final polePaint = Paint()
      ..color = const Color(0xFF1A1A1A)
      ..style = PaintingStyle.fill;
    
    canvas.drawRect(
      Rect.fromLTWH(size.x / 2 - 3, size.y - 130, 6, 130),
      polePaint,
    );
    
    // 가로등 상단 (랜턴 모양)
    final lampBodyPaint = Paint()
      ..color = const Color(0xFF2A2A2A)
      ..style = PaintingStyle.fill;
    
    // 랜턴 본체
    canvas.drawRect(
      Rect.fromLTWH(size.x / 2 - 15, size.y - 150, 30, 35),
      lampBodyPaint,
    );
    
    // 랜턴 지붕
    final roofPath = Path()
      ..moveTo(size.x / 2 - 18, size.y - 150)
      ..lineTo(size.x / 2, size.y - 165)
      ..lineTo(size.x / 2 + 18, size.y - 150)
      ..close();
    canvas.drawPath(roofPath, lampBodyPaint);
    
    // 은은한 따뜻한 빛 (주황빛 - 너무 밝지 않게)
    final glowPaint = Paint()
      ..color = Color.fromARGB(
        (flickerIntensity * 60).toInt(), // 매우 낮은 투명도
        255, 200, 100, // 따뜻한 주황빛
      )
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 25);
    
    canvas.drawCircle(
      Offset(size.x / 2, size.y - 132),
      35,
      glowPaint,
    );
    
    // 랜턴 내부 빛 (작고 은은하게)
    final innerLightPaint = Paint()
      ..color = Color.fromARGB(
        (flickerIntensity * 120).toInt(),
        255, 220, 150,
      );
    
    canvas.drawRect(
      Rect.fromLTWH(size.x / 2 - 10, size.y - 145, 20, 25),
      innerLightPaint,
    );
  }
}

// Ground Component
class Ground extends PositionComponent {
  Ground({required super.position})
      : super(
          size: Vector2(10000, 200),
        );

  @override
  void render(Canvas canvas) {
    super.render(canvas);

    // Ground
    final groundPaint = Paint()..color = const Color(0xFF2D2440);
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.x, size.y),
      groundPaint,
    );

    // Grass details
    final grassPaint = Paint()..color = const Color(0xFF3D3450);
    for (int i = 0; i < size.x ~/ 50; i++) {
      canvas.drawRect(
        Rect.fromLTWH(i * 50.0, 0, 40, 5),
        grassPaint,
      );
    }
  }
}

// Game UI Component
class GameUI extends PositionComponent with TapCallbacks {
  // 🕹️ 터치 상태 추적 (누르고 있는 동안 계속 이동)
  bool isPressingLeft = false;
  bool isPressingRight = false;
  bool isPressingUp = false;
  bool isPressingDown = false;
  
  @override
  Future<void> onLoad() async {
    await super.onLoad();
    // 🎯 CRITICAL: GameUI가 전체 화면을 덮어야 터치 이벤트를 받을 수 있음!
    final game = findGame()! as BlackCatDeliveryGame;
    size = game.size.clone();
    position = Vector2.zero();
    priority = 100; // UI는 최상위에 렌더링
  }
  
  @override
  void render(Canvas canvas) {
    super.render(canvas);

    final game = findGame()! as BlackCatDeliveryGame;
    final textPaint = TextPaint(
      style: const TextStyle(
        color: Colors.white,
        fontSize: 20,
        fontWeight: FontWeight.bold,
      ),
    );

    // Draw score
    textPaint.render(
      canvas,
      'Score: ${game.score}',
      Vector2(10, 10),
    );

    // Draw candies
    textPaint.render(
      canvas,
      '🍬: ${game.candies}',
      Vector2(10, 40),
    );
    
    // Draw passed candies (지나간 사탕)
    textPaint.render(
      canvas,
      '📊: ${game.passedCandies}',
      Vector2(10, 70),
    );
    
    // 🎯 Draw monsters killed
    textPaint.render(
      canvas,
      '🎯: ${game.monstersKilled}',
      Vector2(150, 10),
    );
    
    // 🍭 Draw current power-up (파워업 활성화 시)
    if (game.currentPowerUp.isNotEmpty) {
      String powerUpIcon = '';
      String powerUpText = '';
      String powerUpDesc = '';
      
      switch (game.currentPowerUp) {
        case 'invincible':
          powerUpIcon = '⭐';
          powerUpText = '무적';
          powerUpDesc = '무적+3배속도';
          break;
        case 'magnet':
          powerUpIcon = '🧲';
          powerUpText = '자석';
          powerUpDesc = '사탕자석';
          break;
        case 'super_jump':
          powerUpIcon = '🚀';
          powerUpText = '슈퍼점프';
          powerUpDesc = '8단점프+2배';
          break;
        case 'lightning':
          powerUpIcon = '⚡';
          powerUpText = '번개속도';
          powerUpDesc = '5배 속도';
          break;
        case 'star_blessing':
          powerUpIcon = '🌟';
          powerUpText = '별의축복';
          powerUpDesc = '무한사탕';
          break;
        case 'rage_mode':
          powerUpIcon = '🔥';
          powerUpText = '분노모드';
          powerUpDesc = '자동공격';
          break;
      }
      
      // 배경 박스 (반투명 황금색)
      final bgPaint = Paint()
        ..color = const Color(0xAAFFD700)
        ..style = PaintingStyle.fill;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(145, 35, 180, 30),
          const Radius.circular(8),
        ),
        bgPaint,
      );
      
      // 테두리
      final borderPaint = Paint()
        ..color = const Color(0xFFFFD700)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(145, 35, 180, 30),
          const Radius.circular(8),
        ),
        borderPaint,
      );
      
      // 텍스트
      final powerUpPaint = TextPaint(
        style: const TextStyle(
          color: Color(0xFF000000), // 검은색 (배경이 밝으니)
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
      );
      
      final timerPaint = TextPaint(
        style: const TextStyle(
          color: Color(0xFF8B0000), // 진한 빨강
          fontSize: 16,
          fontWeight: FontWeight.bold,
        ),
      );
      
      // 버프 텍스트 (박스 중앙 정렬)
      powerUpPaint.render(
        canvas,
        '$powerUpIcon $powerUpText',
        Vector2(155, 50), // 박스의 중앙으로 조정
        anchor: Anchor.centerLeft, // 왼쪽 정렬하되 수직 중앙
      );
      
      timerPaint.render(
        canvas,
        '${game.powerUpTimer.toStringAsFixed(1)}s',
        Vector2(320, 50), // 박스의 중앙으로 조정
        anchor: Anchor.centerRight, // 오른쪽 정렬하되 수직 중앙
      );
    }
    
    // 🍇 Draw current nerf (너프 활성화 시) - 빨간색으로 표시
    if (game.currentNerf.isNotEmpty) {
      String nerfIcon = '';
      String nerfText = '';
      String nerfDesc = '';
      
      switch (game.currentNerf) {
        case 'slow_motion':
          nerfIcon = '🐌';
          nerfText = '슬로우';
          nerfDesc = '50%감속';
          break;
        case 'jump_reduced':
          nerfIcon = '🔻';
          nerfText = '점프감소';
          nerfDesc = '60%약화';
          break;
        case 'powerup_blocked':
          nerfIcon = '🚫';
          nerfText = '왕사탕무효';
          nerfDesc = '파워업차단';
          break;
      }
      
      // 배경 박스 (반투명 빨간색)
      final bgPaint = Paint()
        ..color = const Color(0xAAFF4444)
        ..style = PaintingStyle.fill;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(145, 72, 200, 30),
          const Radius.circular(8),
        ),
        bgPaint,
      );
      
      // 테두리
      final borderPaint = Paint()
        ..color = const Color(0xFFFF0000)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(145, 72, 200, 30),
          const Radius.circular(8),
        ),
        borderPaint,
      );
      
      // 텍스트
      final nerfPaint = TextPaint(
        style: const TextStyle(
          color: Color(0xFFFFFFFF), // 흰색 (배경이 어두우니)
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
      );
      
      final timerPaint = TextPaint(
        style: const TextStyle(
          color: Color(0xFFFFFF00), // 노란색 (경고)
          fontSize: 16,
          fontWeight: FontWeight.bold,
        ),
      );
      
      // 디버프 텍스트 (박스 중앙 정렬)
      nerfPaint.render(
        canvas,
        '$nerfIcon $nerfText',
        Vector2(155, 87), // 박스의 중앙으로 조정
        anchor: Anchor.centerLeft, // 왼쪽 정렬하되 수직 중앙
      );
      
      timerPaint.render(
        canvas,
        '${game.nerfTimer.toStringAsFixed(1)}s',
        Vector2(335, 87), // 박스의 중앙으로 조정
        anchor: Anchor.centerRight, // 오른쪽 정렬하되 수직 중앙
      );
    }

    // Draw health
    final healthText = '❤️' * game.health;
    textPaint.render(
      canvas,
      healthText,
      Vector2(10, 100),
    );
    
    // ⏸️ 일시정지 버튼 (모바일 - 하트 아래)
    if (!game.gameOver) {
      final pauseButtonRect = Rect.fromLTWH(10, 130, 40, 40);
      final pauseButtonPaint = Paint()
        ..color = Colors.white.withValues(alpha: 0.3)
        ..style = PaintingStyle.fill;
      canvas.drawRRect(
        RRect.fromRectAndRadius(pauseButtonRect, const Radius.circular(8)),
        pauseButtonPaint,
      );
      
      // 일시정지 아이콘
      final iconPaint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.fill;
      if (game.isPaused) {
        // 재생 아이콘 (삼각형)
        final playPath = Path()
          ..moveTo(22, 140)
          ..lineTo(22, 160)
          ..lineTo(38, 150)
          ..close();
        canvas.drawPath(playPath, iconPaint);
      } else {
        // 일시정지 아이콘 (두 막대)
        canvas.drawRect(Rect.fromLTWH(18, 140, 6, 20), iconPaint);
        canvas.drawRect(Rect.fromLTWH(30, 140, 6, 20), iconPaint);
      }
    }
    
    // 📖 튜토리얼 (우측 상단)
    if (game.showTutorial && !game.gameOver && !game.isPaused) {
      final tutorialPaint = TextPaint(
        style: const TextStyle(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
      );
      
      final tutorialBg = Paint()
        ..color = Colors.black.withValues(alpha: 0.6);
      
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(game.size.x - 220, 10, 210, 100),
          const Radius.circular(10),
        ),
        tutorialBg,
      );
      
      tutorialPaint.render(canvas, '위로: 4단까지 점프 가능', Vector2(game.size.x - 210, 20));
      tutorialPaint.render(canvas, '아래로: 빠른 낙하', Vector2(game.size.x - 210, 50));
      tutorialPaint.render(canvas, '방향키: 앞, 뒤 이동', Vector2(game.size.x - 210, 80));
    }
    
    // 📱 모바일 컨트롤 (우하단 점프 버튼)
    if (!game.gameOver && !game.isPaused) {
      // 점프 버튼 (우하단)
      final jumpButtonPaint = Paint()
        ..color = Colors.white.withValues(alpha: 0.3)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(
        Offset(game.size.x - 60, game.size.y - 60),
        40,
        jumpButtonPaint,
      );
      
      final jumpTextPaint = TextPaint(
        style: const TextStyle(
          color: Colors.white,
          fontSize: 20, // 16 -> 20 (더 크게)
          fontWeight: FontWeight.bold,
        ),
      );
      // 텍스트를 원의 중앙에 배치 (anchor를 center로 설정)
      jumpTextPaint.render(
        canvas, 
        '점프', 
        Vector2(game.size.x - 60, game.size.y - 60),
        anchor: Anchor.center, // 중앙 정렬
      );
      
      // 방향키 (좌하단) - 더 모여있는 디자인
      final buttonRadius = 30.0; // 버튼 반지름
      final buttonGap = 15.0; // 버튼 사이 간격 (줄였음: 120 -> 15)
      final dpadCenterX = 70.0; // D-pad 중심 X
      final dpadCenterY = game.size.y - 70.0; // D-pad 중심 Y
      
      final dpadPaint = Paint()
        ..color = Colors.white.withValues(alpha: 0.25)
        ..style = PaintingStyle.fill;
      
      final arrowPaint = Paint()..color = Colors.white;
      
      // 위 버튼
      final upButtonY = dpadCenterY - buttonRadius - buttonGap;
      canvas.drawCircle(Offset(dpadCenterX, upButtonY), buttonRadius, dpadPaint);
      final upArrow = Path()
        ..moveTo(dpadCenterX, upButtonY - 12)
        ..lineTo(dpadCenterX - 10, upButtonY + 6)
        ..lineTo(dpadCenterX + 10, upButtonY + 6)
        ..close();
      canvas.drawPath(upArrow, arrowPaint);
      
      // 아래 버튼
      final downButtonY = dpadCenterY + buttonRadius + buttonGap;
      canvas.drawCircle(Offset(dpadCenterX, downButtonY), buttonRadius, dpadPaint);
      final downArrow = Path()
        ..moveTo(dpadCenterX, downButtonY + 12)
        ..lineTo(dpadCenterX - 10, downButtonY - 6)
        ..lineTo(dpadCenterX + 10, downButtonY - 6)
        ..close();
      canvas.drawPath(downArrow, arrowPaint);
      
      // 왼쪽 버튼
      final leftButtonX = dpadCenterX - buttonRadius - buttonGap;
      canvas.drawCircle(Offset(leftButtonX, dpadCenterY), buttonRadius, dpadPaint);
      final leftArrow = Path()
        ..moveTo(leftButtonX - 12, dpadCenterY)
        ..lineTo(leftButtonX + 6, dpadCenterY - 10)
        ..lineTo(leftButtonX + 6, dpadCenterY + 10)
        ..close();
      canvas.drawPath(leftArrow, arrowPaint);
      
      // 오른쪽 버튼
      final rightButtonX = dpadCenterX + buttonRadius + buttonGap;
      canvas.drawCircle(Offset(rightButtonX, dpadCenterY), buttonRadius, dpadPaint);
      final rightArrow = Path()
        ..moveTo(rightButtonX + 12, dpadCenterY)
        ..lineTo(rightButtonX - 6, dpadCenterY - 10)
        ..lineTo(rightButtonX - 6, dpadCenterY + 10)
        ..close();
      canvas.drawPath(rightArrow, arrowPaint);
    }
    
    // ⏸️ 일시정지 화면
    if (game.isPaused) {
      final width = game.size.x;
      final height = game.size.y;
      
      final overlayPaint = Paint()..color = Colors.black.withValues(alpha: 0.7);
      canvas.drawRect(
        Rect.fromLTWH(0, 0, width, height),
        overlayPaint,
      );
      
      final pausedPaint = TextPaint(
        style: const TextStyle(
          color: Colors.white,
          fontSize: 48,
          fontWeight: FontWeight.bold,
        ),
      );
      
      pausedPaint.render(canvas, '일시정지', Vector2(width / 2 - 100, height / 2 - 50));
      
      final instructionPaint = TextPaint(
        style: const TextStyle(
          color: Colors.white,
          fontSize: 20,
        ),
      );
      
      instructionPaint.render(canvas, 'ESC 또는 일시정지 버튼을 눌러 재개', Vector2(width / 2 - 180, height / 2 + 20));
    }

    // ✅ 게임 오버 화면은 GameOverOverlay에서 렌더링됨 (터치 이벤트를 확실하게 받기 위함)
  }

  @override
  void update(double dt) {
    super.update(dt);
    
    final game = findGame()! as BlackCatDeliveryGame;
    
    // 📋 안내 화면이 표시 중이면 게임 컨트롤 무시
    if (game.showInstructions) return;
    
    // 🕹️ 버튼을 누르고 있으면 계속 이동
    if (!game.gameOver && !game.isPaused) {
      if (isPressingLeft) {
        game.player.moveLeft();
      }
      if (isPressingRight) {
        game.player.moveRight();
      }
      if (isPressingUp) {
        // 위 버튼은 점프이므로 한 번만 실행 (연속 점프 방지)
        // 이미 onTapDown에서 처리됨
      }
      if (isPressingDown) {
        game.player.fastFall();
      }
    }
  }
  
  @override
  void onTapDown(TapDownEvent event) {
    final game = findGame()! as BlackCatDeliveryGame;
    
    // 🔥 Release 빌드에서도 출력
    print('👆 GameUI.onTapDown: gameOver=${game.gameOver}, leaderboard=${game.showLeaderboard}');
    
    // 🚨 CRITICAL: 게임 오버, 리더보드, 닉네임 입력 시에는 GameUI가 터치를 완전히 무시!
    if (game.gameOver || game.showLeaderboard || game.showNicknameInput) {
      print('👆 GameUI ignoring touch - overlay active');
      return;
    }
    
    final tapPos = event.localPosition;
    
    // 📋 안내 화면이 표시 중이면 GameUI 터치 무시 (InstructionsOverlay가 처리)
    if (game.showInstructions) {
      return;
    }
    
    // 🎵 첫 탭에서 음악 시작
    game._startBackgroundMusic();
    
    // 튜토리얼 닫기
    if (game.showTutorial) {
      game.showTutorial = false;
      return;
    }
    
    // 일시정지 버튼 (10, 130, 40, 40)
    if (!game.gameOver && tapPos.x >= 10 && tapPos.x <= 50 && 
        tapPos.y >= 130 && tapPos.y <= 170) {
      game.togglePause();
      return;
    }
    
    // 일시정지 중이면 다른 입력 무시
    if (game.isPaused) return;
    
    if (!game.gameOver) {
      final width = game.size.x;
      final height = game.size.y;
      
      // 점프 버튼 (우하단)
      final jumpX = width - 60;
      final jumpY = height - 60;
      final distToJump = math.sqrt(
        math.pow(tapPos.x - jumpX, 2) + math.pow(tapPos.y - jumpY, 2)
      );
      if (distToJump <= 40) {
        game.player.jump();
        return;
      }
      
      // 방향키 (더 모여있는 디자인)
      final buttonRadius = 30.0;
      final buttonGap = 15.0;
      final dpadCenterX = 70.0;
      final dpadCenterY = height - 70.0;
      
      // 위 버튼 (점프로도 동작)
      final upButtonY = dpadCenterY - buttonRadius - buttonGap;
      final distToUp = math.sqrt(
        math.pow(tapPos.x - dpadCenterX, 2) + 
        math.pow(tapPos.y - upButtonY, 2)
      );
      if (distToUp <= buttonRadius) {
        game.player.jump();
        return;
      }
      
      // 아래 버튼
      final downButtonY = dpadCenterY + buttonRadius + buttonGap;
      final distToDown = math.sqrt(
        math.pow(tapPos.x - dpadCenterX, 2) + 
        math.pow(tapPos.y - downButtonY, 2)
      );
      if (distToDown <= buttonRadius) {
        game.player.fastFall();
        return;
      }
      
      // 왼쪽 버튼 (누르고 있으면 계속 이동)
      final leftButtonX = dpadCenterX - buttonRadius - buttonGap;
      final distToLeft = math.sqrt(
        math.pow(tapPos.x - leftButtonX, 2) + 
        math.pow(tapPos.y - dpadCenterY, 2)
      );
      if (distToLeft <= buttonRadius) {
        isPressingLeft = true;
        game.player.moveLeft();
        return;
      }
      
      // 오른쪽 버튼 (누르고 있으면 계속 이동)
      final rightButtonX = dpadCenterX + buttonRadius + buttonGap;
      final distToRight = math.sqrt(
        math.pow(tapPos.x - rightButtonX, 2) + 
        math.pow(tapPos.y - dpadCenterY, 2)
      );
      if (distToRight <= buttonRadius) {
        isPressingRight = true;
        game.player.moveRight();
        return;
      }
    }
  }
  
  @override
  void onTapUp(TapUpEvent event) {
    // 터치를 떼면 모든 버튼 상태 해제
    isPressingLeft = false;
    isPressingRight = false;
    isPressingUp = false;
    isPressingDown = false;
  }
  
  @override
  void onTapCancel(TapCancelEvent event) {
    // 터치가 취소되면 모든 버튼 상태 해제
    isPressingLeft = false;
    isPressingRight = false;
    isPressingUp = false;
    isPressingDown = false;
  }
}

// 🍭 Mega Candy Component (왕사탕)
class MegaCandy extends SpriteComponent with CollisionCallbacks {
  final double speed;
  
  // 🧲 자석 효과 관련 변수
  bool isBeingAttracted = false;
  Vector2? targetPosition;

  MegaCandy({
    required super.position,
    required this.speed,
  }) : super(
          size: Vector2(60, 60), // 일반 사탕(30x30)보다 2배 크기!
          anchor: Anchor.center,
        );

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    
    // 🍭 왕사탕 이미지 로드
    try {
      final gameEngine = parent as BlackCatDeliveryGame;
      final megaCandyImage = gameEngine.images.fromCache('mega_candy');
      sprite = Sprite(megaCandyImage);
      
      // 투명도 보존을 위한 Paint 설정
      paint = Paint()
        ..filterQuality = FilterQuality.high
        ..isAntiAlias = true;
      
      if (kDebugMode) {
        debugPrint('🍭 Mega candy sprite loaded with transparency!');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Failed to load mega candy sprite: $e');
      }
    }
    
    // 왕사탕은 크므로 CircleHitbox 사용
    add(CircleHitbox(
      radius: size.x * 0.4,
      position: Vector2(size.x * 0.1, size.y * 0.1),
    ));
  }

  // 🧲 자석 효과 활성화
  void attractToPlayer(Vector2 playerPos) {
    isBeingAttracted = true;
    // targetPosition은 초기화만 하고, update에서 실시간으로 플레이어 추적
  }

  @override
  void update(double dt) {
    super.update(dt);
    
    // 🧲 자석 효과가 활성화되면 플레이어 쪽으로 빠르게 이동
    if (isBeingAttracted) {
      final game = findGame()! as BlackCatDeliveryGame;
      
      // 🎯 실시간으로 플레이어 위치 추적 (고정된 위치가 아님!)
      final playerPos = game.player.position;
      final direction = playerPos - position;
      final distance = direction.length;
      
      if (distance > 10) {
        // 플레이어 쪽으로 빠르게 이동 (실시간 추적)
        direction.normalize();
        position += direction * 1200 * dt; // 매우 빠른 속도로 추적
      } else {
        // 플레이어에게 도달하면 제거 (자동 수집)
        game.collectMegaCandy();
        removeFromParent();
      }
    } else {
      // 일반 이동
      position.x -= speed * dt;

      // 화면 밖으로 나가면 제거
      if (position.x < -50) {
        removeFromParent();
      }
    }
  }

  // SpriteComponent가 자동으로 sprite를 렌더링하므로 render 메서드 불필요
  // 투명 배경이 유지됩니다!
}

// 🔥 Fireball Projectile Component
class Fireball extends SpriteComponent with CollisionCallbacks {
  final double speed;
  
  Fireball({
    required super.position,
    required this.speed,
  }) : super(
          size: Vector2(40, 40),
          anchor: Anchor.center,
        );

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    
    // 🔥 불꽃 발사체 이미지 로드
    try {
      final gameEngine = parent as BlackCatDeliveryGame;
      final fireballImage = gameEngine.images.fromCache('fireball');
      sprite = Sprite(fireballImage);
      
      if (kDebugMode) {
        debugPrint('🔥 Fireball sprite loaded!');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Failed to load fireball sprite: $e');
      }
    }
    
    // 충돌 감지
    add(CircleHitbox(radius: size.x * 0.4));
  }

  @override
  void update(double dt) {
    super.update(dt);
    
    // 왼쪽으로 빠르게 이동
    position.x -= speed * dt;

    // 화면 밖으로 나가면 제거
    if (position.x < -100) {
      removeFromParent();
    }
  }

  @override
  void onCollision(Set<Vector2> intersectionPoints, PositionComponent other) {
    super.onCollision(intersectionPoints, other);
    
    // 플레이어와 충돌 시
    if (other is PlayerCat) {
      final game = findGame()! as BlackCatDeliveryGame;
      
      // 🦘 점프 공격: 고양이가 위에서 내려오면서 불꽃탄을 밟으면 불꽃탄만 제거!
      final isJumpAttack = other.velocityY > 0 && other.position.y < position.y;
      
      if (isJumpAttack) {
        // 위에서 밟았다! 불꽃탄만 제거하고 고양이는 안전
        game.killMonster(); // 🎯 몬스터 처치 카운트 & 점수 추가
        
        // 💥 폭발 이펙트
        game.add(ExplosionEffect(
          position: position.clone(),
        ));
        
        removeFromParent();
        // 작은 점프 효과
        other.velocityY = other.jumpStrength * 0.5;
        if (kDebugMode) debugPrint('🦘🔥 Jump attack on Fireball! Fireball destroyed!');
      } else {
        // 옆이나 아래에서 충돌 - 일반 충돌 처리
        if (!game.isInvincible) {
          game.takeDamage();
          removeFromParent();
          
          if (kDebugMode) {
            debugPrint('🔥 Fireball hit player! Health: ${game.health}');
          }
        } else {
          // 무적 상태에서는 불꽃탄만 제거
          removeFromParent();
          if (kDebugMode) {
            debugPrint('⭐ Fireball ignored - Invincible!');
          }
        }
      }
    }
  }
}

// 🎃 Scarecrow Boss Component
class ScarecrowBoss extends SpriteComponent with CollisionCallbacks {
  final double gameSpeed;
  
  // Boss behavior
  double velocityY = 0;
  final double gravity = 980;
  final double jumpStrength = -700; // 2 levels high (higher than player)
  bool isOnGround = true;
  double groundY = 0;
  double jumpTimer = 0;
  final double jumpInterval = 2.0; // Jump every 2 seconds
  bool hasFiredThisJump = false; // Fire only once per jump
  
  ScarecrowBoss({
    required Vector2 position,
    required this.gameSpeed,
  }) : super(
    position: position,
    size: Vector2(360, 405), // 300% size (120x135 * 3)
    anchor: Anchor.center,
  );

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    groundY = position.y;
    
    // 🎃 Load scarecrow sprite
    try {
      final gameEngine = parent as BlackCatDeliveryGame;
      final scarecrowImage = gameEngine.images.fromCache('scarecrow');
      sprite = Sprite(scarecrowImage);
      
      // Transparency preservation
      paint = Paint()
        ..filterQuality = FilterQuality.high
        ..isAntiAlias = true;
      
      if (kDebugMode) {
        debugPrint('🎃 Scarecrow Boss sprite loaded with transparency!');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Failed to load scarecrow boss sprite: $e');
      }
    }
    
    // Boss hitbox (larger than normal obstacles)
    add(RectangleHitbox(
      size: Vector2(size.x * 0.5, size.y * 0.6),
      position: Vector2(size.x * 0.25, size.y * 0.2),
    ));
  }

  @override
  void update(double dt) {
    super.update(dt);
    
    final game = findGame()! as BlackCatDeliveryGame;
    
    // Move forward
    position.x -= gameSpeed * 0.8 * dt; // Slightly slower than normal obstacles
    
    // Apply gravity
    velocityY += gravity * dt;
    position.y += velocityY * dt;
    
    // Ground collision
    if (position.y >= groundY) {
      position.y = groundY;
      velocityY = 0;
      isOnGround = true;
      hasFiredThisJump = false; // Reset firing flag when landing
    } else {
      isOnGround = false;
    }
    
    // Jump timer
    jumpTimer += dt;
    if (jumpTimer >= jumpInterval && isOnGround) {
      jumpTimer = 0;
      velocityY = jumpStrength;
      isOnGround = false;
      
      if (kDebugMode) {
        debugPrint('🎃 Boss jumped!');
      }
    }
    
    // Fire 2 fireballs when airborne (only once per jump)
    if (!isOnGround && !hasFiredThisJump && velocityY > -500) {
      hasFiredThisJump = true;
      _shootTwoFireballs();
    }
    
    // Remove boss when off-screen and reset boss state
    if (position.x < -200) {
      game.isBossActive = false;
      // 🎵 보스 퇴장 - 정상 음악으로 복귀
      game._resumeNormalMusic();
      removeFromParent();
      if (kDebugMode) {
        debugPrint('🎃 Boss passed! Normal obstacles will resume.');
      }
    }
  }
  
  // 🔥 Fire 2 fireballs simultaneously
  void _shootTwoFireballs() {
    final gameEngine = parent as BlackCatDeliveryGame;
    
    // Fireball 1: Slightly upward angle
    gameEngine.add(Fireball(
      position: position.clone() + Vector2(-50, -30),
      speed: 450.0,
    ));
    
    // Fireball 2: Slightly downward angle
    gameEngine.add(Fireball(
      position: position.clone() + Vector2(-50, 30),
      speed: 450.0,
    ));
    
    if (kDebugMode) {
      debugPrint('🎃🔥 Boss fired 2 fireballs!');
    }
  }

  @override
  void onCollision(Set<Vector2> intersectionPoints, PositionComponent other) {
    super.onCollision(intersectionPoints, other);
    
    // Boss collision with player
    if (other is PlayerCat) {
      final game = findGame()! as BlackCatDeliveryGame;
      
      // 🦘 점프 공격: 고양이가 위에서 내려오면서 보스를 밟으면 보스 제거!
      final isJumpAttack = other.velocityY > 0 && other.position.y < position.y;
      
      if (isJumpAttack) {
        // 위에서 밟았다! 보스 처치 성공!
        game.killMonster(isBoss: true); // 🎯 보스 처치! 100점 추가
        
        // 💥 큰 폭발 이펙트 (보스는 더 크게!)
        game.add(ExplosionEffect(
          position: position.clone(),
          isBossExplosion: true,
        ));
        
        // 🎵 보스 폭발 효과음 (왕사탕 효과음 재사용 - 풀에서 재생)
        game._playFromPool(game.megaCandySoundPool, 'audio/mega_candy_powerup.mp3');
        
        game.isBossActive = false;
        game._resumeNormalMusic(); // 보스 음악 종료, 일반 음악으로
        removeFromParent();
        // 큰 점프 효과 (보스 밟기는 더 통쾌!)
        other.velocityY = other.jumpStrength * 0.7;
        if (kDebugMode) debugPrint('🦘🎃 Jump attack on BOSS! Boss defeated! +100 points!');
      } else {
        // 옆이나 아래에서 충돌 - 일반 충돌 처리
        if (!game.isInvincible) {
          game.takeDamage();
          if (kDebugMode) debugPrint('🎃 Boss hit player! Health: ${game.health}');
        } else {
          if (kDebugMode) debugPrint('⭐ Boss collision ignored - Invincible!');
        }
      }
    }
  }
}

// 🔥 Player Fireball Component (분노 모드 자동 공격)
class PlayerFireball extends SpriteComponent with CollisionCallbacks {
  final double speed;
  
  PlayerFireball({
    required super.position,
    required this.speed,
  }) : super(
          size: Vector2(40, 40),
          anchor: Anchor.center,
        );

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    
    // 🔥 불꽃 발사체 이미지 로드
    try {
      final gameEngine = parent as BlackCatDeliveryGame;
      final fireballImage = gameEngine.images.fromCache('fireball');
      sprite = Sprite(fireballImage);
      
      if (kDebugMode) {
        debugPrint('🔥 Player fireball sprite loaded!');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Failed to load player fireball sprite: $e');
      }
    }
    
    // 충돌 감지
    add(CircleHitbox(radius: size.x * 0.4));
  }

  @override
  void update(double dt) {
    super.update(dt);
    
    // 오른쪽으로 빠르게 이동
    position.x += speed * dt;

    // 화면 밖으로 나가면 제거
    final game = findGame()! as BlackCatDeliveryGame;
    if (position.x > game.size.x + 100) {
      removeFromParent();
    }
  }

  @override
  void onCollision(Set<Vector2> intersectionPoints, PositionComponent other) {
    super.onCollision(intersectionPoints, other);
    
    final game = findGame()! as BlackCatDeliveryGame;
    
    // 적 장애물과 충돌 시
    if (other is Obstacle) {
      game.killMonster();
      
      // 💥 폭발 효과
      game.add(ExplosionEffect(
        position: position.clone(),
      ));
      
      // 몬스터 제거
      other.removeFromParent();
      removeFromParent();
      
      if (kDebugMode) debugPrint('🔥 Player fireball hit obstacle!');
    } else if (other is ScarecrowBoss) {
      game.killMonster(isBoss: true);
      
      // 💥 보스 폭발 효과
      game.add(ExplosionEffect(
        position: position.clone(),
        isBossExplosion: true,
      ));
      
      game.isBossActive = false;
      game._resumeNormalMusic();
      other.removeFromParent();
      removeFromParent();
      
      if (kDebugMode) debugPrint('🔥 Player fireball destroyed BOSS!');
    } else if (other is Fireball) {
      // 적 불꽃탄과 상쇄
      other.removeFromParent();
      removeFromParent();
      
      if (kDebugMode) debugPrint('🔥 Player fireball cancelled enemy fireball!');
    }
  }
}

// 💥 Explosion Effect Component (몬스터 처치 시 폭발 효과)
class ExplosionEffect extends PositionComponent {
  final bool isBossExplosion;
  double lifetime = 0.0;
  final double maxLifetime = 0.5; // 0.5초 동안 표시
  
  ExplosionEffect({
    required Vector2 position,
    this.isBossExplosion = false,
  }) : super(
    position: position,
    size: isBossExplosion ? Vector2(200, 200) : Vector2(100, 100), // 보스는 2배 크기
    anchor: Anchor.center,
  );
  
  @override
  void update(double dt) {
    super.update(dt);
    
    lifetime += dt;
    if (lifetime >= maxLifetime) {
      removeFromParent();
    }
  }
  
  @override
  void render(Canvas canvas) {
    super.render(canvas);
    
    // 폭발 애니메이션 (시간에 따라 크기와 투명도 변화)
    final progress = lifetime / maxLifetime;
    final scale = 0.5 + (progress * 1.5); // 0.5배 → 2배로 커짐
    final opacity = 1.0 - progress; // 점점 투명해짐
    
    // 외부 원 (주황색)
    final outerPaint = Paint()
      ..color = Color.fromARGB(
        (opacity * 200).toInt(),
        255, 100, 0, // 주황색
      )
      ..style = PaintingStyle.fill;
    canvas.drawCircle(
      Offset(size.x / 2, size.y / 2),
      size.x / 2 * scale,
      outerPaint,
    );
    
    // 중간 원 (노란색)
    final middlePaint = Paint()
      ..color = Color.fromARGB(
        (opacity * 220).toInt(),
        255, 200, 0, // 노란색
      )
      ..style = PaintingStyle.fill;
    canvas.drawCircle(
      Offset(size.x / 2, size.y / 2),
      size.x / 3 * scale,
      middlePaint,
    );
    
    // 내부 원 (흰색 섬광)
    final innerPaint = Paint()
      ..color = Color.fromARGB(
        (opacity * 255).toInt(),
        255, 255, 255, // 흰색
      )
      ..style = PaintingStyle.fill;
    canvas.drawCircle(
      Offset(size.x / 2, size.y / 2),
      size.x / 5 * scale,
      innerPaint,
    );
    
    // 보스 폭발은 추가 효과 (빛나는 별 효과)
    if (isBossExplosion) {
      final starPaint = Paint()
        ..color = Color.fromARGB(
          (opacity * 255).toInt(),
          255, 255, 0,
        )
        ..style = PaintingStyle.fill;
      
      // 8방향 별 효과
      for (int i = 0; i < 8; i++) {
        final angle = (i * math.pi / 4) + (progress * math.pi * 2);
        final distance = size.x / 2 * scale * 1.2;
        final x = size.x / 2 + math.cos(angle) * distance;
        final y = size.y / 2 + math.sin(angle) * distance;
        
        // 큰 별 그리기
        final path = Path();
        for (int j = 0; j < 5; j++) {
          final starAngle = (j * 2 * math.pi / 5) - math.pi / 2;
          final radius = j.isEven ? 20.0 * scale : 10.0 * scale;
          final px = x + math.cos(starAngle) * radius;
          final py = y + math.sin(starAngle) * radius;
          if (j == 0) {
            path.moveTo(px, py);
          } else {
            path.lineTo(px, py);
          }
        }
        path.close();
        canvas.drawPath(path, starPaint);
      }
    }
  }
}

// 📋 게임 시작 안내 화면 (Instructions Overlay)
class InstructionsOverlay extends PositionComponent with TapCallbacks {
  @override
  Future<void> onLoad() async {
    await super.onLoad();
    
    // 전체 화면 크기로 설정
    final game = findGame()! as BlackCatDeliveryGame;
    size = game.size.clone();
    position = Vector2.zero();
    priority = 1000; // 최상위 레이어
  }
  
  @override
  void render(Canvas canvas) {
    super.render(canvas);
    
    final game = findGame()! as BlackCatDeliveryGame;
    
    // 안내 화면이 표시되지 않으면 컴포넌트 제거
    if (!game.showInstructions) {
      if (parent != null) {
        removeFromParent();
        if (kDebugMode) debugPrint('📋 InstructionsOverlay auto-removed');
      }
      return;
    }
    
    // 🎨 반투명 검은색 배경
    final bgPaint = Paint()..color = const Color(0xDD000000);
    canvas.drawRect(size.toRect(), bgPaint);
    
    // 📏 화면 중앙 계산
    final centerX = size.x / 2;
    final centerY = size.y / 2;
    
    // 🌙 제목 텍스트
    final titlePainter = TextPainter(
      text: TextSpan(
        text: '🌙 달빛 배달부 루나 🌙',
        style: TextStyle(
          color: const Color(0xFFFFAA00),
          fontSize: math.min(size.x * 0.06, 48),
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    titlePainter.layout();
    final titleY = centerY - size.y * 0.25;
    titlePainter.paint(
      canvas,
      Offset(centerX - titlePainter.width / 2, titleY),
    );
    
    // 📧 문의 이메일 (제목 바로 아래, 충분한 간격)
    final contactPainter = TextPainter(
      text: TextSpan(
        text: '문의 : lascod@naver.com',
        style: TextStyle(
          color: Colors.white70,
          fontSize: math.min(size.x * 0.025, 18),
          fontWeight: FontWeight.w400,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    contactPainter.layout();
    // 제목 높이를 고려하여 바로 아래 배치 (간격 추가)
    final contactY = titleY + titlePainter.height + 12;
    contactPainter.paint(
      canvas,
      Offset(centerX - contactPainter.width / 2, contactY),
    );
    
    // 📋 안내 문구들
    final instructions = [
      '🎮 조작법',
      '• 상하좌우 이동 / 최대 4단점프',
      '  아래 버튼: 빠른 낙하',
      '• 몬스터 머리 밟기: 제거',
      '• 빨간사탕: 20개당 목숨 1+',
      '• 보라사탕: 랜덤 디버프',
      '• 왕사탕: 랜덤 버프',
    ];
    
    // 📝 안내문 렌더링
    double yOffset = centerY - size.y * 0.08;
    final lineHeight = math.min(size.x * 0.05, 36);
    
    for (final instruction in instructions) {
      final instructionPainter = TextPainter(
        text: TextSpan(
          text: instruction,
          style: TextStyle(
            color: Colors.white,
            fontSize: math.min(size.x * 0.032, 24),
            fontWeight: FontWeight.w500,
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      instructionPainter.layout(maxWidth: size.x * 0.85);
      instructionPainter.paint(
        canvas,
        Offset(centerX - instructionPainter.width / 2, yOffset),
      );
      yOffset += lineHeight;
    }
    
    // 🖱️ 터치 유도 문구 (애니메이션 효과)
    final time = DateTime.now().millisecondsSinceEpoch / 1000;
    final opacity = (math.sin(time * 2) * 0.3 + 0.7).clamp(0.0, 1.0);
    
    final tapPainter = TextPainter(
      text: TextSpan(
        text: '화면을 터치하여 시작하세요!',
        style: TextStyle(
          color: Color.fromRGBO(255, 170, 0, opacity),
          fontSize: math.min(size.x * 0.045, 32),
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    tapPainter.layout();
    tapPainter.paint(
      canvas,
      Offset(centerX - tapPainter.width / 2, centerY + size.y * 0.22),
    );
  }
  
  @override
  void onTapDown(TapDownEvent event) {
    final game = findGame()! as BlackCatDeliveryGame;
    
    // 안내 화면이 표시 중일 때만 게임 시작
    if (game.showInstructions) {
      game.startGame();
      if (kDebugMode) debugPrint('📋 Instructions dismissed - Game started!');
      // render 메서드에서 자동으로 제거됨
    }
  }
}


// ========================================
// 🎮 Flutter 위젯 오버레이 (게임 오버, 리더보드, 닉네임 입력)
// ========================================

// 💀 게임 오버 화면 위젯
class GameOverOverlayWidget extends StatefulWidget {
  final BlackCatDeliveryGame game;
  
  const GameOverOverlayWidget({super.key, required this.game});
  
  @override
  State<GameOverOverlayWidget> createState() => _GameOverOverlayWidgetState();
}

class _GameOverOverlayWidgetState extends State<GameOverOverlayWidget> {
  Map<String, dynamic>? globalStats;
  bool isLoadingStats = true;
  
  @override
  void initState() {
    super.initState();
    _loadGlobalStats();
  }
  
  Future<void> _loadGlobalStats() async {
    try {
      final stats = await widget.game.getGlobalStats();
      if (mounted) {
        setState(() {
          globalStats = stats;
          isLoadingStats = false;
        });
      }
    } catch (e) {
      print('❌ Failed to load global stats: $e');
      if (mounted) {
        setState(() {
          isLoadingStats = false;
        });
      }
    }
  }
  
  @override
  Widget build(BuildContext context) {
    print('💀 GameOverOverlayWidget.build() CALLED!');
    
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;
    
    return Stack(
      children: [
        // 배경 (터치 방지 - 버튼만 터치 가능하게)
        Positioned.fill(
          child: Container(
            color: Colors.black.withValues(alpha: 0.8),
          ),
        ),
        // UI 컨텐츠 - 위로 배치
        SingleChildScrollView(
          child: Container(
            height: screenHeight,
            padding: EdgeInsets.only(
              top: screenHeight * 0.08, // 상단 여백 줄임 (15% → 8%)
              left: 20,
              right: 20,
              bottom: screenHeight * 0.15, // 하단 여백 (버튼 공간 확보)
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                // 게임오버 텍스트 (크기 대폭 축소 - 한 줄로)
                const Text(
                  '💀 GAME OVER',
                  style: TextStyle(
                    color: Colors.red,
                    fontSize: 32, // 48 → 32 (대폭 축소)
                    fontWeight: FontWeight.bold,
                    shadows: [
                      Shadow(
                        color: Colors.black,
                        offset: Offset(2, 2),
                        blurRadius: 4,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 15), // 간격 줄임
                // 점수 정보
                Text(
                  '최종 점수: ${widget.game.score}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 10), // 간격 줄임
                Text(
                  '수집한 사탕: ${widget.game.candies} 🍬',
                  style: const TextStyle(
                    color: Colors.orange,
                    fontSize: 20,
                  ),
                ),
                const SizedBox(height: 18), // 간격 줄임
                // 글로벌 통계 표시
                if (isLoadingStats)
                  const CircularProgressIndicator(color: Colors.yellow)
                else if (globalStats != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12), // 패딩 줄임
                    margin: const EdgeInsets.symmetric(horizontal: 25),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.yellow, width: 2),
                    ),
                    child: Column(
                      children: [
                        if (globalStats!['my_rank'] > 0) ...[
                          Text(
                            '🏆 글로벌 순위: #${globalStats!['my_rank']} / ${globalStats!['total_players']}',
                            style: const TextStyle(
                              color: Colors.yellow,
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 5),
                          Text(
                            '📊 상위 ${globalStats!['top_percentage']}%의 플레이어입니다!',
                            style: const TextStyle(
                              color: Colors.greenAccent,
                              fontSize: 15,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 8),
                        ],
                        Text(
                          '📈 오늘 플레이: ${globalStats!['today_players']}명',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '📊 누적 플레이: ${globalStats!['total_players']}명',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 12),
                        // 🍗 매월 1등 치킨 쿠폰 안내
                        const Text(
                          '🍗 매 월 1등 치킨 쿠폰 이메일 발송',
                          style: TextStyle(
                            color: Color(0xFFFFD700), // 골드 컬러
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ],
                const Spacer(), // 남은 공간 차지
              ],
            ),
          ),
        ),
        // 하단 버튼들 (고정 위치)
        Positioned(
          left: 20,
          right: 20,
          bottom: screenHeight * 0.08, // 하단에서 8% 위치
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // 좌측: 다시하기 버튼
              Expanded(
                child: ElevatedButton(
                  onPressed: () {
                    print('🔄 Restart button pressed!');
                    widget.game.overlays.remove('gameOver');
                    widget.game.resetGame();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4CAF50),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    '🔄 다시하기',
                    style: TextStyle(
                      fontSize: 20,
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 20),
              // 우측: 랭킹보기 버튼
              Expanded(
                child: ElevatedButton(
                  onPressed: () {
                    print('🏆 Leaderboard button pressed!');
                    widget.game.overlays.remove('gameOver');
                    widget.game.overlays.add('leaderboard');
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6B4FA0),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    '🏆 랭킹보기',
                    style: TextStyle(
                      fontSize: 20,
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// 🏆 리더보드 화면 위젯
class LeaderboardOverlayWidget extends StatefulWidget {
  final BlackCatDeliveryGame game;
  
  const LeaderboardOverlayWidget({super.key, required this.game});
  
  @override
  State<LeaderboardOverlayWidget> createState() => _LeaderboardOverlayWidgetState();
}

class _LeaderboardOverlayWidgetState extends State<LeaderboardOverlayWidget> {
  List<Map<String, dynamic>> topScores = [];
  bool isLoading = true;
  
  @override
  void initState() {
    super.initState();
    print('🏆 LeaderboardOverlayWidget.initState() CALLED!');
    _loadLeaderboard();
  }
  
  Future<void> _loadLeaderboard() async {
    try {
      print('🏆 Loading leaderboard data...');
      print('🔥 Firebase initialized: $_isFirebaseInitialized');
      
      final scores = await widget.game.getTopScores(limit: 10);
      
      if (mounted) {
        setState(() {
          topScores = scores;
          isLoading = false;
        });
      }
      
      print('🏆 Leaderboard loaded: ${topScores.length} entries');
      if (topScores.isNotEmpty) {
        print('🏆 First entry: ${topScores[0]}');
      }
    } catch (e) {
      print('❌ Failed to load leaderboard: $e');
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }
  
  @override
  Widget build(BuildContext context) {
    print('🏆 LeaderboardOverlayWidget.build() CALLED! isLoading=$isLoading');
    
    return GestureDetector(
      onTapDown: (details) {
        final tapY = details.localPosition.dy;
        
        // 상단 X 버튼 영역
        if (tapY < 100) {
          print('❌ Close button tapped!');
          widget.game.overlays.remove('leaderboard');
          widget.game.overlays.add('gameOver');
          return;
        }
      },
      child: Container(
        color: Colors.black.withValues(alpha: 0.9),
        child: SafeArea(
          child: Column(
            children: [
              // 헤더
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // ID 표시 (리더보드 타이틀 대체)
                        Expanded(
                          child: Text(
                            'ID: ${widget.game.playerName}',
                            style: const TextStyle(
                              color: Colors.yellow,
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.white, size: 32),
                          onPressed: () {
                            print('❌ Close button pressed!');
                            widget.game.overlays.remove('leaderboard');
                            widget.game.overlays.add('gameOver');
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // 이메일 ID 안내
                    LayoutBuilder(
                      builder: (context, constraints) {
                        // 화면 너비에 따라 글자 크기 조정 (컴퓨터는 더 크게)
                        final screenWidth = MediaQuery.of(context).size.width;
                        final fontSize = screenWidth > 600 ? 20.0 : 14.0; // 600px 이상은 컴퓨터
                        
                        return Text(
                          '이메일 ID만 선물발송 가능',
                          style: TextStyle(
                            color: const Color(0xFFFFD700), // 골드 컬러
                            fontSize: fontSize,
                            fontWeight: FontWeight.w500,
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
              // 로딩 또는 리스트
              Expanded(
                child: isLoading
                    ? const Center(
                        child: CircularProgressIndicator(color: Colors.yellow),
                      )
                    : topScores.isEmpty
                        ? const Center(
                            child: Text(
                              '아직 기록이 없습니다',
                              style: TextStyle(color: Colors.white60, fontSize: 20),
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            itemCount: topScores.length,
                            itemBuilder: (context, index) {
                              final entry = topScores[index];
                              final rank = index + 1;
                              final name = entry['name'] ?? 'Unknown';
                              final score = entry['score'] ?? 0;
                              final candies = entry['candies'] ?? 0;
                              
                              String medal = '';
                              Color rankColor = Colors.white;
                              
                              if (rank == 1) {
                                medal = '🥇';
                                rankColor = const Color(0xFFFFD700);
                              } else if (rank == 2) {
                                medal = '🥈';
                                rankColor = const Color(0xFFC0C0C0);
                              } else if (rank == 3) {
                                medal = '🥉';
                                rankColor = const Color(0xFFCD7F32);
                              }
                              
                              return Container(
                                margin: const EdgeInsets.only(bottom: 12),
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(12),
                                  border: rank <= 3 
                                      ? Border.all(color: rankColor, width: 2)
                                      : null,
                                ),
                                child: Row(
                                  children: [
                                    SizedBox(
                                      width: 50,
                                      child: Text(
                                        medal.isNotEmpty ? medal : '#$rank',
                                        style: TextStyle(
                                          color: rankColor,
                                          fontSize: 24,
                                          fontWeight: FontWeight.bold,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            name,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 20,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          Text(
                                            '$candies 🍬',
                                            style: const TextStyle(
                                              color: Colors.orange,
                                              fontSize: 16,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Text(
                                      '$score',
                                      style: const TextStyle(
                                        color: Colors.yellow,
                                        fontSize: 24,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
              ),
              // 닉네임 변경 버튼
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: ElevatedButton(
                  onPressed: () {
                    print('✏️ Nickname input button pressed!');
                    widget.game.overlays.remove('leaderboard');
                    widget.game.overlays.add('nicknameInput');
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6B4FA0),
                    padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 12),
                  ),
                  child: const Text(
                    '✏️ 닉네임 변경',
                    style: TextStyle(fontSize: 18, color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ✏️ 닉네임 입력 화면 위젯
class NicknameInputOverlayWidget extends StatefulWidget {
  final BlackCatDeliveryGame game;
  
  const NicknameInputOverlayWidget({super.key, required this.game});
  
  @override
  State<NicknameInputOverlayWidget> createState() => _NicknameInputOverlayWidgetState();
}

class _NicknameInputOverlayWidgetState extends State<NicknameInputOverlayWidget> {
  final TextEditingController _controller = TextEditingController();
  
  @override
  void initState() {
    super.initState();
    _controller.text = widget.game.playerName;
    print('✏️ NicknameInputOverlayWidget.initState() - Current name: ${widget.game.playerName}');
  }
  
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    print('✏️ NicknameInputOverlayWidget.build() CALLED!');
    
    return GestureDetector(
      onTap: () {
        // 배경 터치 시 키보드 숨기기
        FocusScope.of(context).unfocus();
      },
      child: Container(
        color: Colors.black.withValues(alpha: 0.9),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    '✏️ 닉네임 입력',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 30),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white30),
                    ),
                    child: TextField(
                      controller: _controller,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                      ),
                      maxLength: 50, // 📧 이메일 주소 사용 가능하도록 50자로 확장
                      textAlign: TextAlign.center,
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        hintText: '닉네임 또는 이메일을 입력하세요',
                        hintStyle: TextStyle(color: Colors.white38),
                        counterStyle: TextStyle(color: Colors.white60),
                      ),
                    ),
                  ),
                  const SizedBox(height: 40),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ElevatedButton(
                        onPressed: () async {
                          if (_controller.text.isNotEmpty) {
                            print('✅ Saving nickname: ${_controller.text}');
                            await widget.game.saveNickname(_controller.text);
                            if (mounted) {
                              widget.game.overlays.remove('nicknameInput');
                              widget.game.overlays.add('leaderboard');
                            }
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF6B4FA0),
                          padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 12),
                        ),
                        child: const Text(
                          '✅ 저장',
                          style: TextStyle(fontSize: 20, color: Colors.white),
                        ),
                      ),
                      const SizedBox(width: 20),
                      ElevatedButton(
                        onPressed: () {
                          print('❌ Nickname input cancelled');
                          widget.game.overlays.remove('nicknameInput');
                          widget.game.overlays.add('leaderboard');
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.grey,
                          padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 12),
                        ),
                        child: const Text(
                          '❌ 취소',
                          style: TextStyle(fontSize: 20, color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    '※ PC에서는 키보드로 직접 입력하세요',
                    style: TextStyle(
                      color: Colors.white54,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// 🍇 Purple Nerf Candy Component
class PurpleCandy extends PositionComponent with CollisionCallbacks {
  final double speed;
  
  // 🧲 자석 효과 관련 변수
  bool isBeingAttracted = false;
  Vector2? targetPosition;

  PurpleCandy({
    required super.position,
    required this.speed,
  }) : super(
          size: Vector2(30, 30),
          anchor: Anchor.center,
        );

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    
    // 사탕은 원형이므로 CircleHitbox 사용 (더 정확한 충돌)
    add(CircleHitbox(
      radius: size.x * 0.4, // 80% 크기
      position: Vector2(size.x * 0.1, size.y * 0.1),
    ));
  }

  // 🧲 자석 효과 활성화
  void attractToPlayer(Vector2 playerPos) {
    isBeingAttracted = true;
    targetPosition = playerPos.clone();
  }

  @override
  void update(double dt) {
    super.update(dt);
    
    // 🧲 자석 효과가 활성화되면 플레이어 쪽으로 빠르게 이동
    if (isBeingAttracted && targetPosition != null) {
      final direction = targetPosition! - position;
      final distance = direction.length;
      
      if (distance > 5) {
        // 플레이어 쪽으로 빠르게 이동 (속도 증가)
        direction.normalize();
        position += direction * 800 * dt; // 매우 빠른 속도
      } else {
        // 플레이어에게 도달하면 제거 (자동 수집)
        final game = findGame()! as BlackCatDeliveryGame;
        game.collectPurpleCandy();
        removeFromParent();
      }
    } else {
      // 일반 이동
      position.x -= speed * dt;

      if (position.x < -50) {
        removeFromParent();
      }
    }
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);

    // 왼쪽 포장지 날개 (보라색)
    final leftWrapperPaint = Paint()..color = const Color(0xFF9B59B6);
    final leftWrapperPath = Path()
      ..moveTo(size.x * 0.1, size.y * 0.5)
      ..quadraticBezierTo(
        0,
        size.y * 0.3,
        size.x * 0.05,
        size.y * 0.2,
      )
      ..quadraticBezierTo(
        size.x * 0.15,
        size.y * 0.35,
        size.x * 0.3,
        size.y * 0.4,
      )
      ..lineTo(size.x * 0.3, size.y * 0.6)
      ..quadraticBezierTo(
        size.x * 0.15,
        size.y * 0.65,
        size.x * 0.05,
        size.y * 0.8,
      )
      ..quadraticBezierTo(
        0,
        size.y * 0.7,
        size.x * 0.1,
        size.y * 0.5,
      )
      ..close();
    canvas.drawPath(leftWrapperPath, leftWrapperPaint);

    // 오른쪽 포장지 날개 (보라색)
    final rightWrapperPaint = Paint()..color = const Color(0xFF9B59B6);
    final rightWrapperPath = Path()
      ..moveTo(size.x * 0.9, size.y * 0.5)
      ..quadraticBezierTo(
        size.x,
        size.y * 0.3,
        size.x * 0.95,
        size.y * 0.2,
      )
      ..quadraticBezierTo(
        size.x * 0.85,
        size.y * 0.35,
        size.x * 0.7,
        size.y * 0.4,
      )
      ..lineTo(size.x * 0.7, size.y * 0.6)
      ..quadraticBezierTo(
        size.x * 0.85,
        size.y * 0.65,
        size.x * 0.95,
        size.y * 0.8,
      )
      ..quadraticBezierTo(
        size.x,
        size.y * 0.7,
        size.x * 0.9,
        size.y * 0.5,
      )
      ..close();
    canvas.drawPath(rightWrapperPath, rightWrapperPaint);

    // 중앙 사탕 본체 (진한 보라색)
    final candyPaint = Paint()..color = const Color(0xFF8E44AD);
    canvas.drawOval(
      Rect.fromLTWH(size.x * 0.3, size.y * 0.35, size.x * 0.4, size.y * 0.3),
      candyPaint,
    );

    // 사탕 하이라이트 (빛 반사)
    final highlightPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.4)
      ..style = PaintingStyle.fill;
    canvas.drawOval(
      Rect.fromLTWH(size.x * 0.4, size.y * 0.4, size.x * 0.15, size.y * 0.1),
      highlightPaint,
    );

    // 포장지 어두운 스트라이프 (왼쪽)
    final stripePaint = Paint()
      ..color = const Color(0xFF663399)
      ..strokeWidth = 2;
    canvas.drawLine(
      Offset(size.x * 0.08, size.y * 0.35),
      Offset(size.x * 0.15, size.y * 0.45),
      stripePaint,
    );
    canvas.drawLine(
      Offset(size.x * 0.08, size.y * 0.65),
      Offset(size.x * 0.15, size.y * 0.55),
      stripePaint,
    );

    // 포장지 어두운 스트라이프 (오른쪽)
    canvas.drawLine(
      Offset(size.x * 0.92, size.y * 0.35),
      Offset(size.x * 0.85, size.y * 0.45),
      stripePaint,
    );
    canvas.drawLine(
      Offset(size.x * 0.92, size.y * 0.65),
      Offset(size.x * 0.85, size.y * 0.55),
      stripePaint,
    );
    
    // 🍇 보라색 후광 효과 (불길한 느낌)
    final glowPaint = Paint()
      ..color = const Color(0xFF8E44AD).withValues(alpha: 0.3)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
    canvas.drawCircle(
      Offset(size.x / 2, size.y / 2),
      size.x * 0.6,
      glowPaint,
    );
  }
}

// 🚫 Blocked PowerUp Effect (왕사탕 무효화 시각 효과)
class BlockedPowerUpEffect extends PositionComponent {
  double lifetime = 1.0;
  double opacity = 1.0;
  
  BlockedPowerUpEffect({required super.position})
      : super(
          size: Vector2(80, 80),
          anchor: Anchor.center,
        );

  @override
  void update(double dt) {
    super.update(dt);
    lifetime -= dt;
    opacity = lifetime.clamp(0.0, 1.0);
    
    // 위로 떠오르는 효과
    position.y -= 50 * dt;
    
    if (lifetime <= 0) {
      removeFromParent();
    }
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    
    // 🚫 빨간 X 표시
    final paint = Paint()
      ..color = Color.fromARGB((opacity * 255).toInt(), 255, 50, 50)
      ..strokeWidth = 6
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    
    // X 그리기
    canvas.drawLine(
      Offset(size.x * 0.2, size.y * 0.2),
      Offset(size.x * 0.8, size.y * 0.8),
      paint,
    );
    canvas.drawLine(
      Offset(size.x * 0.8, size.y * 0.2),
      Offset(size.x * 0.2, size.y * 0.8),
      paint,
    );
    
    // 🚫 텍스트 표시
    final textPaint = TextPaint(
      style: TextStyle(
        color: Color.fromARGB((opacity * 255).toInt(), 255, 50, 50),
        fontSize: 16,
        fontWeight: FontWeight.bold,
      ),
    );
    textPaint.render(canvas, '무효!', Vector2(size.x * 0.15, size.y + 10));
  }
}

import 'dart:convert';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'domain/yatzy_engine.dart';
import 'graphics/yatzy_game.dart';
import 'social/social_platform.dart';
import 'social/social_platform_selector.dart';

void main() {
  runApp(const OpenYatzyApp());
}

class OpenYatzyApp extends StatelessWidget {
  const OpenYatzyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'YATZY!',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.light,
        scaffoldBackgroundColor: const Color(0xFF7BB4D9), // Pastel Blue
        colorScheme: const ColorScheme.light(
          primary: Color(0xFF2196F3), // Player 1 Blue
          secondary: Color(0xFFEF5350), // Player 2 Red
          surface: Color(0xFF323846), // Dark slate card
          background: Color(0xFF7BB4D9),
        ),
        fontFamily: 'Roboto',
      ),
      home: const GameScreen(),
    );
  }
}

class GameScreen extends StatefulWidget {
  const GameScreen({super.key});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  final YatzyEngine _engine = YatzyEngine();
  final SocialPlatform _social = getSocialPlatform();
  late final YatzyGame _game;

  bool _isSocialInitialized = false;
  List<Map<String, dynamic>> _leaderboard = [];

  // Multiplayer setup state
  bool _isGameStarted = false;
  int _setupPlayerCount = 2;
  final List<TextEditingController> _nameControllers = [];
  bool _isRolling = false;
  bool _hasSavedGame = false;

  @override
  void initState() {
    super.initState();
    // Initialize 2 text controllers for names
    _nameControllers.add(TextEditingController(text: 'Player 1'));
    _nameControllers.add(TextEditingController(text: 'Player 2'));

    _game = YatzyGame(
      engine: _engine,
      onStateChanged: () {
        setState(() {
          _isRolling = _game.isAnyDieRolling();
        });
        _saveGameState();
      },
    );
    _initSocial();
    _checkSavedMatch();
  }

  @override
  void dispose() {
    for (var controller in _nameControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _initSocial() async {
    await _social.initialize();
    setState(() {
      _isSocialInitialized = true;
    });
    _refreshLeaderboard();
  }

  Future<void> _refreshLeaderboard() async {
    final list = await _social.getLeaderboard();
    setState(() {
      _leaderboard = list;
    });
  }

  Future<void> _loginSocial() async {
    final user = await _social.login();
    if (user != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Logged in as ${user.displayName}')),
      );
      _refreshLeaderboard();
      setState(() {});
    }
  }

  // Persistence methods
  Future<void> _saveGameState() async {
    if (_engine.isGameOver) {
      await _deleteSavedMatch();
      return;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      final List<Map<String, dynamic>> serializedScorecards = [];
      for (var scorecard in _engine.scorecards) {
        final Map<String, dynamic> cardMap = {};
        scorecard.forEach((category, value) {
          cardMap[category.name] = value;
        });
        serializedScorecards.add(cardMap);
      }

      final state = {
        'playerCount': _engine.playerCount,
        'playerNames': _engine.playerNames,
        'activePlayerIndex': _engine.activePlayerIndex,
        'scorecards': serializedScorecards,
        'diceValues': _engine.diceValues,
        'heldDice': _engine.heldDice,
        'rollsRemaining': _engine.rollsRemaining,
        'isGameOver': _engine.isGameOver,
      };

      await prefs.setString('saved_yatzy_match', jsonEncode(state));
      setState(() {
        _hasSavedGame = true;
      });
    } catch (e) {
      debugPrint("Error saving game state: $e");
    }
  }

  Future<void> _deleteSavedMatch() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('saved_yatzy_match');
      setState(() {
        _hasSavedGame = false;
      });
    } catch (e) {
      debugPrint("Error deleting saved match: $e");
    }
  }

  Future<void> _checkSavedMatch() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final hasSaved = prefs.containsKey('saved_yatzy_match');
      setState(() {
        _hasSavedGame = hasSaved;
      });
    } catch (e) {
      debugPrint("Error checking saved match: $e");
    }
  }

  Future<bool> _loadGameState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final serialized = prefs.getString('saved_yatzy_match');
      if (serialized == null) return false;

      final state = jsonDecode(serialized) as Map<String, dynamic>;
      final isGameOver = state['isGameOver'] as bool;
      if (isGameOver) {
        await _deleteSavedMatch();
        return false;
      }

      final playerCount = state['playerCount'] as int;
      final playerNames = List<String>.from(state['playerNames'] as List);
      final activePlayerIndex = state['activePlayerIndex'] as int;
      final rollsRemaining = state['rollsRemaining'] as int;
      final diceValues = List<int>.from(state['diceValues'] as List);
      final heldDice = List<bool>.from(state['heldDice'] as List);

      final List<Map<ScoringCategory, int?>> scorecards = [];
      final listScorecards = state['scorecards'] as List;
      for (var cardObj in listScorecards) {
        final cardMap = cardObj as Map<String, dynamic>;
        final Map<ScoringCategory, int?> scorecard = {};
        for (var category in ScoringCategory.values) {
          if (cardMap.containsKey(category.name)) {
            scorecard[category] = cardMap[category.name] as int?;
          } else {
            scorecard[category] = null;
          }
        }
        scorecards.add(scorecard);
      }

      _engine.restoreState(
        playerCount: playerCount,
        playerNames: playerNames,
        activePlayerIndex: activePlayerIndex,
        scorecards: scorecards,
        diceValues: diceValues,
        heldDice: heldDice,
        rollsRemaining: rollsRemaining,
        isGameOver: isGameOver,
      );

      setState(() {
        _setupPlayerCount = playerCount;
        for (int i = 0; i < playerCount; i++) {
          if (i < _nameControllers.length) {
            _nameControllers[i].text = playerNames[i];
          }
        }
      });

      return true;
    } catch (e) {
      debugPrint("Error loading game state: $e");
      await _deleteSavedMatch();
      return false;
    }
  }

  // Rules Guide Modal
  void _showRulesDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF323846),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: Color(0xFF1F2430), width: 1.5),
          ),
          title: Row(
            children: [
              const Icon(Icons.help, color: Color(0xFFFBBC05), size: 24),
              const SizedBox(width: 8),
              const Text(
                'YATZY! Rules Guide',
                style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFFFBBC05), fontSize: 18),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.grey, size: 20),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          content: Container(
            width: double.maxFinite,
            constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.65),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'YATZY! is a classic dice board game played with 5 dice. Your objective is to score the highest total by rolling combinations and filling out your scorecard.',
                    style: TextStyle(fontSize: 13, height: 1.5, color: Colors.white),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Gameplay',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFFFBBC05)),
                  ),
                  const Divider(color: Color(0xFF1F2430)),
                  _buildBulletPoint('A match consists of 13 rounds per player.'),
                  _buildBulletPoint('On your turn, you can roll the dice up to 3 times.'),
                  _buildBulletPoint('After the 1st or 2nd roll, tap any dice you want to hold (they won\'t be re-rolled).'),
                  _buildBulletPoint('Before your turn ends, you must select one empty scoring category to record your score.'),
                  const SizedBox(height: 14),
                  const Text(
                    'Scoring Categories',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFFFBBC05)),
                  ),
                  const Divider(color: Color(0xFF1F2430)),
                  const Text(
                    'Upper Section (Ones to Sixes)',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white),
                  ),
                  const SizedBox(height: 4),
                  _buildBulletPoint('Sum of all dice showing that number. (e.g., rolling ⚃ ⚃ ⚂ ⚄ ⚁ and scoring in Fours yields 8 pts).'),
                  _buildBulletPoint('Upper Section Bonus: If the sum of your Upper Section scores is 63 or more, you receive a +35 bonus.'),
                  const SizedBox(height: 12),
                  const Text(
                    'Lower Section (Combinations)',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white),
                  ),
                  const SizedBox(height: 6),
                  Table(
                    columnWidths: const {
                      0: FlexColumnWidth(3),
                      1: FlexColumnWidth(4.5),
                      2: FlexColumnWidth(2.5),
                    },
                    border: TableBorder(
                      horizontalInside: BorderSide(color: Colors.white.withOpacity(0.05), width: 1),
                    ),
                    children: [
                      const TableRow(
                        children: [
                          Padding(padding: EdgeInsets.symmetric(vertical: 4), child: Text('Category', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFFFBBC05), fontSize: 11))),
                          Padding(padding: EdgeInsets.symmetric(vertical: 4), child: Text('Requirements', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFFFBBC05), fontSize: 11))),
                          Padding(padding: EdgeInsets.symmetric(vertical: 4), child: Text('Score', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFFFBBC05), fontSize: 11), textAlign: TextAlign.right)),
                        ],
                      ),
                      _buildRulesTableRow('3 of a Kind', '3+ matching dice', 'Sum of dice'),
                      _buildRulesTableRow('4 of a Kind', '4+ matching dice', 'Sum of dice'),
                      _buildRulesTableRow('Full House', '3 matching & pair', '25 pts'),
                      _buildRulesTableRow('Sm. Straight', 'Sequence of 4', '30 pts'),
                      _buildRulesTableRow('Lg. Straight', 'Sequence of 5', '40 pts'),
                      _buildRulesTableRow('Yatzy!', 'All 5 matching', '50 pts'),
                      _buildRulesTableRow('Chance', 'Any combination', 'Sum of dice'),
                    ],
                  ),
                ],
              ),
            ),
          ),
          actions: [
            Center(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFBBC05),
                    foregroundColor: const Color(0xFF323846),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Got it, let\'s play!', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildBulletPoint(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('• ', style: TextStyle(color: Color(0xFFFBBC05), fontSize: 14)),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 12, height: 1.4, color: Colors.white90),
            ),
          ),
        ],
      ),
    );
  }

  TableRow _buildRulesTableRow(String category, String requirement, String score) {
    return TableRow(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Text(category, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.white)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Text(requirement, style: const TextStyle(fontSize: 11, color: Colors.white70)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Text(score, style: const TextStyle(fontSize: 11, color: Color(0xFFFBBC05)), textAlign: TextAlign.right),
        ),
      ],
    );
  }

  void _rollDice() {
    if (_engine.rollsRemaining > 0 && !_engine.isGameOver && !_isRolling) {
      HapticFeedback.mediumImpact();
      SystemSound.play(SystemSoundType.click);
      setState(() {
        _engine.rollDice();
        _isRolling = true;
      });
      _game.triggerRollAnimation();
      _saveGameState();
    }
  }

  void _selectCategory(ScoringCategory category) async {
    if (_engine.rollsRemaining == 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Roll the dice first before scoring!')),
      );
      return;
    }
    if (_isRolling) {
      return;
    }
    
    final succeeded = _engine.selectCategory(category);
    if (succeeded) {
      HapticFeedback.heavyImpact();
      SystemSound.play(SystemSoundType.click);
      _game.resetVisuals();
      setState(() {
        _isRolling = false;
      });

      if (_engine.isGameOver) {
        await _deleteSavedMatch();
        int maxScore = 0;
        for (int i = 0; i < _engine.playerCount; i++) {
          final total = _engine.getTotalScore(i);
          if (total > maxScore) {
            maxScore = total;
          }
        }
        await _social.submitScore(maxScore);
        _refreshLeaderboard();
        _showGameOverDialog();
      } else {
        await _saveGameState();
      }
    }
  }

  void _resetGame() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF323846),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Color(0xFF1F2430), width: 1.5),
          ),
          title: const Text(
            'Reset Match?',
            style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFFFBBC05)),
          ),
          content: const Text(
            'Are you sure you want to reset the current match? Your progress will be lost.',
            style: TextStyle(color: Colors.white90),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFBBC05),
                foregroundColor: const Color(0xFF323846),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () {
                Navigator.of(context).pop();
                setState(() {
                  _engine.resetGame();
                  _game.resetVisuals();
                  _isRolling = false;
                });
                _deleteSavedMatch();
              },
              child: const Text('Reset', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  void _showGameOverDialog() {
    // Rank players
    final List<Map<String, dynamic>> playerRankings = [];
    for (int i = 0; i < _engine.playerCount; i++) {
      playerRankings.add({
        'index': i,
        'name': _engine.playerNames[i],
        'score': _engine.getTotalScore(i),
      });
    }
    playerRankings.sort((a, b) => (b['score'] as int).compareTo(a['score'] as int));

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF323846),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Color(0xFF1F2430), width: 1.5),
          ),
          title: const Text(
            '🏆 Match Completed!',
            style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFFFBBC05)),
            textAlign: TextAlign.center,
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Final rankings:', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
              const SizedBox(height: 12),
              ...playerRankings.asMap().entries.map((entry) {
                final index = entry.key;
                final player = entry.value;
                final score = player['score'];
                final name = player['name'];
                final pIndex = player['index'] as int;
                final playerColor = pIndex == 0 ? const Color(0xFF2196F3) : const Color(0xFFEF5350);

                String rankEmoji = '${index + 1}.';
                if (index == 0) rankEmoji = '🥇';
                if (index == 1) rankEmoji = '🥈';

                return Container(
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: index == 0 ? playerColor.withOpacity(0.2) : const Color(0xFF202430),
                    borderRadius: BorderRadius.circular(8),
                    border: index == 0 ? Border.all(color: playerColor, width: 1.5) : null,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Text(rankEmoji, style: const TextStyle(fontSize: 16)),
                          const SizedBox(width: 8),
                          Text(
                            name,
                            style: TextStyle(
                              fontWeight: index == 0 ? FontWeight.bold : FontWeight.normal,
                              color: index == 0 ? playerColor : Colors.white,
                            ),
                          ),
                        ],
                      ),
                      Text(
                        '$score pts',
                        style: TextStyle(fontWeight: FontWeight.bold, color: index == 0 ? playerColor : Colors.white),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ],
          ),
          actions: [
            Center(
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFBBC05),
                  foregroundColor: const Color(0xFF323846),
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Back to Menu', style: TextStyle(fontWeight: FontWeight.bold)),
                onPressed: () {
                  Navigator.of(context).pop();
                  setState(() {
                    _isGameStarted = false;
                  });
                },
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_isGameStarted) {
      return _buildSetupScreen();
    }

    return Scaffold(
      endDrawer: _buildLeaderboardDrawer(),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  AnimatedRotation(
                    turns: _engine.activePlayerIndex == 1 ? 0.5 : 0.0,
                    duration: const Duration(milliseconds: 600),
                    curve: Curves.easeInOutCubic,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        // Main Card
                        Container(
                          constraints: const BoxConstraints(maxWidth: 480),
                          decoration: BoxDecoration(
                            color: const Color(0xFF323846),
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(color: const Color(0xFF1F2430), width: 1.5),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.35),
                                blurRadius: 30,
                                offset: const Offset(0, 10),
                              ),
                            ],
                          ),
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // Header
                              _buildCustomHeader(),
                              const SizedBox(height: 10),
                              // Turn strip
                              _buildTurnStrip(),
                              const SizedBox(height: 10),
                              // Scorecard (On TOP)
                              _buildScorecardTable(),
                              const SizedBox(height: 14),
                              // Dice component (Flame canvas on BOTTOM)
                              _buildDiceArena(),
                              const SizedBox(height: 14),
                              // Controls
                              _buildControlBar(),
                            ],
                          ),
                        ),
                        // Left score tab
                        Positioned(
                          left: -28,
                          top: 180,
                          child: _buildLeftScoreTab(),
                        ),
                        // Right exit tab
                        Positioned(
                          right: -28,
                          top: 180,
                          child: _buildRightExitTab(),
                        ),
                      ],
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

  Widget _buildSetupScreen() {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
              child: Container(
                constraints: const BoxConstraints(maxWidth: 400),
                decoration: BoxDecoration(
                  color: const Color(0xFF323846),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: const Color(0xFF1F2430), width: 1.5),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.3),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                padding: const EdgeInsets.all(24.0),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Center(
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 16),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(24),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFFFBBC05).withOpacity(0.3),
                                  blurRadius: 20,
                                  spreadRadius: 2,
                                )
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(24),
                              child: Image.asset(
                                'assets/images/logo.png',
                                height: 110,
                                width: 110,
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                        ),
                        const Text(
                          'YATZY!',
                          style: TextStyle(
                            fontSize: 36,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 4,
                            color: Color(0xFFFBBC05),
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Play Local Multiplayer Without Ads',
                          style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'open-games.app is the parent name who builds open-source games without ads. Play Now Free!',
                          style: TextStyle(color: Color(0xFFA0A5B5), fontSize: 11),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 20),
                        
                        if (_hasSavedGame) ...[
                          Container(
                            margin: const EdgeInsets.only(bottom: 20),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFF202430),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: const Color(0xFFFBBC05), width: 1.5),
                            ),
                            child: Column(
                              children: [
                                const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.history_edu, color: Color(0xFFFBBC05), size: 18),
                                    SizedBox(width: 8),
                                    Text(
                                      'Unfinished Match Detected',
                                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFFFBBC05)),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                  children: [
                                    TextButton.icon(
                                      onPressed: () {
                                        showDialog(
                                          context: context,
                                          builder: (context) => AlertDialog(
                                            backgroundColor: const Color(0xFF323846),
                                            shape: RoundedRectangleBorder(
                                              borderRadius: BorderRadius.circular(16),
                                              side: const BorderSide(color: Color(0xFF1F2430), width: 1.5),
                                            ),
                                            title: const Text('Delete Saved Match?', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFFFBBC05))),
                                            content: const Text('Are you sure you want to delete the saved match progress?', style: TextStyle(color: Colors.white90)),
                                            actions: [
                                              TextButton(
                                                onPressed: () => Navigator.pop(context),
                                                child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
                                              ),
                                              ElevatedButton(
                                                style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
                                                onPressed: () {
                                                  Navigator.pop(context);
                                                  _deleteSavedMatch();
                                                },
                                                child: const Text('Delete', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                              ),
                                            ],
                                          ),
                                        );
                                      },
                                      icon: const Icon(Icons.delete, color: Colors.redAccent, size: 16),
                                      label: const Text('Delete', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 12)),
                                    ),
                                    ElevatedButton.icon(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(0xFFFBBC05),
                                        foregroundColor: const Color(0xFF323846),
                                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                      ),
                                      icon: const Icon(Icons.play_arrow, size: 18),
                                      label: const Text('RESUME MATCH', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                                      onPressed: () async {
                                        final loaded = await _loadGameState();
                                        if (loaded) {
                                          _game.resetVisuals();
                                          _game.syncVisualsToEngine();
                                          setState(() {
                                            _isGameStarted = true;
                                            _isRolling = false;
                                          });
                                        }
                                      },
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],

                        // Player Names Card
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(0xFF202430),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: const Color(0xFF1F2430)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'PLAYER NAMES',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFFFBBC05)),
                              ),
                              const SizedBox(height: 12),
                              ...List.generate(2, (index) {
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 8.0),
                                  child: TextField(
                                    controller: _nameControllers[index],
                                    style: const TextStyle(color: Colors.white, fontSize: 14),
                                    decoration: InputDecoration(
                                      labelText: 'Player ${index + 1} Name',
                                      labelStyle: const TextStyle(color: Color(0xFFA0A5B5), fontSize: 12),
                                      filled: true,
                                      fillColor: const Color(0xFF323846),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                        borderSide: const BorderSide(color: Color(0xFF1F2430)),
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                        borderSide: const BorderSide(color: Color(0xFFFBBC05)),
                                      ),
                                    ),
                                  ),
                                );
                              }),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),

                        // Start Match Button
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFFBBC05),
                            foregroundColor: const Color(0xFF323846),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            elevation: 4,
                          ),
                          onPressed: () {
                            final List<String> names = [];
                            for (int i = 0; i < 2; i++) {
                              final val = _nameControllers[i].text.trim();
                              names.add(val.isNotEmpty ? val : 'Player ${i + 1}');
                            }
                            
                            _engine.setupPlayers(2, names);
                            _game.resetVisuals();
                            setState(() {
                              _isGameStarted = true;
                              _isRolling = false;
                            });
                          },
                          child: const Text(
                            'START MATCH',
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, letterSpacing: 1.5),
                          ),
                        ),
                      ],
                    ),
                    Positioned(
                      top: -12,
                      right: -12,
                      child: IconButton(
                        icon: const Icon(Icons.help_outline, color: Color(0xFFFBBC05), size: 24),
                        onPressed: _showRulesDialog,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCustomHeader() {
    return Row(
      children: [
        IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.grey),
          onPressed: () {
            setState(() {
              _isGameStarted = false;
            });
          },
        ),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Image.asset(
            'assets/images/logo.png',
            height: 28,
            width: 28,
            fit: BoxFit.cover,
          ),
        ),
        const SizedBox(width: 8),
        const Text(
          'YATZY!',
          style: TextStyle(
            letterSpacing: 2,
            fontWeight: FontWeight.w900,
            color: Color(0xFFFBBC05),
            fontSize: 18,
          ),
        ),
        const Spacer(),
        IconButton(
          icon: const Icon(Icons.help_outline, color: Color(0xFFFBBC05)),
          onPressed: _showRulesDialog,
        ),
        IconButton(
          icon: const Icon(Icons.refresh, color: Colors.grey),
          onPressed: _resetGame,
        ),
        if (_social.currentUser == null)
          IconButton(
            icon: const Icon(Icons.login, color: Color(0xFFFBBC05)),
            onPressed: _loginSocial,
          )
        else
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4.0),
            child: Center(
              child: Text(
                _social.currentUser!.displayName.split(' ')[0],
                style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        IconButton(
          icon: const Icon(Icons.leaderboard, color: Color(0xFFFBBC05)),
          onPressed: () {
            _refreshLeaderboard();
            Scaffold.of(context).openEndDrawer();
          },
        ),
      ],
    );
  }

  Widget _buildTurnStrip() {
    final activeIdx = _engine.activePlayerIndex;
    final activePlayerName = _engine.playerNames[activeIdx];
    final activeColor = activeIdx == 0 ? const Color(0xFF2196F3) : const Color(0xFFEF5350);

    return Container(
      decoration: BoxDecoration(
        color: activeColor.withOpacity(0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: activeColor.withOpacity(0.3), width: 1),
      ),
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.person, color: activeColor, size: 18),
          const SizedBox(width: 8),
          Text(
            "TURN: ${activePlayerName.toUpperCase()}",
            style: TextStyle(
              fontWeight: FontWeight.w900,
              letterSpacing: 1.5,
              color: activeColor,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLeftScoreTab() {
    final p1Score = _engine.getTotalScore(0);
    final p2Score = _engine.getTotalScore(1);
    final activeColor = _engine.activePlayerIndex == 0 ? const Color(0xFF2196F3) : const Color(0xFFEF5350);

    return Container(
      width: 28,
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(20),
          bottomLeft: Radius.circular(20),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 4,
            offset: Offset(-2, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$p2Score',
            style: const TextStyle(color: Color(0xFF2C3E50), fontSize: 11, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: activeColor,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '$p1Score',
            style: const TextStyle(color: Color(0xFF2C3E50), fontSize: 11, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildRightExitTab() {
    return GestureDetector(
      onTap: () {
        setState(() {
          _isGameStarted = false;
        });
      },
      child: Container(
        width: 28,
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.only(
            topRight: Radius.circular(20),
            bottomRight: Radius.circular(20),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black12,
              blurRadius: 4,
              offset: Offset(2, 2),
            ),
          ],
        ),
        child: const Center(
          child: RotatedBox(
            quarterTurns: 1,
            child: Text(
              'EXIT',
              style: TextStyle(
                color: Color(0xFF2C3E50),
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 1,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDiceArena() {
    return Container(
      height: 125,
      decoration: BoxDecoration(
        color: const Color(0xFF202430),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF1F2430), width: 1.5),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 10,
            offset: Offset(0, 4),
          )
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: GameWidget(game: _game),
    );
  }

  Widget _buildControlBar() {
    final activeIdx = _engine.activePlayerIndex;
    final activeColor = activeIdx == 0 ? const Color(0xFF2196F3) : const Color(0xFFEF5350);
    final canRoll = _engine.rollsRemaining > 0 && !_engine.isGameOver && !_isRolling;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'ROLLS REMAINING: ${_engine.rollsRemaining}/3',
              style: TextStyle(
                fontWeight: FontWeight.bold, 
                fontSize: 12, 
                color: activeColor,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              _engine.rollsRemaining == 3 
                  ? 'Roll dice to begin!' 
                  : _engine.rollsRemaining == 0 
                      ? 'Select score category' 
                      : 'Tap to hold, roll again!',
              style: const TextStyle(color: Color(0xFFA0A5B5), fontSize: 11),
            ),
          ],
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: activeColor,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            elevation: 4,
          ),
          onPressed: canRoll ? _rollDice : null,
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.casino, size: 18),
              SizedBox(width: 8),
              Text(
                'ROLL DICE',
                style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.5, fontSize: 13),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildScorecardTable() {
    final int activeIdx = _engine.activePlayerIndex;
    final bool hasRolled = _engine.rollsRemaining < 3;

    final categories = ScoringCategory.values;
    final upperSection = categories.sublist(0, 6);
    final lowerSection = categories.sublist(6);

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFFAF4E7),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF1F2430), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Table(
        columnWidths: const {
          0: FlexColumnWidth(4.0),
          1: FlexColumnWidth(3.0),
          2: FlexColumnWidth(3.0),
        },
        defaultVerticalAlignment: TableCellVerticalAlignment.fill,
        border: const TableBorder(
          horizontalInside: BorderSide(color: Color(0xFF1F2430), width: 1.5),
          verticalInside: BorderSide(color: Color(0xFF1F2430), width: 1.5),
        ),
        children: [
          _buildHeaderRow(activeIdx),
          ...upperSection.map((cat) => _buildCategoryRow(cat, activeIdx, hasRolled)),
          _buildSummaryRow(
            label: 'Subtotal',
            scoreProvider: (idx) => _engine.getUpperSectionSum(idx),
          ),
          _buildSummaryRow(
            label: 'Bonus (+35)',
            scoreProvider: (idx) => _engine.getUpperSectionBonus(idx),
          ),
          ...lowerSection.map((cat) => _buildCategoryRow(cat, activeIdx, hasRolled)),
          _buildSummaryRow(
            label: 'GRAND TOTAL',
            scoreProvider: (idx) => _engine.getTotalScore(idx),
            isGrand: true,
          ),
        ],
      ),
    );
  }

  TableRow _buildHeaderRow(int activeIdx) {
    final p1Name = _engine.playerNames[0];
    final p2Name = _engine.playerNames[1];

    final isP1Active = activeIdx == 0;
    final isP2Active = activeIdx == 1;

    return TableRow(
      children: [
        _buildTableCell(
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 6.0),
            child: Text(
              'CATEGORY',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 10,
                color: Color(0xFF1F2430),
                letterSpacing: 0.5,
              ),
            ),
          ),
          backgroundColor: const Color(0xFFFAF4E7),
        ),
        _buildTableCell(
          child: Text(
            p2Name.toUpperCase(),
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 11,
              color: isP2Active ? const Color(0xFFEF5350) : const Color(0xFF1F2430),
              decoration: isP2Active ? TextDecoration.underline : null,
              decorationColor: const Color(0xFFEF5350),
              decorationThickness: 2,
            ),
          ),
          backgroundColor: const Color(0xFFFAF4E7),
        ),
        _buildTableCell(
          child: Text(
            p1Name.toUpperCase(),
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 11,
              color: isP1Active ? const Color(0xFF2196F3) : const Color(0xFF1F2430),
              decoration: isP1Active ? TextDecoration.underline : null,
              decorationColor: const Color(0xFF2196F3),
              decorationThickness: 2,
            ),
          ),
          backgroundColor: const Color(0xFFFAF4E7),
        ),
      ],
    );
  }

  TableRow _buildCategoryRow(ScoringCategory category, int activeIdx, bool hasRolled) {
    final isP1Filled = _engine.scorecards[0][category] != null;
    final isP2Filled = _engine.scorecards[1][category] != null;
    
    final isActiveP1 = activeIdx == 0;
    final isActiveP2 = activeIdx == 1;

    final isP1CellClickable = !isP1Filled && isActiveP1 && !_engine.isGameOver && !_isRolling;
    final isP2CellClickable = !isP2Filled && isActiveP2 && !_engine.isGameOver && !_isRolling;
    
    final showPreview = hasRolled && !_isRolling;

    final categoryChild = Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: CategorySymbolWidget(
        category: category,
        color: const Color(0xFF1F2430),
      ),
    );

    Widget p2Cell;
    Color p2BgColor;
    final p2Score = _engine.scorecards[1][category];
    if (p2Score != null) {
      p2BgColor = const Color(0xFFFAF4E7);
      p2Cell = Text(
        '$p2Score',
        style: const TextStyle(
          fontWeight: FontWeight.w900,
          color: Color(0xFF1F2430),
          fontSize: 13,
        ),
      );
    } else if (isActiveP2 && showPreview) {
      p2BgColor = const Color(0xFFFAF4E7);
      final preview = YatzyEngine.calculateScore(category, _engine.diceValues);
      p2Cell = Text(
        '$preview',
        style: TextStyle(
          fontWeight: FontWeight.bold,
          color: const Color(0xFFEF5350).withOpacity(0.7),
          fontStyle: FontStyle.italic,
          fontSize: 12,
        ),
      );
    } else {
      p2BgColor = const Color(0xFFEF5350);
      p2Cell = const SizedBox.shrink();
    }

    Widget p1Cell;
    Color p1BgColor;
    final p1Score = _engine.scorecards[0][category];
    if (p1Score != null) {
      p1BgColor = const Color(0xFFFAF4E7);
      p1Cell = Text(
        '$p1Score',
        style: const TextStyle(
          fontWeight: FontWeight.w900,
          color: Color(0xFF1F2430),
          fontSize: 13,
        ),
      );
    } else if (isActiveP1 && showPreview) {
      p1BgColor = const Color(0xFFFAF4E7);
      final preview = YatzyEngine.calculateScore(category, _engine.diceValues);
      p1Cell = Text(
        '$preview',
        style: TextStyle(
          fontWeight: FontWeight.bold,
          color: const Color(0xFF2196F3).withOpacity(0.7),
          fontStyle: FontStyle.italic,
          fontSize: 12,
        ),
      );
    } else {
      p1BgColor = const Color(0xFF2196F3);
      p1Cell = const SizedBox.shrink();
    }

    final bool isRowClickable = (isActiveP1 && isP1CellClickable) || (isActiveP2 && isP2CellClickable);
    final VoidCallback? onTap = isRowClickable ? () => _selectCategory(category) : null;

    return TableRow(
      children: [
        _buildTableCell(
          child: categoryChild,
          backgroundColor: const Color(0xFFFAF4E7),
          isClickable: isRowClickable,
          onTap: onTap,
        ),
        _buildTableCell(
          child: p2Cell,
          backgroundColor: p2BgColor,
          isClickable: isP2CellClickable,
          onTap: onTap,
        ),
        _buildTableCell(
          child: p1Cell,
          backgroundColor: p1BgColor,
          isClickable: isP1CellClickable,
          onTap: onTap,
        ),
      ],
    );
  }

  TableRow _buildSummaryRow({
    required String label,
    required int Function(int) scoreProvider,
    bool isGrand = false,
  }) {
    final p2Score = scoreProvider(1);
    final p1Score = scoreProvider(0);

    return TableRow(
      children: [
        _buildTableCell(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6.0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: isGrand ? 12 : 11,
                  color: isGrand ? const Color(0xFFFBBC05) : const Color(0xFF1F2430),
                ),
              ),
            ),
          ),
          backgroundColor: isGrand ? const Color(0xFF202430) : const Color(0xFFEADFC9),
        ),
        _buildTableCell(
          child: Text(
            isGrand ? '$p2Score' : (label.contains('Bonus') ? '+$p2Score' : '$p2Score'),
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: isGrand ? 14 : 12,
              color: isGrand ? const Color(0xFFFBBC05) : const Color(0xFF1F2430),
            ),
          ),
          backgroundColor: isGrand ? const Color(0xFF202430) : const Color(0xFFEADFC9),
        ),
        _buildTableCell(
          child: Text(
            isGrand ? '$p1Score' : (label.contains('Bonus') ? '+$p1Score' : '$p1Score'),
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: isGrand ? 14 : 12,
              color: isGrand ? const Color(0xFFFBBC05) : const Color(0xFF1F2430),
            ),
          ),
          backgroundColor: isGrand ? const Color(0xFF202430) : const Color(0xFFEADFC9),
        ),
      ],
    );
  }

  Widget _buildTableCell({
    required Widget child,
    Color? backgroundColor,
    bool isClickable = false,
    VoidCallback? onTap,
  }) {
    Widget content = Container(
      height: 34,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: backgroundColor ?? const Color(0xFFFAF4E7),
      ),
      child: child,
    );

    if (isClickable && onTap != null) {
      content = GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: content,
      );
    }

    return content;
  }

  Widget _buildLeaderboardDrawer() {
    return Drawer(
      backgroundColor: const Color(0xFF202430),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              color: const Color(0xFF323846),
              child: const Row(
                children: [
                  Icon(Icons.emoji_events, color: Color(0xFFFBBC05), size: 28),
                  SizedBox(width: 12),
                  Text(
                    'LEADERBOARD',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: 1.5, color: Color(0xFFFBBC05)),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _leaderboard.isEmpty
                  ? const Center(child: CircularProgressIndicator(color: Color(0xFFFBBC05)))
                  : ListView.builder(
                      itemCount: _leaderboard.length,
                      itemBuilder: (context, index) {
                        final entry = _leaderboard[index];
                        final int score = entry['score'] ?? 0;
                        final String name = entry['name'] ?? 'Anonymous';
                        final int rank = entry['rank'] ?? (index + 1);

                        String rankSymbol = rank.toString();
                        if (rank == 1) rankSymbol = '🥇';
                        if (rank == 2) rankSymbol = '🥈';
                        if (rank == 3) rankSymbol = '🥉';

                        return Container(
                          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFF323846),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: rank <= 3 ? const Color(0xFFFBBC05).withOpacity(0.3) : Colors.transparent,
                            ),
                          ),
                          child: Row(
                            children: [
                              ui.SizedBox(
                                width: 35,
                                child: Text(
                                  rankSymbol,
                                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  name,
                                  style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                                ),
                              ),
                              Text(
                                '$score pts',
                                style: const TextStyle(color: Color(0xFFFBBC05), fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  String _getCategoryLabel(ScoringCategory category) {
    switch (category) {
      case ScoringCategory.ones: return 'Ones';
      case ScoringCategory.twos: return 'Twos';
      case ScoringCategory.threes: return 'Threes';
      case ScoringCategory.fours: return 'Fours';
      case ScoringCategory.fives: return 'Fives';
      case ScoringCategory.sixes: return 'Sixes';
      case ScoringCategory.threeOfAKind: return 'Three of a Kind';
      case ScoringCategory.fourOfAKind: return 'Four of a Kind';
      case ScoringCategory.fullHouse: return 'Full House';
      case ScoringCategory.smallStraight: return 'Small Straight';
      case ScoringCategory.largeStraight: return 'Large Straight';
      case ScoringCategory.yatzy: return 'Yatzy!';
      case ScoringCategory.chance: return 'Chance';
    }
  }
}

class CategorySymbolPainter extends CustomPainter {
  final ScoringCategory category;
  final Color color;

  CategorySymbolPainter(this.category, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final strokePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    final double h = size.height;
    final double w = size.width;

    switch (category) {
      case ScoringCategory.ones:
        _drawDieOutline(canvas, strokePaint, h);
        _drawPips(canvas, paint, h, [const Offset(0.5, 0.5)]);
        break;
      case ScoringCategory.twos:
        _drawDieOutline(canvas, strokePaint, h);
        _drawPips(canvas, paint, h, [const Offset(0.3, 0.3), const Offset(0.7, 0.7)]);
        break;
      case ScoringCategory.threes:
        _drawDieOutline(canvas, strokePaint, h);
        _drawPips(canvas, paint, h, [const Offset(0.25, 0.25), const Offset(0.5, 0.5), const Offset(0.75, 0.75)]);
        break;
      case ScoringCategory.fours:
        _drawDieOutline(canvas, strokePaint, h);
        _drawPips(canvas, paint, h, [
          const Offset(0.3, 0.3),
          const Offset(0.7, 0.3),
          const Offset(0.3, 0.7),
          const Offset(0.7, 0.7),
        ]);
        break;
      case ScoringCategory.fives:
        _drawDieOutline(canvas, strokePaint, h);
        _drawPips(canvas, paint, h, [
          const Offset(0.25, 0.25),
          const Offset(0.75, 0.25),
          const Offset(0.5, 0.5),
          const Offset(0.25, 0.75),
          const Offset(0.75, 0.75),
        ]);
        break;
      case ScoringCategory.sixes:
        _drawDieOutline(canvas, strokePaint, h);
        _drawPips(canvas, paint, h, [
          const Offset(0.3, 0.25),
          const Offset(0.7, 0.25),
          const Offset(0.3, 0.5),
          const Offset(0.7, 0.5),
          const Offset(0.3, 0.75),
          const Offset(0.7, 0.75),
        ]);
        break;
      case ScoringCategory.threeOfAKind:
        final double boxSize = h * 0.7;
        final double spacing = h * 0.3;
        final double startX = (w - (3 * boxSize + 2 * spacing)) / 2;
        final double centerY = (h - boxSize) / 2;
        for (int i = 0; i < 3; i++) {
          final rect = RRect.fromRectAndRadius(
            Rect.fromLTWH(startX + i * (boxSize + spacing), centerY, boxSize, boxSize),
            const Radius.circular(1.5),
          );
          canvas.drawRRect(rect, paint);
        }
        break;
      case ScoringCategory.fourOfAKind:
        final double circleRadius = h * 0.32;
        final double spacing = h * 0.3;
        final double startX = (w - (8 * circleRadius + 3 * spacing)) / 2 + circleRadius;
        final double centerY = h / 2;
        for (int i = 0; i < 4; i++) {
          canvas.drawCircle(Offset(startX + i * (2 * circleRadius + spacing), centerY), circleRadius, paint);
        }
        break;
      case ScoringCategory.fullHouse:
        final double itemSize = h * 0.65;
        final double spacing = h * 0.25;
        final double startX = (w - (5 * itemSize + 4 * spacing)) / 2;
        final double centerY = h / 2;
        for (int i = 0; i < 3; i++) {
          final double cx = startX + i * (itemSize + spacing) + itemSize / 2;
          final double cy = centerY;
          final path = Path()
            ..moveTo(cx, cy - itemSize / 2)
            ..lineTo(cx + itemSize / 2, cy)
            ..lineTo(cx, cy + itemSize / 2)
            ..lineTo(cx - itemSize / 2, cy)
            ..close();
          canvas.drawPath(path, paint);
        }
        for (int i = 3; i < 5; i++) {
          final double cx = startX + i * (itemSize + spacing) + itemSize / 2;
          final double cy = centerY;
          canvas.drawCircle(Offset(cx, cy), itemSize * 0.45, paint);
        }
        break;
      case ScoringCategory.smallStraight:
        final double itemSize = h * 0.65;
        final double spacing = h * 0.25;
        final double startX = (w - (4 * itemSize + 3 * spacing)) / 2;
        final double centerY = h / 2;
        
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(startX, centerY - itemSize / 2, itemSize, itemSize),
            const Radius.circular(1.5),
          ),
          paint,
        );

        double cx = startX + (itemSize + spacing) + itemSize / 2;
        final pDiamond = Path()
          ..moveTo(cx, centerY - itemSize / 2)
          ..lineTo(cx + itemSize / 2, centerY)
          ..lineTo(cx, centerY + itemSize / 2)
          ..lineTo(cx - itemSize / 2, centerY)
          ..close();
        canvas.drawPath(pDiamond, paint);

        cx = startX + 2 * (itemSize + spacing) + itemSize / 2;
        canvas.drawCircle(Offset(cx, centerY), itemSize * 0.45, paint);

        cx = startX + 3 * (itemSize + spacing) + itemSize / 2;
        final pTriangle = Path()
          ..moveTo(cx, centerY - itemSize / 2)
          ..lineTo(cx + itemSize / 2, centerY + itemSize / 2)
          ..lineTo(cx - itemSize / 2, centerY + itemSize / 2)
          ..close();
        canvas.drawPath(pTriangle, paint);
        break;
      case ScoringCategory.largeStraight:
        final double itemSize = h * 0.65;
        final double spacing = h * 0.22;
        final double startX = (w - (5 * itemSize + 4 * spacing)) / 2;
        final double centerY = h / 2;

        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(startX, centerY - itemSize / 2, itemSize, itemSize),
            const Radius.circular(1.5),
          ),
          paint,
        );

        double cx = startX + (itemSize + spacing) + itemSize / 2;
        final pDiamond = Path()
          ..moveTo(cx, centerY - itemSize / 2)
          ..lineTo(cx + itemSize / 2, centerY)
          ..lineTo(cx, centerY + itemSize / 2)
          ..lineTo(cx - itemSize / 2, centerY)
          ..close();
        canvas.drawPath(pDiamond, paint);

        cx = startX + 2 * (itemSize + spacing) + itemSize / 2;
        canvas.drawCircle(Offset(cx, centerY), itemSize * 0.45, paint);

        cx = startX + 3 * (itemSize + spacing) + itemSize / 2;
        final pTriangle = Path()
          ..moveTo(cx, centerY - itemSize / 2)
          ..lineTo(cx + itemSize / 2, centerY + itemSize / 2)
          ..lineTo(cx - itemSize / 2, centerY + itemSize / 2)
          ..close();
        canvas.drawPath(pTriangle, paint);

        cx = startX + 4 * (itemSize + spacing) + itemSize / 2;
        _paintStar(canvas, cx, centerY, itemSize / 2, paint);
        break;
      case ScoringCategory.yatzy:
        final double itemSize = h * 0.65;
        final double spacing = h * 0.22;
        final double startX = (w - (5 * itemSize + 4 * spacing)) / 2;
        final double centerY = h / 2;
        for (int i = 0; i < 5; i++) {
          final double cx = startX + i * (itemSize + spacing) + itemSize / 2;
          _paintStar(canvas, cx, centerY, itemSize / 2, paint);
        }
        break;
      case ScoringCategory.chance:
        final textPainter = TextPainter(
          text: TextSpan(
            text: '?',
            style: TextStyle(
              color: color,
              fontSize: h * 0.8,
              fontWeight: FontWeight.w900,
              fontFamily: 'Roboto',
            ),
          ),
          textDirection: TextDirection.ltr,
        );
        textPainter.layout();
        textPainter.paint(canvas, Offset((w - textPainter.width) / 2, (h - textPainter.height) / 2));
        break;
    }
  }

  void _drawDieOutline(Canvas canvas, Paint strokePaint, double h) {
    final double boxSize = h * 0.72;
    final double left = (h - boxSize) / 2;
    final double top = (h - boxSize) / 2;
    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(left, top, boxSize, boxSize),
      const Radius.circular(3),
    );
    canvas.drawRRect(rrect, strokePaint);
  }

  void _drawPips(Canvas canvas, Paint fillPaint, double h, List<Offset> pips) {
    final double boxSize = h * 0.72;
    final double left = (h - boxSize) / 2;
    final double top = (h - boxSize) / 2;
    final double pipRadius = h * 0.08;

    for (var pip in pips) {
      final double px = left + pip.dx * boxSize;
      final double py = top + pip.dy * boxSize;
      canvas.drawCircle(Offset(px, py), pipRadius, fillPaint);
    }
  }

  void _paintStar(Canvas canvas, double cx, double cy, double radius, Paint paint) {
    final double outerRadius = radius;
    final double innerRadius = radius * 0.4;
    const int spikes = 5;
    
    final path = Path();
    double rot = (pi / 2) * 3;
    const double step = pi / spikes;

    path.moveTo(cx, cy - outerRadius);
    for (int i = 0; i < spikes; i++) {
      double x = cx + cos(rot) * outerRadius;
      double y = cy + sin(rot) * outerRadius;
      path.lineTo(x, y);
      rot += step;

      x = cx + cos(rot) * innerRadius;
      y = cy + sin(rot) * innerRadius;
      path.lineTo(x, y);
      rot += step;
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CategorySymbolPainter oldDelegate) {
    return oldDelegate.category != category || oldDelegate.color != color;
  }
}

class CategorySymbolWidget extends StatelessWidget {
  final ScoringCategory category;
  final Color color;

  const CategorySymbolWidget({
    super.key,
    required this.category,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final double height = 20.0;
    final double width;
    switch (category) {
      case ScoringCategory.threeOfAKind:
        width = 60.0;
        break;
      case ScoringCategory.fourOfAKind:
      case ScoringCategory.smallStraight:
        width = 80.0;
        break;
      case ScoringCategory.fullHouse:
      case ScoringCategory.largeStraight:
      case ScoringCategory.yatzy:
        width = 100.0;
        break;
      default:
        width = 24.0;
    }
    return SizedBox(
      width: width,
      height: height,
      child: CustomPaint(
        painter: CategorySymbolPainter(category, color),
      ),
    );
  }
}

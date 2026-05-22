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
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0B1C15), // Board felt green
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFFBBC05), // Amber Gold
          secondary: Color(0xFFFBBC05),
          surface: Color(0xFF162E24), // Rich forest green card
          background: Color(0xFF0B1C15),
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
  int _setupPlayerCount = 1;
  final List<TextEditingController> _nameControllers = [];
  bool _isRolling = false;
  bool _hasSavedGame = false;

  @override
  void initState() {
    super.initState();
    // Initialize 4 text controllers for names
    for (int i = 1; i <= 4; i++) {
      _nameControllers.add(TextEditingController(text: 'Player $i'));
    }

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
          backgroundColor: const Color(0xFF162E24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: Color(0xFF1B3D2F), width: 1.5),
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
                    style: TextStyle(fontSize: 13, height: 1.5),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Gameplay',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFFFBBC05)),
                  ),
                  const Divider(color: Color(0xFF1B3D2F)),
                  _buildBulletPoint('A match consists of 13 rounds per player.'),
                  _buildBulletPoint('On your turn, you can roll the dice up to 3 times.'),
                  _buildBulletPoint('After the 1st or 2nd roll, tap any dice you want to hold (they won\'t be re-rolled).'),
                  _buildBulletPoint('Before your turn ends, you must select one empty scoring category to record your score.'),
                  const SizedBox(height: 14),
                  const Text(
                    'Scoring Categories',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFFFBBC05)),
                  ),
                  const Divider(color: Color(0xFF1B3D2F)),
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
                    foregroundColor: const Color(0xFF0B1C15),
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
          backgroundColor: const Color(0xFF162E24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Color(0xFF1B3D2F), width: 1.5),
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
                foregroundColor: const Color(0xFF0B1C15),
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
          backgroundColor: const Color(0xFF1E293B),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text(
            '🏆 Match Completed!',
            style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFFFACC15)),
            textAlign: TextAlign.center,
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Final rankings:', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              ...playerRankings.asMap().entries.map((entry) {
                final index = entry.key;
                final player = entry.value;
                final score = player['score'];
                final name = player['name'];

                String rankEmoji = '${index + 1}.';
                if (index == 0) rankEmoji = '🥇';
                if (index == 1) rankEmoji = '🥈';
                if (index == 2) rankEmoji = '🥉';

                return Container(
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: index == 0 ? const Color(0xFF6366F1).withOpacity(0.2) : const Color(0xFF0F172A),
                    borderRadius: BorderRadius.circular(8),
                    border: index == 0 ? Border.all(color: const Color(0xFFFACC15), width: 1) : null,
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
                              color: index == 0 ? const Color(0xFFFACC15) : Colors.white,
                            ),
                          ),
                        ],
                      ),
                      Text(
                        '$score pts',
                        style: const TextStyle(fontWeight: FontWeight.bold),
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
                  backgroundColor: const Color(0xFF6366F1),
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Back to Menu', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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

    final double screenWidth = MediaQuery.of(context).size.width;
    final bool isCompact = screenWidth < 600;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B1C15),
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.grey),
          onPressed: () {
            setState(() {
              _isGameStarted = false;
            });
          },
        ),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
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
              style: TextStyle(letterSpacing: 2, fontWeight: FontWeight.w900, color: Color(0xFFFBBC05)),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline, color: Color(0xFFFBBC05)),
            onPressed: _showRulesDialog,
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.grey),
            onPressed: _resetGame,
          ),
          if (_social.currentUser == null)
            TextButton.icon(
              icon: const Icon(Icons.login, color: Color(0xFFFACC15), size: 18),
              label: const Text('Login', style: TextStyle(color: Color(0xFFFACC15), fontSize: 13)),
              onPressed: _loginSocial,
            )
          else
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0),
              child: Center(
                child: Text(
                  _social.currentUser!.displayName,
                  style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          Builder(
            builder: (context) => IconButton(
              icon: const Icon(Icons.leaderboard, color: Color(0xFFFACC15)),
              onPressed: () {
                _refreshLeaderboard();
                Scaffold.of(context).openEndDrawer();
              },
            ),
          ),
        ],
      ),
      endDrawer: _buildLeaderboardDrawer(),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Active Player Handoff Indicator
              Container(
                color: const Color(0xFF162E24),
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.person, color: Color(0xFFFBBC05), size: 18),
                    const SizedBox(width: 8),
                    Text(
                      "TURN: ${_engine.playerNames[_engine.activePlayerIndex].toUpperCase()}",
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.5,
                        color: Color(0xFFFBBC05),
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),

              // 1. Flame Dice Arena Canvas Container
              Container(
                margin: const EdgeInsets.all(16),
                height: 180,
                decoration: BoxDecoration(
                  color: const Color(0xFF162E24),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFF1B3D2F), width: 1.5),
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
              ),

              // 2. Play Turn Status & Persistent Action Roll Button
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'ROLLS REMAINING: ${_engine.rollsRemaining}/3',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFFFACC15)),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _engine.rollsRemaining == 3 
                              ? 'Roll dice to begin!' 
                              : _engine.rollsRemaining == 0 
                                  ? 'Select score category' 
                                  : 'Tap to hold, roll again!',
                          style: const TextStyle(color: Colors.grey, fontSize: 12),
                        ),
                      ],
                    ),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFBBC05),
                        foregroundColor: const Color(0xFF0B1C15),
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: const BorderSide(color: Color(0xFFFDD835), width: 1.5),
                        ),
                        elevation: 4,
                      ),
                      onPressed: (_engine.rollsRemaining > 0 && !_engine.isGameOver && !_isRolling) ? _rollDice : null,
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.casino, size: 20),
                          SizedBox(width: 8),
                          Text('ROLL DICE', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.5)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // 3. Interactive Scorecard Layout
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: _buildScorecardTable(),
              ),

              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }

  /// Builds a setup widget to configure player count and names before matching.
  Widget _buildSetupScreen() {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B1C15),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline, color: Color(0xFFFBBC05)),
            onPressed: _showRulesDialog,
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 8.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 20),
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
                          height: 120,
                          width: 120,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                  ),
                  const Text(
                    'YATZY!',
                    style: TextStyle(
                      fontSize: 42,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 4,
                      color: Color(0xFFFBBC05),
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Play Local Multiplayer Without Ads',
                    style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'open-games.app is the parent name who builds open-source games without ads. Play Now Free!',
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  
                  if (_hasSavedGame) ...[
                    Container(
                      margin: const EdgeInsets.only(bottom: 24),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF162E24),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFFBBC05), width: 1.5),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x33000000),
                            blurRadius: 10,
                            offset: Offset(0, 4),
                          )
                        ],
                      ),
                      child: Column(
                        children: [
                          const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.history_edu, color: Color(0xFFFBBC05)),
                              SizedBox(width: 8),
                              Text(
                                'Unfinished Match Detected',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFFFBBC05)),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              TextButton.icon(
                                onPressed: () {
                                  showDialog(
                                    context: context,
                                    builder: (context) => AlertDialog(
                                      backgroundColor: const Color(0xFF162E24),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(16),
                                        side: const BorderSide(color: Color(0xFF1B3D2F), width: 1.5),
                                      ),
                                      title: const Text('Delete Saved Match?', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFFFBBC05))),
                                      content: const Text('Are you sure you want to delete the saved match progress?'),
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
                                icon: const Icon(Icons.delete, color: Colors.redAccent, size: 18),
                                label: const Text('Delete', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                              ),
                              ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFFFBBC05),
                                  foregroundColor: const Color(0xFF0B1C15),
                                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  elevation: 2,
                                ),
                                icon: const Icon(Icons.play_arrow),
                                label: const Text('RESUME MATCH', style: TextStyle(fontWeight: FontWeight.bold)),
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
                  
                  // Player Count card
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF162E24),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFF1B3D2F)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Number of Players',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFFFBBC05)),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [1, 2, 3, 4].map((count) {
                            final bool selected = _setupPlayerCount == count;
                            return InkWell(
                              onTap: () {
                                setState(() {
                                  _setupPlayerCount = count;
                                });
                              },
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                                decoration: BoxDecoration(
                                  color: selected ? const Color(0xFFFBBC05) : const Color(0xFF0B1C15),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: selected ? const Color(0xFFFDD835) : const Color(0xFF1B3D2F),
                                    width: 1.5,
                                  ),
                                ),
                                child: Text(
                                  '$count',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 18,
                                    color: selected ? const Color(0xFF0B1C15) : Colors.grey,
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Player Names card
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF162E24),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFF1B3D2F)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Player Names',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFFFBBC05)),
                        ),
                        const SizedBox(height: 12),
                        ...List.generate(_setupPlayerCount, (index) {
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8.0),
                            child: TextField(
                              controller: _nameControllers[index],
                              decoration: InputDecoration(
                                labelText: 'Player ${index + 1} Name',
                                filled: true,
                                fillColor: const Color(0xFF0B1C15),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: const BorderSide(color: Color(0xFF1B3D2F)),
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
                  const SizedBox(height: 30),

                  // Start Match Button
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFBBC05),
                      foregroundColor: const Color(0xFF0B1C15),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      elevation: 4,
                    ),
                    child: const Text(
                      'START MATCH',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1.5),
                    ),
                    onPressed: () {
                      final List<String> names = [];
                      for (int i = 0; i < _setupPlayerCount; i++) {
                        final val = _nameControllers[i].text.trim();
                        names.add(val.isNotEmpty ? val : 'Player ${i + 1}');
                      }
                      
                      _engine.setupPlayers(_setupPlayerCount, names);
                      _game.resetVisuals();
                      setState(() {
                        _isGameStarted = true;
                        _isRolling = false;
                      });
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Builds the scorecard table using columns (Category | Player 1 | Player 2 ... )
  Widget _buildScorecardTable() {
    final int pCount = _engine.playerCount;
    final int activeIdx = _engine.activePlayerIndex;
    final bool hasRolled = _engine.rollsRemaining < 3;
    final bool isCompact = MediaQuery.of(context).size.width < 500;

    final categories = ScoringCategory.values;
    final upperSection = categories.sublist(0, 6);
    final lowerSection = categories.sublist(6);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Upper Section Column
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildTableHeader('UPPER SECTION', pCount, activeIdx, isCompact),
              const SizedBox(height: 6),
              ...upperSection.map((cat) => _buildRowForCategory(cat, pCount, activeIdx, hasRolled)),
              _buildRowForSummary('Subtotal', (idx) => '${_engine.getUpperSectionSum(idx)}', pCount, activeIdx),
              _buildRowForSummary('Bonus (+35)', (idx) => '+${_engine.getUpperSectionBonus(idx)}', pCount, activeIdx),
            ],
          ),
        ),
        SizedBox(width: isCompact ? 6.0 : 12.0),
        // Lower Section Column
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildTableHeader('LOWER SECTION', pCount, activeIdx, isCompact),
              const SizedBox(height: 6),
              ...lowerSection.map((cat) => _buildRowForCategory(cat, pCount, activeIdx, hasRolled)),
              _buildRowForSummary('Subtotal', (idx) => '${_engine.getLowerSectionSum(idx)}', pCount, activeIdx),
              _buildRowForSummary('GRAND TOTAL', (idx) => '${_engine.getTotalScore(idx)}', pCount, activeIdx, isGrand: true),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTableHeader(String title, int pCount, int activeIdx, bool isCompact) {
    final List<Widget> headerCells = [
      Expanded(
        flex: 3,
        child: Text(
          title,
          style: TextStyle(
            fontWeight: FontWeight.bold, 
            color: Colors.grey, 
            fontSize: isCompact ? 9 : 11
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    ];

    for (int i = 0; i < pCount; i++) {
      final bool isActive = i == activeIdx;
      String name = _engine.playerNames[i];
      if (name.length > 8) name = '${name.substring(0, 6)}..';

      headerCells.add(
        Expanded(
          flex: 2,
          child: Container(
            alignment: Alignment.center,
            padding: EdgeInsets.symmetric(vertical: isCompact ? 2 : 4, horizontal: 1),
            decoration: BoxDecoration(
              color: isActive ? const Color(0xFFFBBC05).withOpacity(0.15) : Colors.transparent,
              borderRadius: BorderRadius.circular(4),
              border: isActive ? Border.all(color: const Color(0xFFFBBC05), width: 1.0) : null,
            ),
            child: Text(
              name,
              style: TextStyle(
                fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                color: isActive ? const Color(0xFFFBBC05) : Colors.grey,
                fontSize: isCompact ? 9 : 11,
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      );
    }

    return Container(
      padding: EdgeInsets.symmetric(vertical: isCompact ? 6 : 8, horizontal: isCompact ? 6 : 12),
      decoration: BoxDecoration(
        color: const Color(0xFF162E24),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(children: headerCells),
    );
  }

  IconData _getCategoryIcon(ScoringCategory category) {
    switch (category) {
      case ScoringCategory.ones: return Icons.looks_one;
      case ScoringCategory.twos: return Icons.looks_two;
      case ScoringCategory.threes: return Icons.looks_3;
      case ScoringCategory.fours: return Icons.looks_4;
      case ScoringCategory.fives: return Icons.looks_5;
      case ScoringCategory.sixes: return Icons.looks_6;
      case ScoringCategory.threeOfAKind: return Icons.filter_3;
      case ScoringCategory.fourOfAKind: return Icons.filter_4;
      case ScoringCategory.fullHouse: return Icons.home;
      case ScoringCategory.smallStraight: return Icons.linear_scale;
      case ScoringCategory.largeStraight: return Icons.forward;
      case ScoringCategory.yatzy: return Icons.emoji_events;
      case ScoringCategory.chance: return Icons.help_outline;
    }
  }

  String _getCategoryInstruction(ScoringCategory category) {
    switch (category) {
      case ScoringCategory.ones: return 'Score sum of 1s';
      case ScoringCategory.twos: return 'Score sum of 2s';
      case ScoringCategory.threes: return 'Score sum of 3s';
      case ScoringCategory.fours: return 'Score sum of 4s';
      case ScoringCategory.fives: return 'Score sum of 5s';
      case ScoringCategory.sixes: return 'Score sum of 6s';
      case ScoringCategory.threeOfAKind: return 'Sum if 3+ matching';
      case ScoringCategory.fourOfAKind: return 'Sum if 4+ matching';
      case ScoringCategory.fullHouse: return '3 of kind + pair (25)';
      case ScoringCategory.smallStraight: return 'Sequence of 4 (30)';
      case ScoringCategory.largeStraight: return 'Sequence of 5 (40)';
      case ScoringCategory.yatzy: return '5 matching (50)';
      case ScoringCategory.chance: return 'Sum of all 5 dice';
    }
  }

  String? _getCategoryDiceFace(ScoringCategory category) {
    switch (category) {
      case ScoringCategory.ones: return '⚀';
      case ScoringCategory.twos: return '⚁';
      case ScoringCategory.threes: return '⚂';
      case ScoringCategory.fours: return '⚃';
      case ScoringCategory.fives: return '⚄';
      case ScoringCategory.sixes: return '⚅';
      default: return null;
    }
  }

  Widget _buildRowForCategory(ScoringCategory category, int pCount, int activeIdx, bool hasRolled) {
    final String label = _getCategoryLabel(category);
    final IconData icon = _getCategoryIcon(category);
    final String instruction = _getCategoryInstruction(category);
    final String? diceFace = _getCategoryDiceFace(category);
    final bool isCompact = MediaQuery.of(context).size.width < 500;

    final List<Widget> cells = [
      Expanded(
        flex: 3,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!isCompact || pCount <= 2) ...[
              Icon(
                icon,
                size: isCompact ? 14 : 18,
                color: const Color(0xFF818CF8),
              ),
              SizedBox(width: isCompact ? 4 : 6),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          label,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: (isCompact && pCount > 2) ? 10 : 12,
                            color: Colors.white,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (diceFace != null && (!isCompact || pCount <= 2)) ...[
                        const SizedBox(width: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 0.5),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1E293B),
                            border: Border.all(color: const Color(0xFF475569), width: 1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            diceFace,
                            style: const TextStyle(
                              color: Color(0xFFFBBC05),
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (!isCompact) ...[
                    const SizedBox(height: 2),
                    Text(
                      instruction,
                      style: const TextStyle(
                        color: Colors.grey,
                        fontSize: 9,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    ];

    final bool isClickable = _engine.scorecards[activeIdx][category] == null && !_engine.isGameOver && !_isRolling;
    final bool showPreview = hasRolled && !_isRolling;

    for (int i = 0; i < pCount; i++) {
      final int? actualScore = _engine.scorecards[i][category];
      final bool isActive = i == activeIdx;

      Widget cellChild;
      if (actualScore != null) {
        cellChild = Text(
          '$actualScore',
          style: TextStyle(
            fontWeight: FontWeight.bold, 
            fontSize: isCompact ? 12 : 14
          ),
          textAlign: TextAlign.center,
        );
      } else if (isActive && showPreview) {
        // Preview score
        final preview = YatzyEngine.calculateScore(category, _engine.diceValues);
        cellChild = Text(
          '$preview',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: const Color(0xFFFBBC05).withOpacity(0.8),
            fontStyle: FontStyle.italic,
            fontSize: isCompact ? 11 : 13,
          ),
          textAlign: TextAlign.center,
        );
      } else {
        cellChild = Text(
          '-',
          style: TextStyle(
            color: const Color(0xFF475569),
            fontSize: isCompact ? 12 : 14
          ),
          textAlign: TextAlign.center,
        );
      }

      cells.add(
        Expanded(
          flex: 2,
          child: Container(
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(vertical: 4),
            decoration: BoxDecoration(
              color: isActive ? const Color(0xFFFBBC05).withOpacity(0.05) : Colors.transparent,
              borderRadius: BorderRadius.circular(4),
            ),
            child: cellChild,
          ),
        ),
      );
    }

    return InkWell(
      onTap: isClickable ? () => _selectCategory(category) : null,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 2),
        padding: EdgeInsets.symmetric(horizontal: isCompact ? 6 : 12, vertical: isCompact ? 5 : 8),
        decoration: BoxDecoration(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isClickable && showPreview ? const Color(0xFF1B3D2F) : Colors.transparent,
            width: 1,
          ),
        ),
        child: Row(children: cells),
      ),
    );
  }

  Widget _buildRowForSummary(String label, String Function(int) scoreProvider, int pCount, int activeIdx, {bool isGrand = false}) {
    final bool isCompact = MediaQuery.of(context).size.width < 500;

    final List<Widget> cells = [
      Expanded(
        flex: 3,
        child: Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: isGrand ? const Color(0xFFFBBC05) : Colors.white,
            fontSize: isGrand ? (isCompact ? 12 : 14) : (isCompact ? 10 : 12),
          ),
        ),
      ),
    ];

    for (int i = 0; i < pCount; i++) {
      final String val = scoreProvider(i);
      final bool isActive = i == activeIdx;

      cells.add(
        Expanded(
          flex: 2,
          child: Text(
            val,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: isGrand ? const Color(0xFFFBBC05) : Colors.white,
              fontSize: isGrand ? (isCompact ? 14 : 17) : (isCompact ? 11 : 13),
            ),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: EdgeInsets.symmetric(horizontal: isCompact ? 6 : 12, vertical: isCompact ? 6 : 10),
      decoration: BoxDecoration(
        color: isGrand ? const Color(0xFFFBBC05).withOpacity(0.15) : const Color(0xFF162E24).withOpacity(0.6),
        borderRadius: BorderRadius.circular(8),
        border: isGrand ? Border.all(color: const Color(0xFFFBBC05), width: 1.2) : null,
      ),
      child: Row(children: cells),
    );
  }

  Widget _buildLeaderboardDrawer() {
    return Drawer(
      backgroundColor: const Color(0xFF0B1C15),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              color: const Color(0xFF162E24),
              child: const Row(
                children: [
                  Icon(Icons.emoji_events, color: Color(0xFFFACC15), size: 28),
                  SizedBox(width: 12),
                  Text(
                    'LEADERBOARD',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: 1.5),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _leaderboard.isEmpty
                  ? const Center(child: CircularProgressIndicator())
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
                            color: const Color(0xFF162E24),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: rank <= 3 ? const Color(0xFFFACC15).withOpacity(0.3) : Colors.transparent,
                            ),
                          ),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 35,
                                child: Text(
                                  rankSymbol,
                                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  name,
                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                ),
                              ),
                              Text(
                                '$score pts',
                                style: const TextStyle(color: Color(0xFFFACC15), fontWeight: FontWeight.bold),
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

import 'package:flame/game.dart';
import 'package:flutter/material.dart';
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
      title: 'Open-Yatzy',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0B0F19),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF4285F4), // Google Blue
          secondary: Color(0xFFFBBC05), // Google Yellow
          surface: Color(0xFF1E293B), // Slate Surface
          background: const Color(0xFF0B0F19),
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
      },
    );
    _initSocial();
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

  void _rollDice() {
    if (_engine.rollsRemaining > 0 && !_engine.isGameOver && !_isRolling) {
      setState(() {
        _engine.rollDice();
        _isRolling = true;
      });
      _game.triggerRollAnimation();
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
      return; // Block scoring during animation
    }
    
    final succeeded = _engine.selectCategory(category);
    if (succeeded) {
      _game.resetVisuals();
      setState(() {
        _isRolling = false;
      });

      if (_engine.isGameOver) {
        // Submit highest score among players to the global leaderboard
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
      }
    }
  }

  void _resetGame() {
    setState(() {
      _engine.resetGame();
      _game.resetVisuals();
      _isRolling = false;
    });
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
        backgroundColor: const Color(0xFF0B0F19),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.grey),
          onPressed: () {
            setState(() {
              _isGameStarted = false;
            });
          },
        ),
        title: const Text(
          'OPEN-YATZY',
          style: TextStyle(letterSpacing: 2, fontWeight: FontWeight.w900, color: Colors.white),
        ),
        actions: [
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
                color: const Color(0xFF1E293B),
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.person, color: Color(0xFFFACC15), size: 18),
                    const SizedBox(width: 8),
                    Text(
                      "TURN: ${_engine.playerNames[_engine.activePlayerIndex].toUpperCase()}",
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.5,
                        color: Color(0xFFFACC15),
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
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFF334155), width: 1.5),
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
                        backgroundColor: const Color(0xFF4285F4),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: const BorderSide(color: Color(0xFF669DF6), width: 1.5),
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
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 24),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF4285F4).withOpacity(0.3),
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
                    'OPEN-YATZY',
                    style: TextStyle(
                      fontSize: 36,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 4,
                      color: Colors.white,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Open-Gaming Local Pass & Play',
                    style: TextStyle(color: Colors.grey, fontSize: 16),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 40),
                  
                  // Player Count card
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFF334155)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Number of Players',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFFFACC15)),
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
                                  color: selected ? const Color(0xFF4285F4) : const Color(0xFF0F172A),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: selected ? const Color(0xFF669DF6) : const Color(0xFF334155),
                                    width: 1.5,
                                  ),
                                ),
                                child: Text(
                                  '$count',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 18,
                                    color: selected ? Colors.white : Colors.grey,
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
                      color: const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFF334155)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Player Names',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFFFACC15)),
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
                                fillColor: const Color(0xFF0F172A),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: const BorderSide(color: Color(0xFF334155)),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: const BorderSide(color: Color(0xFF4285F4)),
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
                      backgroundColor: const Color(0xFF4285F4),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      elevation: 4,
                    ),
                    child: const Text(
                      'START MATCH',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1.5, color: Colors.white),
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
              color: isActive ? const Color(0xFF4285F4).withOpacity(0.3) : Colors.transparent,
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
        color: const Color(0xFF1E293B),
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
              color: isActive ? const Color(0xFF4285F4).withOpacity(0.08) : Colors.transparent,
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
            color: isClickable && showPreview ? const Color(0xFF334155) : Colors.transparent,
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
            color: isGrand ? const Color(0xFF4285F4) : Colors.white,
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
        color: isGrand ? const Color(0xFF4285F4).withOpacity(0.12) : const Color(0xFF1E293B).withOpacity(0.6),
        borderRadius: BorderRadius.circular(8),
        border: isGrand ? Border.all(color: const Color(0xFF4285F4), width: 1.2) : null,
      ),
      child: Row(children: cells),
    );
  }

  Widget _buildLeaderboardDrawer() {
    return Drawer(
      backgroundColor: const Color(0xFF0F172A),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              color: const Color(0xFF1E293B),
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
                            color: const Color(0xFF1E293B),
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

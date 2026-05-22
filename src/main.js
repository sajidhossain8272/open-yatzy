import { YatzyEngine, ScoringCategory } from './engine.js';
import { DiceComponent } from './dice.js';
import { SocialPlatform } from './social.js';

// Setup elements
const canvas = document.getElementById('game-canvas');
const ctx = canvas.getContext('2d');
const btnRoll = document.getElementById('btn-roll');
const btnReset = document.getElementById('btn-reset');
const btnLogin = document.getElementById('btn-login');
const btnLeaderboard = document.getElementById('btn-leaderboard');
const drawer = document.getElementById('leaderboard-drawer');
const drawerClose = document.getElementById('drawer-close');
const leaderboardList = document.getElementById('leaderboard-list');
const userDisplay = document.getElementById('user-display');
const rollsRemainingText = document.getElementById('rolls-remaining');
const statusDescText = document.getElementById('status-desc');
const tableContainer = document.getElementById('scorecard-table-container');

// Modal Elements
const modal = document.getElementById('gameover-modal');

// Instantiate state classes
const engine = new YatzyEngine();
const social = new SocialPlatform();
const diceComponents = [];

// Physics / Loop timer variables
let lastTime = performance.now();
const diceSize = 75;

// Multiplayer setup state
let selectedPlayerCount = 1;
let isDiceRolling = false;

// Category labels
const categoryLabels = {
  [ScoringCategory.ONES]: 'Ones',
  [ScoringCategory.TWOS]: 'Twos',
  [ScoringCategory.THREES]: 'Threes',
  [ScoringCategory.FOURS]: 'Fours',
  [ScoringCategory.FIVES]: 'Fives',
  [ScoringCategory.SIXES]: 'Sixes',
  [ScoringCategory.THREE_OF_A_KIND]: 'Three of a Kind',
  [ScoringCategory.FOUR_OF_A_KIND]: 'Four of a Kind',
  [ScoringCategory.FULL_HOUSE]: 'Full House',
  [ScoringCategory.SMALL_STRAIGHT]: 'Small Straight',
  [ScoringCategory.LARGE_STRAIGHT]: 'Large Straight',
  [ScoringCategory.YATZY]: 'Yatzy!',
  [ScoringCategory.CHANCE]: 'Chance'
};

const categoryInstructions = {
  [ScoringCategory.ONES]: 'Score sum of 1s',
  [ScoringCategory.TWOS]: 'Score sum of 2s',
  [ScoringCategory.THREES]: 'Score sum of 3s',
  [ScoringCategory.FOURS]: 'Score sum of 4s',
  [ScoringCategory.FIVES]: 'Score sum of 5s',
  [ScoringCategory.SIXES]: 'Score sum of 6s',
  [ScoringCategory.THREE_OF_A_KIND]: 'Sum if 3+ matching',
  [ScoringCategory.FOUR_OF_A_KIND]: 'Sum if 4+ matching',
  [ScoringCategory.FULL_HOUSE]: '3 of kind + pair (25)',
  [ScoringCategory.SMALL_STRAIGHT]: 'Sequence of 4 (30)',
  [ScoringCategory.LARGE_STRAIGHT]: 'Sequence of 5 (40)',
  [ScoringCategory.YATZY]: '5 matching (50)',
  [ScoringCategory.CHANCE]: 'Sum of all 5 dice'
};

const categoryIcons = {
  [ScoringCategory.ONES]: 'looks_one',
  [ScoringCategory.TWOS]: 'looks_two',
  [ScoringCategory.THREES]: 'looks_3',
  [ScoringCategory.FOURS]: 'looks_4',
  [ScoringCategory.FIVES]: 'looks_5',
  [ScoringCategory.SIXES]: 'looks_6',
  [ScoringCategory.THREE_OF_A_KIND]: 'filter_3',
  [ScoringCategory.FOUR_OF_A_KIND]: 'filter_4',
  [ScoringCategory.FULL_HOUSE]: 'home',
  [ScoringCategory.SMALL_STRAIGHT]: 'linear_scale',
  [ScoringCategory.LARGE_STRAIGHT]: 'forward',
  [ScoringCategory.YATZY]: 'emoji_events',
  [ScoringCategory.CHANCE]: 'help_outline'
};

const upperCategories = [
  ScoringCategory.ONES,
  ScoringCategory.TWOS,
  ScoringCategory.THREES,
  ScoringCategory.FOURS,
  ScoringCategory.FIVES,
  ScoringCategory.SIXES
];

const lowerCategories = [
  ScoringCategory.THREE_OF_A_KIND,
  ScoringCategory.FOUR_OF_A_KIND,
  ScoringCategory.FULL_HOUSE,
  ScoringCategory.SMALL_STRAIGHT,
  ScoringCategory.LARGE_STRAIGHT,
  ScoringCategory.YATZY,
  ScoringCategory.CHANCE
];

// Theme Icon Sync
function updateThemeToggleIcons(theme) {
  const iconName = theme === 'light' ? 'dark_mode' : 'light_mode';
  const setupIcon = document.querySelector('#btn-theme-toggle-setup .material-symbols-outlined');
  const gameIcon = document.querySelector('#btn-theme-toggle-game .material-symbols-outlined');
  if (setupIcon) setupIcon.innerText = iconName;
  if (gameIcon) gameIcon.innerText = iconName;
}

// Initialization
function init() {
  // Load and apply saved theme
  const savedTheme = localStorage.getItem('theme') || 'dark';
  if (savedTheme === 'light') {
    document.body.classList.add('light-theme');
    updateThemeToggleIcons('light');
  } else {
    document.body.classList.remove('light-theme');
    updateThemeToggleIcons('dark');
  }

  // Bind theme toggle buttons
  const themeToggleSetup = document.getElementById('btn-theme-toggle-setup');
  const themeToggleGame = document.getElementById('btn-theme-toggle-game');

  const toggleTheme = () => {
    const isLight = document.body.classList.toggle('light-theme');
    const newTheme = isLight ? 'light' : 'dark';
    localStorage.setItem('theme', newTheme);
    updateThemeToggleIcons(newTheme);
  };

  if (themeToggleSetup) themeToggleSetup.addEventListener('click', toggleTheme);
  if (themeToggleGame) themeToggleGame.addEventListener('click', toggleTheme);

  // Bind setup count selector
  setupCountSelector();
  updateNameInputs();

  // Set up social SDK
  social.initialize().then(() => {
    updateSocialHeader();
    refreshLeaderboard();
  });

  // Bind main window events
  window.addEventListener('resize', onResize);
  canvas.addEventListener('mousedown', onCanvasClick);
  canvas.addEventListener('touchstart', onCanvasTouch, { passive: true });

  // Bind controls
  btnRoll.addEventListener('click', rollDice);
  btnReset.addEventListener('click', resetGame);
  btnLogin.addEventListener('click', loginSocial);
  btnLeaderboard.addEventListener('click', openLeaderboard);
  drawerClose.addEventListener('click', closeLeaderboard);

  // Back to setup screen
  document.getElementById('btn-back').addEventListener('click', () => {
    document.getElementById('game-screen').style.display = 'none';
    document.getElementById('setup-screen').style.display = 'flex';
  });

  // Start match
  document.getElementById('btn-start').addEventListener('click', () => {
    const names = [];
    for (let i = 1; i <= selectedPlayerCount; i++) {
      const val = document.getElementById(`input-p${i}`).value.trim();
      names.push(val !== '' ? val : `Player ${i}`);
    }

    engine.setupPlayers(selectedPlayerCount, names);

    // Swap views
    document.getElementById('setup-screen').style.display = 'none';
    document.getElementById('game-screen').style.display = 'flex';

    // Refresh layout and sizes
    resizeCanvas();
    setupDice();
    updateUI();
  });

  // Confirm turn handoff
  document.getElementById('btn-handoff-confirm').addEventListener('click', () => {
    document.getElementById('handoff-modal').classList.remove('open');
    updateUI();
  });

  // Table category click event delegation
  tableContainer.addEventListener('click', (e) => {
    const row = e.target.closest('.category-row.clickable');
    if (row) {
      const category = row.dataset.category;
      selectCategory(category);
    }
  });

  // Start with Setup screen
  document.getElementById('setup-screen').style.display = 'flex';
  document.getElementById('game-screen').style.display = 'none';

  // Start animation loop
  requestAnimationFrame(loop);
}

// Player Setup controller
function setupCountSelector() {
  const countButtons = document.querySelectorAll('.btn-count');
  countButtons.forEach(btn => {
    btn.addEventListener('click', () => {
      countButtons.forEach(b => b.classList.remove('active'));
      btn.classList.add('active');
      selectedPlayerCount = parseInt(btn.dataset.count, 10);
      updateNameInputs();
    });
  });
}

function updateNameInputs() {
  const container = document.getElementById('player-names-container');
  container.innerHTML = '';
  for (let i = 1; i <= selectedPlayerCount; i++) {
    const input = document.createElement('input');
    input.type = 'text';
    input.className = 'input-field';
    input.id = `input-p${i}`;
    input.value = `Player ${i}`;
    input.placeholder = `Player ${i} Name`;
    container.appendChild(input);
  }
}

// Responsive layout adjusting
function resizeCanvas() {
  const rect = canvas.parentElement.getBoundingClientRect();
  if (rect.width === 0 || rect.height === 0) return;

  const dpr = window.devicePixelRatio || 1;
  canvas.width = rect.width * dpr;
  canvas.height = rect.height * dpr;

  canvas.style.width = rect.width + 'px';
  canvas.style.height = rect.height + 'px';

  ctx.scale(dpr, dpr);
}

function setupDice() {
  diceComponents.length = 0;
  const rect = canvas.getBoundingClientRect();
  if (rect.width === 0) return;

  const spacing = rect.width / 6;
  const centerY = rect.height / 2;
  const dynamicDiceSize = Math.min(75, rect.width / 6.5);

  for (let i = 0; i < 5; i++) {
    const x = spacing * (i + 1);
    const y = centerY;

    const die = new DiceComponent(i, x, y, dynamicDiceSize, () => {
      if (engine.rollsRemaining === 3 || engine.rollsRemaining < 0 || engine.isGameOver || isDiceRolling) return;
      const succeeded = engine.toggleHold(i);
      if (succeeded) {
        die.held = engine.heldDice[i];
        die.triggerTapBounce();
        updateUI();
      }
    });

    die.visualValue = engine.diceValues[i];
    die.held = engine.heldDice[i];
    diceComponents.push(die);
  }
}

function onResize() {
  resizeCanvas();

  const rect = canvas.getBoundingClientRect();
  if (rect.width === 0) return;

  const spacing = rect.width / 6;
  const centerY = rect.height / 2;
  const dynamicDiceSize = Math.min(75, rect.width / 6.5);

  diceComponents.forEach((die, i) => {
    die.x = spacing * (i + 1);
    die.y = centerY;
    die.size = dynamicDiceSize;
  });
}

// Input routing
function getCanvasMouseCoords(e) {
  const rect = canvas.getBoundingClientRect();
  const mx = e.clientX - rect.left;
  const my = e.clientY - rect.top;
  return { mx, my };
}

function onCanvasClick(e) {
  const { mx, my } = getCanvasMouseCoords(e);
  handleTap(mx, my);
}

function onCanvasTouch(e) {
  if (e.touches.length === 0) return;
  const touch = e.touches[0];
  const rect = canvas.getBoundingClientRect();
  const mx = touch.clientX - rect.left;
  const my = touch.clientY - rect.top;
  handleTap(mx, my);
}

function handleTap(mx, my) {
  diceComponents.forEach(die => {
    if (die.isTapped(mx, my)) {
      die.onTap();
    }
  });
}

// Actions
function rollDice() {
  if (engine.rollsRemaining > 0 && !engine.isGameOver && !isDiceRolling) {
    isDiceRolling = true;
    engine.rollDice();

    // Sync components and trigger rolls
    diceComponents.forEach((die, i) => {
      die.held = engine.heldDice[i];
      if (!die.held || engine.rollsRemaining === 2) {
        die.roll(engine.diceValues[i]);
      }
    });

    updateUI();
  }
}

function selectCategory(category) {
  if (engine.rollsRemaining === 3) {
    alert('Roll the dice first before choosing a category!');
    return;
  }
  if (isDiceRolling) {
    return;
  }

  const succeeded = engine.selectCategory(category);
  if (succeeded) {
    // Reset visual die statuses
    diceComponents.forEach(die => {
      die.held = false;
      die.visualValue = 1;
      die.targetValue = 1;
      die.angle = 0;
      die.scaleFactor = 1.0;
    });

    if (engine.isGameOver) {
      let maxScore = 0;
      for (let i = 0; i < engine.playerCount; i++) {
        const score = engine.getTotalScore(i);
        if (score > maxScore) maxScore = score;
      }
      social.submitScore(maxScore).then(() => {
        refreshLeaderboard();
        showGameOver();
      });
    } else {
      if (engine.playerCount > 1) {
        const nextPlayerName = engine.playerNames[engine.activePlayerIndex];
        showHandoffModal(nextPlayerName);
      } else {
        updateUI();
      }
    }
  }
}

function resetGame() {
  engine.resetGame();

  // Clear visual die holds
  diceComponents.forEach(die => {
    die.held = false;
    die.visualValue = 1;
    die.targetValue = 1;
    die.angle = 0;
    die.scaleFactor = 1.0;
  });

  modal.classList.remove('open');
  updateUI();
}

function showHandoffModal(playerName) {
  const handoffModal = document.getElementById('handoff-modal');
  const handoffPlayerName = document.getElementById('handoff-player-name');
  handoffPlayerName.innerText = playerName;
  handoffModal.classList.add('open');
}

function showGameOver() {
  const playerRankings = [];
  for (let i = 0; i < engine.playerCount; i++) {
    playerRankings.push({
      name: engine.playerNames[i],
      score: engine.getTotalScore(i)
    });
  }
  playerRankings.sort((a, b) => b.score - a.score);

  const modalContent = modal.querySelector('.modal-content');

  let rankingsHtml = `
    <div class="modal-title">🏆 Match Completed!</div>
    <div style="color: var(--color-text-secondary); font-size: 14px; margin-bottom: 8px;">Final standings:</div>
    <div class="ranking-container">
  `;

  playerRankings.forEach((player, index) => {
    let rankEmoji = `${index + 1}.`;
    if (index === 0) rankEmoji = '🥇';
    else if (index === 1) rankEmoji = '🥈';
    else if (index === 2) rankEmoji = '🥉';

    const isWinner = index === 0;
    rankingsHtml += `
      <div class="ranking-item ${isWinner ? 'winner' : ''}">
        <div style="display: flex; align-items: center; gap: 8px;">
          <span>${rankEmoji}</span>
          <span>${player.name}</span>
        </div>
        <span>${player.score} pts</span>
      </div>
    `;
  });

  rankingsHtml += `
    </div>
    <button id="modal-restart" class="btn-roll" style="width: auto; margin-top: 10px;">
      Back to Menu
    </button>
  `;

  modalContent.innerHTML = rankingsHtml;

  document.getElementById('modal-restart').addEventListener('click', () => {
    modal.classList.remove('open');
    document.getElementById('game-screen').style.display = 'none';
    document.getElementById('setup-screen').style.display = 'flex';
  });

  modal.classList.add('open');
}

// UI Updating
function updateUI() {
  // Update turn strip player name
  const activePlayerName = engine.playerNames[engine.activePlayerIndex];
  document.getElementById('active-player-name').innerText = `TURN: ${activePlayerName.toUpperCase()}`;

  // Update turn metadata
  rollsRemainingText.innerText = `ROLLS REMAINING: ${engine.rollsRemaining}/3`;

  if (engine.rollsRemaining === 3) {
    statusDescText.innerText = "Roll dice to begin!";
  } else if (engine.rollsRemaining === 0) {
    statusDescText.innerText = "Select score category";
  } else {
    statusDescText.innerText = "Tap to hold, roll again!";
  }

  // Roll button state
  btnRoll.disabled = (engine.rollsRemaining === 0 || engine.isGameOver || isDiceRolling);

  // Render dynamic scorecard table
  renderScorecard();
}

function renderScorecard() {
  const pCount = engine.playerCount;
  const activeIdx = engine.activePlayerIndex;
  const hasRolled = engine.rollsRemaining < 3;

  // Render Upper Section Table
  let upperHtml = `<table class="scorecard-table">`;
  upperHtml += `<thead><tr><th>UPPER SECTION</th>`;
  for (let i = 0; i < pCount; i++) {
    const isActive = i === activeIdx;
    let name = engine.playerNames[i];
    if (name.length > 8) name = name.substring(0, 6) + '..';
    const activeClass = isActive ? ' class="active-column-header"' : '';
    upperHtml += `<th${activeClass}>${name.toUpperCase()}</th>`;
  }
  upperHtml += `</tr></thead><tbody>`;

  upperCategories.forEach(cat => {
    upperHtml += renderCategoryRow(cat, pCount, activeIdx, hasRolled);
  });

  upperHtml += `<tr class="summary-row-tr"><td>Subtotal</td>`;
  for (let i = 0; i < pCount; i++) {
    const isActive = i === activeIdx;
    const cellClass = isActive ? ' class="active-column-cell"' : '';
    upperHtml += `<td${cellClass}>${engine.getUpperSectionSum(i)}</td>`;
  }
  upperHtml += `</tr>`;

  upperHtml += `<tr class="summary-row-tr"><td>Bonus (+35)</td>`;
  for (let i = 0; i < pCount; i++) {
    const isActive = i === activeIdx;
    const cellClass = isActive ? ' class="active-column-cell"' : '';
    upperHtml += `<td${cellClass}>+${engine.getUpperSectionBonus(i)}</td>`;
  }
  upperHtml += `</tr>`;
  upperHtml += `</tbody></table>`;

  // Render Lower Section Table
  let lowerHtml = `<table class="scorecard-table">`;
  lowerHtml += `<thead><tr><th>LOWER SECTION</th>`;
  for (let i = 0; i < pCount; i++) {
    const isActive = i === activeIdx;
    let name = engine.playerNames[i];
    if (name.length > 8) name = name.substring(0, 6) + '..';
    const activeClass = isActive ? ' class="active-column-header"' : '';
    lowerHtml += `<th${activeClass}>${name.toUpperCase()}</th>`;
  }
  lowerHtml += `</tr></thead><tbody>`;

  lowerCategories.forEach(cat => {
    lowerHtml += renderCategoryRow(cat, pCount, activeIdx, hasRolled);
  });

  lowerHtml += `<tr class="summary-row-tr"><td>Subtotal</td>`;
  for (let i = 0; i < pCount; i++) {
    const isActive = i === activeIdx;
    const cellClass = isActive ? ' class="active-column-cell"' : '';
    lowerHtml += `<td${cellClass}>${engine.getLowerSectionSum(i)}</td>`;
  }
  lowerHtml += `</tr>`;

  lowerHtml += `<tr class="summary-row-tr grand-total"><td>GRAND TOTAL</td>`;
  for (let i = 0; i < pCount; i++) {
    const isActive = i === activeIdx;
    const cellClass = isActive ? ' class="active-column-cell grand-val"' : ' class="grand-val"';
    lowerHtml += `<td${cellClass}>${engine.getTotalScore(i)}</td>`;
  }
  lowerHtml += `</tr>`;
  lowerHtml += `</tbody></table>`;

  const playerClass = pCount > 2 ? 'many-players' : 'few-players';
  tableContainer.innerHTML = `
    <div class="scorecard-tables-flex ${playerClass}">
      <div class="scorecard-table-wrapper upper-wrapper">
        ${upperHtml}
      </div>
      <div class="scorecard-table-wrapper lower-wrapper">
        ${lowerHtml}
      </div>
    </div>
  `;
}

function renderCategoryRow(cat, pCount, activeIdx, hasRolled) {
  const label = categoryLabels[cat];
  const isFilled = engine.scorecards[activeIdx][cat] !== null;
  const isClickable = !isFilled && !engine.isGameOver && !isDiceRolling;
  const showPreview = hasRolled && !isDiceRolling;

  const rowClass = `class="category-row ${isClickable ? 'clickable' : ''} ${isClickable && showPreview ? 'active-roll' : ''}"`;

  const diceMap = {
    [ScoringCategory.ONES]: { val: 1, char: '⚀' },
    [ScoringCategory.TWOS]: { val: 2, char: '⚁' },
    [ScoringCategory.THREES]: { val: 3, char: '⚂' },
    [ScoringCategory.FOURS]: { val: 4, char: '⚃' },
    [ScoringCategory.FIVES]: { val: 5, char: '⚄' },
    [ScoringCategory.SIXES]: { val: 6, char: '⚅' }
  };

  const instruction = categoryInstructions[cat] || '';
  const icon = categoryIcons[cat] || 'casino';

  let labelHtml = `
    <div class="category-label-container">
      <span class="material-symbols-outlined category-row-icon">
        ${icon}
      </span>
      <div class="category-text-block">
        <div class="category-title-row">
          <span class="category-name">${label}</span>
  `;
  
  if (diceMap[cat]) {
    const d = diceMap[cat];
    labelHtml += `
          <span class="inline-die-icon" title="Scoring target: ${d.val}">${d.char}</span>
    `;
  }
  
  labelHtml += `
        </div>
        <div class="category-instruction">${instruction}</div>
      </div>
    </div>
  `;

  let rowHtml = `<tr ${rowClass} data-category="${cat}">`;
  rowHtml += `<td>${labelHtml}</td>`;

  for (let i = 0; i < pCount; i++) {
    const actualScore = engine.scorecards[i][cat];
    const isActive = i === activeIdx;
    const cellClass = isActive ? ' class="active-column-cell"' : '';

    if (actualScore !== null) {
      rowHtml += `<td${cellClass}><span class="cell-value">${actualScore}</span></td>`;
    } else if (isActive && showPreview) {
      const preview = engine.calculateScore(cat, engine.diceValues);
      rowHtml += `<td${cellClass}><span class="cell-value preview">${preview}</span></td>`;
    } else {
      rowHtml += `<td${cellClass}><span class="cell-value empty">-</span></td>`;
    }
  }
  rowHtml += `</tr>`;
  return rowHtml;
}

// Social Platform Sync
function updateSocialHeader() {
  if (social.currentUser) {
    btnLogin.style.display = 'none';
    userDisplay.style.display = 'inline';
    userDisplay.innerText = social.currentUser.displayName;
  } else {
    btnLogin.style.display = 'inline';
    userDisplay.style.display = 'none';
  }
}

function loginSocial() {
  social.login().then(user => {
    if (user) {
      updateSocialHeader();
      let maxScore = 0;
      for (let i = 0; i < engine.playerCount; i++) {
        const score = engine.getTotalScore(i);
        if (score > maxScore) maxScore = score;
      }
      social.submitScore(maxScore).then(() => {
        refreshLeaderboard();
      });
    }
  });
}

function openLeaderboard() {
  refreshLeaderboard();
  drawer.classList.add('open');
}

function closeLeaderboard() {
  drawer.classList.remove('open');
}

function refreshLeaderboard() {
  social.getLeaderboard().then(list => {
    leaderboardList.innerHTML = '';
    list.forEach(entry => {
      const item = document.createElement('div');
      const isTopThree = entry.rank <= 3;
      item.className = `leaderboard-item ${isTopThree ? 'top-three' : ''}`;

      let rankText = entry.rank;
      if (entry.rank === 1) rankText = '🥇';
      else if (entry.rank === 2) rankText = '🥈';
      else if (entry.rank === 3) rankText = '🥉';

      item.innerHTML = `
        <div class="leaderboard-rank">${rankText}</div>
        <div class="leaderboard-name">${entry.name}</div>
        <div class="leaderboard-score">${entry.score} pts</div>
      `;
      leaderboardList.appendChild(item);
    });
  });
}

// Animation loop
function loop(time) {
  const dt = (time - lastTime) / 1000;
  lastTime = time;

  // Clear canvas
  const rect = canvas.getBoundingClientRect();
  if (rect.width > 0 && rect.height > 0) {
    ctx.clearRect(0, 0, rect.width, rect.height);

    // Update and draw dice components
    diceComponents.forEach(die => {
      die.update(dt);
      die.draw(ctx);
    });
  }

  // Check if dice completed rolling
  const currentlyRolling = diceComponents.some(die => die.rollTimer > 0);
  if (isDiceRolling && !currentlyRolling) {
    isDiceRolling = false;
    updateUI(); // Re-render to show previews and enable clicks now that roll is revealed!
  }

  requestAnimationFrame(loop);
}

// Launch application
init();

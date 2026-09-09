import 'dart:math';

import 'package:flutter/material.dart';

void main() {
  runApp(const GraskoenigApp());
}

const int handLimit = 5;
const int maxTurnsPerPlayerPerRound = 6;

enum CardType { grass, energy, base, attack, defense, action }

class GameCard {
  final CardType type;
  final String title;
  final String value;
  final String effect;
  final int power;

  const GameCard({
    required this.type,
    required this.title,
    required this.value,
    required this.effect,
    this.power = 0,
  });
}

GameCard grassCard(int power) {
  switch (power) {
    case 20:
      return const GameCard(type: CardType.grass, title: 'Kleiner Beutel', value: '20 g', effect: 'Klein, aber fein.', power: 20);
    case 50:
      return const GameCard(type: CardType.grass, title: 'Solide Ernte', value: '50 g', effect: 'Es wird was.', power: 50);
    case 100:
      return const GameCard(type: CardType.grass, title: 'Fette Ernte', value: '100 g', effect: 'Jetzt wird’s ernst.', power: 100);
    default:
      return const GameCard(type: CardType.grass, title: 'Maximum', value: '200 g', effect: 'Maximum.', power: 200);
  }
}

GameCard energyCard(int power) {
  switch (power) {
    case 25:
      return const GameCard(type: CardType.energy, title: 'Notstrom', value: '25 %', effect: 'Ein bisschen reicht.', power: 25);
    case 50:
      return const GameCard(type: CardType.energy, title: 'Kellerstrom', value: '50 %', effect: 'Läuft.', power: 50);
    case 75:
      return const GameCard(type: CardType.energy, title: 'Grow Power', value: '75 %', effect: 'Schon ordentlich.', power: 75);
    default:
      return const GameCard(type: CardType.energy, title: 'Volle Power', value: '100 %', effect: 'Volle Power.', power: 100);
  }
}

List<GameCard> buildDeck() {
  final deck = <GameCard>[];

  void addCards(int amount, CardType type, String title, String value, String effect, {int power = 0}) {
    for (int i = 0; i < amount; i++) {
      deck.add(GameCard(type: type, title: title, value: value, effect: effect, power: power));
    }
  }

  addCards(4, CardType.grass, 'Kleiner Beutel', '20 g', 'Klein, aber fein.', power: 20);
  addCards(5, CardType.grass, 'Solide Ernte', '50 g', 'Es wird was.', power: 50);
  addCards(4, CardType.grass, 'Fette Ernte', '100 g', 'Jetzt wird’s ernst.', power: 100);
  addCards(3, CardType.grass, 'Maximum', '200 g', 'Maximum.', power: 200);

  addCards(3, CardType.energy, 'Notstrom', '25 %', 'Ein bisschen reicht.', power: 25);
  addCards(4, CardType.energy, 'Kellerstrom', '50 %', 'Läuft.', power: 50);
  addCards(4, CardType.energy, 'Grow Power', '75 %', 'Schon ordentlich.', power: 75);
  addCards(3, CardType.energy, 'Volle Power', '100 %', 'Volle Power.', power: 100);

  addCards(4, CardType.base, 'Kumpel um die Ecke', '×2', 'Regional. Loyal.', power: 2);
  addCards(3, CardType.base, 'Dealer', '×3', 'Schnelle Verbindungen.', power: 3);
  addCards(3, CardType.base, 'Growshop', '×3', 'Alles was du brauchst.', power: 3);
  addCards(2, CardType.base, 'Graskönig', '×4', 'Das Nonplusultra.', power: 4);

  addCards(2, CardType.attack, 'Stromausfall', '💥', 'Energie eines Gegners −1 Stufe.');
  addCards(2, CardType.attack, 'Energiediebstahl', '💥', 'Tausche deine Energie mit der eines Gegners.');
  addCards(2, CardType.attack, 'Schädlingsbefall', '💥', 'Gras eines Gegners −1 Stufe.');
  addCards(2, CardType.attack, 'Razzia', '💥', 'Ein Gegner legt 1 zufällige Handkarte ab.');
  addCards(2, CardType.attack, 'Zu platt', '💥', 'Ein Gegner überspringt seinen nächsten Zug.');

  addCards(2, CardType.defense, 'Sicherungskasten', '🛡️', 'Stoppt Stromausfall.');
  addCards(1, CardType.defense, 'Wachhund', '🛡️', 'Stoppt Energiediebstahl.');
  addCards(1, CardType.defense, 'Schädlingsmittel', '🛡️', 'Stoppt Schädlingsbefall.');
  addCards(2, CardType.defense, 'Anwalt', '🛡️', 'Stoppt Razzia oder Zu platt.');
  addCards(2, CardType.defense, 'Alles easy', '🛡️', 'Stoppt jeden Angriff.');

  addCards(3, CardType.action, 'Dünger', '★', 'Gras +1 Stufe.');
  addCards(3, CardType.action, 'Gartenschere', '★', 'Ziehe 2 Karten, behalte 1.');
  addCards(2, CardType.action, 'Übertopf', '★', 'Gras bis zu deinem nächsten Zug geschützt.');
  addCards(2, CardType.action, 'Beste Freunde', '★', 'Tausche blind 1 Handkarte.');
  addCards(2, CardType.action, 'Glückstreffer', '★', 'Ziehe 3 Karten, behalte 1.');
  addCards(2, CardType.action, 'Ich zieh mir zwei', '★', 'Ziehe 2 Karten.');

  return deck;
}

class GraskoenigApp extends StatelessWidget {
  const GraskoenigApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Graskönig',
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF021D10),
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF147A3F), brightness: Brightness.dark),
        useMaterial3: true,
      ),
      home: const StartScreen(),
    );
  }
}

class StartScreen extends StatelessWidget {
  const StartScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('👑', style: TextStyle(fontSize: 90)),
            const SizedBox(height: 10),
            const Text('GRASKÖNIG', style: TextStyle(fontSize: 48, fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            const Text('GUTE FREUNDE. GUTER GROW.', style: TextStyle(color: Color(0xFF92EF65), letterSpacing: 2)),
            const SizedBox(height: 60),
            SizedBox(
              width: 280,
              height: 60,
              child: FilledButton(
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PlayerSetupScreen())),
                child: const Text('SPIEL STARTEN', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class PlayerSetupScreen extends StatefulWidget {
  const PlayerSetupScreen({super.key});

  @override
  State<PlayerSetupScreen> createState() => _PlayerSetupScreenState();
}

class _PlayerSetupScreenState extends State<PlayerSetupScreen> {
  int playerCount = 4;

  final controllers = [
    TextEditingController(text: 'Spieler 1'),
    TextEditingController(text: 'Spieler 2'),
    TextEditingController(text: 'Spieler 3'),
    TextEditingController(text: 'Spieler 4'),
    TextEditingController(text: 'Spieler 5'),
    TextEditingController(text: 'Spieler 6'),
  ];

  @override
  void dispose() {
    for (final controller in controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Neues Spiel')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Text('Wie viele Spieler?', style: TextStyle(fontSize: 25, fontWeight: FontWeight.bold)),
          const SizedBox(height: 20),
          Wrap(
            spacing: 10,
            children: List.generate(5, (index) {
              final number = index + 2;
              return ChoiceChip(
                label: Text('$number'),
                selected: playerCount == number,
                onSelected: (_) => setState(() => playerCount = number),
              );
            }),
          ),
          const SizedBox(height: 30),
          ...List.generate(
            playerCount,
            (index) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: TextField(
                controller: controllers[index],
                decoration: InputDecoration(labelText: 'Spieler ${index + 1}', border: const OutlineInputBorder()),
              ),
            ),
          ),
          const SizedBox(height: 25),
          SizedBox(
            height: 60,
            child: FilledButton(
              onPressed: () {
                final players = List.generate(playerCount, (index) => controllers[index].text.trim());
                Navigator.push(context, MaterialPageRoute(builder: (_) => GameScreen(players: players)));
              },
              child: const Text('KARTEN AUSTEILEN', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }
}

class GameScreen extends StatefulWidget {
  final List<String> players;

  const GameScreen({super.key, required this.players});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  late List<GameCard> deck;
  late List<List<GameCard>> hands;
  late List<GameCard?> grassSlots;
  late List<GameCard?> energySlots;
  late List<GameCard?> baseSlots;
  late List<bool> skipNextTurn;
  late List<bool> grassProtected;
  late List<int> completedTurns;

  late List<int> totalScores;
  late List<int> roundWins;

  final discardPile = <GameCard>[];
  final random = Random();

  int currentPlayer = 0;
  int roundNumber = 1;
  int? selectedCardIndex;

  bool hasDrawn = false;
  bool turnFinished = false;

  bool knockActive = false;
  bool roundEnding = false;
  int? knockingPlayer;
  final Set<int> finalTurnsRemaining = <int>{};

  @override
  void initState() {
    super.initState();
    totalScores = List<int>.filled(widget.players.length, 0);
    roundWins = List<int>.filled(widget.players.length, 0);
    startRound();
  }

  // ==========================================================
  // RUNDE STARTEN
  // ==========================================================

  void startRound() {
    deck = buildDeck()..shuffle();
    discardPile.clear();

    hands = List.generate(widget.players.length, (_) => []);
    grassSlots = List<GameCard?>.filled(widget.players.length, null);
    energySlots = List<GameCard?>.filled(widget.players.length, null);
    baseSlots = List<GameCard?>.filled(widget.players.length, null);
    skipNextTurn = List<bool>.filled(widget.players.length, false);
    grassProtected = List<bool>.filled(widget.players.length, false);
    completedTurns = List<int>.filled(widget.players.length, 0);

    knockActive = false;
    roundEnding = false;
    knockingPlayer = null;
    finalTurnsRemaining.clear();

    currentPlayer = (roundNumber - 1) % widget.players.length;
    selectedCardIndex = null;
    hasDrawn = false;
    turnFinished = false;

    for (int card = 0; card < 5; card++) {
      for (int player = 0; player < widget.players.length; player++) {
        final next = drawFromDeck();
        if (next != null) {
          hands[player].add(next);
        }
      }
    }
  }

  // ==========================================================
  // DECK
  // ==========================================================

  void recycleDiscardIfNeeded() {
    if (deck.isEmpty && discardPile.isNotEmpty) {
      deck.addAll(discardPile);
      discardPile.clear();
      deck.shuffle();
    }
  }

  GameCard? drawFromDeck() {
    recycleDiscardIfNeeded();
    if (deck.isEmpty) return null;
    return deck.removeLast();
  }

  List<GameCard> takeCardsFromDeck(int amount) {
    final cards = <GameCard>[];
    for (int i = 0; i < amount; i++) {
      final card = drawFromDeck();
      if (card == null) break;
      cards.add(card);
    }
    return cards;
  }

  // ==========================================================
  // ZIEHEN
  // ==========================================================

  void drawCard() {
    if (hasDrawn || turnFinished || knockActive && currentPlayer == knockingPlayer) {
      return;
    }

    final card = drawFromDeck();
    if (card == null) {
      showMessage('Es sind keine Karten mehr verfügbar.');
      return;
    }

    setState(() {
      hands[currentPlayer].add(card);
      hasDrawn = true;
      selectedCardIndex = null;
    });
  }

  // ==========================================================
  // AUSWÄHLEN / SPIELEN
  // ==========================================================

  void selectCard(int index) {
    if (turnFinished) return;
    setState(() {
      selectedCardIndex = selectedCardIndex == index ? null : index;
    });
  }

  Future<void> playSelectedCard() async {
    if (!hasDrawn) {
      showMessage('Ziehe zuerst eine Karte. Danach kannst du eine Karte spielen.');
      return;
    }

    if (turnFinished) {
      showMessage('Du hast in diesem Zug bereits gespielt oder abgelegt.');
      return;
    }

    if (selectedCardIndex == null) {
      showMessage('Wähle zuerst eine Karte aus.');
      return;
    }

    final card = hands[currentPlayer][selectedCardIndex!];

    switch (card.type) {
      case CardType.grass:
        playPlantCard(card, grassSlots, 'Gras');
        break;
      case CardType.energy:
        playPlantCard(card, energySlots, 'Energie');
        break;
      case CardType.base:
        playPlantCard(card, baseSlots, 'Basis');
        break;
      case CardType.attack:
        await playAttackCard(card);
        break;
      case CardType.defense:
        showMessage('Verteidigungskarten werden bei einem Angriff eingesetzt.');
        break;
      case CardType.action:
        await playActionCard(card);
        break;
    }
  }

  void playPlantCard(GameCard card, List<GameCard?> slots, String slotName) {
    final oldCard = slots[currentPlayer];

    if (oldCard != null && card.power <= oldCard.power) {
      showMessage('Du kannst nur eine bessere $slotName-Karte ausspielen.');
      return;
    }

    setState(() {
      if (oldCard != null) discardPile.add(oldCard);
      slots[currentPlayer] = card;
      hands[currentPlayer].removeAt(selectedCardIndex!);
      selectedCardIndex = null;
      turnFinished = true;
    });
  }

  // ==========================================================
  // AKTIONSKARTEN
  // ==========================================================

  Future<void> playActionCard(GameCard action) async {
    // Wichtig: Aktionskarten werden erst nach einem erfolgreichen Effekt
    // aus der Hand entfernt. So geht bei abgebrochenen Dialogen nichts verloren.

    switch (action.title) {
      case 'Dünger':
        final grass = grassSlots[currentPlayer];

        if (grass == null) {
          showMessage('Dünger geht erst, wenn bereits eine Gras-Karte in deiner Plantage liegt.');
          return;
        }

        if (grass.power >= 200) {
          showMessage('Dein Gras steht bereits bei 200 g – höher geht es nicht.');
          return;
        }

        final newPower = grass.power == 20
            ? 50
            : grass.power == 50
                ? 100
                : 200;

        setState(() {
          grassSlots[currentPlayer] = grassCard(newPower);
          removeSelectedPlayedCard(action);
          turnFinished = true;
        });

        showMessage('🌱 Dünger: Dein Gras steigt auf $newPower g.');
        return;

      case 'Übertopf':
        if (grassSlots[currentPlayer] == null) {
          showMessage('Übertopf geht erst, wenn eine Gras-Karte in deiner Plantage liegt.');
          return;
        }

        setState(() {
          grassProtected[currentPlayer] = true;
          removeSelectedPlayedCard(action);
          turnFinished = true;
        });

        showMessage('🪴 Übertopf: Dein Gras ist bis zu deinem nächsten eigenen Zug geschützt.');
        return;

      case 'Beste Freunde':
        // Nach dem normalen Ziehen sind in der Regel genug Handkarten vorhanden.
        // Die Aktionskarte selbst wird erst nach der Zielwahl entfernt.
        if (hands[currentPlayer].length <= 1) {
          showMessage('Du brauchst neben „Beste Freunde“ noch mindestens eine weitere Handkarte.');
          return;
        }

        final target = await chooseTarget(
          title: 'Mit wem blind tauschen?',
          icon: '🤝',
        );

        if (target == null || !mounted) {
          return;
        }

        if (hands[target].isEmpty) {
          showMessage('${widget.players[target]} hat keine Handkarte zum Tauschen.');
          return;
        }

        // Merke den Index der Aktionskarte, bevor sie entfernt wird.
        final actionIndex = selectedCardIndex!;

        setState(() {
          final removedAction = hands[currentPlayer].removeAt(actionIndex);
          discardPile.add(removedAction);
          selectedCardIndex = null;

          // Jetzt aus den verbleibenden Karten des aktiven Spielers blind wählen.
          final myIndex = random.nextInt(hands[currentPlayer].length);
          final targetIndex = random.nextInt(hands[target].length);

          final myCard = hands[currentPlayer][myIndex];
          final targetCard = hands[target][targetIndex];

          hands[currentPlayer][myIndex] = targetCard;
          hands[target][targetIndex] = myCard;

          turnFinished = true;
        });

        showMessage('🤝 Beste Freunde: Ihr habt blind je eine Handkarte getauscht.');
        return;

      case 'Gartenschere':
        final drawn = takeCardsFromDeck(2);

        if (drawn.isEmpty) {
          showMessage('Es sind keine Karten mehr zum Ziehen verfügbar.');
          return;
        }

        final keepIndex = await chooseDrawnCard(
          drawn,
          '✂️ Gartenschere – welche Karte behalten?',
        );

        if (keepIndex == null || !mounted) {
          // Falls der Dialog unerwartet geschlossen wird, Karten zurück auf den Ablagestapel.
          setState(() {
            discardPile.addAll(drawn);
          });
          return;
        }

        setState(() {
          removeSelectedPlayedCard(action);

          for (int i = 0; i < drawn.length; i++) {
            if (i == keepIndex) {
              hands[currentPlayer].add(drawn[i]);
            } else {
              discardPile.add(drawn[i]);
            }
          }

          turnFinished = true;
        });

        await enforceHandLimit();

        if (mounted) {
          showMessage('✂️ Gartenschere: Du hast 2 gezogen und 1 behalten.');
        }
        return;

      case 'Glückstreffer':
        final drawn = takeCardsFromDeck(3);

        if (drawn.isEmpty) {
          showMessage('Es sind keine Karten mehr zum Ziehen verfügbar.');
          return;
        }

        final keepIndex = await chooseDrawnCard(
          drawn,
          '🍀 Glückstreffer – welche Karte behalten?',
        );

        if (keepIndex == null || !mounted) {
          setState(() {
            discardPile.addAll(drawn);
          });
          return;
        }

        setState(() {
          removeSelectedPlayedCard(action);

          for (int i = 0; i < drawn.length; i++) {
            if (i == keepIndex) {
              hands[currentPlayer].add(drawn[i]);
            } else {
              discardPile.add(drawn[i]);
            }
          }

          turnFinished = true;
        });

        await enforceHandLimit();

        if (mounted) {
          showMessage('🍀 Glückstreffer: Du hast 3 gezogen und 1 behalten.');
        }
        return;

      case 'Ich zieh mir zwei':
        final drawn = takeCardsFromDeck(2);

        if (drawn.isEmpty) {
          showMessage('Es sind keine Karten mehr zum Ziehen verfügbar.');
          return;
        }

        setState(() {
          removeSelectedPlayedCard(action);
          hands[currentPlayer].addAll(drawn);
          turnFinished = true;
        });

        await enforceHandLimit();

        if (mounted) {
          showMessage('😎 Ich zieh mir zwei: ${drawn.length} zusätzliche Karten gezogen.');
        }
        return;

      default:
        showMessage('Für „${action.title}“ ist noch kein Effekt hinterlegt.');
        return;
    }
  }

  void removeSelectedPlayedCard(GameCard card) {
    if (selectedCardIndex == null) return;

    final removed = hands[currentPlayer].removeAt(selectedCardIndex!);
    discardPile.add(removed);
    selectedCardIndex = null;
  }

  Future<int?> chooseDrawnCard(List<GameCard> cards, String title) async {
    if (cards.length == 1) return 0;

    return showDialog<int>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          title: Text(title),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (int i = 0; i < cards.length; i++)
                  ListTile(
                    leading: Text(cardIcon(cards[i].type), style: const TextStyle(fontSize: 25)),
                    title: Text(cards[i].title),
                    subtitle: Text('${cards[i].value} – ${cards[i].effect}'),
                    onTap: () => Navigator.pop(context, i),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> enforceHandLimit() async {
    while (mounted && hands[currentPlayer].length > handLimit) {
      final index = await showDialog<int>(
        context: context,
        barrierDismissible: false,
        builder: (context) {
          return AlertDialog(
            title: const Text('Handkartenlimit: 7'),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Wähle eine Karte, die du ablegen möchtest.'),
                  const SizedBox(height: 10),
                  for (int i = 0; i < hands[currentPlayer].length; i++)
                    ListTile(
                      leading: Text(cardIcon(hands[currentPlayer][i].type), style: const TextStyle(fontSize: 23)),
                      title: Text(hands[currentPlayer][i].title),
                      subtitle: Text(hands[currentPlayer][i].value),
                      onTap: () => Navigator.pop(context, i),
                    ),
                ],
              ),
            ),
          );
        },
      );

      if (index == null || !mounted) return;

      setState(() {
        final discarded = hands[currentPlayer].removeAt(index);
        discardPile.add(discarded);
      });
    }
  }

  // ==========================================================
  // ANGRIFF / VERTEIDIGUNG
  // ==========================================================

  Future<void> playAttackCard(GameCard attack) async {
    final target = await chooseTarget();
    if (target == null || !mounted) return;

    final defenseIndices = validDefenseIndices(target, attack);
    int defenseIndex = -1;

    if (defenseIndices.isNotEmpty) {
      final result = await chooseDefense(target, attack, defenseIndices);
      if (!mounted) return;
      defenseIndex = result ?? -1;
    }

    if (defenseIndex >= 0) {
      final defense = hands[target][defenseIndex];

      setState(() {
        hands[target].removeAt(defenseIndex);
        hands[currentPlayer].removeAt(selectedCardIndex!);
        discardPile.add(attack);
        discardPile.add(defense);
        selectedCardIndex = null;
        turnFinished = true;
      });

      showMessage('${widget.players[target]} wehrt ${attack.title} mit ${defense.title} ab!');
      return;
    }

    String resultMessage = '';

    setState(() {
      resultMessage = applyAttackEffect(attack, target);
      hands[currentPlayer].removeAt(selectedCardIndex!);
      discardPile.add(attack);
      selectedCardIndex = null;
      turnFinished = true;
    });

    showMessage(resultMessage);
  }

  Future<int?> chooseTarget({
    String title = 'Wen angreifen?',
    String icon = '💥',
  }) async {
    return showDialog<int>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (int i = 0; i < widget.players.length; i++)
                if (i != currentPlayer)
                  ListTile(
                    leading: Text(icon, style: const TextStyle(fontSize: 25)),
                    title: Text(widget.players[i]),
                    onTap: () => Navigator.pop(context, i),
                  ),
            ],
          ),
        );
      },
    );
  }

  List<int> validDefenseIndices(int player, GameCard attack) {
    final result = <int>[];

    for (int i = 0; i < hands[player].length; i++) {
      final defense = hands[player][i];
      if (defense.type != CardType.defense) continue;

      if (defense.title == 'Alles easy') {
        result.add(i);
        continue;
      }

      if (attack.title == 'Stromausfall' && defense.title == 'Sicherungskasten') {
        result.add(i);
      }
      if (attack.title == 'Energiediebstahl' && defense.title == 'Wachhund') {
        result.add(i);
      }
      if (attack.title == 'Schädlingsbefall' && defense.title == 'Schädlingsmittel') {
        result.add(i);
      }
      if ((attack.title == 'Razzia' || attack.title == 'Zu platt') && defense.title == 'Anwalt') {
        result.add(i);
      }
    }

    return result;
  }

  Future<int?> chooseDefense(
    int player,
    GameCard attack,
    List<int> defenseIndices,
  ) async {
    return showDialog<int>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          title: Text('${widget.players[player]} wird angegriffen!'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('${attack.title}\n${attack.effect}', textAlign: TextAlign.center),
              const SizedBox(height: 20),
              const Text('Verteidigung einsetzen?', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              for (final index in defenseIndices)
                ListTile(
                  leading: const Text('🛡️', style: TextStyle(fontSize: 25)),
                  title: Text(hands[player][index].title),
                  subtitle: Text(hands[player][index].effect),
                  onTap: () => Navigator.pop(context, index),
                ),
              TextButton(
                onPressed: () => Navigator.pop(context, -1),
                child: const Text('NICHT VERTEIDIGEN'),
              ),
            ],
          ),
        );
      },
    );
  }

  String applyAttackEffect(GameCard attack, int target) {
    switch (attack.title) {
      case 'Stromausfall':
        final energy = energySlots[target];
        if (energy == null) return '${widget.players[target]} hat noch keine Energie.';
        if (energy.power <= 25) return '${widget.players[target]} ist bereits bei 25 %.';

        final newPower = energy.power == 100 ? 75 : energy.power == 75 ? 50 : 25;
        energySlots[target] = energyCard(newPower);
        return '${widget.players[target]}: Energie sinkt auf $newPower %.';

      case 'Energiediebstahl':
        final myEnergy = energySlots[currentPlayer];
        final targetEnergy = energySlots[target];

        if (myEnergy == null || targetEnergy == null) {
          return 'Für Energiediebstahl brauchen beide Spieler eine Energie-Karte.';
        }

        energySlots[currentPlayer] = targetEnergy;
        energySlots[target] = myEnergy;
        return 'Die Energie von ${widget.players[currentPlayer]} und ${widget.players[target]} wurde getauscht.';

      case 'Schädlingsbefall':
        if (grassProtected[target]) {
          return 'Der Übertopf schützt das Gras von ${widget.players[target]}.';
        }

        final grass = grassSlots[target];
        if (grass == null) return '${widget.players[target]} hat noch kein Gras.';
        if (grass.power <= 20) return '${widget.players[target]} ist bereits bei 20 g.';

        final newPower = grass.power == 200 ? 100 : grass.power == 100 ? 50 : 20;
        grassSlots[target] = grassCard(newPower);
        return '${widget.players[target]}: Gras sinkt auf $newPower g.';

      case 'Razzia':
        if (hands[target].isEmpty) return '${widget.players[target]} hat keine Handkarte.';

        final index = random.nextInt(hands[target].length);
        final lostCard = hands[target].removeAt(index);
        discardPile.add(lostCard);
        return '${widget.players[target]} verliert zufällig „${lostCard.title}“.';

      case 'Zu platt':
        skipNextTurn[target] = true;
        return '${widget.players[target]} setzt den nächsten Zug aus.';

      default:
        return 'Angriff ausgeführt.';
    }
  }

  // ==========================================================
  // ABLEGEN
  // ==========================================================

  void discardSelectedCard() {
    if (!hasDrawn || turnFinished) return;

    if (selectedCardIndex == null) {
      showMessage('Wähle zuerst eine Karte aus.');
      return;
    }

    setState(() {
      final card = hands[currentPlayer].removeAt(selectedCardIndex!);
      discardPile.add(card);
      selectedCardIndex = null;
      turnFinished = true;
    });
  }

  bool automaticRoundEndReached() {
    return completedTurns.every(
      (turns) => turns >= maxTurnsPerPlayerPerRound,
    );
  }

  // ==========================================================
  // KLOPFEN
  // ==========================================================

  bool plantationComplete(int player) {
    return grassSlots[player] != null &&
        energySlots[player] != null &&
        baseSlots[player] != null;
  }

  bool canKnock() {
    return !knockActive &&
        !hasDrawn &&
        !turnFinished &&
        completedTurns[currentPlayer] >= 2 &&
        plantationComplete(currentPlayer);
  }

  Future<void> knock() async {
    if (!canKnock()) {
      if (knockActive) {
        showMessage('Es wurde in dieser Runde bereits geklopft.');
      } else if (hasDrawn || turnFinished) {
        showMessage('Klopfen geht nur zu Beginn deines Zuges – bevor du eine Karte ziehst.');
      } else if (completedTurns[currentPlayer] < 2) {
        showMessage('Klopfen ist erst ab deinem 3. eigenen Zug möglich.');
      } else if (!plantationComplete(currentPlayer)) {
        showMessage('Du brauchst zuerst Gras, Energie und Basis.');
      }
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('👊 ICH KLOPFE!'),
          content: Text(
            'Deine Plantage wird eingefroren. Alle anderen Spieler bekommen noch genau einen letzten Zug.\n\n'
            'Aktueller Wert: ${calculatePoints(currentPlayer)} Punkte',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('ABBRECHEN'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('KLOPFEN'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) return;

    setState(() {
      knockActive = true;
      knockingPlayer = currentPlayer;
      finalTurnsRemaining
        ..clear()
        ..addAll(
          List.generate(widget.players.length, (i) => i)
              .where((i) => i != currentPlayer),
        );
    });

    showMessage('${widget.players[currentPlayer]} hat geklopft!');
    await moveToNextFinalPlayer();
  }

  // ==========================================================
  // SPIELERWECHSEL
  // ==========================================================

  Future<void> nextPlayer() async {
    if (!hasDrawn) {
      showMessage('Du musst zuerst eine Karte ziehen.');
      return;
    }

    if (!turnFinished) {
      showMessage('Spiele oder lege zuerst eine Karte ab.');
      return;
    }

    completedTurns[currentPlayer]++;

    if (!knockActive && automaticRoundEndReached()) {
      await finishRound(
        reason: 'Maximale Rundendauer erreicht',
      );
      return;
    }

    if (knockActive) {
      finalTurnsRemaining.remove(currentPlayer);
      await moveToNextFinalPlayer();
      return;
    }

    int next = currentPlayer;
    final skippedPlayers = <String>[];

    for (int attempt = 0; attempt < widget.players.length; attempt++) {
      next++;
      if (next >= widget.players.length) next = 0;

      if (skipNextTurn[next]) {
        skipNextTurn[next] = false;
        grassProtected[next] = false;
        completedTurns[next]++;
        skippedPlayers.add(widget.players[next]);
        continue;
      }

      break;
    }

    if (!knockActive && automaticRoundEndReached()) {
      await finishRound(
        reason: 'Maximale Rundendauer erreicht',
      );
      return;
    }

    setState(() {
      currentPlayer = next;
      grassProtected[currentPlayer] = false;
      hasDrawn = false;
      turnFinished = false;
      selectedCardIndex = null;
    });

    if (skippedPlayers.isNotEmpty) {
      showMessage('${skippedPlayers.join(', ')} setzt aus.');
    }
  }

  Future<void> moveToNextFinalPlayer() async {
    if (finalTurnsRemaining.isEmpty) {
      await finishRound();
      return;
    }

    int next = currentPlayer;
    final skippedPlayers = <String>[];

    for (int attempt = 0; attempt < widget.players.length * 2; attempt++) {
      next++;
      if (next >= widget.players.length) next = 0;

      if (!finalTurnsRemaining.contains(next)) continue;

      if (skipNextTurn[next]) {
        skipNextTurn[next] = false;
        grassProtected[next] = false;
        completedTurns[next]++;
        finalTurnsRemaining.remove(next);
        skippedPlayers.add(widget.players[next]);

        if (finalTurnsRemaining.isEmpty) {
          if (skippedPlayers.isNotEmpty) {
            showMessage('${skippedPlayers.join(', ')} setzt den letzten Zug aus.');
          }
          await finishRound();
          return;
        }
        continue;
      }

      setState(() {
        currentPlayer = next;
        grassProtected[currentPlayer] = false;
        hasDrawn = false;
        turnFinished = false;
        selectedCardIndex = null;
      });

      if (skippedPlayers.isNotEmpty) {
        showMessage('${skippedPlayers.join(', ')} setzt den letzten Zug aus.');
      }
      return;
    }

    await finishRound();
  }

  // ==========================================================
  // PUNKTE / RUNDENENDE
  // ==========================================================

  int calculatePoints(int player) {
    final grass = grassSlots[player];
    final energy = energySlots[player];
    final base = baseSlots[player];

    if (grass == null || energy == null || base == null) return 0;
    return (grass.power * (energy.power / 100) * base.power).round();
  }

  Future<void> finishRound({
    String reason = 'Klopfen',
  }) async {
    if (roundEnding) return;

    roundEnding = true;

    final rawScores = List<int>.generate(
      widget.players.length,
      (i) => calculatePoints(i),
    );

    final highestRaw = rawScores.reduce(max);
    final highestPlayers = <int>[
      for (int i = 0; i < rawScores.length; i++)
        if (rawScores[i] == highestRaw) i,
    ];

    for (final player in highestPlayers) {
      roundWins[player]++;
    }

    final roundScores = List<int>.from(rawScores);
    int bonusPlayer = -1;

    if (knockingPlayer != null &&
        highestPlayers.length == 1 &&
        highestPlayers.first == knockingPlayer) {
      bonusPlayer = knockingPlayer!;
      roundScores[bonusPlayer] += 100;
    }

    for (int i = 0; i < roundScores.length; i++) {
      totalScores[i] += roundScores[i];
    }

    if (!mounted) return;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          title: Text('🏁 Runde $roundNumber beendet'),
          content: SizedBox(
            width: 460,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  reason == 'Klopfen'
                      ? 'Die Runde endet nach dem Klopfen.'
                      : 'Die Runde endet automatisch nach $maxTurnsPerPlayerPerRound Zügen pro Spieler.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 12),
                for (int i = 0; i < widget.players.length; i++)
                  ListTile(
                    leading: Text(i == bonusPlayer ? '👑' : '🌿'),
                    title: Text(widget.players[i]),
                    subtitle: Text(
                      i == bonusPlayer
                          ? '${rawScores[i]} + 100 Klopf-Bonus'
                          : '${rawScores[i]} Plantagenpunkte',
                    ),
                    trailing: Text(
                      '${roundScores[i]} P',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                const Divider(),
                for (int i = 0; i < widget.players.length; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(widget.players[i]),
                        Text('Gesamt: ${totalScores[i]} P'),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: Text(roundNumber < 4 ? 'NÄCHSTE RUNDE' : 'GESAMTWERTUNG'),
            ),
          ],
        );
      },
    );

    if (!mounted) return;

    if (roundNumber >= 4) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => FinalScoreScreen(
            players: widget.players,
            totalScores: totalScores,
            roundWins: roundWins,
          ),
        ),
      );
      return;
    }

    setState(() {
      roundNumber++;
      startRound();
    });
  }

  // ==========================================================
  // INFO
  // ==========================================================

  void showMessage(String text) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  // ==========================================================
  // UI
  // ==========================================================

  @override
  Widget build(BuildContext context) {
    final hand = hands[currentPlayer];
    final points = calculatePoints(currentPlayer);
    final complete = plantationComplete(currentPlayer);
    final knockReady = canKnock();

    return Scaffold(
      appBar: AppBar(
        title: Text('Graskönig – Runde $roundNumber/4 • V0.6.4'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            if (knockActive)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF6B4A00),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '👊 ${widget.players[knockingPlayer!]} hat geklopft – letzter Zug für die übrigen Spieler!',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),

            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '${widget.players[currentPlayer]} ist am Zug',
                  style: const TextStyle(fontSize: 25, fontWeight: FontWeight.bold),
                ),
                const SizedBox(width: 12),
                Chip(label: Text('Gesamt ${totalScores[currentPlayer]} P')),
              ],
            ),

            const SizedBox(height: 4),
            Text(
              '${deck.length} Karten im Stapel • eigener Zug ${completedTurns[currentPlayer] + 1}',
              style: const TextStyle(color: Colors.white54),
            ),

            const SizedBox(height: 12),

            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 190,
                  height: 45,
                  child: FilledButton.icon(
                    // Der Button bleibt immer sichtbar und anklickbar.
                    // Falls Klopfen noch nicht erlaubt ist, erklärt knock() warum.
                    onPressed: knockActive ? null : knock,
                    icon: const Text('👊'),
                    label: Text(
                      knockActive
                          ? 'GEKLOPFT'
                          : completedTurns[currentPlayer] < 2
                              ? 'KLOPFEN AB ZUG 3'
                              : !complete
                                  ? 'KLOPFEN – PLANTAGE FEHLT'
                                  : knockReady
                                      ? 'ICH KLOPFE!'
                                      : 'KLOPFEN',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 190,
                  height: 45,
                  child: FilledButton.icon(
                    onPressed: hasDrawn ? null : drawCard,
                    icon: const Icon(Icons.add_card),
                    label: Text(hasDrawn ? 'KARTE GEZOGEN' : '1 KARTE ZIEHEN'),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 6),
            const Text(
              'Klopfen: ab dem 3. eigenen Zug. Ohne Klopfen endet die Runde spätestens nach $maxTurnsPerPlayerPerRound Zügen pro Spieler.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white54, fontSize: 11),
            ),

            const SizedBox(height: 12),
            const Text('DEINE PLANTAGE', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),

            Row(
              children: [
                Expanded(
                  child: PlantSlot(
                    icon: '🌿',
                    title: 'GRAS',
                    card: grassSlots[currentPlayer],
                    protected: grassProtected[currentPlayer],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: PlantSlot(
                    icon: '⚡',
                    title: 'ENERGIE',
                    card: energySlots[currentPlayer],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: PlantSlot(
                    icon: '👑',
                    title: 'BASIS',
                    card: baseSlots[currentPlayer],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            Container(
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF123A23),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                points == 0
                    ? 'Plantage noch nicht vollständig'
                    : 'PLANTAGENWERT: $points PUNKTE',
                style: TextStyle(
                  fontSize: points == 0 ? 13 : 18,
                  fontWeight: FontWeight.bold,
                  color: points == 0 ? Colors.white60 : const Color(0xFF9CF070),
                ),
              ),
            ),

            const Spacer(),

            Text(
              'DEINE HAND – ${hand.length} KARTEN',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),

            SizedBox(
              height: 190,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: hand.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (_, index) => GameCardWidget(
                  card: hand[index],
                  selected: selectedCardIndex == index,
                  onTap: () => selectCard(index),
                ),
              ),
            ),

            const SizedBox(height: 8),

            if (selectedCardIndex != null)
              Text(
                'Ausgewählt: ${hands[currentPlayer][selectedCardIndex!].title}',
                style: const TextStyle(
                  color: Colors.amber,
                  fontWeight: FontWeight.bold,
                ),
              ),

            const SizedBox(height: 8),

            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 150,
                  height: 48,
                  child: FilledButton(
                    onPressed: playSelectedCard,
                    child: const Text('SPIELEN'),
                  ),
                ),
                const SizedBox(width: 15),
                SizedBox(
                  width: 150,
                  height: 48,
                  child: OutlinedButton(
                    onPressed: discardSelectedCard,
                    child: const Text('ABLEGEN'),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            SizedBox(
              width: 240,
              height: 50,
              child: FilledButton(
                onPressed: turnFinished ? nextPlayer : null,
                child: Text(
                  knockActive ? 'LETZTEN ZUG BEENDEN' : 'NÄCHSTER SPIELER',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class FinalScoreScreen extends StatelessWidget {
  final List<String> players;
  final List<int> totalScores;
  final List<int> roundWins;

  const FinalScoreScreen({
    super.key,
    required this.players,
    required this.totalScores,
    required this.roundWins,
  });

  List<int> determineWinners() {
    final highestScore = totalScores.reduce(max);
    var candidates = <int>[
      for (int i = 0; i < totalScores.length; i++)
        if (totalScores[i] == highestScore) i,
    ];

    if (candidates.length <= 1) return candidates;

    final highestRoundWins = candidates.map((i) => roundWins[i]).reduce(max);
    candidates = candidates.where((i) => roundWins[i] == highestRoundWins).toList();
    return candidates;
  }

  @override
  Widget build(BuildContext context) {
    final winners = determineWinners();
    final winnerText = winners.length == 1
        ? '${players[winners.first]} ist GRASKÖNIG!'
        : '${winners.map((i) => players[i]).join(' & ')} sind GRASKÖNIGE!';

    final order = List<int>.generate(players.length, (i) => i)
      ..sort((a, b) => totalScores[b].compareTo(totalScores[a]));

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 650),
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('👑', style: TextStyle(fontSize: 90)),
                  const SizedBox(height: 10),
                  const Text(
                    'SPIEL BEENDET',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    winnerText,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 34,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF9CF070),
                    ),
                  ),
                  const SizedBox(height: 28),
                  for (int position = 0; position < order.length; position++)
                    Card(
                      child: ListTile(
                        leading: Text(
                          position == 0 ? '👑' : '${position + 1}.',
                          style: const TextStyle(fontSize: 24),
                        ),
                        title: Text(
                          players[order[position]],
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text('${roundWins[order[position]]}× höchste Plantage'),
                        trailing: Text(
                          '${totalScores[order[position]]} P',
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  const SizedBox(height: 25),
                  SizedBox(
                    width: 280,
                    height: 55,
                    child: FilledButton(
                      onPressed: () {
                        Navigator.of(context).pushAndRemoveUntil(
                          MaterialPageRoute(builder: (_) => const StartScreen()),
                          (route) => false,
                        );
                      },
                      child: const Text(
                        'NEUES SPIEL',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
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

String cardIcon(CardType type) {
  switch (type) {
    case CardType.grass:
      return '🌿';
    case CardType.energy:
      return '⚡';
    case CardType.base:
      return '👑';
    case CardType.attack:
      return '💥';
    case CardType.defense:
      return '🛡️';
    case CardType.action:
      return '★';
  }
}

class GameCardWidget extends StatelessWidget {
  final GameCard card;
  final bool selected;
  final VoidCallback onTap;

  const GameCardWidget({super.key, required this.card, required this.selected, required this.onTap});

  Color cardColor() {
    switch (card.type) {
      case CardType.grass:
        return const Color(0xFF13713B);
      case CardType.energy:
        return const Color(0xFFC89600);
      case CardType.base:
        return const Color(0xFF712792);
      case CardType.attack:
        return const Color(0xFFA62620);
      case CardType.defense:
        return const Color(0xFF1374AA);
      case CardType.action:
        return const Color(0xFFBC6000);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 125,
        padding: const EdgeInsets.all(10),
        transform: selected ? Matrix4.translationValues(0, -8, 0) : Matrix4.identity(),
        decoration: BoxDecoration(
          color: cardColor(),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: selected ? Colors.amber : Colors.white, width: selected ? 4 : 2),
          boxShadow: [
            BoxShadow(
              color: selected ? Colors.amber.withOpacity(0.35) : Colors.black45,
              blurRadius: selected ? 12 : 6,
            ),
          ],
        ),
        child: Column(
          children: [
            Text(cardIcon(card.type), style: const TextStyle(fontSize: 27)),
            const SizedBox(height: 5),
            Text(card.title.toUpperCase(), textAlign: TextAlign.center, maxLines: 2, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            const Spacer(),
            Text(card.value, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
            const Spacer(),
            Text(card.effect, textAlign: TextAlign.center, maxLines: 3, style: const TextStyle(fontSize: 9)),
          ],
        ),
      ),
    );
  }
}

class PlantSlot extends StatelessWidget {
  final String icon;
  final String title;
  final GameCard? card;
  final bool protected;

  const PlantSlot({super.key, required this.icon, required this.title, required this.card, this.protected = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 145,
      decoration: BoxDecoration(
        color: const Color(0xFF0B2718),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: protected ? Colors.lightBlueAccent : Colors.white24, width: protected ? 3 : 2),
      ),
      child: Center(
        child: card == null
            ? Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(icon, style: const TextStyle(fontSize: 38)),
                  const SizedBox(height: 10),
                  Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
                ],
              )
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(protected ? '🪴' : icon, style: const TextStyle(fontSize: 28)),
                  const SizedBox(height: 5),
                  Text(card!.title, textAlign: TextAlign.center, maxLines: 2, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text(card!.value, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Color(0xFF9CF070))),
                ],
              ),
      ),
    );
  }
}

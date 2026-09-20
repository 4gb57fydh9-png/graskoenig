import 'dart:math';
import 'dart:convert';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await TestWallet.instance.load();
  await lockPortraitOrientation();
  runApp(const GraskoenigApp());
}

Future<void> lockPortraitOrientation() {
  // Im Browser (vor allem Safari auf dem iPhone) darf Flutter die
  // Geräteausrichtung nicht erzwingen. Nach einem Wechsel Portrait ->
  // Landscape kann Safari sonst sichtbare Widgets und Touch-Koordinaten
  // gegeneinander verschieben. Native Android/iOS Builds werden weiterhin
  // korrekt gesperrt.
  if (kIsWeb) return Future<void>.value();
  return SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
}

Future<void> lockLandscapeOrientation() {
  if (kIsWeb) return Future<void>.value();
  return SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
}

// Graskoenig V0.12.0 - Kartenfarben, Symbole und ausgewogene Avatare.
// Setup: flutter pub add shared_preferences
// Keine echten Zahlungen, kein Online-Spiel, keine auszahlbare Waehrung.
const int handLimit = 5;
const int maxTurnsPerPlayerPerRound = 6;

const Color kBg = Color(0xFF03190F);
const Color kPanel = Color(0xFF0A2518);
const Color kPanel2 = Color(0xFF102F20);
const Color kNeon = Color(0xFF42F35C);
const Color kMint = Color(0xFF9CF0A7);
const Color kGold = Color(0xFFFFC62E);
const Color kCream = Color(0xFFF3E7CA);

// Test economy only. Production must verify purchases and results on a server.
class CoinMatch {
  final int fee;
  final int players;
  bool started = false;
  bool closed = false;
  int payout = 0;
  CoinMatch(this.fee, this.players);
}

class TestWallet extends ChangeNotifier {
  static final instance = TestWallet();
  static const entryFees = [50, 100, 250];
  static const initialCoins = 1000;
  static const dailyCoins = 250;
  static const packages = [500, 1500, 5000];
  static const _key = 'graskoenig_test_wallet_v1';
  SharedPreferences? _prefs;
  int coins = initialCoins;
  int lastBonus = 0;
  List<String> history = [];
  bool busy = false;
  String? error;
  bool get ready => _prefs != null && error == null;
  bool get canClaim =>
      DateTime.now().millisecondsSinceEpoch - lastBonus >=
      const Duration(hours: 24).inMilliseconds;

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw != null) {
        final value = jsonDecode(raw) as Map<String, dynamic>;
        final balance = value['coins'] as int;
        final bonus = value['lastBonus'] as int;
        final entries = List<String>.from(value['history'] as List);
        if (balance < 0 || bonus < 0)
          throw const FormatException('Ungültiger Münzstand');
        coins = balance;
        lastBonus = bonus;
        history = entries;
      } else {
        final ok = await prefs.setString(
          _key,
          jsonEncode({
            'coins': initialCoins,
            'lastBonus': 0,
            'history': ['Startguthaben: +$initialCoins'],
          }),
        );
        if (!ok)
          throw StateError('Startguthaben konnte nicht gespeichert werden.');
        history = ['Startguthaben: +$initialCoins'];
      }
      _prefs = prefs;
      error = null;
    } catch (_) {
      error = 'Guthaben konnte nicht geladen werden. Bitte App neu starten. Es wurden keine Münzen zurückgesetzt.';
    }
  }

  Future<void> _change(int delta, String label, {int? bonusTime}) async {
    if (!ready) throw StateError(error ?? 'Guthaben nicht verfügbar.');
    if (busy) throw StateError('Bitte einen Moment warten.');
    if (coins + delta < 0)
      throw StateError(
        'Zu wenig Münzen. Hole den Gratisbonus oder Testmünzen im Shop.',
      );
    busy = true;
    notifyListeners();
    try {
      final entries = [
        '$label: ${delta >= 0 ? '+' : ''}$delta',
        ...history,
      ].take(30).toList();
      final nextBonus = bonusTime ?? lastBonus;
      final ok = await _prefs!.setString(
        _key,
        jsonEncode({
          'coins': coins + delta,
          'lastBonus': nextBonus,
          'history': entries,
        }),
      );
      if (!ok)
        throw StateError(
          'Münzen konnten nicht gespeichert werden. Bitte erneut versuchen.',
        );
      coins += delta;
      lastBonus = nextBonus;
      history = entries;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<CoinMatch> enter(int fee, int players) async {
    if (!entryFees.contains(fee) || players < 2 || players > 3)
      throw StateError('Ungültiger Tisch.');
    await _change(-fee, 'Tischeinsatz');
    return CoinMatch(fee, players);
  }

  Future<void> refund(CoinMatch match) async {
    if (match.started || match.closed) return;
    await _change(match.fee, 'Start abgebrochen');
    match.closed = true;
  }

  Future<int?> settle(
    CoinMatch? match,
    List<int> scores,
    List<int> wins,
  ) async {
    if (match == null) return null;
    if (match.closed) return match.payout;
    final best = scores.reduce(max);
    final candidates = [
      for (int i = 0; i < scores.length; i++)
        if (scores[i] == best) i,
    ];
    final bestWins = candidates.map((i) => wins[i]).reduce(max);
    final winners = candidates.where((i) => wins[i] == bestWins).toList();
    final payout = winners.contains(0)
        ? match.fee * match.players ~/ winners.length
        : 0;
    await _change(
      payout,
      payout > 0 ? 'Partie gewonnen (Spieler 1)' : 'Partie beendet',
    );
    match.payout = payout;
    match.closed = true;
    return payout;
  }

  Future<void> claim() async {
    if (!canClaim) throw StateError('Der Bonus ist alle 24 Stunden verfügbar.');
    await _change(
      dailyCoins,
      'Gratisbonus',
      bonusTime: DateTime.now().millisecondsSinceEpoch,
    );
  }

  Future<void> buyTestCoins(int amount) async {
    if (!packages.contains(amount)) throw StateError('Unbekanntes Münzpaket.');
    await _change(amount, 'Simulierter Kauf – kostenlos');
  }
}

class WalletBar extends StatelessWidget {
  const WalletBar({super.key});
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: TestWallet.instance,
    builder: (context, _) => Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            const Icon(Icons.monetization_on_rounded, color: kGold),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                TestWallet.instance.error ??
                    '${TestWallet.instance.coins} MÜNZEN • SPIELER 1',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class CoinLobbyScreen extends StatelessWidget {
  const CoinLobbyScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('GRASKÖNIG • SPIELTISCHE')),
    body: LeafBackground(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: AnimatedBuilder(
            animation: TestWallet.instance,
            builder: (context, _) => ListView(
              padding: const EdgeInsets.all(20),
              children: [
                const WalletBar(),
                const SizedBox(height: 16),
                const Text(
                  'DEIN TISCH. DEIN GROW.',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    color: kMint,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Lokaler Test mit 2–3 Spielern und optionalem Bot. Vier Runden pro Partie. '
                  'Spieler 1 zahlt den Einsatz; die Gegnereinsätze werden simuliert. '
                  'Der Gesamtsieger erhält den Pot, bei Gleichstand wird geteilt (abgerundet). '
                  'Nur Testmünzen, keine Auszahlung in Geld.',
                ),
                const SizedBox(height: 16),
                for (int i = 0; i < TestWallet.entryFees.length; i++)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            const [
                              'KLEINER GARTEN',
                              'GEWÄCHSHAUS',
                              'KÖNIGSPLANTAGE',
                            ][i],
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 20,
                              color: kGold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '${TestWallet.entryFees[i]} Münzen Einsatz • Pot: ${TestWallet.entryFees[i] * 2}–${TestWallet.entryFees[i] * 3}',
                          ),
                          const SizedBox(height: 12),
                          FilledButton(
                            onPressed:
                                TestWallet.instance.ready &&
                                    !TestWallet.instance.busy &&
                                    TestWallet.instance.coins >=
                                        TestWallet.entryFees[i]
                                ? () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => PlayerSetupScreen(
                                        entryFee: TestWallet.entryFees[i],
                                      ),
                                    ),
                                  )
                                : null,
                            child: Text(
                              TestWallet.instance.coins <
                                      TestWallet.entryFees[i]
                                  ? 'ZU WENIG MÜNZEN'
                                  : 'SPIELER & AVATARE WÄHLEN',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                OutlinedButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const CoinShopScreen()),
                  ),
                  icon: const Icon(Icons.storefront),
                  label: const Text('SHOP & GRATISBONUS'),
                ),
                const ListTile(
                  leading: Icon(Icons.lock_outline),
                  title: Text('Online, Freunde & Rangliste'),
                  subtitle: Text('Nach den lokalen Tests verfügbar'),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class CoinShopScreen extends StatefulWidget {
  const CoinShopScreen({super.key});
  @override
  State<CoinShopScreen> createState() => _CoinShopScreenState();
}

class _CoinShopScreenState extends State<CoinShopScreen> {
  bool _working = false;
  Future<void> _run(Future<void> Function() action) async {
    if (_working) return;
    setState(() => _working = true);
    try {
      await action();
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$error')));
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _purchase(int amount) async {
    await _run(() async {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('KOSTENLOSER TESTKAUF'),
          content: Text(
            '$amount Testmünzen hinzufügen? Es erfolgt keine Zahlung und kein App-Store-Kauf.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('ABBRECHEN'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('TESTKAUF BESTÄTIGEN'),
            ),
          ],
        ),
      );
      if (confirmed == true) await TestWallet.instance.buyTestCoins(amount);
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('MÜNZSHOP • TESTVERSION')),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: AnimatedBuilder(
          animation: TestWallet.instance,
          builder: (context, _) {
            final wallet = TestWallet.instance;
            final enabled = wallet.ready && !wallet.busy && !_working;
            return ListView(
              padding: const EdgeInsets.all(20),
              children: [
                const WalletBar(),
                const SizedBox(height: 12),
                const Text(
                  'Alle Pakete sind im Test kostenlos. Echte In-App-Käufe werden später freigeschaltet. '
                  'Testmünzen haben keinen Geldwert und werden nicht in einen späteren Echtgeldkauf umgewandelt.',
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: enabled && wallet.canClaim
                      ? () => _run(wallet.claim)
                      : null,
                  icon: const Icon(Icons.redeem),
                  label: Text(
                    wallet.canClaim
                        ? '+${TestWallet.dailyCoins} GRATIS ABHOLEN'
                        : 'BONUS ABGEHOLT • ALLE 24 STUNDEN',
                  ),
                ),
                for (final amount in TestWallet.packages)
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.monetization_on, color: kGold),
                      title: Text('$amount Münzen'),
                      subtitle: const Text('Kostenlose Kaufsimulation'),
                      trailing: TextButton(
                        onPressed: enabled ? () => _purchase(amount) : null,
                        child: const Text('TESTEN'),
                      ),
                    ),
                  ),
                const SizedBox(height: 20),
                const Text(
                  'LETZTE BUCHUNGEN',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                for (final entry in wallet.history)
                  ListTile(dense: true, title: Text(entry)),
                const Text(
                  'Guthaben wird nur auf diesem Gerät gespeichert. Neuinstallation oder Löschen der App-Daten setzt den Teststand zurück. '
                  'Beim Schließen einer laufenden Partie verfällt der Einsatz.',
                ),
              ],
            );
          },
        ),
      ),
    ),
  );
}

enum GameHaptic { selection, light, medium, heavy }

class GameFeedback {
  static bool soundEnabled = true;
  static bool hapticsEnabled = true;
  static bool musicEnabled = true;

  static final AudioPlayer _player = AudioPlayer();
  static final AudioPlayer _musicPlayer = AudioPlayer();
  static bool menuMusicPlaying = false;

  static Future<void> _haptic(GameHaptic kind) async {
    if (!hapticsEnabled) return;

    switch (kind) {
      case GameHaptic.selection:
        await HapticFeedback.selectionClick();
        break;
      case GameHaptic.light:
        await HapticFeedback.lightImpact();
        break;
      case GameHaptic.medium:
        await HapticFeedback.mediumImpact();
        break;
      case GameHaptic.heavy:
        await HapticFeedback.heavyImpact();
        break;
    }
  }

  static Future<void> trigger(
    String file, {
    GameHaptic haptic = GameHaptic.light,
  }) async {
    await _haptic(haptic);

    if (!soundEnabled) return;

    try {
      await _player.stop();
      await _player.play(AssetSource('cards/$file'));
    } catch (_) {
      // Das Spiel soll auch dann weiterlaufen, wenn ein Browser oder Gerät
      // einen Ton nicht abspielen kann.
    }
  }

  static Future<void> selection() => _haptic(GameHaptic.selection);

  static Future<void> preview() =>
      trigger('sound_action.wav', haptic: GameHaptic.medium);

  static Future<void> startMenuMusic() async {
    if (!musicEnabled || menuMusicPlaying) return;

    try {
      await _musicPlayer.setReleaseMode(ReleaseMode.loop);
      await _musicPlayer.setVolume(0.18);
      await _musicPlayer.play(AssetSource('cards/sound_reggae_menu.wav'));
      menuMusicPlaying = true;
    } catch (_) {
      // Browser können automatisches Audio vor dem ersten Nutzertipp blockieren.
      menuMusicPlaying = false;
    }
  }

  static Future<void> stopMenuMusic() async {
    try {
      await _musicPlayer.stop();
    } catch (_) {}
    menuMusicPlaying = false;
  }

  static Future<void> toggleMenuMusic() async {
    if (menuMusicPlaying) {
      await stopMenuMusic();
    } else {
      musicEnabled = true;
      await startMenuMusic();
    }
  }
}

Color playerAccent(int index) {
  const colors = <Color>[
    Color(0xFF41E563),
    Color(0xFFFF5B66),
    Color(0xFF53A7FF),
    Color(0xFFFFB52E),
    Color(0xFFC86BFF),
    Color(0xFF38D6C7),
  ];
  return colors[index % colors.length];
}

class AvatarOption {
  final String name;
  final String assetPath;

  const AvatarOption(this.name, this.assetPath);
}

const List<AvatarOption> kAvatarOptions = <AvatarOption>[
  AvatarOption('Graskönig', 'assets/cards/graskoenig_icon.png'),
  AvatarOption('Powerfrau', 'assets/cards/en100_v12.png'),
  AvatarOption('Kumpel', 'assets/cards/basis2.jpg'),
  AvatarOption('Glücksfee', 'assets/cards/glueck_v12.png'),
  AvatarOption('Dealer', 'assets/cards/dealer.jpg'),
  AvatarOption('Anwältin', 'assets/cards/anwalt_v12.png'),
];

// Display only the artwork region of a card, never its border or footer.
class CharacterPortrait extends StatelessWidget {
  final String asset;
  const CharacterPortrait({super.key, required this.asset});
  @override
  Widget build(BuildContext context) => ClipRect(
    child: LayoutBuilder(
      builder: (context, box) {
        final size = min(box.maxWidth, box.maxHeight);
        if (asset == 'assets/cards/graskoenig_icon.png') {
          return Image.asset(
            asset,
            width: size,
            height: size,
            fit: BoxFit.contain,
          );
        }
        return Center(
          child: SizedBox(
            width: size,
            height: size,
            child: ClipRect(
              child: OverflowBox(
                maxWidth: size / .8,
                maxHeight: size * 1.5 / .8,
                alignment: const Alignment(0, -.25),
                child: Image.asset(
                  asset,
                  width: size / .8,
                  height: size * 1.5 / .8,
                  fit: BoxFit.fill,
                  errorBuilder: (_, __, ___) =>
                      const Center(child: Icon(Icons.person, size: 48)),
                ),
              ),
            ),
          ),
        );
      },
    ),
  );
}

String categoryName(CardType? type) {
  if (type == null) return 'ALLE';
  switch (type) {
    case CardType.grass:
      return 'GRAS';
    case CardType.energy:
      return 'ENERGIE';
    case CardType.base:
      return 'BASIS';
    case CardType.attack:
      return 'ANGRIFF';
    case CardType.defense:
      return 'ABWEHR';
    case CardType.action:
      return 'AKTION';
  }
}

Color cardCategoryColor(CardType type) {
  switch (type) {
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
      return const Color(0xFFDD278C);
  }
}

// Symbols are rendered consistently by Flutter on every face-up card,
// including assets not included in this update. The card back stays neutral.
class CardFace extends StatelessWidget {
  final GameCard card;
  const CardFace({super.key, required this.card});
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final badge = (box.maxWidth * .18).clamp(13.0, 36.0).toDouble();
      return Column(
        children: [
          Expanded(
            child: SizedBox(
              width: double.infinity,
              child: card.assetPath == null
                  ? CardFallbackLarge(card: card)
                  : Image.asset(
                      card.assetPath!,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) =>
                          CardFallbackLarge(card: card),
                    ),
            ),
          ),
          Container(
            height: badge + 2,
            color: cardCategoryColor(card.type),
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.only(left: 2),
              child: Text(
                cardIcon(card.type),
                semanticsLabel: categoryName(card.type),
                style: TextStyle(
                  fontSize: badge * .8,
                  height: 1,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      );
    },
  );
}

String playerAvatarAsset(int index) {
  return kAvatarOptions[index % kAvatarOptions.length].assetPath;
}

enum CardType { grass, energy, base, attack, defense, action }

class GameCard {
  final CardType type;
  final String title;
  final String value;
  final String effect;
  final int power;
  final String? assetPath;

  const GameCard({
    required this.type,
    required this.title,
    required this.value,
    required this.effect,
    this.power = 0,
    this.assetPath,
  });
}

GameCard grassCard(int power) {
  switch (power) {
    case 20:
      return const GameCard(
        type: CardType.grass,
        title: 'Kleiner Beutel',
        value: '20 g',
        effect: 'Klein, aber fein.',
        power: 20,
        assetPath: 'assets/cards/gras20.jpg',
      );
    case 50:
      return const GameCard(
        type: CardType.grass,
        title: 'Solide Ernte',
        value: '50 g',
        effect: 'Es wird was.',
        power: 50,
        assetPath: 'assets/cards/gras50.jpg',
      );
    case 100:
      return const GameCard(
        type: CardType.grass,
        title: 'Fette Ernte',
        value: '100 g',
        effect: 'Jetzt wird’s ernst.',
        power: 100,
        assetPath: 'assets/cards/gras100.jpg',
      );
    default:
      return const GameCard(
        type: CardType.grass,
        title: 'Maximum',
        value: '200 g',
        effect: 'Maximum.',
        power: 200,
        assetPath: 'assets/cards/gras200.jpg',
      );
  }
}

GameCard energyCard(int power) {
  switch (power) {
    case 25:
      return const GameCard(
        type: CardType.energy,
        title: 'Notstrom',
        value: '25 %',
        effect: 'Ein bisschen reicht.',
        power: 25,
        assetPath: 'assets/cards/en25.jpg',
      );
    case 50:
      return const GameCard(
        type: CardType.energy,
        title: 'Kellerstrom',
        value: '50 %',
        effect: 'Läuft.',
        power: 50,
        assetPath: 'assets/cards/en50_v12.png',
      );
    case 75:
      return const GameCard(
        type: CardType.energy,
        title: 'Grow Power',
        value: '75 %',
        effect: 'Schon ordentlich.',
        power: 75,
        assetPath: 'assets/cards/en75.jpg',
      );
    default:
      return const GameCard(
        type: CardType.energy,
        title: 'Volle Power',
        value: '100 %',
        effect: 'Volle Power.',
        power: 100,
        assetPath: 'assets/cards/en100_v12.png',
      );
  }
}

List<GameCard> buildDeck() {
  final deck = <GameCard>[];

  void addCards(
    int amount,
    CardType type,
    String title,
    String value,
    String effect, {
    int power = 0,
    String? assetPath,
  }) {
    for (int i = 0; i < amount; i++) {
      deck.add(
        GameCard(
          type: type,
          title: title,
          value: value,
          effect: effect,
          power: power,
          assetPath: assetPath,
        ),
      );
    }
  }

  addCards(
    4,
    CardType.grass,
    'Kleiner Beutel',
    '20 g',
    'Klein, aber fein.',
    power: 20,
    assetPath: 'assets/cards/gras20.jpg',
  );
  addCards(
    5,
    CardType.grass,
    'Solide Ernte',
    '50 g',
    'Es wird was.',
    power: 50,
    assetPath: 'assets/cards/gras50.jpg',
  );
  addCards(
    4,
    CardType.grass,
    'Fette Ernte',
    '100 g',
    'Jetzt wird’s ernst.',
    power: 100,
    assetPath: 'assets/cards/gras100.jpg',
  );
  addCards(
    3,
    CardType.grass,
    'Maximum',
    '200 g',
    'Maximum.',
    power: 200,
    assetPath: 'assets/cards/gras200.jpg',
  );

  addCards(
    3,
    CardType.energy,
    'Notstrom',
    '25 %',
    'Ein bisschen reicht.',
    power: 25,
    assetPath: 'assets/cards/en25.jpg',
  );
  addCards(
    4,
    CardType.energy,
    'Kellerstrom',
    '50 %',
    'Läuft.',
    power: 50,
    assetPath: 'assets/cards/en50_v12.png',
  );
  addCards(
    4,
    CardType.energy,
    'Grow Power',
    '75 %',
    'Schon ordentlich.',
    power: 75,
    assetPath: 'assets/cards/en75.jpg',
  );
  addCards(
    3,
    CardType.energy,
    'Volle Power',
    '100 %',
    'Volle Power.',
    power: 100,
    assetPath: 'assets/cards/en100_v12.png',
  );

  addCards(
    4,
    CardType.base,
    'Kumpel um die Ecke',
    '×2',
    'Regional. Loyal.',
    power: 2,
    assetPath: 'assets/cards/basis2.jpg',
  );
  addCards(
    3,
    CardType.base,
    'Dealer',
    '×3',
    'Schnelle Verbindungen.',
    power: 3,
    assetPath: 'assets/cards/dealer.jpg',
  );
  addCards(
    3,
    CardType.base,
    'Growshop',
    '×3',
    'Alles was du brauchst.',
    power: 3,
    assetPath: 'assets/cards/growshop.jpg',
  );
  addCards(
    2,
    CardType.base,
    'Graskönig',
    '×4',
    'Das Nonplusultra.',
    power: 4,
    assetPath: 'assets/cards/graskoenig.jpg',
  );

  addCards(
    2,
    CardType.attack,
    'Stromausfall',
    '💥',
    'Energie eines Gegners −1 Stufe.',
    assetPath: 'assets/cards/strom.jpg',
  );
  addCards(
    2,
    CardType.attack,
    'Energiediebstahl',
    '💥',
    'Tausche deine Energie mit der eines Gegners.',
    assetPath: 'assets/cards/energiedieb.jpg',
  );
  addCards(
    2,
    CardType.attack,
    'Schädlingsbefall',
    '💥',
    'Gras eines Gegners −1 Stufe.',
    assetPath: 'assets/cards/schaedling.jpg',
  );
  addCards(
    2,
    CardType.attack,
    'Razzia',
    '💥',
    'Ein Gegner legt 1 zufällige Handkarte ab.',
    assetPath: 'assets/cards/razzia.jpg',
  );
  addCards(
    2,
    CardType.attack,
    'Zu platt',
    '💥',
    'Ein Gegner überspringt seinen nächsten Zug.',
    assetPath: 'assets/cards/platt.jpg',
  );

  addCards(
    2,
    CardType.defense,
    'Sicherungskasten',
    '🛡️',
    'Stoppt Stromausfall.',
    assetPath: 'assets/cards/sicherung.jpg',
  );
  addCards(
    1,
    CardType.defense,
    'Wachhund',
    '🛡️',
    'Stoppt Energiediebstahl.',
    assetPath: 'assets/cards/wachhund.jpg',
  );
  addCards(
    1,
    CardType.defense,
    'Schädlingsmittel',
    '🛡️',
    'Stoppt Schädlingsbefall.',
    assetPath: 'assets/cards/mittel.jpg',
  );
  addCards(
    2,
    CardType.defense,
    'Anwalt',
    '🛡️',
    'Stoppt Razzia oder Zu platt.',
    assetPath: 'assets/cards/anwalt_v12.png',
  );
  addCards(
    2,
    CardType.defense,
    'Alles easy',
    '🛡️',
    'Stoppt jeden Angriff.',
    assetPath: 'assets/cards/easy.jpg',
  );

  addCards(
    3,
    CardType.action,
    'Dünger',
    '★',
    'Gras +1 Stufe.',
    assetPath: 'assets/cards/duenger_v12.png',
  );
  addCards(
    3,
    CardType.action,
    'Gartenschere',
    '★',
    'Ziehe 2 Karten, behalte 1.',
    assetPath: 'assets/cards/schere_v12.png',
  );
  addCards(
    2,
    CardType.action,
    'Übertopf',
    '★',
    'Gras bis zu deinem nächsten Zug geschützt.',
    assetPath: 'assets/cards/uebertopf_v12.png',
  );
  addCards(
    2,
    CardType.action,
    'Beste Freunde',
    '★',
    'Tausche blind 1 Handkarte.',
    assetPath: 'assets/cards/freunde_v12.png',
  );
  addCards(
    2,
    CardType.action,
    'Glückstreffer',
    '★',
    'Ziehe 3 Karten, behalte 1.',
    assetPath: 'assets/cards/glueck_v12.png',
  );
  addCards(
    2,
    CardType.action,
    'Ich zieh mir zwei',
    '★',
    'Ziehe 2 Karten.',
    assetPath: 'assets/cards/zwei_v12.png',
  );

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
        scaffoldBackgroundColor: kBg,
        colorScheme: ColorScheme.fromSeed(
          seedColor: kNeon,
          brightness: Brightness.dark,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xEE061A10),
          foregroundColor: Colors.white,
          elevation: 0,
          centerTitle: true,
        ),
        dialogTheme: DialogThemeData(
          backgroundColor: const Color(0xFF091E14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: Color(0x5542F35C)),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF16A638),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            textStyle: const TextStyle(fontWeight: FontWeight.w900),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.white,
            side: const BorderSide(color: Colors.white38),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        useMaterial3: true,
      ),
      home: const StartScreen(),
    );
  }
}

class OrientationHintScreen extends StatelessWidget {
  final bool portrait;
  final String title;
  final String subtitle;

  const OrientationHintScreen({
    super.key,
    required this.portrait,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: LeafBackground(
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    portrait
                        ? Icons.stay_current_portrait_rounded
                        : Icons.stay_current_landscape_rounded,
                    size: 64,
                    color: kGold,
                  ),
                  const SizedBox(height: 14),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    subtitle,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white60),
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

class StartScreen extends StatefulWidget {
  const StartScreen({super.key});

  @override
  State<StartScreen> createState() => _StartScreenState();
}

class _StartScreenState extends State<StartScreen> {
  @override
  void initState() {
    super.initState();
    lockPortraitOrientation();
  }

  Future<void> _openPage(Widget page) async {
    await GameFeedback.stopMenuMusic();
    if (!mounted) return;

    await Navigator.push(context, MaterialPageRoute(builder: (_) => page));

    if (!mounted) return;
    await GameFeedback.startMenuMusic();
    if (mounted) setState(() {});
  }

  Future<void> _comingSoon(BuildContext context, String title) async {
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: const Text(
          'Dieser Bereich ist für eine spätere Version vorgesehen. Das lokale Spiel funktioniert bereits vollständig.',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleMusic() async {
    await GameFeedback.toggleMenuMusic();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb &&
        MediaQuery.of(context).orientation == Orientation.landscape) {
      return const OrientationHintScreen(
        portrait: true,
        title: 'BITTE IPHONE HOCHKANT HALTEN',
        subtitle: 'Das Hauptmenü ist für Hochformat optimiert.',
      );
    }

    return Scaffold(
      body: LeafBackground(
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 430),
              child: Stack(
                children: [
                  ListView(
                    padding: const EdgeInsets.fromLTRB(18, 22, 18, 22),
                    children: [
                      const SizedBox(height: 8),

                      Center(
                        child: Container(
                          width: 260,
                          height: 260,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(18),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x66000000),
                                blurRadius: 18,
                                offset: Offset(0, 8),
                              ),
                              BoxShadow(
                                color: Color(0x3342F35C),
                                blurRadius: 18,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(15),
                            child: const CharacterPortrait(
                              asset: 'assets/cards/graskoenig_icon.png',
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 12),
                      const Text(
                        'GRASKÖNIG',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 48,
                          height: 0.95,
                          fontWeight: FontWeight.w900,
                          fontStyle: FontStyle.italic,
                          letterSpacing: -1.5,
                          shadows: [
                            Shadow(
                              color: Colors.black,
                              blurRadius: 8,
                              offset: Offset(2, 3),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'DAS KARTENSPIEL FÜR ERWACHSENE GENIESSER',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: kCream,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.1,
                        ),
                      ),
                      const SizedBox(height: 28),
                      const WalletBar(),
                      const SizedBox(height: 12),

                      MenuButton(
                        icon: Icons.play_arrow_rounded,
                        label: 'TISCH AUSWÄHLEN',
                        primary: true,
                        onTap: () => _openPage(const CoinLobbyScreen()),
                      ),
                      const SizedBox(height: 9),
                      MenuButton(
                        icon: Icons.groups_2_outlined,
                        label: 'ONLINE & FREUNDE • BALD',
                        onTap: () =>
                            _comingSoon(context, 'ONLINE NOCH NICHT VERFÜGBAR'),
                      ),
                      const SizedBox(height: 9),
                      MenuButton(
                        icon: Icons.storefront_outlined,
                        label: 'MÜNZSHOP & TAGESBONUS',
                        onTap: () => _openPage(const CoinShopScreen()),
                      ),
                      const SizedBox(height: 9),
                      MenuButton(
                        icon: Icons.menu_book_outlined,
                        label: 'REGELN',
                        onTap: () => _openPage(const RulesScreen()),
                      ),
                      const SizedBox(height: 9),
                      MenuButton(
                        icon: Icons.style_outlined,
                        label: 'KARTENÜBERSICHT',
                        onTap: () => _openPage(const CardsOverviewScreen()),
                      ),
                      const SizedBox(height: 9),
                      MenuButton(
                        icon: Icons.settings_outlined,
                        label: 'EINSTELLUNGEN',
                        onTap: () => _openPage(const SettingsScreen()),
                      ),
                      const SizedBox(height: 24),
                      const Text(
                        'GUTE FREUNDE\nGUTER GROW\nGAME ON!',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: kNeon,
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          fontStyle: FontStyle.italic,
                          height: 1.05,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'V0.12.0 • LOKALER MÜNZTEST • KEINE ECHTEN KÄUFE',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white38,
                          fontSize: 10,
                          letterSpacing: 1,
                        ),
                      ),
                    ],
                  ),

                  Positioned(
                    right: 8,
                    top: 0,
                    child: Material(
                      color: const Color(0xD90A2518),
                      borderRadius: BorderRadius.circular(22),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(22),
                        onTap: _toggleMusic,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 11,
                            vertical: 8,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                GameFeedback.menuMusicPlaying
                                    ? Icons.music_note_rounded
                                    : Icons.music_off_rounded,
                                size: 18,
                                color: GameFeedback.menuMusicPlaying
                                    ? kNeon
                                    : Colors.white54,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                GameFeedback.menuMusicPlaying
                                    ? 'MUSIK AN'
                                    : 'MUSIK STARTEN',
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w900,
                                  color: GameFeedback.menuMusicPlaying
                                      ? kNeon
                                      : Colors.white54,
                                ),
                              ),
                            ],
                          ),
                        ),
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

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('EINSTELLUNGEN')),
      body: LeafBackground(
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 430),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(18, 22, 18, 28),
                children: [
                  const Text(
                    'SPIELGEFÜHL',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Hintergrundmusik, Spieltöne und Vibration kannst du jederzeit ein- oder ausschalten.',
                    style: TextStyle(color: Colors.white60),
                  ),
                  const SizedBox(height: 18),
                  Container(
                    decoration: BoxDecoration(
                      color: const Color(0xE80A2518),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: Column(
                      children: [
                        SwitchListTile(
                          secondary: const Icon(
                            Icons.music_note_rounded,
                            color: kGold,
                          ),
                          title: const Text(
                            'HINTERGRUNDMUSIK',
                            style: TextStyle(fontWeight: FontWeight.w900),
                          ),
                          subtitle: const Text('Reggae-Musik im Hauptmenü'),
                          value: GameFeedback.musicEnabled,
                          onChanged: (value) async {
                            setState(() => GameFeedback.musicEnabled = value);
                            if (!value) {
                              await GameFeedback.stopMenuMusic();
                            }
                          },
                        ),
                        const Divider(height: 1, color: Colors.white12),
                        SwitchListTile(
                          secondary: const Icon(
                            Icons.volume_up_rounded,
                            color: kNeon,
                          ),
                          title: const Text(
                            'TON',
                            style: TextStyle(fontWeight: FontWeight.w900),
                          ),
                          subtitle: const Text(
                            'Kartenziehen, Angriff, Klopfen und Sieg',
                          ),
                          value: GameFeedback.soundEnabled,
                          onChanged: (value) {
                            setState(() => GameFeedback.soundEnabled = value);
                            if (value) GameFeedback.preview();
                          },
                        ),
                        const Divider(height: 1, color: Colors.white12),
                        SwitchListTile(
                          secondary: const Icon(
                            Icons.vibration_rounded,
                            color: kGold,
                          ),
                          title: const Text(
                            'VIBRATION',
                            style: TextStyle(fontWeight: FontWeight.w900),
                          ),
                          subtitle: const Text(
                            'Haptisches Feedback auf Android und iPhone',
                          ),
                          value: GameFeedback.hapticsEnabled,
                          onChanged: (value) {
                            setState(() => GameFeedback.hapticsEnabled = value);
                            if (value) GameFeedback.selection();
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    height: 52,
                    child: FilledButton.icon(
                      onPressed: GameFeedback.preview,
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: const Text('TON & VIBRATION TESTEN'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Hinweis: Vibration ist im Edge-Browser nicht spürbar. Sie funktioniert später auf dem echten Handy. Ton sollte auch im Browser hörbar sein.',
                    style: TextStyle(
                      color: Colors.white38,
                      fontSize: 11,
                      height: 1.35,
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

class PlayerSetupScreen extends StatefulWidget {
  final int entryFee;
  const PlayerSetupScreen({super.key, this.entryFee = 50});

  @override
  State<PlayerSetupScreen> createState() => _PlayerSetupScreenState();
}

class _PlayerSetupScreenState extends State<PlayerSetupScreen> {
  int playerCount = 2;
  bool useBot = true;
  bool _launching = false;

  final controllers = [
    TextEditingController(text: 'Spieler 1'),
    TextEditingController(text: 'Spieler 2'),
    TextEditingController(text: 'Spieler 3'),
  ];

  final List<int> avatarSelections = <int>[0, 1, 2];

  @override
  void initState() {
    super.initState();
    lockPortraitOrientation();
  }

  @override
  void dispose() {
    for (final controller in controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> chooseAvatar(int playerIndex) async {
    final selected = await showDialog<int>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('AVATAR FÜR SPIELER ${playerIndex + 1}'),
          content: SizedBox(
            width: 360,
            child: GridView.builder(
              shrinkWrap: true,
              itemCount: kAvatarOptions.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 0.82,
              ),
              itemBuilder: (context, index) {
                final avatar = kAvatarOptions[index];
                final active = avatarSelections[playerIndex] == index;
                return InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => Navigator.pop(context, index),
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: active ? const Color(0xFF174D24) : Colors.black26,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: active ? kNeon : Colors.white24,
                        width: active ? 2.5 : 1,
                      ),
                    ),
                    child: Column(
                      children: [
                        Expanded(
                          child: ClipOval(
                            child: CharacterPortrait(asset: avatar.assetPath),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          avatar.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
    );

    if (selected != null && mounted) {
      setState(() => avatarSelections[playerIndex] = selected);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb &&
        MediaQuery.of(context).orientation == Orientation.landscape) {
      return const OrientationHintScreen(
        portrait: true,
        title: 'BITTE IPHONE HOCHKANT HALTEN',
        subtitle: 'Spieler, Bot und Avatare stellst du im Hochformat ein.',
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text('TISCH • ${widget.entryFee} MÜNZEN')),
      body: LeafBackground(
        child: SafeArea(
          top: false,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 430),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
                children: [
                  SectionPanel(
                    title:
                        'SPIELERANZAHL • GUTHABEN: ${TestWallet.instance.coins}',
                    child: Row(
                      children: [
                        for (final number in const [2, 3]) ...[
                          Expanded(
                            child: ChoiceChip(
                              label: SizedBox(
                                height: 34,
                                child: Center(
                                  child: Text(
                                    '$number SPIELER',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                              ),
                              selected: playerCount == number,
                              onSelected: (_) =>
                                  setState(() => playerCount = number),
                              selectedColor: const Color(0xFF174D24),
                              side: BorderSide(
                                color: playerCount == number
                                    ? kNeon
                                    : Colors.white24,
                              ),
                            ),
                          ),
                          if (number == 2) const SizedBox(width: 10),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  SectionPanel(
                    title: 'GEGNER',
                    child: Column(
                      children: [
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          secondary: Icon(
                            useBot
                                ? Icons.smart_toy_rounded
                                : Icons.groups_2_rounded,
                            color: useBot ? kGold : kNeon,
                          ),
                          title: Text(
                            useBot ? 'MIT BOT' : 'NUR MENSCHEN',
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                          subtitle: Text(
                            useBot
                                ? playerCount == 2
                                      ? 'Du spielst gegen einen Computergegner.'
                                      : 'Die letzte Position übernimmt der Bot.'
                                : 'Alle Spieler spielen lokal auf diesem Gerät.',
                          ),
                          value: useBot,
                          onChanged: (value) => setState(() => useBot = value),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  SectionPanel(
                    title: 'SPIELER & AVATARE',
                    child: Column(
                      children: List.generate(playerCount, (index) {
                        final isBot = useBot && index == playerCount - 1;
                        final avatar = kAvatarOptions[avatarSelections[index]];
                        final color = playerAccent(index);
                        return Padding(
                          padding: EdgeInsets.only(
                            bottom: index == playerCount - 1 ? 0 : 10,
                          ),
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.black26,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: isBot
                                    ? kGold.withOpacity(0.7)
                                    : Colors.white12,
                              ),
                            ),
                            child: Row(
                              children: [
                                const SizedBox(width: 8),
                                InkWell(
                                  borderRadius: BorderRadius.circular(30),
                                  onTap: () => chooseAvatar(index),
                                  child: Padding(
                                    padding: const EdgeInsets.all(4),
                                    child: GraskoenigAvatar(
                                      playerIndex: index,
                                      assetPath: avatar.assetPath,
                                      size: 42,
                                      borderColor: color,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: isBot
                                      ? const Padding(
                                          padding: EdgeInsets.symmetric(
                                            vertical: 15,
                                          ),
                                          child: Text(
                                            'Kiffer-Karl  •  BOT',
                                            style: TextStyle(
                                              color: kGold,
                                              fontWeight: FontWeight.w900,
                                            ),
                                          ),
                                        )
                                      : TextField(
                                          controller: controllers[index],
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 16,
                                          ),
                                          decoration: const InputDecoration(
                                            border: InputBorder.none,
                                            isDense: true,
                                            hintText: 'Spielername',
                                            contentPadding:
                                                EdgeInsets.symmetric(
                                                  vertical: 14,
                                                ),
                                          ),
                                        ),
                                ),
                                Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      isBot
                                          ? Icons.smart_toy_rounded
                                          : Icons.edit_outlined,
                                      color: isBot ? kGold : Colors.white54,
                                      size: 19,
                                    ),
                                    const SizedBox(height: 2),
                                    const Text(
                                      'AVATAR',
                                      style: TextStyle(
                                        fontSize: 7,
                                        color: Colors.white38,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(width: 12),
                              ],
                            ),
                          ),
                        );
                      }),
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Avatar antippen, um einen Graskönig-Charakter auszuwählen.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white38, fontSize: 10),
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    height: 58,
                    child: FilledButton.icon(
                      icon: const Icon(Icons.screen_rotation_rounded),
                      onPressed: _launching
                          ? null
                          : () async {
                              setState(() => _launching = true);
                              CoinMatch? match;
                              try {
                                // Wichtig fuer iPhone/Safari: vor dem Wechsel ins Spiel
                                // jedes Textfeld sicher verlassen und dem VisualViewport
                                // Zeit geben, nach der Tastatur wieder auf 1:1 zu kommen.
                                FocusManager.instance.primaryFocus?.unfocus();
                                await Future<void>.delayed(
                                  const Duration(milliseconds: 350),
                                );
                                if (!mounted) return;

                                final players = List<String>.generate(
                                  playerCount,
                                  (index) {
                                    if (useBot && index == playerCount - 1) {
                                      return 'Kiffer-Karl';
                                    }
                                    return controllers[index].text
                                            .trim()
                                            .isEmpty
                                        ? 'Spieler ${index + 1}'
                                        : controllers[index].text.trim();
                                  },
                                );
                                final avatars = List<String>.generate(
                                  playerCount,
                                  (index) =>
                                      kAvatarOptions[avatarSelections[index]]
                                          .assetPath,
                                );
                                final bots = List<bool>.generate(
                                  playerCount,
                                  (index) => useBot && index == playerCount - 1,
                                );
                                match = await TestWallet.instance.enter(
                                  widget.entryFee,
                                  playerCount,
                                );
                                if (!mounted) return;

                                if (!kIsWeb) {
                                  // Native iOS/Android: zuerst wirklich ins Querformat
                                  // wechseln und danach direkt das Spiel oeffnen.
                                  // Die Safari-Zwischenansicht darf hier NICHT verwendet
                                  // werden, weil sie auf eine Rotation wartet, waehrend
                                  // der Setup-Screen noch auf Portrait gesperrt ist.
                                  await lockLandscapeOrientation();
                                  await Future<void>.delayed(
                                    const Duration(milliseconds: 300),
                                  );
                                  if (!mounted) return;

                                  await Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => GameScreen(
                                        coinMatch: match,
                                        players: players,
                                        avatarAssets: avatars,
                                        botPlayers: bots,
                                      ),
                                    ),
                                  );
                                  return;
                                }

                                // Web/Safari: dort bleibt die spezielle Zwischenansicht
                                // bestehen, weil sie die Safari-Touchkoordinaten nach
                                // einer manuellen Drehung stabilisiert.
                                final alreadyLandscape =
                                    MediaQuery.of(context).orientation ==
                                    Orientation.landscape;

                                await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => alreadyLandscape
                                        ? GameScreen(
                                            coinMatch: match,
                                            players: players,
                                            avatarAssets: avatars,
                                            botPlayers: bots,
                                          )
                                        : LandscapeLaunchScreen(
                                            coinMatch: match,
                                            players: players,
                                            avatarAssets: avatars,
                                            botPlayers: bots,
                                          ),
                                  ),
                                );
                              } catch (error) {
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('$error')),
                                  );
                                }
                              } finally {
                                if (match != null && !match.started) {
                                  try {
                                    await TestWallet.instance.refund(match);
                                  } catch (error) {
                                    if (mounted)
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                            SnackBar(content: Text('$error')),
                                          );
                                  }
                                }
                                await lockPortraitOrientation();
                                if (mounted) setState(() => _launching = false);
                              }
                            },
                      label: const Text(
                        'SPIEL STARTEN',
                        style: TextStyle(fontSize: 18),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    kIsWeb
                        ? 'Guthaben: Spieler 1. Ab Spielbeginn verfällt der Einsatz bei Abbruch. Bitte quer halten.'
                        : 'Guthaben: Spieler 1. Ab Spielbeginn verfällt der Einsatz bei Abbruch. Das Spiel wechselt ins Querformat.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white38, fontSize: 10),
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

class LandscapeLaunchScreen extends StatefulWidget {
  final CoinMatch? coinMatch;
  final List<String> players;
  final List<String> avatarAssets;
  final List<bool> botPlayers;

  const LandscapeLaunchScreen({
    super.key,
    this.coinMatch,
    required this.players,
    required this.avatarAssets,
    required this.botPlayers,
  });

  @override
  State<LandscapeLaunchScreen> createState() => _LandscapeLaunchScreenState();
}

class _LandscapeLaunchScreenState extends State<LandscapeLaunchScreen> {
  bool _viewportReady = false;
  Orientation? _lastOrientation;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final orientation = MediaQuery.of(context).orientation;
    if (_lastOrientation != orientation) {
      _lastOrientation = orientation;
      _viewportReady = false;
      if (orientation == Orientation.landscape) {
        // Safari braucht nach dem Drehen kurz Zeit, bis VisualViewport,
        // Flutter-Layout und Touch-Koordinaten wieder identisch sind.
        Future<void>.delayed(const Duration(milliseconds: 650), () {
          if (mounted &&
              MediaQuery.of(context).orientation == Orientation.landscape) {
            setState(() => _viewportReady = true);
          }
        });
      }
    }
  }

  void _openGame() {
    if (!_viewportReady) return;
    _viewportReady = false;
    widget.coinMatch?.started = true;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => GameScreen(
          coinMatch: widget.coinMatch,
          players: widget.players,
          avatarAssets: widget.avatarAssets,
          botPlayers: widget.botPlayers,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final landscape =
        MediaQuery.of(context).orientation == Orientation.landscape;

    return Scaffold(
      body: LeafBackground(
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      landscape
                          ? Icons.stay_current_landscape_rounded
                          : Icons.screen_rotation_rounded,
                      size: 62,
                      color: landscape ? kNeon : kGold,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      landscape
                          ? 'QUERFORMAT ERKANNT'
                          : 'BITTE IPHONE QUER HALTEN',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      landscape
                          ? (_viewportReady
                                ? 'Die Touch-Flächen sind jetzt neu ausgerichtet. Du kannst das Spiel starten.'
                                : 'Einen Moment – Safari richtet die Touch-Flächen neu aus …')
                          : 'Erst nach dem Drehen wird das Spielfeld geladen. So bleiben Bild und Touch auf dem iPhone deckungsgleich.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white60,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 22),
                    if (landscape)
                      SizedBox(
                        width: double.infinity,
                        height: 58,
                        child: FilledButton.icon(
                          onPressed: _viewportReady ? _openGame : null,
                          icon: _viewportReady
                              ? const Icon(Icons.play_arrow_rounded)
                              : const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                          label: Text(
                            _viewportReady
                                ? 'JETZT SPIELEN'
                                : 'TOUCH WIRD AUSGERICHTET',
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
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
}

class OnlineJoinScreen extends StatefulWidget {
  const OnlineJoinScreen({super.key});

  @override
  State<OnlineJoinScreen> createState() => _OnlineJoinScreenState();
}

class _OnlineJoinScreenState extends State<OnlineJoinScreen> {
  final TextEditingController roomController = TextEditingController();

  @override
  void initState() {
    super.initState();
    lockPortraitOrientation();
  }

  @override
  void dispose() {
    roomController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb &&
        MediaQuery.of(context).orientation == Orientation.landscape) {
      return const OrientationHintScreen(
        portrait: true,
        title: 'BITTE IPHONE HOCHKANT HALTEN',
        subtitle: 'Den Online-Raumcode gibst du im Hochformat ein.',
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('ONLINE • SPIEL BEITRETEN')),
      body: LeafBackground(
        child: SafeArea(
          top: false,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 430),
              child: ListView(
                padding: const EdgeInsets.all(18),
                children: [
                  const SizedBox(height: 24),
                  const Icon(Icons.public_rounded, size: 70, color: kNeon),
                  const SizedBox(height: 16),
                  const Text(
                    'ONLINE-SPIEL',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Hier wird später der Raumcode eines Freundes eingegeben. '
                    'Jeder Spieler sieht dann nur seine eigene Hand, die Plantagen bleiben für alle sichtbar.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white70, height: 1.4),
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    controller: roomController,
                    textCapitalization: TextCapitalization.characters,
                    textAlign: TextAlign.center,
                    maxLength: 6,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 4,
                    ),
                    decoration: InputDecoration(
                      counterText: '',
                      hintText: 'GK1234',
                      filled: true,
                      fillColor: Colors.black26,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 54,
                    child: FilledButton.icon(
                      onPressed: () {
                        showDialog<void>(
                          context: context,
                          builder: (_) => AlertDialog(
                            title: const Text('Online-Multiplayer'),
                            content: const Text(
                              'Die Oberfläche ist vorbereitet. Die echte Online-Verbindung '
                              'bauen wir als nächsten Schritt mit einem Multiplayer-Backend ein.',
                            ),
                            actions: [
                              FilledButton(
                                onPressed: () => Navigator.pop(context),
                                child: const Text('OK'),
                              ),
                            ],
                          ),
                        );
                      },
                      icon: const Icon(Icons.login_rounded),
                      label: const Text('RAUM BEITRETEN'),
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

class RulesScreen extends StatelessWidget {
  const RulesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('REGELN')),
      body: LeafBackground(
        child: SafeArea(
          top: false,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 430),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  GestureDetector(
                    onTap: () => showDialog<void>(
                      context: context,
                      builder: (dialogContext) => Dialog.fullscreen(
                        backgroundColor: const Color(0xFF071B10),
                        child: SafeArea(
                          child: Column(
                            children: [
                              Align(
                                alignment: Alignment.centerRight,
                                child: IconButton(
                                  tooltip: 'Schließen',
                                  icon: const Icon(Icons.close),
                                  onPressed: () => Navigator.pop(dialogContext),
                                ),
                              ),
                              Expanded(
                                child: InteractiveViewer(
                                  minScale: 1,
                                  maxScale: 5,
                                  child: Center(
                                    child: Image.asset(
                                      'assets/cards/rules_v12.png',
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    child: Image.asset('assets/cards/rules_v12.png'),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Anleitung antippen und zum Vergrößern zoomen. Motive in der Grafik sind Beispiele.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  const RulesFallback(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class RulesFallback extends StatelessWidget {
  const RulesFallback({super.key});

  @override
  Widget build(BuildContext context) {
    return const SectionPanel(
      title: 'KURZREGELN',
      child: Text(
        '2–3 Spieler • 4 Runden • 5 Startkarten. Optional spielt der letzte Platz als Bot.\n\n'
        'Zug: 1 Karte ziehen, höchstens 1 Karte spielen oder ablegen. '
        'Nach dem Ausspielen oder Ablegen wechselt das Spiel automatisch zum nächsten Spieler. '
        'Erforderliche Karten- und Gegnerauswahlen werden vorher abgeschlossen. '
        'Die Plantage besteht aus Gras, Energie und Basis. '
        'Punkte = Gras × Energie × Basis.\n\n'
        'Ab dem 3. eigenen Zug darfst du mit vollständiger Plantage klopfen. '
        'Danach erhalten die anderen Spieler je einen letzten Zug. '
        'Der erfolgreiche Klopfer erhält +100 Punkte, wenn seine Plantage allein die beste ist. '
        'Ohne Klopfen endet die Runde nach maximal 6 Zügen pro Spieler.\n\n'
        'KARTEN ERKENNEN\n'
        'Das Symbol links unten zeigt den Kartentyp:\n'
        '🌿 Gras – grün\n⚡ Energie – gelb\n👑 Basis – violett\n'
        '💥 Angriff – rot\n🛡️ Verteidigung – blau\n★ Aktion – rosa\n'
        'Alle Aktionskarten sind rosa, auch die Gartenschere. Die Symbole werden in der App eingeblendet.\n\n'
        'AVATARE\nWähle vor dem Spiel eine von 6 Figuren: 3 weibliche und 3 männliche. '
        'Die Auswahl verändert keine Kartenwerte oder Gewinnchancen. Bot-Handkarten bleiben verdeckt.\n\n'
        'MÜNZEN IM LOKALEN TEST\n'
        'Spieler 1 startet mit 1.000 Münzen. Pro Partie kostet der Tisch 50, 100 oder 250 Münzen. '
        'Gegnereinsätze werden simuliert. Der Gesamtsieger nach vier Runden gewinnt den Pot. '
        'Bei Punktegleichstand zählen Rundensiege; bei weiterem Gleichstand wird der Pot geteilt und abgerundet. '
        'Nur Gewinne von Spieler 1 werden diesem Gerät gutgeschrieben. '
        'Bei Abbruch einer laufenden Partie verfällt der Einsatz.\n\n'
        'Im Shop gibt es alle 24 Stunden 250 Gratis-Münzen und kostenlose Testkäufe. '
        'Keine echten Zahlungen, keine Auszahlung in Geld und noch kein Online-Spiel.',
        style: TextStyle(height: 1.45, color: Colors.white70),
      ),
    );
  }
}

class CardsOverviewScreen extends StatefulWidget {
  const CardsOverviewScreen({super.key});

  @override
  State<CardsOverviewScreen> createState() => _CardsOverviewScreenState();
}

class _CardsOverviewScreenState extends State<CardsOverviewScreen> {
  CardType? filter;

  List<GameCard> get uniqueCards {
    final map = <String, GameCard>{};
    for (final card in buildDeck()) {
      map['${card.type}-${card.title}-${card.value}'] = card;
    }
    return map.values
        .where((card) => filter == null || card.type == filter)
        .toList();
  }

  Future<void> showDetail(GameCard card) async {
    await showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: const Color(0xFF071B10),
        insetPadding: const EdgeInsets.all(20),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 390, maxHeight: 720),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        card.title.toUpperCase(),
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                Flexible(
                  child: AspectRatio(
                    aspectRatio: 2 / 3,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: CardFace(card: card),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  '${categoryName(card.type)} • ${card.value}',
                  style: const TextStyle(
                    color: kMint,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  card.effect,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cards = uniqueCards;
    final filters = <CardType?>[null, ...CardType.values];

    return Scaffold(
      appBar: AppBar(title: const Text('KARTENÜBERSICHT')),
      body: LeafBackground(
        child: SafeArea(
          top: false,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 430),
              child: Column(
                children: [
                  SizedBox(
                    height: 54,
                    child: ListView.separated(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      scrollDirection: Axis.horizontal,
                      itemCount: filters.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 7),
                      itemBuilder: (_, index) {
                        final type = filters[index];
                        final selected = filter == type;
                        return ChoiceChip(
                          label: Text(categoryName(type)),
                          selected: selected,
                          onSelected: (_) => setState(() => filter = type),
                          selectedColor: const Color(0xFF14642A),
                          side: BorderSide(
                            color: selected ? kNeon : Colors.white24,
                          ),
                        );
                      },
                    ),
                  ),
                  Expanded(
                    child: GridView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 6, 12, 24),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            childAspectRatio: 0.67,
                            crossAxisSpacing: 10,
                            mainAxisSpacing: 10,
                          ),
                      itemCount: cards.length,
                      itemBuilder: (_, index) {
                        final card = cards[index];
                        return GestureDetector(
                          onTap: () => showDetail(card),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(14),
                            child: CardFace(card: card),
                          ),
                        );
                      },
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

class GameScreen extends StatefulWidget {
  final CoinMatch? coinMatch;
  final List<String> players;
  final List<String> avatarAssets;
  final List<bool> botPlayers;

  const GameScreen({
    super.key,
    this.coinMatch,
    required this.players,
    required this.avatarAssets,
    required this.botPlayers,
  });

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

  bool _botBusy = false;
  bool _resolvingPlay = false;
  bool _autoAdvancePending = false;
  bool hasDrawn = false;
  bool turnFinished = false;

  bool knockActive = false;
  bool roundEnding = false;
  int? knockingPlayer;
  final Set<int> finalTurnsRemaining = <int>{};

  @override
  void initState() {
    super.initState();
    widget.coinMatch?.started = true;
    lockLandscapeOrientation();
    totalScores = List<int>.filled(widget.players.length, 0);
    roundWins = List<int>.filled(widget.players.length, 0);
    startRound();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeRunBotTurn());
  }

  @override
  void dispose() {
    lockPortraitOrientation();
    super.dispose();
  }

  bool get isBotTurn =>
      currentPlayer < widget.botPlayers.length &&
      widget.botPlayers[currentPlayer];

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

  Future<void> _maybeRunBotTurn() async {
    if (!mounted || _botBusy || !isBotTurn || roundEnding) return;

    _botBusy = true;
    try {
      await Future.delayed(const Duration(milliseconds: 650));
      if (!mounted || !isBotTurn || roundEnding) return;

      if (canKnock() && calculatePoints(currentPlayer) >= 250) {
        await _botKnock();
        return;
      }

      if (!hasDrawn) {
        if (discardPile.isNotEmpty && _botWantsCard(discardPile.last)) {
          drawDiscardCard();
        } else {
          drawCard();
        }
      }

      await Future.delayed(const Duration(milliseconds: 550));
      if (!mounted || !isBotTurn || roundEnding) return;

      if (!turnFinished) {
        final bestIndex = _bestBotPlayableIndex();
        if (bestIndex != null) {
          setState(() => selectedCardIndex = bestIndex);
          final card = hands[currentPlayer][bestIndex];

          if (card.type == CardType.grass ||
              card.type == CardType.energy ||
              card.type == CardType.base ||
              (card.type == CardType.action &&
                  (card.title == 'Dünger' || card.title == 'Übertopf'))) {
            await playSelectedCard();
          }
        }
      }

      if (!turnFinished && hands[currentPlayer].isNotEmpty) {
        setState(() {
          selectedCardIndex = _botDiscardIndex();
        });
        discardSelectedCard();
      }

      await Future.delayed(const Duration(milliseconds: 500));
      if (mounted && isBotTurn && !roundEnding) {
        await nextPlayer();
      }
    } finally {
      _botBusy = false;
      if (mounted && isBotTurn && !roundEnding) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _maybeRunBotTurn());
      }
    }
  }

  bool _botWantsCard(GameCard card) {
    switch (card.type) {
      case CardType.grass:
        return grassSlots[currentPlayer] == null ||
            card.power > grassSlots[currentPlayer]!.power;
      case CardType.energy:
        return energySlots[currentPlayer] == null ||
            card.power > energySlots[currentPlayer]!.power;
      case CardType.base:
        return baseSlots[currentPlayer] == null ||
            card.power > baseSlots[currentPlayer]!.power;
      case CardType.action:
        if (card.title == 'Dünger') {
          final grass = grassSlots[currentPlayer];
          return grass != null && grass.power < 200;
        }
        if (card.title == 'Übertopf') {
          return grassSlots[currentPlayer] != null &&
              !grassProtected[currentPlayer];
        }
        return false;
      case CardType.attack:
      case CardType.defense:
        return false;
    }
  }

  int? _bestBotPlayableIndex() {
    int? bestIndex;
    int bestScore = -999999;

    for (int i = 0; i < hands[currentPlayer].length; i++) {
      final card = hands[currentPlayer][i];
      int? score;

      switch (card.type) {
        case CardType.grass:
          final current = grassSlots[currentPlayer]?.power ?? 0;
          if (card.power > current) score = 1000 + card.power - current;
          break;
        case CardType.energy:
          final current = energySlots[currentPlayer]?.power ?? 0;
          if (card.power > current) score = 900 + (card.power - current) * 2;
          break;
        case CardType.base:
          final current = baseSlots[currentPlayer]?.power ?? 0;
          if (card.power > current) score = 800 + (card.power - current) * 100;
          break;
        case CardType.action:
          if (card.title == 'Dünger') {
            final grass = grassSlots[currentPlayer];
            if (grass != null && grass.power < 200) score = 700;
          } else if (card.title == 'Übertopf') {
            if (grassSlots[currentPlayer] != null &&
                !grassProtected[currentPlayer]) {
              score = 250;
            }
          }
          break;
        case CardType.attack:
        case CardType.defense:
          break;
      }

      if (score != null && score > bestScore) {
        bestScore = score;
        bestIndex = i;
      }
    }

    return bestIndex;
  }

  int _botDiscardIndex() {
    for (int i = 0; i < hands[currentPlayer].length; i++) {
      final card = hands[currentPlayer][i];
      if (!_botWantsCard(card)) return i;
    }
    return 0;
  }

  Future<void> _botKnock() async {
    if (!canKnock()) return;

    setState(() {
      knockActive = true;
      knockingPlayer = currentPlayer;
      finalTurnsRemaining
        ..clear()
        ..addAll(
          List.generate(
            widget.players.length,
            (i) => i,
          ).where((i) => i != currentPlayer),
        );
    });

    GameFeedback.trigger('sound_knock.wav', haptic: GameHaptic.heavy);
    showMessage('🤖 ${widget.players[currentPlayer]} klopft!');
    await moveToNextFinalPlayer();
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
    if (hasDrawn ||
        turnFinished ||
        knockActive && currentPlayer == knockingPlayer) {
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

    GameFeedback.trigger('sound_draw.wav', haptic: GameHaptic.light);
  }

  void drawDiscardCard() {
    if (hasDrawn || turnFinished || discardPile.isEmpty) {
      return;
    }

    final card = discardPile.removeLast();

    setState(() {
      hands[currentPlayer].add(card);
      hasDrawn = true;
      selectedCardIndex = null;
    });

    GameFeedback.trigger('sound_draw.wav', haptic: GameHaptic.light);

    showMessage('Du hast ${card.title} vom Ablagestapel genommen.');
  }

  // ==========================================================
  // AUSWÄHLEN / SPIELEN
  // ==========================================================

  void selectCard(int index) {
    if (turnFinished || isBotTurn || _resolvingPlay) return;
    setState(() {
      selectedCardIndex = selectedCardIndex == index ? null : index;
    });
    GameFeedback.selection();
  }

  Future<void> playSelectedCard() async {
    if (_resolvingPlay || _autoAdvancePending || roundEnding) return;
    if (!hasDrawn) {
      showMessage(
        'Ziehe zuerst eine Karte. Danach kannst du eine Karte spielen.',
      );
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
    _resolvingPlay = true;
    try {
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
          showMessage(
            'Verteidigungskarten werden bei einem Angriff eingesetzt.',
          );
          break;
        case CardType.action:
          await playActionCard(card);
          break;
      }
    } finally {
      _resolvingPlay = false;
    }
    // Target selection, defense and excess-card dialogs have all completed.
    await _advanceHumanTurnAutomatically();
  }

  Future<void> _advanceHumanTurnAutomatically() async {
    // Bots already await nextPlayer in their own turn loop.
    if (!mounted ||
        isBotTurn ||
        !turnFinished ||
        roundEnding ||
        _resolvingPlay ||
        _autoAdvancePending)
      return;
    _autoAdvancePending = true;
    final playerAtEnd = currentPlayer;
    final roundAtEnd = roundNumber;
    try {
      await Future<void>.delayed(const Duration(milliseconds: 600));
      if (!mounted ||
          roundEnding ||
          currentPlayer != playerAtEnd ||
          roundNumber != roundAtEnd ||
          !turnFinished)
        return;
      await nextPlayer();
    } finally {
      _autoAdvancePending = false;
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

    GameFeedback.trigger('sound_play.wav', haptic: GameHaptic.medium);
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
          showMessage(
            'Dünger geht erst, wenn bereits eine Gras-Karte in deiner Plantage liegt.',
          );
          return;
        }

        if (grass.power >= 200) {
          showMessage(
            'Dein Gras steht bereits bei 200 g – höher geht es nicht.',
          );
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

        GameFeedback.trigger('sound_action.wav', haptic: GameHaptic.medium);
        showMessage('🌱 Dünger: Dein Gras steigt auf $newPower g.');
        return;

      case 'Übertopf':
        if (grassSlots[currentPlayer] == null) {
          showMessage(
            'Übertopf geht erst, wenn eine Gras-Karte in deiner Plantage liegt.',
          );
          return;
        }

        setState(() {
          grassProtected[currentPlayer] = true;
          removeSelectedPlayedCard(action);
          turnFinished = true;
        });

        GameFeedback.trigger('sound_action.wav', haptic: GameHaptic.medium);
        showMessage(
          '🪴 Übertopf: Dein Gras ist bis zu deinem nächsten eigenen Zug geschützt.',
        );
        return;

      case 'Beste Freunde':
        // Nach dem normalen Ziehen sind in der Regel genug Handkarten vorhanden.
        // Die Aktionskarte selbst wird erst nach der Zielwahl entfernt.
        if (hands[currentPlayer].length <= 1) {
          showMessage(
            'Du brauchst neben „Beste Freunde“ noch mindestens eine weitere Handkarte.',
          );
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
          showMessage(
            '${widget.players[target]} hat keine Handkarte zum Tauschen.',
          );
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

        GameFeedback.trigger('sound_action.wav', haptic: GameHaptic.medium);
        showMessage(
          '🤝 Beste Freunde: Ihr habt blind je eine Handkarte getauscht.',
        );
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
          GameFeedback.trigger('sound_action.wav', haptic: GameHaptic.medium);
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
          GameFeedback.trigger('sound_action.wav', haptic: GameHaptic.medium);
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
          GameFeedback.trigger('sound_action.wav', haptic: GameHaptic.medium);
          showMessage(
            '😎 Ich zieh mir zwei: ${drawn.length} zusätzliche Karten gezogen.',
          );
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
                    leading: Text(
                      cardIcon(cards[i].type),
                      style: const TextStyle(fontSize: 25),
                    ),
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
            title: const Text('Handkartenlimit: 5'),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Wähle eine Karte, die du ablegen möchtest.'),
                  const SizedBox(height: 10),
                  for (int i = 0; i < hands[currentPlayer].length; i++)
                    ListTile(
                      leading: Text(
                        cardIcon(hands[currentPlayer][i].type),
                        style: const TextStyle(fontSize: 23),
                      ),
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
      if (target < widget.botPlayers.length && widget.botPlayers[target]) {
        defenseIndex = defenseIndices.firstWhere(
          (index) => hands[target][index].title == 'Alles easy',
          orElse: () => defenseIndices.first,
        );
        await Future.delayed(const Duration(milliseconds: 450));
      } else {
        final result = await chooseDefense(target, attack, defenseIndices);
        if (!mounted) return;
        defenseIndex = result ?? -1;
      }
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

      GameFeedback.trigger('sound_defend.wav', haptic: GameHaptic.heavy);
      showMessage(
        '${widget.players[target]} wehrt ${attack.title} mit ${defense.title} ab!',
      );
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

    GameFeedback.trigger('sound_attack.wav', haptic: GameHaptic.heavy);
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

      if (attack.title == 'Stromausfall' &&
          defense.title == 'Sicherungskasten') {
        result.add(i);
      }
      if (attack.title == 'Energiediebstahl' && defense.title == 'Wachhund') {
        result.add(i);
      }
      if (attack.title == 'Schädlingsbefall' &&
          defense.title == 'Schädlingsmittel') {
        result.add(i);
      }
      if ((attack.title == 'Razzia' || attack.title == 'Zu platt') &&
          defense.title == 'Anwalt') {
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
          title: PulseScale(
            active: true,
            minScale: 1.0,
            maxScale: 1.025,
            duration: const Duration(milliseconds: 480),
            child: Row(
              children: [
                const Text('💥', style: TextStyle(fontSize: 24)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('${widget.players[player]} wird angegriffen!'),
                ),
              ],
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${attack.title}\n${attack.effect}',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              const Text(
                'Verteidigung einsetzen?',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
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
        if (energy == null)
          return '${widget.players[target]} hat noch keine Energie.';
        if (energy.power <= 25)
          return '${widget.players[target]} ist bereits bei 25 %.';

        final newPower = energy.power == 100
            ? 75
            : energy.power == 75
            ? 50
            : 25;
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
        if (grass == null)
          return '${widget.players[target]} hat noch kein Gras.';
        if (grass.power <= 20)
          return '${widget.players[target]} ist bereits bei 20 g.';

        final newPower = grass.power == 200
            ? 100
            : grass.power == 100
            ? 50
            : 20;
        grassSlots[target] = grassCard(newPower);
        return '${widget.players[target]}: Gras sinkt auf $newPower g.';

      case 'Razzia':
        if (hands[target].isEmpty)
          return '${widget.players[target]} hat keine Handkarte.';

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
    if (!hasDrawn ||
        turnFinished ||
        _resolvingPlay ||
        _autoAdvancePending ||
        roundEnding)
      return;

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

    GameFeedback.trigger('sound_play.wav', haptic: GameHaptic.light);
    _advanceHumanTurnAutomatically();
  }

  bool automaticRoundEndReached() {
    return completedTurns.every((turns) => turns >= maxTurnsPerPlayerPerRound);
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
        showMessage(
          'Klopfen geht nur zu Beginn deines Zuges – bevor du eine Karte ziehst.',
        );
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
          List.generate(
            widget.players.length,
            (i) => i,
          ).where((i) => i != currentPlayer),
        );
    });

    GameFeedback.trigger('sound_knock.wav', haptic: GameHaptic.heavy);
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
      await finishRound(reason: 'Maximale Rundendauer erreicht');
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
      await finishRound(reason: 'Maximale Rundendauer erreicht');
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

    _maybeRunBotTurn();
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
            showMessage(
              '${skippedPlayers.join(', ')} setzt den letzten Zug aus.',
            );
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
      _maybeRunBotTurn();
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

  Future<void> finishRound({String reason = 'Klopfen'}) async {
    if (roundEnding) return;

    roundEnding = true;

    GameFeedback.trigger('sound_round.wav', haptic: GameHaptic.medium);

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
      int? payout;
      try {
        payout = await TestWallet.instance.settle(
          widget.coinMatch,
          totalScores,
          roundWins,
        );
      } catch (error) {
        if (mounted) {
          await showDialog<void>(
            context: context,
            barrierDismissible: false,
            builder: (dialogContext) => AlertDialog(
              title: const Text('Guthaben nicht gespeichert'),
              content: Text('$error\nBitte erneut versuchen.'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('ERNEUT VERSUCHEN'),
                ),
              ],
            ),
          );
          // Keep the final scores intact; retry settlement without another round.
          if (mounted) _retryCoinSettlement();
        }
        return;
      }
      if (!mounted) return;
      GameFeedback.trigger('sound_win.wav', haptic: GameHaptic.heavy);
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => FinalScoreScreen(
            coinPayout: payout,
            entryFee: widget.coinMatch?.fee ?? 0,
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
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeRunBotTurn());
  }

  Future<void> _retryCoinSettlement() async {
    try {
      final payout = await TestWallet.instance.settle(
        widget.coinMatch,
        totalScores,
        roundWins,
      );
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => FinalScoreScreen(
            players: widget.players,
            totalScores: totalScores,
            roundWins: roundWins,
            coinPayout: payout,
            entryFee: widget.coinMatch?.fee ?? 0,
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (c) => AlertDialog(
          title: const Text('Speichern fehlgeschlagen'),
          content: Text('$error'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('ERNEUT VERSUCHEN'),
            ),
          ],
        ),
      );
      if (mounted) _retryCoinSettlement();
    }
  }

  Future<void> showCardZoom(GameCard card) async {
    await showDialog<void>(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: const Color(0xFF071B10),
          insetPadding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 430, maxHeight: 720),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          card.title.toUpperCase(),
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Flexible(
                    child: InteractiveViewer(
                      minScale: 1,
                      maxScale: 3,
                      child: AspectRatio(
                        aspectRatio: 2 / 3,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(18),
                          child: CardFace(card: card),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '${card.value}  •  ${card.effect}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white70),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Tipp: Im großen Bild kannst du mit der Maus bzw. mit zwei Fingern zoomen.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 11, color: Colors.white38),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void showPlayerPlantation(int player) {
    final points = calculatePoints(player);

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF091E14),
      isScrollControlled: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 18,
                      backgroundColor: playerAccent(player),
                      child: player == currentPlayer
                          ? const Text('👑', style: TextStyle(fontSize: 16))
                          : const Icon(
                              Icons.person,
                              color: Colors.black87,
                              size: 20,
                            ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        widget.players[player],
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    Text(
                      '$points P',
                      style: const TextStyle(
                        color: kGold,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                const Text(
                  'Offene Plantage – Handkarten bleiben geheim',
                  style: TextStyle(color: Colors.white54, fontSize: 10),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: PlantSlot(
                        icon: '🌿',
                        title: 'GRAS',
                        card: grassSlots[player],
                        protected: grassProtected[player],
                      ),
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: PlantSlot(
                        icon: '⚡',
                        title: 'ENERGIE',
                        card: energySlots[player],
                      ),
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: PlantSlot(
                        icon: '👑',
                        title: 'BASIS',
                        card: baseSlots[player],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.pop(sheetContext),
                    child: const Text('SCHLIESSEN'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ==========================================================
  // SPIEL AUFGEBEN
  // ==========================================================

  Future<void> confirmGiveUp() async {
    final giveUp = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFF0B2117),
          title: const Row(
            children: [
              Icon(Icons.flag_outlined, color: Color(0xFFFF6B6B)),
              SizedBox(width: 10),
              Text('SPIEL AUFGEBEN?'),
            ],
          ),
          content: const Text(
            'Das aktuelle Spiel wird beendet und du kehrst zum Hauptmenü zurück. '
            'Der aktuelle Spielstand und der Münzeinsatz dieser Partie gehen verloren.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('WEITERSPIELEN'),
            ),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFB3261E),
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.pop(dialogContext, true),
              icon: const Icon(Icons.flag_rounded),
              label: const Text('AUFGEBEN'),
            ),
          ],
        );
      },
    );

    if (giveUp == true && mounted) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  // ==========================================================
  // INFO
  // ==========================================================

  void showMessage(String text) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), duration: const Duration(seconds: 3)),
    );
  }

  // ==========================================================
  // UI – QUERFORMAT / 3 SPIELER
  // ==========================================================

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    if (media.orientation != Orientation.landscape) {
      return Scaffold(
        body: LeafBackground(
          child: SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(Icons.screen_rotation_rounded, size: 58, color: kGold),
                    SizedBox(height: 14),
                    Text(
                      'BITTE IPHONE QUER HALTEN',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Graskönig ist ab dieser Version für Querformat optimiert.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white60),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    final hand = hands[currentPlayer];
    final points = calculatePoints(currentPlayer);
    final complete = plantationComplete(currentPlayer);
    final knockReady = canKnock();
    final topDiscard = discardPile.isEmpty ? null : discardPile.last;
    final opponents = <int>[
      for (int i = 0; i < widget.players.length; i++)
        if (i != currentPlayer) i,
    ];

    Widget playerPanel(int player, {required bool reverse}) {
      return LandscapePlayerPanel(
        playerIndex: player,
        avatarAsset: widget.avatarAssets[player],
        name: widget.players[player],
        score: totalScores[player],
        grass: grassSlots[player],
        energy: energySlots[player],
        base: baseSlots[player],
        grassProtected: grassProtected[player],
        reverse: reverse,
        onTap: () => showPlayerPlantation(player),
        onCardTap: (card) {
          if (card != null) showCardZoom(card);
        },
      );
    }

    return Scaffold(
      body: LeafBackground(
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final veryLow = constraints.maxHeight < 350;
              final topHeight = veryLow ? 72.0 : 82.0;
              final centerHeight = veryLow ? 108.0 : 120.0;
              final handHeight = max(
                110.0,
                constraints.maxHeight - topHeight - centerHeight - 18,
              );

              return Stack(
                children: [
                  Positioned.fill(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
                      child: Column(
                        children: [
                          SizedBox(
                            height: topHeight,
                            child: Row(
                              children: [
                                Expanded(
                                  child: opponents.isNotEmpty
                                      ? playerPanel(
                                          opponents.first,
                                          reverse: false,
                                        )
                                      : const SizedBox.shrink(),
                                ),
                                const SizedBox(width: 8),
                                SizedBox(
                                  width: veryLow ? 116 : 132,
                                  child: RoundCenterBadge(
                                    roundNumber: roundNumber,
                                    currentTurn:
                                        completedTurns[currentPlayer] + 1,
                                    deckRemaining: deck.length,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: opponents.length > 1
                                      ? playerPanel(opponents[1], reverse: true)
                                      : const SizedBox.shrink(),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 4),
                          SizedBox(
                            height: centerHeight,
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Expanded(
                                  flex: 10,
                                  child: CurrentPlantationPanel(
                                    playerIndex: currentPlayer,
                                    avatarAsset:
                                        widget.avatarAssets[currentPlayer],
                                    name: widget.players[currentPlayer],
                                    score: points,
                                    grass: grassSlots[currentPlayer],
                                    energy: energySlots[currentPlayer],
                                    base: baseSlots[currentPlayer],
                                    grassProtected:
                                        grassProtected[currentPlayer],
                                    onCardTap: (card) {
                                      if (card != null) showCardZoom(card);
                                    },
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  flex: 8,
                                  child: CenterCardTable(
                                    deckRemaining: deck.length,
                                    canDraw:
                                        !isBotTurn &&
                                        !hasDrawn &&
                                        deck.isNotEmpty,
                                    onDraw: drawCard,
                                    topDiscard: topDiscard,
                                    canTakeDiscard:
                                        !isBotTurn &&
                                        !hasDrawn &&
                                        topDiscard != null,
                                    onTakeDiscard: drawDiscardCard,
                                    onZoomDiscard: topDiscard == null
                                        ? null
                                        : () => showCardZoom(topDiscard),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  flex: 7,
                                  child: LandscapeActionPanel(
                                    botTurn: isBotTurn,
                                    turnFinished: turnFinished,
                                    knockActive: knockActive,
                                    knockReady: knockReady,
                                    complete: complete,
                                    completedTurns:
                                        completedTurns[currentPlayer],
                                    onPlay: playSelectedCard,
                                    onDiscard: discardSelectedCard,
                                    onKnock: knock,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 4),
                          Expanded(
                            child: Container(
                              decoration: BoxDecoration(
                                color: const Color(0xB8061B11),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: Colors.white12),
                              ),
                              padding: const EdgeInsets.fromLTRB(8, 4, 8, 2),
                              child: Row(
                                children: [
                                  SizedBox(
                                    width: veryLow ? 98 : 112,
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        GraskoenigAvatar(
                                          playerIndex: currentPlayer,
                                          assetPath: widget
                                              .avatarAssets[currentPlayer],
                                          size: veryLow ? 42 : 50,
                                          borderColor: playerAccent(
                                            currentPlayer,
                                          ),
                                          active: true,
                                        ),
                                        const SizedBox(height: 3),
                                        Text(
                                          widget.players[currentPlayer],
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          textAlign: TextAlign.center,
                                          style: const TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w900,
                                          ),
                                        ),
                                        Text(
                                          hasDrawn
                                              ? 'KARTE SPIELEN'
                                              : 'ZUERST ZIEHEN',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            fontSize: 8,
                                            fontWeight: FontWeight.w800,
                                            color: hasDrawn ? kNeon : kGold,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Expanded(
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.end,
                                      children: [
                                        if (knockActive)
                                          Padding(
                                            padding: const EdgeInsets.only(
                                              bottom: 2,
                                            ),
                                            child: Text(
                                              '👊 ${widget.players[knockingPlayer!]} hat geklopft – letzter Zug!',
                                              textAlign: TextAlign.center,
                                              style: const TextStyle(
                                                color: kGold,
                                                fontSize: 9,
                                                fontWeight: FontWeight.w900,
                                              ),
                                            ),
                                          ),
                                        Expanded(
                                          child: isBotTurn
                                              ? FittedBox(
                                                  fit: BoxFit.scaleDown,
                                                  child: SizedBox(
                                                    height: veryLow ? 92 : 110,
                                                    child: Row(
                                                      mainAxisSize:
                                                          MainAxisSize.min,
                                                      children: [
                                                        for (
                                                          int i = 0;
                                                          i < hand.length;
                                                          i++
                                                        )
                                                          Padding(
                                                            padding:
                                                                const EdgeInsets.symmetric(
                                                                  horizontal: 2,
                                                                ),
                                                            child: SizedBox(
                                                              width: veryLow
                                                                  ? 34
                                                                  : 42,
                                                              child: ClipRRect(
                                                                borderRadius:
                                                                    BorderRadius.circular(
                                                                      6,
                                                                    ),
                                                                child: Image.asset(
                                                                  'assets/cards/back.jpg',
                                                                  fit: BoxFit
                                                                      .cover,
                                                                  errorBuilder: (_, __, ___) => Container(
                                                                    color:
                                                                        kPanel2,
                                                                    alignment:
                                                                        Alignment
                                                                            .center,
                                                                    child: const Icon(
                                                                      Icons
                                                                          .forest,
                                                                      color:
                                                                          kMint,
                                                                    ),
                                                                  ),
                                                                ),
                                                              ),
                                                            ),
                                                          ),
                                                      ],
                                                    ),
                                                  ),
                                                )
                                              : HandFan(
                                                  hand: hand,
                                                  selectedIndex:
                                                      selectedCardIndex,
                                                  onSelect: selectCard,
                                                  onZoom: showCardZoom,
                                                  cardWidth: veryLow ? 72 : 82,
                                                  cardHeight: veryLow
                                                      ? 104
                                                      : 120,
                                                  fanHeight: handHeight,
                                                  minStep: veryLow ? 30 : 34,
                                                ),
                                        ),
                                        if (!isBotTurn &&
                                            selectedCardIndex != null)
                                          Text(
                                            'Ausgewählt: ${hand[selectedCardIndex!].title}',
                                            textAlign: TextAlign.center,
                                            style: const TextStyle(
                                              color: kGold,
                                              fontSize: 8.5,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    left: 10,
                    top: 8,
                    child: Material(
                      color: const Color(0xDD071B12),
                      shape: const CircleBorder(),
                      child: IconButton(
                        tooltip: 'Menü',
                        iconSize: 20,
                        onPressed: () {
                          showModalBottomSheet<void>(
                            context: context,
                            backgroundColor: const Color(0xFF091E14),
                            builder: (_) => SafeArea(
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    ListTile(
                                      leading: const Icon(
                                        Icons.menu_book_outlined,
                                      ),
                                      title: const Text('Regeln ansehen'),
                                      onTap: () {
                                        Navigator.pop(context);
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) => const RulesScreen(),
                                          ),
                                        );
                                      },
                                    ),
                                    ListTile(
                                      leading: const Icon(Icons.style_outlined),
                                      title: const Text('Kartenübersicht'),
                                      onTap: () {
                                        Navigator.pop(context);
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) =>
                                                const CardsOverviewScreen(),
                                          ),
                                        );
                                      },
                                    ),
                                    ListTile(
                                      leading: const Icon(
                                        Icons.settings_outlined,
                                      ),
                                      title: const Text('Ton & Vibration'),
                                      onTap: () {
                                        Navigator.pop(context);
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) =>
                                                const SettingsScreen(),
                                          ),
                                        );
                                      },
                                    ),
                                    const Divider(color: Colors.white12),
                                    ListTile(
                                      leading: const Icon(
                                        Icons.flag_outlined,
                                        color: Color(0xFFFF6B6B),
                                      ),
                                      title: const Text(
                                        'Spiel aufgeben',
                                        style: TextStyle(
                                          color: Color(0xFFFF8A80),
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                      onTap: () {
                                        Navigator.pop(context);
                                        Future.delayed(
                                          Duration.zero,
                                          confirmGiveUp,
                                        );
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                        icon: const Icon(Icons.menu_rounded),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class GraskoenigAvatar extends StatelessWidget {
  final int playerIndex;
  final String? assetPath;
  final double size;
  final Color borderColor;
  final bool active;

  const GraskoenigAvatar({
    super.key,
    required this.playerIndex,
    this.assetPath,
    required this.size,
    required this.borderColor,
    this.active = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: active ? kGold : borderColor,
          width: active ? 3 : 2,
        ),
        boxShadow: active
            ? const [BoxShadow(color: Color(0x6659FF7C), blurRadius: 10)]
            : null,
      ),
      child: ClipOval(
        child: CharacterPortrait(
          asset: assetPath ?? playerAvatarAsset(playerIndex),
        ),
      ),
    );
  }
}

class MiniPlantCard extends StatelessWidget {
  final String label;
  final String icon;
  final GameCard? card;
  final bool protected;
  final ValueChanged<GameCard?>? onTap;

  const MiniPlantCard({
    super.key,
    required this.label,
    required this.icon,
    required this.card,
    this.protected = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: card == null || onTap == null ? null : () => onTap!(card),
      child: Container(
        width: 52,
        height: 64,
        decoration: BoxDecoration(
          color: const Color(0xFF0A291A),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: protected ? Colors.lightBlueAccent : Colors.white24,
            width: protected ? 2 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            Positioned.fill(
              child: card != null
                  ? CardFace(card: card!)
                  : Center(
                      child: Text(
                        icon,
                        style: const TextStyle(
                          fontSize: 21,
                          color: Colors.white30,
                        ),
                      ),
                    ),
            ),
            Positioned(
              left: card == null ? 2 : 18,
              right: 2,
              bottom: 2,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 1.5),
                decoration: BoxDecoration(
                  color: const Color(0xD8071B12),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  card == null ? label : card!.value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 7.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class LandscapePlayerPanel extends StatelessWidget {
  final int playerIndex;
  final String avatarAsset;
  final String name;
  final int score;
  final GameCard? grass;
  final GameCard? energy;
  final GameCard? base;
  final bool grassProtected;
  final bool reverse;
  final VoidCallback onTap;
  final ValueChanged<GameCard?> onCardTap;

  const LandscapePlayerPanel({
    super.key,
    required this.playerIndex,
    required this.avatarAsset,
    required this.name,
    required this.score,
    required this.grass,
    required this.energy,
    required this.base,
    required this.grassProtected,
    required this.reverse,
    required this.onTap,
    required this.onCardTap,
  });

  @override
  Widget build(BuildContext context) {
    final accent = playerAccent(playerIndex);
    final avatarBlock = GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 86,
        child: Row(
          mainAxisAlignment: reverse
              ? MainAxisAlignment.end
              : MainAxisAlignment.start,
          children: [
            if (reverse) ...[
              Flexible(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      '$score P',
                      style: const TextStyle(
                        fontSize: 9,
                        color: kGold,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 5),
            ],
            GraskoenigAvatar(
              playerIndex: playerIndex,
              assetPath: avatarAsset,
              size: 42,
              borderColor: accent,
            ),
            if (!reverse) ...[
              const SizedBox(width: 5),
              Flexible(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      '$score P',
                      style: const TextStyle(
                        fontSize: 9,
                        color: kGold,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );

    final plantation = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        MiniPlantCard(
          label: 'GRAS',
          icon: '🌿',
          card: grass,
          protected: grassProtected,
          onTap: onCardTap,
        ),
        const SizedBox(width: 4),
        MiniPlantCard(
          label: 'ENERGIE',
          icon: '⚡',
          card: energy,
          onTap: onCardTap,
        ),
        const SizedBox(width: 4),
        MiniPlantCard(label: 'BASIS', icon: '👑', card: base, onTap: onCardTap),
      ],
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xD9092116),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withOpacity(0.6)),
      ),
      child: Row(
        mainAxisAlignment: reverse
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        children: reverse
            ? [
                Expanded(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: plantation,
                  ),
                ),
                const SizedBox(width: 7),
                avatarBlock,
              ]
            : [
                avatarBlock,
                const SizedBox(width: 7),
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: plantation,
                  ),
                ),
              ],
      ),
    );
  }
}

class CurrentPlantationPanel extends StatelessWidget {
  final int playerIndex;
  final String avatarAsset;
  final String name;
  final int score;
  final GameCard? grass;
  final GameCard? energy;
  final GameCard? base;
  final bool grassProtected;
  final ValueChanged<GameCard?> onCardTap;

  const CurrentPlantationPanel({
    super.key,
    required this.playerIndex,
    required this.avatarAsset,
    required this.name,
    required this.score,
    required this.grass,
    required this.energy,
    required this.base,
    required this.grassProtected,
    required this.onCardTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(7),
      decoration: BoxDecoration(
        color: const Color(0xE60A2518),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: playerAccent(playerIndex).withOpacity(0.7)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              GraskoenigAvatar(
                playerIndex: playerIndex,
                assetPath: avatarAsset,
                size: 34,
                borderColor: playerAccent(playerIndex),
                active: true,
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'DEINE PLANTAGE • $name',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      score == 0 ? 'noch nicht vollständig' : '$score PUNKTE',
                      style: TextStyle(
                        fontSize: 9,
                        color: score == 0 ? Colors.white54 : kNeon,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              MiniPlantCard(
                label: 'GRAS',
                icon: '🌿',
                card: grass,
                protected: grassProtected,
                onTap: onCardTap,
              ),
              const SizedBox(width: 5),
              MiniPlantCard(
                label: 'ENERGIE',
                icon: '⚡',
                card: energy,
                onTap: onCardTap,
              ),
              const SizedBox(width: 5),
              MiniPlantCard(
                label: 'BASIS',
                icon: '👑',
                card: base,
                onTap: onCardTap,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class RoundCenterBadge extends StatelessWidget {
  final int roundNumber;
  final int currentTurn;
  final int deckRemaining;

  const RoundCenterBadge({
    super.key,
    required this.roundNumber,
    required this.currentTurn,
    required this.deckRemaining,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xE6092116),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kGold.withOpacity(0.55)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'RUNDE $roundNumber/4',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w900,
              color: kGold,
            ),
          ),
          Text(
            'ZUG $currentTurn',
            style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w800),
          ),
          Text(
            '$deckRemaining Karten',
            style: const TextStyle(fontSize: 8, color: Colors.white54),
          ),
        ],
      ),
    );
  }
}

class CenterCardTable extends StatelessWidget {
  final int deckRemaining;
  final bool canDraw;
  final VoidCallback onDraw;
  final GameCard? topDiscard;
  final bool canTakeDiscard;
  final VoidCallback onTakeDiscard;
  final VoidCallback? onZoomDiscard;

  const CenterCardTable({
    super.key,
    required this.deckRemaining,
    required this.canDraw,
    required this.onDraw,
    required this.topDiscard,
    required this.canTakeDiscard,
    required this.onTakeDiscard,
    this.onZoomDiscard,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xAA04130C),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: CardBackStack(
                remaining: deckRemaining,
                enabled: canDraw,
                onTap: onDraw,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: DiscardStack(
                card: topDiscard,
                enabled: canTakeDiscard,
                onTake: onTakeDiscard,
                onZoom: onZoomDiscard,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class LandscapeActionPanel extends StatelessWidget {
  final bool botTurn;
  final bool turnFinished;
  final bool knockActive;
  final bool knockReady;
  final bool complete;
  final int completedTurns;
  final VoidCallback onPlay;
  final VoidCallback onDiscard;
  final VoidCallback onKnock;

  const LandscapeActionPanel({
    super.key,
    required this.botTurn,
    required this.turnFinished,
    required this.knockActive,
    required this.knockReady,
    required this.complete,
    required this.completedTurns,
    required this.onPlay,
    required this.onDiscard,
    required this.onKnock,
  });

  String get knockLabel {
    if (knockActive) return 'GEKLOPFT';
    if (completedTurns < 2) return 'KLOPFEN AB ZUG 3';
    if (!complete) return 'PLANTAGE FEHLT';
    if (knockReady) return '👊 ICH KLOPFE!';
    return 'KLOPFEN';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(7),
      decoration: BoxDecoration(
        color: const Color(0xE6092116),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white12),
      ),
      child: botTurn
          ? const Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.smart_toy_rounded, color: kGold, size: 32),
                SizedBox(height: 6),
                Text(
                  'BOT DENKT…',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontWeight: FontWeight.w900, color: kGold),
                ),
                SizedBox(height: 3),
                Text(
                  'Kiffer-Karl ist am Zug',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 9, color: Colors.white54),
                ),
              ],
            )
          : turnFinished
          ? const Center(
              child: Text(
                'ZUG ABGESCHLOSSEN',
                textAlign: TextAlign.center,
                style: TextStyle(color: kMint, fontWeight: FontWeight.w900),
              ),
            )
          : Column(
              children: [
                Expanded(
                  child: FastTouchButton(
                    label: 'KARTE AUSSPIELEN',
                    onTap: onPlay,
                    filled: true,
                  ),
                ),
                const SizedBox(height: 5),
                Expanded(
                  child: FastTouchButton(label: 'ABLEGEN', onTap: onDiscard),
                ),
                const SizedBox(height: 5),
                Expanded(
                  child: FastTouchButton(
                    label: knockLabel,
                    onTap: knockActive ? null : onKnock,
                    accent: knockReady && !knockActive ? kGold : null,
                  ),
                ),
              ],
            ),
    );
  }
}

class FastTouchButton extends StatefulWidget {
  final String label;
  final VoidCallback? onTap;
  final bool filled;
  final Color? accent;

  const FastTouchButton({
    super.key,
    required this.label,
    required this.onTap,
    this.filled = false,
    this.accent,
  });

  @override
  State<FastTouchButton> createState() => _FastTouchButtonState();
}

class _FastTouchButtonState extends State<FastTouchButton> {
  bool _pressed = false;
  bool _locked = false;

  void _fire() {
    if (widget.onTap == null || _locked) return;
    _locked = true;
    widget.onTap!();
    Future<void>.delayed(const Duration(milliseconds: 220), () {
      if (mounted) _locked = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    final accent = widget.accent ?? (widget.filled ? kNeon : Colors.white38);

    // Keine Transform-/Scale-Animation auf interaktiven Flächen.
    // Das vermeidet auf Safari nach einer Drehung versetzte Hit-Tests.
    return SizedBox.expand(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: enabled ? _fire : null,
          onHighlightChanged: enabled
              ? (value) {
                  if (mounted) setState(() => _pressed = value);
                }
              : null,
          borderRadius: BorderRadius.circular(12),
          splashColor: accent.withValues(alpha: 0.18),
          highlightColor: accent.withValues(alpha: 0.10),
          child: Container(
            width: double.infinity,
            height: double.infinity,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: !enabled
                  ? Colors.white.withValues(alpha: 0.05)
                  : widget.filled
                  ? (_pressed
                        ? const Color(0xFF128A2F)
                        : const Color(0xFF16A638))
                  : (_pressed
                        ? const Color(0x55000000)
                        : const Color(0x42000000)),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: enabled ? accent : Colors.white12,
                width: widget.accent != null ? 2 : 1.2,
              ),
            ),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                widget.label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  color: !enabled
                      ? Colors.white30
                      : widget.accent ?? Colors.white,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class FinalScoreScreen extends StatelessWidget {
  final int? coinPayout;
  final int entryFee;
  final List<String> players;
  final List<int> totalScores;
  final List<int> roundWins;

  const FinalScoreScreen({
    super.key,
    this.coinPayout,
    this.entryFee = 0,
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
    candidates = candidates
        .where((i) => roundWins[i] == highestRoundWins)
        .toList();
    return candidates;
  }

  @override
  Widget build(BuildContext context) {
    final winners = determineWinners();
    final winnerText = winners.length == 1
        ? '${players[winners.first]} ist der GRASKÖNIG!'
        : '${winners.map((i) => players[i]).join(' & ')} sind GRASKÖNIGE!';

    final order = List<int>.generate(players.length, (i) => i)
      ..sort((a, b) => totalScores[b].compareTo(totalScores[a]));

    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: LeafBackground(
              child: SafeArea(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 430),
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(18, 24, 18, 28),
                      children: [
                        if (coinPayout != null)
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Text(
                                'SPIELER 1 • ${coinPayout! > 0 ? 'GEWINN' : 'KEIN GEWINN'}\n'
                                'Auszahlung: $coinPayout Münzen • Einsatz: $entryFee\n'
                                'Guthaben: ${TestWallet.instance.coins} Münzen',
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),
                        const Text(
                          'GRATULATION!',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: kNeon,
                            fontSize: 27,
                            fontWeight: FontWeight.w900,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Center(
                          child: Text('👑', style: TextStyle(fontSize: 78)),
                        ),
                        const Text(
                          'GRASKÖNIG',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 42,
                            fontWeight: FontWeight.w900,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                        const SizedBox(height: 7),
                        Text(
                          winnerText,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: kCream,
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 22),
                        Container(
                          decoration: BoxDecoration(
                            color: const Color(0xDB061E12),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: Colors.white12),
                          ),
                          child: Column(
                            children: [
                              for (
                                int position = 0;
                                position < order.length;
                                position++
                              )
                                Container(
                                  margin: const EdgeInsets.all(6),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 9,
                                  ),
                                  decoration: BoxDecoration(
                                    color: position == 0
                                        ? const Color(0x443F8C2D)
                                        : Colors.black26,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: position == 0
                                          ? kGold
                                          : Colors.white10,
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      SizedBox(
                                        width: 30,
                                        child: Text(
                                          position == 0
                                              ? '👑'
                                              : '${position + 1}.',
                                          style: const TextStyle(
                                            fontSize: 20,
                                            fontWeight: FontWeight.w900,
                                          ),
                                        ),
                                      ),
                                      CircleAvatar(
                                        radius: 14,
                                        backgroundColor: playerAccent(
                                          order[position],
                                        ),
                                        child: const Icon(
                                          Icons.person,
                                          color: Colors.black87,
                                          size: 17,
                                        ),
                                      ),
                                      const SizedBox(width: 9),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              players[order[position]],
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w900,
                                              ),
                                            ),
                                            Text(
                                              '${roundWins[order[position]]}× beste Plantage',
                                              style: const TextStyle(
                                                fontSize: 9,
                                                color: Colors.white54,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Text(
                                        '${totalScores[order[position]]}',
                                        style: TextStyle(
                                          fontSize: position == 0 ? 24 : 19,
                                          fontWeight: FontWeight.w900,
                                          color: position == 0
                                              ? kGold
                                              : Colors.white,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 18),
                        SizedBox(
                          height: 54,
                          child: FilledButton(
                            onPressed: () {
                              Navigator.of(context).pushAndRemoveUntil(
                                MaterialPageRoute(
                                  builder: (_) => const StartScreen(),
                                ),
                                (route) => false,
                              );
                            },
                            child: const Text('NEUES SPIEL'),
                          ),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          height: 48,
                          child: OutlinedButton(
                            onPressed: () {
                              Navigator.of(context).pushAndRemoveUntil(
                                MaterialPageRoute(
                                  builder: (_) => const StartScreen(),
                                ),
                                (route) => false,
                              );
                            },
                            child: const Text('HAUPTMENÜ'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          const Positioned.fill(
            child: IgnorePointer(child: ConfettiCelebration()),
          ),
        ],
      ),
    );
  }
}

class MenuButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool primary;

  const MenuButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.primary = false,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 54,
      child: primary
          ? FilledButton.icon(
              onPressed: onTap,
              icon: Icon(icon, size: 24),
              label: Text(
                label,
                style: const TextStyle(fontSize: 17, letterSpacing: 0.4),
              ),
            )
          : OutlinedButton.icon(
              onPressed: onTap,
              icon: Icon(icon, size: 22),
              label: Text(
                label,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.4,
                ),
              ),
            ),
    );
  }
}

class SectionPanel extends StatelessWidget {
  final String title;
  final Widget child;

  const SectionPanel({super.key, required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: const Color(0xDC071E12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w900,
              color: kCream,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class ModeRow extends StatelessWidget {
  final bool selected;
  final String title;
  final String subtitle;

  const ModeRow({
    super.key,
    required this.selected,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: selected ? const Color(0x3316A638) : Colors.black26,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: selected ? kNeon : Colors.white12),
      ),
      child: Row(
        children: [
          Icon(
            selected ? Icons.radio_button_checked : Icons.radio_button_off,
            color: selected ? kNeon : Colors.white38,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                Text(
                  subtitle,
                  style: const TextStyle(fontSize: 10, color: Colors.white54),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class PulseScale extends StatefulWidget {
  final bool active;
  final double minScale;
  final double maxScale;
  final Duration duration;
  final Widget child;

  const PulseScale({
    super.key,
    required this.active,
    required this.child,
    this.minScale = 1.0,
    this.maxScale = 1.04,
    this.duration = const Duration(milliseconds: 800),
  });

  @override
  State<PulseScale> createState() => _PulseScaleState();
}

class _PulseScaleState extends State<PulseScale>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);
    _syncAnimation();
  }

  @override
  void didUpdateWidget(covariant PulseScale oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active != widget.active ||
        oldWidget.duration != widget.duration) {
      _controller.duration = widget.duration;
      _syncAnimation();
    }
  }

  void _syncAnimation() {
    if (widget.active) {
      _controller.repeat(reverse: true);
    } else {
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) {
        final scale =
            widget.minScale +
            (widget.maxScale - widget.minScale) * _controller.value;
        return Transform.scale(scale: scale, child: child);
      },
    );
  }
}

class ConfettiCelebration extends StatefulWidget {
  const ConfettiCelebration({super.key});

  @override
  State<ConfettiCelebration> createState() => _ConfettiCelebrationState();
}

class _ConfettiCelebrationState extends State<ConfettiCelebration>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 5),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (_, __) => CustomPaint(
        painter: ConfettiPainter(_controller.value),
        size: Size.infinite,
      ),
    );
  }
}

class ConfettiPainter extends CustomPainter {
  final double progress;

  ConfettiPainter(this.progress);

  @override
  void paint(Canvas canvas, Size size) {
    final random = Random(42);
    const colors = <Color>[
      kNeon,
      kGold,
      Color(0xFFFF6B6B),
      Color(0xFF53A7FF),
      kCream,
    ];

    for (int i = 0; i < 42; i++) {
      final x = random.nextDouble() * size.width;
      final start = random.nextDouble();
      final speed = 0.45 + random.nextDouble() * 0.8;
      final yNorm = (start + progress * speed) % 1.15;
      final y = yNorm * size.height - 20;
      final sway = sin((progress * 8) + i) * (8 + random.nextDouble() * 12);
      final angle = progress * 8 + random.nextDouble() * pi;
      final w = 5.0 + random.nextDouble() * 5;
      final h = 8.0 + random.nextDouble() * 8;
      final paint = Paint()
        ..color = colors[i % colors.length].withOpacity(0.85);

      canvas.save();
      canvas.translate(x + sway, y);
      canvas.rotate(angle);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset.zero, width: w, height: h),
          const Radius.circular(2),
        ),
        paint,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant ConfettiPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

class LeafBackground extends StatelessWidget {
  final Widget child;

  const LeafBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: kBg),
        const IgnorePointer(child: CustomPaint(painter: LeafPatternPainter())),
        child,
      ],
    );
  }
}

class LeafPatternPainter extends CustomPainter {
  const LeafPatternPainter();

  @override
  void paint(Canvas canvas, Size size) {
    // Seven serrated leaflets form a recognizable hemp leaf, like the back.
    // Fixed spacing keeps the pattern visible on both phones and wide screens.
    const spacing = 150.0;
    final fill = Paint();
    final vein = Paint()
      ..color = const Color(0x553C8659)
      ..strokeWidth = 1.1
      ..style = PaintingStyle.stroke;

    for (int row = -1; row * spacing < size.height + spacing; row++) {
      for (int col = -1; col * spacing < size.width + spacing; col++) {
        final variant = (row + col) % 3;
        fill.color = const [
          Color(0x5530874B),
          Color(0x44336E46),
          Color(0x66317C49),
        ][variant];
        canvas.save();
        canvas.translate(
          col * spacing + (row.isOdd ? spacing / 2 : 0),
          row * spacing + 55,
        );
        canvas.rotate((row * 3 + col * 2) * .47);
        final scale = .85 + variant * .13;
        canvas.scale(scale);
        canvas.drawLine(Offset.zero, const Offset(0, 27), vein);
        for (int finger = -3; finger <= 3; finger++) {
          canvas.save();
          canvas.rotate(finger * .48);
          final length = 76.0 - finger.abs() * 14;
          final halfWidth = 10.0 - finger.abs() * 1.5;
          final blade = Path()..moveTo(0, 0);
          for (final side in [-1.0, 1.0]) {
            // Outward teeth alternate with shallow notches on each edge.
            for (int step = 1; step <= 12; step++) {
              final t = side < 0 ? step / 13 : (13 - step) / 13;
              final width = sin(pi * t) * halfWidth;
              final tooth = step.isEven ? .67 : 1.0;
              blade.lineTo(side * width * tooth, -length * t);
            }
            if (side < 0) blade.lineTo(0, -length);
          }
          blade.close();
          canvas.drawPath(blade, fill);
          canvas.drawLine(Offset.zero, Offset(0, -length + 5), vein);
          canvas.restore();
        }
        canvas.restore();
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class DiscardStack extends StatelessWidget {
  final GameCard? card;
  final bool enabled;
  final VoidCallback onTake;
  final VoidCallback? onZoom;

  const DiscardStack({
    super.key,
    required this.card,
    required this.enabled,
    required this.onTake,
    this.onZoom,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: enabled ? onTake : null,
                borderRadius: BorderRadius.circular(10),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: 70,
                  height: 104,
                  decoration: BoxDecoration(
                    color: const Color(0xFF0C2A1A),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: enabled ? kGold : Colors.white24,
                      width: enabled ? 2 : 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: enabled
                            ? kGold.withOpacity(0.18)
                            : Colors.black38,
                        blurRadius: enabled ? 12 : 8,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: card == null
                      ? const Center(
                          child: Icon(
                            Icons.layers_clear_outlined,
                            color: Colors.white24,
                            size: 30,
                          ),
                        )
                      : CardFace(card: card!),
                ),
              ),
            ),
            if (card != null && onZoom != null)
              Positioned(
                right: -5,
                top: -5,
                child: Listener(
                  behavior: HitTestBehavior.opaque,
                  onPointerDown: onZoom == null ? null : (_) => onZoom!(),
                  child: Container(
                    width: 25,
                    height: 25,
                    decoration: BoxDecoration(
                      color: const Color(0xDD071B12),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white24),
                    ),
                    child: const Icon(
                      Icons.search_rounded,
                      size: 15,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          enabled ? 'ABLAGE • ANTIPPEN' : 'ABLAGE',
          style: TextStyle(
            fontSize: 8.5,
            fontWeight: FontWeight.bold,
            color: enabled ? kGold : Colors.white,
          ),
        ),
      ],
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

class CardBackStack extends StatelessWidget {
  final int remaining;
  final bool enabled;
  final VoidCallback onTap;

  const CardBackStack({
    super.key,
    required this.remaining,
    required this.enabled,
    required this.onTap,
  });

  Widget backCard() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(9),
      child: Image.asset(
        'assets/cards/back.jpg',
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Container(
          color: const Color(0xFF0C482A),
          alignment: Alignment.center,
          child: const Text('👑', style: TextStyle(fontSize: 28)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Nur der sichtbare Kartenrücken ist der Zieh-Button.
        // Die komplette Kartenfläche reagiert auf einen Tap.
        SizedBox(
          width: 72,
          height: 92,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: enabled ? onTap : null,
              borderRadius: BorderRadius.circular(10),
              child: Opacity(
                opacity: enabled ? 1 : 0.52,
                child: Stack(
                  children: [
                    Positioned(
                      left: 12,
                      top: 0,
                      width: 56,
                      height: 84,
                      child: backCard(),
                    ),
                    Positioned(
                      left: 7,
                      top: 4,
                      width: 56,
                      height: 84,
                      child: backCard(),
                    ),
                    Positioned(
                      left: 2,
                      top: 8,
                      width: 56,
                      height: 84,
                      child: backCard(),
                    ),
                    if (enabled)
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: kGold.withValues(alpha: 0.55),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 3),
        Text(
          enabled
              ? 'ZIEHSTAPEL • KARTE ANTIPPEN • $remaining'
              : 'GEZOGEN • $remaining',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 9.5,
            fontWeight: FontWeight.bold,
            color: enabled ? kGold : Colors.white54,
          ),
        ),
      ],
    );
  }
}

class CardFallbackLarge extends StatelessWidget {
  final GameCard card;

  const CardFallbackLarge({super.key, required this.card});

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
        return const Color(0xFFDD278C);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: cardColor(),
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          Text(cardIcon(card.type), style: const TextStyle(fontSize: 54)),
          Text(
            card.title.toUpperCase(),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900),
          ),
          Text(
            card.value,
            style: const TextStyle(fontSize: 44, fontWeight: FontWeight.w900),
          ),
          Text(
            card.effect,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 17),
          ),
        ],
      ),
    );
  }
}

class HandFan extends StatelessWidget {
  final List<GameCard> hand;
  final int? selectedIndex;
  final ValueChanged<int> onSelect;
  final ValueChanged<GameCard> onZoom;
  final double cardWidth;
  final double cardHeight;
  final double fanHeight;
  final double minStep;

  const HandFan({
    super.key,
    required this.hand,
    required this.selectedIndex,
    required this.onSelect,
    required this.onZoom,
    this.cardWidth = 104,
    this.cardHeight = 154,
    this.fanHeight = 166,
    this.minStep = 38,
  });

  @override
  Widget build(BuildContext context) {
    if (hand.isEmpty) {
      return const SizedBox(
        height: 156,
        child: Center(
          child: Text(
            'Keine Karten auf der Hand',
            style: TextStyle(color: Colors.white54),
          ),
        ),
      );
    }

    const topPadding = 4.0;

    return SizedBox(
      height: fanHeight,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final count = hand.length;
          final maxWidth = constraints.maxWidth;
          final naturalStep = cardWidth + 8;
          final fitStep = count <= 1
              ? 0.0
              : (maxWidth - cardWidth) / (count - 1);
          final step = count <= 1
              ? 0.0
              : min(naturalStep, max(minStep, fitStep));
          final totalWidth = cardWidth + step * (count - 1);
          final startLeft = max(0.0, (maxWidth - totalWidth) / 2);

          final visualCards = <Widget>[];
          Widget? selectedVisual;

          for (int index = 0; index < count; index++) {
            final visual = Positioned(
              left: startLeft + (step * index),
              top: selectedIndex == index ? 0 : topPadding,
              width: cardWidth,
              height: cardHeight,
              child: IgnorePointer(
                child: GameCardWidget(
                  card: hand[index],
                  selected: selectedIndex == index,
                  onTap: () {},
                  onZoom: () {},
                  width: cardWidth,
                ),
              ),
            );
            if (selectedIndex == index) {
              selectedVisual = visual;
            } else {
              visualCards.add(visual);
            }
          }

          // Separate unsichtbare Touch-Zonen verhindern auf iPhone/Safari,
          // dass sich überlappende Karten gegenseitig die Berührung wegnehmen.
          final hitZones = <Widget>[];
          for (int index = 0; index < count; index++) {
            final visibleWidth = index == count - 1
                ? cardWidth
                : max(step, 44.0);
            hitZones.add(
              Positioned(
                left: startLeft + (step * index),
                top: 0,
                width: visibleWidth,
                height: cardHeight + 10,
                child: Listener(
                  behavior: HitTestBehavior.opaque,
                  onPointerDown: (_) => onSelect(index),
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onDoubleTap: () => onZoom(hand[index]),
                    onLongPress: () => onZoom(hand[index]),
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
            );
          }

          // Große Zoom-Fläche für die aktuell gewählte Karte.
          final selectedZoom = selectedIndex == null
              ? const <Widget>[]
              : <Widget>[
                  Positioned(
                    left: min(
                      maxWidth - 38,
                      startLeft + (step * selectedIndex!) + cardWidth - 34,
                    ),
                    top: 2,
                    width: 38,
                    height: 38,
                    child: Listener(
                      behavior: HitTestBehavior.opaque,
                      onPointerDown: (_) => onZoom(hand[selectedIndex!]),
                      child: Container(
                        decoration: BoxDecoration(
                          color: const Color(0xDD071B12),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white38),
                        ),
                        child: const Icon(
                          Icons.zoom_in_rounded,
                          size: 22,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ];

          return Stack(
            clipBehavior: Clip.none,
            children: [
              ...visualCards,
              if (selectedVisual != null) selectedVisual,
              ...hitZones,
              ...selectedZoom,
            ],
          );
        },
      ),
    );
  }
}

class GameCardWidget extends StatelessWidget {
  final GameCard card;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onZoom;
  final double width;

  const GameCardWidget({
    super.key,
    required this.card,
    required this.selected,
    required this.onTap,
    required this.onZoom,
    this.width = 104,
  });

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
        return const Color(0xFFDD278C);
    }
  }

  Widget fallbackCard() {
    return Container(
      color: cardColor(),
      padding: const EdgeInsets.all(10),
      child: Column(
        children: [
          Text(cardIcon(card.type), style: const TextStyle(fontSize: 27)),
          const SizedBox(height: 5),
          Text(
            card.title.toUpperCase(),
            textAlign: TextAlign.center,
            maxLines: 2,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
          ),
          const Spacer(),
          Text(
            card.value,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
          ),
          const Spacer(),
          Text(
            card.effect,
            textAlign: TextAlign.center,
            maxLines: 3,
            style: const TextStyle(fontSize: 9),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => onTap(),
      onLongPress: onZoom,
      child: AnimatedScale(
        scale: selected ? 1.045 : 1.0,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutBack,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: width,
          transform: selected
              ? Matrix4.translationValues(0, -8, 0)
              : Matrix4.identity(),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? Colors.amber : Colors.white,
              width: selected ? 4 : 2,
            ),
            boxShadow: [
              BoxShadow(
                color: selected
                    ? Colors.amber.withOpacity(0.35)
                    : Colors.black45,
                blurRadius: selected ? 12 : 6,
              ),
            ],
          ),
          child: Stack(
            children: [
              Positioned.fill(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(11),
                  child: CardFace(card: card),
                ),
              ),
              Positioned(
                top: 6,
                right: 6,
                child: Material(
                  color: Colors.black.withOpacity(0.58),
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: onZoom,
                    child: const Padding(
                      padding: EdgeInsets.all(7),
                      child: Icon(Icons.zoom_in, size: 18, color: Colors.white),
                    ),
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

class PlantSlot extends StatelessWidget {
  final String icon;
  final String title;
  final GameCard? card;
  final bool protected;

  const PlantSlot({
    super.key,
    required this.icon,
    required this.title,
    required this.card,
    this.protected = false,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOut,
      height: 92,
      decoration: BoxDecoration(
        color: const Color(0xFF0B2718),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: protected ? Colors.lightBlueAccent : Colors.white24,
          width: protected ? 3 : 2,
        ),
        boxShadow: card != null
            ? const [
                BoxShadow(
                  color: Color(0x3316A638),
                  blurRadius: 12,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 360),
        switchInCurve: Curves.easeOutBack,
        switchOutCurve: Curves.easeIn,
        transitionBuilder: (child, animation) {
          return FadeTransition(
            opacity: animation,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.78, end: 1.0).animate(animation),
              child: child,
            ),
          );
        },
        child: card == null
            ? Column(
                key: ValueKey('empty_$title'),
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(icon, style: const TextStyle(fontSize: 30)),
                  const SizedBox(height: 7),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              )
            : Padding(
                key: ValueKey('${card!.title}_${card!.value}_$protected'),
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
                child: Row(
                  children: [
                    if (card!.assetPath != null)
                      SizedBox(
                        width: 45,
                        height: 72,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(7),
                          child: CardFace(card: card!),
                        ),
                      )
                    else
                      SizedBox(
                        width: 42,
                        child: Center(
                          child: Text(
                            protected ? '🪴' : icon,
                            style: const TextStyle(fontSize: 30),
                          ),
                        ),
                      ),

                    const SizedBox(width: 5),

                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (protected) ...[
                            const FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(
                                '🪴 GESCHÜTZT',
                                style: TextStyle(
                                  fontSize: 8,
                                  color: Colors.lightBlueAccent,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(height: 2),
                          ],

                          Text(
                            card!.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 10,
                              height: 1.05,
                              fontWeight: FontWeight.bold,
                            ),
                          ),

                          const SizedBox(height: 3),

                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              card!.value,
                              maxLines: 1,
                              style: const TextStyle(
                                fontSize: 16,
                                height: 1,
                                fontWeight: FontWeight.w900,
                                color: kNeon,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

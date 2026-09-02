import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/api/api_client.dart';
import '../../../../core/utils/word_audio.dart';

/// One word card's data (§ word card deck, 2026-08-31) — named `WordDeckCard`
/// rather than `WordCard` to avoid colliding with the unrelated word-card
/// DTO in features/vocabulary/data/vocabulary_repository.dart (that one is
/// the backend's `wordId` lookup shape; this one is purely what this deck
/// needs to render). `ipa`/`example`/`exampleFocus` are nullable — the
/// backend's vocabulary doesn't carry an example sentence yet, so the deck
/// just omits that block for a card that doesn't have one, same as it
/// already tolerates a missing photo or audio recording.
class WordDeckCard {
  const WordDeckCard({
    required this.id,
    required this.word,
    required this.translation,
    this.ipa,
    this.example,
    this.exampleFocus,
    this.imageUrl,
    this.audioUrl,
  });

  final String id;
  final String word;
  final String translation;
  final String? ipa;
  final String? example;
  final String? exampleFocus;
  final String? imageUrl;
  final String? audioUrl;
}

const _ink = Color(0xFF141A2B);
const _mute = Color(0xFF6C7490);
const _line = Color(0xFFDDE4F0);
const _paper = Color(0xFFFFFFFF);
const _blue = Color(0xFF7FC3F2);
const _rose = Color(0xFFF5A9C8);
const _shadow = Color(0x8C162246);

/// A handful of pastel gradient pairs for a card's image area when it has
/// no photo yet (or while one is loading) — picked deterministically from
/// the word's own id, not randomly, so a given card looks the same every
/// time it's shown rather than flickering between colors on rebuild.
const _scenePalette = [
  (Color(0xFFBFE0F7), Color(0xFFE7D6F2)),
  (Color(0xFFC9D4EE), Color(0xFFEBD9E6)),
  (Color(0xFFD8ECC9), Color(0xFFF3E7C8)),
  (Color(0xFFD3C6EC), Color(0xFFF6C9B8)),
  (Color(0xFFC6E9E3), Color(0xFFDFEFF8)),
  (Color(0xFFDCEAF7), Color(0xFFF0F3FA)),
];

(Color, Color) _sceneColors(String id) => _scenePalette[id.hashCode.abs() % _scenePalette.length];

/// A swipeable deck of word cards (§ word card deck, 2026-08-31) — ports the
/// approved HTML/JS prototype's exact proportions, timings, curves and
/// gesture thresholds to Flutter rather than a reinvented version. Vertical
/// drag only: up commits to the next word, down returns to the previous
/// one; nothing here does network I/O — every word arrives ready via
/// [words]. Reusable across lessons: the caller supplies the words and two
/// callbacks, and handles what happens after the deck is finished.
class WordCardDeck extends ConsumerStatefulWidget {
  const WordCardDeck({
    super.key,
    required this.words,
    required this.courseId,
    required this.onComplete,
    this.initialIndex = 0,
    this.onCardChanged,
  });

  final List<WordDeckCard> words;
  final String courseId;

  /// Fired once, when the learner taps "Продолжить урок" on the completion
  /// screen — not merely when they swipe past the last card (swiping past
  /// the last card reveals the completion screen; leaving the deck is a
  /// separate, deliberate action, same as the prototype).
  final VoidCallback onComplete;

  final int initialIndex;

  /// Fired with the new front-card index every time it changes, forward or
  /// backward — persisting `vocabIndex` and deciding whether a "learned
  /// words" counter should increase are both the caller's job (§ deck spec:
  /// that counter must only ever increase, even though this index can move
  /// backward when the learner reviews a word).
  final ValueChanged<int>? onCardChanged;

  @override
  ConsumerState<WordCardDeck> createState() => _WordCardDeckState();
}

class _WordCardDeckState extends ConsumerState<WordCardDeck> with SingleTickerProviderStateMixin {
  static const _duration = Duration(milliseconds: 420);
  static const _curve = Cubic(0.2, 0.85, 0.25, 1);
  static const _nextThresholdPx = 90.0;
  // Decision threshold — how far a release must have dragged to COMMIT
  // backward at all. Distinct from _prevTravelPx below (how far the
  // incoming-card animation visually travels once committed) — conflating
  // the two was the original bug: the commit animation used to jump the
  // whole 1.15x deck-height offscreen in one frame instead of animating
  // through this same travel distance, so it never visibly played.
  static const _prevThresholdPx = 70.0;
  static const _prevTravelPx = 170.0;
  static const _velocityThreshold = 700.0; // logical px/s, matches the prototype's flick threshold

  late final AnimationController _controller;
  late int _index;
  double _dragDy = 0;
  int _dragDir = 0; // -1 dragging toward next, 1 toward previous, 0 none/rubber-band
  bool _dragging = false;
  double _deckHeight = 500;
  bool _playingAudio = false;

  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex.clamp(0, widget.words.length);
    _controller = AnimationController(vsync: this, duration: _duration);
    WidgetsBinding.instance.addPostFrameCallback((_) => _precacheWholeDeck());
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  String? _resolvedImage(WordDeckCard card) {
    final url = card.imageUrl;
    if (url == null || url.isEmpty) return null;
    final resolved = ref.read(apiClientProvider).assetUrl(url);
    return resolved.isEmpty ? null : resolved;
  }

  /// Warms the card currently on screen first, then the next two, then
  /// everything else in the lesson (§ word photos appear late, 2026-09-02).
  ///
  /// The old version started at `_index + 1`, so the card the learner was
  /// actually looking at — the very first one, on opening the lesson — was
  /// never warmed and had to fetch its own image while visible. With word
  /// photos running around a megabyte each that is seconds of empty card.
  /// Order matters more than the set: the visible card must not queue behind
  /// the rest of the deck.
  void _precacheWholeDeck() {
    final seen = <String>{};
    for (final i in [_index, _index + 1, _index + 2, ...List.generate(widget.words.length, (i) => i)]) {
      if (i < 0 || i >= widget.words.length) continue;
      final url = _resolvedImage(widget.words[i]);
      if (url == null || !seen.add(url)) continue;
      if (!mounted) return;
      // CachedNetworkImageProvider, not NetworkImage: this has to warm the
      // same disk cache the cards read from, otherwise the work is thrown
      // away when the app closes. Errors are swallowed on purpose — a photo
      // that fails to prefetch is retried by the card itself, and a broken
      // URL must never take down the lesson.
      precacheImage(CachedNetworkImageProvider(url), context, onError: (_, _) {});
    }
  }

  void _precacheAhead() => _precacheWholeDeck();

  Future<void> _animateDragTo(double target) async {
    final tween = Tween<double>(begin: _dragDy, end: target);
    _controller.value = 0;
    void listener() => setState(() => _dragDy = tween.transform(_controller.value));
    _controller.addListener(listener);
    await _controller.animateTo(1, curve: _curve);
    _controller.removeListener(listener);
  }

  Future<void> _commitNext() async {
    if (_index >= widget.words.length) return;
    await _animateDragTo(-_deckHeight * 1.2);
    if (!mounted) return;
    setState(() {
      _index++;
      _dragDy = 0;
      _dragDir = 0;
    });
    _precacheAhead();
    if (_index < widget.words.length) widget.onCardChanged?.call(_index);
  }

  Future<void> _commitPrev() async {
    if (_index <= 0) return;
    // Animates _dragDy from wherever it is (a live drag release, or 0 for a
    // keyboard press) up to _prevTravelPx — the same distance
    // _positionedCard's/_incomingPrevCard's own `t = dragDy / _prevTravelPx`
    // math already uses, so the incoming card visibly plays through the
    // whole arrival animation instead of only the fraction the drag itself
    // covered.
    setState(() => _dragDir = 1);
    await _animateDragTo(_prevTravelPx);
    if (!mounted) return;
    setState(() {
      _index--;
      _dragDy = 0;
      _dragDir = 0;
    });
    widget.onCardChanged?.call(_index);
  }

  Future<void> _springBack() async {
    await _animateDragTo(0);
    if (!mounted) return;
    setState(() {
      _dragDy = 0;
      _dragDir = 0;
    });
  }

  void _onDragStart(DragStartDetails details) {
    if (widget.words.isEmpty) return;
    _dragging = true;
    _dragDy = 0;
    _dragDir = 0;
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (!_dragging) return;
    setState(() {
      _dragDy += details.delta.dy;
      if (_dragDy < 0 && _index < widget.words.length) {
        _dragDir = -1;
      } else if (_dragDy > 0 && _index == 0) {
        _dragDir = 0; // rubber band, handled specially below
      } else if (_dragDy > 0 && _index > 0) {
        _dragDir = 1;
      }
    });
  }

  void _onDragEnd(DragEndDetails details) {
    if (!_dragging) return;
    _dragging = false;
    final velocity = details.primaryVelocity ?? 0;
    if (_dragDir == -1) {
      final commit = -_dragDy > _nextThresholdPx || -velocity > _velocityThreshold;
      if (commit) {
        _commitNext();
      } else {
        _springBack();
      }
    } else if (_dragDir == 1) {
      final commit = _dragDy > _prevThresholdPx || velocity > _velocityThreshold;
      if (commit) {
        _commitPrev();
      } else {
        _springBack();
      }
    } else {
      _springBack();
    }
  }

  Future<void> _playAudio(WordDeckCard card) async {
    setState(() => _playingAudio = true);
    try {
      await ref.read(wordAudioServiceProvider).play(card.word, audioUrl: card.audioUrl);
    } finally {
      Future.delayed(const Duration(milliseconds: 600), () {
        if (mounted) setState(() => _playingAudio = false);
      });
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.arrowUp || event.logicalKey == LogicalKeyboardKey.space) {
      _commitNext();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      _commitPrev();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = math.min(constraints.maxWidth, 340.0);
        _deckHeight = math.min(500.0, MediaQuery.sizeOf(context).height * 0.64);
        return Focus(
          focusNode: _focusNode,
          onKeyEvent: _onKey,
          child: GestureDetector(
            onVerticalDragStart: _onDragStart,
            onVerticalDragUpdate: _onDragUpdate,
            onVerticalDragEnd: _onDragEnd,
            child: SizedBox(
              width: width,
              height: _deckHeight,
              child: _index >= widget.words.length
                  ? _buildDoneWithPeek(context, width)
                  : _buildCards(context, width),
            ),
          ),
        );
      },
    );
  }

  Widget _buildCards(BuildContext context, double width) {
    // Only the visible cards plus one buffer beyond the stack depth this
    // deck ever shows (§ performance — never build all of a long deck).
    final visibleCount = math.min(widget.words.length - _index, 5);
    final showIncomingPrev = _dragDir == 1 && _index > 0;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        for (var k = visibleCount - 1; k >= 0; k--) _positionedCard(context, width, k),
        if (showIncomingPrev) Positioned.fill(child: _incomingPrevCard(width, widget.words[_index - 1])),
      ],
    );
  }

  /// The done screen, plus — while the learner is mid-drag/mid-commit
  /// pulling the previous card back down over it — that last word card
  /// sliding in on top, exactly like any other backward transition (same
  /// [_incomingPrevCard] the normal in-deck case uses, not a second,
  /// divergent implementation of the same effect).
  Widget _buildDoneWithPeek(BuildContext context, double width) {
    final pulling = _dragDir == 1 && widget.words.isNotEmpty;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        _DoneScreen(onContinue: widget.onComplete),
        if (pulling) Positioned.fill(child: _incomingPrevCard(width, widget.words.last)),
      ],
    );
  }

  /// The previous card sliding in from above as the learner drags/commits
  /// backward — `t` is 0 at the start of the gesture/commit and 1 once
  /// fully arrived, driving translateY/scale/rotation/opacity together the
  /// same way the prototype's own "prev" transition does.
  Widget _incomingPrevCard(double width, WordDeckCard card) {
    final t = (_dragDy / _prevTravelPx).clamp(0.0, 1.0);
    return IgnorePointer(
      child: Transform.translate(
        offset: Offset(0, -_deckHeight * 1.15 * (1 - t)),
        child: Transform.scale(
          scale: 0.9 + t * 0.1,
          alignment: const Alignment(0, 0.8),
          child: Transform.rotate(
            angle: -3 * (1 - t) * math.pi / 180,
            alignment: const Alignment(0, 0.8),
            child: Opacity(
              opacity: t,
              child: _WordCardFace(card: card, width: width, imageUrl: _resolvedImage(card), playing: false, onPlayAudio: () {}),
            ),
          ),
        ),
      ),
    );
  }

  Widget _positionedCard(BuildContext context, double width, int k) {
    final card = widget.words[_index + k];
    final isFront = k == 0;

    double dy;
    double scale;
    double opacity;
    double rotationDeg = 0;

    if (isFront && _dragDir == -1) {
      // Following the finger upward toward "next".
      dy = _dragDy;
      rotationDeg = _dragDy * 0.012;
      final t = (-_dragDy / 160).clamp(0.0, 1.0);
      scale = 1 - t * 0.02;
      opacity = 1;
    } else if (isFront && _dragDir == 0 && _dragDy > 0 && _index == 0) {
      // First card, rubber-band resistance on an over-pull downward.
      dy = math.pow(_dragDy, 0.7).toDouble() * 2;
      scale = 1;
      opacity = 1;
    } else if (isFront && _dragDir == 1) {
      final t = (_dragDy / _prevTravelPx).clamp(0.0, 1.0);
      dy = -16 * t;
      scale = 1 - t * 0.05;
      opacity = 1;
    } else if (k == 1 && _dragDir == -1) {
      final t = (-_dragDy / 160).clamp(0.0, 1.0);
      dy = -16 + t * 16;
      scale = 0.95 + t * 0.05;
      opacity = 1;
    } else {
      final depth = math.min(k, 3);
      dy = -depth * 16.0;
      scale = 1 - depth * 0.05;
      opacity = k > 3 ? 0.0 : 1 - depth * 0.18;
    }

    return Positioned.fill(
      child: IgnorePointer(
        ignoring: !isFront,
        child: Transform.translate(
          offset: Offset(0, dy),
          transformHitTests: isFront,
          child: Transform.scale(
            scale: scale,
            alignment: const Alignment(0, 0.8),
            child: Transform.rotate(
              angle: rotationDeg * math.pi / 180,
              alignment: const Alignment(0, 0.8),
              child: Opacity(
                opacity: opacity,
                child: _WordCardFace(
                  card: card,
                  width: width,
                  imageUrl: _resolvedImage(card),
                  playing: isFront && _playingAudio,
                  onPlayAudio: () => _playAudio(card),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _WordCardFace extends StatelessWidget {
  const _WordCardFace({required this.card, required this.width, required this.imageUrl, required this.playing, required this.onPlayAudio});

  final WordDeckCard card;
  final double width;
  final String? imageUrl;
  final bool playing;
  final VoidCallback onPlayAudio;

  @override
  Widget build(BuildContext context) {
    final (a, b) = _sceneColors(card.id);
    return Container(
      decoration: BoxDecoration(
        color: _paper,
        borderRadius: BorderRadius.circular(26),
        boxShadow: const [BoxShadow(color: _shadow, blurRadius: 46, offset: Offset(0, 26), spreadRadius: -30)],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Expanded(
            flex: 58,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [a, b])),
                    // Disk-backed, like the avatar already is: Image.network
                    // only ever cached in memory, so every app restart —
                    // and every return to a lesson — re-downloaded the photo
                    // in full. The prefetch before the lesson opens writes
                    // into this same cache, so by the time a card is shown
                    // its file is normally already local
                    // (§ pre-download word photos, 2026-09-02).
                    child: imageUrl != null
                        ? CachedNetworkImage(
                            imageUrl: imageUrl!,
                            fit: BoxFit.cover,
                            // The card's own gradient shows through while a
                            // photo loads, so there is deliberately no
                            // spinner: a card that is about to be filled
                            // should not flash a loading state for the split
                            // second the disk read takes.
                            placeholder: (_, _) => const SizedBox.shrink(),
                            errorWidget: (_, _, _) => const SizedBox.shrink(),
                          )
                        : null,
                  ),
                ),
                // Bottom 44% fades to white so the text block below never
                // fights the image for contrast.
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: 200,
                  child: FractionallySizedBox(
                    heightFactor: 0.44 / 0.58,
                    alignment: Alignment.bottomCenter,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [_paper.withValues(alpha: 0.92), _paper.withValues(alpha: 0)],
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  right: 20,
                  bottom: -28,
                  child: Semantics(
                    label: 'Слушать: ${card.word}',
                    button: true,
                    child: GestureDetector(
                      onTap: onPlayAudio,
                      child: Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: playing ? null : _ink,
                          gradient: playing ? const LinearGradient(colors: [_blue, _rose]) : null,
                          boxShadow: [BoxShadow(color: _shadow.withValues(alpha: 0.4), blurRadius: 22, offset: const Offset(0, 12))],
                        ),
                        child: const Icon(Icons.volume_up, color: Colors.white, size: 22),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 42,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 22, 24, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  Text(
                    card.word,
                    style: const TextStyle(fontFamily: 'serif', fontWeight: FontWeight.w500, fontSize: 36, color: _ink, height: 1.05),
                  ),
                  if (card.ipa != null && card.ipa!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(card.ipa!, style: const TextStyle(fontSize: 15, color: _mute)),
                  ],
                  const SizedBox(height: 8),
                  Text(card.translation, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w500, color: _ink)),
                  if (card.example != null && card.example!.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Container(padding: const EdgeInsets.only(top: 12), decoration: const BoxDecoration(border: Border(top: BorderSide(color: _line)))),
                    Flexible(
                      child: Text.rich(
                        _exampleSpan(card),
                        style: const TextStyle(fontSize: 14, height: 1.5, color: _mute),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  TextSpan _exampleSpan(WordDeckCard card) {
    final example = card.example!;
    final focus = card.exampleFocus;
    if (focus == null || focus.isEmpty) return TextSpan(text: example);
    final i = example.indexOf(focus);
    if (i < 0) return TextSpan(text: example);
    return TextSpan(children: [
      TextSpan(text: example.substring(0, i)),
      TextSpan(text: focus, style: const TextStyle(fontWeight: FontWeight.w500, color: _ink)),
      TextSpan(text: example.substring(i + focus.length)),
    ]);
  }
}

class _DoneScreen extends StatelessWidget {
  const _DoneScreen({required this.onContinue});
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Image.asset('assets/images/word_deck_done.png', width: 150, height: 150),
          const SizedBox(height: 18),
          const Text('Все слова пройдены', style: TextStyle(fontSize: 16, color: _mute)),
          const SizedBox(height: 18),
          FilledButton(
            onPressed: onContinue,
            style: FilledButton.styleFrom(backgroundColor: _ink, padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14), shape: const StadiumBorder()),
            child: const Text('Продолжить урок'),
          ),
          const SizedBox(height: 10),
          const Text('Или смахните вниз, чтобы повторить слова', style: TextStyle(fontSize: 13, color: _mute)),
        ],
      ),
    );
  }
}

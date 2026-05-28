import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spotted/src/isar/local_event/local_event_service.dart';
import '../api/firebase_api.dart';
import '../enums/enums.dart';
import '../models/event_model.dart';
import '../models/user_model.dart';
import '../providers/user_provider.dart';
import '../routers/router.dart';
import '../services/recommendations/event_recommendation_service.dart';
import '../services/posthog_service.dart';
import '../utils/constants.dart';
import '../utils/swipe_tutorial_overlay.dart';
import '../utils/utils.dart';
import '../widgets/custom_swipe_card.dart';
import '../utils/swipe_cards_with_animation.dart';

import '../../shell.dart';
import 'archive_grid_page.dart';

/*──────────────────────────────────────────────────────────────
 *                        HOME PAGE
 *──────────────────────────────────────────────────────────────*/

//Constants
// Numero di attività caricate per ogni fetch
const int kEventsNumberPerFetch = 5;
// Ritardo minimo per mostrare il loader
const Duration kMinLoadingDuration = Duration(milliseconds: 500);

//Provider per il tutorial
final tutorialActiveProvider = StateProvider<bool>((ref) => false);

class HomePage extends ConsumerStatefulWidget {
  const HomePage({Key? key}) : super(key: key);

  @override
  ConsumerState<ConsumerStatefulWidget> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage>
    with AutomaticKeepAliveClientMixin, SingleTickerProviderStateMixin {
  bool _isLoading = true;
  List<EventModel> _events = [];
  List<SwipeItem> _swipeItems = [];
  QueryDocumentSnapshot? _lastDoc; // ⬅️ cursore per la paginazione
  bool _canShowEmptyState = false;
  final String _recommendationSessionId =
      DateTime.now().microsecondsSinceEpoch.toString();
  final Map<String, RankedEvent> _rankingByEventId = {};

  @override
  bool get wantKeepAlive => true; // mantiene lo State vivo
  late Future<void> _initFuture;

  @override
  void initState() {
    super.initState();
    debugPrint('DEBUG: HomePage initState called');
    _initFuture = _initEvents();
    TutorialPrefs.hasSeen().then((seen) async {
      await _initFuture;
      if (!seen && _swipeItems.isNotEmpty) {
        await Future.delayed(const Duration(milliseconds: 1000));
        ref.read(tutorialActiveProvider.notifier).state = true;
      }
    });
  }

  @override
  void dispose() {
    super.dispose();
  }

  /*──────────────────────────────*
   *  ➜  FETCH INIZIALE (prima pagina)
   *──────────────────────────────*/
  Future<void> _initEvents() async {
    if (!mounted) return;
    debugPrint("DEBUG: Starting initial events fetch");
    final startTime = DateTime.now();

    setState(() => _isLoading = true);

    // Get user with retry logic
    UserModel? user;
    int retryCount = 0;
    while (user == null && retryCount < 10 && mounted) {
      try {
        user = ref.read(userProv).user;
        debugPrint(
          "DEBUG: Attempt ${retryCount + 1} to get user: ${user?.uid ?? 'null'}",
        );
        if (user == null) {
          await Future.delayed(const Duration(milliseconds: 500));
          if (!mounted) return;
          await ref.read(userProv).refresh();
          retryCount++;
        }
      } catch (e) {
        debugPrint("DEBUG: Error getting user: $e");
        if (!mounted) return;
        retryCount++;
      }
    }

    if (!mounted) return;

    if (user == null) {
      debugPrint("DEBUG: Failed to obtain user after $retryCount attempts");
      // Respect minimum loading time
      final elapsed = DateTime.now().difference(startTime);
      if (elapsed < kMinLoadingDuration) {
        await Future.delayed(kMinLoadingDuration - elapsed);
      }
      if (!mounted) return;
      setState(() {
        _canShowEmptyState = true;
        _isLoading = false;
      });
      return;
    }

    debugPrint("DEBUG: Successfully got user: ${user.uid}");
    final String uid = user.uid!;
    final universities = Utils(
      context,
    ).getVisibleEventsUniversities(user.university ?? University.unimi);

    debugPrint("DEBUG: Fetching events for universities: $universities");
    try {
      final (initialEvents, lastDoc) = await FirebaseApi.fetchEventsForFeed(
        uid: uid,
        universities: universities,
        limit: kEventsNumberPerFetch,
        lastDoc: null,
      );
      debugPrint("DEBUG: Fetched ${initialEvents.length} initial events");
      final rankedEvents = _rankEventsForUser(initialEvents, user);
      final rankedInitialEvents =
          rankedEvents.map((rankedEvent) => rankedEvent.event).toList();
      unawaited(
        EventRecommendationService.logImpressions(
          userId: uid,
          rankedEvents: rankedEvents,
          sessionId: _recommendationSessionId,
        ),
      );

      // Respect minimum loading time
      final elapsed = DateTime.now().difference(startTime);
      if (elapsed < kMinLoadingDuration) {
        await Future.delayed(kMinLoadingDuration - elapsed);
      }

      if (!mounted) return;
      setState(() {
        _events = rankedInitialEvents;
        _lastDoc = lastDoc;
        _swipeItems = _events.map(_buildSwipeItem).toList();
        _canShowEmptyState = _swipeItems.isEmpty;
        _isLoading = false;
        debugPrint(
          "DEBUG: State updated - Events: ${_events.length}, SwipeItems: ${_swipeItems.length}",
        );
      });
    } catch (e) {
      debugPrint("DEBUG: Error fetching events: $e");
      if (!mounted) return;
      setState(() {
        _canShowEmptyState = true;
        _isLoading = false;
      });
    }
  }

  /*──────────────────────────────*
   *  ➜  FETCH SUCCESSIVI (quando lo stack finisce)
   *──────────────────────────────*/
  Future<void> _loadMoreEvents() async {
    debugPrint("DEBUG: Loading more events - Current count: ${_events.length}");
    if (_lastDoc == null) {
      setState(() => _canShowEmptyState = true);
      return;
    }
    //commit tattico
    final startTime = DateTime.now();
    setState(() => _isLoading = true);

    final user = ref.read(userProv).user;
    if (user == null) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _canShowEmptyState = true;
      });
      return;
    }

    final uid = user.uid ?? 'error';
    final universities = Utils(
      context,
    ).getVisibleEventsUniversities(user.university ?? University.unimi);

    final (moreEvents, newLastDoc) = await FirebaseApi.fetchEventsForFeed(
      uid: uid,
      universities: universities,
      limit: kEventsNumberPerFetch,
      lastDoc: _lastDoc,
    );
    debugPrint("DEBUG: Fetched ${moreEvents.length} additional events");
    final rankedEvents = _rankEventsForUser(moreEvents, user);
    final rankedMoreEvents =
        rankedEvents.map((rankedEvent) => rankedEvent.event).toList();
    unawaited(
      EventRecommendationService.logImpressions(
        userId: uid,
        rankedEvents: rankedEvents,
        sessionId: _recommendationSessionId,
      ),
    );

    // Rispettiamo il minimo loading time
    final elapsed = DateTime.now().difference(startTime);
    if (elapsed < kMinLoadingDuration) {
      await Future.delayed(kMinLoadingDuration - elapsed);
    }

    if (!mounted) return;
    setState(() {
      _events.addAll(rankedMoreEvents);
      _lastDoc = newLastDoc;
      // ricreo lo stack SOLO coi nuovi eventi
      _swipeItems = rankedMoreEvents.map(_buildSwipeItem).toList();
      _isLoading = false;
      if (rankedMoreEvents.isEmpty) {
        _canShowEmptyState = true;
      }
      debugPrint(
        "DEBUG: Updated state - Total events: ${_events.length}, New stack size: ${_swipeItems.length}",
      );
    });
  }

  List<RankedEvent> _rankEventsForUser(
    List<EventModel> events,
    UserModel user,
  ) {
    final rankedEvents = EventRecommendationService.rankEvents(
      events: events,
      user: user,
    );

    _rankingByEventId.addAll({
      for (final rankedEvent in rankedEvents)
        if (rankedEvent.event.id != null) rankedEvent.event.id!: rankedEvent,
    });

    return rankedEvents;
  }

  /*──────────────────────────────*
   *  ➜  COSTRUZIONE DELLA CARD
   *──────────────────────────────*/
  SwipeItem _buildSwipeItem(EventModel event) {
    final user = ref.read(userProv).user;
    final userId = user?.uid ?? 'error';
    final rankedEvent = _rankingByEventId[event.id];

    return SwipeItem(
      //key: UniqueKey(),
      content: CustomSwipeCard(
        key: UniqueKey(), // evita conflitti di key interni a Flutter
        event: event,
        isParticipantButtonActive: false,
        onJoinAction: null,
        onLeaveAction: null,
      ),

      likeAction: () async {
        final didParticipate = await Utils(context).handleEventParticipation(
          onJoinAction: null,
          context: context,
          ref: ref,
          event: event,
          showConfirmation: false,
        );

        if (didParticipate) {
          unawaited(
            EventRecommendationService.logInteraction(
              user: user,
              event: event,
              action: event.type == EventType.requestToJoin.toString()
                  ? RecommendationAction.requestToJoin
                  : RecommendationAction.join,
              sessionId: _recommendationSessionId,
              score: rankedEvent?.score,
            ),
          );
        }

        // [PostHog] - Track swipe right
        PostHogService().trackSwipeRight(event);
      },
      superlikeAction: () async {
        print("DEBUG: MAYBE ACTION CALLED");

        // Salva in locale (su isar) l'evento con action="maybe"
        await LocalEventService().onSwipeUpEvent(event, userId, ref);

        unawaited(
          EventRecommendationService.logInteraction(
            user: user,
            event: event,
            action: RecommendationAction.maybe,
            sessionId: _recommendationSessionId,
            score: rankedEvent?.score,
          ),
        );
      },
      nopeAction: () async {
        print("DEBUG: PASS ACTION CALLED");

        // Salva in locale (su isar) l'evento con action="pass"
        await LocalEventService().savePassEvent(event, userId, ref);

        unawaited(
          EventRecommendationService.logInteraction(
            user: user,
            event: event,
            action: RecommendationAction.pass,
            sessionId: _recommendationSessionId,
            score: rankedEvent?.score,
          ),
        );

        // PostHog - Track swipe left
        PostHogService().trackSwipeLeft(event);
      },
    );
  }

  /*───────────────────────────*
   *  ➜  RESTART ACTIVITIES     *
   *───────────────────────────*/
  Future<void> _restartEvents() async {
    debugPrint("DEBUG: Restarting events - clearing current state");
    setState(() {
      _events.clear();
      _swipeItems.clear();
      _lastDoc = null;
      _canShowEmptyState = false;
    });
    await _initEvents();

    // PostHog track ReloadActivities Pressed from Home Page
    PostHogService().trackHomePageReloadActivitiesPressed();
  }

  /*───────────────────────────*
   *         EMPTY STATE        *
   *───────────────────────────*/
  Widget _buildEmptyState() {
    final double spacing =
        MediaQuery.of(context).size.width * kEdgeInsetsSpacing;

    // Tracciamento analytics
    PostHogService().trackHomePageEmptyState();

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: spacing),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: SizedBox()),

          // Titolo
          Text(
            "You've seen it all.",
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.normal),
          ),
          SizedBox(height: spacing / 2),
          Text(
            'And now?',
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.headlineLarge?.copyWith(fontWeight: FontWeight.bold),
          ),

          Expanded(child: SizedBox()),

          // 1) CARD centrale "Create your New Activity"
          GestureDetector(
            onTap: () {
              // naviga a Create Event
              final shellState = context.findAncestorStateOfType<ShellState>();
              if (shellState != null) shellState.onPageSelected(1);
              PostHogService().trackHomePageCreateActivitiesPressed();
            },
            child: ClipRRect(
              borderRadius: BorderRadius.circular(spacing),
              child: Image.asset(
                'assets/home_page/button_create_activity.png',
                width: double.infinity,
                fit: BoxFit.cover,
              ),
            ),
          ),

          SizedBox(height: spacing),

          // 2) Row con le due card in basso
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    _restartEvents();
                    PostHogService().trackHomePageReloadActivitiesPressed();
                  },
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(spacing),
                    child: Image.asset(
                      'assets/home_page/button_rewatch_activities.png',
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
              ),
              SizedBox(width: spacing),
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    PostHogService().trackHomePageRecentlyPassedPressed();
                    Navigator.of(context).pushNamed(
                      Paths.archiveGrid,
                      arguments: {'gridType': ArchiveGridType.recentViewedGrid},
                    );
                  },
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(spacing),
                    child: Image.asset(
                      'assets/home_page/button_recently_passed.png',
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: spacing),
        ],
      ),
    );
  }

  /*──────────────────────────────*
   *  ➜  UI
   *──────────────────────────────*/
  @override
  Widget build(BuildContext context) {
    super.build(context); // per AutomaticKeepAliveClientMixin
    final tutorialActive = ref.watch(tutorialActiveProvider);
    if (_isLoading) {
      debugPrint("DEBUG: Rendering loading state");
      return const Center(child: CircularProgressIndicator());
    }

    debugPrint(
      "DEBUG: Rendering SwipeCardsWithAnimation - Stack size: ${_swipeItems.length}",
    );
    final swipeCards = SwipeCardsWithAnimation(
      matchEngine: MatchEngine(swipeItems: _swipeItems),
      itemBuilder: (BuildContext context, int index) {
        return _swipeItems[index].content;
      },
      onStackFinished: _loadMoreEvents,
      itemChanged: (SwipeItem item, int index) {
        print("Item changed $index");
      },
      upSwipeAllowed: true,
      fillSpace: true,
    );
    return SwipeTutorialOverlay(
      active: tutorialActive,
      child: Stack(
        children: [if (_canShowEmptyState) _buildEmptyState(), swipeCards],
      ),
      onCompleted: () async {
        // Disattiva tutorial e segna come visto
        ref.read(tutorialActiveProvider.notifier).state = false;
        await TutorialPrefs.setSeen();
        // facoltativo: trigger di rebuild o callback aggiuntive
      },
    );
  }
}

import 'dart:math';

import 'package:dart_rl/dart_rl.dart';
import 'package:flutter/foundation.dart';
import 'package:spotted/src/enums/enums.dart';
import 'package:spotted/src/models/event_model.dart';
import 'package:spotted/src/models/user_model.dart';

enum RecommendationAction {
  impression,
  join,
  requestToJoin,
  maybe,
  pass,
  leave,
  report,
  chatActivity,
}

class RankedEvent {
  const RankedEvent({
    required this.event,
    required this.score,
    required this.exploitationScore,
    required this.explorationBonus,
    required this.features,
  });

  final EventModel event;
  final double score;
  final double exploitationScore;
  final double explorationBonus;
  final Map<String, double> features;
}

class EventRecommendationService {
  EventRecommendationService._();

  static const String interactionCollection =
      'event_recommendation_interactions';

  static const Map<String, double> _priorWeights = {
    'bias': 0.05,
    'same_university': 0.35,
    'free_to_join': 0.20,
    'request_to_join': 0.08,
    'starts_soon': 0.22,
    'evening_event': 0.08,
    'weekend_event': 0.10,
    'attendee_ratio': 0.18,
    'waiting_ratio': 0.12,
    'has_image': 0.06,
    'fresh_event': 0.07,
    'category_profile_match': 0.16,
    'report_penalty': -0.40,
  };

  static const Map<String, double> _posteriorStd = {
    'bias': 0.02,
    'same_university': 0.08,
    'free_to_join': 0.06,
    'request_to_join': 0.05,
    'starts_soon': 0.07,
    'evening_event': 0.05,
    'weekend_event': 0.05,
    'attendee_ratio': 0.08,
    'waiting_ratio': 0.07,
    'has_image': 0.03,
    'fresh_event': 0.05,
    'category_profile_match': 0.08,
    'report_penalty': 0.10,
  };

  static List<RankedEvent> rankEvents({
    required List<EventModel> events,
    required UserModel user,
  }) {
    final bandit = LinearThompsonSampling<EventModel>(
      weights: _priorWeights,
      standardDeviations: _posteriorStd,
    );
    final arms = events
        .map(
          (event) => ContextualBanditArm(
            item: event,
            features: buildFeatures(user: user, event: event),
          ),
        )
        .toList();

    return bandit.rank(arms).map((ranking) {
      return RankedEvent(
        event: ranking.item,
        score: ranking.score,
        exploitationScore: ranking.expectedReward,
        explorationBonus: ranking.explorationBonus,
        features: ranking.features,
      );
    }).toList();
  }

  static Map<String, double> buildFeatures({
    required UserModel user,
    required EventModel event,
  }) {
    final eventDate = event.eventAt?.toDate();
    final now = DateTime.now();
    final hoursUntilEvent = eventDate == null
        ? 168.0
        : eventDate.difference(now).inMinutes / Duration.minutesPerHour;
    final createdAt = event.createdAt?.toDate();
    final attendeeCount = event.attendees?['uids']?.length ?? 0;
    final waitingCount = event.waitings?['uids']?.length ?? 0;
    final maxAttendees = event.maxAttendees?.toDouble();
    final capacity = maxAttendees == null || maxAttendees <= 1
        ? max<double>((attendeeCount + waitingCount).toDouble() + 1.0, 1.0)
        : max<double>(maxAttendees - 1.0, 1.0);

    return {
      'bias': 1.0,
      'same_university': event.university == user.university ? 1.0 : 0.0,
      'free_to_join': event.type == EventType.freeToJoin.toString() ? 1.0 : 0.0,
      'request_to_join':
          event.type == EventType.requestToJoin.toString() ? 1.0 : 0.0,
      'starts_soon': _clamp01(1.0 - (hoursUntilEvent / 168.0)),
      'evening_event': eventDate != null && eventDate.hour >= 18 ? 1.0 : 0.0,
      'weekend_event': eventDate != null &&
              (eventDate.weekday == DateTime.saturday ||
                  eventDate.weekday == DateTime.sunday)
          ? 1.0
          : 0.0,
      'attendee_ratio': _clamp01(attendeeCount / capacity),
      'waiting_ratio': _clamp01(waitingCount / capacity),
      'has_image': (event.images?.isNotEmpty ?? false) ? 1.0 : 0.0,
      'fresh_event': createdAt == null
          ? 0.0
          : _clamp01(1.0 - (now.difference(createdAt).inHours / 168.0)),
      'category_profile_match': _categoryProfileMatch(user, event),
      'report_penalty': _clamp01((event.reportCount ?? 0) / 5.0),
    };
  }

  static Future<void> logImpressions({
    required String userId,
    required List<RankedEvent> rankedEvents,
    required String sessionId,
  }) async {
    if (rankedEvents.isEmpty || userId == 'error') return;

    debugPrint(
      '[EventRecommendationService] skipped remote impression logging; '
      'synthetic simulations are used for evaluation.',
    );
  }

  static Future<void> logInteraction({
    required UserModel? user,
    required EventModel event,
    required RecommendationAction action,
    required String sessionId,
    int? rank,
    double? score,
  }) async {
    if (user?.uid == null || user!.uid == 'error') return;

    debugPrint(
      '[EventRecommendationService] skipped remote action logging '
      '(${action.name}); synthetic simulations are used for evaluation.',
    );
  }

  static double rewardForAction(RecommendationAction action) {
    switch (action) {
      case RecommendationAction.impression:
        return 0.0;
      case RecommendationAction.join:
        return 1.0;
      case RecommendationAction.requestToJoin:
        return 0.7;
      case RecommendationAction.maybe:
        return 0.3;
      case RecommendationAction.pass:
        return -0.1;
      case RecommendationAction.leave:
        return -0.6;
      case RecommendationAction.report:
        return -1.0;
      case RecommendationAction.chatActivity:
        return 0.2;
    }
  }

  static double _clamp01(double value) => value.clamp(0.0, 1.0).toDouble();

  static double _categoryProfileMatch(UserModel user, EventModel event) {
    final category = event.category?.toLowerCase().trim();
    if (category == null || category.isEmpty) return 0.0;

    final profileText = [
      user.studyProgram,
      user.studentType,
      user.nationality,
    ].whereType<String>().join(' ').toLowerCase();

    if (profileText.isEmpty) return 0.0;

    final categoryTokens = category
        .split(RegExp(r'[_\s-]+'))
        .where((token) => token.length > 2)
        .toList();

    if (categoryTokens.isEmpty) return 0.0;

    final matches =
        categoryTokens.where((token) => profileText.contains(token)).length;
    return _clamp01(matches / categoryTokens.length);
  }
}

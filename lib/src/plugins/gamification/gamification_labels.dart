import 'package:discourse_native/discourse_plugin_contracts.dart'
    show DCalendarDate;
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

import 'gamification_models.dart';

String gamePeriodLabel(BuildContext context, GamificationPeriod period) =>
    switch (period) {
      GamificationPeriod.allTime => context.l10n.gamificationAllTime,
      GamificationPeriod.yearly => context.l10n.gamificationYearly,
      GamificationPeriod.quarterly => context.l10n.gamificationQuarterly,
      GamificationPeriod.monthly => context.l10n.gamificationMonthly,
      GamificationPeriod.weekly => context.l10n.gamificationWeekly,
      GamificationPeriod.daily => context.l10n.gamificationDaily,
    };
String gameRuleLabel(BuildContext context, GamificationRule rule) =>
    switch (rule) {
      GamificationRule.likeGiven => context.l10n.gamificationLikeGiven,
      GamificationRule.likeReceived => context.l10n.gamificationLikeReceived,
      GamificationRule.solution => context.l10n.gamificationSolution,
      GamificationRule.userInvited => context.l10n.gamificationUserInvited,
      GamificationRule.timeRead => context.l10n.gamificationTimeRead,
      GamificationRule.postRead => context.l10n.gamificationPostRead,
      GamificationRule.topicCreated => context.l10n.gamificationTopicCreated,
      GamificationRule.postCreated => context.l10n.gamificationPostCreated,
      GamificationRule.flagCreated => context.l10n.gamificationFlagCreated,
      GamificationRule.dayVisited => context.l10n.gamificationDayVisited,
      GamificationRule.reactionReceived =>
        context.l10n.gamificationReactionReceived,
      GamificationRule.reactionGiven => context.l10n.gamificationReactionGiven,
      GamificationRule.chatReactionReceived =>
        context.l10n.gamificationChatReactionReceived,
      GamificationRule.chatReactionGiven =>
        context.l10n.gamificationChatReactionGiven,
      GamificationRule.chatMessageCreated =>
        context.l10n.gamificationChatMessageCreated,
    };

String gameNumber(BuildContext context, int value) =>
    NumberFormat.decimalPattern(context.l10n.localeName).format(value);
String gameDateLabel(BuildContext context, DCalendarDate date) =>
    DateFormat.yMMMd(context.l10n.localeName).format(date.dateTimeUtc);

String? gameRuleHelp(BuildContext context, GamificationRule rule) =>
    switch (rule) {
      GamificationRule.timeRead => context.l10n.gamificationReadHourHelp,
      GamificationRule.postRead => context.l10n.gamificationReadPostsHelp,
      GamificationRule.flagCreated =>
        context.l10n.gamificationAcceptedFlagsHelp,
      _ => null,
    };

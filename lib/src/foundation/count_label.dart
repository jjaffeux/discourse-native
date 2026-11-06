import 'package:discourse_native/l10n/strings.dart';
import 'package:intl/intl.dart';

/// Typed nouns keep English words out of plural selection at call sites.
enum CountNoun {
  badge,
  reply,
  person,
  click,
  like,
  member,
  topic,
  post,
  view,
  message,
  reaction,
  category,
  entry,
  day,
  tag,
  second,
  repost,
  unreadNotification,
  membershipRequest,
  thread,
  link,
  user,
  image,
  draft,
  recipient,
  vote,
  voter,
  group,
  minute,
  hour,
  month,
  year,
}

// A row writes several counts as it builds; a format is built once per locale.
final _integerFormats = <String, NumberFormat>{};

/// A complete localized count, optionally using an already formatted number.
String countLabel(int count, CountNoun noun, {String? number}) {
  final l10n = appL10n;
  final written =
      number ??
      _integerFormats
          .putIfAbsent(
            l10n.localeName,
            () => NumberFormat('0', l10n.localeName),
          )
          .format(count);
  return switch (noun) {
    CountNoun.badge => l10n.countBadge(count, written),
    CountNoun.reply => l10n.countReply(count, written),
    CountNoun.person => l10n.countPerson(count, written),
    CountNoun.click => l10n.countClick(count, written),
    CountNoun.like => l10n.countLike(count, written),
    CountNoun.member => l10n.countMember(count, written),
    CountNoun.topic => l10n.countTopic(count, written),
    CountNoun.post => l10n.countPost(count, written),
    CountNoun.view => l10n.countView(count, written),
    CountNoun.message => l10n.countMessage(count, written),
    CountNoun.reaction => l10n.countReaction(count, written),
    CountNoun.category => l10n.countCategory(count, written),
    CountNoun.entry => l10n.countEntry(count, written),
    CountNoun.day => l10n.countDay(count, written),
    CountNoun.tag => l10n.countTag(count, written),
    CountNoun.second => l10n.countSecond(count, written),
    CountNoun.repost => l10n.countRepost(count, written),
    CountNoun.unreadNotification => l10n.countUnreadNotification(
      count,
      written,
    ),
    CountNoun.membershipRequest => l10n.countMembershipRequest(count, written),
    CountNoun.thread => l10n.countThread(count, written),
    CountNoun.link => l10n.countLink(count, written),
    CountNoun.user => l10n.countUser(count, written),
    CountNoun.image => l10n.countImage(count, written),
    CountNoun.draft => l10n.countDraft(count, written),
    CountNoun.recipient => l10n.countRecipient(count, written),
    CountNoun.vote => l10n.countVote(count, written),
    CountNoun.voter => l10n.countVoter(count, written),
    CountNoun.group => l10n.countGroup(count, written),
    CountNoun.minute => l10n.countMinute(count, written),
    CountNoun.hour => l10n.countHour(count, written),
    CountNoun.month => l10n.countMonth(count, written),
    CountNoun.year => l10n.countYear(count, written),
  };
}

/// Localized noun for a number displayed in a separate visual element.
String countNoun(int count, CountNoun noun) => switch (noun) {
  CountNoun.badge => appL10n.nounBadge(count),
  CountNoun.reply => appL10n.nounReply(count),
  CountNoun.person => appL10n.nounPerson(count),
  CountNoun.click => appL10n.nounClick(count),
  CountNoun.like => appL10n.nounLike(count),
  CountNoun.member => appL10n.nounMember(count),
  CountNoun.topic => appL10n.nounTopic(count),
  CountNoun.post => appL10n.nounPost(count),
  CountNoun.view => appL10n.nounView(count),
  CountNoun.message => appL10n.nounMessage(count),
  CountNoun.reaction => appL10n.nounReaction(count),
  CountNoun.category => appL10n.nounCategory(count),
  CountNoun.entry => appL10n.nounEntry(count),
  CountNoun.day => appL10n.nounDay(count),
  CountNoun.tag => appL10n.nounTag(count),
  CountNoun.second => appL10n.nounSecond(count),
  CountNoun.repost => appL10n.nounRepost(count),
  CountNoun.unreadNotification => appL10n.nounUnreadNotification(count),
  CountNoun.membershipRequest => appL10n.nounMembershipRequest(count),
  CountNoun.thread => appL10n.nounThread(count),
  CountNoun.link => appL10n.nounLink(count),
  CountNoun.user => appL10n.nounUser(count),
  CountNoun.image => appL10n.nounImage(count),
  CountNoun.draft => appL10n.nounDraft(count),
  CountNoun.recipient => appL10n.nounRecipient(count),
  CountNoun.vote => appL10n.nounVote(count),
  CountNoun.voter => appL10n.nounVoter(count),
  CountNoun.group => appL10n.nounGroup(count),
  CountNoun.minute => appL10n.nounMinute(count),
  CountNoun.hour => appL10n.nounHour(count),
  CountNoun.month => appL10n.nounMonth(count),
  CountNoun.year => appL10n.nounYear(count),
};

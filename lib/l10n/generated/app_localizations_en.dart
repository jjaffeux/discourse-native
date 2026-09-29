// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get primaryNavigation => 'Primary navigation';

  @override
  String get commands => 'Commands';

  @override
  String get typeACommandOrSearch => 'Type a command or search...';

  @override
  String get searchCommands => 'Search commands';

  @override
  String get commandResults => 'Command results';

  @override
  String get loading => 'Loading…';

  @override
  String get commandPalette => 'Command Palette';

  @override
  String get searchForACommandToRun => 'Search for a command to run...';

  @override
  String get pullToRefresh => 'Pull to refresh';

  @override
  String get releaseToRefresh => 'Release to refresh';

  @override
  String get refreshing => 'Refreshing';

  @override
  String get refresh => 'Refresh';

  @override
  String get loadingDbutton => 'Loading';

  @override
  String get menuBar => 'Menu bar';

  @override
  String get resizePanel => 'Resize panel';

  @override
  String get submit => 'Submit';

  @override
  String get questionnaireProgress => 'Questionnaire progress';

  @override
  String questionOf(String valueCurrent, String valueTotal) {
    return 'Question $valueCurrent of $valueTotal';
  }

  @override
  String get reset => 'Reset';

  @override
  String get previous => 'Previous';

  @override
  String get skip => 'Skip';

  @override
  String get next => 'Next';

  @override
  String get select => 'Select';

  @override
  String get selectAllRowsOnThisPage => 'Select all rows on this page';

  @override
  String get noResults => 'No results.';

  @override
  String resizeColumn(String columnLabel) {
    return 'Resize $columnLabel column';
  }

  @override
  String selectRow(String index) {
    return 'Select row $index';
  }

  @override
  String get sortAscending => 'Sort ascending';

  @override
  String get sortDescending => 'Sort descending';

  @override
  String get hideColumn => 'Hide column';

  @override
  String columnOptions(String title) {
    return '$title column options';
  }

  @override
  String sortedAscending(String title) {
    return '$title, sorted ascending';
  }

  @override
  String sortedDescending(String title) {
    return '$title, sorted descending';
  }

  @override
  String notSorted(String title) {
    return '$title, not sorted';
  }

  @override
  String get columns => 'Columns';

  @override
  String get toggleColumns => 'Toggle columns';

  @override
  String get filter => 'Filter…';

  @override
  String get rowsPerPage => 'Rows per page';

  @override
  String get tablePagination => 'Table pagination';

  @override
  String pageOf(String statePage, String metricsPageCount) {
    return 'Page $statePage of $metricsPageCount';
  }

  @override
  String get recentlyUsed => 'Recently used';

  @override
  String get messageDefault => 'Default';

  @override
  String get hue => 'Hue';

  @override
  String get saturation => 'Saturation';

  @override
  String get brightness => 'Brightness';

  @override
  String get leftAndRightChangeHueUpAndDownChangeLightness =>
      'Left and right change hue. Up and down change lightness.';

  @override
  String get lighter => 'Lighter';

  @override
  String get darker => 'Darker';

  @override
  String get dismissDialog => 'Dismiss dialog';

  @override
  String get close => 'Close';

  @override
  String get options => 'Options';

  @override
  String get ctrl => 'Ctrl';

  @override
  String get control => 'Control';

  @override
  String get alt => 'Alt';

  @override
  String get option => 'Option';

  @override
  String get shift => 'Shift';

  @override
  String get meta => 'Meta';

  @override
  String get command => 'Command';

  @override
  String get enter => 'Enter';

  @override
  String get numpadEnter => 'Numpad Enter';

  @override
  String get esc => 'Esc';

  @override
  String get space => 'Space';

  @override
  String get tab => 'Tab';

  @override
  String get backspace => 'Backspace';

  @override
  String get delete => 'Delete';

  @override
  String get key => 'Key';

  @override
  String get escape => 'Escape';

  @override
  String get arrowUp => 'Arrow Up';

  @override
  String get arrowDown => 'Arrow Down';

  @override
  String get arrowLeft => 'Arrow Left';

  @override
  String get arrowRight => 'Arrow Right';

  @override
  String get questionMark => 'Question mark';

  @override
  String get pagination => 'Pagination';

  @override
  String pageCurrentPage(String page) {
    return 'Page $page, current page';
  }

  @override
  String goToPage(String page) {
    return 'Go to page $page';
  }

  @override
  String get goToPreviousPage => 'Go to previous page';

  @override
  String get goToNextPage => 'Go to next page';

  @override
  String get goToFirstPage => 'Go to first page';

  @override
  String get goToLastPage => 'Go to last page';

  @override
  String get morePages => 'More pages';

  @override
  String noPagesItemsPerPage(String pageSize) {
    return 'No pages, $pageSize items per page';
  }

  @override
  String pageOfItemsPerPage(String page, String pageCount, String pageSize) {
    return 'Page $page of $pageCount, $pageSize items per page';
  }

  @override
  String get alertDialog => 'Alert dialog';

  @override
  String get working => 'Working';

  @override
  String get sending => 'Sending';

  @override
  String get delivered => 'Delivered';

  @override
  String get read => 'Read';

  @override
  String get failedToSend => 'Failed to send';

  @override
  String get messageDeleted => 'Message deleted';

  @override
  String get copyCode => 'Copy code';

  @override
  String get copied => 'Copied';

  @override
  String get copyFailed => 'Copy failed';

  @override
  String get mermaidChart => 'Mermaid chart';

  @override
  String get collapseChartEditor => 'Collapse chart editor';

  @override
  String get expandChartEditor => 'Expand chart editor';

  @override
  String get mermaidSourceCode => 'Mermaid source code';

  @override
  String get selectAnOption => 'Select an option';

  @override
  String get selectOptions => 'Select options';

  @override
  String get scrollOptionsUp => 'Scroll options up';

  @override
  String get scrollOptionsDown => 'Scroll options down';

  @override
  String get chooseInbox => 'Choose inbox';

  @override
  String get searchInboxes => 'Search inboxes…';

  @override
  String get searchInboxesDmessageinboxmenu => 'Search inboxes';

  @override
  String get noInboxesFound => 'No inboxes found.';

  @override
  String get today => ', Today';

  @override
  String get todayDcalendarevents => 'Today';

  @override
  String get pickADate => 'Pick a date';

  @override
  String get selectDate => 'Select date';

  @override
  String get datePickerRange => 'Date Picker Range';

  @override
  String get june012025 => 'June 01, 2025';

  @override
  String get date => 'Date';

  @override
  String get enterAValidDate => 'Enter a valid date';

  @override
  String get time => 'Time';

  @override
  String get enterAValidTime => 'Enter a valid time';

  @override
  String get dismissDrawer => 'Dismiss drawer';

  @override
  String get openInBrowser => 'Open in browser';

  @override
  String get embedLoadingTimedOut => 'Embed loading timed out';

  @override
  String loadingDembed(String title) {
    return 'Loading $title';
  }

  @override
  String get couldNotLoadThisEmbed => 'Could not load this embed.';

  @override
  String get retry => 'Retry';

  @override
  String get dismissSheet => 'Dismiss sheet';

  @override
  String get sheetBackground => 'Sheet background';

  @override
  String slideOf(String index, String count) {
    return 'Slide $index of $count';
  }

  @override
  String get previousSlide => 'Previous slide';

  @override
  String get nextSlide => 'Next slide';

  @override
  String get chooseAnAnswerToContinue => 'Choose an answer to continue.';

  @override
  String get chooseAnAnswerOrSkipThisQuestion =>
      'Choose an answer or skip this question.';

  @override
  String get couldNotPlayThisAudio => 'Could not play this audio.';

  @override
  String get audioPosition => 'Audio position';

  @override
  String get pauseAudio => 'Pause audio';

  @override
  String get playAudio => 'Play audio';

  @override
  String get retryAudio => 'Retry audio';

  @override
  String get openAudio => 'Open audio';

  @override
  String get notifications => 'Notifications';

  @override
  String get closeToast => 'Close toast';

  @override
  String get closeNotification => 'Close notification';

  @override
  String get sidebar => 'Sidebar';

  @override
  String get toggleSidebar => 'Toggle Sidebar';

  @override
  String get codeEditor => 'Code editor';

  @override
  String get mermaidDiagram => 'Mermaid diagram';

  @override
  String get copySource => 'Copy source';

  @override
  String get theDiagramIsEmpty => 'The diagram is empty.';

  @override
  String get theDiagramExceedsThe50000CharacterLimit =>
      'The diagram exceeds the 50,000 character limit.';

  @override
  String get diagramRenderingTimedOut => 'Diagram rendering timed out.';

  @override
  String get diagramImageIsTooLarge => 'Diagram image is too large.';

  @override
  String get invalidMermaidSyntax => 'Invalid Mermaid syntax.';

  @override
  String get couldNotReadTheRenderedDiagram =>
      'Could not read the rendered diagram.';

  @override
  String get couldNotLoadTheDiagramRenderer =>
      'Could not load the diagram renderer.';

  @override
  String get couldNotStartTheDiagramRenderer =>
      'Could not start the diagram renderer.';

  @override
  String get mermaidSource => 'Mermaid source';

  @override
  String get couldnTRenderDiagram => 'Couldn\'t render diagram';

  @override
  String get renderingDiagram => 'Rendering diagram';

  @override
  String get viewSource => 'View source';

  @override
  String get expandDiagram => 'Expand diagram';

  @override
  String get couldNotDisplayTheDiagram => 'Could not display the diagram.';

  @override
  String get zoomOut => 'Zoom out';

  @override
  String get zoomIn => 'Zoom in';

  @override
  String get fit => 'Fit';

  @override
  String dragToMoveOrActivateForActions(String label) {
    return '$label. Drag to move or activate for actions.';
  }

  @override
  String get breadcrumb => 'Breadcrumb';

  @override
  String get chooseFile => 'Choose file';

  @override
  String get noFileChosen => 'No file chosen';

  @override
  String get couldNotChooseAFileTryAgain =>
      'Could not choose a file. Try again.';

  @override
  String get choosing => 'Choosing…';

  @override
  String get value => 'Value';

  @override
  String valueDslider(String i) {
    return 'Value $i';
  }

  @override
  String get calendar => 'Calendar';

  @override
  String get previousMonth => 'Previous month';

  @override
  String get nextMonth => 'Next month';

  @override
  String get chooseMonth => 'Choose month';

  @override
  String get chooseYear => 'Choose year';

  @override
  String get week => 'Week';

  @override
  String get booked => 'Booked';

  @override
  String get noData => 'No data';

  @override
  String get noCategorySelected => 'No category selected';

  @override
  String get useLeftAndRightArrowKeysToInspectValues =>
      'Use left and right arrow keys to inspect values';

  @override
  String get messages => 'Messages';

  @override
  String get scrollToEnd => 'Scroll to end';

  @override
  String get scrollToStart => 'Scroll to start';

  @override
  String get suggestions => 'Suggestions';

  @override
  String get clearSelection => 'Clear selection';

  @override
  String get closeSuggestions => 'Close suggestions';

  @override
  String get openSuggestions => 'Open suggestions';

  @override
  String get pressDeleteOrBackspaceToRemove =>
      'Press Delete or Backspace to remove';

  @override
  String remove(String rootLabelForValue) {
    return 'Remove $rootLabelForValue';
  }

  @override
  String get firing => 'Firing';

  @override
  String get silenced => 'Silenced';

  @override
  String get stale => 'Stale';

  @override
  String get history => 'History';

  @override
  String get openLink => 'Open Link';

  @override
  String get alerts => 'Alerts';

  @override
  String get expand => 'Expand';

  @override
  String get collapse => 'Collapse';

  @override
  String get openAlertmanager => 'Open Alertmanager';

  @override
  String get alert => 'Alert';

  @override
  String previouslySilencedOn(String formatAlertLastSuppressedAt) {
    return 'Previously silenced on $formatAlertLastSuppressedAt';
  }

  @override
  String get previouslySilenced => 'Previously silenced';

  @override
  String get quoteAlert => 'Quote Alert';

  @override
  String get unknownTime => 'Unknown time';

  @override
  String get thisChannelCanNoLongerBeChanged =>
      'This channel can no longer be changed.';

  @override
  String get onlyFollowedChannelsCanBeStarred =>
      'Only followed channels can be starred.';

  @override
  String get anotherChannelChangeIsStillFinishing =>
      'Another channel change is still finishing.';

  @override
  String get reconnectThisSiteToChangeTheChannel =>
      'Reconnect this site to change the channel.';

  @override
  String get chooseAChannelNotificationSettingToChange =>
      'Choose a channel notification setting to change.';

  @override
  String get onlyFollowedChannelsHaveNotificationSettings =>
      'Only followed channels have notification settings.';

  @override
  String get anotherNotificationChangeIsStillFinishing =>
      'Another notification change is still finishing.';

  @override
  String get reconnectThisSiteToChangeChannelNotifications =>
      'Reconnect this site to change channel notifications.';

  @override
  String get thisMemberListIsNoLongerAvailable =>
      'This member list is no longer available.';

  @override
  String get onlyFollowedChannelsShowTheirMembers =>
      'Only followed channels show their members.';

  @override
  String get reconnectThisSiteToSeeChannelMembers =>
      'Reconnect this site to see channel members.';

  @override
  String get couldnTLoadThisChannelSMembers =>
      'Couldn\'t load this channel\'s members.';

  @override
  String get theChannelDirectoryIsNoLongerAvailable =>
      'The channel directory is no longer available.';

  @override
  String get reconnectThisSiteToBrowseChatChannels =>
      'Reconnect this site to browse chat channels.';

  @override
  String get couldnTLoadChatChannels => 'Couldn\'t load chat channels.';

  @override
  String get thisChannelCannotBeEdited => 'This channel cannot be edited.';

  @override
  String get theChannelSlugMustBeBetween1And100Characters =>
      'The channel slug must be between 1 and 100 characters.';

  @override
  String get theChannelDescriptionCannotExceed280Characters =>
      'The channel description cannot exceed 280 characters.';

  @override
  String get reconnectThisSiteToEditTheChannel =>
      'Reconnect this site to edit the channel.';

  @override
  String get thisChannelSStatusCannotBeChanged =>
      'This channel’s status cannot be changed.';

  @override
  String get directMessagesCannotBeJoinedFromBrowseChannels =>
      'Direct messages cannot be joined from Browse Channels.';

  @override
  String get thisChannelCannotBeJoined => 'This channel cannot be joined.';

  @override
  String get couldNotLoadPinnedMessages => 'Could not load pinned messages.';

  @override
  String get thisMessageCanNoLongerBeFlagged =>
      'This message can no longer be flagged.';

  @override
  String get thisFlagReasonIsNoLongerAvailable =>
      'This flag reason is no longer available.';

  @override
  String yourMessageMustBeBetweenAndCharacters(
    String minimum,
    String postFlagTypeMaximumMessageLength,
  ) {
    return 'Your message must be between $minimum and $postFlagTypeMaximumMessageLength characters.';
  }

  @override
  String get anotherMessageChangeIsStillFinishing =>
      'Another message change is still finishing.';

  @override
  String thisMessageCanNoLongerBe(String pinned) {
    String _temp0 = intl.Intl.selectLogic(pinned, {
      'true': 'This message can no longer be pinned.',
      'other': 'This message can no longer be unpinned.',
    });
    return '$_temp0';
  }

  @override
  String get selectAtLeastOneMessage => 'Select at least one message.';

  @override
  String selectNoMoreThanMessagesToDelete(String maximumBulkDeleteMessages) {
    return 'Select no more than $maximumBulkDeleteMessages messages to delete.';
  }

  @override
  String get oneOrMoreMessagesCanNoLongerBeDeleted =>
      'One or more messages can no longer be deleted.';

  @override
  String get oneOrMoreMessagesCanNoLongerBeMoved =>
      'One or more messages can no longer be moved.';

  @override
  String get chooseAnotherPublicChannel => 'Choose another public channel.';

  @override
  String get theSelectedMessagesOrDestinationChanged =>
      'The selected messages or destination changed.';

  @override
  String get thisMessageCanNoLongerBeDeleted =>
      'This message can no longer be deleted.';

  @override
  String get thisMessageCanNoLongerBeRestored =>
      'This message can no longer be restored.';

  @override
  String get thisMessageCanNoLongerBeRebuilt =>
      'This message can no longer be rebuilt.';

  @override
  String get oneOfThoseMessagesIsNoLongerAvailable =>
      'One of those messages is no longer available.';

  @override
  String get thatTranscriptIsStillBeingBuilt =>
      'That transcript is still being built.';

  @override
  String get thisMessageCanNoLongerBeEdited =>
      'This message can no longer be edited.';

  @override
  String get aMessageCannotBeEmpty => 'A message cannot be empty.';

  @override
  String messagesCanBeAtMostCharacters(String chatMessageMaximumEditLength) {
    return 'Messages can be at most $chatMessageMaximumEditLength characters.';
  }

  @override
  String get anotherEditIsStillFinishing => 'Another edit is still finishing.';

  @override
  String get thisMessageChangedBeforeTheEditCouldBeSaved =>
      'This message changed before the edit could be saved.';

  @override
  String get couldNotFindOutWhoReacted => 'Could not find out who reacted.';

  @override
  String get youNoLongerHaveAccessToThisChannel =>
      'You no longer have access to this channel.';

  @override
  String get couldNotLoadThisSiteSChatChannels =>
      'Could not load this site’s chat channels.';

  @override
  String get couldNotLoadYourChatThreads => 'Could not load your chat threads.';

  @override
  String get couldNotLoadThisChannelSThreads =>
      'Could not load this channel’s threads.';

  @override
  String get thatMessageIsUnavailableShowingTheThreadInstead =>
      'That message is unavailable. Showing the thread instead.';

  @override
  String get thisThreadIsNoLongerAvailable =>
      'This thread is no longer available.';

  @override
  String get couldNotLoadThisThread => 'Could not load this thread.';

  @override
  String get couldNotLoadThisChannel => 'Could not load this channel.';

  @override
  String get exitChat => 'Exit chat';

  @override
  String chatUrgent(num urgentCount) {
    String _temp0 = intl.Intl.pluralLogic(
      urgentCount,
      locale: localeName,
      other: 'Chat, $urgentCount urgent messages',
      one: 'Chat, $urgentCount urgent message',
    );
    return '$_temp0';
  }

  @override
  String get chatUnreadMessages => 'Chat, unread messages';

  @override
  String get chat => 'Chat';

  @override
  String get someone => 'Someone';

  @override
  String mentionedYouIn(String channel) {
    return 'mentioned you in $channel';
  }

  @override
  String sentAMessageIn(String channel) {
    return 'sent a message in $channel';
  }

  @override
  String invitedYouTo(String channel) {
    return 'invited you to $channel';
  }

  @override
  String get quotedYourChatMessage => 'quoted your chat message';

  @override
  String get thereIsANewReplyInAThreadYouFollow =>
      'There is a new reply in a thread you follow';

  @override
  String get newChatNotification => 'New chat notification';

  @override
  String get threadPaneWidth => 'Thread pane width';

  @override
  String get noRepliesYet => 'No replies yet.';

  @override
  String get dropFilesToUploadToThisThread =>
      'Drop files to upload to this thread';

  @override
  String get back => 'Back';

  @override
  String get thread => 'Thread';

  @override
  String get closeThread => 'Close thread';

  @override
  String get normal => 'Normal';

  @override
  String get mentionsOnly => 'Mentions only';

  @override
  String get tracking => 'Tracking';

  @override
  String get mentionsAndUnreadReplyCount => 'Mentions and unread reply count';

  @override
  String get watching => 'Watching';

  @override
  String get everyReplyAndUnreadCount => 'Every reply and unread count';

  @override
  String get threadNotifications => 'Thread notifications';

  @override
  String get threadSettings => 'Thread settings';

  @override
  String loadingChatbrowseskeleton(String pageName) {
    return 'Loading $pageName';
  }

  @override
  String get findAChannel => 'Find a channel';

  @override
  String get status => 'Status';

  @override
  String get membership => 'Membership';

  @override
  String get tryAgain => 'Try again';

  @override
  String get noMatchingChannelsLoadedYet => 'No matching channels loaded yet.';

  @override
  String get noChannelsMatchTheseFilters => 'No channels match these filters.';

  @override
  String get loadMore => 'Load more';

  @override
  String get all => 'All';

  @override
  String get open => 'Open';

  @override
  String get closed => 'Closed';

  @override
  String get archived => 'Archived';

  @override
  String get joined => 'Joined';

  @override
  String get notJoined => 'Not joined';

  @override
  String get readOnly => 'Read only';

  @override
  String get no => 'No';

  @override
  String get join => 'Join';

  @override
  String get leave => 'Leave';

  @override
  String get leaving => 'Leaving…';

  @override
  String get joining => 'Joining…';

  @override
  String get openChannel => 'Open channel';

  @override
  String get joinChannel => 'Join channel';

  @override
  String openMenu(String channelTitle) {
    return 'Open $channelTitle menu';
  }

  @override
  String get couldNotOpenThisChannel => 'Could not open this channel.';

  @override
  String selectMessageFrom(String messageAuthorDisplayName) {
    return 'Select message from $messageAuthorDisplayName';
  }

  @override
  String get linkCopied => 'Link copied!';

  @override
  String get couldnTCopyLink => 'Couldn\'t copy link.';

  @override
  String get messageCopied => 'Message copied!';

  @override
  String get couldnTCopyMessage => 'Couldn\'t copy message.';

  @override
  String get hTMLRebuildQueued => 'HTML rebuild queued.';

  @override
  String get thanksForKeepingOurCommunityCivil =>
      'Thanks for keeping our community civil!';

  @override
  String get flagMessage => 'Flag message';

  @override
  String get addReaction => 'Add reaction';

  @override
  String get reply => 'Reply';

  @override
  String get react => 'React';

  @override
  String get bookmark => 'Bookmark';

  @override
  String get editBookmark => 'Edit bookmark';

  @override
  String get unpin => 'Unpin';

  @override
  String get pin => 'Pin';

  @override
  String get copyLink => 'Copy link';

  @override
  String get copyText => 'Copy text';

  @override
  String get edit => 'Edit';

  @override
  String get flag => 'Flag';

  @override
  String get restoreDeletedMessage => 'Restore deleted message';

  @override
  String get rebuildHTML => 'Rebuild HTML';

  @override
  String get messageActions => 'Message actions';

  @override
  String get moreMessageActions => 'More message actions';

  @override
  String get pinnedChatMessage => 'Pinned chat message';

  @override
  String get bookmarkedChatMessage => 'Bookmarked chat message';

  @override
  String get chatMessageBookmarkedWithAReminder =>
      'Chat message bookmarked with a reminder';

  @override
  String failedToSendChatmessagetile(String messageSendError) {
    return 'Failed to send: $messageSendError';
  }

  @override
  String get retryAfterCooldown => 'Retry after cooldown';

  @override
  String viewProfileFor(String messageAuthorUsername, String authorFlairLabel) {
    return 'View profile for @$messageAuthorUsername, $authorFlairLabel';
  }

  @override
  String jumpToMessageFrom(
    String replyFlairNull,
    String replyUsername,
    String replyExcerpt,
    String replyFlairLabel,
  ) {
    String _temp0 = intl.Intl.selectLogic(replyFlairNull, {
      'true': 'Jump to message from @$replyUsername: $replyExcerpt',
      'other':
          'Jump to message from @$replyUsername, $replyFlairLabel: $replyExcerpt',
    });
    return '$_temp0';
  }

  @override
  String get originalMessage => 'Original message';

  @override
  String get removeYourReaction => 'remove your reaction';

  @override
  String get addThisReaction => 'add this reaction';

  @override
  String openThreadWith(String replies) {
    return 'Open thread with $replies.';
  }

  @override
  String get latestReply => ' Latest reply';

  @override
  String get online => 'Online';

  @override
  String get unmuteChannel => 'Unmute channel';

  @override
  String get muteChannel => 'Mute channel';

  @override
  String get channelSettings => 'Channel settings';

  @override
  String get removeFromStarredChannels => 'Remove from starred channels';

  @override
  String get addToStarredChannels => 'Add to starred channels';

  @override
  String get closeChannel => 'Close channel';

  @override
  String get leaveChannel => 'Leave channel';

  @override
  String get never => 'Never';

  @override
  String get allActivity => 'All activity';

  @override
  String get chatMessageChatbookmark => 'chat message';

  @override
  String get foldersCannotBeUploadedHere => 'Folders cannot be uploaded here.';

  @override
  String get send => 'Send';

  @override
  String get save => 'Save';

  @override
  String get couldnTOpenThePhotoLibrary => 'Couldn\'t open the photo library.';

  @override
  String get couldnTOpenTheFilePicker => 'Couldn\'t open the file picker.';

  @override
  String get youCannotSendChatMessages => 'You cannot send chat messages.';

  @override
  String get thisChatIsReadOnly => 'This chat is read-only.';

  @override
  String replyingTo(String replyUsername) {
    return 'Replying to @$replyUsername';
  }

  @override
  String get cancelReply => 'Cancel reply';

  @override
  String get messageChat => 'Message chat';

  @override
  String message(String channelTitle) {
    return 'Message $channelTitle';
  }

  @override
  String messageChatcomposer(String channelTitle) {
    return 'Message #$channelTitle';
  }

  @override
  String get files => 'Files';

  @override
  String get photoLibrary => 'Photo Library';

  @override
  String get insertGIF => 'Insert GIF';

  @override
  String get emoji => 'Emoji';

  @override
  String get addToMessage => 'Add to message';

  @override
  String get addEmoji => 'Add emoji';

  @override
  String get cancelEdit => 'Cancel edit';

  @override
  String get sendMessage => 'Send message';

  @override
  String get saveEdit => 'Save edit';

  @override
  String joinToStartChatting(String channelTitle) {
    return 'Join #$channelTitle to start chatting';
  }

  @override
  String youCanTJoin(String channelTitle) {
    return 'You can’t join #$channelTitle';
  }

  @override
  String get youLlBeAbleToPostAndReplyAndItLl =>
      'You’ll be able to post and reply, and it’ll show up in your channel list.';

  @override
  String get thisChannelIsnTOpenToNewMembersRightNow =>
      'This channel isn’t open to new members right now.';

  @override
  String get sentBy => 'Sent by';

  @override
  String get people => 'People';

  @override
  String get usernameOrMe => 'Username or me';

  @override
  String get findMessagesSentByOnePerson => 'Find messages sent by one person.';

  @override
  String get channel => 'Channel';

  @override
  String get where => 'Where';

  @override
  String get channelSlugOrID => 'Channel slug or ID';

  @override
  String get searchOneChannelAvailableToYourAccount =>
      'Search one channel available to your account.';

  @override
  String get threadReplies => 'Thread replies';

  @override
  String get content => 'Content';

  @override
  String get excludingRepliesStillIncludesMessagesThatStartedAThread =>
      'Excluding replies still includes messages that started a thread.';

  @override
  String get includeThreadReplies => 'Include thread replies';

  @override
  String get excludeThreadReplies => 'Exclude thread replies';

  @override
  String get mostRelevant => 'Most relevant';

  @override
  String get latestMessage => 'Latest message';

  @override
  String get chatSearchIsUnavailable => 'Chat search is unavailable.';

  @override
  String get channels => 'Channels';

  @override
  String get starredChannels => 'Starred channels';

  @override
  String get directMessages => 'Direct messages';

  @override
  String reapplyFilter(String label) {
    return 'Reapply filter: $label';
  }

  @override
  String showAll(String label) {
    return 'Show all: $label';
  }

  @override
  String get filterChatchannellistactions => 'Filter';

  @override
  String get sort => 'Sort';

  @override
  String get dismissStartChatting => 'Dismiss start chatting';

  @override
  String get startChatting => 'Start chatting';

  @override
  String get couldNotSearchChat => 'Could not search Chat.';

  @override
  String get thisConversationIsNoLongerAvailable =>
      'This conversation is no longer available.';

  @override
  String get couldNotStartThisChat => 'Could not start this chat.';

  @override
  String aGroupChatCanIncludeUpToPeople(String maximumGroupMembers) {
    return 'A group chat can include up to $maximumGroupMembers people.';
  }

  @override
  String get couldNotCreateThisGroup => 'Could not create this group.';

  @override
  String get bringAFewPeopleIntoTheConversation =>
      'Bring a few people into the conversation.';

  @override
  String get pickUpAConversationOrFindSomeoneNew =>
      'Pick up a conversation or find someone new.';

  @override
  String get cancel => 'Cancel';

  @override
  String get newGroupChat => 'New group chat';

  @override
  String get closeStartChatting => 'Close start chatting';

  @override
  String get groupNameOptional => 'Group name (optional)';

  @override
  String get chatDestinations => 'Chat destinations';

  @override
  String get searchChatRecipients => 'Search chat recipients';

  @override
  String get searchUsersOrGroups => 'Search users or groups';

  @override
  String get searchUsersGroupsOrChannels => 'Search users, groups, or channels';

  @override
  String get startGroupChat => 'Start group chat';

  @override
  String removeChatnewdirectmessage(String memberLabelMember) {
    return 'Remove $memberLabelMember';
  }

  @override
  String ofPeopleSelected(String membersCount, String maximumGroupMembers) {
    return '$membersCount of $maximumGroupMembers people selected';
  }

  @override
  String get groups => 'Groups';

  @override
  String get recentConversations => 'Recent conversations';

  @override
  String get conversations => 'Conversations';

  @override
  String get chatRecipientsAndConversations =>
      'Chat recipients and conversations';

  @override
  String get openingConversation => 'Opening conversation…';

  @override
  String get searching => 'Searching…';

  @override
  String get trySearchingAgain => 'Try searching again.';

  @override
  String get searchForPeopleOrGroupsToAdd =>
      'Search for people or groups to add.';

  @override
  String get searchForAUserToStartADirectMessage =>
      'Search for a user to start a direct message.';

  @override
  String get noMatchesFoundTryAnotherNameOrUsername =>
      'No matches found. Try another name or username.';

  @override
  String get createAGroupChat => 'Create a group chat';

  @override
  String get chatIsDisabledForThisUser => 'Chat is disabled for this user.';

  @override
  String get thisGroupCannotBeAddedToChat =>
      'This group cannot be added to Chat.';

  @override
  String get groupMemberLimitReached => 'Group member limit reached';

  @override
  String get bookmarkChatMessage => 'Bookmark chat message';

  @override
  String get chatMessageBookmark => 'Chat message bookmark';

  @override
  String openImage(String uploadOriginalFilename) {
    return 'Open image: $uploadOriginalFilename';
  }

  @override
  String openAttachment(String uploadOriginalFilename) {
    return 'Open attachment: $uploadOriginalFilename';
  }

  @override
  String openAttachmentChatuploads(
    String uploadOriginalFilename,
    String filesize,
  ) {
    return 'Open attachment: $uploadOriginalFilename, $filesize';
  }

  @override
  String get directMessage => 'Direct message';

  @override
  String openDetails(String title) {
    return 'Open $title details';
  }

  @override
  String get browseChats => 'Browse chats';

  @override
  String get browseChannels => 'Browse channels';

  @override
  String get browseThreads => 'Browse threads';

  @override
  String get browseChat => 'Browse chat';

  @override
  String get chats => 'Chats';

  @override
  String get threads => 'Threads';

  @override
  String get missingDirectMessageChatChannel =>
      'Missing direct-message chat channel.';

  @override
  String get missingChatChannel => 'Missing chat channel.';

  @override
  String get missingChatChannelMembership => 'Missing chat channel membership.';

  @override
  String get missingChatMessageMoveDestination =>
      'Missing chat message move destination.';

  @override
  String get missingChatQuoteMarkdown => 'Missing chat quote markdown.';

  @override
  String get missingChatThreadMembership => 'Missing chat thread membership.';

  @override
  String get atMost => 'at most';

  @override
  String get between1And => 'between 1 and';

  @override
  String inChat(String authorSomeone) {
    return '$authorSomeone in chat';
  }

  @override
  String get search => 'Search';

  @override
  String get theTopicComposerIsNoLongerAvailableHere =>
      'The topic composer is no longer available here.';

  @override
  String get startAMessage => 'Start a message';

  @override
  String get chatChannelsAreNotAvailable => 'Chat channels are not available.';

  @override
  String get chatIsNotAvailable => 'Chat is not available.';

  @override
  String get threadsAreNotAvailable => 'Threads are not available.';

  @override
  String get chatThreadsAreNotAvailable => 'Chat threads are not available.';

  @override
  String get chatSearchIsNotAvailable => 'Chat search is not available.';

  @override
  String get thereAreNoActiveThreadsInThisChannel =>
      'There are no active threads in this channel.';

  @override
  String get noUnreadConversations => 'No unread conversations.';

  @override
  String get noConversationsYet => 'No conversations yet.';

  @override
  String get youHaveNotJoinedAnyChannelsYet =>
      'You have not joined any channels yet.';

  @override
  String get youHaveNoDirectMessagesYet => 'You have no direct messages yet.';

  @override
  String get noVoiceRoomsYet => 'No voice rooms yet.';

  @override
  String get unread => 'Unread';

  @override
  String get recent => 'Recent';

  @override
  String get chatActivity => 'Chat activity';

  @override
  String get voiceRooms => 'Voice rooms';

  @override
  String get conversationType => 'Conversation type';

  @override
  String get browse => 'Browse';

  @override
  String get couldNotLoadConversations => 'Could not load conversations';

  @override
  String get noMessagesYet => 'No messages yet';

  @override
  String get unreadConversation => 'Unread conversation';

  @override
  String get loadingConversations => 'Loading conversations';

  @override
  String get activeInTheLast30Days => 'Active in the last 30 days';

  @override
  String get mentions => 'Mentions';

  @override
  String get alphabetical => 'Alphabetical';

  @override
  String get recentActivity => 'Recent activity';

  @override
  String get priority => 'Priority';

  @override
  String get messageNew => 'New';

  @override
  String get newMessage => 'New message';

  @override
  String get starred => 'Starred';

  @override
  String get noChannelsMatchThisFilter => 'No channels match this filter.';

  @override
  String get youHaveNoStarredChannels => 'You have no starred channels.';

  @override
  String get loadingChatChannels => 'Loading chat channels';

  @override
  String urgentNotifications(String badgeCount) {
    return '$badgeCount urgent notifications';
  }

  @override
  String get closingTheChannelPreventsNonStaffUsersFromSendingNewMessages =>
      'Closing the channel prevents non-staff users from sending new messages or editing existing messages.';

  @override
  String get reopeningTheChannelLetsAllMembersSendMessagesAndEditTheir =>
      'Reopening the channel lets all members send messages and edit their existing messages.';

  @override
  String get pinnedMessages => 'Pinned messages';

  @override
  String pinnedBy(String by) {
    return 'Pinned by $by';
  }

  @override
  String messageBy(String messageAuthorDisplayName) {
    return 'Message by $messageAuthorDisplayName';
  }

  @override
  String get loadingPinnedMessages => 'Loading pinned messages';

  @override
  String get pinnedMessage => 'Pinned message';

  @override
  String get unseenPinnedMessages => 'Unseen pinned messages';

  @override
  String get couldNotLoadThisConversation =>
      'Could not load this conversation.';

  @override
  String get messageNotSent => 'Message not sent.';

  @override
  String get searchMessagesAcrossYourChatChannels =>
      'Search messages across your Chat channels.';

  @override
  String get noChatMessagesFound => 'No chat messages found.';

  @override
  String get couldNotOpenThisChatMessage => 'Could not open this chat message.';

  @override
  String get relevance => 'Relevance';

  @override
  String get bestMatchingMessagesFirst => 'Best matching messages first';

  @override
  String get latest => 'Latest';

  @override
  String get newestMessagesFirst => 'Newest messages first';

  @override
  String get searchMessages => 'Search messages';

  @override
  String get clearSearch => 'Clear search';

  @override
  String get sortSearchResults => 'Sort search results';

  @override
  String sortSearchResultsBy(String label) {
    return 'Sort search results by $label';
  }

  @override
  String inThread(String threadTitle) {
    return 'in thread $threadTitle';
  }

  @override
  String get reconnectToThisForumToSeeChatNotifications =>
      'Reconnect to this forum to see chat notifications.';

  @override
  String get couldnTLoadChatNotificationsFromThisForum =>
      'Couldn\'t load chat notifications from this forum.';

  @override
  String get youDonTHaveAnyChatNotificationsYet =>
      'You don’t have any chat notifications yet.';

  @override
  String get allChannels => 'All channels';

  @override
  String get noChatThreadsYet => 'No chat threads yet.';

  @override
  String get noThreadsInThisChannel => 'No threads in this channel.';

  @override
  String get noRepliesYetChatmythreadsview => 'No replies yet';

  @override
  String openThread(
    String channelNull,
    String unread,
    String title,
    String replyCountLabelThreadReplyCount,
    String channelTitle,
  ) {
    String _temp0 = intl.Intl.selectLogic(unread, {
      'true': 'Open thread $title, $replyCountLabelThreadReplyCount, unread',
      'other': 'Open thread $title, $replyCountLabelThreadReplyCount',
    });
    String _temp1 = intl.Intl.selectLogic(unread, {
      'true':
          'Open thread $title in $channelTitle, $replyCountLabelThreadReplyCount, unread',
      'other':
          'Open thread $title in $channelTitle, $replyCountLabelThreadReplyCount',
    });
    String _temp2 = intl.Intl.selectLogic(channelNull, {
      'true': '$_temp0',
      'other': '$_temp1',
    });
    return '$_temp2';
  }

  @override
  String get couldNotOpenThisChatThread => 'Could not open this chat thread.';

  @override
  String openThreadChatmythreadsview(String title) {
    return 'Open thread $title';
  }

  @override
  String get latestReplyChatmythreadsview => 'Latest reply';

  @override
  String get showSeparateSidebarModesForForumAndChat =>
      'Show separate sidebar modes for forum and chat';

  @override
  String get always => 'Always';

  @override
  String get whenChatIsInFullscreen => 'When chat is in fullscreen';

  @override
  String get couldNotSaveChannelPreferencesTryAgain =>
      'Could not save channel preferences. Try again.';

  @override
  String get attachment => 'Attachment';

  @override
  String get couldNotSaveTheThreadTitleTryAgain =>
      'Could not save the thread title. Try again.';

  @override
  String get title => 'Title';

  @override
  String get giveThisThreadATitle => 'Give this thread a title';

  @override
  String get youCanNoLongerEditThisThreadTitle =>
      'You can no longer edit this thread title.';

  @override
  String get noMessagesHereYet => 'No messages here yet.';

  @override
  String dropFilesToUploadTo(String channelTitleChat) {
    return 'Drop files to upload to #$channelTitleChat';
  }

  @override
  String get couldNotStartThisThreadTryAgain =>
      'Could not start this thread. Try again.';

  @override
  String get messagesCopied => 'Messages copied!';

  @override
  String get couldnTCopyMessages => 'Couldn\'t copy messages.';

  @override
  String get moveMessages => 'Move messages';

  @override
  String moveSelectedTo(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Move $count selected messages to:',
      one: 'Move $count selected message to:',
    );
    return '$_temp0';
  }

  @override
  String get destinationChannel => 'Destination channel';

  @override
  String get move => 'Move';

  @override
  String get deleteSelectedMessages => 'Delete selected messages?';

  @override
  String areYouSureYouWantToDelete(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Are you sure you want to delete $count messages?',
      one: 'Are you sure you want to delete $count message?',
    );
    return '$_temp0';
  }

  @override
  String get messagesDeleted => 'Messages deleted.';

  @override
  String get quoteSelectedMessages => 'Quote selected messages';

  @override
  String get copy => 'Copy';

  @override
  String get moveSelectedMessagesToAnotherChannel =>
      'Move selected messages to another channel';

  @override
  String selectNoMoreThanMessages(
    String chatControllerMaximumBulkDeleteMessages,
  ) {
    return 'Select no more than $chatControllerMaximumBulkDeleteMessages messages';
  }

  @override
  String get deleteSelectedMessagesChatchannelview =>
      'Delete selected messages';

  @override
  String get cancelSelection => 'Cancel selection';

  @override
  String jumpToLatestMessagesNew(String pendingCount) {
    return 'Jump to latest messages, $pendingCount new';
  }

  @override
  String get jumpToLatestMessages => 'Jump to latest messages';

  @override
  String get aMessageWasDeletedView => 'A message was deleted. [view]';

  @override
  String messagesWereDeletedViewAll(String messageIdsLength) {
    return '$messageIdsLength messages were deleted. [view all]';
  }

  @override
  String get loadingNewerMessages => 'Loading newer messages';

  @override
  String get loadingOlderMessages => 'Loading older messages';

  @override
  String get loadingChatChannel => 'Loading chat channel';

  @override
  String get editChannelDetails => 'Edit channel details';

  @override
  String get name => 'Name';

  @override
  String get slug => 'Slug';

  @override
  String get usedInTheChannelURL => 'Used in the channel URL';

  @override
  String get description => 'Description';

  @override
  String searchTermsMustBeAtMostCharacters(String maximumQueryLength) {
    return 'Search terms must be at most $maximumQueryLength characters.';
  }

  @override
  String get couldNotLoadMoreChatResults => 'Could not load more chat results.';

  @override
  String get couldNotSearchChatTryAgain => 'Could not search Chat. Try again.';

  @override
  String get thisChannelIsNoLongerAvailable =>
      'This channel is no longer available.';

  @override
  String get settings => 'Settings';

  @override
  String members(String channelMembershipsCount) {
    return 'Members ($channelMembershipsCount)';
  }

  @override
  String get membersChatchannelinfoview => 'Members';

  @override
  String get yourNotifications => 'Your notifications';

  @override
  String get hideUnreadIndicatorsAndStopChannelNotifications =>
      'Hide unread indicators and stop channel notifications.';

  @override
  String get pushNotifications => 'Push notifications';

  @override
  String get chooseWhichActivityShouldReachThisDevice =>
      'Choose which activity should reach this device.';

  @override
  String get conversation => 'Conversation';

  @override
  String get threadedReplies => 'Threaded replies';

  @override
  String get repliesOpenAsSeparateConversationsAlongsideTheMainChannel =>
      'Replies open as separate conversations alongside the main channel.';

  @override
  String get enableThreads => 'Enable threads';

  @override
  String get channelInformation => 'Channel information';

  @override
  String get category => 'Category';

  @override
  String get controlsVisibilityAndMembershipRules =>
      'Controls visibility and membership rules.';

  @override
  String get messageHistory => 'Message history';

  @override
  String get messagesAreRemovedAfterTheRetentionPeriod =>
      'Messages are removed after the retention period.';

  @override
  String get channelManagement => 'Channel management';

  @override
  String get channelIsClosed => 'Channel is closed.';

  @override
  String get channelIsOpen => 'Channel is open.';

  @override
  String get openingLetsMembersPostInThisChannelAgain =>
      'Opening lets members post in this channel again.';

  @override
  String get closingPreventsNonStaffMembersFromPosting =>
      'Closing prevents non-staff members from posting.';

  @override
  String get leaveThisChannel => 'Leave this channel';

  @override
  String removeFromYourSidebarAndStopFollowingItsConversations(
    String channelTitle,
  ) {
    return 'Remove $channelTitle from your sidebar and stop following its conversations.';
  }

  @override
  String get forever => 'Forever';

  @override
  String get tellPeopleWhatThisChannelIsAbout =>
      'Tell people what this channel is about.';

  @override
  String get editDetails => 'Edit details';

  @override
  String get filterMembers => 'Filter members';

  @override
  String get noMembers => 'No members.';

  @override
  String get noMembersFound => 'No members found.';

  @override
  String get invalidPlaceholderStore => 'Invalid placeholder store';

  @override
  String get selectAValue => 'Select a value';

  @override
  String removeYourReactionReactionpicker(String mine) {
    return 'Remove your $mine reaction';
  }

  @override
  String get chooseAReaction => 'Choose a reaction';

  @override
  String get chooseAReactionReactionpicker => 'choose a reaction';

  @override
  String get stillFindingOutWhichReactionsThisSiteAllows =>
      'Still finding out which reactions this site allows.';

  @override
  String get moreEmojis => 'More emojis';

  @override
  String showAllReactions(String countLabelCountReaction) {
    return '$countLabelCountReaction. Show all reactions';
  }

  @override
  String get showAllReactionsReactionsrow => 'Show all reactions';

  @override
  String get postReactions => 'Post reactions';

  @override
  String get reactions => 'Reactions';

  @override
  String changeYourReactionTo(String reaction) {
    return 'change your reaction to $reaction';
  }

  @override
  String reactionCountCanUndo(String id, String count, String canUndo) {
    return 'Reaction($id, count: $count, canUndo: $canUndo)';
  }

  @override
  String reactionsMineUsers(String entries, String mine, String userCount) {
    return 'Reactions($entries, mine: $mine, users: $userCount)';
  }

  @override
  String get reactToThisPost => 'React to this post';

  @override
  String get aTopic => 'a topic';

  @override
  String reactedToOfYourPosts(String count) {
    return 'reacted to $count of your posts';
  }

  @override
  String get reactedToYourPosts => 'reacted to your posts';

  @override
  String reactedToYourPostIn(String title) {
    return 'reacted to your post in $title';
  }

  @override
  String get topicVotes => 'Topic votes';

  @override
  String get extensions => 'Extensions';

  @override
  String get atLeast => 'at least';

  @override
  String get matchTheNumberOfVotesOnATopic =>
      'Match the number of votes on a topic.';

  @override
  String get mostVotes => 'Most votes';

  @override
  String get mermaidChartEditor => 'Mermaid chart editor';

  @override
  String get youTubePlaylist => 'YouTube playlist';

  @override
  String get youTubeVideo => 'YouTube video';

  @override
  String get searchGIFs => 'Search GIFs';

  @override
  String get theComposerChangedWhileTheGIFPickerWasOpenNothingWas =>
      'The composer changed while the GIF picker was open. Nothing was changed.';

  @override
  String get connectToThisSiteBeforeSearchingForGIFs =>
      'Connect to this site before searching for GIFs.';

  @override
  String get thatGIFSearchIsTooLong => 'That GIF search is too long.';

  @override
  String get gIFSearchIsNotConfiguredForThisSiteOrItsAPI =>
      'GIF search is not configured for this site, or its API key is invalid.';

  @override
  String get gIFSearchIsNotEnabledForThisSite =>
      'GIF search is not enabled for this site.';

  @override
  String get tooManyGIFSearchesTryAgainInAMoment =>
      'Too many GIF searches. Try again in a moment.';

  @override
  String get couldnTLoadGIFsCheckTheConnectionAndTryAgain =>
      'Couldn\'t load GIFs. Check the connection and try again.';

  @override
  String get browseCategories => 'Browse categories';

  @override
  String get typeAtLeast3CharactersToSearchForAGIF =>
      'Type at least 3 characters to search for a GIF.';

  @override
  String get noGIFsFound => 'No GIFs found.';

  @override
  String get chooseGIF => 'Choose GIF';

  @override
  String chooseGIFGifpicker(String resultTitle) {
    return 'Choose $resultTitle GIF';
  }

  @override
  String searchGIFsGifpicker(String categoryTitle) {
    return 'Search $categoryTitle GIFs';
  }

  @override
  String get poweredByKlipy => 'Powered by Klipy';

  @override
  String activateToEdit(String label) {
    return '$label. Activate to edit.';
  }

  @override
  String activateToEditLocaldatecomposercomponent(
    String formatterAccountTimezoneAccountTimezone,
  ) {
    return '$formatterAccountTimezoneAccountTimezone. Activate to edit.';
  }

  @override
  String get localDate => 'Local date';

  @override
  String get aFewSeconds => 'a few seconds';

  @override
  String get aMinute => 'a minute';

  @override
  String get anHour => 'an hour';

  @override
  String get aDay => 'a day';

  @override
  String get aMonth => 'a month';

  @override
  String get aYear => 'a year';

  @override
  String get dateAndTime => 'Date and time';

  @override
  String get dismissDateAndTime => 'Dismiss date and time';

  @override
  String get device => 'Device';

  @override
  String get source => 'Source';

  @override
  String get localDatesDisabled => 'local dates disabled';

  @override
  String get localDateSyntaxContainsUnsupportedOptions =>
      'local date syntax contains unsupported options';

  @override
  String get localDateSyntaxIsMalformedOrUnsupported =>
      'local date syntax is malformed or unsupported';

  @override
  String get localDateSyntaxCouldNotBeAccountedFor =>
      'local date syntax could not be accounted for';

  @override
  String get insertDateTime => 'Insert date/time';

  @override
  String get theComposerChangedWhileThisDateWasOpenNothingWasChanged =>
      'The composer changed while this date was open. Nothing was changed.';

  @override
  String get theComposerChangedBeforeThisDateCouldBeRemovedNothingWas =>
      'The composer changed before this date could be removed. Nothing was changed.';

  @override
  String get llllZ => 'llll z';

  @override
  String get chooseAValidStartDate => 'Choose a valid start date.';

  @override
  String get chooseAValidStartTime => 'Choose a valid start time.';

  @override
  String get chooseAValidEndDate => 'Choose a valid end date.';

  @override
  String get anEndTimeNeedsAValidEndDate =>
      'An end time needs a valid end date.';

  @override
  String get chooseAtMostFivePreviewTimezones =>
      'Choose at most five preview timezones.';

  @override
  String get everyTimezoneMustBeAValidIANATimezone =>
      'Every timezone must be a valid IANA timezone.';

  @override
  String get recurrenceMustLookLike1Weeks =>
      'Recurrence must look like “1.weeks”.';

  @override
  String get rangesCannotRecurOrUseCountdownMode =>
      'Ranges cannot recur or use countdown mode.';

  @override
  String get theStartTimeDoesNotExistInThatTimezone =>
      'The start time does not exist in that timezone.';

  @override
  String get theEndTimeDoesNotExistInThatTimezone =>
      'The end time does not exist in that timezone.';

  @override
  String get theEndMustBeAfterTheStart => 'The end must be after the start.';

  @override
  String get insertDateAndTime => 'Insert date and time';

  @override
  String get editDateAndTime => 'Edit date and time';

  @override
  String get chooseTheDateThenCheckHowItWillAppear =>
      'Choose the date, then check how it will appear.';

  @override
  String get when => 'When';

  @override
  String get start => 'Start';

  @override
  String get addEndDateAndTime => 'Add end date and time';

  @override
  String get end => 'End';

  @override
  String get timezone => 'Timezone';

  @override
  String get sourceTimezone => 'Source timezone';

  @override
  String get thisIsTheTimezoneInWhichTheDateAndTimeWere =>
      'This is the timezone in which the date and time were entered.';

  @override
  String get displayOptions => 'Display options';

  @override
  String get recurrenceOptional => 'Recurrence (optional)';

  @override
  String get countdown => 'Countdown';

  @override
  String get displayedTimezoneOptional => 'Displayed timezone (optional)';

  @override
  String get relativeDay => 'Relative day';

  @override
  String get automatic => 'Automatic';

  @override
  String get alwaysOn => 'Always on';

  @override
  String get off => 'Off';

  @override
  String get momentFormatOptional => 'Moment format (optional)';

  @override
  String get forExampleLLLOrYYYYMMDDAtHHMm =>
      'For example: LLL or YYYY-MM-DD [at] HH:mm';

  @override
  String siteFormats(String siteFormatsJoin) {
    return 'Site formats: $siteFormatsJoin';
  }

  @override
  String get previewTimezones => 'Preview timezones';

  @override
  String get addPreviewTimezone => 'Add preview timezone';

  @override
  String get addTimezone => 'Add timezone';

  @override
  String chooseTime(String label) {
    return 'Choose $label time';
  }

  @override
  String includeTime(String label) {
    return 'Include $label time';
  }

  @override
  String get completeTheDateToSeeAPreview =>
      'Complete the date to see a preview.';

  @override
  String get previewOfTheRenderedDate => 'Preview of the rendered date';

  @override
  String get thatWallTimeDoesNotExist => 'That wall time does not exist.';

  @override
  String get removeLocaldatecomposersheet => 'Remove';

  @override
  String get apply => 'Apply';

  @override
  String get noneDeviceTimezone => 'None / device timezone';

  @override
  String get noTimezonesFound => 'No timezones found.';

  @override
  String get callTranscriptDraft => 'Call transcript draft';

  @override
  String voiceOperationFailed(String operation, String errorType) {
    return 'Voice operation $operation failed ($errorType).';
  }

  @override
  String
  get microphoneAccessIsBlockedAllowMicrophoneAccessInYourSystemSettings =>
      'Microphone access is blocked. Allow microphone access in your system settings, then try joining again.';

  @override
  String get weCouldnTAccessYourMicrophoneCheckThatItIsConnected =>
      'We couldn\'t access your microphone. Check that it is connected and not in use by another app, then try again.';

  @override
  String couldnTJoin(String roomName) {
    return 'Couldn\'t join $roomName.';
  }

  @override
  String get thisCallConnectsParticipantsDirectlySoOtherParticipantsMayBeAble =>
      'This call connects participants directly, so other participants may be able to see your IP address.';

  @override
  String get couldnTLoadVoiceRooms => 'Couldn\'t load voice rooms.';

  @override
  String get videoWasTurnedOffInThisRoom =>
      'Video was turned off in this room.';

  @override
  String get youVeBeenMovedToListeners => 'You\'ve been moved to listeners.';

  @override
  String get youVeBeenMadeASpeaker => 'You\'ve been made a speaker.';

  @override
  String get thisCallIsNowBeingRecorded => 'This call is now being recorded.';

  @override
  String get theRecordingHasStopped => 'The recording has stopped.';

  @override
  String get yourRequestToSpeakWasDismissed =>
      'Your request to speak was dismissed.';

  @override
  String raisedTheirHandToSpeak(String nameRaiserUsername) {
    return '$nameRaiserUsername raised their hand to speak.';
  }

  @override
  String get yourCallSessionHasExpiredRejoinTheRoomToStartA =>
      'Your call session has expired. Rejoin the room to start a new one.';

  @override
  String get youWereAutoMutedAfterBeingIdleUnmuteToKeepTalking =>
      'You were auto-muted after being idle. Unmute to keep talking.';

  @override
  String youWereDisconnectedFromDueToInactivity(String callRoomName) {
    return 'You were disconnected from $callRoomName due to inactivity.';
  }

  @override
  String get theMediaSettingWasNotApplied =>
      'The media setting was not applied.';

  @override
  String get couldnTSaveTheVoiceRoom => 'Couldn\'t save the voice room.';

  @override
  String get couldnTDeleteTheVoiceRoom => 'Couldn\'t delete the voice room.';

  @override
  String get couldnTLoadRoomChat => 'Couldn\'t load room chat.';

  @override
  String get couldnTAddTheMember => 'Couldn\'t add the member.';

  @override
  String get couldnTChangeTheMemberSRole =>
      'Couldn\'t change the member\'s role.';

  @override
  String get couldnTRemoveTheMember => 'Couldn\'t remove the member.';

  @override
  String get theMediaConnectionCouldNotBeRestored =>
      'The media connection could not be restored.';

  @override
  String get enterAnAgentName => 'Enter an agent name.';

  @override
  String get use256CharactersOrFewer => 'Use 256 characters or fewer.';

  @override
  String get couldnTLoadDeployedAgentsYouCanTypeAName =>
      'Couldn\'t load deployed agents. You can type a name.';

  @override
  String get thisInvitationIsNoLongerAvailable =>
      'This invitation is no longer available.';

  @override
  String get couldnTInviteTheAgentTryAgain =>
      'Couldn\'t invite the agent. Try again.';

  @override
  String get aVoiceRoom => 'a voice room';

  @override
  String get isCallingYou => 'is calling you';

  @override
  String invitedYouToJoin(String roomName) {
    return 'invited you to join $roomName';
  }

  @override
  String get thePreviousCaptureEndedWithoutAStopMarker =>
      'The previous capture ended without a stop marker.';

  @override
  String get inviteAgent => 'Invite agent';

  @override
  String get inviteVoiceAgent => 'Invite voice agent';

  @override
  String get chooseADeployedAgentOrEnterItsDispatchName =>
      'Choose a deployed agent or enter its dispatch name.';

  @override
  String get agentInvitationSent => 'Agent invitation sent.';

  @override
  String get agentName => 'Agent name';

  @override
  String get deployedAgent => 'Deployed agent';

  @override
  String get chooseAnAgent => 'Choose an agent';

  @override
  String get typeAName => 'Type a name';

  @override
  String get refreshAgents => 'Refresh agents';

  @override
  String get done => 'Done';

  @override
  String get sendInvitation => 'Send invitation';

  @override
  String get sendingInvitation => 'Sending invitation';

  @override
  String get recentRecordsOnlyUseShareSaveForTheFullReport =>
      'Recent records only. Use Share/Save for the full report.';

  @override
  String get saveReport => 'Save report';

  @override
  String get shareReport => 'Share report';

  @override
  String get jSONLinesDiagnostics => 'JSON Lines diagnostics';

  @override
  String get voiceDiagnostics => 'Voice diagnostics';

  @override
  String get voice => 'Voice';

  @override
  String get voiceCaptureRecording => 'Voice capture recording';

  @override
  String get voiceDiagnosticsAreUnavailable =>
      'Voice diagnostics are unavailable.';

  @override
  String get couldnTStartTheCall => 'Couldn\'t start the call.';

  @override
  String get call => 'Call';

  @override
  String get voiceCall => 'Voice call';

  @override
  String get unsupportedVoiceTransport => 'Unsupported Voice transport';

  @override
  String get missingVoiceRoom => 'Missing Voice room';

  @override
  String get createVoiceRoom => 'Create voice room';

  @override
  String get editVoiceRoom => 'Edit voice room';

  @override
  String get chooseHowPeopleJoinAndParticipateInYourRoom =>
      'Choose how people join and participate in your room.';

  @override
  String get roomDetails => 'Room details';

  @override
  String get enterARoomName => 'Enter a room name.';

  @override
  String get use80CharactersOrFewer => 'Use 80 characters or fewer.';

  @override
  String get whatWillPeopleTalkAboutOptional =>
      'What will people talk about? (optional)';

  @override
  String get roomSettings => 'Room settings';

  @override
  String get publicRoom => 'Public room';

  @override
  String get visibleToEveryoneOnTheForum => 'Visible to everyone on the forum.';

  @override
  String get stageRoom => 'Stage room';

  @override
  String get peopleJoinAsListenersUntilInvitedToSpeak =>
      'People join as listeners until invited to speak.';

  @override
  String get allowVideo => 'Allow video';

  @override
  String get letParticipantsShareTheirCameraAndScreen =>
      'Let participants share their camera and screen.';

  @override
  String get maximumParticipants => 'Maximum participants';

  @override
  String get forumDefault => 'Forum default';

  @override
  String get optional2200People => 'Optional, 2–200 people.';

  @override
  String get optional250People => 'Optional, 2–50 people.';

  @override
  String get maximumMediaQuality => 'Maximum media quality';

  @override
  String get advancedSettings => 'Advanced settings';

  @override
  String get chatChannelIDOptional => 'Chat channel ID (optional)';

  @override
  String get useAChannelWithThreadingEnabledForRoomConversations =>
      'Use a channel with threading enabled for room conversations.';

  @override
  String get newChatThreadAfterMinutes => 'New chat thread after (minutes)';

  @override
  String get startAFreshThreadAfter21440MinutesOfInactivity =>
      'Start a fresh thread after 2–1,440 minutes of inactivity. Defaults to 15.';

  @override
  String get useLiveKit => 'Use LiveKit';

  @override
  String get createRoom => 'Create room';

  @override
  String get saveChanges => 'Save changes';

  @override
  String get standard => 'Standard';

  @override
  String get high => 'High';

  @override
  String get maximum => 'Maximum';

  @override
  String enterAWholeNumberOfOrMore(String min) {
    return 'Enter a whole number of $min or more.';
  }

  @override
  String enterAWholeNumberFromTo(String min, String max) {
    return 'Enter a whole number from $min to $max.';
  }

  @override
  String get hTTPPathContainsVoice => 'HTTP path contains /voice/';

  @override
  String get recording => 'Recording';

  @override
  String get unmute => 'Unmute';

  @override
  String get mute => 'Mute';

  @override
  String get leaveRoom => 'Leave room';

  @override
  String cand(
    String head,
    String redactMatchGroup,
    String redactMatchGroupValue3,
    String matchGroup,
  ) {
    return 'Cand[$head:$redactMatchGroup:$redactMatchGroupValue3$matchGroup';
  }

  @override
  String get notAllowed => 'not allowed';

  @override
  String get permissionDenied => 'permission denied';

  @override
  String get permissionDismissed => 'permission dismissed';

  @override
  String get notAuthorized => 'not authorized';

  @override
  String get mediaAccessDenied => 'media access denied';

  @override
  String get microphonePermissionWasDenied =>
      'Microphone permission was denied.';

  @override
  String get theMicrophoneIsUnavailable => 'The microphone is unavailable.';

  @override
  String voiceMediaOperationFailed(String operation) {
    return 'Voice media operation $operation failed.';
  }

  @override
  String get rejectedVoiceTrack => 'rejected Voice track';

  @override
  String get missingLiveKitCredentials => 'Missing LiveKit credentials';

  @override
  String get voiceMedia => 'Voice media';

  @override
  String duringLiveKit(String operation) {
    return 'during LiveKit $operation';
  }

  @override
  String get voiceCallingIsUnavailable => 'Voice calling is unavailable.';

  @override
  String get couldnTOpenTheVoiceRoom => 'Couldn\'t open the voice room.';

  @override
  String get couldnTUpdateTheMicrophone => 'Couldn\'t update the microphone.';

  @override
  String get couldnTLeaveTheVoiceRoom => 'Couldn\'t leave the voice room.';

  @override
  String get mediaDevice => 'media device';

  @override
  String get pushToTalkPreference => 'push-to-talk preference';

  @override
  String get cameraPreference => 'camera preference';

  @override
  String get privacyAcknowledgement => 'privacy acknowledgement';

  @override
  String get statusPreference => 'status preference';

  @override
  String get participantVolume => 'participant volume';

  @override
  String get searchVoiceCapture => 'Search Voice capture';

  @override
  String get turnOnDeepVoiceCapture => 'Turn on deep Voice capture?';

  @override
  String get thisRecordsUsernamesAndUserIDsNetworkAddressesRawSDPAnd =>
      'This records usernames and user IDs, network addresses, raw SDP and ICE negotiation, media statistics, and device details. Credentials and other secrets are redacted. Capture stays on until you turn it off or restart the app.';

  @override
  String get turnOnCapture => 'Turn on capture';

  @override
  String get deepCaptureIsOn => 'Deep capture is on';

  @override
  String get deepCaptureStopped => 'Deep capture stopped';

  @override
  String get clearVoiceCapture => 'Clear Voice capture?';

  @override
  String
  get thisPermanentlyRemovesTheRetainedDeepCaptureRecordsFromThisDevice =>
      'This permanently removes the retained deep-capture records from this device.';

  @override
  String get clearCapture => 'Clear capture';

  @override
  String get voiceCaptureCleared => 'Voice capture cleared';

  @override
  String get recentReportCopiedFullReportIsTooLarge =>
      'Recent report copied (full report is too large)';

  @override
  String get voiceReportCopied => 'Voice report copied';

  @override
  String get captureEventCopied => 'Capture event copied';

  @override
  String get voiceReportSaved => 'Voice report saved';

  @override
  String get voiceReportShared => 'Voice report shared';

  @override
  String voiceDiagnosticsFailed(String error) {
    return 'Voice diagnostics failed: $error';
  }

  @override
  String get recordingOn => 'Recording On';

  @override
  String get recordingOff => 'Recording Off';

  @override
  String
  get deepCaptureStoresIdentitiesNetworkAndMediaNegotiationDeviceDetailsAnd =>
      'Deep capture stores identities, network and media negotiation, device details, and SDK logs. Secrets are redacted. Restarting the app turns recording off.';

  @override
  String get truncated => 'Truncated';

  @override
  String since(String diagnosticTimeTextStateStartedAtUtc) {
    return 'Since $diagnosticTimeTextStateStartedAtUtc';
  }

  @override
  String capture(String stateCaptureId) {
    return 'Capture $stateCaptureId';
  }

  @override
  String get copyReport => 'Copy report';

  @override
  String get turnRecordingOffBeforeClearing =>
      'Turn recording off before clearing';

  @override
  String get backToCapture => 'Back to capture';

  @override
  String get noMatchingCaptureEvents => 'No matching capture events';

  @override
  String get waitingForVoiceActivity => 'Waiting for Voice activity';

  @override
  String get noDeepCaptureRecords => 'No deep-capture records';

  @override
  String get changeTheSearchToSeeMore => 'Change the search to see more.';

  @override
  String get callAndSignalingEventsWillAppearHere =>
      'Call and signaling events will appear here.';

  @override
  String get turnRecordingOnBeforeReproducingTheCallProblem =>
      'Turn recording on before reproducing the call problem.';

  @override
  String get captureEvent => 'capture event';

  @override
  String kiB(String bytesToStringAsFixed) {
    return '$bytesToStringAsFixed KiB';
  }

  @override
  String miB(String bytesToStringAsFixed) {
    return '$bytesToStringAsFixed MiB';
  }

  @override
  String get beforeYouJoinThisRoom => 'Before you join this room';

  @override
  String get thisRoomConnectsParticipantsDirectlyToEachOtherSoWhileYou =>
      'This room connects participants directly to each other, so while you are in the call other participants may be able to see your IP address. This is how peer-to-peer calls work and is usually harmless, but join only if you are comfortable with it.';

  @override
  String get donTShowThisAgain => 'Don\'t show this again';

  @override
  String get joinRoom => 'Join room';

  @override
  String isCallingYouVoiceincomingcall(String nameCallerUsername) {
    return '$nameCallerUsername is calling you';
  }

  @override
  String get isCallingYouVoiceincomingcallValue => 'is calling you…';

  @override
  String get answer => 'Answer';

  @override
  String get decline => 'Decline';

  @override
  String get thisVoiceRoomIsUnavailable => 'This voice room is unavailable.';

  @override
  String get dismiss => 'Dismiss';

  @override
  String calling(String nameUserUsername) {
    return 'Calling $nameUserUsername';
  }

  @override
  String callingVoiceroomview(String nameUserUsername) {
    return 'Calling $nameUserUsername…';
  }

  @override
  String get thisCallIsBeingRecorded => 'This call is being recorded';

  @override
  String recordingStartedBy(String startedBy) {
    return 'Recording started by @$startedBy';
  }

  @override
  String nobodyIsInYet(String roomName) {
    return 'Nobody is in $roomName yet.';
  }

  @override
  String get handRaised => 'hand raised';

  @override
  String get participantActions => 'Participant actions';

  @override
  String get localVolume => 'Local volume';

  @override
  String get notifyModerators => 'Notify moderators';

  @override
  String get makeSpeaker => 'Make speaker';

  @override
  String get moveToListeners => 'Move to listeners';

  @override
  String get dismissRaisedHand => 'Dismiss raised hand';

  @override
  String get removeFromRoom => 'Remove from room';

  @override
  String get listen => 'Listen';

  @override
  String get deafen => 'Deafen';

  @override
  String get cameraOff => 'Camera off';

  @override
  String get cameraOn => 'Camera on';

  @override
  String get stopSharing => 'Stop sharing';

  @override
  String get shareScreen => 'Share screen';

  @override
  String get raiseHand => 'Raise hand';

  @override
  String get lowerHand => 'Lower hand';

  @override
  String get invitePeople => 'Invite people';

  @override
  String get roomChat => 'Room chat';

  @override
  String get stopRecording => 'Stop recording';

  @override
  String get startRecording => 'Start recording';

  @override
  String get mediaSettings => 'Media settings';

  @override
  String get editRoom => 'Edit room';

  @override
  String get manageMembers => 'Manage members';

  @override
  String get inviteSent => 'Invite sent.';

  @override
  String invitesSent(String count) {
    return '$count invites sent.';
  }

  @override
  String canTBeInvitedBecauseTheyDonTHaveAccessTo(String nameNameJoin) {
    return '$nameNameJoin can\'t be invited because they don\'t have access to voice rooms.';
  }

  @override
  String get couldnTSendTheInvite => 'Couldn\'t send the invite.';

  @override
  String inviteTo(String roomName) {
    return 'Invite to $roomName';
  }

  @override
  String get inviteByName => 'Invite by name';

  @override
  String get sendInvite => 'Send invite';

  @override
  String get peopleYouVeSharedThisRoomWith =>
      'People you\'ve shared this room with';

  @override
  String togetherRecently(String timeTogetherSuggestionTotalSeconds) {
    return '$timeTogetherSuggestionTotalSeconds together recently';
  }

  @override
  String get invited => 'Invited';

  @override
  String get invite => 'Invite';

  @override
  String get orShareAnInviteLink => 'Or share an invite link';

  @override
  String get linkCopiedToClipboard => 'Link copied to clipboard';

  @override
  String get participantVolumeVoiceroomview => 'Participant volume';

  @override
  String get microphone => 'Microphone';

  @override
  String get speaker => 'Speaker';

  @override
  String get camera => 'Camera';

  @override
  String get pushToTalk => 'Push to talk';

  @override
  String get holdSpaceWhileTheRoomIsFocused =>
      'Hold Space while the room is focused.';

  @override
  String get showMyStatusWhileInACall => 'Show my status while in a call';

  @override
  String get setsYourUserStatusToTheRoomYouAreIn =>
      'Sets your user status to the room you are in.';

  @override
  String get nativeNoiseSuppression => 'Native noise suppression';

  @override
  String get echoCancellationNoiseSuppressionAndAutomaticGainControlAreActive =>
      'Echo cancellation, noise suppression, and automatic gain control are active.';

  @override
  String get microphoneIsAvailable => 'Microphone is available.';

  @override
  String get couldnTTestTheMicrophonePleaseTryAgain =>
      'Couldn\'t test the microphone. Please try again.';

  @override
  String get testMicrophone => 'Test microphone';

  @override
  String get testing => 'Testing…';

  @override
  String messageDefaultVoiceroomview(String label) {
    return 'Default $label';
  }

  @override
  String get moderatorNotificationIsUnavailable =>
      'Moderator notification is unavailable.';

  @override
  String notifyModeratorsAbout(String username) {
    return 'Notify moderators about @$username';
  }

  @override
  String get whatShouldModeratorsKnow => 'What should moderators know?';

  @override
  String get notify => 'Notify';

  @override
  String get stopRecordingVoiceroomview => 'Stop recording?';

  @override
  String get startRecordingVoiceroomview => 'Start recording?';

  @override
  String get theCurrentRoomRecordingWillStop =>
      'The current room recording will stop.';

  @override
  String get everyParticipantWillSeeThatThisRoomIsBeingRecorded =>
      'Every participant will see that this room is being recorded.';

  @override
  String get stop => 'Stop';

  @override
  String get messageTheRoom => 'Message the room';

  @override
  String get noMessagesYetVoiceroomview => 'No messages yet.';

  @override
  String get loadOlderMessages => 'Load older messages';

  @override
  String get couldnTLoadTheRoomSMembers =>
      'Couldn\'t load the room\'s members.';

  @override
  String get couldnTRefreshTheRoomSMembers =>
      'Couldn\'t refresh the room\'s members.';

  @override
  String membersOf(String roomName) {
    return 'Members of $roomName';
  }

  @override
  String user(String membershipUserId) {
    return 'User $membershipUserId';
  }

  @override
  String get changeRole => 'Change role';

  @override
  String get removeMember => 'Remove member';

  @override
  String get username => 'Username';

  @override
  String get addMember => 'Add member';

  @override
  String assign(String targetName) {
    return 'Assign $targetName';
  }

  @override
  String editAssignment(String targetName) {
    return 'Edit $targetName assignment';
  }

  @override
  String dismissAssignment(String targetName) {
    return 'Dismiss $targetName assignment';
  }

  @override
  String get assignTopic => 'Assign topic';

  @override
  String get assignAssignmentsheet => 'Assign';

  @override
  String assignTo(String selectedIdentifier) {
    return 'Assign to @$selectedIdentifier';
  }

  @override
  String get unassign => 'Unassign';

  @override
  String get closeAssignment => 'Close assignment';

  @override
  String get chooseOnePersonOrGroup => 'Choose one person or group.';

  @override
  String get assignToAssignmentsheet => 'Assign to';

  @override
  String get searchUsersOrGroupsAssignmentsheet => 'Search users or groups…';

  @override
  String get group => 'Group';

  @override
  String get suggested => 'Suggested';

  @override
  String get searchResults => 'Search results';

  @override
  String get noMatchingUsersOrGroups => 'No matching users or groups.';

  @override
  String get tryADifferentNameOrUsername => 'Try a different name or username.';

  @override
  String selected(String selectedIdentifier) {
    return 'Selected: @$selectedIdentifier';
  }

  @override
  String get hideNote => 'Hide note';

  @override
  String get addANote => 'Add a note';

  @override
  String get editNote => 'Edit note';

  @override
  String get optional => 'Optional';

  @override
  String get noteOptional => 'Note (optional)';

  @override
  String get addContextForTheAssignee => 'Add context for the assignee…';

  @override
  String groupAssignmentsheet(String assignmentAssigneeGroupName) {
    return 'Group @$assignmentAssigneeGroupName';
  }

  @override
  String statusAssignmentsheet(String status) {
    return 'Status: $status';
  }

  @override
  String note(String note) {
    return 'Note: $note';
  }

  @override
  String assignedTo(String targetLabel, String assignmentAssigneeDisplayName) {
    return '$targetLabel assigned to $assignmentAssigneeDisplayName';
  }

  @override
  String get editAssignmentAssignmentsheet => 'Edit assignment';

  @override
  String get viewAllAssigned => 'View all assigned';

  @override
  String get notificationPreferences => 'Notification preferences';

  @override
  String get assignedToAssignmenttopiclist => 'Assigned to';

  @override
  String openTopicToViewAllAssignments(String allLength) {
    return 'Open topic to view all $allLength assignments';
  }

  @override
  String viewAllAssignmentsInTopic(String allLength) {
    return 'View all $allLength assignments in topic';
  }

  @override
  String get topic => 'Topic';

  @override
  String get post => 'Post';

  @override
  String get reconnectToThisForumToSeeAssignmentNotifications =>
      'Reconnect to this forum to see assignment notifications.';

  @override
  String get couldnTLoadAssignmentNotificationsFromThisForum =>
      'Couldn\'t load assignment notifications from this forum.';

  @override
  String get youDonTHaveAnyAssignmentsYet =>
      'You don’t have any assignments yet.';

  @override
  String get markAllUnreadAssignNotificationsAsRead =>
      'Mark all unread assign notifications as read';

  @override
  String get aGroup => 'a group';

  @override
  String areYouSureYouHaveUnreadAssign(
    String unreadCount,
    String notifications,
  ) {
    return 'Are you sure? You have $unreadCount unread assign $notifications.';
  }

  @override
  String get assignList => 'Assign list';

  @override
  String get assigned => 'Assigned';

  @override
  String get assignments => 'Assignments';

  @override
  String manageAssignmentTo(String directAssigneeDisplayName) {
    return 'Manage assignment to $directAssigneeDisplayName';
  }

  @override
  String get manageAssignments => 'Manage assignments';

  @override
  String assignedPost(num postAssignmentsLength) {
    String _temp0 = intl.Intl.pluralLogic(
      postAssignmentsLength,
      locale: localeName,
      other: '$postAssignmentsLength assigned posts',
      one: '$postAssignmentsLength assigned post',
    );
    return '$_temp0';
  }

  @override
  String get assignPost => 'Assign post';

  @override
  String get assignThisPost => 'Assign this post';

  @override
  String get editThisPostAssignment => 'Edit this post assignment';

  @override
  String assignedToAPost(String who) {
    return 'assigned $who to a post';
  }

  @override
  String unassignedFromAPost(String who) {
    return 'unassigned $who from a post';
  }

  @override
  String changedAssignmentDetailsFor(String who) {
    return 'changed assignment details for $who';
  }

  @override
  String changedAssignmentNoteFor(String who) {
    return 'changed assignment note for $who';
  }

  @override
  String changedAssignmentStatusFor(String who) {
    return 'changed assignment status for $who';
  }

  @override
  String get topicUnassignedAssignTopic => 'Topic unassigned. Assign topic';

  @override
  String openAssignplugin(String targetLabel) {
    return 'Open $targetLabel';
  }

  @override
  String assignedToAssignplugin(String targetLabel) {
    return 'Assigned to · $targetLabel';
  }

  @override
  String get changeAssignee => 'Change assignee';

  @override
  String changeAssignment(String actionTarget) {
    return 'Change $actionTarget assignment';
  }

  @override
  String get removeAssignment => 'Remove assignment';

  @override
  String removeAssignmentAssignplugin(String actionTarget) {
    return 'Remove $actionTarget assignment';
  }

  @override
  String assignmentRemoved(String targetLabel) {
    return '$targetLabel assignment removed';
  }

  @override
  String get undo => 'Undo';

  @override
  String postAssignplugin(String postNumber) {
    return 'Post #$postNumber';
  }

  @override
  String get reconnectToViewGroupAssignments =>
      'Reconnect to view group assignments.';

  @override
  String get couldnTLoadThisGroupSAssignedMembers =>
      'Couldn\'t load this group\'s assigned members.';

  @override
  String get reconnectToLoadMoreAssignedMembers =>
      'Reconnect to load more assigned members.';

  @override
  String get couldnTLoadMoreAssignedMembers =>
      'Couldn\'t load more assigned members.';

  @override
  String get couldnTLoadThisGroupSAssignments =>
      'Couldn\'t load this group\'s assignments.';

  @override
  String get reconnectToLoadMoreAssignments =>
      'Reconnect to load more assignments.';

  @override
  String get couldnTLoadMoreAssignments => 'Couldn\'t load more assignments.';

  @override
  String get assignment => 'Assignment';

  @override
  String get requiresPermissionToViewAssignments =>
      'Requires permission to view assignments.';

  @override
  String get unassigned => 'Unassigned';

  @override
  String get usernameOrGroupName => 'Username or group name';

  @override
  String get findTopicsAssignedToAPersonOrGroup =>
      'Find topics assigned to a person or group.';

  @override
  String get thisAssignmentTargetIsNoLongerAvailable =>
      'This assignment target is no longer available.';

  @override
  String get anAssignmentUpdateIsAlreadyInProgress =>
      'An assignment update is already in progress.';

  @override
  String get topics => 'Topics';

  @override
  String get filterAssignments => 'Filter assignments';

  @override
  String get wordsInTheTopicTitle => 'Words in the topic title';

  @override
  String get everyone => 'Everyone';

  @override
  String get loadMoreAssignments => 'Load more assignments';

  @override
  String get hidePersonSearch => 'Hide person search';

  @override
  String get findAssignedPerson => 'Find assigned person';

  @override
  String get noActiveAssignmentsMatchThisFilter =>
      'No active assignments match this filter.';

  @override
  String get related => 'Related';

  @override
  String get summarize => 'Summarize';

  @override
  String get topicSummary => 'Topic summary';

  @override
  String get couldnTGenerateThisSummary => 'Couldn\'t generate this summary.';

  @override
  String thisCommunityHasReachedItsAICreditLimitForTodayPlease(String reset) {
    return 'This community has reached its AI credit limit for today. Please try again after $reset or contact your site administrator for more information.';
  }

  @override
  String get thisCommunityHasReachedItsAICreditLimitForTodayResponses =>
      'This community has reached its AI credit limit for today. Responses will be unavailable until your limit resets. Please contact your site administrator for more information.';

  @override
  String get regeneratingSummary => 'Regenerating summary…';

  @override
  String get generatingSummary => 'Generating summary…';

  @override
  String thisSummaryIsOutdatedByNew(num summaryNewPostsSinceSummary) {
    String _temp0 = intl.Intl.pluralLogic(
      summaryNewPostsSinceSummary,
      locale: localeName,
      other:
          'This summary is outdated by $summaryNewPostsSinceSummary new posts.',
      one: 'This summary is outdated by $summaryNewPostsSinceSummary new post.',
    );
    return '$_temp0';
  }

  @override
  String get thisSummaryIsOutdated => 'This summary is outdated.';

  @override
  String generatedWith(String algorithm) {
    return 'Generated with $algorithm';
  }

  @override
  String get regenerate => 'Regenerate';

  @override
  String get proofreadingIsnTAvailableRightNowNothingWasPostedTryAgain =>
      'Proofreading isn\'t available right now. Nothing was posted. Try again to post without it.';

  @override
  String get thePostChangedWhileItWasBeingProofreadNothingWasPosted =>
      'The post changed while it was being proofread. Nothing was posted. Review it and try again.';

  @override
  String get summaryResponseHadNoSummary => 'Summary response had no summary.';

  @override
  String get proofread => 'Proofread';

  @override
  String get proofreadingResponseContainedNoSuggestion =>
      'Proofreading response contained no suggestion.';

  @override
  String aiSummaryStreamFailureType(String type) {
    return 'AiSummaryStreamFailure(type: $type)';
  }

  @override
  String get summaryStreamTimedOut => 'Summary stream timed out.';

  @override
  String get committed => 'Committed';

  @override
  String get opened => 'Opened';

  @override
  String get loadingEvents => 'Loading events';

  @override
  String get anEvent => 'an event';

  @override
  String isStartingSoon(String title) {
    return '$title is starting soon';
  }

  @override
  String isHappeningNow(String title) {
    return '$title is happening now';
  }

  @override
  String hasEnded(String title) {
    return '$title has ended';
  }

  @override
  String reminderFor(String title) {
    return 'Reminder for $title';
  }

  @override
  String yourAttendanceWasSetFor(String titleRow) {
    return 'Your attendance was set for $titleRow';
  }

  @override
  String setYourAttendanceAndInvitedYouTo(String titleRow) {
    return 'set your attendance and invited you to $titleRow';
  }

  @override
  String invitationTo(String titleRow) {
    return 'Invitation to $titleRow';
  }

  @override
  String invitedYouToEventnotifications(String titleRow) {
    return 'invited you to $titleRow';
  }

  @override
  String get topicCalendar => 'Topic calendar';

  @override
  String get openWebCalendar => 'Open web calendar';

  @override
  String get openTheOriginalTopicToViewThisCalendar =>
      'Open the original topic to view this calendar.';

  @override
  String get events => 'Events';

  @override
  String get eventFilter => 'Event filter';

  @override
  String get myEvents => 'My events';

  @override
  String get allEvents => 'All events';

  @override
  String get calendarView => 'Calendar view';

  @override
  String get allDay => 'All day';

  @override
  String get noEventsOnThisDay => 'No events on this day.';

  @override
  String get localTime => ' (local time)';

  @override
  String get event => 'Event';

  @override
  String get starts => 'Starts';

  @override
  String get endsOptional => 'Ends (optional)';

  @override
  String get repeatUntilOptional => 'Repeat until (optional)';

  @override
  String get allowedGroupsCommaSeparated => 'Allowed groups (comma separated)';

  @override
  String get meetingOrEventURL => 'Meeting or event URL';

  @override
  String get location => 'Location';

  @override
  String get maximumAttendeesOptional => 'Maximum attendees (optional)';

  @override
  String get remindersForExampleNotification15Minutes =>
      'Reminders (for example: notification.15.minutes)';

  @override
  String get eventImageURL => 'Event image URL';

  @override
  String get displayInTheEventTimezone => 'Display in the event timezone';

  @override
  String get minimalCard => 'Minimal card';

  @override
  String get enableEventChat => 'Enable event chat';

  @override
  String get enableLivestreamFromTheEventURL =>
      'Enable livestream from the event URL';

  @override
  String get thePostChangedWhileThisEditorWasOpenCloseItAnd =>
      'The post changed while this editor was open. Close it and reopen the event.';

  @override
  String get enterAStartDateAndTimeOrSelectAllDay =>
      'Enter a start date and time, or select All day.';

  @override
  String get enterAValidEndDate => 'Enter a valid end date.';

  @override
  String get chooseAValidTimezoneSuchAsEuropeParis =>
      'Choose a valid timezone, such as Europe/Paris.';

  @override
  String get enterValidDatesAndTimes => 'Enter valid dates and times.';

  @override
  String get theEventMustEndAfterItStarts =>
      'The event must end after it starts.';

  @override
  String get maximumAttendeesMustBeAPositiveWholeNumber =>
      'Maximum attendees must be a positive whole number.';

  @override
  String get chooseAtLeastOneAllowedGroupForAPrivateEvent =>
      'Choose at least one allowed group for a private event.';

  @override
  String get chooseDateAndTime => 'Choose date and time';

  @override
  String get addEvent => 'Add event';

  @override
  String get editEvent => 'Edit event';

  @override
  String get repeats => 'Repeats';

  @override
  String get doesNotRepeat => 'Does not repeat';

  @override
  String get participation => 'Participation';

  @override
  String get public => 'Public';

  @override
  String get privateGroups => 'Private groups';

  @override
  String get noAttendanceTracking => 'No attendance tracking';

  @override
  String get descriptionMarkdown => 'Description (Markdown)';

  @override
  String get moreOptions => 'More options';

  @override
  String get removeEvent => 'Remove event';

  @override
  String get anEventMustBeTheOnlyEventInTheFirstPost =>
      'An event must be the only event in the first post of a topic.';

  @override
  String get participantDetailsAreNoLongerAvailable =>
      'Participant details are no longer available.';

  @override
  String get closeParticipants => 'Close participants';

  @override
  String get participants => 'Participants';

  @override
  String get searchParticipants => 'Search participants';

  @override
  String participantsEventparticipants(
    String typeNull,
    String eventResponseLabelType,
  ) {
    String _temp0 = intl.Intl.selectLogic(typeNull, {
      'true': 'Participants: All',
      'other': 'Participants: $eventResponseLabelType',
    });
    return '$_temp0';
  }

  @override
  String get showingUpTo200PeopleSearchToNarrowTheList =>
      'Showing up to 200 people. Search to narrow the list.';

  @override
  String get unableToLoadParticipants => 'Unable to load participants';

  @override
  String get noParticipantsFound => 'No participants found';

  @override
  String get tryAnotherNameOrUsername => 'Try another name or username.';

  @override
  String get tryADifferentResponseFilter => 'Try a different response filter.';

  @override
  String get noParticipantsToShowYet => 'No participants to show yet.';

  @override
  String get showAllParticipants => 'Show all participants';

  @override
  String get loadingParticipants => 'Loading participants';

  @override
  String get everyOccurrence => 'Every occurrence';

  @override
  String get youCanNoLongerManageThisEvent =>
      'You can no longer manage this event.';

  @override
  String get unableToSendInvitations => 'Unable to send invitations.';

  @override
  String get sendEventNotificationsToTheseUsernamesForPrivateEventsAccessIs =>
      'Send event notifications to these usernames. For private events, access is still determined by the allowed groups.';

  @override
  String get usernamesSeparatedByCommas => 'Usernames, separated by commas';

  @override
  String get sendInvitations => 'Send invitations';

  @override
  String viewEventSchedule(String scheduleDescription) {
    return 'View event schedule: $scheduleDescription';
  }

  @override
  String get allDayEventtopictitle => ' · All day';

  @override
  String get eventSchedule => 'Event schedule';

  @override
  String get dateUnavailable => 'Date unavailable';

  @override
  String get ends => 'Ends';

  @override
  String get invalidEventResponse => 'Invalid event response';

  @override
  String get invalidEventList => 'Invalid event list';

  @override
  String get invalidParticipantList => 'Invalid participant list';

  @override
  String get upcomingEvents => 'Upcoming events';

  @override
  String get unableToLoadEventsTryRefreshingTheCalendar =>
      'Unable to load events. Try refreshing the calendar.';

  @override
  String get noEventsInThisPeriod => 'No events in this period.';

  @override
  String get chooseRecurringAttendance => 'Choose recurring attendance';

  @override
  String get thisOccurrenceOnly => 'This occurrence only';

  @override
  String get viewParticipants => 'View participants';

  @override
  String get openEventChat => 'Open event chat';

  @override
  String get private => 'Private';

  @override
  String get createdBy => '· Created by';

  @override
  String get eventActions => 'Event actions';

  @override
  String get removeMyResponse => 'Remove my response';

  @override
  String get exportCalendar => 'Export calendar';

  @override
  String get openEventOnWeb => 'Open event on web';

  @override
  String get bulkInvitationsAndReportsOnWeb =>
      'Bulk invitations and reports on web';

  @override
  String get openLivestream => 'Open livestream';

  @override
  String get thisEventIsClosed => 'This event is closed.';

  @override
  String get thisEventHasEnded => 'This event has ended.';

  @override
  String get thisEventIsAtCapacity => 'This event is at capacity.';

  @override
  String get connectToRespond => 'Connect to respond';

  @override
  String get loadingEvent => 'Loading event';

  @override
  String get refreshEvent => 'Refresh event';

  @override
  String get showLess => 'Show less';

  @override
  String get showFullDescription => 'Show full description';

  @override
  String get going => 'Going';

  @override
  String get interested => 'Interested';

  @override
  String get notGoing => 'Not going';

  @override
  String get thisEventHasNoDatesLeftToExport =>
      'This event has no dates left to export.';

  @override
  String get eventDetailsAreUnavailable => 'Event details are unavailable.';

  @override
  String get thisEventHasEndedEventtime => 'This event has ended';

  @override
  String allDayEventtime(String dateFormatStart) {
    return '$dateFormatStart · All day';
  }

  @override
  String allDayEventtimeValue(String dateFormatStart, String dateFormatEnd) {
    return '$dateFormatStart – $dateFormatEnd · All day';
  }

  @override
  String get everyDay => 'Every day';

  @override
  String get everyWeekday => 'Every weekday';

  @override
  String get everyWeek => 'Every week';

  @override
  String get everyTwoWeeks => 'Every two weeks';

  @override
  String get everyFourWeeks => 'Every four weeks';

  @override
  String get everyMonthOnTheSameWeekday => 'Every month on the same weekday';

  @override
  String get repeatingEvent => 'Repeating event';

  @override
  String get invalidCalendarResponse => 'Invalid calendar response';

  @override
  String get groupTimezonesReadOnly => 'Group timezones, read only';

  @override
  String get groupTimezones => 'Group timezones';

  @override
  String timezonesFor(String group) {
    return 'Timezones for $group';
  }

  @override
  String get groupMemberTimezonesAreNotAvailableHere =>
      'Group member timezones are not available here.';

  @override
  String get month => 'Month';

  @override
  String get day => 'Day';

  @override
  String get agenda => 'Agenda';

  @override
  String allDayTopiccalendar(String formatEventStart, String end) {
    return '$formatEventStart$end · All day';
  }

  @override
  String get noCalendarEntriesForThisDay => 'No calendar entries for this day.';

  @override
  String viewReply(String number) {
    return 'View reply #$number';
  }

  @override
  String get allWeekdaysAreHiddenInThisCalendar =>
      'All weekdays are hidden in this calendar.';

  @override
  String get calendarsWithHiddenWeekdaysAreNotSupported =>
      'Calendars with hidden weekdays are not supported.';

  @override
  String previousTopiccalendar(
    String viewCalendarViewAgenda,
    String viewLabel,
  ) {
    String _temp0 = intl.Intl.selectLogic(viewCalendarViewAgenda, {
      'true': 'Previous month',
      'other': 'Previous $viewLabel',
    });
    return '$_temp0';
  }

  @override
  String nextTopiccalendar(String viewCalendarViewAgenda, String viewLabel) {
    String _temp0 = intl.Intl.selectLogic(viewCalendarViewAgenda, {
      'true': 'Next month',
      'other': 'Next $viewLabel',
    });
    return '$_temp0';
  }

  @override
  String get noCalendarEntriesThisMonth => 'No calendar entries this month.';

  @override
  String get noCalendarEntriesInThisView => 'No calendar entries in this view.';

  @override
  String moreEntries(String numberOfHiddenRows) {
    return '$numberOfHiddenRows more entries';
  }

  @override
  String get calendarTimezone => 'Calendar timezone';

  @override
  String get searchTimezones => 'Search timezones';

  @override
  String get goingInterestedNotGoing => 'going|interested|not going';

  @override
  String get schedule => 'Schedule';

  @override
  String get year => 'Year';

  @override
  String get attributeValuesCannotContainLineBreaksOrBothKindsOfQuotation =>
      'Attribute values cannot contain line breaks or both kinds of quotation mark.';

  @override
  String get calendarEntry => 'Calendar entry';

  @override
  String get unableToLoadThisEventTryAgain =>
      'Unable to load this event. Try again.';

  @override
  String get unableToConfirmTheChangeTheEventHasBeenRefreshedCheck =>
      'Unable to confirm the change. The event has been refreshed; check your response before trying again.';

  @override
  String get solution => 'Solution';

  @override
  String get findSolvedTopicsOrUnsolvedTopicsInCategoriesThatSupportSolutions =>
      'Find solved topics or unsolved topics in categories that support solutions.';

  @override
  String get solved => 'Solved';

  @override
  String get unsolved => 'Unsolved';

  @override
  String get alwaysVisible => 'Always visible';

  @override
  String get afterVoting => 'After voting';

  @override
  String get afterThePollCloses => 'After the poll closes';

  @override
  String get staffOnly => 'Staff only';

  @override
  String get unknown => 'Unknown';

  @override
  String get theSitePollOptionLimitIsUnavailable =>
      'The site poll option limit is unavailable.';

  @override
  String get rankedChoicePollsCanOnlyBeCreatedOnTheWeb =>
      'Ranked-choice polls can only be created on the web.';

  @override
  String get theTypeOfAnExistingRankedChoicePollCannotChange =>
      'The type of an existing ranked-choice poll cannot change.';

  @override
  String get thisPollTypeCanOnlyBeEditedAsRawSource =>
      'This poll type can only be edited as raw source.';

  @override
  String get onlyStaffCanMakePollResultsStaffOnly =>
      'Only staff can make poll results staff-only.';

  @override
  String get automaticCloseMustBeAValidISO8601DateAndTime =>
      'Automatic close must be a valid ISO-8601 date and time.';

  @override
  String get minimumMustBeZeroOrGreater => 'Minimum must be zero or greater.';

  @override
  String get maximumMustBeGreaterThanOrEqualToMinimum =>
      'Maximum must be greater than or equal to minimum.';

  @override
  String get stepMustBeAtLeast1 => 'Step must be at least 1.';

  @override
  String get aNumberPollMustGenerateAtLeastTwoOptions =>
      'A number poll must generate at least two options.';

  @override
  String aPollCanHaveAtMostGeneratedOptions(String maximumOptions) {
    return 'A poll can have at most $maximumOptions generated options.';
  }

  @override
  String get everyOptionNeedsText => 'Every option needs text.';

  @override
  String get aPollNeedsAtLeastTwoOptions =>
      'A poll needs at least two options.';

  @override
  String aPollCanHaveAtMostOptions(String maximumOptions) {
    return 'A poll can have at most $maximumOptions options.';
  }

  @override
  String get pollOptionsMustBeUnique => 'Poll options must be unique.';

  @override
  String get multipleChoiceRequires1MinimumMaximumOptionCountWithMinimumBelow =>
      'Multiple choice requires 1 ≤ minimum ≤ maximum ≤ option count, with minimum below the option count.';

  @override
  String get theComposerChangedWhileThisPollWasOpenNothingWasChanged =>
      'The composer changed while this poll was open. Nothing was changed.';

  @override
  String get addPoll => 'Add poll';

  @override
  String get editPoll => 'Edit poll';

  @override
  String get thisPollMayAlreadyHaveVotes => 'This poll may already have votes.';

  @override
  String thisPollHas(num voterCount) {
    String _temp0 = intl.Intl.pluralLogic(
      voterCount,
      locale: localeName,
      other: 'This poll has $voterCount voters.',
      one: 'This poll has $voterCount voter.',
    );
    return '$_temp0';
  }

  @override
  String get removePublishedPoll => 'Remove published poll?';

  @override
  String removingItWillRemoveThePollFromThePost(String detail) {
    return '$detail Removing it will remove the poll from the post.';
  }

  @override
  String get removePoll => 'Remove poll';

  @override
  String get titleOptional => 'Title (optional)';

  @override
  String get lunchChoice => 'Lunch choice';

  @override
  String get rankedChoicePollsKeepTheirTypeVotingRemainsAvailableOnThe =>
      'Ranked-choice polls keep their type. Voting remains available on the web.';

  @override
  String get publicVoterIdentities => 'Public voter identities';

  @override
  String get theVoterListItselfIsShownOnTheWebInThis =>
      'The voter list itself is shown on the web in this version.';

  @override
  String get automaticClose => 'Automatic close';

  @override
  String get closeDateAndTime => 'Close date and time';

  @override
  String get iSO8601InThisDeviceSTimeZoneUnlessOneIs =>
      'ISO 8601, in this device\'s time zone unless one is given';

  @override
  String get pollType => 'Poll type';

  @override
  String get singleChoice => 'Single choice';

  @override
  String get multipleChoice => 'Multiple choice';

  @override
  String get number => 'Number';

  @override
  String get rankedChoice => 'Ranked choice';

  @override
  String optionPollcomposersheet(String index) {
    return 'Option $index';
  }

  @override
  String get moveOptionUp => 'Move option up';

  @override
  String get moveOptionDown => 'Move option down';

  @override
  String get removeOption => 'Remove option';

  @override
  String get addOption => 'Add option';

  @override
  String get minimumChoices => 'Minimum choices';

  @override
  String get maximumChoices => 'Maximum choices';

  @override
  String get numberRange => 'Number range';

  @override
  String get minimum => 'Minimum';

  @override
  String get step => 'Step';

  @override
  String get optionsAreGeneratedInclusivelyFromThisRange =>
      'Options are generated inclusively from this range.';

  @override
  String get showResults => 'Show results';

  @override
  String preserve(String draftResultsSource) {
    return 'Preserve “$draftResultsSource”';
  }

  @override
  String get automaticCloseNeedsADateAndTime =>
      'Automatic close needs a date and time.';

  @override
  String get minimumMaximumAndStepMustBeWholeNumbers =>
      'Minimum, maximum, and step must be whole numbers.';

  @override
  String get poll => 'Poll';

  @override
  String get theComposerChangedBeforeThisPollCouldBeRemovedNothingWas =>
      'The composer changed before this poll could be removed. Nothing was changed.';

  @override
  String get couldnTSaveThatVote => 'Couldn\'t save that vote.';

  @override
  String get polls => 'Polls';

  @override
  String get findPostsContainingPolls => 'Find posts containing polls.';

  @override
  String get containsAPoll => 'Contains a poll';

  @override
  String pollPollcomposerpill(
    String nullTitleIsEmpty,
    String optionCount,
    String noun,
    String title,
  ) {
    String _temp0 = intl.Intl.selectLogic(nullTitleIsEmpty, {
      'true': 'Poll · Untitled · $optionCount $noun',
      'other': 'Poll · $title · $optionCount $noun',
    });
    return '$_temp0';
  }

  @override
  String get votingIsUnavailableInArchivedTopics =>
      'Voting is unavailable in archived topics.';

  @override
  String get thisPollIsClosed => 'This poll is closed.';

  @override
  String get thisPollHasAnUnsupportedStatusAndIsReadOnly =>
      'This poll has an unsupported status and is read only.';

  @override
  String get votingIsUnavailableBecauseThisTopicIsArchived =>
      'Voting is unavailable because this topic is archived.';

  @override
  String get connectAnAccountToVote => 'Connect an account to vote.';

  @override
  String get yourGroupMembershipCouldNotBeConfirmedSoThisPollIs =>
      'Your group membership could not be confirmed, so this poll is read only.';

  @override
  String onlyMembersOfCanVoteInThisPoll(String humanListPollGroups) {
    return 'Only members of $humanListPollGroups can vote in this poll.';
  }

  @override
  String weightedAverage(String formatAverageCalculateNumberPollAverageP) {
    return 'Weighted average: $formatAverageCalculateNumberPollAverageP';
  }

  @override
  String chooseExactly(String multipleMin) {
    return 'Choose exactly $multipleMin.';
  }

  @override
  String chooseBetweenAndOptions(String multipleMin, String multipleMax) {
    return 'Choose between $multipleMin and $multipleMax options.';
  }

  @override
  String get removeVotes => 'Remove votes';

  @override
  String get castVotes => 'Cast votes';

  @override
  String get rankedChoiceVotingIsAvailableOnTheWeb =>
      'Ranked-choice voting is available on the web.';

  @override
  String get thisPollTypeIsReadOnlyInTheAppYouCan =>
      'This poll type is read only in the app. You can vote on the web.';

  @override
  String get thisPollHasNoOptionsThatCanBeDisplayed =>
      'This poll has no options that can be displayed.';

  @override
  String get savingVote => 'Saving vote…';

  @override
  String get voteOnWeb => 'Vote on web';

  @override
  String get connectAccount => 'Connect account';

  @override
  String get resultsWillBeShownWhenThisPollCloses =>
      'Results will be shown when this poll closes.';

  @override
  String get resultsAreNotAvailable => 'Results are not available.';

  @override
  String get voteToSeeResults => 'Vote to see results.';

  @override
  String get resultsAreVisibleToStaff => 'Results are visible to staff.';

  @override
  String get message1Voter => '1 voter';

  @override
  String get privateVoterIdentities => 'Private voter identities';

  @override
  String get dynamicOptions => 'Dynamic options';

  @override
  String restrictedTo(String humanListPollGroups) {
    return 'Restricted to $humanListPollGroups';
  }

  @override
  String get automaticallyClosed => 'Automatically closed';

  @override
  String get message1Vote => '1 vote';

  @override
  String get tieBetween => 'Tie between';

  @override
  String get winner => 'Winner';

  @override
  String get rankedChoiceResultsAreNotAvailableYet =>
      'Ranked-choice results are not available yet.';

  @override
  String automaticallyClosedAt(String date, String time) {
    return 'Automatically closed $date at $time.';
  }

  @override
  String closesAt(String date, String time) {
    return 'Closes $date at $time.';
  }

  @override
  String get pollReadOnly => 'Poll, read only';

  @override
  String get thisPollCannotBeDisplayedInteractively =>
      'This poll cannot be displayed interactively.';

  @override
  String get unavailable => 'Unavailable';

  @override
  String get spoiler => ' Spoiler ';

  @override
  String get details => 'Details';

  @override
  String get removeDraft => 'Remove draft?';

  @override
  String willBePermanentlyRemovedFromThisAccount(String draftDisplayTitle) {
    return '“$draftDisplayTitle” will be permanently removed from this account.';
  }

  @override
  String get connectThisAccountToSeeItsDrafts =>
      'Connect this account to see its drafts';

  @override
  String get noDraftsYet => 'No drafts yet';

  @override
  String get repliesAndTopicsYouStartWritingWillAppearHere =>
      'Replies and topics you start writing will appear here.';

  @override
  String get loadingDrafts => 'Loading drafts';

  @override
  String get removeDraftDraftlist => 'Remove draft';

  @override
  String get closeSettings => 'Close settings';

  @override
  String get preferencesForAllYourForums => 'Preferences for all your forums.';

  @override
  String get limitContentSize => 'Limit content size';

  @override
  String get centerContentInEachPanelWithAMaximumWidthOf825 =>
      'Center content in each panel with a maximum width of 825 px.';

  @override
  String get disableGIFAnimations => 'Disable GIF animations';

  @override
  String get pauseGIFsByDefaultInPostsAndChatMessages =>
      'Pause GIFs by default in posts and chat messages.';

  @override
  String get couldNotSaveTheFont => 'Could not save the font.';

  @override
  String get font => 'Font';

  @override
  String get usedForReadingAndWritingInEveryForum =>
      'Used for reading and writing in every forum.';

  @override
  String get theQuickBrownFoxJumpsOverTheLazyDog =>
      'The quick brown fox jumps over the lazy dog.';

  @override
  String get couldNotSaveTheEffects => 'Could not save the effects.';

  @override
  String get effects => 'Effects';

  @override
  String get drawnOverTheColoursOfEveryForum =>
      'Drawn over the colours of every forum.';

  @override
  String get textSize => 'Text size';

  @override
  String get textSizeControls => 'Text size controls';

  @override
  String get decreaseTextSize => 'Decrease text size';

  @override
  String get currentTextSize => 'Current text size';

  @override
  String get increaseTextSize => 'Increase text size';

  @override
  String get shortcuts => 'Shortcuts:';

  @override
  String get toResize => 'to resize ·';

  @override
  String get toReset => 'to reset';

  @override
  String get keyboardShortcuts => 'Keyboard shortcuts';

  @override
  String get shiftJAndShiftKSelectTopicsWithoutOpeningThemJ =>
      'Shift+J and Shift+K select topics without opening them. J and K move through posts in the open topic. When no topic is open, J and K select topics in the list. G then J or K opens the next or previous topic. Navigation shortcuts pause while you type or use a menu.';

  @override
  String get backInCurrentTab => 'Back in current tab';

  @override
  String get forwardInCurrentTab => 'Forward in current tab';

  @override
  String get refreshCurrentTab => 'Refresh current tab';

  @override
  String get newTopic => 'New topic';

  @override
  String get replyToTopic => 'Reply to topic';

  @override
  String get bookmarkTopic => 'Bookmark topic';

  @override
  String get submitComposer => 'Submit composer';

  @override
  String get closeComposer => 'Close composer';

  @override
  String get globalSearch => 'Global search';

  @override
  String get contextualSearch => 'Contextual search';

  @override
  String get useASingleLineForTheSummary =>
      'Use a single line for the summary.';

  @override
  String get theSummaryContainsTooManyQuotationStyles =>
      'The summary contains too many quotation styles.';

  @override
  String get thePlatformVideoPlayerFailed =>
      'The platform video player failed.';

  @override
  String get couldnTOpenTheDestinationTopic =>
      'Couldn\'t open the destination topic.';

  @override
  String get movePosts => 'Move posts';

  @override
  String moveSelected(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Move $count selected posts.',
      one: 'Move $count selected post.',
    );
    return '$_temp0';
  }

  @override
  String get existingMessage => 'Existing message';

  @override
  String get existingTopic => 'Existing topic';

  @override
  String get createAndMove => 'Create and move';

  @override
  String get messageTitle => 'Message title';

  @override
  String get topicTitle => 'Topic title';

  @override
  String get defaultCategory => 'Default category';

  @override
  String get searchByMessageTitleOrID => 'Search by message title or ID';

  @override
  String get searchByTopicTitleOrID => 'Search by topic title or ID';

  @override
  String get searchForADestinationTopic => 'Search for a destination topic.';

  @override
  String get searchForADestinationMessage =>
      'Search for a destination message.';

  @override
  String get noTopicsFound => 'No topics found.';

  @override
  String get noMessagesFound => 'No messages found.';

  @override
  String get messageTopicmoveposts => 'Message';

  @override
  String get preserveChronologicalOrder => 'Preserve chronological order';

  @override
  String get toDo => 'To-do';

  @override
  String get moveUp => 'Move up';

  @override
  String get moveDown => 'Move down';

  @override
  String get dragToMoveOrClickToOpenMenu =>
      'Drag to move or click to open menu';

  @override
  String get addBlock => 'Add block';

  @override
  String get emptyParagraphActions => 'Empty paragraph actions';

  @override
  String get list => 'List';

  @override
  String get listItemContent => 'List item content';

  @override
  String get quote => 'Quote';

  @override
  String get gallery => 'Gallery';

  @override
  String get image => 'Image';

  @override
  String get theDraftChangedMoveTheBlockAgain =>
      'The draft changed. Move the block again.';

  @override
  String get communityNavigation => 'Community navigation';

  @override
  String get navigation => 'Navigation';

  @override
  String get loadingTopicDetails => 'Loading topic details';

  @override
  String get loadingTopicActivity => 'Loading topic activity';

  @override
  String get loadingTopicTitle => 'Loading topic title';

  @override
  String get topicClosed => 'Topic closed';

  @override
  String get latestTopics => 'Latest topics';

  @override
  String backToList(String content) {
    return 'Back to $content list';
  }

  @override
  String collapseTopicinboxheader(String content) {
    return 'Collapse $content';
  }

  @override
  String get minRead => 'min read';

  @override
  String get lastActivityJustNow => 'last activity just now';

  @override
  String lastActivityAgo(String age) {
    return 'last activity $age ago';
  }

  @override
  String get topicReminders => 'Topic reminders';

  @override
  String get removeSubcategory => 'Remove subcategory';

  @override
  String get moveToUncategorized => 'Move to Uncategorized';

  @override
  String get subcategory => '+ Subcategory';

  @override
  String get categoryTopicinboxheader => '+ Category';

  @override
  String browseTopicinboxheader(String valueName) {
    return 'Browse $valueName';
  }

  @override
  String get editTopicSubcategory => 'Edit topic subcategory';

  @override
  String get editTopicCategory => 'Edit topic category';

  @override
  String get savingCategory => 'Saving category';

  @override
  String browseTopicinboxheaderValue(String categoryName) {
    return 'Browse $categoryName';
  }

  @override
  String dismissTopicinboxheader(String sectionLabel) {
    return 'Dismiss $sectionLabel';
  }

  @override
  String get none => 'None';

  @override
  String get backMouseBackButton => 'Back (mouse back button)';

  @override
  String get forwardMouseForwardButton => 'Forward (mouse forward button)';

  @override
  String get forward => 'Forward';

  @override
  String couldnTLoad(String routeIsDirectory) {
    String _temp0 = intl.Intl.selectLogic(routeIsDirectory, {
      'true': 'Couldn\'t load badges.',
      'other': 'Couldn\'t load this badge.',
    });
    return '$_temp0';
  }

  @override
  String get couldnTLoadBadgeRecipients => 'Couldn\'t load badge recipients.';

  @override
  String get dismissTagsPicker => 'Dismiss tags picker';

  @override
  String get tags => 'Tags';

  @override
  String get couldnTLoadTags => 'Couldn\'t load tags.';

  @override
  String get findOrAddTags => 'Find or add tags…';

  @override
  String createNewTag(String newTagName) {
    return 'Create new tag: “$newTagName”';
  }

  @override
  String openTag(String tagName) {
    return 'Open tag $tagName';
  }

  @override
  String get noTagsAvailable => 'No tags available.';

  @override
  String get noMatchingTags => 'No matching tags.';

  @override
  String loadingDirectoryskeleton(String kindName) {
    return 'Loading $kindName';
  }

  @override
  String reconnectToToSeeNotifications(String instanceHost) {
    return 'Reconnect to $instanceHost to see notifications.';
  }

  @override
  String couldnTLoadNotificationsFrom(String instanceHost) {
    return 'Couldn\'t load notifications from $instanceHost.';
  }

  @override
  String reconnectToToSeeReplies(String instanceHost) {
    return 'Reconnect to $instanceHost to see replies.';
  }

  @override
  String couldnTLoadRepliesFrom(String instanceHost) {
    return 'Couldn\'t load replies from $instanceHost.';
  }

  @override
  String reconnectToToSeeLikes(String instanceHost) {
    return 'Reconnect to $instanceHost to see likes.';
  }

  @override
  String couldnTLoadLikesFrom(String instanceHost) {
    return 'Couldn\'t load likes from $instanceHost.';
  }

  @override
  String reconnectToToSeeOtherNotifications(String instanceHost) {
    return 'Reconnect to $instanceHost to see other notifications.';
  }

  @override
  String couldnTLoadOtherNotificationsFrom(String instanceHost) {
    return 'Couldn\'t load other notifications from $instanceHost.';
  }

  @override
  String notAllowedTryReconnectingTo(String instanceHost) {
    return 'Not allowed — try reconnecting to $instanceHost.';
  }

  @override
  String couldnTReach(String instanceHost) {
    return 'Couldn\'t reach $instanceHost.';
  }

  @override
  String reconnectToToSeeYourBookmarks(String instanceHost) {
    return 'Reconnect to $instanceHost to see your bookmarks.';
  }

  @override
  String couldnTLoadBookmarksFrom(String instanceHost) {
    return 'Couldn\'t load bookmarks from $instanceHost.';
  }

  @override
  String reconnectToToSeeYourActivity(String instanceHost) {
    return 'Reconnect to $instanceHost to see your activity.';
  }

  @override
  String couldnTLoadActivityFrom(String instanceHost) {
    return 'Couldn\'t load activity from $instanceHost.';
  }

  @override
  String couldnTLoadTopicfeedcontroller(String instanceHost) {
    return 'Couldn\'t load $instanceHost.';
  }

  @override
  String couldnTLoadMoreTopicsFrom(String instanceHost) {
    return 'Couldn\'t load more topics from $instanceHost.';
  }

  @override
  String get unknownGroupRoute => 'Unknown group route.';

  @override
  String leaveGrouppageshost(String groupLabel) {
    return 'Leave $groupLabel?';
  }

  @override
  String get youWonTBeAbleToJoinItAgainOnYour =>
      'You won\'t be able to join it again on your own.';

  @override
  String get leaveGroup => 'Leave group';

  @override
  String get updateExistingMembers => 'Update existing members?';

  @override
  String thisChangeAlsoAffectsTheNotificationPreferencesOfExistingApplyIt(
    String userCount,
    String members,
  ) {
    return 'This change also affects the notification preferences of $userCount existing $members. Apply it to them too?';
  }

  @override
  String get onlyNewMembers => 'Only new members';

  @override
  String update(String userCount, String members) {
    return 'Update $userCount $members';
  }

  @override
  String requestToJoin(String groupLabel) {
    return 'Request to join $groupLabel';
  }

  @override
  String get reason => 'Reason';

  @override
  String get sendRequest => 'Send request';

  @override
  String get yesterday => 'Yesterday';

  @override
  String get lastWeek => 'Last week';

  @override
  String get lastMonth => 'Last month';

  @override
  String get lastYear => 'Last year';

  @override
  String get markNotificationsAsRead => 'Mark notifications as read?';

  @override
  String get couldnTMarkNotificationsAsReadTryAgain =>
      'Couldn\'t mark notifications as read. Try again.';

  @override
  String get loadingNotifications => 'Loading notifications';

  @override
  String get youHavenTReceivedAnyLikesYet =>
      'You haven\'t received any likes yet.';

  @override
  String get youDonTHaveAnyOtherNotificationsYet =>
      'You don’t have any other notifications yet.';

  @override
  String get nothingNew => 'Nothing new.';

  @override
  String get noTopicsFoundTryAnotherSearchOrChangeTheFilters =>
      'No topics found. Try another search or change the filters.';

  @override
  String get youReAllCaughtUp => 'You\'re all caught up.';

  @override
  String get nothingHereYet => 'Nothing here yet.';

  @override
  String get loadingMessages => 'Loading messages';

  @override
  String get loadingFilteredTopics => 'Loading filtered topics';

  @override
  String get loadingTopics => 'Loading topics';

  @override
  String get newTopicTopiclistview => 'new topic';

  @override
  String get newOrUpdatedTopic => 'new or updated topic';

  @override
  String see(num count, String noun) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'See $count ${noun}s',
      one: 'See $count $noun',
    );
    return '$_temp0';
  }

  @override
  String get categoryPath => 'Category path';

  @override
  String parentCategory(String parentName) {
    return 'Parent category: $parentName';
  }

  @override
  String categoryTopiclistview(String categoryName) {
    return 'Category: $categoryName';
  }

  @override
  String tag(String tagName) {
    return 'Tag: $tagName';
  }

  @override
  String get badgesAreDisabledOnThisForum =>
      'Badges are disabled on this forum.';

  @override
  String get thisGroupFeatureIsUnavailable =>
      'This group feature is unavailable.';

  @override
  String get unknownGroupSection => 'Unknown group section.';

  @override
  String get theGroupCouldNotBeDeleted => 'The group could not be deleted.';

  @override
  String get joinGroup => 'Join group';

  @override
  String get requestToJoinGrouppage => 'Request to join';

  @override
  String get groupActions => 'Group actions';

  @override
  String get deleteGroup => 'Delete group';

  @override
  String get moreGroupActions => 'More group actions';

  @override
  String get owner => 'Owner';

  @override
  String get member => 'Member';

  @override
  String get deleteGroupGrouppage => 'Delete group?';

  @override
  String thisCannotBeUndoneTypeToConfirm(String groupName) {
    return 'This cannot be undone. Type “$groupName” to confirm.';
  }

  @override
  String get groupName => 'Group name';

  @override
  String get deletePermanently => 'Delete permanently';

  @override
  String get activity => 'Activity';

  @override
  String get requests => 'Requests';

  @override
  String get manage => 'Manage';

  @override
  String get permissions => 'Permissions';

  @override
  String notificationCounterIsNotRegistered(String idId) {
    return 'Notification counter $idId is not registered.';
  }

  @override
  String pluginCannotUpdateNotificationCounter(String consumer, String idId) {
    return 'Plugin $consumer cannot update notification counter $idId.';
  }

  @override
  String pluginCannotBuildComposerTarget(
    String consumer,
    String requestKindId,
  ) {
    return 'Plugin $consumer cannot build composer target $requestKindId.';
  }

  @override
  String timedOut(String description) {
    return 'Timed out $description.';
  }

  @override
  String get reconnectToDismissNewTopics => 'Reconnect to dismiss new topics.';

  @override
  String get couldNotDismissNewTopicsPleaseTryAgain =>
      'Could not dismiss new topics. Please try again.';

  @override
  String get couldnTLoadThePresenceSettingTryAgain =>
      'Couldn\'t load the presence setting. Try again.';

  @override
  String noLongerAcceptsThisSignInSignInAgainToContinue(String host) {
    return '$host no longer accepts this sign-in. Sign in again to continue.';
  }

  @override
  String theSignInForIsNoLongerSavedOnThisDevice(String host) {
    return 'The sign-in for $host is no longer saved on this device. Sign in again to continue.';
  }

  @override
  String get reconnectThisAccountToLoadItsPresenceSetting =>
      'Reconnect this account to load its presence setting.';

  @override
  String get couldnTUpdatePresenceCheckTheConnectionAndTryAgain =>
      'Couldn\'t update presence. Check the connection and try again.';

  @override
  String get theSiteDidnTAcceptThatPresenceSetting =>
      'The site didn\'t accept that presence setting.';

  @override
  String tooFastTryChangingPresenceAgainInS(String waitInSeconds) {
    return 'Too fast — try changing presence again in ${waitInSeconds}s.';
  }

  @override
  String get tooFastTryChangingPresenceAgainInAMoment =>
      'Too fast — try changing presence again in a moment.';

  @override
  String get presenceCouldNotBeChangedReconnectThisAccountAndTryAgain =>
      'Presence could not be changed. Reconnect this account and try again.';

  @override
  String get presenceChangedSomewhereElseTryAgainToUseThisSetting =>
      'Presence changed somewhere else. Try again to use this setting.';

  @override
  String get customStatusIsNotAvailableForThisAccount =>
      'Custom status is not available for this account.';

  @override
  String get anotherStatusChangeIsStillFinishing =>
      'Another status change is still finishing.';

  @override
  String get chooseATimeInTheFuture => 'Choose a time in the future.';

  @override
  String get users => 'Users';

  @override
  String get thisTopicCanNoLongerBeChanged =>
      'This topic can no longer be changed.';

  @override
  String get thisTopicDoesNotOfferAPinPreference =>
      'This topic does not offer a pin preference.';

  @override
  String get anotherPinChangeIsStillFinishing =>
      'Another pin change is still finishing.';

  @override
  String get thisMessageCanNoLongerBeMoved =>
      'This message can no longer be moved.';

  @override
  String get anotherInboxActionIsStillFinishing =>
      'Another inbox action is still finishing.';

  @override
  String get theAccountHasChanged => 'The account has changed.';

  @override
  String get thisTopicCanNoLongerBeChangedThatWay =>
      'This topic can no longer be changed that way.';

  @override
  String get anotherTopicActionIsStillFinishing =>
      'Another topic action is still finishing.';

  @override
  String get thisTopicCannotBeDeleted => 'This topic cannot be deleted.';

  @override
  String get thisTopicCannotBeRecovered => 'This topic cannot be recovered.';

  @override
  String get couldnTLoadThisTopicSSummary =>
      'Couldn\'t load this topic\'s summary.';

  @override
  String get thisPostCanNoLongerBeEdited =>
      'This post can no longer be edited.';

  @override
  String get openTheFullEditorToEditLocalizedContent =>
      'Open the full editor to edit localized content.';

  @override
  String get theSelectedTextCouldNotBeMatchedSafely =>
      'The selected text could not be matched safely.';

  @override
  String get anotherActionOnThisPostIsStillBeingSaved =>
      'Another action on this post is still being saved.';

  @override
  String get theTopicChangedBeforeTheEditCouldBeSaved =>
      'The topic changed before the edit could be saved.';

  @override
  String get thisTopicCanNoLongerBeEdited =>
      'This topic can no longer be edited.';

  @override
  String get aTopicTitleIsRequired => 'A topic title is required.';

  @override
  String get theForumChangedBeforeTheTitleSaved =>
      'The forum changed before the title saved.';

  @override
  String get theForumChangedBeforeTheCategorySaved =>
      'The forum changed before the category saved.';

  @override
  String get topicTagsCanNoLongerBeEdited =>
      'Topic tags can no longer be edited.';

  @override
  String get theSiteChangedBeforeTagsWereSaved =>
      'The site changed before tags were saved.';

  @override
  String get moreEmoji => 'More emoji';

  @override
  String get yourConnectionChangedReopenMovePostsAndTryAgain =>
      'Your connection changed. Reopen Move posts and try again.';

  @override
  String get yourConnectionChangedReopenChangeOwnerAndTryAgain =>
      'Your connection changed. Reopen Change owner and try again.';

  @override
  String get yourConnectionChangedReopenTheActionAndTryAgain =>
      'Your connection changed. Reopen the action and try again.';

  @override
  String get thisPostCannotBePermanentlyDeleted =>
      'This post cannot be permanently deleted.';

  @override
  String get thisPostCannotBePermanentlyDeletedYet =>
      'This post cannot be permanently deleted yet.';

  @override
  String get yourConnectionChangedReopenThePostNoticeAndTryAgain =>
      'Your connection changed. Reopen the post notice and try again.';

  @override
  String get thisPostNoticeCanNoLongerBeEdited =>
      'This post notice can no longer be edited.';

  @override
  String get thisPostCanNoLongerBeFlagged =>
      'This post can no longer be flagged.';

  @override
  String get yourConnectionChangedReopenTheFlagFormAndTryAgain =>
      'Your connection changed. Reopen the flag form and try again.';

  @override
  String get thisTopicCanNoLongerBeFlagged =>
      'This topic can no longer be flagged.';

  @override
  String get anotherFlagOnThisTopicIsStillBeingSaved =>
      'Another flag on this topic is still being saved.';

  @override
  String get anotherPostActionIsStillFinishing =>
      'Another post action is still finishing.';

  @override
  String get reconnectToThisForumToBookmarkIt =>
      'Reconnect to this forum to bookmark it.';

  @override
  String get thisBookmarkTargetRequiresItsOwningContext =>
      'This bookmark target requires its owning context.';

  @override
  String get thisBookmarkTargetIsNotAvailableInThisBuild =>
      'This bookmark target is not available in this build.';

  @override
  String get anotherActionOnThisBookmarkIsStillFinishing =>
      'Another action on this bookmark is still finishing.';

  @override
  String get theForumChangedBeforeTheBookmarkFinished =>
      'The forum changed before the bookmark finished.';

  @override
  String couldnTConfirmWhetherTheBookmarkWasCreatedTheIsBeing(
    String refreshTarget,
  ) {
    return 'Couldn\'t confirm whether the bookmark was created. The $refreshTarget is being refreshed.';
  }

  @override
  String get theBookmarkWasSavedOnTheForum =>
      'The bookmark was saved on the forum.';

  @override
  String get thisBookmarkCannotBeEditedHere =>
      'This bookmark cannot be edited here.';

  @override
  String couldnTConfirmTheBookmarkChangesTheIsBeingRefreshed(
    String refreshTarget,
  ) {
    return 'Couldn\'t confirm the bookmark changes. The $refreshTarget is being refreshed.';
  }

  @override
  String get theBookmarkWasUpdatedOnTheForum =>
      'The bookmark was updated on the forum.';

  @override
  String get thisBookmarkCannotBeDeletedHere =>
      'This bookmark cannot be deleted here.';

  @override
  String couldnTConfirmTheDeletionTheIsBeingRefreshed(String refreshTarget) {
    return 'Couldn\'t confirm the deletion. The $refreshTarget is being refreshed.';
  }

  @override
  String get theBookmarkWasDeletedOnTheForum =>
      'The bookmark was deleted on the forum.';

  @override
  String get reconnectToThisForumToDeleteItsBookmarks =>
      'Reconnect to this forum to delete its bookmarks.';

  @override
  String get anotherBookmarkActionIsStillFinishing =>
      'Another bookmark action is still finishing.';

  @override
  String get theForumChangedBeforeTheBookmarksWereDeleted =>
      'The forum changed before the bookmarks were deleted.';

  @override
  String get couldnTConfirmTheDeletionTheTopicIsBeingRefreshed =>
      'Couldn\'t confirm the deletion. The topic is being refreshed.';

  @override
  String get couldnTSeeWhoLikedThis => 'Couldn\'t see who liked this.';

  @override
  String get couldnTLoadWhoLikedThis => 'Couldn\'t load who liked this.';

  @override
  String get uploadCancelled => 'Upload cancelled.';

  @override
  String get couldnTPrepareThisPostNothingWasPosted =>
      'Couldn\'t prepare this post. Nothing was posted.';

  @override
  String get couldnTReachTheSiteNothingWasPosted =>
      'Couldn\'t reach the site. Nothing was posted.';

  @override
  String get pleaseAddDetailsAndSpecificsToYourTopicByEditingThe =>
      'Please add details and specifics to your topic by editing the topic template.';

  @override
  String get youMustChooseACategory => 'You must choose a category.';

  @override
  String get couldnTSeeThatProfile => 'Couldn\'t see that profile.';

  @override
  String couldnTLoadShellcontroller(String username) {
    return 'Couldn\'t load @$username.';
  }

  @override
  String couldnTLoadTagsFrom(String instanceHost) {
    return 'Couldn\'t load tags from $instanceHost.';
  }

  @override
  String couldnTLoadCategoriesFrom(String instanceHost) {
    return 'Couldn\'t load categories from $instanceHost.';
  }

  @override
  String couldnTLoadMoreCategoriesFrom(String instanceHost) {
    return 'Couldn\'t load more categories from $instanceHost.';
  }

  @override
  String get summary => 'Summary';

  @override
  String pluginCannotUseEmojiContext(String consumer, String contextId) {
    return 'Plugin $consumer cannot use emoji context $contextId.';
  }

  @override
  String pluginCannotInspectPluginDataOwnedBy(
    String consumer,
    String keyOwner,
  ) {
    return 'Plugin $consumer cannot inspect plugin data owned by $keyOwner.';
  }

  @override
  String pluginCannotInspectCurrentUserDataOwnedBy(
    String consumer,
    String keyOwner,
  ) {
    return 'Plugin $consumer cannot inspect current-user data owned by $keyOwner.';
  }

  @override
  String pluginCannotUpdatePluginDataOwnedBy(String consumer, String keyOwner) {
    return 'Plugin $consumer cannot update plugin data owned by $keyOwner.';
  }

  @override
  String pluginCannotRequestBookmarkTarget(
    String consumer,
    String targetTypeId,
  ) {
    return 'Plugin $consumer cannot request bookmark target $targetTypeId.';
  }

  @override
  String thisBookmarkDoesNotBelongTo(String targetTypeRefreshLabel) {
    return 'This bookmark does not belong to $targetTypeRefreshLabel.';
  }

  @override
  String get didNotRegisterNotificationFeed =>
      'did not register notification feed';

  @override
  String get cannotAccessNotificationFeed => 'cannot access notification feed';

  @override
  String plugin(String consumer, String reason, String idId) {
    return 'Plugin $consumer $reason $idId.';
  }

  @override
  String pluginMustUseItsRegisteredNotificationFeed(
    String consumer,
    String sourceIdId,
  ) {
    return 'Plugin $consumer must use its registered notification feed $sourceIdId.';
  }

  @override
  String pluginDidNotRegisterDismissalForNotificationFeed(
    String consumer,
    String sourceIdId,
  ) {
    return 'Plugin $consumer did not register dismissal for notification feed $sourceIdId.';
  }

  @override
  String get noTagsYet => 'No tags yet';

  @override
  String get theComposerChangedWhileTheEmojiPickerWasOpenNothingWas =>
      'The composer changed while the emoji picker was open. Nothing was changed.';

  @override
  String get noForumsSelected => 'No forums selected';

  @override
  String get noMatchingTopics => 'No matching topics';

  @override
  String get chooseForums => 'Choose forums';

  @override
  String get forumFilters => 'Forum filters';

  @override
  String get editActiveFilters => 'Edit active filters';

  @override
  String get useForumDefault => 'Use forum default';

  @override
  String get aggregate => 'Aggregate';

  @override
  String aggregateAggregateview(String index) {
    return 'Aggregate $index';
  }

  @override
  String get aggregateTab => 'Aggregate tab';

  @override
  String get thisForumAlreadyHas20TabsCloseOneAndTryAgain =>
      'This forum already has 20 tabs. Close one and try again.';

  @override
  String get thatTopicIsNoLongerAvailable =>
      'That topic is no longer available.';

  @override
  String notBeRefreshed(num failed) {
    String _temp0 = intl.Intl.pluralLogic(
      failed,
      locale: localeName,
      other: '$failed forums could not be refreshed.',
      one: '$failed forum could not be refreshed.',
    );
    return '$_temp0';
  }

  @override
  String get posts => 'Posts';

  @override
  String get groupActivity => 'Group activity';

  @override
  String get topicsAreNotAvailableYet => 'Topics are not available yet.';

  @override
  String noYet(String kind) {
    return 'No $kind yet.';
  }

  @override
  String get thereAreNoPendingMembershipRequests =>
      'There are no pending membership requests.';

  @override
  String get accept => 'Accept';

  @override
  String get deny => 'Deny';

  @override
  String get inbox => 'Inbox';

  @override
  String get archive => 'Archive';

  @override
  String get messagesAreNotAvailableYet => 'Messages are not available yet.';

  @override
  String get groupMessages => 'Group messages';

  @override
  String get thereAreNoCategoriesAssociatedWithThisGroup =>
      'There are no categories associated with this group.';

  @override
  String get createReplyAndSee => 'Create, reply, and see';

  @override
  String get replyAndSee => 'Reply and see';

  @override
  String get seeGroupactivityview => 'See';

  @override
  String get customAccess => 'Custom access';

  @override
  String get loggedInUsers => 'Logged-in users';

  @override
  String get groupMembers => 'Group members';

  @override
  String get groupOwners => 'Group owners';

  @override
  String get staff => 'Staff';

  @override
  String get nobody => 'Nobody';

  @override
  String level(String value) {
    return 'Level $value';
  }

  @override
  String get groupChanged => 'Group changed';

  @override
  String get enterAGroupName => 'Enter a group name.';

  @override
  String get couldnTSaveThatGroupChange => 'Couldn\'t save that group change.';

  @override
  String get addMembers => 'Add members';

  @override
  String get inviteToGroup => 'Invite to group';

  @override
  String get thisGroupSMembersArePrivate => 'This group’s members are private.';

  @override
  String get thisGroupHasNoMembers => 'This group has no members.';

  @override
  String noMembersMatch(String filter) {
    return 'No members match “$filter”.';
  }

  @override
  String get loadingMoreMembers => 'Loading more members';

  @override
  String get searchMembers => 'Search members';

  @override
  String get added => 'Added';

  @override
  String get lastPost => 'Last post';

  @override
  String get lastSeen => 'Last seen';

  @override
  String get sortedAscendingGroupmembersview => 'Sorted ascending';

  @override
  String get sortedDescendingGroupmembersview => 'Sorted descending';

  @override
  String sortBy(String label) {
    return 'Sort by $label';
  }

  @override
  String get primary => 'Primary';

  @override
  String get posted => 'Posted';

  @override
  String get seen => 'Seen';

  @override
  String removeGroupmembersview(String memberUsername) {
    return 'Remove @$memberUsername?';
  }

  @override
  String thisMemberWillLoseAccessGrantedBy(String groupLabel) {
    return 'This member will lose access granted by $groupLabel.';
  }

  @override
  String get theMemberCouldNotBeUpdated => 'The member could not be updated.';

  @override
  String manageGroupmembersview(String memberUsername) {
    return 'Manage @$memberUsername';
  }

  @override
  String get makeOwner => 'Make owner';

  @override
  String get removeAsOwner => 'Remove as owner';

  @override
  String get makePrimaryGroup => 'Make primary group';

  @override
  String get removeAsPrimaryGroup => 'Remove as primary group';

  @override
  String get removeFromGroup => 'Remove from group';

  @override
  String get usernameOrEmailAddress => 'Username or email address';

  @override
  String get matchingUsersAndEmailAddress => 'Matching users and email address';

  @override
  String get typeAtLeastTwoCharacters => 'Type at least two characters.';

  @override
  String get noMatchingUsers => 'No matching users.';

  @override
  String get addByEmailAddress => 'Add by email address';

  @override
  String invitationSentTo(String normalizedEmail) {
    return 'Invitation sent to $normalizedEmail.';
  }

  @override
  String get enterAnEmailToSendAnInvitationOrLeaveItBlank =>
      'Enter an email to send an invitation, or leave it blank to create a one-use link.';

  @override
  String get emailOptional => 'Email (optional)';

  @override
  String get messageOptional => 'Message (optional)';

  @override
  String get copyInviteLink => 'Copy invite link';

  @override
  String get inviteLinkCopied => 'Invite link copied.';

  @override
  String get createLink => 'Create link';

  @override
  String get membersCouldNotBeSearchedTryAgain =>
      'Members could not be searched. Try again.';

  @override
  String get theSelectedMembersCouldNotBeAdded =>
      'The selected members could not be added.';

  @override
  String notAdded(String resultSkippedUsernamesJoin) {
    return 'Not added: $resultSkippedUsernamesJoin';
  }

  @override
  String get theInvitationCouldNotBeCreated =>
      'The invitation could not be created.';

  @override
  String get theServerDidNotReturnAnInviteLink =>
      'The server did not return an invite link.';

  @override
  String get youCannotManageThisGroup => 'You cannot manage this group.';

  @override
  String get profile => 'Profile';

  @override
  String get interaction => 'Interaction';

  @override
  String get email => 'Email';

  @override
  String get categories => 'Categories';

  @override
  String get logs => 'Logs';

  @override
  String get groupSettings => 'Group settings';

  @override
  String get chooseWhoCanDiscoverAndJoinThisGroup =>
      'Choose who can discover and join this group.';

  @override
  String get whoCanJoin => 'Who can join?';

  @override
  String get invitationOnly => 'Invitation only';

  @override
  String get requestApproval => 'Request approval';

  @override
  String get anyoneCanJoin => 'Anyone can join';

  @override
  String get membersCanLeave => 'Members can leave';

  @override
  String get groupVisibility => 'Group visibility';

  @override
  String get memberListVisibility => 'Member-list visibility';

  @override
  String get requestTemplate => 'Request template';

  @override
  String get automaticMembershipEmailDomains =>
      'Automatic membership email domains';

  @override
  String get associatedGroupIDs => 'Associated group IDs';

  @override
  String get grantTrustLevel => 'Grant trust level';

  @override
  String get controlMentionsMessagesAndNotificationDefaults =>
      'Control mentions, messages, and notification defaults.';

  @override
  String get whoCanMentionThisGroup => 'Who can mention this group?';

  @override
  String get whoCanMessageThisGroup => 'Who can message this group?';

  @override
  String get defaultNotificationLevel => 'Default notification level';

  @override
  String get publishReadState => 'Publish read state';

  @override
  String get letMembersShareMessageReadState =>
      'Let members share message read state.';

  @override
  String get incomingEmailAddress => 'Incoming email address';

  @override
  String get configureTheMailboxUsedByThisGroup =>
      'Configure the mailbox used by this group.';

  @override
  String get enableSMTP => 'Enable SMTP';

  @override
  String get port => 'Port';

  @override
  String get password => 'Password';

  @override
  String get leaveBlankToKeepTheExistingPassword =>
      'Leave blank to keep the existing password';

  @override
  String get fromAlias => 'From alias';

  @override
  String get allowRepliesFromUnknownSenders =>
      'Allow replies from unknown senders';

  @override
  String get categoryNotifications => 'Category notifications';

  @override
  String get enterCommaSeparatedCategoryIDsForEachLevel =>
      'Enter comma-separated category IDs for each level.';

  @override
  String get tagNotifications => 'Tag notifications';

  @override
  String get enterCommaSeparatedTagNamesForEachLevel =>
      'Enter comma-separated tag names for each level.';

  @override
  String get theNameAndIdentityPeopleSeeAroundTheForum =>
      'The name and identity people see around the forum.';

  @override
  String get fullName => 'Full name';

  @override
  String get aboutThisGroup => 'About this group';

  @override
  String get memberTitle => 'Member title';

  @override
  String get flairIcon => 'Flair icon';

  @override
  String get flairBackground => 'Flair background';

  @override
  String get flairForeground => 'Flair foreground';

  @override
  String get noGroupChangesHaveBeenRecorded =>
      'No group changes have been recorded.';

  @override
  String get membershipAndSettingsChangesForThisGroup =>
      'Membership and settings changes for this group.';

  @override
  String get removeCategory => 'Remove category';

  @override
  String get couldnTCopyTheInviteLink => 'Couldn\'t copy the invite link.';

  @override
  String get invitationEmailSent => 'Invitation email sent.';

  @override
  String get inviteLinkCreated => 'Invite link created.';

  @override
  String get copiedInviteeditor => 'Copied!';

  @override
  String get backToInvites => 'Back to invites';

  @override
  String get createInvite => 'Create invite';

  @override
  String get leaveBlankForAShareableLink => 'Leave blank for a shareable link.';

  @override
  String get enterAValidEmailAddress => 'Enter a valid email address.';

  @override
  String get descriptionOptional => 'Description (optional)';

  @override
  String get maximumUses => 'Maximum uses';

  @override
  String upTo(String limit) {
    return 'Up to $limit';
  }

  @override
  String enterANumberFrom1To(String limit) {
    return 'Enter a number from 1 to $limit.';
  }

  @override
  String get expiresAfterDays => 'Expires after (days)';

  @override
  String get enterANumberFrom1To36500 => 'Enter a number from 1 to 36500.';

  @override
  String get sendInvitationEmail => 'Send invitation email';

  @override
  String get customMessageOptional => 'Custom message (optional)';

  @override
  String get creating => 'Creating…';

  @override
  String get createAndSendEmail => 'Create and send email';

  @override
  String get createInviteLink => 'Create invite link';

  @override
  String get link => 'Link';

  @override
  String editLinkTo(String url) {
    return 'Edit link to $url';
  }

  @override
  String get insertLink => 'Insert link';

  @override
  String get text => 'Text';

  @override
  String get pinned => 'Pinned';

  @override
  String get bookmarked => 'Bookmarked';

  @override
  String get topicHasNewReplies => 'Topic has new replies';

  @override
  String get changePostOwner => 'Change post owner';

  @override
  String assignByToAnotherAccount(num count, String oldUsername) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Assign $count posts by @$oldUsername to another account.',
      one: 'Assign $count post by @$oldUsername to another account.',
    );
    return '$_temp0';
  }

  @override
  String get searchUsers => 'Search users';

  @override
  String get searchForTheNewOwner => 'Search for the new owner.';

  @override
  String get noUsersFound => 'No users found.';

  @override
  String get changeOwner => 'Change owner';

  @override
  String get searchGroups => 'Search groups';

  @override
  String get newGroup => 'New group';

  @override
  String get filterByGroupType => 'Filter by group type';

  @override
  String get allGroups => 'All groups';

  @override
  String get myGroups => 'My groups';

  @override
  String get groupsIOwn => 'Groups I own';

  @override
  String get publicGroups => 'Public groups';

  @override
  String get closedGroups => 'Closed groups';

  @override
  String get automaticGroups => 'Automatic groups';

  @override
  String get membersHidden => 'Members hidden';

  @override
  String get noGroupsMatchTheseFilters => 'No groups match these filters.';

  @override
  String get topicsPosts => 'Topics & posts';

  @override
  String get noMatchingOptions => 'No matching options.';

  @override
  String dismissChoicemenu(String title) {
    return 'Dismiss $title';
  }

  @override
  String get clearFilter => 'Clear filter';

  @override
  String get choices => 'Choices';

  @override
  String illegalContent(String topicTitle) {
    return 'Illegal content: $topicTitle';
  }

  @override
  String thisPostContainsIllegalContent(String postUrl) {
    return 'This post $postUrl contains illegal content.';
  }

  @override
  String get reportIllegalContent => 'Report illegal content';

  @override
  String get thisSiteAcceptsIllegalContentReportsByEmailYourMailApplication =>
      'This site accepts illegal-content reports by email. Your mail application will open with the post link and subject filled in.';

  @override
  String get openEmail => 'Open email';

  @override
  String get couldnTOpenAMailApplication =>
      'Couldn\'t open a mail application.';

  @override
  String get editTopicTitle => 'Edit topic title';

  @override
  String get theVideoCouldNotBeDownloaded =>
      'The video could not be downloaded.';

  @override
  String get couldnTUploadThisImage => 'Couldn\'t upload this image.';

  @override
  String get uploaded => 'Uploaded';

  @override
  String get processingImage => 'Processing image';

  @override
  String get retrying => 'Retrying';

  @override
  String get uploading => 'Uploading';

  @override
  String get retryUpload => 'Retry upload';

  @override
  String get removeUpload => 'Remove upload';

  @override
  String get cancelUpload => 'Cancel upload';

  @override
  String previewOf(String filename) {
    return 'Preview of $filename';
  }

  @override
  String pixelsWide(String valueRound) {
    return '$valueRound pixels wide';
  }

  @override
  String get topicLists => 'Topic lists';

  @override
  String get newTopics => 'New · Topics';

  @override
  String get newReplies => 'New · Replies';

  @override
  String get unseen => 'Unseen';

  @override
  String get trending => 'Trending';

  @override
  String top(String modeTopPeriodLabel) {
    return 'Top · $modeTopPeriodLabel';
  }

  @override
  String get replies => 'Replies';

  @override
  String get chooseTopicFeed => 'Choose topic feed';

  @override
  String get newActivity => 'New activity';

  @override
  String get topTopiclistnavigation => 'Top';

  @override
  String get topPeriods => 'Top periods';

  @override
  String searchGlobalsearchpanel(String scopeLabel) {
    return 'Search $scopeLabel';
  }

  @override
  String get clear => 'Clear';

  @override
  String get clearAllSearchConditions => 'Clear all search conditions';

  @override
  String get keepTyping => 'Keep typing';

  @override
  String enterAtLeastCharactersToSearch(
    String controllerCapabilitiesMinimumLength,
  ) {
    return 'Enter at least $controllerCapabilitiesMinimumLength characters to search.';
  }

  @override
  String get searchCouldNotLoad => 'Search could not load';

  @override
  String get pleaseTryAgain => 'Please try again.';

  @override
  String get noResultsFound => 'No results found';

  @override
  String get tryDifferentWordsOrRemoveACondition =>
      'Try different words or remove a condition.';

  @override
  String get viewAll => 'View all';

  @override
  String viewAllResults(String sectionScopeLabel) {
    return 'View all $sectionScopeLabel results';
  }

  @override
  String get recentSearches => 'Recent searches';

  @override
  String get clearHistory => 'Clear history';

  @override
  String get clearConditions => 'Clear conditions';

  @override
  String get personalMessage => 'Personal message';

  @override
  String get orderingAndDisplay => 'Ordering and display';

  @override
  String get ordering => 'Ordering';

  @override
  String get orderSearchResults => 'Order search results';

  @override
  String get ascending => 'Ascending';

  @override
  String get ascendingOrder => 'Ascending order';

  @override
  String get displayProperties => 'Display properties';

  @override
  String get excerpt => 'Excerpt';

  @override
  String get author => 'Author';

  @override
  String get likes => 'Likes';

  @override
  String get flagTopic => 'Flag Topic';

  @override
  String get flagPost => 'Flag Post';

  @override
  String messageTo(String username) {
    return 'Message to @$username';
  }

  @override
  String get describeTheIllegalContent => 'Describe the illegal content';

  @override
  String get messageToTheModerators => 'Message to the moderators';

  @override
  String explainConstructivelyHowThisCanBeImproved(String targetNoun) {
    return 'Explain constructively how this $targetNoun can be improved.';
  }

  @override
  String explainPreciselyWhatIsIllegalAboutThis(String targetNoun) {
    return 'Explain precisely what is illegal about this $targetNoun.';
  }

  @override
  String explainWhyThisNeedsModeratorAttention(String targetNoun) {
    return 'Explain why this $targetNoun needs moderator attention.';
  }

  @override
  String moreRequiredRemaining(
    String minimumMessageLengthLength,
    String postFlagTypeMaximumMessageLengthLength,
  ) {
    return '$minimumMessageLengthLength more required · $postFlagTypeMaximumMessageLengthLength remaining';
  }

  @override
  String get allFlagsAreReceivedByModeratorsAndWillBeReviewedAs =>
      'All flags are received by moderators and will be reviewed as soon as possible.';

  @override
  String get whatIVeWrittenAboveIsAccurateAndComplete =>
      'What I’ve written above is accurate and complete';

  @override
  String get connectThisAccountToSeeItsActivity =>
      'Connect this account to see its activity';

  @override
  String get noActivityYet => 'No activity yet';

  @override
  String get topicsYouCreateAndRepliesYouPostWillAppearHereLikes =>
      'Topics you create and replies you post will appear here. Likes, bookmarks, reads, and drafts have their own lists.';

  @override
  String get loadingMoreActivity => 'Loading more activity';

  @override
  String topicCreatedBy(String itemUsername) {
    return 'Topic created by $itemUsername';
  }

  @override
  String replyBy(String itemUsername) {
    return 'Reply by $itemUsername';
  }

  @override
  String postUseractivity(String itemPostNumber) {
    return 'Post $itemPostNumber';
  }

  @override
  String get deleted => 'Deleted';

  @override
  String get hidden => 'Hidden';

  @override
  String get loadingActivity => 'Loading activity';

  @override
  String get display => 'Display';

  @override
  String get themes => 'Themes';

  @override
  String get accessibility => 'Accessibility';

  @override
  String get gray => 'Gray';

  @override
  String get brown => 'Brown';

  @override
  String get orange => 'Orange';

  @override
  String get yellow => 'Yellow';

  @override
  String get green => 'Green';

  @override
  String get blue => 'Blue';

  @override
  String get purple => 'Purple';

  @override
  String get pink => 'Pink';

  @override
  String get red => 'Red';

  @override
  String get background => 'Background';

  @override
  String get textAndBackgroundColors => 'Text and background colors';

  @override
  String get backgroundColor => 'Background color';

  @override
  String get textColor => 'Text color';

  @override
  String get color => 'Color';

  @override
  String get minimizePanel => 'Minimize panel';

  @override
  String get openATabInTheOtherPanelFirst =>
      'Open a tab in the other panel first';

  @override
  String get mainPanelMinimized => 'Main panel, minimized';

  @override
  String get secondaryPanelMinimized => 'Secondary panel, minimized';

  @override
  String get resizeMainPanel => 'Resize main panel';

  @override
  String get mainPanel => 'Main panel';

  @override
  String get secondaryPanel => 'Secondary panel';

  @override
  String get dropThisTabHere => 'Drop this tab here';

  @override
  String get dragATabHereOrOpenANewTab => 'Drag a tab here or open a new tab.';

  @override
  String message1pxSolid(String horizontalRuleColor) {
    return '1px solid $horizontalRuleColor';
  }

  @override
  String get linkClicked1Time => 'link clicked 1 time';

  @override
  String linkClickedTimes(String count) {
    return 'link clicked $count times';
  }

  @override
  String get headerAHref => 'header a[href]';

  @override
  String get addTag => 'Add tag';

  @override
  String get savingTags => 'Saving tags';

  @override
  String tagsTopicheadertags(String tagsLength) {
    return 'Tags · $tagsLength';
  }

  @override
  String get topicTags => 'Topic tags';

  @override
  String editTopicTags(String tagsIndexName) {
    return 'Edit topic tags: $tagsIndexName';
  }

  @override
  String openTagTopicheadertags(String tagsIndexName) {
    return 'Open tag $tagsIndexName';
  }

  @override
  String viewAndEditAllTopicTags(String tagsLength) {
    return 'View and edit all $tagsLength topic tags';
  }

  @override
  String viewAllTopicTags(String tagsLength) {
    return 'View all $tagsLength topic tags';
  }

  @override
  String get addOrRemoveTopicTags => 'Add or remove topic tags';

  @override
  String get findATopicTag => 'Find a topic tag';

  @override
  String get noMatchingTagsTopicheadertags => 'No matching tags';

  @override
  String get detailsEditor => 'Details editor';

  @override
  String get detailsSummary => 'Details summary';

  @override
  String get detailsContent => 'Details content';

  @override
  String get writeHere => 'Write here…';

  @override
  String get removeDetailsKeepContent => 'Remove details, keep content';

  @override
  String get deleteDetails => 'Delete details';

  @override
  String get collapseDetails => 'Collapse details';

  @override
  String get expandDetails => 'Expand details';

  @override
  String get invitesAreUnavailableForThisAccount =>
      'Invites are unavailable for this account.';

  @override
  String get searchInvites => 'Search invites';

  @override
  String get emailOrUsername => 'Email or username';

  @override
  String get loadingInvites => 'Loading invites';

  @override
  String get noMatchingInvites => 'No matching invites.';

  @override
  String get manageInvitesInBrowser => 'Manage invites in browser';

  @override
  String restrictedToInvitelist(String inviteDomain) {
    return 'Restricted to $inviteDomain';
  }

  @override
  String get expired => 'Expired';

  @override
  String get expires => 'Expires';

  @override
  String invitedVia(String inviteInviteSource) {
    return 'Invited via $inviteInviteSource';
  }

  @override
  String get removeThisInviteItWillNoLongerBeUsable =>
      'Remove this invite? It will no longer be usable.';

  @override
  String get confirmRemoval => 'Confirm removal';

  @override
  String get resend => 'Resend';

  @override
  String get replyingToAPost => 'Replying to a post';

  @override
  String get follow => 'Follow';

  @override
  String followOnX(String handle) {
    return 'Follow @$handle on X';
  }

  @override
  String get viewPostOnX => 'View post on X';

  @override
  String get couldNotCopyLinkTryAgain => 'Could not copy link. Try again.';

  @override
  String likeOnX(String metricLabelLikesLike) {
    return '$metricLabelLikesLike. Like on X';
  }

  @override
  String viewPostOnXTwitter(String metricLabelRepostsRepost) {
    return '$metricLabelRepostsRepost. View post on X';
  }

  @override
  String get readReplies => 'Read replies';

  @override
  String reddit(String comment, String path, String pathValue3) {
    String _temp0 = intl.Intl.selectLogic(comment, {
      'true': 'Reddit comment · $path/$pathValue3',
      'other': 'Reddit post · $path/$pathValue3',
    });
    return '$_temp0';
  }

  @override
  String get openOnReddit => 'Open on Reddit';

  @override
  String get audio => 'Audio';

  @override
  String get thisSharedThemeIsIncompleteOrInvalidAskForANew =>
      'This shared theme is incomplete or invalid. Ask for a new copy.';

  @override
  String get couldNotSaveThemeTryAgain => 'Could not save theme. Try again.';

  @override
  String forumAppearancePreview(String themeName) {
    return '$themeName forum appearance preview';
  }

  @override
  String get customTheme => 'Custom theme';

  @override
  String get themePreviewAppearance => 'Theme preview appearance';

  @override
  String get previewLightTheme => 'Preview light theme';

  @override
  String get lightPreview => 'Light preview';

  @override
  String get previewDarkTheme => 'Preview dark theme';

  @override
  String get darkPreview => 'Dark preview';

  @override
  String get usingTheme => 'Using theme';

  @override
  String get useTheme => 'Use theme';

  @override
  String get savingTheme => 'Saving theme';

  @override
  String get openThisThemeInAConnectedForum =>
      'Open this theme in a connected forum.';

  @override
  String get asciinemaRecording => 'Asciinema recording';

  @override
  String get loadEmbed => 'Load embed';

  @override
  String get subcategories => 'Subcategories';

  @override
  String get filterByTag => 'Filter by tag';

  @override
  String filterByTags(String tagNameJoin) {
    return 'Filter by tags: $tagNameJoin';
  }

  @override
  String tagTopiclistfilterbar(String selectedTagsFirstName) {
    return 'Tag: $selectedTagsFirstName';
  }

  @override
  String removeInstanceactions(String instanceTitle) {
    return 'Remove $instanceTitle?';
  }

  @override
  String thisSignsOutOfAndTakesItOutOfTheRail(String instanceHost) {
    return 'This signs out of $instanceHost and takes it out of the rail. The app will revoke this device’s access so notifications stop. You can add the forum back at any time.';
  }

  @override
  String couldnTRemoveTryAgain(String instanceTitle) {
    return 'Couldn\'t remove $instanceTitle. Try again.';
  }

  @override
  String get showForumActions => 'Show forum actions';

  @override
  String get removeForum => 'Remove forum';

  @override
  String get moreOptionsInstanceactions => 'More Options';

  @override
  String get forumActions => 'Forum actions';

  @override
  String get deleteThisTopicAction => 'Delete this topic action';

  @override
  String get removeLike => 'Remove like';

  @override
  String get like => 'Like';

  @override
  String get removeYourLike => 'Remove your like';

  @override
  String get likeThisPost => 'Like this post';

  @override
  String get share => 'Share';

  @override
  String get shareThisPost => 'Share this post';

  @override
  String get copyALinkToThisPostToClipboard =>
      'Copy a link to this post to clipboard';

  @override
  String get replyToThisPost => 'Reply to this post';

  @override
  String get editThisPost => 'Edit this post';

  @override
  String get bookmarkThisPost => 'Bookmark this post';

  @override
  String get editThisPostBookmark => 'Edit this post bookmark';

  @override
  String get viewEditHistory => 'View edit history';

  @override
  String get viewThisPostSEditHistory => 'View this post\'s edit history';

  @override
  String get removeWiki => 'Remove wiki';

  @override
  String get makeWiki => 'Make wiki';

  @override
  String get returnThisToOrdinaryPostEditing =>
      'Return this to ordinary post editing';

  @override
  String get allowCommunityMembersToEditThisPost =>
      'Allow community members to edit this post';

  @override
  String get unlockPost => 'Unlock post';

  @override
  String get lockPost => 'Lock post';

  @override
  String get allowThisPostToBeEditedAgain =>
      'Allow this post to be edited again';

  @override
  String get preventFurtherEditsToThisPost =>
      'Prevent further edits to this post';

  @override
  String get privatelyFlagThisPostForAttention =>
      'Privately flag this post for attention';

  @override
  String get reportIllegalContentByEmail => 'Report illegal content by email';

  @override
  String get unhidePost => 'Unhide post';

  @override
  String get restoreThisHiddenPost => 'Restore this hidden post';

  @override
  String get revertToRegularPost => 'Revert to regular post';

  @override
  String get convertToModeratorPost => 'Convert to moderator post';

  @override
  String get removeTheModeratorStylingFromThisPost =>
      'Remove the moderator styling from this post';

  @override
  String get markThisAsAnOfficialModeratorPost =>
      'Mark this as an official moderator post';

  @override
  String get addPostNotice => 'Add post notice';

  @override
  String get changePostNotice => 'Change post notice';

  @override
  String get addAStaffNoticeAboveThisPost =>
      'Add a staff notice above this post';

  @override
  String get changeOrRemoveTheStaffNotice =>
      'Change or remove the staff notice';

  @override
  String get assignThisPostToAnotherAccount =>
      'Assign this post to another account';

  @override
  String get editTags => 'Edit tags';

  @override
  String get editTopicTagsPostactions => 'Edit topic tags';

  @override
  String get permanentlyDelete => 'Permanently delete';

  @override
  String get permanentlyDeleteThisPost => 'Permanently delete this post';

  @override
  String get undelete => 'Undelete';

  @override
  String get putThisPostBack => 'Put this post back';

  @override
  String get deleteThisPost => 'Delete this post';

  @override
  String get uncategorized => 'Uncategorized';

  @override
  String categoryPostactions(String id) {
    return 'Category $id';
  }

  @override
  String get actions => 'Actions';

  @override
  String get moreActions => 'More actions';

  @override
  String moreActionsForPost(String scopePostNumber) {
    return 'More actions for post $scopePostNumber';
  }

  @override
  String get imageGallery => 'Image gallery';

  @override
  String get previousImage => 'Previous image';

  @override
  String get nextImage => 'Next image';

  @override
  String goToImageOf(String number, String total) {
    return 'Go to image $number of $total';
  }

  @override
  String openImageLightbox(String description) {
    return 'Open image: $description';
  }

  @override
  String get openImageLightboxValue => 'Open image';

  @override
  String saved(String filename) {
    return 'Saved $filename.';
  }

  @override
  String get couldnTDownloadImage => 'Couldn\'t download image.';

  @override
  String get resetZoom => 'Reset zoom';

  @override
  String get downloading => 'Downloading…';

  @override
  String get download => 'Download';

  @override
  String get includeSubcategories => 'include subcategories';

  @override
  String get onlyTheseCategories => 'only these categories';

  @override
  String get chooseCategories => 'Choose categories';

  @override
  String
  get chooseOneOrMoreCategoriesMultipleCategoriesMatchAnySelectedCategory =>
      'Choose one or more categories. Multiple categories match any selected category.';

  @override
  String get includeAny => 'include any';

  @override
  String get includeAll => 'include all';

  @override
  String get excludeAny => 'exclude any';

  @override
  String get excludeCombination => 'exclude combination';

  @override
  String get chooseTags => 'Choose tags';

  @override
  String get matchAnyTagEveryTagOrExcludeSelectedTags =>
      'Match any tag, every tag, or exclude selected tags.';

  @override
  String get postedBy => 'Posted by';

  @override
  String get findPostsWrittenByASpecificPersonUseMeForYour =>
      'Find posts written by a specific person. Use me for your posts.';

  @override
  String get startedBy => 'Started by';

  @override
  String get findOpeningPostsWrittenByThisPerson =>
      'Find opening posts written by this person.';

  @override
  String get authorSGroup => 'Author’s group';

  @override
  String get findPostsWrittenByMembersOfAGroupWhoseMembershipYou =>
      'Find posts written by members of a group whose membership you can view.';

  @override
  String get groupInbox => 'Group inbox';

  @override
  String get searchPersonalMessagesAddressedToThisGroup =>
      'Search personal messages addressed to this group.';

  @override
  String get searchIn => 'Search in';

  @override
  String get byDefaultResultsAreGroupedByTopicEveryMatchingPostShows =>
      'By default, results are grouped by topic. Every matching post shows separate results from the same topic.';

  @override
  String get topicTitles => 'Topic titles';

  @override
  String get openingPosts => 'Opening posts';

  @override
  String get everyMatchingPost => 'Every matching post';

  @override
  String get messagesTopics => 'Messages & topics';

  @override
  String get searchTheTopicsAndPersonalMessagesAvailableToYourAccount =>
      'Search the topics and personal messages available to your account.';

  @override
  String get topicsAndMyMessages => 'Topics and my messages';

  @override
  String get myPersonalMessages => 'My personal messages';

  @override
  String get oneToOnePersonalMessages => 'One-to-one personal messages';

  @override
  String get myActivity => 'My activity';

  @override
  String get personal => 'Personal';

  @override
  String get narrowResultsUsingYourReadingNotificationAndPostingActivity =>
      'Narrow results using your reading, notification, and posting activity.';

  @override
  String get readPosts => 'Read posts';

  @override
  String get unreadPosts => 'Unread posts';

  @override
  String get trackingOrWatching => 'Tracking or watching';

  @override
  String get bookmarkedPosts => 'Bookmarked posts';

  @override
  String get likedPosts => 'Liked posts';

  @override
  String get myPosts => 'My posts';

  @override
  String get topicsIStarted => 'Topics I started';

  @override
  String get topicStatus => 'Topic status';

  @override
  String get openTopicsAreNeitherClosedNorArchived =>
      'Open topics are neither closed nor archived.';

  @override
  String get noReplies => 'No replies';

  @override
  String get oneParticipant => 'One participant';

  @override
  String get publicCategories => 'Public categories';

  @override
  String get postType => 'Post type';

  @override
  String get chooseTheTypeOfPostToFind => 'Choose the type of post to find.';

  @override
  String get regularPosts => 'Regular posts';

  @override
  String get wikiPosts => 'Wiki posts';

  @override
  String get postsInPinnedTopics => 'Posts in pinned topics';

  @override
  String get postsByBots => 'Posts by bots';

  @override
  String get postsByPeople => 'Posts by people';

  @override
  String get contains => 'Contains';

  @override
  String get findPostsWithImagesOrTopicsWithOrWithoutTags =>
      'Find posts with images or topics with or without tags.';

  @override
  String get images => 'Images';

  @override
  String get atLeastOneTag => 'At least one tag';

  @override
  String get noTags => 'No tags';

  @override
  String get fileTypes => 'File types';

  @override
  String get enterOneOrMoreFileExtensionsSeparatedByCommas =>
      'Enter one or more file extensions, separated by commas.';

  @override
  String get postDate => 'Post date';

  @override
  String get datesCounts => 'Dates & counts';

  @override
  String get matchWhenAPostWasCreated => 'Match when a post was created.';

  @override
  String get postCount => 'Post count';

  @override
  String get countAllPostsInTheTopicIncludingTheOpeningPost =>
      'Count all posts in the topic, including the opening post.';

  @override
  String get views => 'Views';

  @override
  String get matchTheTopicSViewCount => 'Match the topic’s view count.';

  @override
  String get language => 'Language';

  @override
  String get enFrAnyOrNone => 'en, fr, any, or none';

  @override
  String get enterALanguageCodeAnyForADetectedLanguageOrNone =>
      'Enter a language code, any for a detected language, or none for posts without one.';

  @override
  String get english => 'English';

  @override
  String get french => 'French';

  @override
  String get german => 'German';

  @override
  String get spanish => 'Spanish';

  @override
  String get anyDetectedLanguage => 'Any detected language';

  @override
  String get noDetectedLanguage => 'No detected language';

  @override
  String get authorSBadge => 'Author’s badge';

  @override
  String get badgeNameOrID => 'Badge name or ID';

  @override
  String get findPostsWrittenByUsersWhoHoldThisBadge =>
      'Find posts written by users who hold this badge.';

  @override
  String get specificTopic => 'Specific topic';

  @override
  String get topicID => 'Topic ID';

  @override
  String get searchPostsWithinOneTopic => 'Search posts within one topic.';

  @override
  String get categoryTagOrTagGroup => 'Category, tag or tag group';

  @override
  String get advanced => 'Advanced';

  @override
  String get categoryTagOrTagGroupSlug => 'Category, tag, or tag group slug';

  @override
  String get lookUpACategoryFirstThenATagThenATag =>
      'Look up a category first, then a tag, then a tag group with this slug.';

  @override
  String get unlistedTopics => 'Unlisted topics';

  @override
  String
  get availableWhenYourAccountCanViewUnlistedTopicsIncludingEligibleTrust =>
      'Available when your account can view unlisted topics, including eligible trust level 4 users.';

  @override
  String get includeUnlistedTopics => 'Include unlisted topics';

  @override
  String get whispers => 'Whispers';

  @override
  String get requiresPermissionToReadWhispers =>
      'Requires permission to read whispers.';

  @override
  String get whisperPosts => 'Whisper posts';

  @override
  String get allPersonalMessages => 'All personal messages';

  @override
  String get administratorSearchAcrossPersonalMessages =>
      'Administrator search across personal messages.';

  @override
  String get allUsersPersonalMessages => 'All users’ personal messages';

  @override
  String get userSPersonalMessages => 'User’s personal messages';

  @override
  String get administratorSearchWithinThePersonalMessagesOfThisUser =>
      'Administrator search within the personal messages of this user.';

  @override
  String get isAMemberOf => 'is a member of';

  @override
  String get isNotAMemberOf => 'is not a member of';

  @override
  String get selectAGroupWhoseMembershipIsVisibleExclusionsCanContainMultiple =>
      'Select a group whose membership is visible. Exclusions can contain multiple group names.';

  @override
  String get isExactly => 'is exactly';

  @override
  String get matchOneExactUsernameOrExcludeUsernamesSeparatedByCommas =>
      'Match one exact username, or exclude usernames separated by commas.';

  @override
  String get activityPeriod => 'Activity period';

  @override
  String get chooseTheTimePeriodUsedForUserActivityStatistics =>
      'Choose the time period used for user activity statistics.';

  @override
  String get allTime => 'All time';

  @override
  String get quarter => 'Quarter';

  @override
  String get groupType => 'Group type';

  @override
  String get filterGroupMembershipOrAdmissionClosedMembershipDoesNotMeanThe =>
      'Filter group membership or admission. Closed membership does not mean the group is hidden.';

  @override
  String get groupsIJoined => 'Groups I joined';

  @override
  String get openMembership => 'Open membership';

  @override
  String get closedMembership => 'Closed membership';

  @override
  String get customGroups => 'Custom groups';

  @override
  String get browseAutomaticGroupsAvailableToStaff =>
      'Browse automatic groups available to staff.';

  @override
  String get findGroupsThisPersonBelongsToWhereGroupMembershipIsVisible =>
      'Find groups this person belongs to, where group membership is visible.';

  @override
  String get latestPost => 'Latest post';

  @override
  String get oldestPost => 'Oldest post';

  @override
  String get newestTopic => 'Newest topic';

  @override
  String get oldestTopic => 'Oldest topic';

  @override
  String get mostViewed => 'Most viewed';

  @override
  String get mostLiked => 'Most liked';

  @override
  String get recentlyRead => 'Recently read';

  @override
  String get memberCount => 'Member count';

  @override
  String get likesReceived => 'Likes received';

  @override
  String get likesGiven => 'Likes given';

  @override
  String get topicsViewed => 'Topics viewed';

  @override
  String get topicsCreated => 'Topics created';

  @override
  String get postsCreated => 'Posts created';

  @override
  String get postsRead => 'Posts read';

  @override
  String get daysVisited => 'Days visited';

  @override
  String get thisFilterIsUnavailableOnThisSite =>
      'This filter is unavailable on this site.';

  @override
  String get chooseASupportedCondition => 'Choose a supported condition.';

  @override
  String get chooseOrEnterAValue => 'Choose or enter a value.';

  @override
  String get theFilterValueIsTooLong => 'The filter value is too long.';

  @override
  String get chooseAnAvailableValue => 'Choose an available value.';

  @override
  String get signInToSearchYourMemberships =>
      'Sign in to search your memberships.';

  @override
  String get enterFileExtensionsSeparatedByCommas =>
      'Enter file extensions separated by commas.';

  @override
  String get enterAValidWholeNumber => 'Enter a valid whole number.';

  @override
  String get chooseAValidDate => 'Choose a valid date.';

  @override
  String get enterOneUsernameGroupOrChannelSlug =>
      'Enter one username, group, or channel slug.';

  @override
  String get chooseOneValueForThisCondition =>
      'Choose one value for this condition.';

  @override
  String get enterOneLanguageCodeAnyOrNone =>
      'Enter one language code, any, or none.';

  @override
  String get chooseValidCategorySlugsOrTagNames =>
      'Choose valid category slugs or tag names.';

  @override
  String get removeQuotesFromTheValue => 'Remove quotes from the value.';

  @override
  String get thisOrderingIsUnavailable => 'This ordering is unavailable.';

  @override
  String unknownOrUnavailableSearchOperator(String token) {
    return 'Unknown or unavailable search operator: $token';
  }

  @override
  String get table => 'Table';

  @override
  String get column1Column2 =>
      '| Column 1 | Column 2 |\n| --- | --- |\n|  |  |\n|  |  |';

  @override
  String columnHeading(String column) {
    return 'Column $column heading';
  }

  @override
  String rowColumn(String row, String column) {
    return 'Row $row, column $column';
  }

  @override
  String get heading => 'Heading';

  @override
  String get cell => 'Cell';

  @override
  String columnActions(String column) {
    return 'Column $column actions';
  }

  @override
  String get insertColumnBefore => 'Insert column before';

  @override
  String get insertColumnAfter => 'Insert column after';

  @override
  String get moveColumnEarlier => 'Move column earlier';

  @override
  String get moveColumnLater => 'Move column later';

  @override
  String get deleteColumn => 'Delete column';

  @override
  String rowActions(String row) {
    return 'Row $row actions';
  }

  @override
  String get insertRowAbove => 'Insert row above';

  @override
  String get insertRowBelow => 'Insert row below';

  @override
  String get moveRowUp => 'Move row up';

  @override
  String get moveRowDown => 'Move row down';

  @override
  String get deleteRow => 'Delete row';

  @override
  String get tableEditor => 'Table editor';

  @override
  String get editableTable => 'Editable table';

  @override
  String get addARowToStartWriting => 'Add a row to start writing.';

  @override
  String get rows => 'Rows';

  @override
  String column(String column) {
    return 'Column $column';
  }

  @override
  String get addRow => 'Add row';

  @override
  String get addColumn => 'Add column';

  @override
  String get removeTable => 'Remove table';

  @override
  String get restorePanel => 'Restore panel';

  @override
  String get closeATabBeforeOpeningAnother =>
      'Close a tab before opening another';

  @override
  String get newTab => 'New tab';

  @override
  String dismissPicker(String title) {
    return 'Dismiss $title picker';
  }

  @override
  String get spoilerCookedspoiler => 'Spoiler';

  @override
  String get couldNotOpenTheSignUpPage => 'Could not open the sign-up page.';

  @override
  String notificationsUnread(num unreadCount) {
    String _temp0 = intl.Intl.pluralLogic(
      unreadCount,
      locale: localeName,
      other: 'Notifications, $unreadCount unread items',
      one: 'Notifications, $unreadCount unread item',
    );
    return '$_temp0';
  }

  @override
  String profileUsermenubutton(String displayNameAccountUsername) {
    return '$displayNameAccountUsername, Profile';
  }

  @override
  String get connecting => 'Connecting…';

  @override
  String get signUp => 'Sign up';

  @override
  String get signIn => 'Sign in';

  @override
  String get signingIn => 'Signing in…';

  @override
  String get suggestedCommunities => 'Suggested communities';

  @override
  String get suggestionsAreUnavailableRightNow =>
      'Suggestions are unavailable right now.';

  @override
  String get loadingSuggestedCommunities => 'Loading suggested communities';

  @override
  String get discoverMoreCommunities => 'Discover more communities';

  @override
  String get filterTopicsByCategoryTagOrOtherCriteria =>
      'Filter topics by category, tag, or other criteria';

  @override
  String get topicFilterQuery => 'Topic filter query';

  @override
  String get clearAllFilters => 'Clear all filters';

  @override
  String get filterSuggestions => 'Filter suggestions';

  @override
  String editTopicFilterToken(String label) {
    return 'Edit filter $label';
  }

  @override
  String removeTopicfilterinput(String label) {
    return 'Remove $label';
  }

  @override
  String get quoteCopiedToClipboard => 'Quote copied to clipboard.';

  @override
  String get copyQuote => 'Copy quote';

  @override
  String get checkAgain => 'Check again';

  @override
  String get createTopic => 'Create topic';

  @override
  String get whisper => 'Whisper';

  @override
  String get saveAndClose => 'Save and close';

  @override
  String get giveYourTopicATitle => 'Give your topic a title';

  @override
  String get loadingThatPost => 'Loading that post…';

  @override
  String get writeYourMessage => 'Write your message…';

  @override
  String get writeYourTopic => 'Write your topic…';

  @override
  String get editThisPostComposerpanel => 'Edit this post…';

  @override
  String replyTo(String targetReplyToUsername) {
    return 'Reply to @$targetReplyToUsername…';
  }

  @override
  String get writeAReply => 'Write a reply…';

  @override
  String get couldnTSaveThisDraftOnThisDevice =>
      'Couldn\'t save this draft on this device.';

  @override
  String get notSavedOnTheSiteKeptOnThisDeviceOnly =>
      'Not saved on the site — kept on this device only.';

  @override
  String get scrollToBottom => 'Scroll to bottom';

  @override
  String get noSubcategory => 'No subcategory';

  @override
  String get bold => 'Bold';

  @override
  String get italic => 'Italic';

  @override
  String get inlineCode => 'Inline code';

  @override
  String get formatting => 'Formatting';

  @override
  String headingComposerpanel(String level) {
    return 'Heading $level';
  }

  @override
  String get numberedList => 'Numbered list';

  @override
  String get bulletedList => 'Bulleted list';

  @override
  String get toDoList => 'To-do list';

  @override
  String get upload => 'Upload';

  @override
  String get composerEditor => 'Composer editor';

  @override
  String get imageControls => 'Image controls';

  @override
  String get decreaseImageSize => 'Decrease image size';

  @override
  String get increaseImageSize => 'Increase image size';

  @override
  String get deleteImage => 'Delete image';

  @override
  String get imageDescription => 'Image description';

  @override
  String get addImageDescription => 'Add image description';

  @override
  String get saveAltText => 'Save alt text';

  @override
  String get galleryMode => 'Gallery mode';

  @override
  String get gridGalleryMode => 'Grid gallery mode';

  @override
  String get carouselGalleryMode => 'Carousel gallery mode';

  @override
  String get addImagesToGallery => 'Add images to gallery';

  @override
  String get uploadNewImages => 'Upload new images';

  @override
  String get addExistingDraftImages => 'Add existing draft images';

  @override
  String get removeGalleryKeepImages => 'Remove gallery, keep images';

  @override
  String get addExistingImages => 'Add existing images';

  @override
  String imageComposerpanel(String index) {
    return 'Image $index';
  }

  @override
  String get addSelected => 'Add selected';

  @override
  String get insert => 'Insert';

  @override
  String get composerOptions => 'Composer options';

  @override
  String get more => 'More';

  @override
  String get showMoreComposerTools => 'Show more composer tools';

  @override
  String get showPreviousComposerTools => 'Show previous composer tools';

  @override
  String get discard => 'Discard';

  @override
  String get couldnTDownloadVideoTryAgain =>
      'Couldn\'t download video. Try again.';

  @override
  String get downloadingVideo => 'Downloading video…';

  @override
  String get downloadVideo => 'Download video';

  @override
  String playVideo(String dataTitle) {
    return 'Play video: $dataTitle';
  }

  @override
  String get playVideoInlinevideo => 'Play video';

  @override
  String videoPlayer(String dataTitle) {
    return 'Video player: $dataTitle';
  }

  @override
  String fullScreenVideoPlayer(String dataTitle) {
    return 'Full-screen video player: $dataTitle';
  }

  @override
  String get pause => 'Pause';

  @override
  String get play => 'Play';

  @override
  String get exitFullScreen => 'Exit full screen';

  @override
  String get enterFullScreen => 'Enter full screen';

  @override
  String get playbackPosition => 'Playback position';

  @override
  String openVideo(String dataTitle) {
    return 'Open video: $dataTitle';
  }

  @override
  String get openVideoInlinevideo => 'Open video';

  @override
  String get couldnTPlayThisVideo => 'Couldn\'t play this video.';

  @override
  String get video => 'Video';

  @override
  String get noCategoriesYet => 'No categories yet';

  @override
  String get messageLists => 'Message lists';

  @override
  String get thePostChangedReviewItsToDosAndTryAgain =>
      'The post changed. Review its to-dos and try again.';

  @override
  String get thePostChangedReviewItsToDosBeforeContinuing =>
      'The post changed. Review its to-dos before continuing.';

  @override
  String get couldnTConfirmTheToDoUpdateRefreshThePostTo =>
      'Couldn\'t confirm the to-do update. Refresh the post to check its saved state.';

  @override
  String get youFlaggedThisPost => 'You flagged this post';

  @override
  String get youFlaggedThisAsOffTopic => 'You flagged this as off-topic';

  @override
  String get youFlaggedThisAsSpam => 'You flagged this as spam';

  @override
  String get youFlaggedThisAsInappropriate =>
      'You flagged this as inappropriate';

  @override
  String get youFlaggedThisAsIllegal => 'You flagged this as illegal';

  @override
  String get youFlaggedThisForModeration => 'You flagged this for moderation';

  @override
  String get youSentAMessageToThisUser => 'You sent a message to this user';

  @override
  String youFlaggedThisAs(String typeName) {
    return 'You flagged this as $typeName.';
  }

  @override
  String get startPage => 'Start page';

  @override
  String get closeNavigation => 'Close navigation';

  @override
  String get openNavigation => 'Open navigation';

  @override
  String get bookmarks => 'Bookmarks';

  @override
  String get replyToThisTopic => 'Reply to this topic';

  @override
  String get moreDestinations => 'More destinations';

  @override
  String get selectedComposerrecipients => 'Selected';

  @override
  String get recipients => 'Recipients';

  @override
  String get chooseRecipients => 'Choose recipients';

  @override
  String recipientsComposerrecipients(String recipientsJoin) {
    return 'Recipients: $recipientsJoin';
  }

  @override
  String get addUsersOrGroups => 'Add users or groups';

  @override
  String get searchRecipients => 'Search recipients';

  @override
  String get noUsersOrGroupsFound => 'No users or groups found.';

  @override
  String get to => 'To';

  @override
  String get closeATabBeforeOpeningAnotherOpenlink =>
      'Close a tab before opening another.';

  @override
  String get openLinkOpenlink => 'Open link';

  @override
  String get openInMainPanel => 'Open in main panel';

  @override
  String get openInSecondaryPanel => 'Open in secondary panel';

  @override
  String get openInNewMainTab => 'Open in new main tab';

  @override
  String get openInNewSecondaryTab => 'Open in new secondary tab';

  @override
  String get connectThisAccountToSeeItsSummary =>
      'Connect this account to see its summary';

  @override
  String get highlights => 'Highlights';

  @override
  String get connections => 'Connections';

  @override
  String get reading => 'Reading';

  @override
  String get timeReading => 'Time reading';

  @override
  String readTimeAllTime(String timeLong) {
    return 'read time: $timeLong, all time';
  }

  @override
  String get yourStoryStartsWithAConversation =>
      'Your story starts with a conversation.';

  @override
  String get asYouReadReplyAndConnectWithPeopleYourHighlightsWill =>
      'As you read, reply and connect with people, your highlights will appear here.';

  @override
  String get topTopics => 'Top topics';

  @override
  String get noTopicsYet => 'No topics yet.';

  @override
  String get topReplies => 'Top replies';

  @override
  String get yourMilestones => 'Your milestones';

  @override
  String get noConnectionsYet => 'No connections yet.';

  @override
  String get thePeopleYouReplyToAndExchangeLikesWithWillAppear =>
      'The people you reply to and exchange likes with will appear here.';

  @override
  String get mostRepliedTo => 'Most replied to';

  @override
  String get mostLikedBy => 'Most liked by';

  @override
  String get noLikesYet => 'No likes yet.';

  @override
  String get timeWellSpent => 'Time well spent';

  @override
  String inTheLast60Days(String recentShort) {
    return '$recentShort in the last 60 days';
  }

  @override
  String recentReadTimeInTheLast60Days(String recentLong) {
    return 'recent read time: $recentLong, in the last 60 days';
  }

  @override
  String get allTimeReading => 'All-time reading';

  @override
  String get topCategories => 'Top categories';

  @override
  String get topLinks => 'Top links';

  @override
  String get repliesWritten => 'Replies written';

  @override
  String get topicsStarted => 'Topics started';

  @override
  String openUsersummary(String topicTitle) {
    return 'Open $topicTitle';
  }

  @override
  String get noLinksYet => 'No links yet.';

  @override
  String openExternalLink(String shortUrlLinkUrl, String linkClicksClick) {
    return 'Open external link $shortUrlLinkUrl, $linkClicksClick';
  }

  @override
  String openUsersummaryValue(String linkTopicTitle) {
    return 'Open $linkTopicTitle';
  }

  @override
  String viewProfileForUsersummary(
    String userDisplayName,
    String nounPluralPluralNoun,
  ) {
    return 'View profile for $userDisplayName, $nounPluralPluralNoun';
  }

  @override
  String searchByIn(
    String topics,
    String categoryTopicCountTopic,
    String username,
    String categoryName,
    String replyPluralReplies,
  ) {
    String _temp0 = intl.Intl.selectLogic(topics, {
      'true': 'Search $categoryTopicCountTopic by @$username in $categoryName',
      'other': 'Search $replyPluralReplies by @$username in $categoryName',
    });
    return '$_temp0';
  }

  @override
  String get noBadgesYet => 'No badges yet.';

  @override
  String get loadingSummary => 'Loading summary';

  @override
  String get tagTopictagselector => 'Tag';

  @override
  String get allTags => 'All tags';

  @override
  String tagsTopictagselector(String tagNameJoin) {
    return 'Tags: $tagNameJoin';
  }

  @override
  String get searchTags => 'Search tags…';

  @override
  String get searchTagsTopictagselector => 'Search tags';

  @override
  String get noTagsAreAvailable => 'No tags are available.';

  @override
  String get myTheme => 'My theme';

  @override
  String get newTheme => 'New theme';

  @override
  String get startFrom => 'Start from';

  @override
  String get messageContinue => 'Continue';

  @override
  String reconnectToToLoadPreferences(String instanceHost) {
    return 'Reconnect to $instanceHost to load preferences.';
  }

  @override
  String get thisAccountIsNotAllowedToEditThesePreferences =>
      'This account is not allowed to edit these preferences.';

  @override
  String couldnTLoadPreferencesFrom(String instanceHost) {
    return 'Couldn\'t load preferences from $instanceHost.';
  }

  @override
  String reconnectToToUpdatePreferences(String host) {
    return 'Reconnect to $host to update preferences.';
  }

  @override
  String get thesePreferencesChangedElsewhereReloadAndTryAgain =>
      'These preferences changed elsewhere. Reload and try again.';

  @override
  String couldnTUpdatePreferencesOn(String host) {
    return 'Couldn\'t update preferences on $host.';
  }

  @override
  String get confirmation => 'Confirmation';

  @override
  String get everyNewPostAndUnreadCount => 'Every new post and unread count';

  @override
  String get mentionsRepliesAndUnreadCount =>
      'Mentions, replies, and unread count';

  @override
  String get watchingFirstPost => 'Watching First Post';

  @override
  String get newTopicsOnly => 'New topics only';

  @override
  String get mentionsAndRepliesOnly => 'Mentions and replies only';

  @override
  String get muted => 'Muted';

  @override
  String get noNotificationsHiddenFromLatest =>
      'No notifications; hidden from Latest';

  @override
  String get couldnTCheckForAnExistingDraftTryAgain =>
      'Couldn\'t check for an existing draft. Try again.';

  @override
  String get couldnTDiscardThisDraftTryAgain =>
      'Couldn\'t discard this draft. Try again.';

  @override
  String get thisDraftChangedBeforeItCouldBeDiscardedReviewItAnd =>
      'This draft changed before it could be discarded. Review it and try again.';

  @override
  String get reconnectToThisForumToLoadPreferences =>
      'Reconnect to this forum to load preferences.';

  @override
  String get preferences => 'Preferences';

  @override
  String get savingPreferences => 'Saving preferences';

  @override
  String get savePreferences => 'Save preferences';

  @override
  String get savingChanges => 'Saving changes…';

  @override
  String get likeNotifications => 'Like notifications';

  @override
  String get chooseWhenLikesShouldCreateANotification =>
      'Choose when likes should create a notification.';

  @override
  String get firstTimeAndDaily => 'First time and daily';

  @override
  String get firstTime => 'First time';

  @override
  String get notifyMeAboutRepliesToLinkedPosts =>
      'Notify me about replies to linked posts';

  @override
  String get getANotificationWhenSomeoneRepliesToAPostYouLinked =>
      'Get a notification when someone replies to a post you linked.';

  @override
  String get considerTopicsNew => 'Consider topics new';

  @override
  String get controlsWhichTopicsAppearAsNewToThisAccount =>
      'Controls which topics appear as new to this account.';

  @override
  String get untilIViewThem => 'Until I view them';

  @override
  String get forOneDay => 'For one day';

  @override
  String get forTwoDays => 'For two days';

  @override
  String get forOneWeek => 'For one week';

  @override
  String get forTwoWeeks => 'For two weeks';

  @override
  String get sinceMyLastVisit => 'Since my last visit';

  @override
  String get automaticallyTrackTopics => 'Automatically track topics';

  @override
  String get trackATopicAfterYouHaveReadItForThisLong =>
      'Track a topic after you have read it for this long.';

  @override
  String get immediately => 'Immediately';

  @override
  String get after30Seconds => 'After 30 seconds';

  @override
  String get after1Minute => 'After 1 minute';

  @override
  String get after2Minutes => 'After 2 minutes';

  @override
  String get after3Minutes => 'After 3 minutes';

  @override
  String get after4Minutes => 'After 4 minutes';

  @override
  String get after5Minutes => 'After 5 minutes';

  @override
  String get after10Minutes => 'After 10 minutes';

  @override
  String get whenIReplyToATopic => 'When I reply to a topic';

  @override
  String get chooseTheNotificationLevelAppliedAfterAReply =>
      'Choose the notification level applied after a reply.';

  @override
  String get watchTheTopic => 'Watch the topic';

  @override
  String get trackTheTopic => 'Track the topic';

  @override
  String get keepTheCurrentLevel => 'Keep the current level';

  @override
  String get typeToFilterIANATimezonesUsedForDatesAndReminders =>
      'Type to filter IANA timezones used for dates and reminders.';

  @override
  String get deviceTimezoneIsUnavailable => 'Device timezone is unavailable.';

  @override
  String deviceTimezone(String deviceTimezone) {
    return 'Device timezone: $deviceTimezone';
  }

  @override
  String get useDeviceTimezone => 'Use device timezone';

  @override
  String get automaticallyDeleteBookmarks => 'Automatically delete bookmarks';

  @override
  String get chooseWhatHappensAfterABookmarkReminder =>
      'Choose what happens after a bookmark reminder.';

  @override
  String get afterTheReminderIsSent => 'After the reminder is sent';

  @override
  String get whenTheTopicOwnerReplies => 'When the topic owner replies';

  @override
  String get whenTheReminderIsCleared => 'When the reminder is cleared';

  @override
  String preferencesSaved(String sectionTitleSectionPluginSections) {
    return '$sectionTitleSectionPluginSections preferences saved.';
  }

  @override
  String get refreshingPreferences => 'Refreshing preferences…';

  @override
  String loadingPreferencesFrom(String host) {
    return 'Loading preferences from $host.';
  }

  @override
  String get loadingPreferences => 'Loading preferences…';

  @override
  String get interface => 'Interface';

  @override
  String get topicCreationActions => 'Topic creation actions';

  @override
  String get openTheLatestDraftsMenu => 'Open the latest drafts menu';

  @override
  String get recentDrafts => 'Recent drafts';

  @override
  String get allDrafts => 'All drafts';

  @override
  String get loadingDraftsTopiccreatebutton => 'Loading drafts…';

  @override
  String get couldnTLoadDrafts => 'Couldn\'t load drafts.';

  @override
  String viewAllDraftsOther(String otherDraftCount, String noun) {
    return 'View all drafts, $otherDraftCount other $noun';
  }

  @override
  String get viewAllDrafts => 'view all drafts';

  @override
  String get editCategory => 'Edit category';

  @override
  String get editTopic => 'Edit topic';

  @override
  String editPost(String targetEditingPostNumber) {
    return 'Edit post #$targetEditingPostNumber';
  }

  @override
  String resumeEditing(String label) {
    return 'Resume editing: $label';
  }

  @override
  String get restoreComposer => 'Restore composer';

  @override
  String get resumeEditingComposerheader => 'Resume editing';

  @override
  String get replyVisibility => 'Reply visibility';

  @override
  String get whisperAllowedGroupsOnly => 'Whisper, Allowed groups only';

  @override
  String get allowedGroupsOnly => 'Allowed groups only';

  @override
  String get whisperOptions => 'Whisper options';

  @override
  String get replyOptions => 'Reply options';

  @override
  String get composerActions => 'Composer actions';

  @override
  String get minimize => 'Minimize';

  @override
  String get saveDraft => 'Save draft';

  @override
  String returnTo(String targetTopicTitle) {
    return 'Return to $targetTopicTitle';
  }

  @override
  String get dockSide => 'Dock side';

  @override
  String get composerView => 'Composer view';

  @override
  String get fullScreen => 'Full screen';

  @override
  String get minimizeComposer => 'Minimize composer';

  @override
  String get notSaved => 'Not saved';

  @override
  String get deviceOnly => 'Device only';

  @override
  String openTabsIn(String forumName) {
    return 'Open tabs in $forumName';
  }

  @override
  String get moveToSecondaryPanel => 'Move to secondary panel';

  @override
  String get moveToMainPanel => 'Move to main panel';

  @override
  String get browseTabs => 'Browse tabs';

  @override
  String get searchTabs => 'Search tabs...';

  @override
  String closeForumtabsbar(String itemTitle) {
    return 'Close $itemTitle';
  }

  @override
  String browseTabsIn(String forumName) {
    return 'Browse tabs in $forumName';
  }

  @override
  String get lists => 'Lists';

  @override
  String get recentlyClosed => 'Recently closed ';

  @override
  String dropHere(String itemTitle) {
    return 'Drop $itemTitle here';
  }

  @override
  String get openANewTab => 'Open a new tab';

  @override
  String get showMoreTabs => 'Show more tabs';

  @override
  String get showPreviousTabs => 'Show previous tabs';

  @override
  String get rename => 'Rename';

  @override
  String get urgentUnreadActivity => 'urgent unread activity';

  @override
  String get unreadActivity => 'unread activity';

  @override
  String get unreadItem => 'unread item';

  @override
  String get unreadItems => 'unread items';

  @override
  String get moveLeft => 'Move left';

  @override
  String get moveRight => 'Move right';

  @override
  String get showTabActions => 'Show tab actions';

  @override
  String get tabActions => 'Tab actions';

  @override
  String get closeTab => 'Close tab';

  @override
  String get closeOtherTabs => 'Close other tabs';

  @override
  String get couldnTOpenTheImagePicker => 'Couldn\'t open the image picker.';

  @override
  String get filterTopics => 'Filter topics';

  @override
  String get addAFilter => 'Add a filter…';

  @override
  String get openTopics => 'Open topics';

  @override
  String get unanswered => 'Unanswered';

  @override
  String get closedTopics => 'Closed topics';

  @override
  String get unreadReplies => 'Unread replies';

  @override
  String get newTopicsTopiclistactions => 'New topics';

  @override
  String get applyFilter => 'Apply filter';

  @override
  String get editActiveFilter => 'Edit active filter';

  @override
  String get texture => 'Texture';

  @override
  String get paper => 'Paper';

  @override
  String get lavaLamp => 'Lava lamp';

  @override
  String get gradient => 'Gradient';

  @override
  String get intensity => 'Intensity';

  @override
  String get opacity => 'Opacity';

  @override
  String get tint => 'Tint';

  @override
  String reconnectToToSeeYourSummary(String instanceHost) {
    return 'Reconnect to $instanceHost to see your summary.';
  }

  @override
  String couldnTLoadYourSummaryFrom(String instanceHost) {
    return 'Couldn\'t load your summary from $instanceHost.';
  }

  @override
  String get replyingToThisTopic => 'Replying to this topic';

  @override
  String replyingToComposerreplycontext(String username) {
    return 'Replying to @$username';
  }

  @override
  String get replyingToComposerreplycontextValue => 'Replying to ';

  @override
  String get dismissEmojiPicker => 'Dismiss emoji picker';

  @override
  String get noEmojiAreAvailable => 'No emoji are available.';

  @override
  String get noEmojiFound => 'No emoji found.';

  @override
  String get frequentlyUsed => 'Frequently used';

  @override
  String get searchEmoji => 'Search emoji';

  @override
  String skinTone(String toneLabelControllerTone) {
    return 'Skin tone: $toneLabelControllerTone';
  }

  @override
  String get chooseSkinTone => 'Choose skin tone';

  @override
  String get clearFrequentlyUsedEmoji => 'Clear frequently used emoji';

  @override
  String insertEmojipicker(String choiceCode) {
    return 'Insert :$choiceCode:';
  }

  @override
  String get smileysEmotion => 'Smileys & emotion';

  @override
  String get peopleBody => 'People & body';

  @override
  String get animalsNature => 'Animals & nature';

  @override
  String get foodDrink => 'Food & drink';

  @override
  String get travelPlaces => 'Travel & places';

  @override
  String get activities => 'Activities';

  @override
  String get objects => 'Objects';

  @override
  String get symbols => 'Symbols';

  @override
  String get flags => 'Flags';

  @override
  String get customEmojis => 'Custom emojis';

  @override
  String get neutral => 'Neutral';

  @override
  String get light => 'Light';

  @override
  String get mediumLight => 'Medium-light';

  @override
  String get medium => 'Medium';

  @override
  String get mediumDark => 'Medium-dark';

  @override
  String get dark => 'Dark';

  @override
  String get composerCommands => 'Composer commands';

  @override
  String get noMatchingCommands => 'No matching commands.';

  @override
  String get closeMenu => 'Close menu';

  @override
  String get typeToSearch => 'Type to search';

  @override
  String get themeCopiedPasteItIntoAPostOrChat =>
      'Theme copied. Paste it into a post or chat.';

  @override
  String get couldNotCopyThemeTryAgain => 'Could not copy theme. Try again.';

  @override
  String get useAtMost30Conditions => 'Use at most 30 conditions.';

  @override
  String get recentSearchesCouldNotBeClearedPleaseTryAgain =>
      'Recent searches could not be cleared. Please try again.';

  @override
  String get searchesCanBeAtMost2048Characters =>
      'Searches can be at most 2048 characters.';

  @override
  String get bookmarkPost => 'Bookmark post';

  @override
  String get postBookmark => 'Post bookmark';

  @override
  String get topicBookmark => 'Topic bookmark';

  @override
  String get topicBookmarks => 'Topic bookmarks';

  @override
  String get deleteBookmark => 'Delete bookmark?';

  @override
  String get thisAlsoRemovesItsScheduledReminder =>
      'This also removes its scheduled reminder.';

  @override
  String get deleteAllBookmarks => 'Delete all bookmarks?';

  @override
  String get everyTopicAndPostBookmarkInThisTopicWillBeRemoved =>
      'Every topic and post bookmark in this topic will be removed.';

  @override
  String get deleteAll => 'Delete all';

  @override
  String get savingBookmark => 'Saving bookmark';

  @override
  String get savingBookmarkBookmarkui => 'Saving bookmark…';

  @override
  String get theBookmarkWasNotSaved => 'The bookmark was not saved.';

  @override
  String get bookmarkedBookmarkui => 'Bookmarked!';

  @override
  String get clearReminder => 'Clear reminder';

  @override
  String get deleteBookmarkBookmarkui => 'Delete bookmark';

  @override
  String get thatLocalTimeDoesNotExistBecauseOfDaylightSavingTime =>
      'That local time does not exist because of daylight saving time.';

  @override
  String get enterAPositiveReminderDuration =>
      'Enter a positive reminder duration.';

  @override
  String get chooseAReminderInTheFuture => 'Choose a reminder in the future.';

  @override
  String get chooseAReminderNoMoreThan10YearsAway =>
      'Choose a reminder no more than 10 years away.';

  @override
  String get noteBookmarkui => 'Note';

  @override
  String get whyAreYouSavingThis => 'Why are you saving this?';

  @override
  String get afterward => 'Afterward';

  @override
  String get remindMe => 'Remind me';

  @override
  String timesUse(String zoneName) {
    return 'Times use $zoneName.';
  }

  @override
  String get dateInPost => 'Date in post';

  @override
  String get lastCustomTime => 'Last custom time';

  @override
  String get customDateAndTime => 'Custom date and time';

  @override
  String get noReminder => 'No reminder';

  @override
  String get messageIn => 'In';

  @override
  String get messageSet => 'Set';

  @override
  String reminder(String contextReminderZoneName) {
    return 'Reminder: $contextReminderZoneName';
  }

  @override
  String get thisTopicIsNoLongerAvailable =>
      'This topic is no longer available.';

  @override
  String postBookmarkui(String bookmarkPostNumber) {
    return 'Post #$bookmarkPostNumber';
  }

  @override
  String get postBookmarkActions => 'Post bookmark actions';

  @override
  String get jump => 'Jump';

  @override
  String get deleteAllBookmarksBookmarkui => 'Delete all bookmarks';

  @override
  String get keepBookmark => 'Keep bookmark';

  @override
  String get deleteAfterTheReminder => 'Delete after the reminder';

  @override
  String get deleteOnceIReply => 'Delete once I reply';

  @override
  String get keepBookmarkAndClearReminder => 'Keep bookmark and clear reminder';

  @override
  String imageGalleryComposerimagegallery(num itemsLength) {
    String _temp0 = intl.Intl.pluralLogic(
      itemsLength,
      locale: localeName,
      other: 'Image gallery, $itemsLength images',
      one: 'Image gallery, $itemsLength image',
    );
    return '$_temp0';
  }

  @override
  String addOrRemoveImages(String count) {
    return '$count. Add or remove images.';
  }

  @override
  String get galleryOptions => 'Gallery options';

  @override
  String get someTagsWereRemoved => 'Some tags were removed';

  @override
  String get dismissTagNotice => 'Dismiss tag notice';

  @override
  String get bash => 'Bash';

  @override
  String get clojure => 'Clojure';

  @override
  String get dart => 'Dart';

  @override
  String get diff => 'Diff';

  @override
  String get dockerfile => 'Dockerfile';

  @override
  String get elixir => 'Elixir';

  @override
  String get go => 'Go';

  @override
  String get handlebars => 'Handlebars';

  @override
  String get java => 'Java';

  @override
  String get kotlin => 'Kotlin';

  @override
  String get markdown => 'Markdown';

  @override
  String get objectiveC => 'Objective-C';

  @override
  String get plainText => 'Plain text';

  @override
  String get python => 'Python';

  @override
  String get ruby => 'Ruby';

  @override
  String get rust => 'Rust';

  @override
  String get shell => 'Shell';

  @override
  String get swift => 'Swift';

  @override
  String get code => 'Code';

  @override
  String get viewCodeFullScreen => 'View code full screen';

  @override
  String get closeCodeViewer => 'Close code viewer';

  @override
  String get postCode => 'Post code';

  @override
  String get couldnTCopyCode => 'Couldn\'t copy code.';

  @override
  String get codeCopied => 'Code copied';

  @override
  String get newTopicInstancesidebar => 'New Topic';

  @override
  String get shortcutsInstancesidebar => 'Shortcuts';

  @override
  String get forum => 'Forum';

  @override
  String get openForumInBrowser => 'Open forum in browser';

  @override
  String forumMenu(String name) {
    return '$name, forum menu';
  }

  @override
  String get loadingNavigation => 'Loading navigation';

  @override
  String get movePublicLink => 'Move public link?';

  @override
  String get thisChangesAPublicSidebarSectionForEveryoneOnThisForum =>
      'This changes a public sidebar section for everyone on this forum.';

  @override
  String get couldnTMoveLinkTryAgain => 'Couldn\'t move link. Try again.';

  @override
  String get reorderPublicLinks => 'Reorder public links?';

  @override
  String get thisChangesTheSidebarLinkOrderForEveryoneOnThisForum =>
      'This changes the sidebar link order for everyone on this forum.';

  @override
  String get reorder => 'Reorder';

  @override
  String get couldnTReorderLinksTryAgain =>
      'Couldn\'t reorder links. Try again.';

  @override
  String loadingInstancesidebar(String sectionTitle) {
    return 'Loading $sectionTitle';
  }

  @override
  String loadingInstancesidebarValue(String destinationLabel) {
    return 'Loading $destinationLabel';
  }

  @override
  String get unreadMentions => 'Unread mentions';

  @override
  String openInstancesidebar(String destinationLabel) {
    return 'Open $destinationLabel';
  }

  @override
  String get permanentlyDeletePostpermanentdelete => 'permanently delete';

  @override
  String get cannotPermanentlyDelete => 'Cannot permanently delete';

  @override
  String permanentlyDeletePostpermanentdeleteValue(String target) {
    return 'Permanently delete $target?';
  }

  @override
  String thisCannotBeUndoneTheWillBeRemovedFromTheDatabase(String target) {
    return 'This cannot be undone. The $target will be removed from the database.';
  }

  @override
  String typeToConfirm(String confirmationPhrase) {
    return 'Type “$confirmationPhrase” to confirm.';
  }

  @override
  String get resizeDiagnosticsPanel => 'Resize diagnostics panel';

  @override
  String get signInToContinue => 'Sign in to continue';

  @override
  String isAPrivateForumSignInToViewItsTopicsAnd(String siteTitle) {
    return '$siteTitle is a private forum. Sign in to view its topics and conversations.';
  }

  @override
  String get weCouldnTReachThisCommunityCheckItsAddressOrYour =>
      'We couldn\'t reach this community. Check its address or your internet connection, then try again.';

  @override
  String get tryingAgain => 'Trying again…';

  @override
  String get resizeSidebar => 'Resize sidebar';

  @override
  String get couldnTLoadYourSites => 'Couldn\'t load your sites';

  @override
  String get yourSavedSitesHaveNotBeenChangedTryLoadingThemAgain =>
      'Your saved sites have not been changed. Try loading them again.';

  @override
  String get chooseForumForNewTopic => 'Choose forum for new topic';

  @override
  String get previousTopic => 'Previous topic';

  @override
  String get nextTopic => 'Next topic';

  @override
  String couldnTRefresh(String instanceHost) {
    return 'Couldn\'t refresh $instanceHost.';
  }

  @override
  String couldnTLoadMoreFrom(String sourceInstanceHost) {
    return 'Couldn\'t load more from $sourceInstanceHost.';
  }

  @override
  String get discourse => 'Discourse';

  @override
  String get due => 'Due';

  @override
  String get reminderNewtabpage => 'Reminder';

  @override
  String get comfortable => 'Comfortable';

  @override
  String get compact => 'Compact';

  @override
  String get recentlyClosedNewtabpage => 'Recently closed';

  @override
  String get everythingElse => 'Everything else';

  @override
  String get badges => 'Badges';

  @override
  String get browseLatestTopics => 'Browse latest topics';

  @override
  String postNewtabpage(String number) {
    return 'Post #$number';
  }

  @override
  String get workWithTwoPanels => 'Work with two panels';

  @override
  String get middleClick => 'Middle click';

  @override
  String get opensANewTabInMainPanel => 'Opens a new tab in main panel';

  @override
  String get click => 'Click';

  @override
  String get openInANewTabInSecondaryPanel =>
      'Open in a new tab in secondary panel';

  @override
  String get donTShowThisTutorialAgain => 'Don\'t show this tutorial again';

  @override
  String get main => 'Main';

  @override
  String get secondary => 'Secondary';

  @override
  String get shiftClickOpensHere => 'Shift + click opens here';

  @override
  String reconnectToToSeeYourDrafts(String instanceHost) {
    return 'Reconnect to $instanceHost to see your drafts.';
  }

  @override
  String couldnTLoadDraftsFrom(String instanceHost) {
    return 'Couldn\'t load drafts from $instanceHost.';
  }

  @override
  String couldnTLoadMoreDraftsFrom(String instanceHost) {
    return 'Couldn\'t load more drafts from $instanceHost.';
  }

  @override
  String get couldnTRemoveThatDraftTryAgain =>
      'Couldn\'t remove that draft. Try again.';

  @override
  String get couldnTLoadEmojiCheckTheConnectionAndTryAgain =>
      'Couldn\'t load emoji. Check the connection and try again.';

  @override
  String get theImageCouldNotBeDownloaded =>
      'The image could not be downloaded.';

  @override
  String get yourInbox => 'your inbox';

  @override
  String get yourInboxes => 'your inboxes';

  @override
  String moveTo(String scope) {
    return 'Move to $scope';
  }

  @override
  String archiveFrom(String scope) {
    return 'Archive from $scope';
  }

  @override
  String get moveToInbox => 'Move to inbox';

  @override
  String archivedFrom(String scope) {
    return 'Archived from $scope';
  }

  @override
  String movedTo(String scope) {
    return 'Moved to $scope';
  }

  @override
  String chooseAtLeastForThisCategory(String countLabelMinimumRequiredTagsTag) {
    return 'Choose at least $countLabelMinimumRequiredTagsTag for this category.';
  }

  @override
  String get theyArenTAvailableInThisCategory =>
      'They aren’t available in this category.';

  @override
  String theyArenTAvailableIn(String categoryName) {
    return 'They aren’t available in $categoryName.';
  }

  @override
  String get thatGalleryChangedSoTheImagesWillBeAddedOutsideIt =>
      'That gallery changed, so the images will be added outside it.';

  @override
  String get forImages => ' for images';

  @override
  String thatFileTypeIsNotAllowedOnThisSite(String purpose) {
    return 'That file type is not allowed$purpose on this site.';
  }

  @override
  String fileTypesAreNotAllowedOnThisSite(String rejected, String purpose) {
    return '$rejected file types are not allowed$purpose on this site.';
  }

  @override
  String uploadAtMostAtATime(String limit) {
    return 'Upload at most $limit at a time.';
  }

  @override
  String couldnTUpload(String fileName) {
    return 'Couldn\'t upload $fileName.';
  }

  @override
  String get checkingWhetherThatPosted => 'Checking whether that posted…';

  @override
  String get thatMayHavePostedTheSiteCouldNotBeReachedTo =>
      'That may have posted — the site could not be reached to check. Check again before sending it a second time.';

  @override
  String get yourReplyWasSentForReviewSoItIsNotPosted =>
      'Your reply was sent for review, so it is not posted yet.';

  @override
  String parentCategoryTopictaxonomyfields(String parentCategoryName) {
    return 'Parent category: $parentCategoryName';
  }

  @override
  String openCategory(String parentCategoryName) {
    return 'Open category $parentCategoryName';
  }

  @override
  String openCategoryTopictaxonomyfields(String categoryName) {
    return 'Open category $categoryName';
  }

  @override
  String openCategoryTopictaxonomyfieldsValue(String label) {
    return 'Open category $label';
  }

  @override
  String categoryTopictaxonomyfields(String label) {
    return 'Category: $label';
  }

  @override
  String get savingTopicTags => 'Saving topic tags';

  @override
  String get saving => 'Saving…';

  @override
  String get privateCategory => 'Private category';

  @override
  String quoteFrom(String title) {
    return 'Quote from $title';
  }

  @override
  String get message1Like => '1 like';

  @override
  String message1LikeFrom(String postLiked) {
    String _temp0 = intl.Intl.selectLogic(postLiked, {
      'true': '1 like, from you',
      'other': '1 like, from someone else',
    });
    return '$_temp0';
  }

  @override
  String get showWhoLikedThisPost => 'show who liked this post';

  @override
  String get removeYourLikePostlikes => 'remove your like';

  @override
  String get likeThisPostPostlikes => 'like this post';

  @override
  String get and1Other => 'and 1 other';

  @override
  String get couldnTLoadCategories => 'Couldn\'t load categories.';

  @override
  String allTopiccategoryselector(String noun) {
    return 'All $noun';
  }

  @override
  String get filterByCategory => 'Filter by category';

  @override
  String get chooseCategory => 'Choose category';

  @override
  String filterBySubcategoryOf(String parentName) {
    return 'Filter by subcategory of $parentName';
  }

  @override
  String chooseSubcategoryOf(String parentName) {
    return 'Choose subcategory of $parentName';
  }

  @override
  String get subcategoryTopiccategoryselector => 'Subcategory';

  @override
  String subcategoriesOf(String parentName) {
    return 'Subcategories of $parentName';
  }

  @override
  String filterTopiccategoryselector(String noun) {
    return 'Filter $noun';
  }

  @override
  String noMatching(String noun) {
    return 'No matching $noun.';
  }

  @override
  String get privateConversation => 'Private conversation';

  @override
  String lastPostBy(String username) {
    return 'Last post by $username · ';
  }

  @override
  String lastPostByConversationtopiccard(String username) {
    return 'Last post by $username';
  }

  @override
  String get lastPostByConversationtopiccardValue => 'Last post by ';

  @override
  String sortByConversationtopiccard(
    String orderColumn,
    String label,
    String viewsViewsLabel,
    String ascendingAscendingDescending,
  ) {
    String _temp0 = intl.Intl.selectLogic(orderColumn, {
      'true': '$label, sort by $viewsViewsLabel, $ascendingAscendingDescending',
      'other': '$label, sort by $viewsViewsLabel, unsorted',
    });
    return '$_temp0';
  }

  @override
  String openOnYouTube(String dataTitle) {
    return 'Open on YouTube: $dataTitle';
  }

  @override
  String get openOnYouTubeYoutubevideo => 'Open on YouTube';

  @override
  String get couldnTLoadTheYouTubePlayer =>
      'Couldn\'t load the YouTube player.';

  @override
  String youTubePlayer(String dataTitle) {
    return 'YouTube player: $dataTitle';
  }

  @override
  String get noSitesYet => 'No sites yet';

  @override
  String get connectADiscourseForumToGetStarted =>
      'Connect a Discourse forum to get started.';

  @override
  String get addASite => 'Add a site';

  @override
  String get topicProgress => 'Topic progress';

  @override
  String topicProgressPostOf(String boundedPosition, String boundedTotal) {
    return 'Topic progress, post $boundedPosition of $boundedTotal';
  }

  @override
  String get postNavigation => 'Post navigation';

  @override
  String get closeAndReopenTopicProgressToJumpInTheCurrentTopic =>
      'Close and reopen topic progress to jump in the current topic.';

  @override
  String get couldNotOpenThatPostTryAgain =>
      'Could not open that post. Try again.';

  @override
  String postTopicprogress(String selected) {
    return 'Post $selected ';
  }

  @override
  String get firstPost => 'First post';

  @override
  String postOf(String valueRound, String total) {
    return 'Post $valueRound of $total';
  }

  @override
  String get privateMessagesSentDirectlyToYou =>
      'Private messages sent directly to you';

  @override
  String privateMessagesSentTo(String group) {
    return 'Private messages sent to @$group';
  }

  @override
  String get textFormatting => 'Text formatting';

  @override
  String get underline => 'Underline';

  @override
  String get clearFormatting => 'Clear formatting';

  @override
  String get strikethrough => 'Strikethrough';

  @override
  String get moreFormatting => 'More formatting';

  @override
  String get superscript => 'Superscript';

  @override
  String get subscript => 'Subscript';

  @override
  String get keyboardKey => 'Keyboard key';

  @override
  String get paragraph => 'Paragraph';

  @override
  String get divider => 'Divider';

  @override
  String get block => 'Block';

  @override
  String get sourceBlock => 'Source block';

  @override
  String get thisStaffNoticeWillBeShownAboveThePost =>
      'This staff notice will be shown above the post.';

  @override
  String get notice => 'Notice';

  @override
  String get deleteNotice => 'Delete notice';

  @override
  String get couldNotSaveChanges => 'Could not save changes.';

  @override
  String get home => 'Home';

  @override
  String appliesToOnly(String forumName) {
    return 'Applies to $forumName only.';
  }

  @override
  String get useOnEveryForum => 'Use on every forum';

  @override
  String get everyForumNowUsesTheseColours =>
      'Every forum now uses these colours.';

  @override
  String get appearanceMode => 'Appearance mode';

  @override
  String get auto => 'Auto';

  @override
  String get selectAForumToToggleItsSidebar =>
      'Select a forum to toggle its sidebar';

  @override
  String get collapseSidebar => 'Collapse sidebar';

  @override
  String get expandSidebar => 'Expand sidebar';

  @override
  String get couldnTSaveTheNewSiteOrderTryAgain =>
      'Couldn\'t save the new site order. Try again.';

  @override
  String get allForums => 'All forums';

  @override
  String get retryLoadingSites => 'Retry loading sites';

  @override
  String get openComponentStyleguide => 'Open component styleguide';

  @override
  String get diagnostics => 'Diagnostics';

  @override
  String diagnosticsUnseen(num unseen) {
    String _temp0 = intl.Intl.pluralLogic(
      unseen,
      locale: localeName,
      other: 'Diagnostics, $unseen unseen errors',
      one: 'Diagnostics, $unseen unseen error',
    );
    return '$_temp0';
  }

  @override
  String updateTo(String version) {
    return 'Update to $version';
  }

  @override
  String get restartToFinishUpdating => 'Restart to finish updating';

  @override
  String get theLastUpdateCheckFailed => 'The last update check failed';

  @override
  String get checkForUpdates => 'Check for updates';

  @override
  String get unreadNotification => 'unread notification';

  @override
  String get addADiscourseSite => 'Add a Discourse site';

  @override
  String get otherBookmarks => 'Other bookmarks';

  @override
  String get loadingBookmarks => 'Loading bookmarks';

  @override
  String get nothingBookmarkedYet => 'Nothing bookmarked yet.';

  @override
  String get noBookmarksInThisFilter => 'No bookmarks in this filter.';

  @override
  String get loadingMoreBookmarks => 'Loading more bookmarks';

  @override
  String get filterBookmarks => 'Filter bookmarks';

  @override
  String get allBookmarks => 'All bookmarks';

  @override
  String noteBookmarklist(String name) {
    return 'Note: $name';
  }

  @override
  String get editHistoryLast100Revisions => 'Edit history (last 100 revisions)';

  @override
  String get editHistory => 'Edit history';

  @override
  String get message1Edit => '1 edit';

  @override
  String lastEdited(String ageNow, String age) {
    String _temp0 = intl.Intl.selectLogic(ageNow, {
      'true': 'Last edited now',
      'other': 'Last edited $age ago',
    });
    return '$_temp0';
  }

  @override
  String get yourConnectionChangedReopenEditHistoryAndTryAgain =>
      'Your connection changed. Reopen edit history and try again.';

  @override
  String get couldnTLoadEditHistory => 'Couldn\'t load edit history.';

  @override
  String get loadingRevision => 'Loading revision';

  @override
  String get replyToPostrevisionhistory => 'Reply to';

  @override
  String get wiki => 'Wiki';

  @override
  String get topicType => 'Topic type';

  @override
  String get featuredLink => 'Featured link';

  @override
  String get thisRevisionIsTooComplexToCompare =>
      'This revision is too complex to compare.';

  @override
  String get thePostBodyDidNotChangeInThisRevision =>
      'The post body did not change in this revision.';

  @override
  String get yes => 'Yes';

  @override
  String get regular => 'Regular';

  @override
  String get moderator => 'Moderator';

  @override
  String type(String value) {
    return 'Type $value';
  }

  @override
  String get inline => 'Inline';

  @override
  String get sideBySide => 'Side by side';

  @override
  String get current => 'Current';

  @override
  String get unknownEditor => 'Unknown editor';

  @override
  String get theDifferencesInThisRevisionAreHidden =>
      'The differences in this revision are hidden.';

  @override
  String get first => 'First';

  @override
  String get searchThisForum => 'Search this forum';

  @override
  String get searchCouldNotLoadPleaseTryAgain =>
      'Search could not load. Please try again.';

  @override
  String get theSearchTimedOutPleaseTryAgain =>
      'The search timed out. Please try again.';

  @override
  String get theForumIsBusyPleaseTryAgain =>
      'The forum is busy. Please try again.';

  @override
  String get tooManySearchesWaitAMomentBeforeTryingAgain =>
      'Too many searches. Wait a moment before trying again.';

  @override
  String get searchIsUnavailable => 'Search is unavailable.';

  @override
  String get searchIsTooLong => 'Search is too long.';

  @override
  String get useAFilterFromTheSelectedSearchType =>
      'Use a filter from the selected search type.';

  @override
  String get searchPageIsOutOfRange => 'Search page is out of range.';

  @override
  String get topicsUsersAndGroupsCouldNotLoad =>
      'Topics, users and groups could not load.';

  @override
  String searchCouldNotLoadGlobalsearchapi(String scopeLabel) {
    return '$scopeLabel search could not load.';
  }

  @override
  String get unsupportedSearchResult => 'Unsupported search result.';

  @override
  String get useAShorterCategoryName => 'Use a shorter category name.';

  @override
  String get categorySearchIsUnavailable => 'Category search is unavailable.';

  @override
  String get moreCategoriesCouldnTLoad => 'More categories couldn’t load.';

  @override
  String get couldnTLoadThisTopic => 'Couldn\'t load this topic.';

  @override
  String get deleteSelectedPosts => 'Delete selected posts?';

  @override
  String deleteSelected(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Delete $count selected posts?',
      one: 'Delete $count selected post?',
    );
    return '$_temp0';
  }

  @override
  String get mergeSelectedPosts => 'Merge selected posts?';

  @override
  String mergePostsByTheSameAuthorIntoOnePost(String count) {
    return 'Merge $count posts by the same author into one post?';
  }

  @override
  String get merge => 'Merge';

  @override
  String get selectAllLoaded => 'Select all loaded';

  @override
  String get loadingTopic => 'Loading topic';

  @override
  String get moreTopics => 'More topics';

  @override
  String get hideTopicSidebar => 'Hide topic sidebar';

  @override
  String get showTopicSidebar => 'Show topic sidebar';

  @override
  String get loadingMoreTopics => 'Loading more topics';

  @override
  String get view1HiddenReply => 'View 1 hidden reply';

  @override
  String viewHiddenReplies(String count) {
    return 'View $count hidden replies';
  }

  @override
  String get loadingEarlierPosts => 'Loading earlier posts';

  @override
  String selectPostBy(String postUsername) {
    return 'Select post by $postUsername';
  }

  @override
  String get thisPostIsAPrivateWhisper => 'This post is a private whisper';

  @override
  String thisIsTheFirstTimeHasPostedLetSWelcomeThem(String postUsername) {
    return 'This is the first time $postUsername has posted — let’s welcome them to our community!';
  }

  @override
  String itSBeenAWhileSinceWeVeSeenWelcomeBack(String postUsername) {
    return 'It’s been a while since we’ve seen $postUsername — welcome back!';
  }

  @override
  String get staffNotice => 'Staff notice';

  @override
  String get topicViews => 'Topic views';

  @override
  String get likesInThisTopic => 'Likes in this topic';

  @override
  String get linksInThisTopic => 'Links in this topic';

  @override
  String get showAllTopicview => 'Show all';

  @override
  String get loadingMorePosts => 'Loading more posts';

  @override
  String get pauseGIF => 'Pause GIF';

  @override
  String get playGIF => 'Play GIF';

  @override
  String siteImageIsUnavailable(String url) {
    return 'Site image is unavailable: $url';
  }

  @override
  String editForumthemepicker(String themeName) {
    return 'Edit $themeName';
  }

  @override
  String createThemeBasedOn(String forumName) {
    return 'Create theme based on $forumName';
  }

  @override
  String createThemeBasedOnForumthemepicker(String optionName) {
    return 'Create theme based on $optionName';
  }

  @override
  String get composer => 'Composer';

  @override
  String get resizeComposer => 'Resize composer';

  @override
  String manageTopicBookmark(num topicBookmarksLength) {
    String _temp0 = intl.Intl.pluralLogic(
      topicBookmarksLength,
      locale: localeName,
      other: 'Manage $topicBookmarksLength topic bookmarks',
      one: 'Manage $topicBookmarksLength topic bookmark',
    );
    return '$_temp0';
  }

  @override
  String get bookmarkThisTopic => 'Bookmark this topic';

  @override
  String get shareTopic => 'Share topic';

  @override
  String get deleteTopic => 'Delete topic?';

  @override
  String get thisRemovesTheTopicAndAllOfItsRepliesStaffMay =>
      'This removes the topic and all of its replies. Staff may be able to recover it later.';

  @override
  String get flagTopicTopicactions => 'Flag topic';

  @override
  String get unpinTopic => 'Unpin topic';

  @override
  String get pinTopic => 'Pin topic';

  @override
  String get selectPosts => 'Select posts';

  @override
  String get openTopic => 'Open topic';

  @override
  String get closeTopic => 'Close topic';

  @override
  String get unarchiveTopic => 'Unarchive topic';

  @override
  String get archiveTopic => 'Archive topic';

  @override
  String get makeTopicUnlisted => 'Make topic unlisted';

  @override
  String get makeTopicVisible => 'Make topic visible';

  @override
  String get deleteTopicTopicactions => 'Delete topic';

  @override
  String get recoverTopic => 'Recover topic';

  @override
  String get moreTopicActions => 'More topic actions';

  @override
  String get topicNotifications => 'Topic notifications';

  @override
  String get couldNotSaveTheIconSet => 'Could not save the icon set.';

  @override
  String get icons => 'Icons';

  @override
  String get contentWidth => 'Content width';

  @override
  String get wide => 'Wide';

  @override
  String get userUserspage => 'User';

  @override
  String get filterUsers => 'Filter users';

  @override
  String get filterByGroup => 'Filter by group';

  @override
  String get noGroupsFound => 'No groups found.';

  @override
  String get directoryUnavailable => 'Directory unavailable';

  @override
  String get couldnTLoadInvitesPleaseTryAgain =>
      'Couldn\'t load invites. Please try again.';

  @override
  String get inviteRemoved => 'Invite removed.';

  @override
  String get couldnTSaveTheInvitePleaseTryAgain =>
      'Couldn\'t save the invite. Please try again.';

  @override
  String get couldnTLoadMoreGroups => 'Couldn\'t load more groups.';

  @override
  String get couldnTLoadTheGroupDirectory =>
      'Couldn\'t load the group directory.';

  @override
  String get couldnTLoadThisGroup => 'Couldn\'t load this group.';

  @override
  String get couldnTLoadMoreMembers => 'Couldn\'t load more members.';

  @override
  String get couldnTLoadGroupMembers => 'Couldn\'t load group members.';

  @override
  String get couldnTLoadMoreRequests => 'Couldn\'t load more requests.';

  @override
  String get couldnTLoadMembershipRequests =>
      'Couldn\'t load membership requests.';

  @override
  String get couldnTLoadMoreActivity => 'Couldn\'t load more activity.';

  @override
  String get couldnTLoadGroupActivity => 'Couldn\'t load group activity.';

  @override
  String get couldnTLoadGroupPermissions => 'Couldn\'t load group permissions.';

  @override
  String get couldnTLoadMoreGroupLogs => 'Couldn\'t load more group logs.';

  @override
  String get couldnTLoadGroupLogs => 'Couldn\'t load group logs.';

  @override
  String get closedThisTopic => 'closed this topic';

  @override
  String get openedThisTopic => 'opened this topic';

  @override
  String get archivedThisTopic => 'archived this topic';

  @override
  String get unarchivedThisTopic => 'unarchived this topic';

  @override
  String get pinnedThisTopic => 'pinned this topic';

  @override
  String get unpinnedThisTopic => 'unpinned this topic';

  @override
  String get pinnedThisTopicGlobally => 'pinned this topic globally';

  @override
  String get unpinnedThisTopicGlobally => 'unpinned this topic globally';

  @override
  String get madeThisTopicABanner => 'made this topic a banner';

  @override
  String get removedThisBanner => 'removed this banner';

  @override
  String get listedThisTopic => 'listed this topic';

  @override
  String get unlistedThisTopic => 'unlisted this topic';

  @override
  String get splitThisTopic => 'split this topic';

  @override
  String get movedThisPost => 'moved this post';

  @override
  String get removedThemselvesFromThisMessage =>
      'removed themselves from this message';

  @override
  String get automaticallyBumpedThisTopic => 'automatically bumped this topic';

  @override
  String get madeThisTopicPublic => 'made this topic public';

  @override
  String get madeThisTopicAPersonalMessage =>
      'made this topic a personal message';

  @override
  String get convertedThisToATopic => 'converted this to a topic';

  @override
  String get forwardedTheAboveEmail => 'forwarded the above email';

  @override
  String goToStartOf(String label) {
    return 'Go to start of $label';
  }

  @override
  String get couldNotOpenNotificationPreferences =>
      'Could not open notification preferences.';

  @override
  String get pauseNotificationsFor => 'Pause notifications for…';

  @override
  String get setANotificationSchedule => 'Set a notification schedule';

  @override
  String get appUpdates => 'App updates';

  @override
  String get discourseNative => 'Discourse Native';

  @override
  String discourseNativeUpdatesheet(String updatesRunningVersion) {
    return 'Discourse Native $updatesRunningVersion';
  }

  @override
  String followingTheChannel(String updatesChannelLabel) {
    return 'Following the $updatesChannelLabel channel.';
  }

  @override
  String get youReUpToDate => 'You\'re up to date.';

  @override
  String switchTo(String releaseVersion) {
    return 'Switch to $releaseVersion';
  }

  @override
  String downloadUpdatesheet(String releaseVersion) {
    return 'Download $releaseVersion';
  }

  @override
  String get readyToInstall => 'Ready to install.';

  @override
  String get theAppWillCloseAndReopen => 'The app will close and reopen.';

  @override
  String get restartAndInstall => 'Restart and install';

  @override
  String get installingUpdate => 'Installing update';

  @override
  String get installing => 'Installing…';

  @override
  String get theUpdateCouldNotBeChecked => 'The update could not be checked.';

  @override
  String get openTheReleasesPage => 'Open the releases page';

  @override
  String get neverCheckedForUpdates => 'Never checked for updates.';

  @override
  String get checkedJustNow => 'Checked just now.';

  @override
  String lastCheckedAgo(String ago) {
    return 'Last checked $ago ago.';
  }

  @override
  String get checkingForUpdates => 'Checking for updates';

  @override
  String versionIsOnThisChannel(String releaseVersion) {
    return 'Version $releaseVersion is on this channel.';
  }

  @override
  String versionIsAvailable(String releaseVersion) {
    return 'Version $releaseVersion is available.';
  }

  @override
  String get downloadingUpdate => 'Downloading update';

  @override
  String get downloadInProgress => 'Download in progress.';

  @override
  String downloadingUpdatesheet(String progressRound) {
    return 'Downloading — $progressRound%';
  }

  @override
  String composerRangeSelection(String anchor, String focus) {
    return 'ComposerRangeSelection($anchor, $focus)';
  }

  @override
  String get message1Reaction => '1 reaction';

  @override
  String get showWhoReacted => 'show who reacted';

  @override
  String get loadingReactions => 'Loading reactions';

  @override
  String columnCookedtable(String index) {
    return 'Column $index';
  }

  @override
  String get tableCopied => 'Table copied';

  @override
  String get copyTable => 'Copy table';

  @override
  String get couldnTSaveThisSiteTryAgain =>
      'Couldn\'t save this site. Try again.';

  @override
  String isAlreadyInYourList(String instanceTitle) {
    return '$instanceTitle is already in your list.';
  }

  @override
  String couldnTReachAddinstancesheet(String term) {
    return 'Couldn\'t reach $term.';
  }

  @override
  String get validDiscourseSite => 'Valid Discourse site';

  @override
  String get siteIsUnavailableOrIsNotADiscourseForum =>
      'Site is unavailable or is not a Discourse forum';

  @override
  String get enterTheAddressOfADiscourseForum =>
      'Enter the address of a Discourse forum.';

  @override
  String get forumAddress => 'Forum address';

  @override
  String get connect => 'Connect';

  @override
  String get readOnlyUseTheRemoveQuoteButtonToDeleteIt =>
      'Read only. Use the remove quote button to delete it.';

  @override
  String get removeQuote => 'Remove quote';

  @override
  String get couldnTLoadMoreUsers => 'Couldn\'t load more users.';

  @override
  String get couldnTLoadTheUserDirectory =>
      'Couldn\'t load the user directory.';

  @override
  String get resizeMessageList => 'Resize message list';

  @override
  String get resizeTopicList => 'Resize topic list';

  @override
  String openDetailsMaincontent(String routeTitle) {
    return 'Open $routeTitle details';
  }

  @override
  String get message1Group => '1 group';

  @override
  String get signInToViewYourMessages => 'Sign in to view your messages';

  @override
  String get privateMessagesAreTiedToYourForumAccountAndArenT =>
      'Private messages are tied to your forum account and aren’t available while you’re signed out.';

  @override
  String get notFound => 'Not found';

  @override
  String get theRequestedPageCouldNotBeFound =>
      'The requested page could not be found.';

  @override
  String get addSearchFilter => 'Add search filter';

  @override
  String editCondition(String editorLabel) {
    return 'Edit $editorLabel condition';
  }

  @override
  String get addFilter => 'Add filter';

  @override
  String removeCondition(String definitionLabel) {
    return 'Remove $definitionLabel condition';
  }

  @override
  String get searchFilters => 'Search filters';

  @override
  String get addFilterGlobalsearchfilterpicker => 'Add filter…';

  @override
  String get findASearchFilter => 'Find a search filter';

  @override
  String get noFiltersMatchYourSearch => 'No filters match your search.';

  @override
  String get couldnTLoadTagsGlobalsearchfilterpicker => 'Couldn’t load tags';

  @override
  String get couldnTRefreshTags => 'Couldn’t refresh tags';

  @override
  String get suggestionsCouldNotLoad => 'Suggestions could not load.';

  @override
  String get backToFilters => 'Back to filters';

  @override
  String get matchTopicsThat => 'Match topics that';

  @override
  String get applyChanges => 'Apply changes';

  @override
  String get addCondition => 'Add condition';

  @override
  String get includeAnySelectedTag => 'Include any selected tag';

  @override
  String get includeEverySelectedTag => 'Include every selected tag';

  @override
  String get excludeAnySelectedTag => 'Exclude any selected tag';

  @override
  String get excludeThisCombination => 'Exclude this combination';

  @override
  String removeGlobalsearchfilterpicker(String controllerFilterValue) {
    return 'Remove $controllerFilterValue';
  }

  @override
  String get availableTags => 'Available tags';

  @override
  String get searchAvailableTags => 'Search available tags…';

  @override
  String get searchAvailableTagsGlobalsearchfilterpicker =>
      'Search available tags';

  @override
  String selectedGlobalsearchfilterpicker(String valuesLength) {
    return 'Selected · $valuesLength';
  }

  @override
  String get showingSavedTagsMoreMayBeAvailable =>
      'Showing saved tags. More may be available.';

  @override
  String get tryAgainToSeeAvailableTags => 'Try again to see available tags.';

  @override
  String get savedTags => 'Saved tags';

  @override
  String get matchingTags => 'Matching tags';

  @override
  String get tagSuggestions => 'Tag suggestions';

  @override
  String get findingTags => 'Finding tags…';

  @override
  String get noSavedTagsMatch => 'No saved tags match';

  @override
  String get noTagsMatch => 'No tags match';

  @override
  String get findAnOption => 'Find an option…';

  @override
  String use(String queryTrim) {
    return 'Use “$queryTrim”';
  }

  @override
  String get categoriesCouldnTLoad => 'Categories couldn’t load.';

  @override
  String get loadingCategories => 'Loading categories…';

  @override
  String get categoriesUnavailable => 'Categories unavailable';

  @override
  String allCategories(String choicesLength) {
    return 'All categories · $choicesLength';
  }

  @override
  String get searchAllCategories => 'Search all categories';

  @override
  String get searchAllCategoriesGlobalsearchcategoryeditor =>
      'Search all categories…';

  @override
  String get clearCategorySearch => 'Clear category search';

  @override
  String get noCategoriesAvailable => 'No categories available.';

  @override
  String get noMatchingCategories => 'No matching categories.';

  @override
  String get showAllCategories => 'Show all categories';

  @override
  String get loadMoreCategories => 'Load more categories';

  @override
  String get chooseOneOrMoreCategories => 'Choose one or more categories.';

  @override
  String removeGlobalsearchcategoryeditor(String labelValue) {
    return 'Remove $labelValue';
  }

  @override
  String get includeSubcategoriesGlobalsearchcategoryeditor =>
      'Include subcategories';

  @override
  String get thisDraftCouldNotBeSavedYetPleaseTryAgain =>
      'This draft could not be saved yet. Please try again.';

  @override
  String get finishTheCurrentOperationBeforeClosingThisDraft =>
      'Finish the current operation before closing this draft.';

  @override
  String get thisDraftChangedWhileTheConfirmationWasOpenCancelReviewIt =>
      'This draft changed while the confirmation was open. Cancel, review it, and try again.';

  @override
  String get doYouWantToDiscardYourChanges =>
      'Do you want to discard your changes?';

  @override
  String get doYouWantToDiscardYourPost => 'Do you want to discard your post?';

  @override
  String get discardChanges => 'Discard changes';

  @override
  String get selectedText => 'Selected text';

  @override
  String get saveEditPostfastedit => 'Save Edit';

  @override
  String get allThemes => 'All themes';

  @override
  String get nameThisTheme => 'Name this theme';

  @override
  String get accent => 'Accent';

  @override
  String get highlight => 'Highlight';

  @override
  String get success => 'Success';

  @override
  String get attention => 'Attention';

  @override
  String get startsFromTheThemeInUseNameItToKeepIt =>
      'Starts from the theme in use. Name it to keep it.';

  @override
  String get createTheme => 'Create theme';

  @override
  String get saveTheme => 'Save theme';

  @override
  String colourPalette(String label) {
    return '$label colour palette';
  }

  @override
  String hexColour(String label) {
    return '$label hex colour';
  }

  @override
  String chooseColour(String label) {
    return 'Choose $label colour';
  }

  @override
  String get useRRGGBB => 'Use #RRGGBB.';

  @override
  String get errors => 'Errors';

  @override
  String get searchDiagnostics => 'Search diagnostics';

  @override
  String get severity => 'Severity';

  @override
  String get eventCopied => 'Event copied';

  @override
  String get filteredReportCopied => 'Filtered report copied';

  @override
  String get clearDiagnosticsHistory => 'Clear diagnostics history?';

  @override
  String get thisRemovesTheRecordedRequestsAndErrorsFromThisDeviceRequests =>
      'This removes the recorded requests and errors from this device. Requests already in progress will not be restored afterward.';

  @override
  String get backToDiagnostics => 'Back to diagnostics';

  @override
  String get eventDetails => 'Event details';

  @override
  String get resumeLiveUpdates => 'Resume live updates';

  @override
  String get freezeVisibleEvents => 'Freeze visible events';

  @override
  String get copyFilteredReport => 'Copy filtered report';

  @override
  String get closeDiagnostics => 'Close diagnostics';

  @override
  String get general => 'General';

  @override
  String get scrollPerformance => 'Scroll performance';

  @override
  String get scrollPerformanceCapture => 'Scroll performance capture';

  @override
  String get recordScrollingInATopicTopicListOrUsersDirectoryThen =>
      'Record scrolling in a topic, topic list or users directory, then copy a performance report to share for investigation. The capture stays in memory and never includes post bodies, titles, site URLs, or credentials.';

  @override
  String closeDiagnosticsReproduceTheIssueInATopicTopicListOr(
    String controllerMaximumDurationInMinutes,
    String controllerMaximumEvents,
  ) {
    return 'Close Diagnostics, reproduce the issue in a topic, topic list or users directory, then return here and stop the capture. Scroll for 5–10 seconds, then wait a second for frame timings before stopping. Recording stops automatically after $controllerMaximumDurationInMinutes minutes or $controllerMaximumEvents events.';
  }

  @override
  String get stopCapture => 'Stop capture';

  @override
  String get copyPerformanceReport => 'Copy performance report';

  @override
  String get copyFullJSONCapture => 'Copy full JSON capture';

  @override
  String get startANewCapture => 'Start a new capture';

  @override
  String get discardCapture => 'Discard capture';

  @override
  String get theTraceIncludesTopicListRowBuildsAndScrollBookkeepingTopic =>
      'The trace includes topic-list row builds and scroll bookkeeping, topic scroll notifications, post-sliver visible range and geometry update, paging and anchor decision, row layout cost, viewport bookkeeping cost, and Flutter frame timing. The performance report summarizes slow frames and the most expensive posts without copying the full event log.';

  @override
  String get startCapture => 'Start capture';

  @override
  String get performanceReportCopied => 'Performance report copied';

  @override
  String get scrollCaptureCopied => 'Scroll capture copied';

  @override
  String eventsOverSTopicEventsFramesSlowBuildsSlowRastersBudget(
    String stateEventCount,
    String secondsToStringAsFixed,
    String stateTopicEventCount,
    String stateFrameCount,
    String stateSlowBuildFrameCount,
    String stateSlowRasterFrameCount,
    String stateFrameBudgetMicrosecondsToStringAsFi,
    String stateDisplayRefreshRateToStringAsFixed,
  ) {
    return '$stateEventCount events over ${secondsToStringAsFixed}s\n$stateTopicEventCount topic events · $stateFrameCount frames\n$stateSlowBuildFrameCount slow builds · $stateSlowRasterFrameCount slow rasters\nBudget: $stateFrameBudgetMicrosecondsToStringAsFi ms at $stateDisplayRefreshRateToStringAsFixed Hz';
  }

  @override
  String get stoppedAtTimeLimit => 'Stopped at time limit';

  @override
  String get stoppedAtEventLimit => 'Stopped at event limit';

  @override
  String get captureReady => 'Capture ready';

  @override
  String filterBy(String label) {
    return 'Filter by $label';
  }

  @override
  String get noMatchingEvents => 'No matching events';

  @override
  String get noDiagnosticsYet => 'No diagnostics yet';

  @override
  String get changeTheFiltersOrSearchToSeeMore =>
      'Change the filters or search to see more.';

  @override
  String get requestsLogsAndOperationalErrorsWillAppearHere =>
      'Requests, logs, and operational errors will appear here.';

  @override
  String session(String stateName) {
    return 'Session $stateName';
  }

  @override
  String get previousMessage => 'Previous message';

  @override
  String get nextMessage => 'Next message';

  @override
  String get dismissNewTopics => 'Dismiss new topics';

  @override
  String get dismissNewReplies => 'Dismiss new replies';

  @override
  String get dismissNew => 'Dismiss New';

  @override
  String viewProfileForUsercard(String username) {
    return 'View profile for @$username';
  }

  @override
  String get profilePreviewUnavailable => 'Profile preview unavailable.';

  @override
  String profileFor(String username) {
    return 'Profile for @$username';
  }

  @override
  String get loadingProfile => 'Loading profile';

  @override
  String get viewProfile => 'View profile';

  @override
  String get timeRead => 'Time read';

  @override
  String imageOfXPixelsExceedsTheDecodeLimit(String width, String height) {
    return 'Image of ${width}x$height pixels exceeds the decode limit';
  }

  @override
  String get invites => 'Invites';

  @override
  String get other => 'Other';

  @override
  String get setACustomStatus => 'Set a custom status';

  @override
  String get pauseNotifications => 'Pause notifications';

  @override
  String get drafts => 'Drafts';

  @override
  String get disconnect => 'Disconnect';

  @override
  String get notificationsPaused => 'Notifications paused';

  @override
  String get offline => 'Offline';

  @override
  String get presenceUnavailable => 'Presence unavailable';

  @override
  String get statusAndNotifications => 'Status and notifications';

  @override
  String statusAndNotificationsUsermenu(String label) {
    return 'Status and notifications, $label';
  }

  @override
  String get savingUsermenu => 'Saving';

  @override
  String get onNoExpiration => 'On, no expiration';

  @override
  String onUntil(
    String localizationsFormatMediumDateUntil,
    String clockTimeLabelContextUntil,
  ) {
    return 'On, until $localizationsFormatMediumDateUntil $clockTimeLabelContextUntil';
  }

  @override
  String get loadingPresence => 'Loading presence…';

  @override
  String get presence => 'Presence';

  @override
  String get retryLoadingThePresenceSetting =>
      'Retry loading the presence setting';

  @override
  String get togglePresenceFeatures => 'Toggle presence features';

  @override
  String get thisSiteIsNoLongerAvailable => 'This site is no longer available.';

  @override
  String get thisAccountIsNoLongerConnected =>
      'This account is no longer connected.';

  @override
  String get thisSectionIsNoLongerAvailable =>
      'This section is no longer available.';

  @override
  String continueTheDiscussionFrom(String escaped, String url) {
    return 'Continue the discussion from [$escaped]($url)';
  }

  @override
  String get shareThisTopic => 'Share this topic';

  @override
  String sharePost(String postNumber) {
    return 'Share post #$postNumber';
  }

  @override
  String get replyAsNewMessage => 'Reply as new message';

  @override
  String get replyAsNewTopic => 'Reply as new topic';

  @override
  String get couldnTOpenSharing => 'Couldn\'t open sharing.';

  @override
  String get shareToAnotherApp => 'Share to another app';

  @override
  String get allBadges => 'All badges';

  @override
  String get youEarnedThisBadge => 'You earned this badge';

  @override
  String get canBeEarnedMultipleTimes => 'Can be earned multiple times';

  @override
  String get canBeUsedAsATitle => 'Can be used as a title';

  @override
  String get recentlyAwarded => 'Recently awarded';

  @override
  String awardedTo(String routeUsername) {
    return 'Awarded to $routeUsername';
  }

  @override
  String get showAllRecipients => 'Show all recipients';

  @override
  String get showYourAwards => 'Show your awards';

  @override
  String get noAwardsToDisplay => 'No awards to display.';

  @override
  String get earned => 'Earned';

  @override
  String get notEarned => 'Not earned';

  @override
  String get bronze => 'Bronze';

  @override
  String get silver => 'Silver';

  @override
  String get gold => 'Gold';

  @override
  String get filterBadges => 'Filter badges';

  @override
  String get noBadgesToDisplay => 'No badges to display.';

  @override
  String get noBadgesMatchThisFilter => 'No badges match this filter.';

  @override
  String get viewAwardedPost => 'View awarded post';

  @override
  String get enterAStatusDescription => 'Enter a status description.';

  @override
  String get setCustomStatus => 'Set custom status';

  @override
  String get chooseStatusEmoji => 'Choose status emoji';

  @override
  String get statusEmoji => 'Status emoji';

  @override
  String get whatSYourStatus => 'What’s your status?';

  @override
  String get whatAreYouUpTo => 'What are you up to?';

  @override
  String get clearAfter => 'Clear after';

  @override
  String get message1Hour => '1 hour';

  @override
  String get message2Hours => '2 hours';

  @override
  String get tomorrow => 'Tomorrow';

  @override
  String until(
    String contextFormatMediumDateUntil,
    String clockTimeLabelContextUntil,
  ) {
    return 'Until $contextFormatMediumDateUntil $clockTimeLabelContextUntil';
  }

  @override
  String get preview => 'Preview: ';

  @override
  String get clearStatus => 'Clear status';

  @override
  String get openNextTopic => 'Open next topic';

  @override
  String get openPreviousTopic => 'Open previous topic';

  @override
  String get nextTopicInTheList => 'Next topic in the list';

  @override
  String get previousTopicInTheList => 'Previous topic in the list';

  @override
  String get openHighlightedTopic => 'Open highlighted topic';

  @override
  String get nextPostOrTopic => 'Next post or topic';

  @override
  String get previousPostOrTopic => 'Previous post or topic';

  @override
  String get replyToSelectedPost => 'Reply to selected post';

  @override
  String get january => 'January';

  @override
  String get february => 'February';

  @override
  String get march => 'March';

  @override
  String get may => 'May';

  @override
  String get september => 'September';

  @override
  String get december => 'December';

  @override
  String get newNotification => 'New notification';

  @override
  String mentionedYouInNotificationtypes(String title) {
    return 'mentioned you in $title';
  }

  @override
  String repliedTo(String title) {
    return 'replied to $title';
  }

  @override
  String quotedYouIn(String title) {
    return 'quoted you in $title';
  }

  @override
  String editedYourPostIn(String title) {
    return 'edited your post in $title';
  }

  @override
  String likedYourPostIn(String title) {
    return 'liked your post in $title';
  }

  @override
  String linkedToYourPostFrom(String title) {
    return 'linked to your post from $title';
  }

  @override
  String sentYou(String title) {
    return 'sent you $title';
  }

  @override
  String invitedYouToNotificationtypes(String title) {
    return 'invited you to $title';
  }

  @override
  String get acceptedYourInvitation => 'accepted your invitation';

  @override
  String postedIn(String title) {
    return 'posted in $title';
  }

  @override
  String youEarnedTheBadge(String badge) {
    return 'You earned the $badge badge';
  }

  @override
  String get youEarnedABadge => 'You earned a badge';

  @override
  String inYourInbox(String countLabelCountMessage, String group) {
    return '$countLabelCountMessage in your $group inbox';
  }

  @override
  String youReNowAMemberOf(String group) {
    return 'You\'re now a member of $group';
  }

  @override
  String get membershipRequest => 'membership request';

  @override
  String reminderNotificationtypes(String reminderTitleNotification) {
    return 'Reminder: $reminderTitleNotification';
  }

  @override
  String yourPostInWasApproved(String title) {
    return 'Your post in $title was approved';
  }

  @override
  String get newFeaturesAreAvailable => 'New features are available';

  @override
  String get thereIsNewAdviceOnYourSiteDashboard =>
      'There is new advice on your site dashboard';

  @override
  String get upcomingChangesWereAutomaticallyEnabled =>
      'Upcoming changes were automatically enabled';

  @override
  String get upcomingChangesAreAvailableForPreview =>
      'Upcoming changes are available for preview';

  @override
  String hasBeenAutomaticallyEnabled(String namesFirst) {
    return '\'$namesFirst\' has been automatically enabled';
  }

  @override
  String isAvailableForPreview(String namesFirst) {
    return '\'$namesFirst\' is available for preview';
  }

  @override
  String andWereAutomaticallyEnabled(String names, String namesValue2) {
    return '\'$names\' and \'$namesValue2\' were automatically enabled';
  }

  @override
  String andAreAvailableForPreview(String names, String namesValue2) {
    return '\'$names\' and \'$namesValue2\' are available for preview';
  }

  @override
  String andMoreChangesWereAutomaticallyEnabled(
    String namesFirst,
    String otherCount,
  ) {
    return '\'$namesFirst\' and $otherCount more changes were automatically enabled';
  }

  @override
  String andMoreChangesAreAvailableForPreview(
    String namesFirst,
    String otherCount,
  ) {
    return '\'$namesFirst\' and $otherCount more changes are available for preview';
  }

  @override
  String get oneOfYourPosts => 'one of your posts';

  @override
  String ofYourPosts(String count) {
    return '$count of your posts';
  }

  @override
  String get directoryColumnIsMissingItsName =>
      'Directory column is missing its name.';

  @override
  String get repliesPosted => 'Replies posted';

  @override
  String get directoryUserIsMissingAUsername =>
      'Directory user is missing a username.';

  @override
  String get groupFlair => 'Group flair';

  @override
  String get community => 'Community';

  @override
  String get admin => 'Admin';

  @override
  String get invalidGroupDirectoryRoute => 'Invalid group directory route';

  @override
  String get invalidGroupRouteName => 'Invalid group route name';

  @override
  String get invalidGroupRoute => 'Invalid group route';

  @override
  String get untitledDraft => 'Untitled draft';

  @override
  String get newPersonalMessageDraft => 'New personal message draft';

  @override
  String get newTopicDraft => 'New topic draft';

  @override
  String get editTopicDraft => 'Edit topic draft';

  @override
  String get personalMessageDraft => 'Personal message draft';

  @override
  String get replyDraft => 'Reply draft';

  @override
  String comparingVersionToOf(String previous, String current, String total) {
    return 'Comparing version $previous to $current of $total';
  }

  @override
  String get invalidForumTabAnchor => 'Invalid forum tab anchor';

  @override
  String get invalidThemes => 'Invalid themes.';

  @override
  String myThemeForumthemepreferences(String copy) {
    return 'My theme $copy';
  }

  @override
  String get systemDefault => 'System default';

  @override
  String get openSans => 'Open Sans';

  @override
  String get lato => 'Lato';

  @override
  String get jetBrainsMono => 'JetBrains Mono';

  @override
  String get invalidTheme => 'Invalid theme.';

  @override
  String invalidColor(String key) {
    return 'Invalid $key color.';
  }

  @override
  String invalidOption(String key) {
    return 'Invalid $key option.';
  }

  @override
  String get invalidTint => 'Invalid tint.';

  @override
  String get invalidAlternatePalette => 'Invalid alternate palette.';

  @override
  String get duplicatePaletteMode => 'Duplicate palette mode.';

  @override
  String get pending => 'Pending';

  @override
  String get noPendingInvites => 'No pending invites.';

  @override
  String get noExpiredInvites => 'No expired invites.';

  @override
  String get redeemed => 'Redeemed';

  @override
  String get noRedeemedInvitesYet => 'No redeemed invites yet.';

  @override
  String get inviteLink => 'Invite link';

  @override
  String incomingTopicsFilterCategoryIdTagIds(
    String countsBumps,
    String categoryId,
    String tagIds,
  ) {
    String _temp0 = intl.Intl.selectLogic(countsBumps, {
      'true':
          'IncomingTopicsFilter.latest(categoryId: $categoryId, tagIds: $tagIds)',
      'other':
          'IncomingTopicsFilter.created(categoryId: $categoryId, tagIds: $tagIds)',
    });
    return '$_temp0';
  }

  @override
  String get string => 'String';

  @override
  String composerUploadSizeLimitEnforced(String maxBytes, String enforced) {
    return 'ComposerUploadSizeLimit($maxBytes, enforced: $enforced)';
  }

  @override
  String isTooLargeToUpload(String filename) {
    return '$filename is too large to upload.';
  }

  @override
  String isTooLargeMaximumSizeIs(
    String filename,
    String humanFileSizeMaxBytes,
  ) {
    return '$filename is too large (maximum size is $humanFileSizeMaxBytes).';
  }

  @override
  String get tooManyUploadsPleaseWaitAndRetry =>
      'Too many uploads. Please wait and retry.';

  @override
  String tooManyUploadsTryAgainIn(String countLabelSecondsSecond) {
    return 'Too many uploads. Try again in $countLabelSecondsSecond.';
  }

  @override
  String composerUploadException(String statusCode, String message) {
    return 'ComposerUploadException($statusCode, $message)';
  }

  @override
  String get tagsAreNotAllowedHere => 'Tags are not allowed here.';

  @override
  String get in2Hours => 'In 2 hours';

  @override
  String get in3Days => 'In 3 days';

  @override
  String get laterToday => 'Later today';

  @override
  String get laterThisWeek => 'Later this week';

  @override
  String get thisWeekend => 'This weekend';

  @override
  String get nextMonday => 'Next Monday';

  @override
  String get monday => 'Monday';

  @override
  String get sent => 'Sent';

  @override
  String get badge => 'Badge';

  @override
  String get newTopicsContentroute => 'New - topics';

  @override
  String get newRepliesContentroute => 'New - replies';

  @override
  String topContentroute(String modeTopPeriodLabel) {
    return 'Top - $modeTopPeriodLabel';
  }

  @override
  String get invalidContentRoute => 'Invalid content route';

  @override
  String get invalidContentRouteTopicId => 'Invalid content route topic id';

  @override
  String get invalidContentRoutePostNumber =>
      'Invalid content route post number';

  @override
  String get invalidContentRouteFeedPath => 'Invalid content route feed path';

  @override
  String get invalidContentRouteMessageGroup =>
      'Invalid content route message group';

  @override
  String get invalidContentGroupRoute => 'Invalid content group route';

  @override
  String get invalidContentBadgeRoute => 'Invalid content badge route';

  @override
  String get message30Minutes => '30 minutes';

  @override
  String get untilTomorrow => 'Until tomorrow';

  @override
  String get allCategoriesCategorysidebar => 'All categories';

  @override
  String get invalidBadgeRoute => 'Invalid badge route';

  @override
  String missingPaletteColor(String name) {
    return 'Missing palette color $name';
  }

  @override
  String get invalidAppearance => 'Invalid appearance.';

  @override
  String get keepTopicTabsWithTheList => 'Keep topic tabs with the list';

  @override
  String get splitWithTheList => 'Split with the list';

  @override
  String get invalidBackground => 'Invalid background.';

  @override
  String get dockLeft => 'Dock left';

  @override
  String get dockBottom => 'Dock bottom';

  @override
  String get dockRight => 'Dock right';

  @override
  String get themeTokens => 'Theme tokens';

  @override
  String get typography => 'Typography';

  @override
  String get motion => 'Motion';

  @override
  String get spacing => 'Spacing';

  @override
  String get browseComponents => 'Browse components';

  @override
  String get discourseUi => 'Discourse / ui';

  @override
  String get components => 'Components';

  @override
  String get toggleDocumentationTheme => 'Toggle documentation theme';

  @override
  String get closeStyleguide => 'Close styleguide';

  @override
  String get searchComponents => 'Search components...';

  @override
  String get componentNavigation => 'Component navigation';

  @override
  String get noComponentsMatchYourSearch => 'No components match your search.';

  @override
  String get gettingStarted => 'Getting started';

  @override
  String get previousComponent => 'Previous component';

  @override
  String get nextComponent => 'Next component';

  @override
  String get theme => 'Theme';

  @override
  String get viewportWidth => 'Viewport width';

  @override
  String get message360Px => '360 px';

  @override
  String get message768Px => '768 px';

  @override
  String get message1024Px => '1024 px';

  @override
  String get previewSettings => 'Preview settings';

  @override
  String get resetExamples => 'Reset examples';

  @override
  String get textScale => 'Text scale';

  @override
  String get rightToLeft => 'Right to left';

  @override
  String get reduceMotion => 'Reduce motion';

  @override
  String get onThisPage => 'On This Page';

  @override
  String get hideCode => 'Hide code';

  @override
  String get viewCode => 'View code';

  @override
  String get lucide => 'Lucide';

  @override
  String get phosphor => 'Phosphor';

  @override
  String get tabler => 'Tabler';

  @override
  String get inProcessDartHTTP => 'in-process Dart HTTP';

  @override
  String get flutterFrameworkErrors => 'Flutter framework errors';

  @override
  String get rootIsolatePlatformErrors => 'root-isolate platform errors';

  @override
  String get reportedOperationalErrors => 'reported operational errors';

  @override
  String get reportedStructuredApplicationLogs =>
      'reported structured application logs';

  @override
  String get externalBrowserAndWebAuthTraffic =>
      'external browser and web-auth traffic';

  @override
  String get nativePluginInternalNetworking =>
      'native-plugin-internal networking';

  @override
  String get spawnedIsolatesWithoutTheHTTPOverride =>
      'spawned isolates without the HTTP override';

  @override
  String get nativeProcessCrashes => 'native process crashes';

  @override
  String diagnosticsPersistenceIsUnavailableHistoryIsMemoryOnly(
    String safeErrorMessageError,
  ) {
    return 'Diagnostics persistence is unavailable; history is memory-only. $safeErrorMessageError';
  }

  @override
  String get topicScrollAndMetricsNotifications =>
      'topic scroll and metrics notifications';

  @override
  String get superListViewSliverLayoutAndVisibleRanges =>
      'SuperListView sliver layout and visible ranges';

  @override
  String get visiblePostGeometryAndRowAttachmentLifecycle =>
      'visible post geometry and row attachment lifecycle';

  @override
  String get topicWindowPagingAndExtentInvalidationDecisions =>
      'topic window, paging, and extent invalidation decisions';

  @override
  String get viewportAnchorCaptureAndCorrectionDecisions =>
      'viewport anchor capture and correction decisions';

  @override
  String get flutterUIThreadBuildAndRasterFrameTimings =>
      'Flutter UI-thread build and raster frame timings';

  @override
  String get postLayoutAndViewportBookkeepingDurations =>
      'post layout and viewport bookkeeping durations';

  @override
  String get topicListRowSubtreeBuildAndLayoutDurations =>
      'topic-list row subtree build and layout durations';

  @override
  String get sampledCPUFunctionsInSlowTopicFramesWhenAvailable =>
      'sampled CPU functions in slow topic frames when available';

  @override
  String get recordedRenderingPhasesInSlowTopicRasterFramesWhenAvailable =>
      'recorded rendering phases in slow topic raster frames when available';

  @override
  String get postBodiesAndTitles => 'post bodies and titles';

  @override
  String get siteURLsAndCredentials => 'site URLs and credentials';

  @override
  String get nativeCompositorAndOperatingSystemTraces =>
      'native compositor and operating-system traces';

  @override
  String topicScrollingPerformanceReportV(String reportVersion) {
    return 'Topic scrolling performance report (v$reportVersion)';
  }

  @override
  String app(
    String appVersion,
    String appBuildChannel,
    String appBuildMode,
    String appPlatform,
    String appVersionValue5,
  ) {
    String _temp0 = intl.Intl.selectLogic(appVersion, {
      'true':
          'App: local build | $appBuildChannel | $appBuildMode | $appPlatform',
      'other':
          'App: $appVersionValue5 | $appBuildChannel | $appBuildMode | $appPlatform',
    });
    return '$_temp0';
  }

  @override
  String recordedS(
    String startedAtUtcNoCapture,
    String captureDurationUsToStringAsFixed,
    String captureStatus,
    String stopReasonInProgress,
  ) {
    return 'Recorded: $startedAtUtcNoCapture | ${captureDurationUsToStringAsFixed}s | $captureStatus ($stopReasonInProgress)';
  }

  @override
  String displayAtStartHzFrameBudgetMs(
    String summaryDisplayRefreshRate,
    String msAnalysisFrameBudgetUs,
  ) {
    return 'Display at start: $summaryDisplayRefreshRate Hz | frame budget $msAnalysisFrameBudgetUs ms';
  }

  @override
  String eventsSampledFramesFramesWithTopicActivity(
    String summaryEventCount,
    String allFramesCount,
    String topicFramesCount,
  ) {
    return 'Events: $summaryEventCount | sampled frames: $allFramesCount | frames with topic activity: $topicFramesCount';
  }

  @override
  String accessibilityAtStartAtEndPlatformRequestStateChanges(
    String enabledAccessibilityFrameworkEnabledAtSt,
    String enabledAccessibilityFrameworkEnabledAtEn,
    String enabledAccessibilityPlatformEnabledAtSta,
    String accessibilityStateChanges,
  ) {
    return 'Accessibility: $enabledAccessibilityFrameworkEnabledAtSt at start, $enabledAccessibilityFrameworkEnabledAtEn at end | platform request $enabledAccessibilityPlatformEnabledAtSta | $accessibilityStateChanges state changes';
  }

  @override
  String get debugBuildRepeatInAProfileOrReleaseBuildToAssess =>
      'Debug build: repeat in a profile or release build to assess the scrolling performance users experience.';

  @override
  String get theEventLimitEndedThisCaptureEarlyReproduceWithAShorter =>
      'The event limit ended this capture early. Reproduce with a shorter capture if the slow moment was missed.';

  @override
  String get noContextWasRecordedStartInTheAffectedScreenAndScroll =>
      'No context was recorded. Start in the affected screen and scroll before stopping.';

  @override
  String get noFrameTimingsWereDeliveredScrollForSeveralSecondsAndWait =>
      'No frame timings were delivered. Scroll for several seconds and wait a second before stopping.';

  @override
  String get framesWithScrollActivity => 'Frames with scroll activity:';

  @override
  String get allSampledAppFramesNoTopicFrameMatches =>
      'All sampled app frames (no topic frame matches):';

  @override
  String overBudgetUIRaster(
    String measuredOverBudget,
    String measuredCount,
    String measuredCountToStringAsFixed,
    String measuredSlowBuilds,
    String measuredSlowRasters,
  ) {
    return 'Over budget: $measuredOverBudget/$measuredCount ($measuredCountToStringAsFixed%) | UI: $measuredSlowBuilds | raster: $measuredSlowRasters';
  }

  @override
  String raster(String mapMeasuredRasterUs) {
    return 'Raster: $mapMeasuredRasterUs';
  }

  @override
  String vsyncDelay(String mapMeasuredVsyncOverheadUs) {
    return 'Vsync delay: $mapMeasuredVsyncOverheadUs';
  }

  @override
  String totalFrameLatency(String mapMeasuredTotalSpanUs) {
    return 'Total frame latency: $mapMeasuredTotalSpanUs';
  }

  @override
  String viewportBookkeeping(String mapAnalysisViewportWorkUs) {
    return 'Viewport bookkeeping: $mapAnalysisViewportWorkUs';
  }

  @override
  String postRowLayout(String mapAnalysisPostLayoutUs) {
    return 'Post row layout: $mapAnalysisPostLayoutUs';
  }

  @override
  String topicListScrollBookkeeping(String mapAnalysisTopicListScrollWorkUs) {
    return 'Topic-list scroll bookkeeping: $mapAnalysisTopicListScrollWorkUs';
  }

  @override
  String topicListRowBuild(String mapAnalysisTopicListRowBuildUs) {
    return 'Topic-list row build: $mapAnalysisTopicListRowBuildUs';
  }

  @override
  String topicListRowLayout(String mapAnalysisTopicListRowLayoutUs) {
    return 'Topic-list row layout: $mapAnalysisTopicListRowLayoutUs';
  }

  @override
  String topicListLoadedTopicsInboxViewportExtent(
    String listTopicCount,
    String listInbox,
    String listViewportExtent,
  ) {
    return 'Topic list: $listTopicCount loaded topics | inbox $listInbox | viewport extent $listViewportExtent';
  }

  @override
  String usersDirectoryLoadedUsersColumnsViewportExtent(
    String usersRowCount,
    String usersColumnCount,
    String usersViewportExtent,
  ) {
    return 'Users directory: $usersRowCount loaded users | $usersColumnCount columns | viewport extent $usersViewportExtent';
  }

  @override
  String usersMetricMaxima(String mapAnalysisUsersMaximaWorkUs) {
    return 'Users metric maxima: $mapAnalysisUsersMaximaWorkUs';
  }

  @override
  String topicLoadedPostsViewportPixelRatio(
    String topicTopicId,
    String topicLoadedPostCount,
    String topicStreamPostCount,
    String topicViewportLogicalSizeWidth,
    String topicViewportLogicalSizeHeight,
    String topicDevicePixelRatio,
  ) {
    return 'Topic $topicTopicId: $topicLoadedPostCount loaded / $topicStreamPostCount posts | viewport $topicViewportLogicalSizeWidth × $topicViewportLogicalSizeHeight | pixel ratio $topicDevicePixelRatio';
  }

  @override
  String get mostExpensivePostLayoutsUpTo8ByWorstLayout =>
      'Most expensive post layouts (up to 8, by worst layout):';

  @override
  String topicPostIdHTMLCharacters(
    String postTopicId,
    String postPostId,
    String postHtmlCharacters,
    String mapPostLayoutUs,
  ) {
    return '  Topic $postTopicId, post id $postPostId, $postHtmlCharacters HTML characters: $mapPostLayoutUs';
  }

  @override
  String get worstSampledFramesUpTo5ByUIRasterDuration =>
      'Worst sampled frames (up to 5, by UI/raster duration):';

  @override
  String frameUIMsRasterMs(
    String frameFrameNumber,
    String msFrameBuildUs,
    String msFrameRasterUs,
    String frameTopicActivityLimit,
  ) {
    return '  Frame $frameFrameNumber: UI $msFrameBuildUs ms, raster $msFrameRasterUs ms; $frameTopicActivityLimit';
  }

  @override
  String measuredRowLayoutMsViewportMsTopicListBuildMsLayout(
    String workPostLayout,
    String workViewportWork,
    String topicListRowBuild,
    String topicListRowLayout,
  ) {
    return '    Measured row layout $workPostLayout ms; viewport $workViewportWork ms; topic-list build $topicListRowBuild ms, layout $topicListRowLayout ms';
  }

  @override
  String renderingMsOutsidePhaseMarkers(
    String phasesIsEmpty,
    String msRenderingOutsidePhaseMarkersUs,
    String durationUsMsJoin,
  ) {
    String _temp0 = intl.Intl.selectLogic(phasesIsEmpty, {
      'true':
          '    Rendering: no named phases; $msRenderingOutsidePhaseMarkersUs ms outside phase markers',
      'other':
          '    Rendering: $durationUsMsJoin; $msRenderingOutsidePhaseMarkersUs ms outside phase markers',
    });
    return '$_temp0';
  }

  @override
  String activityCounts(String analysisActivityCountsLimit) {
    return 'Activity counts: $analysisActivityCountsLimit';
  }

  @override
  String
  get interpretationUIOverrunsPointToBuildLayoutPaintWorkRasterOverruns =>
      'Interpretation: UI overruns point to build/layout/paint work; raster overruns point to drawing/compositing. Viewport and row timings measure those operations only; they do not cover all UI work. Activity in a slow frame is correlation, not proof of its cause.';

  @override
  String get timingsCoverFramesDeliveredBeforeStopNotIdleTimeOrNative =>
      'Timings cover frames delivered before Stop, not idle time or native compositor stalls. UI and raster overlap; their sum is not a dropped-frame count. Topic frame matches use engine frame numbers.';

  @override
  String get postContentsTitlesSiteURLsAndCredentialsAreExcludedTheFull =>
      'Post contents, titles, site URLs, and credentials are excluded. The full JSON capture is available separately.';

  @override
  String get cPUSamplingRequiresADebugOrProfileBuild =>
      'CPU sampling requires a debug or profile build.';

  @override
  String get runFlutterWithEnableDartProfilingAndCaptureAgain =>
      'Run Flutter with --enable-dart-profiling and capture again.';

  @override
  String get startTheAppWithFlutterRunInDebugOrProfileMode =>
      'Start the app with flutter run in debug or profile mode.';

  @override
  String get stopTheCaptureBeforeExportingCPUSamples =>
      'Stop the capture before exporting CPU samples.';

  @override
  String get noCaptureHasBeenRecorded => 'No capture has been recorded.';

  @override
  String get theDartVMServiceCouldNotSupplyCPUSamples =>
      'The Dart VM service could not supply CPU samples.';

  @override
  String cPUProfileUnavailable(String reason) {
    return 'CPU profile unavailable: $reason';
  }

  @override
  String cPUSamplingCaptureSamplesInSlowTopicUIFramesPeriodMs(
    String captureSampleCount,
    String slowSampleCount,
    String msProfileSamplePeriodUs,
  ) {
    return 'CPU sampling: $captureSampleCount capture samples | $slowSampleCount in slow topic UI frames | period $msProfileSamplePeriodUs ms';
  }

  @override
  String get noCPUSamplesRemainForThisCaptureCopySoonAfterStopping =>
      'No CPU samples remain for this capture. Copy soon after stopping; the VM overwrites old samples.';

  @override
  String get cPUFunctionsInSlowTopicFramesExclusiveSamples =>
      'CPU functions in slow topic frames (exclusive samples):';

  @override
  String get cPUFunctionsAcrossTheCaptureNoSlowFrameSamples =>
      'CPU functions across the capture (no slow-frame samples):';

  @override
  String cPURuntimeTags(String selectedSampleCountJoin) {
    return 'CPU runtime tags: $selectedSampleCountJoin';
  }

  @override
  String get frequentSampledCallPathsLeafCallers =>
      'Frequent sampled call paths (leaf ← callers):';

  @override
  String get cPUSamplesAreStatisticalAndMayBeIncompleteTheyAreNot =>
      'CPU samples are statistical and may be incomplete. They are not exact durations; debug compilation, assertions, and GC can appear here.';

  @override
  String get renderingTimelineUnavailableRunInProfileModeToRecordEnginePhases =>
      'Rendering timeline unavailable. Run in profile mode to record engine phases.';

  @override
  String get renderingTimelineNoOverBudgetTopicRasterFrames =>
      'Rendering timeline: no over-budget topic raster frames.';

  @override
  String renderingTimelineProfiledSlowRasterFramesMatchedUpTo20Of(
    String profileMatchedFrameCount,
    String profileProfiledFrameCount,
    String requested,
  ) {
    return 'Rendering timeline: $profileMatchedFrameCount/$profileProfiledFrameCount profiled slow raster frames matched (up to 20 of $requested).';
  }

  @override
  String engineMarkersRetainedDuringCaptureIncludingTheFinalSnapshotDiscardedAt(
    String intProfileStreamedEventCount,
    String intProfileRetainedEventCount,
    String intProfileDiscardedEventCount,
  ) {
    return 'Engine markers retained during capture: $intProfileStreamedEventCount; $intProfileRetainedEventCount including the final snapshot; $intProfileDiscardedEventCount discarded at the capture limit.';
  }

  @override
  String get liveTimelineCollectionAddsDiagnosticOverheadDuringRecording =>
      'Live timeline collection adds diagnostic overhead during recording.';

  @override
  String get finalEngineSnapshotUnavailableTheLastEventBlockMayBeMissing =>
      'Final engine snapshot unavailable; the last event block may be missing.';

  @override
  String get renderingUsesTheRollingVMBufferLiveRecordingWasUnavailable =>
      'Rendering uses the rolling VM buffer; live recording was unavailable.';

  @override
  String get olderThanTheRetainedEngineTrace =>
      'older than the retained engine trace';

  @override
  String get newerThanTheRetainedEngineTrace =>
      'newer than the retained engine trace';

  @override
  String get multipleRasterThreadsMatch => 'multiple raster threads match';

  @override
  String get noEngineFrameMarkersWereRecorded =>
      'no engine frame markers were recorded';

  @override
  String get noOverlappingEngineFrameMarker =>
      'no overlapping engine frame marker';

  @override
  String renderingFrameUnmatched(String frameFrameNumber, String reason) {
    return '  Rendering frame $frameFrameNumber unmatched: $reason.';
  }

  @override
  String get renderingDataIsIncompleteTheStallCannotBeAttributedToAn =>
      'Rendering data is incomplete; the stall cannot be attributed to an engine phase.';

  @override
  String
  get renderingPhasesAreRecordedEngineDurationsNotGPUExecutionTimesNested =>
      'Rendering phases are recorded engine durations, not GPU execution times. Nested phases overlap; do not add them.';

  @override
  String get noSamples => 'no samples';

  @override
  String moreEventTypesInJSON(String rankedLengthLimit) {
    return '$rankedLengthLimit more event types in JSON';
  }

  @override
  String get expectedAJSONList => 'Expected a JSON list';

  @override
  String get missingDiscoverCommunities => 'Missing Discover communities.';

  @override
  String get expectedATopicTrackingStateList =>
      'Expected a topic tracking state list';

  @override
  String get bookmarkNotesMustBe100CharactersOrFewer =>
      'Bookmark notes must be 100 characters or fewer.';

  @override
  String get bookmarkRemindersMustBeInTheFuture =>
      'Bookmark reminders must be in the future.';

  @override
  String get bookmarkRemindersCannotBeMoreThan10YearsAway =>
      'Bookmark reminders cannot be more than 10 years away.';

  @override
  String get preferencesAreNotAJSONObject =>
      'Preferences are not a JSON object.';

  @override
  String unreadablePreferencesWereSetAsideAs(String uriPathSegmentsLast) {
    return 'Unreadable preferences were set aside as $uriPathSegmentsLast.';
  }

  @override
  String siteAppearanceLoadException(
    String failure,
    String url,
    String statusCode,
    String detail,
  ) {
    return 'SiteAppearanceLoadException($failure, $url, $statusCode, $detail)';
  }

  @override
  String get authenticatedAppearanceHasNoUsername =>
      'authenticated appearance has no username';

  @override
  String get stylesheetJSONHasNoNewHref => 'stylesheet JSON has no new_href';

  @override
  String get redirectWithoutALocation => 'redirect without a location';

  @override
  String get authenticatedRedirectCrossedOrigins =>
      'authenticated redirect crossed origins';

  @override
  String get couldNotPersistTheSidebarWidth =>
      'Could not persist the sidebar width.';

  @override
  String get downloadedImageCouldNotBeDecoded =>
      'Downloaded image could not be decoded.';

  @override
  String get tooManyImageRedirects => 'Too many image redirects';

  @override
  String get timedOutFetchingCachedBytes => 'Timed out fetching cached bytes';

  @override
  String get unsupportedEmojiPickerPreferences =>
      'Unsupported emoji picker preferences.';

  @override
  String get invalidEmojiPickerSkinTone => 'Invalid emoji picker skin tone.';

  @override
  String get invalidEmojiPickerHistory => 'Invalid emoji picker history.';

  @override
  String get invalidEmojiPickerContextKey =>
      'Invalid emoji picker context key.';

  @override
  String get invalidEmojiPickerContextHistory =>
      'Invalid emoji picker context history.';

  @override
  String httpResponseTooLargeExceptionBytes(String url, String maxBytes) {
    return 'HttpResponseTooLargeException($url, $maxBytes bytes)';
  }

  @override
  String timedOutReadingResponseFrom(String url) {
    return 'Timed out reading response from $url';
  }

  @override
  String get timedOutBeforeTheResponseBody =>
      'Timed out before the response body';

  @override
  String get expectedAJSONObject => 'Expected a JSON object';

  @override
  String get missingBadge => 'Missing badge';

  @override
  String requestBacklogForAlreadyContainsOperations(
    String origin,
    String maxQueued,
  ) {
    return 'Request backlog for $origin already contains $maxQueued operations.';
  }

  @override
  String get thatForumAddress => 'that forum address';

  @override
  String couldNotConnectTo(String initialHost) {
    return 'Could not connect to $initialHost.';
  }

  @override
  String couldnTRead(String fileName) {
    return 'Couldn\'t read $fileName.';
  }

  @override
  String theSiteReturnedAnIncompleteUploadFor(String fileName) {
    return 'The site returned an incomplete upload for $fileName.';
  }

  @override
  String get couldnTLoadImagePreviews => 'Couldn\'t load image previews.';

  @override
  String couldnTUploadDiscoursecomposerapi(String filename) {
    return 'Couldn\'t upload $filename.';
  }

  @override
  String get connectionSuperseded => 'connection superseded';

  @override
  String get invalidStoredForumBaseURL => 'Invalid stored forum base URL.';

  @override
  String get couldNotPersistTheDiagnosticsPanelWidth =>
      'Could not persist the diagnostics panel width.';

  @override
  String retryAfter(String retryAfter) {
    return ' (retry after $retryAfter)';
  }

  @override
  String get messageBusPollTimedOut => 'Message bus poll timed out';

  @override
  String invalidDraftStorage(String errorMessage) {
    return 'Invalid draft storage: $errorMessage';
  }

  @override
  String get invalidDraftStorageValuesMustBeStrings =>
      'Invalid draft storage: values must be strings';

  @override
  String get invalidDraftStorageBlockersMustBeStrings =>
      'Invalid draft storage: blockers must be strings';

  @override
  String get invalidDraftStorageFormat => 'Invalid draft storage format';

  @override
  String get stable => 'Stable';

  @override
  String get canary => 'Canary';

  @override
  String get couldnTReachTheUpdateServer =>
      'Couldn\'t reach the update server.';

  @override
  String get theUpdateServerAnsweredWithSomethingThisVersionDoesNotUnderstand =>
      'The update server answered with something this version does not understand.';

  @override
  String get theDownloadDidNotMatchItsSignatureAndWasThrownAway =>
      'The download did not match its signature and was thrown away.';

  @override
  String get theUpdateDownloadedButCouldNotBeInstalled =>
      'The update downloaded but could not be installed.';

  @override
  String get thisBuildCannotUpdateItself => 'This build cannot update itself.';

  @override
  String get connectionCancelled => 'Connection cancelled.';

  @override
  String get couldNotOpenTheSignInWindowCheckThatAWeb =>
      'Could not open the sign-in window. Check that a web view is installed.';

  @override
  String get theSiteSReplyCouldNotBeVerifiedPleaseTryAgain =>
      'The site\'s reply could not be verified. Please try again.';

  @override
  String get callbackURLExceedsProtocolLimit =>
      'callback URL exceeds protocol limit';

  @override
  String get unexpectedCallbackURL => 'unexpected callback URL';

  @override
  String get noPayloadInCallback => 'no payload in callback';

  @override
  String get encryptedPayloadMustContainExactlyOneRSABlock =>
      'encrypted payload must contain exactly one RSA block';

  @override
  String get nonceMismatch => 'nonce mismatch';

  @override
  String get noKeyInPayload => 'no key in payload';

  @override
  String get encryptedPayloadExceedsProtocolLimit =>
      'encrypted payload exceeds protocol limit';

  @override
  String get encryptedPayloadExceedsOneRSABlock =>
      'encrypted payload exceeds one RSA block';

  @override
  String formatException(String offsetNull, String message, String offset) {
    String _temp0 = intl.Intl.selectLogic(offsetNull, {
      'true': 'FormatException: $message',
      'other': 'FormatException: $message at $offset',
    });
    return '$_temp0';
  }

  @override
  String isNotADiscourseForumOrIsRunningAVersionToo(String term) {
    return '$term is not a Discourse forum, or is running a version too old to support apps.';
  }

  @override
  String statusCode(String statusCode) {
    return ', statusCode: $statusCode';
  }

  @override
  String get apiKeyRejectedExceptionStatusCode403 =>
      'ApiKeyRejectedException(statusCode: 403)';

  @override
  String get thatWasnTAccepted => 'That wasn\'t accepted.';

  @override
  String tooFastTryAgainInS(String waitInSeconds) {
    return 'Too fast — try again in ${waitInSeconds}s.';
  }

  @override
  String get tooFastTryAgainInAMoment => 'Too fast — try again in a moment.';

  @override
  String get youCanTPostThatHereOrTheConnectionToThis =>
      'You can\'t post that here — or the connection to this site has expired.';

  @override
  String get someoneElseChangedThatFirst => 'Someone else changed that first.';

  @override
  String get couldnTReachTheSite => 'Couldn\'t reach the site.';

  @override
  String writeExceptionStatusCodeRetryAfter(
    String notSent,
    String failure,
    String statusCode,
    String retryAfter,
  ) {
    String _temp0 = intl.Intl.selectLogic(notSent, {
      'true':
          'WriteException($failure, statusCode: $statusCode, retryAfter: $retryAfter, notSent)',
      'other':
          'WriteException($failure, statusCode: $statusCode, retryAfter: $retryAfter)',
    });
    return '$_temp0';
  }

  @override
  String get originRequestGateIsClosed => 'Origin request gate is closed.';

  @override
  String requestsToArePausedForS(String origin, String retryAfterInSeconds) {
    return 'Requests to $origin are paused for ${retryAfterInSeconds}s.';
  }

  @override
  String invalidPrivateStorage(String errorMessage) {
    return 'Invalid private storage: $errorMessage';
  }

  @override
  String get invalidPrivateStorageValuesMustBeStrings =>
      'Invalid private storage: values must be strings';

  @override
  String get invalidPrivateStorageFormat => 'Invalid private storage format';

  @override
  String mediaRequestsToArePausedForS(
    String origin,
    String retryAfterInSeconds,
  ) {
    return 'Media requests to $origin are paused for ${retryAfterInSeconds}s.';
  }

  @override
  String mediaRequestBacklogForAlreadyContainsOperations(
    String origin,
    String maxQueued,
  ) {
    return 'Media request backlog for $origin already contains $maxQueued operations.';
  }

  @override
  String get couldNotSaveTopicView => 'Could not save topic view.';

  @override
  String pixels(String vRound) {
    return '$vRound pixels';
  }

  @override
  String questionOfDquestionnaire(
    String semanticLabel,
    String valueCurrent,
    String valueTotal,
  ) {
    return '$semanticLabel, question $valueCurrent of $valueTotal';
  }

  @override
  String ofRowSSelected(String selectedCount, String totalCount) {
    return '$selectedCount of $totalCount row(s) selected.';
  }

  @override
  String get then => ', then ';

  @override
  String get thenDkbd => 'then';

  @override
  String moreDselect(String first, String itemsLength) {
    return '$first (+$itemsLength more)';
  }

  @override
  String unreadChatbrowsechannelsview(
    String unread,
    num unreadValue2,
    String statusNull,
    String appL10nNo,
    String status,
    String unreadValue6,
  ) {
    String _temp0 = intl.Intl.selectLogic(statusNull, {
      'true': '$appL10nNo unread messages',
      'other': '$appL10nNo unread messages · $status',
    });
    String _temp1 = intl.Intl.selectLogic(statusNull, {
      'true': '$appL10nNo unread message',
      'other': '$appL10nNo unread message · $status',
    });
    String _temp2 = intl.Intl.pluralLogic(
      unreadValue2,
      locale: localeName,
      other: '$_temp0',
      one: '$_temp1',
    );
    String _temp3 = intl.Intl.selectLogic(statusNull, {
      'true': '$unreadValue6 unread messages',
      'other': '$unreadValue6 unread messages · $status',
    });
    String _temp4 = intl.Intl.selectLogic(statusNull, {
      'true': '$unreadValue6 unread message',
      'other': '$unreadValue6 unread message · $status',
    });
    String _temp5 = intl.Intl.pluralLogic(
      unreadValue2,
      locale: localeName,
      other: '$_temp3',
      one: '$_temp4',
    );
    String _temp6 = intl.Intl.selectLogic(unread, {
      'true': '$_temp2',
      'other': '$_temp5',
    });
    return '$_temp6';
  }

  @override
  String menu(String channelTitle) {
    return '$channelTitle menu';
  }

  @override
  String get edited => '(edited)';

  @override
  String get staffChatmessagetile => 'staff';

  @override
  String get bot => 'bot';

  @override
  String from(String name) {
    return ' from $name';
  }

  @override
  String optionsChatchannellistactions(String label) {
    return '$label options';
  }

  @override
  String get messageChatchannelheader => ' message';

  @override
  String get messagesChatchannelheader => ' messages';

  @override
  String get threadChatchannelheader => ' thread';

  @override
  String get threadsChatchannelheader => ' threads';

  @override
  String lastAt(String nowDateTimeNow) {
    return 'last $nowDateTimeNow at ';
  }

  @override
  String messageInChatshellservice(
    String authorAppL10nSomeone,
    String channelLabel,
  ) {
    return '$authorAppL10nSomeone in $channelLabel';
  }

  @override
  String unreadChatplugin(num unreadCount) {
    String _temp0 = intl.Intl.pluralLogic(
      unreadCount,
      locale: localeName,
      other: '$unreadCount unread messages',
      one: '$unreadCount unread message',
    );
    return '$_temp0';
  }

  @override
  String unreadChatinbox(num threadCount) {
    String _temp0 = intl.Intl.pluralLogic(
      threadCount,
      locale: localeName,
      other: '$threadCount unread threads',
      one: '$threadCount unread thread',
    );
    return '$_temp0';
  }

  @override
  String messageNewChatinbox(num channelTrackingMentionCount) {
    String _temp0 = intl.Intl.pluralLogic(
      channelTrackingMentionCount,
      locale: localeName,
      other: '$channelTrackingMentionCount new mentions',
      one: '$channelTrackingMentionCount new mention',
    );
    return '$_temp0';
  }

  @override
  String messageInChatmythreadsview(String channelTitle) {
    return ' in $channelTitle';
  }

  @override
  String get unreadChatmythreadsview => ', unread';

  @override
  String selectedChatchannelview(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count messages selected',
      one: '$count message selected',
    );
    return '$_temp0';
  }

  @override
  String dateLocaldatecomposersheet(String label) {
    return '$label date';
  }

  @override
  String timeLocaldatecomposersheet(String label) {
    return '$label time';
  }

  @override
  String get voiceRoom => 'Voice room';

  @override
  String ms(String eventTotalDurationInMilliseconds) {
    return '$eventTotalDurationInMilliseconds ms';
  }

  @override
  String present(String callSiteName, String callParticipantCount) {
    return '$callSiteName · $callParticipantCount present';
  }

  @override
  String dropped(String stateDroppedRecords) {
    return '$stateDroppedRecords dropped';
  }

  @override
  String groupAssignmentsheetValue(String assignmentAssigneeGroupName) {
    return 'group @$assignmentAssigneeGroupName';
  }

  @override
  String userAssignmentsheet(String assignmentAssigneeUsername) {
    return 'user @$assignmentAssigneeUsername';
  }

  @override
  String statusAssignmentsheetValue(String status) {
    return 'status $status';
  }

  @override
  String noteAssignmentsheet(String note) {
    return 'note $note';
  }

  @override
  String get groupAssignplugin => '· group';

  @override
  String assignedAssignplugin(String who) {
    return 'assigned $who';
  }

  @override
  String unassignedAssignplugin(String who) {
    return 'unassigned $who';
  }

  @override
  String reassigned(String who) {
    return 'reassigned $who';
  }

  @override
  String moreEventcalendar(String numberOfHiddenRows) {
    return '+$numberOfHiddenRows more';
  }

  @override
  String dayOf(
    String differenceFirstDayInDays,
    String differenceFirstDayInDaysValue2,
  ) {
    return 'day $differenceFirstDayInDays of $differenceFirstDayInDaysValue2';
  }

  @override
  String get yYYYMMDDHHMm => 'YYYY-MM-DD HH:mm';

  @override
  String shown(String rowsLength) {
    return '$rowsLength shown';
  }

  @override
  String goingEventcard(String count) {
    return '$count going';
  }

  @override
  String interestedEventcard(String count) {
    return '· $count interested';
  }

  @override
  String interestedEventcardValue(String count) {
    return '$count interested';
  }

  @override
  String cover(String eventTitle) {
    return '$eventTitle cover';
  }

  @override
  String voters(String pollVoters) {
    return '$pollVoters voters';
  }

  @override
  String percent(
    num votes,
    String appL10nMessage1Vote,
    String percentage,
    String votesValue4,
  ) {
    String _temp0 = intl.Intl.pluralLogic(
      votes,
      locale: localeName,
      other: ', $votesValue4 votes, $percentage percent',
      one: ', $appL10nMessage1Vote, $percentage percent',
    );
    return '$_temp0';
  }

  @override
  String votes(String votes) {
    return '$votes votes';
  }

  @override
  String ranked(String optionHtmlLabel, String ranksOptionId) {
    return '$optionHtmlLabel, ranked $ranksOptionId';
  }

  @override
  String or(String namesFirst, String namesLast) {
    return '$namesFirst or $namesLast';
  }

  @override
  String orPollcard(String namesLengthJoin, String namesLast) {
    return '$namesLengthJoin, or $namesLast';
  }

  @override
  String percentAppsettingspage(String percentage) {
    return '$percentage percent';
  }

  @override
  String get orAppsettingspage => 'or';

  @override
  String actionsComposerblocksurface(String blockLabel) {
    return '$blockLabel actions';
  }

  @override
  String item(String itemLabel) {
    return '$itemLabel item';
  }

  @override
  String unreadNotificationlist(String line) {
    return '$line, unread';
  }

  @override
  String moreTopiclistview(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count more tags',
      one: '$count more tag',
    );
    return '$_temp0';
  }

  @override
  String unreadTopiclistindicators(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count unread posts',
      one: '$count unread post',
    );
    return '$_temp0';
  }

  @override
  String get sMTPServer => 'SMTP server';

  @override
  String get sSLMode => 'SSL mode';

  @override
  String groupsGroupspage(String humanizeType) {
    return '$humanizeType groups';
  }

  @override
  String get selectedTopiclistnavigation => ', selected';

  @override
  String remaining(String postFlagTypeMaximumMessageLengthLength) {
    return '$postFlagTypeMaximumMessageLengthLength remaining';
  }

  @override
  String colorComposerselectioncolors(
    String background,
    String appL10nBackground,
    String name,
    String appL10nText,
  ) {
    String _temp0 = intl.Intl.selectLogic(background, {
      'true': '$appL10nBackground color: $name',
      'other': '$appL10nText color: $name',
    });
    return '$_temp0';
  }

  @override
  String ofUses(String inviteRedemptionCount, String inviteMaxRedemptions) {
    return '$inviteRedemptionCount of $inviteMaxRedemptions uses';
  }

  @override
  String get postOnX => 'Post on X';

  @override
  String get quotedPost => 'Quoted post';

  @override
  String embed(String uriHost) {
    return '$uriHost embed';
  }

  @override
  String get pdfPngJpg => 'pdf, png, jpg';

  @override
  String untilUserstatus(
    String statusDescription,
    String contextFormatMediumDateUntil,
    String clockTimeLabelContextUntil,
  ) {
    return '$statusDescription — until $contextFormatMediumDateUntil $clockTimeLabelContextUntil';
  }

  @override
  String recipientsComposerrecipientsValue(String recipientsLength) {
    return '$recipientsLength recipients';
  }

  @override
  String earnedUsersummary(num badgeCount, String badgeName) {
    String _temp0 = intl.Intl.pluralLogic(
      badgeCount,
      locale: localeName,
      other: '$badgeName, earned $badgeCount times',
      one: '$badgeName, earned $badgeCount time',
    );
    return '$_temp0';
  }

  @override
  String tagsTopictagselectorValue(String selectedLength) {
    return '$selectedLength tags';
  }

  @override
  String later(num daysSince) {
    String _temp0 = intl.Intl.pluralLogic(
      daysSince,
      locale: localeName,
      other: '$daysSince days later',
      one: '$daysSince day later',
    );
    return '$_temp0';
  }

  @override
  String laterTimegap(num months) {
    String _temp0 = intl.Intl.pluralLogic(
      months,
      locale: localeName,
      other: '$months months later',
      one: '$months month later',
    );
    return '$_temp0';
  }

  @override
  String laterTimegapValue(num years) {
    String _temp0 = intl.Intl.pluralLogic(
      years,
      locale: localeName,
      other: '$years years later',
      one: '$years year later',
    );
    return '$_temp0';
  }

  @override
  String copyForumthemenewdialog(String baseName) {
    return '$baseName copy';
  }

  @override
  String otherTopiccreatebutton(String otherDraftCount, String noun) {
    return '+$otherDraftCount other $noun';
  }

  @override
  String at(
    String localizationsFormatMediumDateWall,
    String clockTimeLabelContextWall,
  ) {
    return '$localizationsFormatMediumDateWall at $clockTimeLabelContextWall';
  }

  @override
  String navigationInstancesidebar(
    String showShortcuts,
    String appL10nShortcutsInstancesidebar,
    String labelAppL10nForum,
  ) {
    String _temp0 = intl.Intl.selectLogic(showShortcuts, {
      'true': '$appL10nShortcutsInstancesidebar navigation',
      'other': '$labelAppL10nForum navigation',
    });
    return '$_temp0';
  }

  @override
  String unreadInstancesidebar(num sectionUnreadCount) {
    String _temp0 = intl.Intl.pluralLogic(
      sectionUnreadCount,
      locale: localeName,
      other: ', $sectionUnreadCount unread messages',
      one: ', $sectionUnreadCount unread message',
    );
    return '$_temp0';
  }

  @override
  String get oK => 'OK';

  @override
  String get alpha => 'alpha';

  @override
  String atNewtabpage(String label, String wallUse24HourClockUse24HourClock) {
    return '$label at $wallUse24HourClockUse24HourClock';
  }

  @override
  String get tWOPANELS => 'TWO PANELS';

  @override
  String theInbox(String group) {
    return 'the $group inbox';
  }

  @override
  String get and => ' and ';

  @override
  String one(String kind) {
    return 'one $kind';
  }

  @override
  String likesPostlikes(String count) {
    return '$count likes';
  }

  @override
  String likesPostlikesValue(String postLikeCount) {
    return '$postLikeCount likes';
  }

  @override
  String andOthers(String hidden) {
    return 'and $hidden others';
  }

  @override
  String messageOf(String total) {
    return 'of $total';
  }

  @override
  String get homeDefault => 'Home default';

  @override
  String edits(String count) {
    return '$count edits';
  }

  @override
  String ago(String age) {
    return '$age ago';
  }

  @override
  String selectedTopicview(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count posts selected',
      one: '$count post selected',
    );
    return '$_temp0';
  }

  @override
  String get deletedTopicview => 'deleted';

  @override
  String get wikiTopicview => 'wiki';

  @override
  String get locked => 'locked';

  @override
  String get hiddenTopicview => 'hidden';

  @override
  String get moderatorTopicview => 'moderator';

  @override
  String moreTopicview(num remaining) {
    String _temp0 = intl.Intl.pluralLogic(
      remaining,
      locale: localeName,
      other: '$remaining more links',
      one: '$remaining more link',
    );
    return '$_temp0';
  }

  @override
  String get view => 'view';

  @override
  String get viewsTopicview => 'views';

  @override
  String get replyTopicview => 'reply';

  @override
  String get repliesTopicview => 'replies';

  @override
  String get likeTopicview => 'like';

  @override
  String get likesTopicview => 'likes';

  @override
  String get linkTopicview => 'link';

  @override
  String get links => 'links';

  @override
  String get userTopicview => 'user';

  @override
  String get usersTopicview => 'users';

  @override
  String min(String minutes) {
    return '$minutes min';
  }

  @override
  String get readTopicview => 'read';

  @override
  String invitedSmallaction(String subject) {
    return 'invited $subject';
  }

  @override
  String removed(String subject) {
    return 'removed $subject';
  }

  @override
  String mB(String bytesMbToStringAsFixed) {
    return '$bytesMbToStringAsFixed MB';
  }

  @override
  String kB(String bytesRound) {
    return '$bytesRound KB';
  }

  @override
  String reactionsReactionpresentation(String count) {
    return '$count reactions';
  }

  @override
  String message1ReactionReactionpresentation(String reaction) {
    return '1 $reaction reaction';
  }

  @override
  String reactionsReactionpresentationValue(String count, String reaction) {
    return '$count $reaction reactions';
  }

  @override
  String topicsMaincontent(String topicFeedMenuLabelMode) {
    return '$topicFeedMenuLabelMode topics';
  }

  @override
  String groupsMaincontent(String count) {
    return '$count groups';
  }

  @override
  String valueGlobalsearchfilterpicker(String filterLabel) {
    return '$filterLabel value';
  }

  @override
  String condition(String filterLabel) {
    return '$filterLabel condition';
  }

  @override
  String loaded(String categoryPluralCategories) {
    return '$categoryPluralCategories loaded';
  }

  @override
  String ofCategories(String choicesLength, String total) {
    return '$choicesLength of $total categories';
  }

  @override
  String found(String categoryPluralCategories) {
    return '$categoryPluralCategories found';
  }

  @override
  String selectedGlobalsearchcategoryeditor(String selectedLength) {
    return '$selectedLength selected';
  }

  @override
  String msDiagnosticspanel(String millisecondsRound) {
    return '$millisecondsRound ms';
  }

  @override
  String get suspended => 'suspended';

  @override
  String unreadUsermenu(String sectionLabel, String sectionBadge) {
    return '$sectionLabel, $sectionBadge unread';
  }

  @override
  String unreadUsermenuValue(String count) {
    return '$count unread';
  }

  @override
  String awarded(String numberCount) {
    return '$numberCount awarded';
  }

  @override
  String liked(String postsCount) {
    return 'liked $postsCount';
  }

  @override
  String linked(String postsCount) {
    return 'linked $postsCount';
  }

  @override
  String created(String title) {
    return 'created $title';
  }

  @override
  String moved(String title) {
    return 'moved $title';
  }

  @override
  String messageFor(String countAppL10nMembershipRequest, String group) {
    return '$countAppL10nMembershipRequest for $group';
  }

  @override
  String get greyAmber => 'Grey Amber';

  @override
  String get shadesOfBlue => 'Shades of Blue';

  @override
  String get latte => 'Latte';

  @override
  String get summer => 'Summer';

  @override
  String get darkRose => 'Dark Rose';

  @override
  String get dracula => 'Dracula';

  @override
  String get solarized => 'Solarized';

  @override
  String get clover => 'Clover';

  @override
  String get blank => 'Blank';

  @override
  String get foundations => 'Foundations';

  @override
  String offset(String errorMessage, String offset) {
    return '$errorMessage (offset $offset)';
  }

  @override
  String get noCapture => 'no capture';

  @override
  String get inProgress => 'in progress';

  @override
  String uIBuildLayoutPaint(String mapMeasuredBuildUs) {
    return 'UI build/layout/paint: $mapMeasuredBuildUs';
  }

  @override
  String cPUSamples(String cpuSampleCount, String cpuFunctionsLineCpuLimit) {
    return '    CPU ($cpuSampleCount samples): $cpuFunctionsLineCpuLimit';
  }

  @override
  String msTopicscrollreport(String phaseName, String msPhaseDurationUs) {
    return '$phaseName $msPhaseDurationUs ms';
  }

  @override
  String samplesP50MsP95MsP99MsMaxMs(
    String statsCount,
    String msStatsP50,
    String msStatsP95,
    String msStatsP99,
    String msStatsMax,
  ) {
    return '$statsCount samples | p50 $msStatsP50 ms | p95 $msStatsP95 ms | p99 $msStatsP99 ms | max $msStatsMax ms';
  }

  @override
  String messageAlerttables(
    String collapsed,
    String appL10nExpand,
    String groupStatusLabel,
    String groupHeading,
    String groupAlertsLength,
    String appL10nCollapse,
  ) {
    String _temp0 = intl.Intl.selectLogic(collapsed, {
      'true':
          '$appL10nExpand $groupStatusLabel: $groupHeading ($groupAlertsLength)',
      'other':
          '$appL10nCollapse $groupStatusLabel: $groupHeading ($groupAlertsLength)',
    });
    return '$_temp0';
  }

  @override
  String messageChatbrowsechannelsview(
    String following,
    String appL10nLeave,
    String channelTitle,
    String appL10nJoin,
  ) {
    String _temp0 = intl.Intl.selectLogic(following, {
      'true': '$appL10nLeave $channelTitle',
      'other': '$appL10nJoin $channelTitle',
    });
    return '$_temp0';
  }

  @override
  String messageChatmessagetile(num participants) {
    String _temp0 = intl.Intl.pluralLogic(
      participants,
      locale: localeName,
      other: ' $participants participants.',
      one: ' $participants participant.',
    );
    return '$_temp0';
  }

  @override
  String messageChatinbox(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count messages',
      one: '$count message',
    );
    return '$_temp0';
  }

  @override
  String messageAssignmentsheet(
    String assigneeIsGroup,
    String assigneeDisplayName,
    String assigneeIdentifier,
  ) {
    String _temp0 = intl.Intl.selectLogic(assigneeIsGroup, {
      'true': '$assigneeDisplayName, group @$assigneeIdentifier',
      'other': '$assigneeDisplayName, user @$assigneeIdentifier',
    });
    return '$_temp0';
  }

  @override
  String messageGithub(num additions, num deletions) {
    String _temp0 = intl.Intl.pluralLogic(
      deletions,
      locale: localeName,
      other: '$additions additions, $deletions deletions',
      one: '$additions additions, $deletions deletion',
    );
    String _temp1 = intl.Intl.pluralLogic(
      deletions,
      locale: localeName,
      other: '$additions addition, $deletions deletions',
      one: '$additions addition, $deletions deletion',
    );
    String _temp2 = intl.Intl.pluralLogic(
      additions,
      locale: localeName,
      other: '$_temp0',
      one: '$_temp1',
    );
    return '$_temp2';
  }

  @override
  String messageEventcalendar(
    String direction,
    String schedule,
    String appL10nPrevious,
    String viewName,
    String appL10nNext,
  ) {
    String _temp0 = intl.Intl.selectLogic(schedule, {
      'true': '$appL10nPrevious month',
      'other': '$appL10nPrevious $viewName',
    });
    String _temp1 = intl.Intl.selectLogic(schedule, {
      'true': '$appL10nNext month',
      'other': '$appL10nNext $viewName',
    });
    String _temp2 = intl.Intl.selectLogic(direction, {
      'true': '$_temp0',
      'other': '$_temp1',
    });
    return '$_temp2';
  }

  @override
  String messageEventcalendarValue(
    String timeline,
    String timeLabelEvent,
    String timeEventLocalStart,
  ) {
    String _temp0 = intl.Intl.selectLogic(timeline, {
      'true': '$timeLabelEvent ',
      'other': '$timeEventLocalStart ',
    });
    return '$_temp0';
  }

  @override
  String messageEventtopictitle(
    String allDay,
    String dateFormatStart,
    String dateFormatEnd,
    String appL10nAllDay,
    String days,
  ) {
    String _temp0 = intl.Intl.selectLogic(allDay, {
      'true': '$dateFormatStart – $dateFormatEnd · $appL10nAllDay',
      'other': '$dateFormatStart – $dateFormatEnd · $days days',
    });
    return '$_temp0';
  }

  @override
  String messageEventtopictitleValue(
    String allDay,
    String dateFormatStart,
    String appL10nAllDay,
    String timeStart,
  ) {
    String _temp0 = intl.Intl.selectLogic(allDay, {
      'true': '$dateFormatStart · $appL10nAllDay',
      'other': '$dateFormatStart · $timeStart',
    });
    return '$_temp0';
  }

  @override
  String messageEventtime(
    String endNull,
    String zoneNull,
    String dateFormatStart,
    String timeStart,
    String zone,
    String sameDay,
    String timeEnd,
    String dateFormatEnd,
  ) {
    String _temp0 = intl.Intl.selectLogic(zoneNull, {
      'true': '$dateFormatStart, $timeStart',
      'other': '$dateFormatStart, $timeStart ($zone)',
    });
    String _temp1 = intl.Intl.selectLogic(zoneNull, {
      'true': '$dateFormatStart, $timeStart → $timeEnd',
      'other': '$dateFormatStart, $timeStart → $timeEnd ($zone)',
    });
    String _temp2 = intl.Intl.selectLogic(zoneNull, {
      'true': '$dateFormatStart, $timeStart → $dateFormatEnd, $timeEnd',
      'other':
          '$dateFormatStart, $timeStart → $dateFormatEnd, $timeEnd ($zone)',
    });
    String _temp3 = intl.Intl.selectLogic(sameDay, {
      'true': '$_temp1',
      'other': '$_temp2',
    });
    String _temp4 = intl.Intl.selectLogic(endNull, {
      'true': '$_temp0',
      'other': '$_temp3',
    });
    return '$_temp4';
  }

  @override
  String messagePollcard(
    num votes,
    String appL10nMessage1Vote,
    String percentage,
    String votesValue4,
  ) {
    String _temp0 = intl.Intl.pluralLogic(
      votes,
      locale: localeName,
      other: '$votesValue4 votes, $percentage%',
      one: '$appL10nMessage1Vote, $percentage%',
    );
    return '$_temp0';
  }

  @override
  String messageTopicmovepostsValue(
    String message,
    String appL10nMessageTopicmoveposts,
    String destinationId,
    String appL10nTopic,
  ) {
    String _temp0 = intl.Intl.selectLogic(message, {
      'true': '$appL10nMessageTopicmoveposts #$destinationId',
      'other': '$appL10nTopic #$destinationId',
    });
    return '$_temp0';
  }

  @override
  String messageGrouppage(num groupUserCount) {
    String _temp0 = intl.Intl.pluralLogic(
      groupUserCount,
      locale: localeName,
      other: '$groupUserCount members',
      one: '$groupUserCount member',
    );
    return '$_temp0';
  }

  @override
  String messageGroupspage(num dataTotalRows) {
    String _temp0 = intl.Intl.pluralLogic(
      dataTotalRows,
      locale: localeName,
      other: '$dataTotalRows groups',
      one: '$dataTotalRows group',
    );
    return '$_temp0';
  }

  @override
  String messageComposeruploadattachment(
    String retrying,
    String appL10nRetrying,
    String uploadProgressRound,
    String appL10nUploading,
  ) {
    String _temp0 = intl.Intl.selectLogic(retrying, {
      'true': '$appL10nRetrying · $uploadProgressRound%',
      'other': '$appL10nUploading · $uploadProgressRound%',
    });
    return '$_temp0';
  }

  @override
  String messageInvitelist(
    String redeemed,
    String appL10nJoined,
    String contextFormatMediumDateDate,
    String expired,
    String appL10nExpired,
    String appL10nExpires,
  ) {
    String _temp0 = intl.Intl.selectLogic(expired, {
      'true': '$appL10nExpired $contextFormatMediumDateDate',
      'other': '$appL10nExpires $contextFormatMediumDateDate',
    });
    String _temp1 = intl.Intl.selectLogic(redeemed, {
      'true': '$appL10nJoined $contextFormatMediumDateDate',
      'other': '$_temp0',
    });
    return '$_temp1';
  }

  @override
  String messageForumtabsbar(
    String badgeUrgent,
    String title,
    String appL10nUrgentUnreadActivity,
    String appL10nUnreadActivity,
  ) {
    String _temp0 = intl.Intl.selectLogic(badgeUrgent, {
      'true': '$title, $appL10nUrgentUnreadActivity',
      'other': '$title, $appL10nUnreadActivity',
    });
    return '$_temp0';
  }

  @override
  String messageForumtabsbarValue(
    num badgeCount,
    String title,
    String appL10nUnreadItem,
    String appL10nUnreadItems,
  ) {
    String _temp0 = intl.Intl.pluralLogic(
      badgeCount,
      locale: localeName,
      other: '$title, $badgeCount $appL10nUnreadItems',
      one: '$title, $badgeCount $appL10nUnreadItem',
    );
    return '$_temp0';
  }

  @override
  String messageComposerimagegallery(num imageCount) {
    String _temp0 = intl.Intl.pluralLogic(
      imageCount,
      locale: localeName,
      other: '$imageCount images',
      one: '$imageCount image',
    );
    return '$_temp0';
  }

  @override
  String messageInstancesidebar(
    String collapsed,
    String appL10nExpand,
    String sectionTitle,
    String unreadDescription,
    String appL10nCollapse,
  ) {
    String _temp0 = intl.Intl.selectLogic(collapsed, {
      'true': '$appL10nExpand $sectionTitle$unreadDescription',
      'other': '$appL10nCollapse $sectionTitle$unreadDescription',
    });
    return '$_temp0';
  }

  @override
  String messageInstancesidebarValue(
    num count,
    String appL10nUnreadItem,
    String appL10nUnreadItems,
  ) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count $appL10nUnreadItems',
      one: '$count $appL10nUnreadItem',
    );
    return '$_temp0';
  }

  @override
  String messageTopiccategoryselector(
    String parentNull,
    String appL10nCategory,
    String label,
    String appL10nSubcategoryTopiccategoryselector,
  ) {
    String _temp0 = intl.Intl.selectLogic(parentNull, {
      'true': '$appL10nCategory: $label',
      'other': '$appL10nSubcategoryTopiccategoryselector: $label',
    });
    return '$_temp0';
  }

  @override
  String messageGlobalsearchfilterpicker(
    String saved,
    String appL10nSavedTags,
    String choicesLength,
    String queryIsEmpty,
    String appL10nAvailableTags,
    String appL10nMatchingTags,
  ) {
    String _temp0 = intl.Intl.selectLogic(queryIsEmpty, {
      'true': '$appL10nAvailableTags · $choicesLength',
      'other': '$appL10nMatchingTags · $choicesLength',
    });
    String _temp1 = intl.Intl.selectLogic(saved, {
      'true': '$appL10nSavedTags · $choicesLength',
      'other': '$_temp0',
    });
    return '$_temp1';
  }

  @override
  String messageGlobalsearchfilterpickerValue(
    String saved,
    String appL10nNoSavedTagsMatch,
    String query,
    String appL10nNoTagsMatch,
  ) {
    String _temp0 = intl.Intl.selectLogic(saved, {
      'true': '$appL10nNoSavedTagsMatch “$query”',
      'other': '$appL10nNoTagsMatch “$query”',
    });
    return '$_temp0';
  }

  @override
  String messageBadgespage(
    num catalogTotal,
    String catalogHasPersonalState,
    String numberCatalogTotal,
    String numberCatalogEarned,
  ) {
    String _temp0 = intl.Intl.selectLogic(catalogHasPersonalState, {
      'true': '$numberCatalogTotal badges · $numberCatalogEarned earned',
      'other': '$numberCatalogTotal badges',
    });
    String _temp1 = intl.Intl.selectLogic(catalogHasPersonalState, {
      'true': '$numberCatalogTotal badge · $numberCatalogEarned earned',
      'other': '$numberCatalogTotal badge',
    });
    String _temp2 = intl.Intl.pluralLogic(
      catalogTotal,
      locale: localeName,
      other: '$_temp0',
      one: '$_temp1',
    );
    return '$_temp2';
  }

  @override
  String countBadge(num count, String number) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$number badges',
      one: '$number badge',
    );
    return '$_temp0';
  }

  @override
  String nounBadge(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'badges',
      one: 'badge',
    );
    return '$_temp0';
  }

  @override
  String countReply(num count, String number) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$number replies',
      one: '$number reply',
    );
    return '$_temp0';
  }

  @override
  String nounReply(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'replies',
      one: 'reply',
    );
    return '$_temp0';
  }

  @override
  String countPerson(num count, String number) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$number people',
      one: '$number person',
    );
    return '$_temp0';
  }

  @override
  String nounPerson(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'people',
      one: 'person',
    );
    return '$_temp0';
  }

  @override
  String countClick(num count, String number) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$number clicks',
      one: '$number click',
    );
    return '$_temp0';
  }

  @override
  String nounClick(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'clicks',
      one: 'click',
    );
    return '$_temp0';
  }

  @override
  String countLike(num count, String number) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$number likes',
      one: '$number like',
    );
    return '$_temp0';
  }

  @override
  String nounLike(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'likes',
      one: 'like',
    );
    return '$_temp0';
  }

  @override
  String countMember(num count, String number) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$number members',
      one: '$number member',
    );
    return '$_temp0';
  }

  @override
  String nounMember(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'members',
      one: 'member',
    );
    return '$_temp0';
  }

  @override
  String countTopic(num count, String number) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$number topics',
      one: '$number topic',
    );
    return '$_temp0';
  }

  @override
  String nounTopic(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'topics',
      one: 'topic',
    );
    return '$_temp0';
  }

  @override
  String countPost(num count, String number) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$number posts',
      one: '$number post',
    );
    return '$_temp0';
  }

  @override
  String nounPost(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'posts',
      one: 'post',
    );
    return '$_temp0';
  }

  @override
  String countView(num count, String number) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$number views',
      one: '$number view',
    );
    return '$_temp0';
  }

  @override
  String nounView(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'views',
      one: 'view',
    );
    return '$_temp0';
  }

  @override
  String countMessage(num count, String number) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$number messages',
      one: '$number message',
    );
    return '$_temp0';
  }

  @override
  String nounMessage(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'messages',
      one: 'message',
    );
    return '$_temp0';
  }

  @override
  String countReaction(num count, String number) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$number reactions',
      one: '$number reaction',
    );
    return '$_temp0';
  }

  @override
  String nounReaction(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'reactions',
      one: 'reaction',
    );
    return '$_temp0';
  }

  @override
  String countCategory(num count, String number) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$number categories',
      one: '$number category',
    );
    return '$_temp0';
  }

  @override
  String nounCategory(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'categories',
      one: 'category',
    );
    return '$_temp0';
  }

  @override
  String countEntry(num count, String number) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$number entries',
      one: '$number entry',
    );
    return '$_temp0';
  }

  @override
  String nounEntry(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'entries',
      one: 'entry',
    );
    return '$_temp0';
  }

  @override
  String countDay(num count, String number) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$number days',
      one: '$number day',
    );
    return '$_temp0';
  }

  @override
  String nounDay(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'days',
      one: 'day',
    );
    return '$_temp0';
  }

  @override
  String countTag(num count, String number) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$number tags',
      one: '$number tag',
    );
    return '$_temp0';
  }

  @override
  String nounTag(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'tags',
      one: 'tag',
    );
    return '$_temp0';
  }

  @override
  String countSecond(num count, String number) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$number seconds',
      one: '$number second',
    );
    return '$_temp0';
  }

  @override
  String nounSecond(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'seconds',
      one: 'second',
    );
    return '$_temp0';
  }

  @override
  String countRepost(num count, String number) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$number reposts',
      one: '$number repost',
    );
    return '$_temp0';
  }

  @override
  String nounRepost(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'reposts',
      one: 'repost',
    );
    return '$_temp0';
  }

  @override
  String countUnreadNotification(num count, String number) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$number unread notifications',
      one: '$number unread notification',
    );
    return '$_temp0';
  }

  @override
  String nounUnreadNotification(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'unread notifications',
      one: 'unread notification',
    );
    return '$_temp0';
  }

  @override
  String countMembershipRequest(num count, String number) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$number membership requests',
      one: '$number membership request',
    );
    return '$_temp0';
  }

  @override
  String nounMembershipRequest(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'membership requests',
      one: 'membership request',
    );
    return '$_temp0';
  }

  @override
  String countThread(num count, String number) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$number threads',
      one: '$number thread',
    );
    return '$_temp0';
  }

  @override
  String nounThread(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'threads',
      one: 'thread',
    );
    return '$_temp0';
  }

  @override
  String countLink(num count, String number) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$number links',
      one: '$number link',
    );
    return '$_temp0';
  }

  @override
  String nounLink(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'links',
      one: 'link',
    );
    return '$_temp0';
  }

  @override
  String countUser(num count, String number) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$number users',
      one: '$number user',
    );
    return '$_temp0';
  }

  @override
  String nounUser(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'users',
      one: 'user',
    );
    return '$_temp0';
  }

  @override
  String countImage(num count, String number) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$number images',
      one: '$number image',
    );
    return '$_temp0';
  }

  @override
  String nounImage(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'images',
      one: 'image',
    );
    return '$_temp0';
  }

  @override
  String countDraft(num count, String number) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$number drafts',
      one: '$number draft',
    );
    return '$_temp0';
  }

  @override
  String nounDraft(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'drafts',
      one: 'draft',
    );
    return '$_temp0';
  }

  @override
  String countRecipient(num count, String number) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$number recipients',
      one: '$number recipient',
    );
    return '$_temp0';
  }

  @override
  String nounRecipient(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'recipients',
      one: 'recipient',
    );
    return '$_temp0';
  }

  @override
  String countVote(num count, String number) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$number votes',
      one: '$number vote',
    );
    return '$_temp0';
  }

  @override
  String nounVote(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'votes',
      one: 'vote',
    );
    return '$_temp0';
  }

  @override
  String countVoter(num count, String number) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$number voters',
      one: '$number voter',
    );
    return '$_temp0';
  }

  @override
  String nounVoter(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'voters',
      one: 'voter',
    );
    return '$_temp0';
  }

  @override
  String countGroup(num count, String number) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$number groups',
      one: '$number group',
    );
    return '$_temp0';
  }

  @override
  String nounGroup(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'groups',
      one: 'group',
    );
    return '$_temp0';
  }

  @override
  String countMinute(num count, String number) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$number minutes',
      one: '$number minute',
    );
    return '$_temp0';
  }

  @override
  String nounMinute(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'minutes',
      one: 'minute',
    );
    return '$_temp0';
  }

  @override
  String countHour(num count, String number) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$number hours',
      one: '$number hour',
    );
    return '$_temp0';
  }

  @override
  String nounHour(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'hours',
      one: 'hour',
    );
    return '$_temp0';
  }

  @override
  String countMonth(num count, String number) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$number months',
      one: '$number month',
    );
    return '$_temp0';
  }

  @override
  String nounMonth(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'months',
      one: 'month',
    );
    return '$_temp0';
  }

  @override
  String countYear(num count, String number) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$number years',
      one: '$number year',
    );
    return '$_temp0';
  }

  @override
  String nounYear(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'years',
      one: 'year',
    );
    return '$_temp0';
  }

  @override
  String namedReactions(num count, String reaction) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count $reaction reactions',
      one: '1 $reaction reaction',
    );
    return '$_temp0';
  }

  @override
  String relativeYears(int count) {
    return '${count}y';
  }

  @override
  String relativeMonths(int count) {
    return '${count}mo';
  }

  @override
  String relativeDays(int count) {
    return '${count}d';
  }

  @override
  String relativeHours(int count) {
    return '${count}h';
  }

  @override
  String relativeMinutes(int count) {
    return '${count}m';
  }

  @override
  String relativeDurationMonths(int count) {
    return '${count}mon';
  }

  @override
  String get relativeNow => 'now';

  @override
  String get durationLessThanMinuteShort => '<1m';

  @override
  String get durationLessThanMinute => 'less than 1 min';

  @override
  String get durationOneHourShort => '1h';

  @override
  String get durationOneHour => 'about 1 hour';

  @override
  String get durationOneDayShort => '1d';

  @override
  String get durationOneDay => '1 day';

  @override
  String durationMinutes(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count mins',
      one: '$count min',
    );
    return '$_temp0';
  }

  @override
  String durationHours(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'about $count hours',
      one: 'about $count hour',
    );
    return '$_temp0';
  }

  @override
  String durationDays(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count days',
      one: '$count day',
    );
    return '$_temp0';
  }

  @override
  String durationMonths(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count months',
      one: '$count month',
    );
    return '$_temp0';
  }

  @override
  String durationAboutYears(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'about $count years',
      one: 'about $count year',
    );
    return '$_temp0';
  }

  @override
  String durationOverYears(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'over $count years',
      one: 'over $count year',
    );
    return '$_temp0';
  }

  @override
  String durationAlmostYears(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'almost $count years',
      one: 'almost $count year',
    );
    return '$_temp0';
  }

  @override
  String durationOverYearsShort(int count) {
    return '> ${count}y';
  }

  @override
  String get calendarDatePattern => 'd MMMM y';

  @override
  String compactThousands(String number) {
    return '${number}k';
  }

  @override
  String compactMillions(String number) {
    return '${number}M';
  }

  @override
  String get inputTimeWithSeconds => 'HH:mm:ss';

  @override
  String get inputTime => 'HH:mm';

  @override
  String get recurrenceExample => '1.weeks';

  @override
  String get dateFormatExample => 'LLL';

  @override
  String get voiceRoomNameExample => 'e.g. Community lounge';

  @override
  String get usernameLowercase => 'username';

  @override
  String get inputIsoDate => 'YYYY-MM-DD';

  @override
  String get urlLabel => 'URL';

  @override
  String get siteAddressExample => 'meta.discourse.org';

  @override
  String get searchOperatorIs => 'is';

  @override
  String get searchOperatorExcludes => 'excludes';

  @override
  String get chatLowercase => 'chat';

  @override
  String calendarDayEventCount(String date, String isToday, num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$date, Today, $count events',
      one: '$date, Today, 1 event',
    );
    String _temp1 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$date, $count events',
      one: '$date, 1 event',
    );
    String _temp2 = intl.Intl.selectLogic(isToday, {
      'true': '$_temp0',
      'other': '$_temp1',
    });
    return '$_temp2';
  }

  @override
  String calendarDayEntryCount(String date, num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$date, $count entries',
      one: '$date, 1 entry',
    );
    return '$_temp0';
  }

  @override
  String get searchThreadingCannotBeChanged =>
      'Threading cannot be changed for this channel.';

  @override
  String get about => 'About';

  @override
  String get aboutReplayMark => 'Replay Discourse logo animation';

  @override
  String get aboutDiscourseMeta => 'Discourse Meta';

  @override
  String get aboutDocumentation => 'Documentation';

  @override
  String get aboutLinkOpenFailed =>
      'Could not open the link. Please try again.';

  @override
  String aboutExternalLinkLabel(String label) {
    return '$label, opens in browser';
  }

  @override
  String get bookmarkReminders => 'Reminders';

  @override
  String get filterBookmarkType => 'Filter bookmark type';

  @override
  String get allBookmarkTypes => 'All types';

  @override
  String get bookmarkReminderExpired => 'Reminder expired';

  @override
  String get bookmarkChangedRefreshMenu =>
      'Bookmark changed. Open the menu again to refresh it.';

  @override
  String get removeBookmark => 'Remove bookmark';

  @override
  String get categoryDirectoryScope => 'Category scope';

  @override
  String get categoriesWithTopics => 'With topics';

  @override
  String get noUnreadCategories => 'No categories with unread topics';

  @override
  String get noCategoriesWithTopics => 'No categories with topics';

  @override
  String categoryUnreadTopics(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count unread topics',
      one: '1 unread topic',
    );
    return '$_temp0';
  }

  @override
  String get interfaceFontUse => 'Interface';

  @override
  String get readingFontUse => 'Reading';

  @override
  String fontForInterface(String font) {
    return '$font for interface';
  }

  @override
  String fontForReading(String font) {
    return '$font for reading';
  }

  @override
  String get fontAssignmentsDescription =>
      'Choose fonts for the interface and reading in every forum. System default reading follows the interface font.';

  @override
  String get confirmThemeEverywhere =>
      'Every forum and Home will use these light and dark theme selections, replacing their individual selections. Saved themes will stay in your library.';

  @override
  String get confirmUseEverywhere => 'Use everywhere';

  @override
  String startPageForumCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count forums',
      one: '1 forum',
    );
    return '$_temp0';
  }

  @override
  String get composerIndent => 'Indent';

  @override
  String get composerOutdent => 'Outdent';
}
